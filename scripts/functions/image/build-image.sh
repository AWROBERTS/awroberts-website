#!/usr/bin/env bash

build_image() {
  echo "🔨 Building image ${FULL_IMAGE} and tagging as latest for ${PLATFORM}"
  docker buildx build \
    --platform "${PLATFORM}" \
    -t "${FULL_IMAGE}" \
    -t "${LATEST_IMAGE}" \
    --load \
    "${BUILD_CONTEXT}"
}
