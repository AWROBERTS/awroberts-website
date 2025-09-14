setup_kubernetes_networking() {
  if [[ -n "${SYSCTL_ALREADY_APPLIED:-}" ]]; then
    echo "🔁 Kubernetes networking already configured. Skipping."
    return
  fi

  echo "🔧 Ensuring br_netfilter and sysctl settings for Kubernetes networking..."

  # Load br_netfilter module
  sudo modprobe br_netfilter >/dev/null 2>&1 || true
  echo 'br_netfilter' | sudo tee /etc/modules-load.d/br_netfilter.conf >/dev/null

  # Apply required sysctls
  sudo tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

  # Suppress deprecated sysctl warnings
  sudo tee /etc/sysctl.d/99-disable-invalid.conf >/dev/null <<EOF
# Suppress invalid sysctl keys from default config
net.ipv4.conf.all.accept_source_route =
net.ipv4.conf.all.promote_secondaries =
EOF

  # Reload sysctl settings
  sudo sysctl --system >/dev/null

  export SYSCTL_ALREADY_APPLIED=true

  echo "✅ Kubernetes networking sysctls applied successfully."
}
