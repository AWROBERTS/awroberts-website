prepare_nodes() {
  echo "🧱 Preparing all nodes via SSH"

  # Control plane
  run_preflight_core_tools "$CONTROL_PLANE_HOST" "$CONTROL_PLANE_USER"
  prepare_node "$CONTROL_PLANE_HOST" "$CONTROL_PLANE_USER"

  # Workers
  for HOST in $WORKER_HOSTS; do
    run_preflight_core_tools "$HOST" "$WORKER_USER"
    prepare_node "$HOST" "$WORKER_USER"
  done
}

prepare_node() {
  local HOST="$1"
  local USER="$2"

  echo "🧱 Preparing node via SSH: $HOST ($USER)"

  ssh -i "$SSH_KEY_PATH" \
      -o StrictHostKeyChecking=accept-new \
      "$USER@$HOST" "sudo bash -c '
        set -e

        apt-get update
        apt-get install -y containerd

        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
        sed -i \"s/SystemdCgroup = false/SystemdCgroup = true/\" /etc/containerd/config.toml
        systemctl restart containerd
        systemctl enable containerd

        swapoff -a
        sed -i \"/swap/d\" /etc/fstab

        modprobe overlay || true
        modprobe br_netfilter || true
        modprobe nf_conntrack || true

        echo \"overlay\" > /etc/modules-load.d/k8s.conf
        echo \"br_netfilter\" >> /etc/modules-load.d/k8s.conf
        echo \"nf_conntrack\" >> /etc/modules-load.d/k8s.conf

        cat <<EOF >/etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
        sysctl --system

        VERSION=\$(curl -sL https://dl.k8s.io/release/stable.txt)
        ARCH=\$(uname -m | sed \"s/x86_64/amd64/;s/aarch64/arm64/\")
        curl -L --remote-name-all https://dl.k8s.io/\$VERSION/bin/linux/\$ARCH/{kubeadm,kubelet,kubectl}
        chmod +x kubeadm kubelet kubectl
        mv kubeadm kubelet kubectl /usr/local/bin/

        systemctl daemon-reload
        systemctl restart containerd
        systemctl enable --now kubelet

        echo \"✔️ Node prepared: $HOST\"
      '"
}
