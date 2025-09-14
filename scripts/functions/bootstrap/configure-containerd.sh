configure_containerd() {
  echo "Ensuring containerd uses systemd cgroups..."
  sudo_if_needed mkdir -p /etc/containerd
  if ! sudo_if_needed test -f /etc/containerd/config.toml; then
    containerd config default | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
  fi
  sudo_if_needed sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
  sudo_if_needed systemctl enable --now containerd
  sudo_if_needed systemctl restart containerd
}
