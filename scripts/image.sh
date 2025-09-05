#!/usr/bin/env bash
# Image build/import/prune

cleanup_old_images() {
  local base="$1" days="$2" keep_image="$3"
  local now epoch_cutoff in_use_tmp
  now="$(date -u +%s)"
  epoch_cutoff=$(( now - days*24*3600 ))
  in_use_tmp="$(mktemp)"

  kubectl get pods -A -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}{range .items[*].spec.initContainers[*]}{.image}{"\n"}{end}' \
    2>/dev/null | awk 'NF' | sort -u > "$in_use_tmp" || true

  echo "Pruning timestamp-tagged images older than ${days} days for base '${base}:'"
  echo "Keeping current image: ${keep_image}"
  echo "Also keeping any image currently used by running pods."

  _in_use() { grep -Fxq "$1" "$in_use_tmp"; }

  if command -v ctr >/dev/null 2>&1; then
    while IFS= read -r ref; do
      [[ "$ref" == ${base}:* ]] || continue
      [[ "$ref" == "$keep_image" ]] && continue
      _in_use "$ref" && continue
      local tag="${ref#${base}:}"
      if [[ "$tag" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
        local d="${tag:0:4}-${tag:4:2}-${tag:6:2} ${tag:9:2}:${tag:11:2}:${tag:13:2} UTC"
        local ts; ts="$(date -u -d "$d" +%s 2>/dev/null || echo 0)"
        if (( ts > 0 && ts < epoch_cutoff )); then
          echo "  Removing containerd image: $ref (tag time: $d)"
          sudo_if_needed ctr -n k8s.io images rm "$ref" || true
        fi
      fi
    done < <(sudo_if_needed ctr -n k8s.io images ls -q 2>/dev/null || true)
  fi

  while IFS= read -r ref; do
    [[ "$ref" == ${base}:* ]] || continue
    [[ "$ref" == "$keep_image" ]] && continue
    _in_use "$ref" && continue
    local tag="${ref#${base}:}"
    if [[ "$tag" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
      local d="${tag:0:4}-${tag:4:2}-${tag:6:2} ${tag:9:2}:${tag:11:2}:${tag:13:2} UTC"
      local ts; ts="$(date -u -d "$d" +%s 2>/dev/null || echo 0)"
      if (( ts > 0 && ts < epoch_cutoff )); then
        echo "  Removing docker image: $ref (tag time: $d)"
        docker image rm "$ref" >/dev/null 2>&1 || true
      fi
    fi
  done < <(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)

  rm -f "$in_use_tmp"
}

build_image() {
  # Build local image with Buildx (strict; no docker build fallback)
  if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
    docker buildx create --name "$BUILDER_NAME" --use >/dev/null
  else
    docker buildx use "$BUILDER_NAME" >/dev/null
  fi

  echo "Building local image ${FULL_IMAGE} for ${PLATFORM} (buildx)"
  docker buildx build \
    --platform "${PLATFORM}" \
    -t "${FULL_IMAGE}" \
    --load \
    "${BUILD_CONTEXT}"
}

import_image() {
  # Make the image available to the cluster (no external registry)
  echo "Importing image into containerd (kubeadm)"
  if docker save "${FULL_IMAGE}" | sudo_if_needed ctr -n k8s.io images import -; then
    echo "Image imported into containerd."
  else
    echo "Image import via pipe failed. Falling back to tar file..."
    local TAR_NAME
    TAR_NAME="$(echo "${IMAGE_NAME}_${IMAGE_TAG}" | tr '/:' '__').tar"
    docker save -o "${TAR_NAME}" "${FULL_IMAGE}"
    sudo_if_needed ctr -n k8s.io images import "${TAR_NAME}"
  fi

  # Patch deployment to always use local image (not remote registry)
  if [[ -n "${NAMESPACE:-}" && -n "${DEPLOYMENT_NAME:-}" ]]; then
    echo "Setting imagePullPolicy: Never on deployment/${DEPLOYMENT_NAME} in namespace ${NAMESPACE}"
    kubectl -n "${NAMESPACE}" patch deployment "${DEPLOYMENT_NAME}" \
      --type='json' \
      -p='[{"op":"add","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Never"}]' || true
  fi

  # Prune old images (keeps current and anything in use)
  cleanup_old_images "${IMAGE_NAME_BASE}" "${RETENTION_DAYS}" "${FULL_IMAGE}"
}