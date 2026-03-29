setup_kubernetes_networking() {
  # Version marker for idempotency and controlled updates
  SYSCTL_VERSION="v2"
  SYSCTL_FILE="/etc/sysctl.d/99-kubernetes-cri.conf"
  INVALID_OVERRIDE_FILE="/etc/sysctl.d/99-kubernetes-disable-invalid.conf"

  # If the sysctl file exists AND contains the correct version marker, skip reapplying
  if [[ -f "$SYSCTL_FILE" ]] && grep -q "kubernetes-sysctl-$SYSCTL_VERSION" "$SYSCTL_FILE"; then
    echo "🔁 Kubernetes networking already configured. Skipping."
    return
  fi

  echo "🔧 Ensuring br_netfilter and sysctl settings for Kubernetes networking..."

  # Load br_netfilter module if not already loaded
  if ! lsmod | grep -q '^br_netfilter'; then
    sudo modprobe br_netfilter >/dev/null 2>&1 || true
    echo 'br_netfilter' | sudo tee /etc/modules-load.d/br_netfilter.conf >/dev/null
  fi

  # Write Kubernetes-required sysctls with version marker
  sudo tee "$SYSCTL_FILE" >/dev/null <<EOF
# kubernetes-sysctl-$SYSCTL_VERSION
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

  # Override invalid legacy sysctl keys without modifying system files
  sudo tee "$INVALID_OVERRIDE_FILE" >/dev/null <<EOF
# Disable invalid legacy sysctl keys
net.ipv4.conf.all.accept_source_route =
net.ipv4.conf.all.promote_secondaries =
net.ipv4.conf.*.accept_source_route =
net.ipv4.conf.*.promote_secondaries =
EOF

  echo "🔁 Reloading sysctl settings..."
  sudo sysctl --system

  echo "✅ Kubernetes networking sysctls applied successfully."
}
