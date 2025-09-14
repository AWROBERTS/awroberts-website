: "${IMAGE_NAME_BASE:=${IMAGE_NAME%%:*}}"
: "${IMAGE_TAG:=$(date -u +%Y%m%d-%H%M%S)}"
: "${FULL_IMAGE:=${IMAGE_NAME_BASE}:${IMAGE_TAG}}"
: "${LATEST_IMAGE:=${IMAGE_NAME_BASE}:latest}"
