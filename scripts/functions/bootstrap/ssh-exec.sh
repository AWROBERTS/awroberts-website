ssh_exec() {
  local HOST="$1"
  local USER="$2"
  local CMD="$3"

  ssh -i "$SSH_KEY_PATH" \
      -o StrictHostKeyChecking=accept-new \
      "$USER@$HOST" "sudo bash -c '$CMD'"
}
