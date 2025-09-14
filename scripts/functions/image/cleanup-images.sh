#!/usr/bin/env bash
cleanup_old_images() {
  local base="$1" days="$2" keep_image="$3"
  local now epoch_cutoff in_use_tmp
  now="$(date -u +%s)"
  epoch_cutoff=$(( now - days*24*3600 ))
  in_use_tmp="$(mktemp)"
  kubectl get pods -A -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' | sort -u > "$in_use_tmp" || true
  _in_use() { grep -Fxq "$1" "$in_use_tmp"; }

  for ref in $(docker images --format '{{.Repository}}:{{.Tag}}'); do
    [[ "$ref" == ${base}:* ]] && [[ "$ref" != "$keep_image" ]] && ! _in_use "$ref" && docker image rm "$ref" >/dev/null 2>&1 || true
  done

  rm -f "$in_use_tmp"
}
