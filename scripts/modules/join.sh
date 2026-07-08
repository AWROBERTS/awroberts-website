#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Worker Join Module
# ============================================================================
# Handles worker node join logic:
#   - retrieves join command from control-plane
#   - executes join command
#   - validates join success
#
# Replaces:
#   - get-join-command.sh
#   - join-worker-nodes.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

source "${SHARED_DIR}/sudo-if-needed.sh"
source "${SHARED_DIR}/load-env-file.sh"

# ----------------------------------------------------------------------------
# Retrieve join command from control-plane
# ----------------------------------------------------------------------------
get_join_command() {
  echo "Retrieving join command from control-plane..."

  kubectl -n kube-system get secret kubeadm-token-*/token \
    -o go-template='{{.data.token | base64decode}}' >/dev/null 2>&1 || true

  kubeadm token create --print-join-command
}

# ----------------------------------------------------------------------------
# Execute join command
# ----------------------------------------------------------------------------
execute_join() {
  local join_cmd="$1"

  echo "Executing join command..."
  sudo_if_needed bash -c "${join_cmd}"
}

# ----------------------------------------------------------------------------
# Validate join success
# ----------------------------------------------------------------------------
validate_join() {
  echo "Validating worker join..."

  if kubectl get nodes "$(hostname)" 2>/dev/null | grep -q " Ready "; then
    echo "Worker node successfully joined."
  else
    echo "ERROR: Worker node did not join successfully."
    exit 1
  fi
}

# ----------------------------------------------------------------------------
# Wrapper: full join flow
# ----------------------------------------------------------------------------
join_worker() {
  local join_cmd
  join_cmd="$(get_join_command)"
  execute_join "${join_cmd}"
  validate_join
}

# ----------------------------------------------------------------------------
# Main entrypoint
# ----------------------------------------------------------------------------
main() {
  load_env_file
  join_worker
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
