setup_kubernetes_networking() {
  if [[ -n "${SYSCTL_ALREADY_APPLIED:-}" ]]; then
    echo "🔁 Kubernetes networking already configured. Skipping."
    return
  fi

  echo "🔧 Ensuring br_netfilter and sysctl settings for Kubernetes networking..."

  # Load br_netfilter module
  if ! lsmod | grep -q '^br_netfilter'; then
    sudo modprobe br_netfilter >/dev/null 2>&1 || true
    echo 'br_netfilter' | sudo tee /etc/modules-load.d/br_netfilter.conf >/dev/null
  fi

  # Apply required sysctls
  sudo tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<EOF
# Applied by setup_kubernetes_networking on $(date)
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

  # Remove any leftover invalid override file
  sudo rm -f /etc/sysctl.d/99-disable-invalid.conf

  # Comment out invalid and wildcard sysctl keys if config file exists
  SYSCTL_DEFAULT_CONF="/usr/lib/sysctl.d/50-default.conf"
  if [[ -f "$SYSCTL_DEFAULT_CONF" ]]; then
    echo "🧹 Sanitizing invalid sysctl keys in $SYSCTL_DEFAULT_CONF..."
    sudo sed -i 's/^\(net\.ipv4\.conf\.all\.accept_source_route\)/# \1/' "$SYSCTL_DEFAULT_CONF"
    sudo sed -i 's/^\(net\.ipv4\.conf\.all\.promote_secondaries\)/# \1/' "$SYSCTL_DEFAULT_CONF"
    sudo sed -i 's/^\(net\.ipv4\.conf\.\*\.accept_source_route\)/# \1/' "$SYSCTL_DEFAULT_CONF"
    sudo sed -i 's/^\(net\.ipv4\.conf\.\*\.promote_secondaries\)/# \1/' "$SYSCTL_DEFAULT_CONF"
  else
    echo "⚠️ Default sysctl config not found at $SYSCTL_DEFAULT_CONF. Skipping invalid key suppression."
  fi

  # Reload sysctl settings and filter out known warnings
  echo "🔁 Reloading sysctl settings..."
  sudo sysctl --system 2>&1 | grep -v 'Invalid argument'

  export SYSCTL_ALREADY_APPLIED=true
  echo "✅ Kubernetes networking sysctls applied successfully."
}
