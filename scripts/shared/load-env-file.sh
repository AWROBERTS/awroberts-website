#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Environment Loader (hostname-based)
# ============================================================================
# Loads:
#   - awroberts-cluster.env on ALL nodes
#   - awroberts-control-plane.env ONLY on hostname "awr"
#
# This avoids unbound variables, avoids hostname mismatches,
# and works identically on local + remote nodes.
# ============================================================================

load_env_file() {
  # Determine where this script lives
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # PROJECT_ROOT is one level above /scripts
  local PROJECT_ROOT="${SCRIPT_DIR}/../.."

  # Env file paths
  local CLUSTER_ENV="${PROJECT_ROOT}/awroberts-cluster.env"
  local CONTROL_PLANE_ENV="${PROJECT_ROOT}/awroberts-control-plane.env"

  # Load cluster env (always required)
  if [[ ! -f "${CLUSTER_ENV}" ]]; then
    echo "❌ Cluster environment file not found: ${CLUSTER_ENV}"
    exit 1
  fi

  echo "📦 Loading cluster environment variables from: ${CLUSTER_ENV}"
  set -a
  source "${CLUSTER_ENV}"
  set +a

  # Load control-plane env only on hostname "awr"
  if [[ "$(hostname)" == "awr" ]]; then
    if [[ ! -f "${CONTROL_PLANE_ENV}" ]]; then
      echo "❌ Control-plane environment file not found: ${CONTROL_PLANE_ENV}"
      exit 1
    fi

    echo "📦 Loading control-plane environment variables from: ${CONTROL_PLANE_ENV}"
    set -a
    source "${CONTROL_PLANE_ENV}"
    set +a
  fi
}
