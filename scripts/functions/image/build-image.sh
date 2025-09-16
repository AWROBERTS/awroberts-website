#!/usr/bin/env bash

build_image() {
  BUILDER_NAME="custom-builder"
  BUILDKIT_DIR="buildkit-custom"
  BUILDKIT_CONFIG="$BUILDKIT_DIR/buildkitd.toml"
  BUILDKIT_IMAGE="buildkit-with-dns"
  BUILD_CONTEXT="docker/awroberts"

  # Create buildkit-custom directory and config if missing
  if [[ ! -f "$BUILDKIT_CONFIG" ]]; then
    echo "📁 Setting up BuildKit config with custom DNS..."
    mkdir -p "$BUILDKIT_DIR"
    cat <<EOF > "$BUILDKIT_CONFIG"
[worker.oci]
  dns = ["8.8.8.8", "1.1.1.1"]
EOF

    cat <<EOF > "$BUILDKIT_DIR/Dockerfile"
FROM moby/buildkit:latest
COPY buildkitd.toml /etc/buildkit/buildkitd.toml
EOF
  fi

  # Build the custom BuildKit image
  echo "🐳 Building custom BuildKit image with DNS config..."
  docker build -t "$BUILDKIT_IMAGE" "$BUILDKIT_DIR"

  # Remove any existing BuildKit container
  docker rm -f buildkit-container 2>/dev/null || true

  # Start BuildKit container manually with mounted config
  echo "🚀 Starting BuildKit container..."
  docker run -d --privileged \
    --name buildkit-container \
    --network host \
    -v "$(pwd)/buildkit-custom/buildkitd.toml:/etc/buildkit/buildkitd.toml" \
    "$BUILDKIT_IMAGE" \
    --config /etc/buildkit/buildkitd.toml

  # Create builder if it doesn't exist
  if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
    echo "🔧 Registering builder '$BUILDER_NAME' with BuildKit container..."
    docker buildx create \
      --name "$BUILDER_NAME" \
      --driver docker-container \
      --use \
      buildkit-container
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
