get_join_command() {
  echo "🔗 Fetching kubeadm join command from $CONTROL_PLANE_HOST"

  JOIN_CMD=$(ssh -i "$SSH_KEY_PATH" \
      -o StrictHostKeyChecking=accept-new \
      "$CONTROL_PLANE_USER@$CONTROL_PLANE_HOST" "sudo kubeadm token create --print-join-command")

  echo "🔗 Join command retrieved:"
  echo "$JOIN_CMD"
}
