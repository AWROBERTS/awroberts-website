#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./scripts/lib/common.sh
source "${SCRIPT_DIR}/scripts/lib/common.sh"
# shellcheck source=./scripts/cluster.sh
source "${SCRIPT_DIR}/scripts/cluster.sh"
# shellcheck source=./scripts/image.sh
source "${SCRIPT_DIR}/scripts/image.sh"
# shellcheck source=./scripts/deploy.sh
source "${SCRIPT_DIR}/scripts//deploy.sh"

main() {
  cluster_targeting
  preflight_core_tools
  ensure_k8s_and_containerd_installed
  bootstrap_cluster_if_needed
  info_and_validate_context
  ensure_containerd_config
  verify_kubelet_cgroup
  ensure_ingress_nginx
  build_image
  import_image
  kubernetes_deploy
  notes_and_status
}

main "$@"