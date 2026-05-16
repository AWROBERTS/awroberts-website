ensure_k8s_and_containerd_installed() {
  echo "🔍 Checking Kubernetes tools..."

  # Install Kubernetes binaries if missing OR if version is too old
  if ! command -v kubeadm >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
    echo "📦 Installing kubeadm, kubelet, kubectl (latest stable)..."

    # Add the official Kubernetes stable repo (not version-locked)
    sudo_if_needed apt-get update
    sudo_if_needed apt-get install -y apt-transport-https ca-certificates curl gpg

    sudo_if_needed curl -fsSL https://pkgs.k8s.io/core:/stable:/deb/Release.key \
      | sudo_if_needed tee /usr/share/keyrings/kubernetes-archive-keyring.gpg >/dev/null

    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/deb/ /" \
      | sudo_if_needed tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

    sudo_if_needed apt-get update

    # Detect latest Kubernetes version
    LATEST=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    VERSION="${LATEST#v}"   # strip leading v

    echo "📌 Installing Kubernetes version: $VERSION"

    # Install exact version (prevents fallback to older versions like 1.33)
    sudo_if_needed apt-get install -y \
      kubeadm="${VERSION}-1.1" \
      kubelet="${VERSION}-1.1" \
      kubectl="${VERSION}-1.1"

    # Prevent Ubuntu from silently upgrading/downgrading
    sudo_if_needed apt-mark hold kubeadm kubelet kubectl

    sudo_if_needed systemctl enable --now kubelet
  else
    echo "✅ Kubernetes tools already installed."
  fi

  # Ensure containerd exists
  if ! command -v containerd >/dev/null 2>&1; then
    echo "📦 Installing containerd..."
    sudo_if_needed apt-get update
    sudo_if_needed apt-get install -y containerd
  else
    echo "✅ containerd already installed."
  fi
}
