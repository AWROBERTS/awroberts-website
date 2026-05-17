ensure_k8s_and_containerd_installed() {
  echo "🔍 Installing Kubernetes (binary method) + containerd..."

  # --- Install containerd ---
  if ! command -v containerd >/dev/null 2>&1; then
    echo "📦 Installing containerd..."
    sudo_if_needed apt-get update
    sudo_if_needed apt-get install -y containerd
  else
    echo "✅ containerd already installed."
  fi

  echo "🔧 Configuring containerd..."
  sudo_if_needed mkdir -p /etc/containerd
  sudo_if_needed containerd config default | sudo_if_needed tee /etc/containerd/config.toml >/dev/null

  sudo_if_needed sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sudo_if_needed systemctl restart containerd
  sudo_if_needed systemctl enable containerd

  echo "🔧 Disabling swap..."
  sudo_if_needed swapoff -a
  sudo_if_needed sed -i '/swap/d' /etc/fstab

  echo "🌐 Fetching latest Kubernetes version..."
  VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  echo "📌 Latest version: $VERSION"

  echo "⬇️ Downloading kubeadm, kubelet, kubectl..."
  sudo_if_needed curl -L --remote-name-all \
    https://dl.k8s.io/${VERSION}/bin/linux/amd64/{kubeadm,kubelet,kubectl}

  sudo_if_needed chmod +x kubeadm kubelet kubectl
  sudo_if_needed mv kubeadm kubelet kubectl /usr/local/bin/

  echo "🔧 Installing kubelet systemd units..."
  sudo_if_needed mkdir -p /etc/systemd/system/kubelet.service.d

  sudo_if_needed curl -L \
    https://raw.githubusercontent.com/kubernetes/release/${VERSION}/cmd/kubepkg/templates/latest/deb/kubelet/lib/systemd/system/kubelet.service \
    -o /etc/systemd/system/kubelet.service

  sudo_if_needed curl -L \
    https://raw.githubusercontent.com/kubernetes/release/${VERSION}/cmd/kubepkg/templates/latest/deb/kubeadm/10-kubeadm.conf \
    -o /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

  sudo_if_needed systemctl daemon-reload
  sudo_if_needed systemctl enable --now kubelet

  echo "📦 Pulling Kubernetes control plane images..."
  sudo_if_needed kubeadm config images pull

  echo "✅ Kubernetes binaries + containerd installation complete."
}
