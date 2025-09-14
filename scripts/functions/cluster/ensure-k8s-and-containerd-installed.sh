ensure_k8s_and_containerd_installed() {
  # Ensure kubeadm/kubelet/kubectl are installed (auto-install if missing)
  if ! command -v kubeadm >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
    echo "Installing kubeadm, kubelet, kubectl..."
    sudo_if_needed apt-get update
    sudo_if_needed apt-get install -y apt-transport-https ca-certificates curl gpg
    sudo_if_needed curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg \
      https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | \
      sudo_if_needed tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
    sudo_if_needed apt-get update
    sudo_if_needed apt-get install -y kubelet kubeadm kubectl
    sudo_if_needed systemctl enable --now kubelet
  fi

  # Ensure containerd exists
  if ! command -v containerd >/dev/null 2>&1; then
    echo "Installing containerd..."
    sudo_if_needed apt-get update
    sudo_if_needed apt-get install -y containerd
  fi
}