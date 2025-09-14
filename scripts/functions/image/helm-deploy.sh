#!/usr/bin/env bash
deploy_with_helm() {
  echo "🚀 Deploying with Helm using image tag ${IMAGE_TAG}"
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install "${DEPLOYMENT_NAME}" "${HELM_CHART_PATH}" \
    --namespace "${NAMESPACE}" \
    --set image.repository="${IMAGE_NAME_BASE}" \
    --set image.tag="${IMAGE_TAG}" \
    --set image.pullPolicy="Never" \
    --set ingress.tls.secretName="${SECRET_NAME}" \
    --set ingress.rules[0].host="${HOST_A}" \
    --set ingress.rules[1].host="${HOST_B}" \
    --set volume.hostPath="${HOST_MEDIA_PATH}" \
    --set volume.mountPath="/usr/share/nginx/html/awroberts-media"
}
