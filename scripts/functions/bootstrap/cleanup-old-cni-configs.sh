cleanup_old_cni_configs() {
  echo "Cleaning up old CNI configs (preserving Flannel)..."
  sudo_if_needed find /etc/cni/net.d -type f ! -name "10-flannel.conflist" -delete
}
