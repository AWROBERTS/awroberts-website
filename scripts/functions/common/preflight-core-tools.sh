#!/usr/bin/env bash

preflight_core_tools() {
    echo "🔍 Checking required tools..."

    # Helper functions
    latest_apt_version() { apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}'; }
    installed_apt_version() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null; }
    version_needs_upgrade() { dpkg --compare-versions "$1" lt "$2"; }
    latest_helm_version() { curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name // empty'; }

    # Docker
    if ! command -v docker &>/dev/null; then
        echo "🐳 Installing Docker..."
        sudo_if_needed apt update
        sudo_if_needed apt install -y docker.io
        sudo_if_needed systemctl enable docker
        sudo_if_needed systemctl start docker
    else
        echo "✅ Docker installed"
    fi

    # curl
    if ! command -v curl &>/dev/null; then
        echo "🌐 Installing curl..."
        sudo_if_needed apt update
        sudo_if_needed apt install -y curl
    else
        echo "✅ curl installed"
    fi

    # jq
    if ! command -v jq &>/dev/null; then
        echo "🔧 Installing jq..."
        sudo_if_needed apt update
        sudo_if_needed apt install -y jq
    else
        echo "✅ jq installed"
    fi

    # Buildx
    if ! docker buildx version &>/dev/null; then
        echo "❌ Docker Buildx missing"
        exit 1
    fi

    # Control-plane-only checks
    if [[ "$HOST" == "$CONTROL_PLANE_HOST" ]]; then
        echo "🏰 Control-plane detected — running Control-plane-only checks"

        [[ -f "$HOST_CERT_PATH" ]] || { echo "❌ Cert not found at $HOST_CERT_PATH"; exit 1; }
        [[ -f "$HOST_KEY_PATH" ]] || { echo "❌ Key not found at $HOST_KEY_PATH"; exit 1; }
        [[ -d "$MANIFEST_DIR" ]] || { echo "❌ Manifest directory missing: $MANIFEST_DIR"; exit 1; }

        # Docker DNS
        DOCKER_CONFIG="/etc/docker/daemon.json"
        if ! sudo_if_needed test -f "$DOCKER_CONFIG"; then
            echo "📄 Creating Docker daemon.json with DNS..."
            sudo_if_needed bash -c "echo '{\"dns\": [\"8.8.8.8\", \"1.1.1.1\"]}' > \"$DOCKER_CONFIG\""
            sudo_if_needed systemctl restart docker
        fi

        # Helm
        if ! command -v helm &>/dev/null; then
            echo "📦 Installing Helm..."
            curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
            chmod 700 get_helm.sh
            ./get_helm.sh
            rm get_helm.sh
        else
            echo "✅ Helm installed"
        fi
    else
        echo "👷 Worker node detected — skipping Control-plane-only checks"
    fi
}
