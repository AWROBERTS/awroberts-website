#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Kubernetes Tools Module
# ============================================================================
# Installs and configures Kubernetes components:
#   - kubeadm
#   - kubelet
#   - kubectl
#
# Also:
#   - configures kubelet to use systemd cgroups
#   - validates kubelet runtime
#   - configures kubeconfig for control-plane nodes
#
# Replaces:
#   - ensure-k8s-and-containerd-installed.sh
#   - verify-kubelet-cgroup.sh
#   - configure-kubeconfig.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

source "${SHARED_DIR}/sudo-if-needed.sh"
source "${SHARED_DIR}/load-env-file.sh"

# ----------------------------------------------------------------------------
# Install Kubernetes packages
# ----------------------------------------------------------------------------
install_kube_tools() {
  sudo_if_needed apt-get update -y

  sudo_if_needed apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl

  sudo_if_needed curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
    https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list

  sudo_if_needed apt-get update -y

  sudo_if_needed apt-get install -y \
    kubelet \
    kubeadm \
    kubectl

  sudo_if_needed systemctl enable kubelet
}

# ----------------------------------------------------------------------------
# Configure kubelet (systemd cgroups)
# ----------------------------------------------------------------------------
configure_kubelet() {
  sudo_if_needed mkdir -p /etc/systemd/system/kubelet.service.d

  sudo_if_needed tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf >/dev/null <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=systemd"
EOF

  sudo_if_needed systemctl daemon-reload
  sudo_if_needed systemctl restart kubelet
}

# ----------------------------------------------------------------------------
# Validate kubelet runtime
# ----------------------------------------------------------------------------
validate_kubelet_runtime() {
  echo "Validating kubelet runtime..."

  if ! sudo_if_needed systemctl is-active --quiet kubelet; then
    echo "ERROR: kubelet is not running."
    exit 1
  fi

  echo "kubelet is active."
}

# ----------------------------------------------------------------------------
# Configure kubeconfig (control-plane only)
# ----------------------------------------------------------------------------
configure_kubeconfig() {
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    mkdir -p "$HOME/.kube"
    sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  fi
}

# ----------------------------------------------------------------------------
# Wrapper: install + configure + validate
# ----------------------------------------------------------------------------
setup_kube_tools() {
  install_kube_tools
  configure_kubelet
  validate_kubelet_runtime
}

# ----------------------------------------------------------------------------
# Main entrypoint (optional)
# ----------------------------------------------------------------------------
main() {
  load_env_file
  setup_kube_tools
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
