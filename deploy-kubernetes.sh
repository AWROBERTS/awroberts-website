#!/usr/bin/env bash
set -euo pipefail

# Try the most robust way to always get project root (will work even if sh is the shell)
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

echo "PROJECT_ROOT: $PROJECT_ROOT"

source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/cluster.sh"
source "${PROJECT_ROOT}/scripts/image.sh"
source "${PROJECT_ROOT}/scripts/deploy.sh"
source "${PROJECT_ROOT}/scripts/saddleworth-nginx.sh"

main() {
  setup_kubernetes_networking
  cluster_targeting
  preflight_core_tools
  ensure_k8s_and_containerd_installed
  bootstrap_cluster_if_needed
  info_and_validate_context
  ensure_containerd_config
  verify_kubelet_cgroup
  ensure_ingress_admission_secret
  ensure_ingress_nginx
  saddleworth_nginx
  build_image
  import_image
  deploy_with_helm
  notes_and_status
}

main "$@"