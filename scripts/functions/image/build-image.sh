build_image() {
  echo "🔨 Building image ${FULL_IMAGE} and tagging as latest for ${PLATFORM}"
  docker build \
    --no-cache \
    -t "${FULL_IMAGE}" \
    -t "${LATEST_IMAGE}" \
    "${BUILD_CONTEXT}"
}
