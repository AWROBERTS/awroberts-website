ensure_k8s_and_containerd_installed() {
  echo "🔍 Ensuring Kubernetes + containerd are installed..."

  # Add Kubernetes stable repo (safe even if already present)
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

  echo "📌 Latest Kubernetes version detected: $VERSION"

  # Find the correct Debian package version (e.g. 1.36.1-1.1)
  PKG_VERSION=$(apt-cache madison kubeadm | grep "$VERSION" | head -n1 | awk '{print $3}')

  if [ -z "$PKG_VERSION" ]; then
    echo "❌ ERROR: Could not find kubeadm package for version $VERSION"
    exit 1
  fi

  echo "📦 Installing Kubernetes packages: $PKG_VERSION"

  # Always reinstall kubeadm/kubelet/kubectl
  sudo_if_needed apt-get install -y \
    kubeadm="$PKG_VERSION" \
    kubelet="$PKG_VERSION" \
    kubectl="$PKG_VERSION"

  # Prevent Ubuntu from silently upgrading/downgrading
  sudo_if_needed apt-mark hold kubeadm kubelet kubectl

  sudo_if_needed systemctl enable --now kubelet

  # Ensure containerd exists
  if ! command -v containerd >/dev/null 2>&1; then
    echo "📦 Installing containerd..."
    sudo_if_needed apt-get install -y containerd
  else
    echo "✅ containerd already installed."
  fi

  echo "✅ Kubernetes + containerd installation complete."
}
