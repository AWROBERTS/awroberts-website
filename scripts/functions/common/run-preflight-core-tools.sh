run_preflight_core_tools() {
  local HOST="$1"
  local USER="$2"

  echo "🔧 Running preflight_core_tools on $HOST ($USER)..."

  # Send the function definition + environment to the remote node
  ssh -i "$SSH_KEY_PATH" "$USER@$HOST" "bash -s" <<'EOF'
$(declare -f preflight_core_tools)
preflight_core_tools
EOF
}