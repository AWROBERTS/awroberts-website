preflight_core_tools() {
  echo "🔍 Checking required tools..."

  # Docker check and install
  if ! command -v docker &>/dev/null; then
    echo "🐳 Docker not found. Installing Docker..."
    sudo_if_needed apt update
    sudo_if_needed apt install -y docker.io
    sudo_if_needed systemctl enable docker
    sudo_if_needed systemctl start docker
    echo "✅ Docker installed."
  else
    echo "✅ Docker is already installed."
  fi

  # Curl check and install
  if ! command -v curl &>/dev/null; then
    echo "🌐 curl not found. Installing curl..."
    sudo_if_needed apt update
    sudo_if_needed apt install -y curl
    echo "✅ curl installed."
  else
    echo "✅ curl is already installed."
  fi

  # jq check and install
  if ! command -v jq &>/dev/null; then
    echo "🔧 jq not found. Installing jq..."
    sudo_if_needed apt update
    sudo_if_needed apt install -y jq
    echo "✅ jq installed."
  else
    echo "✅ jq is already installed."
  fi

  # Docker Buildx check
  if ! docker buildx version &>/dev/null; then
    echo "❌ Docker Buildx is required but not available."
    exit 1
  fi

  # Cert and manifest checks
  [[ -f "$HOST_CERT_PATH" ]] || { echo "❌ Cert not found at $HOST_CERT_PATH"; exit 1; }
  [[ -f "$HOST_KEY_PATH" ]] || { echo "❌ Key not found at $HOST_KEY_PATH"; exit 1; }
  [[ -d "$MANIFEST_DIR" ]] || { echo "❌ Manifest directory not found: $MANIFEST_DIR"; exit 1; }

  # Docker DNS config
  DOCKER_CONFIG="/etc/docker/daemon.json"
  echo "🔧 Checking Docker DNS configuration..."
  if ! grep -q '"dns"' "$DOCKER_CONFIG" 2>/dev/null; then
    echo "🛠️ Adding DNS settings to Docker daemon.json..."
    sudo_if_needed bash -c "
      jq '. + {dns: [\"8.8.8.8\", \"1.1.1.1\"]}' \"$DOCKER_CONFIG\" > /tmp/daemon.json &&
      mv /tmp/daemon.json \"$DOCKER_CONFIG\" &&
      systemctl restart docker
    "
    echo "✅ Docker daemon restarted with updated DNS."
  else
    echo "✅ Docker DNS already configured."
  fi

  # Helm check and install
  if ! command -v helm &>/dev/null; then
    echo "📦 Helm not found. Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
  else
    echo "✅ Helm is already installed."
  fi
}
