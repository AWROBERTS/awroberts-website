preflight_core_tools() {
  command -v docker >/dev/null 2>&1 || { echo "❌ docker not found"; exit 1; }
  command -v curl >/dev/null 2>&1 || { echo "❌ curl not found"; exit 1; }
  docker buildx version >/dev/null 2>&1 || {
    echo "❌ Docker Buildx is required but not available."
    exit 1
  }
  [[ -f "$HOST_CERT_PATH" ]] || { echo "❌ Cert not found at $HOST_CERT_PATH"; exit 1; }
  [[ -f "$HOST_KEY_PATH" ]] || { echo "❌ Key not found at $HOST_KEY_PATH"; exit 1; }
  [[ -d "$MANIFEST_DIR" ]] || { echo "❌ Manifest directory not found: $MANIFEST_DIR"; exit 1; }

  if ! command -v helm &> /dev/null; then
    echo "📦 Helm not found. Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
  else
    echo "✅ Helm is already installed."
  fi
}
