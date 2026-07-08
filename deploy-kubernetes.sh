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
SHARED_DIR="${SCRIPT_DIR}/shared"
MODULES_DIR="${SCRIPT_DIR}/modules"
CONTROL_PLANE_DIR="${SCRIPT_DIR}/control-plane"
WORKER_DIR="${SCRIPT_DIR}/worker"

source "${SHARED_DIR}/load-env-file.sh"
source "${SHARED_DIR}/sudo-if-needed.sh"

# ----------------------------------------------------------------------------
# Sync scripts to control-plane
# ----------------------------------------------------------------------------
sync_to_control_plane() {
  echo "=== Syncing scripts to control-plane (${CONTROL_PLANE_HOST}) ==="

  rsync -avz \
    "${MODULES_DIR}" \
    "${SHARED_DIR}" \
    "${CONTROL_PLANE_DIR}" \
    "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}:~/scripts/"
}

# ----------------------------------------------------------------------------
# Sync scripts to worker
# ----------------------------------------------------------------------------
sync_to_worker() {
  echo "=== Syncing scripts to worker (${WORKER_HOST}) ==="

  rsync -avz \
    "${MODULES_DIR}" \
    "${SHARED_DIR}" \
    "${WORKER_DIR}" \
    "${WORKER_USER}@${WORKER_HOST}:~/scripts/"
}

# ----------------------------------------------------------------------------
# Run control-plane bootstrap
# ----------------------------------------------------------------------------
run_control_plane() {
  echo "=== Running control-plane bootstrap ==="

  ssh "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}" \
    "bash ~/scripts/control-plane/bootstrap.sh"
}

# ----------------------------------------------------------------------------
# Run worker bootstrap
# ----------------------------------------------------------------------------
run_worker() {
  echo "=== Running worker bootstrap ==="

  ssh "${WORKER_USER}@${WORKER_HOST}" \
    "bash ~/scripts/worker/bootstrap.sh"
}

# ----------------------------------------------------------------------------
# Main orchestration
# ----------------------------------------------------------------------------
main() {
  echo "=== Loading environment ==="
  load_env_file

  sync_to_control_plane
  sync_to_worker

  run_control_plane
  run_worker

  echo "=== Deployment complete ==="
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
