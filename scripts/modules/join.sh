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
  # stderr: stdout is captured as the join command and executed.
  echo "Retrieving join command from control-plane..." >&2

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
  echo "Validating worker join (waiting for node to become Ready)..."

  # A freshly joined node stays NotReady until the CNI agent is running on it.
  if kubectl wait --for=condition=Ready "node/$(hostname)" --timeout=300s; then
    echo "Worker node successfully joined."
  else
    echo "ERROR: Worker node did not become Ready within 5 minutes."
    kubectl get node "$(hostname)" -o wide 2>/dev/null || true
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
