prepare_flannel_host_paths() {
  echo "Creating required host paths for Flannel..."
  sudo_if_needed mkdir -p /opt/cni/bin
  sudo_if_needed mkdir -p /etc/cni/net.d
  sudo_if_needed mkdir -p /run/flannel

  sudo_if_needed chmod 755 /opt/cni/bin
  sudo_if_needed chmod 755 /etc/cni/net.d
  sudo_if_needed chmod 755 /run/flannel
}

