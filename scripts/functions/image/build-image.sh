#!/usr/bin/env bash

build_image() {
  # Define builder name and paths
  BUILDER_NAME="custom-builder"
  BUILDKIT_DIR="buildkit-custom"
  BUILDKIT_CONFIG="$BUILDKIT_DIR/buildkitd.toml"
  BUILDKIT_IMAGE="buildkit-with-dns"
  BUILD_CONTEXT="docker/awroberts"  # Updated build context path

  # Create buildkit-custom directory and config if missing
  if [[ ! -f "$BUILDKIT_CONFIG" ]]; then
    echo "📁 Setting up BuildKit config with custom DNS..."
    mkdir -p "$BUILDKIT_DIR"
    cat <<EOF > "$BUILDKIT_CONFIG"
[worker.oci]
  dns = ["8.8.8.8", "1.1.1.1"]
EOF

    # Create Dockerfile for custom BuildKit image
    cat <<EOF > "$BUILDKIT_DIR/Dockerfile"
FROM moby/buildkit:latest
COPY buildkitd.toml /etc/buildkit/buildkitd.toml
EOF
  fi

  # Build the custom BuildKit image
  echo "🐳 Building custom BuildKit image with DNS config..."
  docker build -t "$BUILDKIT_IMAGE" "$BUILDKIT_DIR"

  # Create builder if it doesn't exist
  if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
    echo "🔧 Creating builder '$BUILDER_NAME' using custom BuildKit image..."
    docker buildx create \
      --name "$BUILDER_NAME" \
      --driver docker-container \
      --use \
      --buildkitd-flags '--config=/etc/buildkit/buildkitd.toml' \
      --image "$BUILDKIT_IMAGE"
  else
    docker buildx use "$BUILDER_NAME"
  fi

  echo "🔨 Building image ${FULL_IMAGE} and tagging as latest for ${PLATFORM}"
  docker buildx build \
    --platform "${PLATFORM}" \
    -t "${FULL_IMAGE}" \
    -t "${LATEST_IMAGE}" \
    --load \
    "$BUILD_CONTEXT"
}
