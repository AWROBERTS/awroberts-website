run_preflight_core_tools() {
    local HOST="$1"
    local USER="$2"

    echo "🔧 Running preflight_core_tools on $HOST ($USER)..."

    ssh -i "$SSH_KEY_PATH" "$USER@$HOST" "bash -s" <<EOF
$(declare -f preflight_core_tools)
$(declare -f sudo_if_needed)

# Load shared env
set -a
source "${PROJECT_ROOT}/awroberts-cluster.env"
set +a

# Load control-plane env only if needed
if [[ "$HOST" == "$CONTROL_PLANE_HOST" ]]; then
    set -a
    source "${PROJECT_ROOT}/awroberts-control-plane.env"
    set +a
fi

preflight_core_tools
EOF
}
