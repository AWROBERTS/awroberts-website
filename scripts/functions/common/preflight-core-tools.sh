preflight_core_tools() {
    echo "🔍 Checking required tools..."

    ###############################################
    # Shared helper functions (available everywhere)
    ###############################################

    latest_apt_version() { apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}'; }
    installed_apt_version() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null; }
    version_needs_upgrade() { dpkg --compare-versions "$1" lt "$2"; }

    prompt_upgrade() {
        local tool_name="$1"
        local current_version="$2"
        local latest_version="$3"

        if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
            echo "ℹ️  $tool_name: current=$current_version (latest unavailable)"
            return 1
        fi

        if ! version_needs_upgrade "$current_version" "$latest_version"; then
            echo "✅ $tool_name is up to date: $current_version"
            return 1
        fi

        echo "⚠️  $tool_name update available: current=$current_version latest=$latest_version"
        read -r -p "Upgrade $tool_name now? [y/N] " response

        case "${response,,}" in
            y|yes) return 0 ;;
            *) echo "⏭️  Skipping $tool_name upgrade."; return 1 ;;
        esac
    }

    upgrade_apt_package() {
        sudo_if_needed apt update
        sudo_if_needed apt install -y --only-upgrade "$1"
    }

    latest_helm_version() {
        curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name // empty'
    }

    ###############################################
    # Install-if-missing logic (shared across nodes)
    ###############################################

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

    # Buildx (required)
    if ! docker buildx version &>/dev/null; then
        echo "❌ Docker Buildx missing"
        exit 1
    fi

    ###############################################
    # Control-plane-only logic
    ###############################################
    if [[ "$HOST" == "$CONTROL_PLANE_HOST" ]]; then
        echo "🏰 Control-plane detected — running Control-plane-only checks"

        # Certs + manifests
        [[ -f "$HOST_CERT_PATH" ]] || { echo "❌ Cert not found at $HOST_CERT_PATH"; exit 1; }
        [[ -f "$HOST_KEY_PATH" ]] || { echo "❌ Key not found at $HOST_KEY_PATH"; exit 1; }
        [[ -d "$MANIFEST_DIR" ]] || { echo "❌ Manifest directory missing: $MANIFEST_DIR"; exit 1; }

        ###############################################
        # Upgrade prompting (Docker, curl, jq)
        ###############################################

        docker_current="$(installed_apt_version docker.io)"
        docker_latest="$(latest_apt_version docker.io)"
        if prompt_upgrade "Docker" "$docker_current" "$docker_latest"; then
            upgrade_apt_package docker.io
        fi

        curl_current="$(installed_apt_version curl)"
        curl_latest="$(latest_apt_version curl)"
        if prompt_upgrade "curl" "$curl_current" "$curl_latest"; then
            upgrade_apt_package curl
        fi

        jq_current="$(installed_apt_version jq)"
        jq_latest="$(latest_apt_version jq)"
        if prompt_upgrade "jq" "$jq_current" "$jq_latest"; then
            upgrade_apt_package jq
        fi

        ###############################################
        # Docker DNS (CP only)
        ###############################################
        DOCKER_CONFIG="/etc/docker/daemon.json"
        if ! sudo_if_needed test -f "$DOCKER_CONFIG"; then
            echo "📄 Creating Docker daemon.json with DNS..."
            sudo_if_needed bash -c "echo '{\"dns\": [\"8.8.8.8\", \"1.1.1.1\"]}' > \"$DOCKER_CONFIG\""
            sudo_if_needed systemctl restart docker
        fi

        ###############################################
        # Helm install-if-missing + upgrade-with-checksum
        ###############################################

        if ! command -v helm &>/dev/null; then
            echo "📦 Installing Helm..."
            curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
            chmod 700 get_helm.sh
            ./get_helm.sh
            rm get_helm.sh
        else
            echo "✅ Helm installed"
        fi

        helm_current="$(helm version --short 2>/dev/null | sed 's/^v//; s/+.*//')"
        helm_latest="$(latest_helm_version | sed 's/^v//; s/+.*//')"

        if [[ "$helm_current" != "$helm_latest" ]]; then
            echo "⚠️ Helm upgrade available: $helm_current → $helm_latest"
            read -r -p "Upgrade Helm now? [y/N] " response

            if [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]; then
                version="${helm_latest}"
                os="$(uname -s | tr '[:upper:]' '[:lower:]')"
                arch="$(uname -m)"
                [[ "$arch" == "x86_64" ]] && arch="amd64"
                [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && arch="arm64"

                tmp_dir="$(mktemp -d)"
                archive="helm-v${version}-${os}-${arch}.tar.gz"
                archive_url="https://get.helm.sh/${archive}"
                checksum_url="${archive_url}.sha256sum"

                echo "⬇️ Downloading Helm ${version}..."
                curl -fsSL -o "${tmp_dir}/${archive}" "$archive_url"

                echo "🔐 Downloading checksum..."
                curl -fsSL -o "${tmp_dir}/${archive}.sha256sum" "$checksum_url"

                expected_sha="$(awk '{print $1}' "${tmp_dir}/${archive}.sha256sum")"
                actual_sha="$(sha256sum "${tmp_dir}/${archive}" | awk '{print $1}')"

                if [[ "$expected_sha" != "$actual_sha" ]]; then
                    echo "❌ Helm checksum verification failed"
                    echo "   expected: $expected_sha"
                    echo "   actual:   $actual_sha"
                    rm -rf "$tmp_dir"
                    exit 1
                fi

                echo "📦 Extracting Helm..."
                tar -xzf "${tmp_dir}/${archive}" -C "$tmp_dir"

                echo "🚀 Installing Helm..."
                sudo_if_needed install -m 0755 "${tmp_dir}/${os}-${arch}/helm" /usr/local/bin/helm

                rm -rf "$tmp_dir"
                echo "✅ Helm upgraded to ${version}"
            else
                echo "⏭️ Skipping Helm upgrade."
            fi
        else
            echo "✅ Helm is up to date: $helm_current"
        fi

    else
        echo "👷 Worker node detected — skipping Control-plane-only checks"
    fi
}
