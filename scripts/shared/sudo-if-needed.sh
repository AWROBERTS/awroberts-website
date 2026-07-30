sudo_if_needed() {
  if [[ $EUID -ne 0 ]]; then
    # Prefer worker password if present, otherwise fall back to control-plane password
    PASS="${WORKER_PASSWORD:-${CONTROL_PLANE_PASSWORD:-}}"

    if [[ -z "$PASS" ]]; then
      echo "ERROR: No password available for sudo_if_needed" >&2
      exit 1
    fi

    echo "$PASS" | sudo -S "$@"
  else
    "$@"
  fi
}
