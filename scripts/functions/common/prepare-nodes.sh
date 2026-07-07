prepare_node() {
  echo "🧱 Preparing all Kubernetes nodes..."

  VERSION="$(curl -sL https://dl.k8s.io/release/stable.txt)"

  for NODE in $(kubectl get nodes -o name | sed 's/node\///'); do
    echo "🔧 Preparing node: $NODE"

    kubectl debug node/$NODE -it --image=busybox -- chroot /host sh -c "
      set -e

      echo '📦 Detecting architecture...'
      ARCH=\$(uname -m)
      case \"\$ARCH\" in
        x86_64) K8S_ARCH=amd64 ;;
        aarch64|arm64) K8S_ARCH=arm64 ;;
        *) echo '❌ Unsupported architecture'; exit 1 ;;
      esac
      echo \"   → Architecture: \$K8S_ARCH\"

      echo '📦 Installing containerd if missing...'
      if ! command -v containerd >/dev/null 2>&1; then
        apt-get update
        apt-get install -y containerd
      fi

      echo '🔧 Configuring containerd (systemd cgroups)...'
      mkdir -p /etc/containerd
      containerd config default > /etc/containerd/config.toml
      sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
      systemctl restart containerd

      echo '📦 Installing crictl...'
      CRI_VERSION=v1.30.0
      curl -sLO https://github.com/kubernetes-sigs/cri-tools/releases/download/\$CRI_VERSION/crictl-\$CRI_VERSION-linux-\$K8S_ARCH.tar.gz
      tar zxvf crictl-\$CRI_VERSION-linux-\$K8S_ARCH.tar.gz -C /usr/local/bin
      rm crictl-\$CRI_VERSION-linux-\$K8S_ARCH.tar.gz

      echo '🔧 Disabling swap...'
      swapoff -a
      sed -i '/swap/d' /etc/fstab

      echo '🔧 Loading kernel modules...'
      modprobe overlay || true
      modprobe br_netfilter || true
      modprobe nf_conntrack || true

      echo 'overlay' > /etc/modules-load.d/k8s.conf
      echo 'br_netfilter' >> /etc/modules-load.d/k8s.conf
      echo 'nf_conntrack' >> /etc/modules-load.d/k8s.conf

      echo '🔧 Applying sysctls...'
      cat <<EOF >/etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
      sysctl --system

      echo '📁 Ensuring CNI directories exist...'
      mkdir -p /opt/cni/bin
      mkdir -p /etc/cni/net.d

      echo '⬇️ Installing kubeadm, kubelet, kubectl for \$K8S_ARCH...'
      curl -L --remote-name-all https://dl.k8s.io/\$VERSION/bin/linux/\$K8S_ARCH/{kubeadm,kubelet,kubectl}
      chmod +x kubeadm kubelet kubectl
      mv kubeadm kubelet kubectl /usr/local/bin/

      echo '🔧 Writing kubelet systemd units...'
      mkdir -p /etc/systemd/system/kubelet.service.d

      cat <<EOF >/etc/systemd/system/kubelet.service
[Unit]
Description=kubelet: The Kubernetes Node Agent
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/kubelet
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

      cat <<EOF >/etc/systemd/system/kubelet.service.d/10-kubeadm.conf
[Service]
Environment=\"KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf\"
Environment=\"KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml\"
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/local/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
EOF

      echo '🔧 Restarting containerd + kubelet...'
      systemctl daemon-reload
      systemctl restart containerd
      systemctl enable --now kubelet

      echo '🔍 Verifying runtime health...'
      crictl info >/dev/null || { echo '❌ crictl cannot talk to containerd'; exit 1; }
      echo '   → Runtime OK'
    "

    echo "✔️ Node $NODE prepared successfully."
  done

  echo "🎉 All nodes fully prepared."
}
