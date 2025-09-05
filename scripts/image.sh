#!/usr/bin/env bash
# Robust image build/import/prune for Kubernetes with unique tags

# Always source config and helpers first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

gen_image_tag() {
  # Always generate a unique timestamp tag if not set/exported
  echo "fix-$(date +%Y%m%d-%H%M%S)"
}

set_image_vars() {
  IMAGE_NAME_BASE="${IMAGE_NAME%%:*}"
  if [[ -z "${IMAGE_TAG:-}" ]]; then
    IMAGE_TAG="$(gen_image_tag)"
  fi
  FULL_IMAGE="${IMAGE_NAME_BASE}:${IMAGE_TAG}"
}

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

  _in_use() { grep -Fxq "$1" "$in_use_tmp"; }

  # Clean containerd images
  if command -v ctr >/dev/null 2>&1; then
    for ref in $(sudo_if_needed ctr -n k8s.io images ls -q 2>/dev/null || true); do
      [[ "$ref" == ${base}:* ]] || continue
      [[ "$ref" == "$keep_image" ]] && continue
      _in_use "$ref" && continue
      echo "  Removing containerd image: $ref"
      sudo_if_needed ctr -n k8s.io images rm "$ref" || true
    done
  fi

  # Clean docker images
  for ref in $(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true); do
    [[ "$ref" == ${base}:* ]] || continue
    [[ "$ref" == "$keep_image" ]] && continue
    _in_use "$ref" && continue
    echo "  Removing docker image: $ref"
    docker image rm "$ref" >/dev/null 2>&1 || true
  done

  rm -f "$in_use_tmp"
}

build_image() {
  set_image_vars
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
  set_image_vars
  echo "Importing image into containerd (kubeadm): ${FULL_IMAGE}"
  if docker save "${FULL_IMAGE}" | sudo_if_needed ctr -n k8s.io images import -; then
    echo "Image imported into containerd."
  else
    echo "Image import via pipe failed. Falling back to tar file..."
    local TAR_NAME
    TAR_NAME="$(echo "${IMAGE_NAME_BASE}_${IMAGE_TAG}" | tr '/:' '__').tar"
    docker save -o "${TAR_NAME}" "${FULL_IMAGE}"
    sudo_if_needed ctr -n k8s.io images import "${TAR_NAME}"
  fi

  # Patch deployment to use our unique tag + local pull only
  echo "Updating deployment ${DEPLOYMENT_NAME} for tag ${IMAGE_TAG}"
  kubectl -n "${NAMESPACE}" set image deployment/"${DEPLOYMENT_NAME}" web="${FULL_IMAGE}"
  kubectl -n "${NAMESPACE}" patch deployment "${DEPLOYMENT_NAME}" \
    --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Never"}]' || true

  cleanup_old_images "${IMAGE_NAME_BASE}" "${RETENTION_DAYS}" "${FULL_IMAGE}"

  # Delete old pods to fully enforce rollout
  echo "Deleting old pods to ensure a fresh rollout"
  kubectl -n "${NAMESPACE}" delete pod -l app="${DEPLOYMENT_NAME%-web}" --ignore-not-found
}

# If script is executed directly, do everything!
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  build_image
  import_image
  echo "-- Build/import complete! Now using: ${FULL_IMAGE} --"
fi