deploy_with_helm() {
  echo "🚀 Deploying with Helm using image tag ${IMAGE_TAG}"

  echo "📦 Ensuring namespace ${NAMESPACE} exists..."
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  helm upgrade --install "${DEPLOYMENT_NAME}" "${HELM_CHART_PATH}" \
    --namespace "${NAMESPACE}" \
    --set image.repository="${APP_IMAGE_NAME_BASE}" \
    --set image.tag="${IMAGE_TAG}" \
    --set image.pullPolicy="Never" \
    --set backgroundVideo.image.repository="${BG_IMAGE_NAME_BASE}" \
    --set backgroundVideo.image.tag="${IMAGE_TAG}" \
    --set backgroundVideo.image.pullPolicy="Never" \
    --set traefik.tls.secretName="${SECRET_NAME}" \
    --set traefik.hostnames[0]="${HOST_A}" \
    --set traefik.hostnames[1]="${HOST_B}" \
    --set volume.hostPath="${HOST_MEDIA_PATH}" \
    --set volume.mountPath="/usr/share/nginx/html/awroberts-media"
}
