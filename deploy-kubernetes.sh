#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
NAMESPACE="${NAMESPACE:-awroberts}"
SECRET_NAME="${SECRET_NAME:-awroberts-tls}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-awroberts-web}"     # Deployment name
CONTAINER_NAME_IN_DEPLOY="${CONTAINER_NAME_IN_DEPLOY:-}" # leave empty to auto-detect
MANIFEST_DIR="${MANIFEST_DIR:-./k8s}"                    # folder with deployment/service/ingress YAMLs
INGRESS_NAME="${INGRESS_NAME:-awroberts-web}"            # matches your existing Ingress YAML
SERVICE_NAME="${SERVICE_NAME:-awroberts-web}"            # Service referenced by the Ingress
HOST_A="${HOST_A:-awroberts.co.uk}"
HOST_B="${HOST_B:-www.awroberts.co.uk}"

# TLS certs (full chain + unencrypted key)
HOST_CERT_PATH="${HOST_CERT_PATH:-/path/to/fullchain.crt}"
HOST_KEY_PATH="${HOST_KEY_PATH:-/path/to/privkey.key}"

# Local image build settings
IMAGE_NAME="${IMAGE_NAME:-awroberts}"     # untagged base
IMAGE_TAG="${IMAGE_TAG:-v1}"              # tag to deploy
IMAGE_NAME_BASE="${IMAGE_NAME%%:*}"       # strip any tag if present
FULL_IMAGE="${IMAGE_NAME_BASE}:${IMAGE_TAG}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"
PLATFORM="${PLATFORM:-linux/amd64}"       # set to your dev arch (e.g., linux/arm64)
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

# Ensure a Service exists; if not, create one for the Deployment (ClusterIP for Ingress)
if ! kubectl -n "$NAMESPACE" get svc "${SERVICE_NAME}" >/dev/null 2>&1; then
  echo "No Service named '${SERVICE_NAME}' found. Creating one for the Deployment '${DEPLOYMENT_NAME}'."
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

# ===== Minikube Ingress automation (enable addon, wait, hosts entries, verify) =====
if command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1 && [[ "$CTX" == minikube* ]]; then
  echo "Minikube detected. Enabling ingress addon (idempotent)."
  minikube addons enable ingress >/dev/null || true

  echo "Waiting for ingress-nginx controller to be ready..."
  # Try common controller names depending on minikube version
  kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s || \
  kubectl -n ingress-nginx rollout status deploy/nginx-ingress-controller --timeout=180s || true
  kubectl -n ingress-nginx get pods

  echo "Verifying Ingress '${INGRESS_NAME}' exists in namespace '${NAMESPACE}'..."
  if ! kubectl -n "$NAMESPACE" get ingress "${INGRESS_NAME}" >/dev/null 2>&1; then
    echo "Warning: Ingress '${INGRESS_NAME}' not found. Ensure it exists in ${MANIFEST_DIR} and references service '${SERVICE_NAME}'."
  else
    kubectl -n "$NAMESPACE" get ingress "${INGRESS_NAME}"
  fi

  echo "Ensuring Service '${SERVICE_NAME}' has endpoints..."
  kubectl -n "$NAMESPACE" get endpoints "${SERVICE_NAME}" -o wide || true

  echo "Resolving Minikube IP..."
  MINIKUBE_IP="$(minikube ip)"
  echo "Minikube IP: ${MINIKUBE_IP}"

  add_host_entry() {
    local host="$1"
    # If entry exists but points elsewhere, update it; otherwise append
    if grep -qE "^[^#]*\b${host}\b" /etc/hosts; then
      if ! grep -qE "^${MINIKUBE_IP}[[:space:]].*\b${host}\b" /etc/hosts; then
        echo "Updating /etc/hosts entry for ${host} to ${MINIKUBE_IP}..."
        tmpfile="$(mktemp)"
        awk -v h="${host}" '!($0 ~ "^[^#].*\\b" h "\\b") {print}' /etc/hosts > "${tmpfile}"
        if echo "${MINIKUBE_IP} ${host}" >> "${tmpfile}" 2>/dev/null; then
          :
        else
          echo "Failed to append to temp file"; rm -f "${tmpfile}"; exit 1
        fi
        if cp "${tmpfile}" /etc/hosts 2>/dev/null; then
          :
        else
          echo "Escalating with sudo to update /etc/hosts..."
          sudo cp "${tmpfile}" /etc/hosts
        fi
        rm -f "${tmpfile}"
      else
        echo "/etc/hosts already has ${host} -> ${MINIKUBE_IP}"
      fi
    else
      echo "Adding ${host} -> ${MINIKUBE_IP} to /etc/hosts..."
      if echo "${MINIKUBE_IP} ${host}" >> /etc/hosts 2>/dev/null; then
        :
      else
        echo "Escalating with sudo to append /etc/hosts..."
        echo "${MINIKUBE_IP} ${host}" | sudo tee -a /etc/hosts >/dev/null
      fi
    fi
  }

  # Add both hosts
  add_host_entry "${HOST_A}"
  add_host_entry "${HOST_B}"

  echo "Testing HTTP reachability via Ingress..."
  set +e
  curl -sS -I "http://${HOST_A}/" || true
  curl -sS -I "http://${HOST_B}/" || true

  echo "Testing HTTPS reachability via Ingress (ignoring cert trust issues)..."
  curl -k -sS -I "https://${HOST_A}/" || true
  curl -k -sS -I "https://${HOST_B}/" || true
  set -e

  echo "If you see HTTP/1.1 200 OK above, Ingress routing is working."
fi

echo "Deployment complete: ${FULL_IMAGE}"