load_env_file() {
  local env_file="./awroberts.env"
  if [[ -f "$env_file" ]]; then
    set -a
    . "$env_file"
    set +a
  else
    echo "❌ Environment file not found: $env_file"
    exit 1
  fi
}
