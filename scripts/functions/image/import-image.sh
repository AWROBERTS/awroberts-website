#!/usr/bin/env bash
import_image() {
  echo "📦 Importing image into containerd: ${FULL_IMAGE}"
  if docker save "${FULL_IMAGE}" | sudo_if_needed ctr -n k8s.io images import -; then
    echo "✅ Image imported successfully."
  else
    local TAR_NAME="$(echo "${IMAGE_NAME_BASE}_${IMAGE_TAG}" | tr '/:' '__').tar"
    docker save -o "${TAR_NAME}" "${FULL_IMAGE}"
    sudo_if_needed ctr -n k8s.io images import "${TAR_NAME}"
    echo "🧹 Removing temporary image archive: ${TAR_NAME}"
    rm -f "${TAR_NAME}"
  fi
}
