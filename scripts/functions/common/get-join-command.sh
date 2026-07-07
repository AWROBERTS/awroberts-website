get_join_command() {
  echo "🔍 Generating kubeadm join command..."

  # Ensure control plane is initialized
  if [[ ! -f /etc/kubernetes/admin.conf ]]; then
    echo "❌ Control plane not initialized yet."
    exit 1
  fi

  JOIN_CMD=$(sudo kubeadm token create --print-join-command)
  echo "📌 Join command generated."

  # Export for other functions
  export JOIN_CMD
}
