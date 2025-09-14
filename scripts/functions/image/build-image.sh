#!/usr/bin/env bash

build_image() {
  # Define builder name and config path
  BUILDER_NAME="custom-builder"
  BUILDKIT_CONFIG="buildkitd.toml"

  # Create BuildKit config file if it doesn't exist
  if [[ ! -f "$BUILDKIT_CONFIG" ]]; then
    echo "📄 Creating BuildKit config with custom DNS..."
    cat <<EOF > "$BUILDKIT_CONFIG"
[worker.oci]
  dns = ["8.8.8.8", "1.1.1.1"]
EOF
  fi

  # Check if builder exists
  if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
    echo "🔧 Creating builder '$BUILDER_NAME' with DNS config mounted..."
    docker buildx create \
      --name "$BUILDER_NAME" \
      --driver docker-container \
      --use \
      --buildkitd-flags '--config=/etc/buildkit/buildkitd.toml' \
      --mount "type=bind,src=$(pwd)/$BUILDKIT_CONFIG,dst=/etc/buildkit/buildkitd.toml" \
      --image moby/buildkit:latest
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
