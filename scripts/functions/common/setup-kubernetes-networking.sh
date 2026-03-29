setup_kubernetes_networking() {
  if [[ -f /etc/sysctl.d/99-kubernetes-cri.conf ]]; then
    echo "🔁 Kubernetes networking already configured. Skipping."
    return
  fi

  echo "🔧 Ensuring br_netfilter and sysctl settings for Kubernetes networking..."

  # Load br_netfilter module
  if ! lsmod | grep -q '^br_netfilter'; then
    sudo modprobe br_netfilter >/dev/null 2>&1 || true
    echo 'br_netfilter' | sudo tee /etc/modules-load.d/br_netfilter.conf >/dev/null
  fi

  # Kubernetes-required sysctls
  sudo tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

  # Override invalid legacy keys without modifying system files
  sudo tee /etc/sysctl.d/99-kubernetes-disable-invalid.conf >/dev/null <<EOF
net.ipv4.conf.all.accept_source_route =
net.ipv4.conf.all.promote_secondaries =
net.ipv4.conf.*.accept_source_route =
net.ipv4.conf.*.promote_secondaries =
EOF

  echo "🔁 Reloading sysctl settings..."
  sudo sysctl --system

  echo "✅ Kubernetes networking sysctls applied successfully."
}
