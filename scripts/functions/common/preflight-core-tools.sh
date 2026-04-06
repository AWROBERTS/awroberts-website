preflight_core_tools() {
  echo "🔍 Checking required tools..."

  latest_apt_version() {
    local package_name="$1"
    apt-cache policy "$package_name" 2>/dev/null | awk '/Candidate:/ {print $2}'
  }

  latest_helm_version() {
    curl -fsSL https://api.github.com/repos/helm/helm/releases/latest 2>/dev/null \
      | jq -r '.tag_name // empty'
  }

  compare_versions() {
    local tool_name="$1"
    local current_version="$2"
    local latest_version="$3"

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
      echo "ℹ️  $tool_name: current=$current_version (latest unavailable)"
      return 0
    fi

    if [[ "$current_version" == "$latest_version" ]]; then
      echo "✅ $tool_name is up to date: $current_version"
      return 0
    fi

    echo "⚠️  $tool_name update available: current=$current_version latest=$latest_version"
    return 0
  }

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
    compare_versions \
      "Docker" \
      "$(docker --version | awk '{print $3}' | sed 's/,$//')" \
      "$(latest_apt_version docker.io)"
  fi

  # Curl check and install
  if ! command -v curl &>/dev/null; then
    echo "🌐 curl not found. Installing curl..."
    sudo_if_needed apt update
    sudo_if_needed apt install -y curl
    echo "✅ curl installed."
  else
    echo "✅ curl is already installed."
    compare_versions \
      "curl" \
      "$(curl --version | head -n1 | awk '{print $2}')" \
      "$(latest_apt_version curl)"
  fi

  # jq check and install
  if ! command -v jq &>/dev/null; then
    echo "🔧 jq not found. Installing jq..."
    sudo_if_needed apt update
    sudo_if_needed apt install -y jq
    echo "✅ jq installed."
  else
    echo "✅ jq is already installed."
    compare_versions \
      "jq" \
      "$(jq --version | sed 's/^jq-//')" \
      "$(latest_apt_version jq)"
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

  if ! sudo_if_needed test -f "$DOCKER_CONFIG"; then
    echo "📄 Docker daemon.json not found. Creating it with DNS settings..."
    sudo_if_needed bash -c "echo '{\"dns\": [\"8.8.8.8\", \"1.1.1.1\"]}' > \"$DOCKER_CONFIG\"" -- DOCKER_CONFIG="$DOCKER_CONFIG"
    sudo_if_needed systemctl restart docker
    echo "✅ Docker daemon created and restarted with DNS config."
  else
    if ! grep -q '"dns"' "$DOCKER_CONFIG" 2>/dev/null; then
      echo "🛠️ Adding DNS settings to existing Docker daemon.json..."
      sudo_if_needed cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.bak"
      sudo_if_needed bash -c "
        jq '. + {dns: [\"8.8.8.8\", \"1.1.1.1\"]}' \"$DOCKER_CONFIG\" > /tmp/daemon.json &&
        mv /tmp/daemon.json \"$DOCKER_CONFIG\" &&
        systemctl restart docker
      "
      echo "✅ Docker daemon restarted with updated DNS."
    else
      echo "✅ Docker DNS already configured."
    fi
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
    compare_versions \
      "Helm" \
      "$(helm version --short 2>/dev/null | sed 's/^v//; s/+.*//')" \
      "$(latest_helm_version | sed 's/^v//; s/+.*//')"
  fi
}