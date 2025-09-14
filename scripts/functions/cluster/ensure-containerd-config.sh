ensure_containerd_config() {
  echo "Ensuring containerd config exists and uses systemd cgroups..."
  sudo_if_needed mkdir -p /etc/containerd
  if ! sudo_if_needed test -f /etc/containerd/config.toml; then
    containerd config default | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
  fi
  sudo_if_needed sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
  # Ensure CRI pause image matches kubeadm v1.30 recommendation (3.9)
  if grep -q 'sandbox_image' /etc/containerd/config.toml; then
    sudo_if_needed sed -i 's#sandbox_image = ".*"#sandbox_image = "registry.k8s.io/pause:3.9"#' /etc/containerd/config.toml || true
  else
    sudo_if_needed awk '1;/\[plugins\."io.containerd.grpc.v1.cri"\]/{print "  sandbox_image = \"registry.k8s.io/pause:3.9\""}' /etc/containerd/config.toml \
      | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
  fi
  sudo_if_needed systemctl enable --now containerd
  sudo_if_needed systemctl restart containerd
  sudo_if_needed ctr -n k8s.io images ls >/dev/null 2>&1 || true
}