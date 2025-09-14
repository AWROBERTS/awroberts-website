#!/usr/bin/env bash
build_image() {
  docker buildx use "$BUILDER_NAME" || docker buildx create --name "$BUILDER_NAME" --use
  echo "🔨 Building image ${FULL_IMAGE} and tagging as latest for ${PLATFORM}"
  docker buildx build --platform "${PLATFORM}" \
    -t "${FULL_IMAGE}" \
    -t "${LATEST_IMAGE}" \
    --load "${BUILD_CONTEXT}"
}
