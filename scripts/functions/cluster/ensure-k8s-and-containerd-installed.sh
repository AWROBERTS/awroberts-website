ensure_k8s_and_containerd_installed() {
  echo "🔍 Ensuring Kubernetes + containerd are installed..."

  sudo_if_needed apt-get update
  sudo_if_needed apt-get install -y apt-transport-https ca-certificates curl gpg

  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo_if_needed tee /usr/share/keyrings/kubernetes-archive-keyring.gpg >/dev/null

  echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] \
https://apt.kubernetes.io/ kubernetes-xenial main" \
    | sudo_if_needed tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

  sudo_if_needed apt-get update

  LATEST=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  VERSION="${LATEST#v}"

  echo "📌 Latest Kubernetes version detected: $VERSION"

  PKG_VERSION=$(apt-cache madison kubeadm | grep "$VERSION" | head -n1 | awk '{print $3}')

  if [ -z "$PKG_VERSION" ]; then
    echo "❌ ERROR: Could not find kubeadm package for version $VERSION"
    exit 1
  fi

  echo "📦 Installing Kubernetes packages: $PKG_VERSION"

  sudo_if_needed apt-get install -y \
    kubeadm="$PKG_VERSION" \
    kubelet="$PKG_VERSION" \
    kubectl="$PKG_VERSION"

  sudo_if_needed apt-mark hold kubeadm kubelet kubectl
  sudo_if_needed systemctl enable --now kubelet

  if ! command -v containerd >/dev/null 2>&1; then
    echo "📦 Installing containerd..."
    sudo_if_needed apt-get install -y containerd
  else
    echo "✅ containerd already installed."
  fi

  echo "✅ Kubernetes + containerd installation complete."
}
