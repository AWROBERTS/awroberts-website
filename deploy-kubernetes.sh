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

# Source cluster functions
CLUSTER_DIR="${PROJECT_ROOT}/scripts/functions/cluster"
if [ -d "$CLUSTER_DIR" ]; then
  for file in "$CLUSTER_DIR"/*.sh; do
    [ -f "$file" ] && source "$file"
  done
else
  echo "Warning: cluster directory not found at $CLUSTER_DIR"
fi

# Source image functions
IMAGE_DIR="${PROJECT_ROOT}/scripts/functions/image"
if [ -d "$IMAGE_DIR" ]; then
  for file in "$IMAGE_DIR"/*.sh; do
    [ -f "$file" ] && source "$file"
  done
else
  echo "Warning: image directory not found at $IMAGE_DIR"
fi

main() {
  setup_kubernetes_networking
  image_vars
  preflight_core_tools
  bootstrap_cluster_if_needed
  ensure_k8s_and_containerd_installed
  ensure_containerd_config
  verify_kubelet_cgroup
  cluster_targeting
  info_and_validate_context
  ensure_tls_secret
  build_image
  import_image
  restart_kube_proxy
  ensure_ingress_nginx_helm
  ensure_ingress_nginx_hostnetwork
  deploy_with_helm
  cleanup_old_images "${IMAGE_NAME_BASE}" "${RETENTION_DAYS}" "${FULL_IMAGE}"
}

main "$@"

