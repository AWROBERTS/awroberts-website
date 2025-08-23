#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
NAMESPACE="${NAMESPACE:-awroberts}"
SECRET_NAME="${SECRET_NAME:-awroberts-tls}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-awroberts-web}"     # Deployment name
CONTAINER_NAME_IN_DEPLOY="${CONTAINER_NAME_IN_DEPLOY:-}" # leave empty to auto-detect
MANIFEST_DIR="${MANIFEST_DIR:-./k8s}"                    # folder with deployment/service/ingress YAMLs
INGRESS_NAME="${INGRESS_NAME:-awroberts-web}"            # Ingress manifest name
SERVICE_NAME="${SERVICE_NAME:-awroberts-web}"            # Service referenced by the Ingress
HOST_A="${HOST_A:-awroberts.co.uk}"
HOST_B="${HOST_B:-www.awroberts.co.uk}"

# TLS certs (full chain + unencrypted key)
HOST_CERT_PATH="${HOST_CERT_PATH:-/var/www/html/awroberts/awroberts-certs/fullchain.crt}"
HOST_KEY_PATH="${HOST_KEY_PATH:-/var/www/html/awroberts/awroberts-certs/awroberts_co_uk.key}"

# Local image build settings
IMAGE_NAME="${IMAGE_NAME:-awroberts}"     # untagged base
IMAGE_TAG="${IMAGE_TAG:-v1}"              # tag to deploy
IMAGE_NAME_BASE="${IMAGE_NAME%%:*}"       # strip any tag if present
FULL_IMAGE="${IMAGE_NAME_BASE}:${IMAGE_TAG}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"
PLATFORM="${PLATFORM:-linux/amd64}"       # set to your dev arch (e.g., linux/arm64)
BUILDER_NAME="${BUILDER_NAME:-localbuilder}"

# MetalLB address pool (auto-derive if empty)
# Override with: METALLB_RANGE_START=192.168.49.240 METALLB_RANGE_END=192.168.49.250
METALLB_RANGE_START="${METALLB_RANGE_START:-}"
METALLB_RANGE_END="${METALLB_RANGE_END:-}"

# ===== Pre-flight checks =====
command -v docker >/dev/null 2>&1 || { echo "docker not found"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
command -v minikube >/dev/null 2>&1 || { echo "minikube not found"; exit 1; }
minikube status >/dev/null 2>&1 || { echo "minikube cluster not running"; exit 1; }

[[ -f "$HOST_CERT_PATH" ]] || { echo "Cert not found at $HOST_CERT_PATH"; exit 1; }
[[ -f "$HOST_KEY_PATH" ]] || { echo "Key not found at $HOST_KEY_PATH"; exit 1; }
[[ -d "$MANIFEST_DIR" ]] || { echo "Manifest directory not found: $MANIFEST_DIR"; exit 1; }

# ===== Build local image with Buildx (loaded into local Docker daemon) =====
if ! docker buildx version >/dev/null 2>&1; then
  echo "docker buildx not found. Please install Docker Buildx."
  exit 1
fi

if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
  docker buildx create --name "$BUILDER_NAME" --use >/dev/null
else
  docker buildx use "$BUILDER_NAME" >/dev/null
fi

echo "Building local image ${FULL_IMAGE} for ${PLATFORM}"
docker buildx build \
  --platform "${PLATFORM}" \
  -t "${FULL_IMAGE}" \
  --load \
  "${BUILD_CONTEXT}"

# ===== Make the image available to the cluster =====
CTX="$(kubectl config current-context || true)"
echo "Current kube-context: ${CTX}"

echo "Loading image into minikube"
minikube image load "${FULL_IMAGE}"

# ===== Kubernetes deploy =====

# 1) Ensure namespace exists
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

# 2) Create or update the TLS Secret idempotently
kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" \
  --cert="$HOST_CERT_PATH" \
  --key="$HOST_KEY_PATH" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3) Apply app manifests (Deployment, Service, Ingress, etc.)
echo "Applying manifests from: ${MANIFEST_DIR}"
kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR"

# Ensure a Service exists; if not, create one for the Deployment (ClusterIP for Ingress)
if ! kubectl -n "$NAMESPACE" get svc "${SERVICE_NAME}" >/dev/null 2>&1; then
  echo "No Service named '${SERVICE_NAME}' found. Creating one for Deployment '${DEPLOYMENT_NAME}'."
  kubectl -n "$NAMESPACE" expose deploy "$DEPLOYMENT_NAME" \
    --name "${SERVICE_NAME}" --port=80 --target-port=80 --type=ClusterIP
fi

# 4) Determine the container name (auto-detect if not provided)
if [[ -z "$CONTAINER_NAME_IN_DEPLOY" ]]; then
  CONTAINERS_IN_DEPLOY="$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[*].name}')"
  if [[ -z "$CONTAINERS_IN_DEPLOY" ]]; then
    echo "Error: No containers found in deployment/${DEPLOYMENT_NAME}"
    exit 1
  fi
  CONTAINER_NAME_IN_DEPLOY="$(echo "$CONTAINERS_IN_DEPLOY" | awk '{print $1}')"
  if [[ "$(echo "$CONTAINERS_IN_DEPLOY" | wc -w)" -gt 1 ]]; then
    echo "Warning: Multiple containers in deployment/${DEPLOYMENT_NAME}: ${CONTAINERS_IN_DEPLOY}. Using '${CONTAINER_NAME_IN_DEPLOY}'."
  fi
fi
echo "Updating image for container '${CONTAINER_NAME_IN_DEPLOY}' in deployment/${DEPLOYMENT_NAME} to ${FULL_IMAGE}"
kubectl -n "$NAMESPACE" set image deployment/"$DEPLOYMENT_NAME" "${CONTAINER_NAME_IN_DEPLOY}=${FULL_IMAGE}"

# 5) Annotate to roll pods when certs change (optional)
TLS_CHECKSUM="$(cat "$HOST_CERT_PATH" "$HOST_KEY_PATH" | sha256sum | awk '{print $1}')"
kubectl -n "$NAMESPACE" annotate deployment/"$DEPLOYMENT_NAME" tls-checksum="$TLS_CHECKSUM" --overwrite

# 6) Prefer not to force pulls for a local image
kubectl -n "$NAMESPACE" patch deployment "$DEPLOYMENT_NAME" \
  --type='json' \
  -p="[
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/imagePullPolicy\",\"value\":\"IfNotPresent\"}
  ]" || true

# 7) Wait for rollout
kubectl -n "$NAMESPACE" rollout status deployment/"$DEPLOYMENT_NAME" --timeout=180s

# ===== Ingress controller and MetalLB setup =====

echo "Enabling ingress addon (nginx)"
minikube addons enable ingress >/dev/null || true
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s || true

# Ensure ingress-nginx controller Service is LoadBalancer
SVC_TYPE="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.type}' 2>/dev/null || echo "")"
if [[ "$SVC_TYPE" != "LoadBalancer" ]]; then
  kubectl -n ingress-nginx patch svc ingress-nginx-controller -p '{"spec":{"type":"LoadBalancer"}}'
fi

echo "Enabling MetalLB addon"
minikube addons enable metallb >/dev/null || true

echo "Waiting for MetalLB components (controller & speaker) to be ready..."
kubectl -n metallb-system rollout status deploy/controller --timeout=