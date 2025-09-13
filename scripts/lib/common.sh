#!/usr/bin/env bash
# Common config, defaults, and helpers. Source this first.

# Load all variables from the env file
ENV_FILE="./awroberts.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
else
  echo "Environment file not found: $ENV_FILE"
  exit 1
fi

# Derived values
IMAGE_NAME_BASE="${IMAGE_NAME%%:*}"
if [[ "${USE_TIMESTAMP}" == "true" && -z "${IMAGE_TAG}" ]]; then
  IMAGE_TAG="$(date -u +%Y%m%d-%H%M%S)"
fi
FULL_IMAGE="${IMAGE_NAME_BASE}:${IMAGE_TAG}"

# Helper: sudo if not root
sudo_if_needed() { if [[ $EUID -ne 0 ]]; then sudo "$@"; else "$@"; fi; }

# TLS secret creation
ensure_tls_secret() {
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
  kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" \
    --cert="$HOST_CERT_PATH" \
    --key="$HOST_KEY_PATH" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# Preflight checks
preflight_core_tools() {
  command -v docker >/dev/null 2>&1 || { echo "docker not found"; exit 1; }
  command -v curl >/dev/null 2>&1 || { echo "curl not found"; exit 1; }
  docker buildx version >/dev/null 2>&1 || {
    echo "Docker Buildx is required but not available."
    exit 1
  }
  [[ -f "$HOST_CERT_PATH" ]] || { echo "Cert not found at $HOST_CERT_PATH"; exit 1; }
  [[ -f "$HOST_KEY_PATH" ]] || { echo "Key not found at $HOST_KEY_PATH"; exit 1; }
  [[ -d "$MANIFEST_DIR" ]] || { echo "Manifest directory not found: $MANIFEST_DIR"; exit 1; }

  # 🛠️ Helm check and install
  if ! command -v helm &> /dev/null; then
    echo "Helm not found. Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
  else
    echo "Helm is already installed."
  fi
}

