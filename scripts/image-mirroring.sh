#!/usr/bin/env bash
set -euo pipefail

ORG="tgmarius"
PREFIX="mirror"

# Safety defaults
PUSH="${PUSH:-0}"                 # Only PUSH=1 will actually write to GHCR
CONCURRENCY="${CONCURRENCY:-3}"   # Tune this (2-4 is usually safe)
MAX_RETRIES="${MAX_RETRIES:-6}"
BASE_DELAY="${BASE_DELAY:-2}"     # seconds

echo "Starting GHCR mirroring"
echo "Mode: $([ "$PUSH" = "1" ] && echo "PUSH" || echo "DRY-RUN")"
echo "Concurrency: ${CONCURRENCY}"
echo "----"

image_exists() {
  local ref="$1"
  docker buildx imagetools inspect "$ref" >/dev/null 2>&1
}

# Retry helper with exponential backoff + jitter
retry() {
  local attempt=0
  local cmd_desc="$1"
  shift

  while true; do
    set +e
    output="$("$@" 2>&1)"
    rc=$?
    set -e

    if [ $rc -eq 0 ]; then
      return 0
    fi

    # Retry only on likely transient/rate-limit issues
    if echo "$output" | grep -Ei '(429|too many requests|toomanyrequests|rate limit|timeout|temporarily unavailable|connection reset|TLS handshake|EOF)' >/dev/null; then
      attempt=$((attempt + 1))
      if [ "$attempt" -ge "$MAX_RETRIES" ]; then
        echo "❌ Failed after ${MAX_RETRIES} retries: ${cmd_desc}"
        echo "$output"
        return $rc
      fi

      # Exponential backoff with small jitter
      sleep_for=$(( BASE_DELAY * (2 ** (attempt - 1)) ))
      jitter=$(( RANDOM % 3 ))
      sleep_for=$(( sleep_for + jitter ))

      echo "⚠️  Transient error for: ${cmd_desc}"
      echo "   Retry ${attempt}/${MAX_RETRIES} in ${sleep_for}s"
      echo "   (last error: $(echo "$output" | tail -n 2))"
      sleep "$sleep_for"
      continue
    fi

    # Non-retryable error
    echo "❌ Non-retryable failure: ${cmd_desc}"
    echo "$output"
    return $rc
  done
}

process_one() {
  local RAW_LINE="$1"

  # Strip comments + whitespace
  local IMAGE
  IMAGE="$(echo "$RAW_LINE" | sed 's/#.*//g' | tr -d '[:space:]')"
  [ -z "$IMAGE" ] && return 0

  echo "Processing: $IMAGE"

  # Split image/tag (if no tag present, this will treat name as tag too; optional improvement below)
  local IMAGE_NAME TAG
  IMAGE_NAME="${IMAGE%%:*}"
  TAG="${IMAGE##*:}"

  # Remove registry if present (keeps only path after first slash)
  # Note: this is your existing behaviour; it intentionally strips e.g. docker.io/, quay.io/, ghcr.io/
  local IMAGE_PATH
  if [[ "$IMAGE_NAME" == */* ]]; then
    IMAGE_PATH="${IMAGE_NAME#*/}"
  else
    IMAGE_PATH="$IMAGE_NAME"
  fi

  local DEST="ghcr.io/${ORG}/${PREFIX}/${IMAGE_PATH}:${TAG}"
  echo "→ Destination: $DEST"

  # 1) Existence check FIRST (avoids touching source registry when already mirrored)
  if image_exists "$DEST"; then
    echo "✅ Exists already, skipping: $DEST"
    echo "----"
    return 0
  fi

  # 2) Push gate
  if [ "$PUSH" != "1" ]; then
    echo "[DRY-RUN] Would mirror: $IMAGE -> $DEST"
    echo "----"
    return 0
  fi

  # 3) Mirror with retry
  retry "mirror $IMAGE -> $DEST" \
    docker buildx imagetools create --tag "$DEST" "$IMAGE"

  echo "✅ Mirrored: $DEST"
  echo "----"
}

export -f process_one image_exists retry
export ORG PREFIX PUSH MAX_RETRIES BASE_DELAY

# Run in parallel (one line per image)
# Use grep to drop fully-empty/comment-only lines early to reduce forks a bit
grep -vE '^\s*(#|$)' images.txt \
  | xargs -I{} -P "$CONCURRENCY" bash -c 'process_one "$@"' _ {}

echo "All images processed"
