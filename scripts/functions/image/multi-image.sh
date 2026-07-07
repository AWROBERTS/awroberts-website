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
# REMOTE HOSTS
# -----------------------------
ARM_NODE_HOST="awr-ffmpeg"
ARM_NODE_USER="awr"
ARM_NODE="${ARM_NODE_USER}@${ARM_NODE_HOST}"

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
# BUILD (LOCAL X86)
# -----------------------------
build_image_x86() {
  local IMAGE="$1"
  local LATEST="$2"
  local CONTEXT="$3"
  local TAG="$4"
  local SOURCE_URL="$5"

  echo "🔨 [x86] Building ${IMAGE}"
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

  echo "⏱️ [x86] Build completed in ${duration}s"
}

# -----------------------------
# BUILD (REMOTE ARM via TAR STREAMING)
# -----------------------------
build_image_arm() {
  local IMAGE="$1"
  local LATEST="$2"
  local CONTEXT="$3"
  local TAG="$4"
  local SOURCE_URL="$5"

  echo "🔨 [ARM] Building ${IMAGE}"
  echo "   → Context (streamed): ${CONTEXT}"

  tar -C "${CONTEXT}" -cf - . \
    | ssh "${ARM_NODE}" "
        docker build \
          --no-cache \
          --build-arg BUILD_SHA='${TAG}' \
          --label 'org.opencontainers.image.revision=${TAG}' \
          --label 'org.opencontainers.image.version=${TAG}' \
          --label 'org.opencontainers.image.title=${IMAGE_NAME_BASE}' \
          ${SOURCE_URL:+--label 'org.opencontainers.image.source=${SOURCE_URL}'} \
          -t '${IMAGE}' \
          -t '${LATEST}' \
          -
      "
}

# -----------------------------
# BUILD ALL IMAGES
# -----------------------------
build_all_images() {
  local TAG
  TAG="$(git_sha_tag)"

  echo "📦 Preparing to build images with tag: ${TAG}"
  echo "  APP_IMAGE_NAME: ${APP_IMAGE_NAME}"
  echo "  BACKGROUND_IMAGE_NAME: ${BACKGROUND_IMAGE_NAME}"

  echo "🚀 Building APP image on awr (x86)..."
  image_vars_for "${APP_IMAGE_NAME}" "${TAG}"
  APP_FULL_IMAGE="${FULL_IMAGE}"
  APP_LATEST_IMAGE="${LATEST_IMAGE}"
  APP_IMAGE_NAME_BASE="${IMAGE_NAME_BASE}"

  build_image_x86 \
    "${APP_FULL_IMAGE}" \
    "${APP_LATEST_IMAGE}" \
    "${PROJECT_ROOT}/docker/awroberts" \
    "${TAG}" \
    "${GIT_REMOTE_URL:-}"

  echo "🎞️ Building BACKGROUND VIDEO image on awr-ffmpeg (ARM)..."
  image_vars_for "${BACKGROUND_IMAGE_NAME}" "${TAG}"
  BG_FULL_IMAGE="${FULL_IMAGE}"
  BG_LATEST_IMAGE="${LATEST_IMAGE}"
  BG_IMAGE_NAME_BASE="${IMAGE_NAME_BASE}"

  build_image_arm \
    "${BG_FULL_IMAGE}" \
    "${BG_LATEST_IMAGE}" \
    "${PROJECT_ROOT}/docker/background-video" \
    "${TAG}" \
    "${GIT_REMOTE_URL:-}"
}

# -----------------------------
# IMPORT (LOCAL X86)
# -----------------------------
import_image_x86() {
  local IMAGE="$1"

  echo "📦 [x86] Importing ${IMAGE} into containerd"
  docker save "${IMAGE}" | sudo ctr -n k8s.io images import -
}

# -----------------------------
# IMPORT (REMOTE ARM — FIXED)
# -----------------------------
import_image_arm() {
  local IMAGE="$1"

  echo "📦 [ARM] Importing ${IMAGE} into containerd"

  ssh "${ARM_NODE}" 'docker save '"${IMAGE}"' | sudo ctr -n k8s.io images import -'
}

# -----------------------------
# IMPORT ALL IMAGES
# -----------------------------
import_all_images() {
  import_image_x86 "${APP_FULL_IMAGE}"
  import_image_x86 "${APP_LATEST_IMAGE}"

  import_image_arm "${BG_FULL_IMAGE}"
  import_image_arm "${BG_LATEST_IMAGE}"
}
