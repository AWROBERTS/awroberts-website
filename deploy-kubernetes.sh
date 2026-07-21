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
PROJECT_ROOT="${SCRIPT_DIR}"

SHARED_DIR="${SCRIPTS_ROOT}/shared"
MODULES_DIR="${SCRIPTS_ROOT}/modules"
CONTROL_PLANE_DIR="${SCRIPTS_ROOT}/control-plane"
WORKER_DIR="${SCRIPTS_ROOT}/worker"

source "${SHARED_DIR}/load-env-file.sh"
source "${SHARED_DIR}/sudo-if-needed.sh"

MAC_IP=$(getent hosts "$MAC_HOST" | awk '{print $1}')

echo "Ensuring route to worker VM network exists..."
WORKER_NET="${WORKER_HOST%.*}.0/24"
sudo ip route replace "$WORKER_NET" via "$MAC_IP" dev enp1s0

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

  # Sync environment files to worker
  rsync -avz \
    "${PROJECT_ROOT}/awroberts-cluster.env" \
    "${PROJECT_ROOT}/awroberts-control-plane.env" \
    "${WORKER_USER}@${WORKER_HOST}:/var/www/html/awroberts/"

}

sync_kubeconfig_to_worker() {
  echo "=== Syncing kubeconfig to worker (${WORKER_HOST}) ==="

  # Ensure .kube directory exists
  ssh "${WORKER_USER}@${WORKER_HOST}" "mkdir -p /home/${WORKER_USER}/.kube"

  # Copy control-plane kubeconfig
  scp "${PROJECT_ROOT}/admin.conf" \
      "${WORKER_USER}@${WORKER_HOST}:/home/${WORKER_USER}/.kube/config"

  # Fix permissions
  ssh "${WORKER_USER}@${WORKER_HOST}" "chmod 600 /home/${WORKER_USER}/.kube/config"
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
# Worker is reachable
# ----------------------------------------------------------------------------

worker_is_reachable() {
  ssh -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no \
      "${WORKER_USER}@${WORKER_HOST}" \
      "exit" >/dev/null 2>&1
}

# ----------------------------------------------------------------------------
# Main orchestration
# ----------------------------------------------------------------------------
main() {
  echo "=== Loading environment ==="
  load_env_file

  echo "=== Checking worker reachability (${WORKER_HOST}) ==="
  if worker_is_reachable; then
    echo "Worker VM reachable at ${WORKER_HOST} — skipping provisioning."
  else
    provision_worker_vm
  fi

  sync_to_worker
  sync_kubeconfig_to_worker
  run_control_plane
  run_worker

  echo "=== Deployment complete ==="
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
