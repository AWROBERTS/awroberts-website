#!/usr/bin/env bash
set -euo pipefail

# Try the most robust way to always get project root (will work even if sh is the shell)
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

echo "PROJECT_ROOT: $PROJECT_ROOT"

for file in "${PROJECT_ROOT}/scripts/functions/common/"*.sh; do
  source "$file"
done

main() {
  sudo_if_needed
  load_env_file
  setup_kubernetes_networking
  image_vars
  ensure_tls_secret
  preflight_core_tools
}

main "$@"