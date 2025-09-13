#!/usr/bin/env bash
# Kubernetes app deployment using Helm, with TLS secret setup

source "${PROJECT_ROOT}/scripts/lib/common.sh"

kubernetes_deploy() {
  ensure_tls_secret
  echo "Deploying ${DEPLOYMENT_NAME} with Helm using image tag ${IMAGE_TAG}"
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
  kubectl -n "$NAMESPACE" rollout status deployment/"$DEPLOYMENT_NAME" --timeout=240s
}

notes_and_status() {
  if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:80 and WAN 443 -> NODE_IP:443"
  else
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:${HTTP_NODEPORT} and WAN 443 -> NODE_IP:${HTTPS_NODEPORT}"
  fi

  echo "Deployment complete. Quick status:"
  kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o wide
  kubectl -n "$NAMESPACE" get svc "$DEPLOYMENT_NAME" -o wide || true
  kubectl -n "$NAMESPACE" get ingress "$DEPLOYMENT_NAME" -o wide || true
  echo "Node IPs: $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')"
  echo "Public IP: $(curl -s https://api.ipify.org || true)"
}
