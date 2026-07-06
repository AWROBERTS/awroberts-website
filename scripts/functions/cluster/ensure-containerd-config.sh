ensure_containerd_config() {
  echo "Ensuring containerd config exists, uses systemd cgroups, and CRI is enabled..."

  sudo_if_needed mkdir -p /etc/containerd

  # Generate default config if missing
  if ! sudo_if_needed test -f /etc/containerd/config.toml; then
    containerd config default | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
  fi

  # Flip SystemdCgroup = true everywhere it appears
  sudo_if_needed sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true

  # Ensure CRI plugin is enabled
  if grep -q '

\[plugins."io.containerd.grpc.v1.cri"\]

' /etc/containerd/config.toml; then
    sudo_if_needed sed -i 's/enable_cri = false/enable_cri = true/' /etc/containerd/config.toml || true
  else
    cat <<EOF | sudo_if_needed tee -a /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri"]
  enable_cri = true
  systemd_cgroup = true
EOF
  fi

  # Ensure pause image matches kubeadm recommendation
  if grep -q 'sandbox_image' /etc/containerd/config.toml; then
    sudo_if_needed sed -i 's#sandbox_image = ".*"#sandbox_image = "registry.k8s.io/pause:3.9"#' /etc/containerd/config.toml || true
  else
    sudo_if_needed awk '1;/

\[plugins\."io.containerd.grpc.v1.cri"\]

/{print "  sandbox_image = \"registry.k8s.io/pause:3.9\""}' \
      /etc/containerd/config.toml | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
  fi

  sudo_if_needed systemctl enable --now containerd
  sudo_if_needed systemctl restart containerd

  # Warm CRI namespace (harmless if empty)
  sudo_if_needed ctr -n k8s.io images ls >/dev/null 2>&1 || true
}
