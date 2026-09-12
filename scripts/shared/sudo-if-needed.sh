sudo_if_needed() {
  if [[ $EUID -ne 0 ]]; then
    # Prefer worker password if present, otherwise fall back to control-plane password
    PASS="${WORKER_PASSWORD:-${CONTROL_PLANE_PASSWORD:-}}"

    if [[ -z "$PASS" ]]; then
      echo "ERROR: No password available for sudo_if_needed" >&2
      exit 1
    fi

    # Prime sudo's credential cache on an isolated stdin, then run the real
    # command through plain sudo with no stdin redirection of its own — this
    # preserves the caller's own stdin (e.g. `docker save | sudo_if_needed ctr
    # images import -`). Piping the password directly into `sudo -S "$@"`
    # would replace the wrapped command's stdin with the password pipe,
    # which is drained the instant sudo reads the password line, so the
    # wrapped command sees immediate EOF instead of the real piped data.
    echo "$PASS" | sudo -S -v
    sudo "$@"
  else
    "$@"
  fi
}
