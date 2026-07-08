ssh_exec() {
    local HOST="$1"
    local USER="$2"
    local FUNC_NAME="$3"

    if [[ -z "$FUNC_NAME" ]]; then
        echo "❌ ssh_wrapper: missing function name"
        exit 1
    fi

    echo "🔧 Running $FUNC_NAME on $HOST ($USER)..."

    ssh -i "$SSH_KEY_PATH" "$USER@$HOST" "bash -s" <<EOF
# Inject required functions
$(declare -f "$FUNC_NAME")
$(declare -f sudo_if_needed)

# Load shared env (always)
set -a
source "${PROJECT_ROOT}/awroberts-cluster.env"
set +a

# Load control-plane env only when needed
if [[ "$HOST" == "$CONTROL_PLANE_HOST" ]]; then
    set -a
    source "${PROJECT_ROOT}/awroberts-control-plane.env"
    set +a
fi

# Execute the requested function
$FUNC_NAME
EOF
}
