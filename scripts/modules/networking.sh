#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Networking Module
# ============================================================================
# Handles Kubernetes cluster networking:
#   - installs Cilium via Helm
#   - waits for Cilium to become Ready
#   - cleans up Gateway API resources (optional)
#   - applies additional networking manifests
#
# Replaces:
#   - install-cilium.sh
#   - cleanup_gateway_api_resources.sh
#   - wait-for-cilium-ready.sh
#   - setup-kubernetes-networking.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

source "${SHARED_DIR}/sudo-if-needed.sh"
source "${SHARED_DIR}/load-env-file.sh"

# ----------------------------------------------------------------------------
# Install Cilium via Helm
# ----------------------------------------------------------------------------
install_cilium() {
  echo "Installing Cilium..."

  helm repo add cilium https://helm.cilium.io >/dev/null
  helm repo update >/dev/null

  helm upgrade --install cilium cilium/cilium \
    --namespace kube-system \
    --set kubeProxyReplacement=strict \
    --set k8sServiceHost="${CONTROL_PLANE_HOST}" \
    --set k8sServicePort=6443 \
    --set ipam.mode=kubernetes \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true
}

# ----------------------------------------------------------------------------
# Wait for Cilium to be Ready
# ----------------------------------------------------------------------------
wait_for_cilium_ready() {
  echo "Waiting for Cilium to become Ready..."

  while true; do
    local not_ready
    not_ready="$(kubectl -n kube-system get pods -l k8s-app=cilium --no-headers | grep -v ' Running ' || true)"

    if [[ -z "${not_ready}" ]]; then
      echo "Cilium is Ready."
      break
    fi

    sleep 2
  done
}

# ----------------------------------------------------------------------------
# Cleanup Gateway API resources (optional)
# ----------------------------------------------------------------------------
cleanup_gateway_api_resources() {
  echo "Cleaning up Gateway API resources (if any)..."

  kubectl delete gatewayclasses.gateway.networking.k8s.io --all >/dev/null 2>&1 || true
  kubectl delete gateways.gateway.networking.k8s.io --all >/dev/null 2>&1 || true
  kubectl delete httproutes.gateway.networking.k8s.io --all >/dev/null 2>&1 || true
}

# ----------------------------------------------------------------------------
# Apply additional networking manifests
# ----------------------------------------------------------------------------
apply_networking_manifests() {
  if [[ -n "${NETWORKING_MANIFESTS_DIR:-}" ]]; then
    echo "Applying networking manifests from ${NETWORKING_MANIFESTS_DIR}..."
    kubectl apply -f "${NETWORKING_MANIFESTS_DIR}"
  fi
}

# ----------------------------------------------------------------------------
# Wrapper: full networking setup
# ----------------------------------------------------------------------------
setup_networking() {
  install_cilium
  wait_for_cilium_ready
  cleanup_gateway_api_resources
  apply_networking_manifests
}

# ----------------------------------------------------------------------------
# Main entrypoint (optional)
# ----------------------------------------------------------------------------
main() {
  load_env_file
  setup_networking
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
