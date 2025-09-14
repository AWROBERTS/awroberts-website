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

# Now source all other functions
for file in "${PROJECT_ROOT}/scripts/functions/common/"*.sh; do
  [[ "$file" == *load_env_file.sh ]] && continue  # Already sourced
  source "$file"
done

main() {
  sudo_if_needed
  setup_kubernetes_networking
  image_vars
  ensure_tls_secret
  preflight_core_tools
}

main "$@"
