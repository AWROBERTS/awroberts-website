verify_kubelet_cgroup() {
  if [[ -f /var/lib/kubelet/config.yaml ]]; then
    if ! grep -q '^cgroupDriver: systemd' /var/lib/kubelet/config.yaml; then
      echo "Warning: kubelet cgroupDriver is not 'systemd'. With containerd, 'systemd' is recommended."
      if [[ "${AUTO_FIX_KUBELET_CGROUP:-true}" == "true" ]]; then
        echo "Setting kubelet cgroupDriver to systemd and restarting kubelet..."
        if grep -q '^cgroupDriver:' /var/lib/kubelet/config.yaml; then
          sudo_if_needed sed -i -E 's/^cgroupDriver: .*/cgroupDriver: systemd/' /var/lib/kubelet/config.yaml || true
        else
          echo "cgroupDriver: systemd" | sudo_if_needed tee -a /var/lib/kubelet/config.yaml >/dev/null
        fi
        sudo_if_needed systemctl restart kubelet || true
      fi
    fi
  fi
}