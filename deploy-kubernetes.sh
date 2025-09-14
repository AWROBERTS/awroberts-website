#!/usr/bin/env bash
set -euo pipefail

# Get project root
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
echo "PROJECT_ROOT: $PROJECT_ROOT"

# Load env loader first
for file in "${PROJECT_ROOT}/scripts/functions/env/"*.sh; do
  [[ "$file" == *load_env_file.sh ]] && continue  # Already sourced
  source "$file"
done
load_env_file  # Load .env variables before anything else

# Source common functions
COMMON_DIR="${PROJECT_ROOT}/scripts/functions/common"
if [ -d "$COMMON_DIR" ]; then
  for file in "$COMMON_DIR"/*.sh; do
    [[ "$file" == *load_env_file.sh ]] && continue
    [ -f "$file" ] && source "$file"
  done
else
  echo "Warning: common directory not found at $COMMON_DIR"
fi

# Source bootstrap functions
BOOTSTRAP_DIR="${PROJECT_ROOT}/scripts/functions/bootstrap"
if [ -d "$BOOTSTRAP_DIR" ]; then
  for file in "$BOOTSTRAP_DIR"/*.sh; do
    [ -f "$file" ] && source "$file"
  done
else
  echo "Warning: bootstrap directory not found at $BOOTSTRAP_DIR"
fi

main() {
  setup_kubernetes_networking
  image_vars
  ensure_tls_secret
  preflight_core_tools

  bootstrap_cluster_if_needed
}

main "$@"

