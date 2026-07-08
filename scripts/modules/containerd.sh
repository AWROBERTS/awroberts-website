#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Containerd Module
# ============================================================================
# This module installs and configures containerd:
#   - installs containerd from apt
#   - generates default config
#   - enables systemd cgroups
#   - restarts containerd cleanly
#
# Replaces:
#   - configure-containerd.sh
#   - ensure-containerd-config.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_ROOT="${SCRIPT_DIR}/.."
SHARED_DIR="${MODULES_ROOT}/shared"

source "${SHARED_DIR}/sudo-if-needed.sh"
source "${SHARED_DIR}/load-env-file.sh"

# ----------------------------------------------------------------------------
# Install containerd
# ----------------------------------------------------------------------------
install_containerd() {
  sudo_if_needed apt-get update -y
  sudo_if_needed apt-get install -y containerd
}

# ----------------------------------------------------------------------------
# Configure containerd (systemd cgroups)
# ----------------------------------------------------------------------------
configure_containerd() {
  sudo_if_needed mkdir -p /etc/containerd

  sudo_if_needed containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

  # Enable systemd cgroups
  sudo_if_needed sed -i \
    's/SystemdCgroup = false/SystemdCgroup = true/' \
    /etc/containerd/config.toml

  sudo_if_needed systemctl restart containerd
  sudo_if_needed systemctl enable containerd
}

# ----------------------------------------------------------------------------
# Wrapper: install + configure
# ----------------------------------------------------------------------------
setup_containerd() {
  install_containerd
  configure_containerd
}

# ----------------------------------------------------------------------------
# Main entrypoint
# ----------------------------------------------------------------------------
main() {
  load_env_file
  setup_containerd
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
