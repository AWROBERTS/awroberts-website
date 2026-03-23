deploy_with_helm() {
  echo "🚀 Deploying with Helm using image tag ${IMAGE_TAG}"

  echo "🧼 Cleaning namespace ${NAMESPACE}..."
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found

  echo "⏳ Waiting for namespace deletion..."
  while kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; do
    sleep 1
  done

  echo "📦 Recreating namespace ${NAMESPACE}..."
  kubectl create namespace "${NAMESPACE}"

  helm upgrade --install "${DEPLOYMENT_NAME}" "${HELM_CHART_PATH}" \
    --namespace "${NAMESPACE}" \
    --set image.repository="${IMAGE_NAME_BASE}" \
    --set image.tag="${IMAGE_TAG}" \
    --set image.pullPolicy="Never" \
    --set traefik.tls.secretName="${SECRET_NAME}" \
    --set traefik.hostnames[0]="${HOST_A}" \
    --set traefik.hostnames[1]="${HOST_B}" \
    --set volume.hostPath="${HOST_MEDIA_PATH}" \
    --set volume.mountPath="/usr/share/nginx/html/awroberts-media"
}
