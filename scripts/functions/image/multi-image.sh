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
  local TAG="$4"
  local SOURCE_URL="$5"

  echo "🔨 Building ${IMAGE}"
  echo "   → Context: ${CONTEXT}"

  local start end duration
  start=$(date +%s)

  docker build \
    --no-cache \
    --build-arg BUILD_SHA="${TAG}" \
    --label "org.opencontainers.image.revision=${TAG}" \
    --label "org.opencontainers.image.version=${TAG}" \
    --label "org.opencontainers.image.title=${IMAGE_NAME_BASE}" \
    ${SOURCE_URL:+--label "org.opencontainers.image.source=${SOURCE_URL}"} \
    -t "${IMAGE}" \
    -t "${LATEST}" \
    "${CONTEXT}"

  end=$(date +%s)
  duration=$(( end - start ))

  echo "⏱️ Build completed in ${duration}s"
}

build_all_images() {
  local TAG
  TAG="$(git_sha_tag)"

  local start_all end_all duration_all
  start_all=$(date +%s)

  echo "📦 Preparing to build images with tag: ${TAG}"
  echo "  APP_IMAGE_NAME: ${APP_IMAGE_NAME}"
  echo "  BACKGROUND_IMAGE_NAME:  ${BACKGROUND_IMAGE_NAME}"

  # APP
  echo "🚀 Building APP image..."
  image_vars_for "${APP_IMAGE_NAME}" "${TAG}"
  APP_FULL_IMAGE="${FULL_IMAGE}"
  APP_LATEST_IMAGE="${LATEST_IMAGE}"
  APP_IMAGE_NAME_BASE="${IMAGE_NAME_BASE}"
  echo "  → ${APP_FULL_IMAGE}"
  build_image_generic \
    "${APP_FULL_IMAGE}" \
    "${APP_LATEST_IMAGE}" \
    "${PROJECT_ROOT}/docker/awroberts" \
    "${TAG}" \
    "${GIT_REMOTE_URL:-}"

  # BACKGROUND VIDEO
  echo "🎞️ Building BACKGROUND VIDEO image..."
  image_vars_for "${BACKGROUND_IMAGE_NAME}" "${TAG}"
  BG_FULL_IMAGE="${FULL_IMAGE}"
  BG_LATEST_IMAGE="${LATEST_IMAGE}"
  BG_IMAGE_NAME_BASE="${IMAGE_NAME_BASE}"
  echo "  → ${BG_FULL_IMAGE}"
  build_image_generic \
    "${BG_FULL_IMAGE}" \
    "${BG_LATEST_IMAGE}" \
    "${PROJECT_ROOT}/docker/background-video" \
    "${TAG}" \
    "${GIT_REMOTE_URL:-}"

  end_all=$(date +%s)
  duration_all=$(( end_all - start_all ))

  echo "🏁 All images built in ${duration_all}s"
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
