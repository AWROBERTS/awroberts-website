#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Cluster Bootstrap Module
# ============================================================================
# Handles control-plane bootstrap logic:
#   - detect if control-plane is already present
#   - run kubeadm init when needed
#   - configure kubeconfig
#   - allow control-plane scheduling
#
# Replaces:
#   - bootstrap-control-plane.sh
#   - bootstrap-cluster-if-needed.sh
#   - is-control-plane-present.sh
#   - should-bootstrap-cluster.sh
#   - allow-control-plane-scheduling.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_ROOT="${SCRIPT_DIR}/.."
SHARED_DIR="${MODULES_ROOT}/shared"

source "${SHARED_DIR}/sudo-if-needed.sh"
source "${SHARED_DIR}/load-env-file.sh"
source "${MODULES_ROOT}/kube-tools.sh"

# ----------------------------------------------------------------------------
# Detect if control-plane is already present
# ----------------------------------------------------------------------------
is_control_plane_present() {
  [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]]
}

# ----------------------------------------------------------------------------
# Detect if cluster is reachable
# ----------------------------------------------------------------------------
is_cluster_accessible() {
  kubectl get nodes >/dev/null 2>&1
}

# ----------------------------------------------------------------------------
# Decide whether to bootstrap cluster
# ----------------------------------------------------------------------------
should_bootstrap_cluster() {
  if is_control_plane_present; then
    return 1
  fi

  if is_cluster_accessible; then
    return 1
  fi

  return 0
}

# ----------------------------------------------------------------------------
# Run kubeadm init
# ----------------------------------------------------------------------------

kubeadm_init_control_plane() {
  echo "Bootstrapping control-plane with kubeadm init..."

  local pod_cidr="${POD_NETWORK_CIDR:-10.244.0.0/16}"
  local kube_version="${K8S_VERSION:-$(kubeadm version -o short)}"

  sudo_if_needed kubeadm init \
    --pod-network-cidr="${pod_cidr}" \
    --kubernetes-version="${kube_version}"

  mkdir -p "$HOME/.kube"
  sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"

  sudo_if_needed systemctl enable kubelet
  sudo_if_needed systemctl start kubelet

  validate_kubelet_runtime
  configure_kubeconfig
}

# ----------------------------------------------------------------------------
# Allow scheduling on control-plane
# ----------------------------------------------------------------------------
allow_control_plane_scheduling() {
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
}

# ----------------------------------------------------------------------------
# Wrapper: bootstrap cluster if needed
# ----------------------------------------------------------------------------
bootstrap_cluster_if_needed() {
  if should_bootstrap_cluster; then
    kubeadm_init_control_plane
    allow_control_plane_scheduling
  else
    echo "Cluster already bootstrapped."
  fi
}

# ----------------------------------------------------------------------------
# Main entrypoint
# ----------------------------------------------------------------------------
main() {
  load_env_file
  bootstrap_cluster_if_needed
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
