join_worker_nodes() {
  echo "🔗 Joining worker nodes to the cluster..."

  # Identify control plane node
  CONTROL_PLANE=$(kubectl get nodes -o json \
    | jq -r '.items[] | select(.metadata.labels["node-role.kubernetes.io/control-plane"]=="") | .metadata.name')

  for NODE in $(kubectl get nodes -o name | sed 's/node\///'); do
    if [[ "$NODE" == "$CONTROL_PLANE" ]]; then
      echo "⏭️ Skipping control plane: $NODE"
      continue
    fi

    echo "🔧 Joining worker node: $NODE"

    kubectl debug node/$NODE -it --image=busybox -- chroot /host sh -c "
      set -e
      echo '📦 Running kubeadm join inside node...'
      $JOIN_CMD
      echo '✔️ Node successfully joined: $NODE'
    "
  done

  echo "🎉 All worker nodes joined."
}
