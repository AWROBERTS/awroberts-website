prepare_flannel_host_paths() {
  echo "Creating required host paths for Flannel..."
  sudo_if_needed mkdir -p /opt/cni/bin /etc/cni/net.d /run/flannel
  sudo_if_needed chmod 755 /etc/cni/net.d /run/flannel
}
