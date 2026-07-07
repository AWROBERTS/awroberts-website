#!/bin/bash

# Source all .sh files in the bootstrap directory
for file in ./bootstrap/*.sh; do
  [ -f "$file" ] && source "$file"
done

bootstrap_cluster_if_needed() {
  should_bootstrap_cluster || return

  #
  # CASE 1 — Control plane already exists
  #
  if is_control_plane_present; then
    echo "Control plane detected; configuring kubeconfig."
    configure_kubeconfig_if_exists

    echo "Ensuring CNI is installed (Cilium)..."
    install_cilium
    wait_for_cilium_ready
    allow_control_plane_scheduling
    wait_for_node_ready

    return
  fi

  #
  # CASE 2 — No control plane exists → fresh bootstrap
  #
  echo "🚀 No control plane detected. Bootstrapping with kubeadm..."

  initialise_kubeadm
  configure_kubeconfig

  echo "⏳ Waiting for Kubernetes API to become ready..."
  until kubectl get nodes >/dev/null 2>&1; do
    sleep 2
  done

  echo "🔍 Generating kubeadm join command..."
  JOIN_CMD=$(sudo kubeadm token create --print-join-command)
  export JOIN_CMD

  echo "🔗 Joining worker nodes..."
  join_worker_nodes

  echo "🌐 Installing CNI (Cilium)..."
  install_cilium
  wait_for_cilium_ready

  echo "⚙️ Allowing control plane scheduling..."
  allow_control_plane_scheduling

  echo "⏳ Waiting for nodes to become Ready..."
  wait_for_node_ready

  cleanup_gateway_api_resources
}
