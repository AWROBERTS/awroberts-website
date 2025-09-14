setup_kubernetes_networking() {
  if [[ -n "${SYSCTL_ALREADY_APPLIED:-}" ]]; then return; fi

  sudo_if_needed modprobe br_netfilter >/dev/null 2>&1 || true
  echo 'br_netfilter' | sudo_if_needed tee /etc/modules-load.d/br_netfilter.conf >/dev/null 2>&1

  sudo_if_needed tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

  export SYSCTL_ALREADY_APPLIED=true
  echo "🔧 Ensuring br_netfilter and sysctl settings for Kubernetes networking..."
  echo "✅ Networking config applied."
}
