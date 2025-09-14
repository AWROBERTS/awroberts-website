cleanup_old_cni_configs() {
  echo "Cleaning up old CNI configs..."
  sudo_if_needed rm -f /etc/cni/net.d/*.conf /etc/cni/net.d/*.conflist
}
