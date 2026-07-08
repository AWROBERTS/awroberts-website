#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Cluster Access Module
# ============================================================================
# Centralises all logic related to:
#   - checking if the cluster API is reachable
#   - validating kubectl context
#   - determining the active target cluster
#
# Replaces:
#   - is-cluster-accessible.sh
#   - info-and-validate-context.sh
#   - cluster-targeting.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

source "${SHARED_DIR}/sudo-if-needed.sh"
source "${SHARED_DIR}/load-env-file.sh"

# ----------------------------------------------------------------------------
# Check if cluster API is reachable
# ----------------------------------------------------------------------------
is_cluster_accessible() {
  kubectl version --short >/dev/null 2>&1
}

# ----------------------------------------------------------------------------
# Validate kubectl context
# ----------------------------------------------------------------------------
validate_kubectl_context() {
  local context
  context="$(kubectl config current-context 2>/dev/null || true)"

  if [[ -z "${context}" ]]; then
    echo "ERROR: No kubectl context is set."
    return 1
  fi

  echo "kubectl context: ${context}"
  return 0
}

# ----------------------------------------------------------------------------
# Determine active cluster target (simple version)
# ----------------------------------------------------------------------------
get_cluster_target() {
  # In your env file you may define CLUSTER_NAME or similar.
  # If not, fall back to kubectl context.
  if [[ -n "${CLUSTER_NAME:-}" ]]; then
    echo "${CLUSTER_NAME}"
  else
    kubectl config current-context 2>/dev/null || echo "unknown"
  fi
}

# ----------------------------------------------------------------------------
# Wrapper: validate cluster access + context
# ----------------------------------------------------------------------------
ensure_cluster_access() {
  if ! validate_kubectl_context; then
    echo "kubectl context invalid."
    return 1
  fi

  if ! is_cluster_accessible; then
    echo "Cluster API is not reachable."
    return 1
  fi

  echo "Cluster API reachable and context valid."
  return 0
}

# ----------------------------------------------------------------------------
# Main entrypoint
# ----------------------------------------------------------------------------
main() {
  load_env_file
  ensure_cluster_access
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
