#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
NAMESPACE="${NAMESPACE:-awroberts}"
SECRET_NAME="${SECRET_NAME:-awroberts-tls}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-awroberts-web}"   # your Deployment name
CONTAINER_NAME_IN_DEPLOY="${CONTAINER_NAME_IN_DEPLOY:-}" # leave empty to auto-detect from Deployment
MANIFEST_DIR="${MANIFEST_DIR:-./k8s}"                  # folder with deployment/service/ingress YAMLs
INGRESS_NAME="${INGRESS_NAME:-}"                       # optional: wait for LB address

# TLS certs (full chain + unencrypted key)
HOST_CERT_PATH="${HOST_CERT_PATH:-/path/to/fullchain.crt}"
HOST_KEY_PATH="${HOST_KEY_PATH:-/path/to/privkey.key}"

# Local image build settings (no registry)
IMAGE_NAME="${IMAGE_NAME:-awroberts}"   # keep UNTAGGED here
IMAGE_TAG="${IMAGE_TAG:-v1}"            # single tag to deploy
IMAGE_NAME_BASE="${IMAGE_NAME%%:*}"     # strip any tag if passed via env
FULL_IMAGE="${IMAGE_NAME_BASE}:${IMAGE_TAG}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"
PLATFORM="${PLATFORM:-linux/amd64}"     # set to your dev arch (e.g., linux/arm64)
BUILDER_NAME="${BUILDER_NAME:-localbuilder}"

# ===== Pre-flight checks =====
command -v docker >/dev/null 2>&1 || { echo "docker not found"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
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
if command -v kind >/dev/null 2>&1 && kind get clusters >/dev/null 2>&1 && [[ "$CTX" == kind* ]]; then
  # Detect kind cluster name from context if possible
  if [[ "$CTX" == "kind" ]]; then
    KIND_CLUSTER_NAME="kind"
  elif [[ "$CTX" == kind-* ]]; then
    KIND_CLUSTER_NAME="${CTX#kind-}"
  else
    KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
  fi
  echo "Loading image into kind cluster: ${KIND_CLUSTER_NAME}"
  kind load docker-image "${FULL_IMAGE}" --name "${KIND_CLUSTER_NAME}"
elif command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1 && [[ "$CTX" == minikube* ]]; then
  echo "Loading image into minikube"
  minikube image load "${FULL_IMAGE}"
else
  # Docker Desktop Kubernetes shares the Docker daemon; nothing to do.
  # For remote clusters, a registry is required.
  if [[ "$CTX" != "docker-desktop" ]]; then
    echo "Note: Current context '${CTX}' may not see local images. For remote clusters, push to a registry or load images to nodes."
  fi
fi

# ===== Kubernetes deploy =====

# 1) Ensure namespace exists
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

# 2) Create or update the TLS Secret idempotently
kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" \
  --cert="$HOST_CERT_PATH" \
  --key="$HOST_KEY_PATH" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3) Apply manifests (Deployment, Service, Ingress, etc.)
echo "Applying manifests from: ${MANIFEST_DIR}"
kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR"

# 4) Determine the container name (auto-detect if not provided)
if [[ -z "$CONTAINER_NAME_IN_DEPLOY" ]]; then
  CONTAINERS_IN_DEPLOY="$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[*].name}')"
  if [[ -z "$CONTAINERS_IN_DEPLOY" ]]; then
    echo "Error: No containers found in deployment/${DEPLOYMENT_NAME}"
    exit 1
  fi
  # Use the first container if multiple
  CONTAINER_NAME_IN_DEPLOY="$(echo "$CONTAINERS_IN_DEPLOY" | awk '{print $1}')"
  if [[ "$(echo "$CONTAINERS_IN_DEPLOY" | wc -w)" -gt 1 ]]; then
    echo "Warning: Multiple containers detected in deployment/${DEPLOYMENT_NAME}: ${CONTAINERS_IN_DEPLOY}. Using '${CONTAINER_NAME_IN_DEPLOY}'."
  fi
fi
echo "Updating image for container '${CONTAINER_NAME_IN_DEPLOY}' in deployment/${DEPLOYMENT_NAME} to ${FULL_IMAGE}"

# 5) Point the Deployment at the freshly built local image
kubectl -n "$NAMESPACE" set image deployment/"$DEPLOYMENT_NAME" \
  "${CONTAINER_NAME_IN_DEPLOY}=${FULL_IMAGE}"

# 6) Ensure pods roll when certs change (optional but recommended)
TLS_CHECKSUM="$(cat "$HOST_CERT_PATH" "$HOST_KEY_PATH" | sha256sum | awk '{print $1}')"
kubectl -n "$NAMESPACE" annotate deployment/"$DEPLOYMENT_NAME" \
  tls-checksum="$TLS_CHECKSUM" --overwrite

# 7) Prefer not to force pulls for a local image
kubectl -n "$NAMESPACE" patch deployment "$DEPLOYMENT_NAME" \
  --type='json' \
  -p="[
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/imagePullPolicy\",\"value\":\"IfNotPresent\"}
  ]" || true

# 8) Wait for rollout
kubectl -n "$NAMESPACE" rollout status deployment/"$DEPLOYMENT_NAME" --timeout=180s

# 9) (Optional) Wait for Ingress to get an address
if [[ -n "$INGRESS_NAME" ]]; then
  kubectl -n "$NAMESPACE" wait ingress/"$INGRESS_NAME" \
    --for=jsonpath='{.status.loadBalancer.ingress[0]}' --timeout=180s || true
fi

echo "Deployment complete: ${FULL_IMAGE}"