sudo_if_needed() {
  if [[ $EUID -ne 0 ]]; then
    # If stdin is coming from a pipe, preserve it
    if [ -t 0 ]; then
      sudo "$@"
    else
      sudo "$@" < /dev/stdin
    fi
  else
    "$@"
  fi
}

