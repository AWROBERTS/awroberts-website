#!/usr/bin/env bash
build_image() {
  # Create or use a builder with DNS settings passed to BuildKit
  if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
    echo "🔧 Creating builder '$BUILDER_NAME' with custom DNS settings..."
    docker buildx create \
      --name "$BUILDER_NAME" \
      --driver docker-container \
      --buildkitd-flags '--dns=8.8.8.8 --dns=1.1.1.1' \
      --use
  else
    docker buildx use "$BUILDER_NAME"
  fi

  echo "🔨 Building image ${FULL_IMAGE} and tagging as latest for ${PLATFORM}"
  docker buildx build \
    --platform "${PLATFORM}" \
    -t "${FULL_IMAGE}" \
    -t "${LATEST_IMAGE}" \
    --load \
    "${BUILD_CONTEXT}"
}
