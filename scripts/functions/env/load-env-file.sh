load_env_file() {
  local env_file="${PROJECT_ROOT}/awroberts.env"
  if [[ -f "$env_file" ]]; then
    echo "📦 Loading environment variables from: $env_file"
    set -a
    . "$env_file"
    set +a
  else
    echo "❌ Environment file not found: $env_file"
    exit 1
  fi
}
