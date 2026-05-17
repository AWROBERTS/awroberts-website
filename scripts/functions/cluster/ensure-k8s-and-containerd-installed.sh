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

  echo "🔧 Writing kubelet systemd units (embedded)..."
  sudo_if_needed mkdir -p /etc/systemd/system/kubelet.service.d

  sudo_if_needed tee /etc/systemd/system/kubelet.service >/dev/null <<'EOF'
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/home/
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  sudo_if_needed tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf >/dev/null <<'EOF'
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF

  echo "🔧 Enabling kubelet..."
  sudo_if_needed systemctl daemon-reload
  sudo_if_needed systemctl enable --now kubelet

  echo "📦 Pulling Kubernetes control plane images..."
  sudo_if_needed kubeadm config images pull

  echo "✅ Kubernetes binaries + containerd installation complete."
}
