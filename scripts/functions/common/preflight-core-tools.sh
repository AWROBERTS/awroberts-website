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

  prompt_upgrade() {
    local tool_name="$1"
    local current_version="$2"
    local latest_version="$3"

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
      echo "ℹ️  $tool_name: current=$current_version (latest unavailable)"
      return 1
    fi

    if [[ "$current_version" == "$latest_version" ]]; then
      echo "✅ $tool_name is up to date: $current_version"
      return 1
    fi

    echo "⚠️  $tool_name update available: current=$current_version latest=$latest_version"
    read -r -p "Upgrade $tool_name now? [y/N] " response
    case "${response,,}" in
      y|yes)
        return 0
        ;;
      *)
        echo "⏭️  Skipping $tool_name upgrade."
        return 1
        ;;
    esac
  }

  upgrade_apt_package() {
    local package_name="$1"
    sudo_if_needed apt update
    sudo_if_needed apt install -y --only-upgrade "$package_name"
  }

  upgrade_helm() {
    local latest_version="$1"
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    curl -fsSL -o "$tmp_dir/get_helm.sh" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 "$tmp_dir/get_helm.sh"

    if [[ -n "$latest_version" && "$latest_version" != "null" ]]; then
      export DESIRED_VERSION="$latest_version"
    fi

    "$tmp_dir/get_helm.sh"
    rm -rf "$tmp_dir"
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
    local docker_current docker_latest
    docker_current="$(docker --version | awk '{print $3}' | sed 's/,$//')"
    docker_latest="$(latest_apt_version docker.io)"
    if prompt_upgrade "Docker" "$docker_current" "$docker_latest"; then
      upgrade_apt_package docker.io
      echo "✅ Docker upgraded."
    fi
  fi

  # Curl check and install
  if ! command -v curl &>/dev/null; then
    echo "🌐 curl not found. Installing curl..."
    sudo_if_needed apt update
    sudo_if_needed apt install -y curl
    echo "✅ curl installed."
  else
    echo "✅ curl is already installed."
    local curl_current curl_latest
    curl_current="$(curl --version | head -n1 | awk '{print $2}')"
    curl_latest="$(latest_apt_version curl)"
    if prompt_upgrade "curl" "$curl_current" "$curl_latest"; then
      upgrade_apt_package curl
      echo "✅ curl upgraded."
    fi
  fi

  # jq check and install
  if ! command -v jq &>/dev/null; then
    echo "🔧 jq not found. Installing jq..."
    sudo_if_needed apt update
    sudo_if_needed apt install -y jq
    echo "✅ jq installed."
  else
    echo "✅ jq is already installed."
    local jq_current jq_latest
    jq_current="$(jq --version | sed 's/^jq-//')"
    jq_latest="$(latest_apt_version jq)"
    if prompt_upgrade "jq" "$jq_current" "$jq_latest"; then
      upgrade_apt_package jq
      echo "✅ jq upgraded."
    fi
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
    local helm_current helm_latest
    helm_current="$(helm version --short 2>/dev/null | sed 's/^v//; s/+.*//')"
    helm_latest="$(latest_helm_version | sed 's/^v//; s/+.*//')"
    if prompt_upgrade "Helm" "$helm_current" "$helm_latest"; then
      upgrade_helm "$helm_latest"
      echo "✅ Helm upgraded."
    fi
  fi
}