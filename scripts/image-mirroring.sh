#!/usr/bin/env bash
set -euo pipefail

ORG="tgmarius"
PREFIX="mirror"

# Safety default
PUSH="${PUSH:-0}"   # Only PUSH=1 will actually write to GHCR

echo "Starting GHCR mirroring"
echo "Mode: $([ "$PUSH" = "1" ] && echo "PUSH" || echo "DRY-RUN")"
echo "----"

image_exists() {
  local ref="$1"
  docker buildx imagetools inspect "$ref" >/dev/null 2>&1
}

while IFS= read -r RAW_LINE || [ -n "$RAW_LINE" ]; do
  # Strip comments + whitespace
  IMAGE="$(echo "$RAW_LINE" | sed 's/#.*//g' | tr -d '[:space:]')"
  [ -z "$IMAGE" ] && continue

  echo "Processing: $IMAGE"

  # Split image/tag
  IMAGE_NAME="${IMAGE%%:*}"
  TAG="${IMAGE##*:}"

  # Remove registry if present
  if [[ "$IMAGE_NAME" == */* ]]; then
    IMAGE_PATH="${IMAGE_NAME#*/}"
  else
    IMAGE_PATH="$IMAGE_NAME"
  fi

  DEST="ghcr.io/${ORG}/${PREFIX}/${IMAGE_PATH}:${TAG}"
  echo "→ Destination: $DEST"

  # Skip if already exists
  if image_exists "$DEST"; then
    echo "✅ Exists already, skipping: $DEST"
    echo "----"
    continue
  fi

  # Dry-run guard
  if [ "$PUSH" != "1" ]; then
    echo "[DRY-RUN] Would mirror: $IMAGE -> $DEST"
    echo "----"
    continue
  fi

  # Mirror (no retry, no parallelism)
  docker buildx imagetools create \
    --tag "$DEST" \
    "$IMAGE"

  echo "✅ Mirrored: $DEST"
  echo "----"

done < images.txt

echo "All images processed"
