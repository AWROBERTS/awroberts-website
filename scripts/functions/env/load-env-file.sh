load_env_file() {
  local CLUSTER_ENV="${PROJECT_ROOT}/awroberts-cluster.env"
  local CONTROL_PLANE_ENV="${PROJECT_ROOT}/awroberts-control-plane.env"

  # Cluster env must always exist
  if [[ ! -f "$CLUSTER_ENV" ]]; then
    echo "❌ Cluster environment file not found: $CLUSTER_ENV"
    exit 1
  fi

  echo "📦 Loading cluster environment variables from: $CLUSTER_ENV"
  source "$CLUSTER_ENV"

  if [[ "$HOSTNAME" == "$CONTROL_PLANE_HOST" ]]; then
    if [[ ! -f "$CONTROL_PLANE_ENV" ]]; then
      echo "❌ Control-plane environment file not found: $CONTROL_PLANE_ENV"
      exit 1
    fi

    echo "📦 Loading control-plane environment variables from: $CONTROL_PLANE_ENV"
    source "$CONTROL_PLANE_ENV"
  fi
}
