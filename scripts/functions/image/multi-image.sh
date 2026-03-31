#!/usr/bin/env bash

# -----------------------------
# TAGGING (GIT SHA)
# -----------------------------
git_sha_tag() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git rev-parse --short HEAD
  else
    date -u +%Y%m%d-%H%M%S
  fi
}

# -----------------------------
# IMAGE VARS (PER IMAGE)
# -----------------------------
image_vars_for() {
  local NAME="$1"
  local TAG="$2"

  local BASE="${NAME%%:*}"
  local FULL="${BASE}:${TAG}"
  local LATEST="${BASE}:latest"

  IMAGE_NAME_BASE="${BASE}"
  IMAGE_TAG="${TAG}"
  FULL_IMAGE="${FULL}"
  LATEST_IMAGE="${LATEST}"
}

# -----------------------------
# BUILD
# -----------------------------
build_image_generic() {
  local IMAGE="$1"
  local LATEST="$2"
  local CONTEXT="$3"

  echo "🔨 Building ${IMAGE}"
  docker build \
    --no-cache \
    -t "${IMAGE}" \
    -t "${LATEST}" \
    "${CONTEXT}"
}

build_all_images() {
  local TAG
  TAG="$(git_sha_tag)"

  # APP
  image_vars_for "${APP_IMAGE_NAME}" "${TAG}"
  APP_FULL_IMAGE="${FULL_IMAGE}"
  APP_LATEST_IMAGE="${LATEST_IMAGE}"
  APP_IMAGE_NAME_BASE="${IMAGE_NAME_BASE}"
  build_image_generic "${APP_FULL_IMAGE}" "${APP_LATEST_IMAGE}" "${PROJECT_ROOT}"

  # BACKGROUND VIDEO
  image_vars_for "${BG_IMAGE_NAME}" "${TAG}"
  BG_FULL_IMAGE="${FULL_IMAGE}"
  BG_LATEST_IMAGE="${LATEST_IMAGE}"
  BG_IMAGE_NAME_BASE="${IMAGE_NAME_BASE}"
  build_image_generic "${BG_FULL_IMAGE}" "${BG_LATEST_IMAGE}" "${PROJECT_ROOT}"
}

# -----------------------------
# IMPORT
# -----------------------------
import_image_generic() {
  local IMAGE="$1"

  echo "📦 Importing ${IMAGE} into containerd"
  if docker save "${IMAGE}" | sudo_if_needed ctr -n k8s.io images import -; then
    echo "✅ Imported ${IMAGE}"
  else
    local SAFE_NAME
    SAFE_NAME="$(echo "${IMAGE}" | tr '/:' '__').tar"
    trap 'rm -f "${SAFE_NAME}"' EXIT
    docker save -o "${SAFE_NAME}" "${IMAGE}"
    sudo_if_needed ctr -n k8s.io images import "${SAFE_NAME}"
  fi
}

import_all_images() {
  import_image_generic "${APP_FULL_IMAGE}"
  import_image_generic "${BG_FULL_IMAGE}"
}
