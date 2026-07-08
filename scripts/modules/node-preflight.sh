#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Node Preflight Module
# ============================================================================
# This module prepares a node for Kubernetes:
#   - disables swap
#   - configures sysctls
#   - installs core tools
#   - validates basic system readiness
#   - waits for node readiness (CP + worker)
#
# This replaces:
#   - prepare-nodes.sh
#   - disable-swap-and-configure-sysctls.sh
#   - preflight-core-tools.sh
#   - run-preflight-core-tools.sh
#   - wait-for-node-ready.sh
#   - wait-for-nodes-ready.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../shared"

# Shared helpers
source "${SHARED_DIR}/sudo-if-needed.sh"
source "${SHARED_DIR}/load-env-file.sh"

# ----------------------------------------------------------------------------
# Disable swap + configure sysctls
# ----------------------------------------------------------------------------
disable_swap_and_sysctls() {
  sudo_if_needed swapoff -a || true

  sudo_if_needed sed -i '/ swap / s/^/#/' /etc/fstab || true

  sudo_if_needed tee /etc/sysctl.d/k8s.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

  sudo_if_needed sysctl --system
}

# ----------------------------------------------------------------------------
# Install core tools (curl, jq, etc.)
# ----------------------------------------------------------------------------
install_core_tools() {
  sudo_if_needed apt-get update -y
  sudo_if_needed apt-get install -y \
    curl \
    jq \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release
}

# ----------------------------------------------------------------------------
# Prepare node (wrapper)
# ----------------------------------------------------------------------------
prepare_node() {
  disable_swap_and_sysctls
  install_core_tools
}

# ----------------------------------------------------------------------------
# Wait for a single node to be Ready
# ----------------------------------------------------------------------------
wait_for_node_ready() {
  local node_name="$1"

  echo "Waiting for node '${node_name}' to become Ready..."

  while true; do
    if kubectl get nodes "${node_name}" 2>/dev/null | grep -q " Ready "; then
      echo "Node '${node_name}' is Ready."
      break
    fi
    sleep 2
  done
}

# ----------------------------------------------------------------------------
# Wait for all nodes to be Ready
# ----------------------------------------------------------------------------
wait_for_all_nodes_ready() {
  echo "Waiting for all nodes to become Ready..."

  while true; do
    local not_ready
    not_ready="$(kubectl get nodes --no-headers | grep -v ' Ready ' || true)"

    if [[ -z "${not_ready}" ]]; then
      echo "All nodes are Ready."
      break
    fi

    sleep 2
  done
}

# ----------------------------------------------------------------------------
# Main entrypoint (optional)
# ----------------------------------------------------------------------------
main() {
  load_env_file
  prepare_node
}

# Allow module to be sourced OR executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
