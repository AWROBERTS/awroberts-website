disable_swap_and_configure_sysctls() {
  echo "Disabling swap and updating /etc/fstab..."
  sudo_if_needed swapoff -a || true
  [[ -f /etc/fstab ]] && sudo_if_needed sed -i.bak -E 's@^([^#].*\s+swap\s+)@#\1@' /etc/fstab || true

  echo "Ensuring br_netfilter kernel module is loaded"
  sudo_if_needed modprobe br_netfilter || true
  echo 'br_netfilter' | sudo_if_needed tee /etc/modules-load.d/br_netfilter.conf >/dev/null

  echo "Configuring kernel sysctls for bridged traffic and forwarding..."
  sudo_if_needed tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
  sudo_if_needed sysctl --system >/dev/null
}
