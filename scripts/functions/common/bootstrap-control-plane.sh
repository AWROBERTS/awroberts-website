bootstrap_control_plane() {
  echo "🚀 Bootstrapping control plane on $CONTROL_PLANE_HOST"

  ssh -i "$SSH_KEY_PATH" \
      -o StrictHostKeyChecking=accept-new \
      "$CONTROL_PLANE_USER@$CONTROL_PLANE_HOST" "sudo bash -c '
        set -e
        kubeadm init --pod-network-cidr=10.244.0.0/16
      '"

  echo "📌 Fetching kubeconfig..."
  ssh "$CONTROL_PLANE_USER@$CONTROL_PLANE_HOST" "sudo cat /etc/kubernetes/admin.conf" > admin.conf

  export KUBECONFIG=\"$(pwd)/admin.conf\"
  echo \"✔️ Control plane bootstrapped and kubeconfig loaded\"
}
