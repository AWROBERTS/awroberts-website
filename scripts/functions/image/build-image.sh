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
    echo "🔧 Creating builder '$BUILDER_NAME' with DNS config..."
    docker buildx create \
      --name "$BUILDER_NAME" \
      --driver docker-container \
      --use \
      --buildkitd-flags '--config=/etc/buildkit/buildkitd.toml' \
      --image moby/buildkit:latest

    # Get builder container ID
    BUILDER_CONTAINER=$(docker ps -qf "name=$BUILDER_NAME")

    # Copy DNS config into builder container
    docker cp "$BUILDKIT_CONFIG" "$BUILDER_CONTAINER":/etc/buildkit/buildkitd.toml
    docker restart "$BUILDER_CONTAINER"
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
