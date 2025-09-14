#!/bin/bash

# Source all .sh files in the bootstrap directory
for file in ./bootstrap/*.sh; do
  [ -f "$file" ] && source "$file"
done

bootstrap_cluster_if_needed() {
  should_bootstrap_cluster || return

  local NEED_INIT="false"
  if is_cluster_accessible; then
    NEED_INIT="false"
  elif is_control_plane_present; then
    echo "Existing kubeadm control plane detected; skipping kubeadm init."
    configure_kubeconfig_if_exists
    wait_for_nodes_ready
  else
    NEED_INIT="true"
  fi

  if [[ "${NEED_INIT}" == "true" ]]; then
    echo "No reachable Kubernetes cluster via kubectl. Bootstrapping control plane with kubeadm (Flannel)..."
    disable_swap_and_configure_sysctls
    configure_containerd
    initialize_kubeadm
    configure_kubeconfig
    prepare_flannel_host_paths
    cleanup_old_cni_configs
    install_cni_plugins
    install_flannel_cni
    wait_for_flannel_ready
    allow_control_plane_scheduling
    wait_for_node_ready
  fi
}
