#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Control Plane Bootstrap Wrapper
# ============================================================================
# This wrapper orchestrates the entire control-plane setup using the new
# module-based architecture:
#
#   1. Load shared environment + helpers
#   2. Run node preflight
#   3. Install + configure containerd
#   4. Install + configure kubeadm/kubelet/kubectl
#   5. Bootstrap cluster if needed (kubeadm init)
#   6. Install + validate networking (Cilium)
#   7. Deploy application images + Helm charts
#
# This replaces ALL old control-plane scripts under functions/.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_PLANE_ROOT="${SCRIPT_DIR}"
SCRIPTS_ROOT="${CONTROL_PLANE_ROOT}/.."
MODULES_DIR="${SCRIPTS_ROOT}/modules"
SHARED_DIR="${SCRIPTS_ROOT}/shared"

# Shared helpers
source "${SHARED_DIR}/sudo-if-needed.sh"
source "${SHARED_DIR}/load-env-file.sh"

# Modules
source "${MODULES_DIR}/node-preflight.sh"
source "${MODULES_DIR}/containerd.sh"
source "${MODULES_DIR}/kube-tools.sh"
source "${MODULES_DIR}/cluster-bootstrap.sh"
source "${MODULES_DIR}/networking.sh"
source "${MODULES_DIR}/image-deploy.sh"

# ----------------------------------------------------------------------------
# Control-plane orchestration
# ----------------------------------------------------------------------------
bootstrap_control_plane() {
  echo "=== [1] Loading environment ==="
  load_env_file

  echo "=== [2] Node preflight ==="
  prepare_node

  echo "=== [3] Containerd setup ==="
  setup_containerd

  echo "=== [4] Kubernetes tools setup ==="
  setup_kube_tools

  echo "=== [5] Cluster bootstrap ==="
  bootstrap_cluster_if_needed

  echo "=== [6] Networking setup ==="
  setup_networking

  echo "=== [7] Image deployment ==="
  deploy_images

  echo "=== Control-plane bootstrap complete ==="
}

# ----------------------------------------------------------------------------
# Main entrypoint
# ----------------------------------------------------------------------------
main() {
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    echo "Cluster already bootstrapped. Skipping control-plane bootstrap."
    return 0
  fi

  bootstrap_control_plane
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
