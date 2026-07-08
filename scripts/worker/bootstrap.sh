#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Worker Bootstrap Wrapper
# ============================================================================
# This wrapper orchestrates the entire worker node setup using the new
# module-based architecture:
#
#   1. Load shared environment + helpers
#   2. Run node preflight
#   3. Install + configure containerd
#   4. Install + configure kubeadm/kubelet/kubectl
#   5. Validate cluster access
#   6. Join worker to cluster
#
# This replaces ALL old worker scripts under functions/.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/../modules"
SHARED_DIR="${SCRIPT_DIR}/../shared"

# Shared helpers
source "${SHARED_DIR}/sudo-if-needed.sh"
source "${SHARED_DIR}/load-env-file.sh"

# Modules
source "${MODULES_DIR}/node-preflight.sh"
source "${MODULES_DIR}/containerd.sh"
source "${MODULES_DIR}/kube-tools.sh"
source "${MODULES_DIR}/cluster-access.sh"
source "${MODULES_DIR}/join.sh"

# ----------------------------------------------------------------------------
# Worker orchestration
# ----------------------------------------------------------------------------
bootstrap_worker() {
  echo "=== [1] Loading environment ==="
  load_env_file

  echo "=== [2] Node preflight ==="
  prepare_node

  echo "=== [3] Containerd setup ==="
  setup_containerd

  echo "=== [4] Kubernetes tools setup ==="
  setup_kube_tools

  echo "=== [5] Validating cluster access ==="
  ensure_cluster_access

  echo "=== [6] Joining worker to cluster ==="
  join_worker

  echo "=== Worker bootstrap complete ==="
}

# ----------------------------------------------------------------------------
# Main entrypoint
# ----------------------------------------------------------------------------
main() {
  bootstrap_worker
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
