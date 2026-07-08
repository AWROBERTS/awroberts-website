join_worker_nodes() {
  for HOST in $WORKER_HOSTS; do
    echo "🔗 Joining worker node: $HOST"

    ssh -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=accept-new \
        "$WORKER_USER@$HOST" "sudo bash -c '
          set -e
          $JOIN_CMD
        '"

    echo "✔️ Worker joined: $HOST"
  done
}
