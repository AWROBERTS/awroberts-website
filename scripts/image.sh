#!/usr/bin/env bash
# Build, tag, and deploy a Kubernetes image using Helm

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

build_image() {
  docker buildx use "$BUILDER_NAME" || docker buildx create --name "$BUILDER_NAME" --use
  echo "🔨 Building image ${FULL_IMAGE} and tagging as latest for ${PLATFORM}"
  docker buildx build --platform "${PLATFORM}" \
    -t "${FULL_IMAGE}" \
    -t "${LATEST_IMAGE}" \
    --load "${BUILD_CONTEXT}"
}

import_image() {
  echo "📦 Importing image into containerd: ${FULL_IMAGE}"
  if docker save "${FULL_IMAGE}" | sudo_if_needed ctr -n k8s.io images import -; then
    echo "✅ Image imported successfully."
  else
    local TAR_NAME="$(echo "${IMAGE_NAME_BASE}_${IMAGE_TAG}" | tr '/:' '__').tar"
    docker save -o "${TAR_NAME}" "${FULL_IMAGE}"
    sudo_if_needed ctr -n k8s.io images import "${TAR_NAME}"
  fi
}

deploy_with_helm() {
  echo "🚀 Deploying with Helm using image tag ${IMAGE_TAG}"
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

cleanup_old_images() {
  local base="$1" days="$2" keep_image="$3"
  local now epoch_cutoff in_use_tmp
  now="$(date -u +%s)"
  epoch_cutoff=$(( now - days*24*3600 ))
  in_use_tmp="$(mktemp)"
  kubectl get pods -A -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' | sort -u > "$in_use_tmp" || true
  _in_use() { grep -Fxq "$1" "$in_use_tmp"; }

  for ref in $(docker images --format '{{.Repository}}:{{.Tag}}'); do
    [[ "$ref" == ${base}:* ]] && [[ "$ref" != "$keep_image" ]] && ! _in_use "$ref" && docker image rm "$ref" >/dev/null 2>&1 || true
  done

  rm -f "$in_use_tmp"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  build_image
  import_image
  ensure_tls_secret

  echo "🔧 Applying kube-proxy ConfigMap..."
  kubectl apply -f "${SCRIPT_DIR}/kube-proxy-config.yaml"

  echo "🔁 Restarting kube-proxy..."
  kubectl delete pod -n kube-system -l k8s-app=kube-proxy

  echo "⏳ Waiting for kube-proxy to become ready..."
  kubectl rollout status daemonset/kube-proxy -n kube-system

  if ! kubectl get deployment ingress-nginx-controller -n ingress-nginx &>/dev/null; then
  echo "🔧 Installing ingress-nginx controller..."
  kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
  kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx
  else
    echo "✅ ingress-nginx controller already installed."
  fi

  deploy_with_helm
  cleanup_old_images "${IMAGE_NAME_BASE}" "${RETENTION_DAYS}" "${FULL_IMAGE}"
  echo "-- ✅ Deployment complete! Using image: ${FULL_IMAGE} (also tagged as latest) --"
fi
