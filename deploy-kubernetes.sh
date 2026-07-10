#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Kubernetes Deployment Orchestrator (Module Architecture)
# ============================================================================
# This script:
#   1. Loads environment variables
#   2. Syncs modules + shared + wrappers to both nodes
#   3. Runs control-plane bootstrap
#   4. Runs worker bootstrap
#
# This replaces ALL old deploy logic that referenced functions/.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="${SCRIPT_DIR}/scripts"

SHARED_DIR="${SCRIPTS_ROOT}/shared"
MODULES_DIR="${SCRIPTS_ROOT}/modules"
CONTROL_PLANE_DIR="${SCRIPTS_ROOT}/control-plane"
WORKER_DIR="${SCRIPTS_ROOT}/worker"

source "${SHARED_DIR}/load-env-file.sh"
source "${SHARED_DIR}/sudo-if-needed.sh"

# ----------------------------------------------------------------------------
# Phase 2: Provision worker VM (autoinstall)
# ----------------------------------------------------------------------------
provision_worker_vm() {
  echo "=== Provisioning worker VM (autoinstall) ==="
  bash "${WORKER_DIR}/provision-worker-vm.sh"
}

# ----------------------------------------------------------------------------
# Sync scripts to worker
# ----------------------------------------------------------------------------
sync_to_worker() {
  echo "=== Syncing scripts to worker (${WORKER_HOST}) ==="

  # Ensure remote directory exists and is owned by the correct user
  ssh "${WORKER_USER}@${WORKER_HOST}" \
    "sudo mkdir -p /var/www/html/awroberts/scripts && sudo chown ${WORKER_USER}:${WORKER_USER} /var/www/html/awroberts/scripts"

  rsync -avz \
    "${MODULES_DIR}" \
    "${SHARED_DIR}" \
    "${WORKER_DIR}" \
    "${WORKER_USER}@${WORKER_HOST}:/var/www/html/awroberts/scripts/"
}

# ----------------------------------------------------------------------------
# Run control-plane bootstrap
# ----------------------------------------------------------------------------
run_control_plane() {
  echo "=== Running control-plane bootstrap ==="

  ssh "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}" \
    "bash /var/www/html/awroberts/scripts/control-plane/bootstrap.sh"
}

# ----------------------------------------------------------------------------
# Run worker bootstrap
# ----------------------------------------------------------------------------
run_worker() {
  echo "=== Running worker bootstrap ==="

  ssh "${WORKER_USER}@${WORKER_HOST}" \
    "bash /var/www/html/awroberts/scripts/worker/bootstrap.sh"
}

# ----------------------------------------------------------------------------
# Main orchestration
# ----------------------------------------------------------------------------
main() {
  echo "=== Loading environment ==="

  load_env_file
  provision_worker_vm
  sync_to_worker
  run_control_plane
  run_worker

  echo "=== Deployment complete ==="
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
