#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Kubernetes Deployment Orchestrator (Module Architecture)
# ============================================================================
# This script loads environment variables, ensures the worker VM and runtime
# services are active, runs control-plane and worker bootstrap scripts, and
# syncs necessary modules and kubeconfigs.
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

provision_worker_vm() {
  echo "=== Provisioning worker VM (autoinstall) ==="
  bash "${WORKER_DIR}/provision-worker-vm.sh"
}

ensure_worker_ready_if_joined() {
  if ssh "${WORKER_USER}@${WORKER_HOST}" "test -f /etc/kubernetes/kubelet.conf"; then
    echo "=== Worker already joined — ensuring containerd and kubelet are active ==="
    ssh "${WORKER_USER}@${WORKER_HOST}" \
      "echo '${WORKER_PASSWORD}' | sudo -S systemctl enable --now containerd kubelet"

    echo "=== Waiting for worker node to report Ready ==="
    ssh "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}" \
      "kubectl wait --for=condition=Ready node/${WORKER_HOST} --timeout=60s"
  fi
}

sync_to_worker() {
  echo "=== Syncing scripts to worker (${WORKER_HOST}) ==="
  ssh "${WORKER_USER}@${WORKER_HOST}" \
    "echo '${WORKER_PASSWORD}' | sudo -S mkdir -p /var/www/html/awroberts/scripts && \
     echo '${WORKER_PASSWORD}' | sudo -S chown -R ${WORKER_USER}:${WORKER_USER} /var/www/html/awroberts"

  rsync -avz "${MODULES_DIR}" "${SHARED_DIR}" "${WORKER_DIR}" "${WORKER_USER}@${WORKER_HOST}:/var/www/html/awroberts/scripts/"
  rsync -avz "${PROJECT_ROOT}/awroberts-cluster.env" "${PROJECT_ROOT}/awroberts-control-plane.env" "${WORKER_USER}@${WORKER_HOST}:/var/www/html/awroberts/"
}

sync_kubeconfig_to_worker() {
  echo "=== Syncing kubeconfig to worker (${WORKER_HOST}) ==="
  [[ ! -f "${PROJECT_ROOT}/admin.conf" ]] && { echo "ERROR: admin.conf not found."; exit 1; }

  ssh "${WORKER_USER}@${WORKER_HOST}" "mkdir -p /home/${WORKER_USER}/.kube"
  scp "${PROJECT_ROOT}/admin.conf" "${WORKER_USER}@${WORKER_HOST}:/home/${WORKER_USER}/.kube/config"
  ssh "${WORKER_USER}@${WORKER_HOST}" "echo '${WORKER_PASSWORD}' | sudo -S chmod 600 /home/${WORKER_USER}/.kube/config"
}

run_control_plane() {
  echo "=== Running control-plane bootstrap ==="
  ssh -tt "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}" "bash /var/www/html/awroberts/scripts/control-plane/bootstrap.sh"
}

run_worker() {
  echo "=== Running worker bootstrap ==="
  ssh -tt "${WORKER_USER}@${WORKER_HOST}" "bash /var/www/html/awroberts/scripts/worker/bootstrap.sh"
}

worker_is_reachable() {
  ping -c 1 -W 1 "${WORKER_HOST}" >/dev/null 2>&1
}

main() {
  load_env_file
  MAC_IP=$(getent hosts "$MAC_HOST" | awk '{print $1}')
  sudo ip route replace "${WORKER_IP%.*}.0/24" via "$MAC_IP" dev enp1s0

  if worker_is_reachable; then
    echo "Worker VM reachable at ${WORKER_HOST} — skipping provisioning."
  else
    provision_worker_vm
  fi

  ensure_worker_ready_if_joined
  run_control_plane

  echo "=== Syncing kubeconfig from control-plane ==="
  ssh "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}" "sudo cat /etc/kubernetes/admin.conf" > "${PROJECT_ROOT}/admin.conf"
  [[ ! -f "${PROJECT_ROOT}/admin.conf" ]] && { echo "ERROR: Failed to retrieve admin.conf."; exit 1; }

  sync_to_worker
  sync_kubeconfig_to_worker
  run_worker
  echo "=== Deployment complete ==="
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
