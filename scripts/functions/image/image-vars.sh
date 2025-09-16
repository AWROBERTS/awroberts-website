image_vars() {

  IMAGE_NAME_BASE="${IMAGE_NAME%%:*}"
  IMAGE_TAG="${IMAGE_TAG:-$(date -u +%Y%m%d-%H%M%S)}"
  FULL_IMAGE="${IMAGE_NAME_BASE}:${IMAGE_TAG}"
  LATEST_IMAGE="${IMAGE_NAME_BASE}:latest"

  echo "📦 Image variables set:"
  echo "  IMAGE_NAME_BASE: $IMAGE_NAME_BASE"
  echo "  IMAGE_TAG:       $IMAGE_TAG"
  echo "  FULL_IMAGE:      $FULL_IMAGE"
  echo "  LATEST_IMAGE:    $LATEST_IMAGE"
}
