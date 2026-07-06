configure_containerd() {
  echo "Ensuring containerd uses systemd cgroups and CRI..."

  sudo_if_needed mkdir -p /etc/containerd

  # Generate default config if missing
  if ! sudo_if_needed test -f /etc/containerd/config.toml; then
    containerd config default | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
  fi

  # Flip SystemdCgroup = true everywhere it appears
  sudo_if_needed sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true

  # Ensure CRI plugin is enabled (Debian requires this explicitly)
  if grep -q '

\[plugins."io.containerd.grpc.v1.cri"\]

' /etc/containerd/config.toml; then
    sudo_if_needed sed -i 's/enable_cri = false/enable_cri = true/' /etc/containerd/config.toml || true
  else
    # Append CRI block if missing
    cat <<EOF | sudo_if_needed tee -a /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri"]
  enable_cri = true
  systemd_cgroup = true
EOF
  fi

  sudo_if_needed systemctl enable --now containerd
  sudo_if_needed systemctl restart containerd
}
