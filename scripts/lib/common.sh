#!/usr/bin/env bash
# Common config, defaults, and helpers. Source this first.

# Load all variables from the env file (no in-script defaults)
# Exports all keys from awroberts.env into the environment
ENV_FILE="./awroberts.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$ENV_FILE"
  set +a
else
  echo "Environment file not found: $ENV_FILE"
  exit 1
fi

# Derived values (do not introduce defaults; compute only from env)
IMAGE_NAME_BASE="${IMAGE_NAME%%:*}"
if [[ "${USE_TIMESTAMP}" == "true" && -z "${IMAGE_TAG}" ]]; then
  IMAGE_TAG="$(date -u +%Y%m%d-%H%M%S)"
fi
FULL_IMAGE="${IMAGE_NAME_BASE}:${IMAGE_TAG}"

# Helper: sudo if not root
sudo_if_needed() { if [[ $EUID -ne 0 ]]; then sudo "$@"; else "$@"; fi; }

# Preflight checks that apply globally
preflight_core_tools() {
  command -v docker >/dev/null 2>&1 || { echo "docker not found"; exit 1; }
  command -v curl >/dev/null 2>&1 || { echo "curl not found"; exit 1; }

  if ! docker buildx version >/dev/null 2>&1; then
    echo "Docker Buildx is required but not available."
    echo "On Debian/Ubuntu/Mint install: sudo apt-get install -y docker-buildx-plugin"
    echo "Docs: https://docs.docker.com/build/buildx/install/"
    exit 1
  fi

  [[ -f "$HOST_CERT_PATH" ]] || { echo "Cert not found at $HOST_CERT_PATH"; exit 1; }
  [[ -f "$HOST_KEY_PATH" ]] || { echo "Key not found at $HOST_KEY_PATH"; exit 1; }
  [[ -d "$MANIFEST_DIR" ]] || { echo "Manifest directory not found: $MANIFEST_DIR"; exit 1; }
}