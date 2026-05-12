set -euo pipefail

ORG="tgmarius"
PREFIX="mirror"

echo "Starting GHCR mirroring"
echo "----"

while IFS= read -r RAW_LINE || [ -n "$RAW_LINE" ]; do
  IMAGE="$(echo "$RAW_LINE" | sed 's/#.*//g' | tr -d '[:space:]')"
  [ -z "$IMAGE" ] && continue

  echo "Processing: $IMAGE"

  # Split image and tag
  IMAGE_NAME="${IMAGE%%:*}"
  TAG="${IMAGE##*:}"

  # Remove registry if present
  if [[ "$IMAGE_NAME" == */* ]]; then
    IMAGE_PATH="${IMAGE_NAME#*/}"
  else
    IMAGE_PATH="$IMAGE_NAME"
  fi

  DEST="ghcr.io/${ORG}/${PREFIX}/${IMAGE_PATH}:${TAG}"

  echo "→ Mirroring to $DEST"

  docker buildx imagetools create \
    --tag "$DEST" \
    "$IMAGE"

  echo "Done"
  echo "----"

done < images.txt

echo "All images mirrored successfully"
