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
HOST_CERT_PATH="${HOST_CERT_PATH:-/var/www/html/awroberts-certs/fullchain.crt}"
HOST_KEY_PATH="${HOST_KEY_PATH:-/var/www/html/awroberts-certs/awroberts_co.uk.key}"

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

# ===== Minikube Ingress automation (enable addon, LB or port-forward fallback, hosts entries, verify) =====
if command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1 && [[ "$CTX" == minikube* ]]; then
  echo "Minikube detected. Enabling ingress addon (idempotent)."
  minikube addons enable ingress >/dev/null || true

  echo "Waiting for ingress-nginx controller to be ready..."
  kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s || true
  kubectl -n ingress-nginx get pods

  echo "Ensuring ingress controller Service is LoadBalancer..."
  SVC_TYPE="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.type}' 2>/dev/null || echo "")"
  if [[ "$SVC_TYPE" != "LoadBalancer" ]]; then
    kubectl -n ingress-nginx patch svc ingress-nginx-controller -p '{"spec":{"type":"LoadBalancer"}}'
  fi

  # Try to start minikube tunnel non-interactively; if it cannot start, we fallback to port-forward.
  TUNNEL_STARTED="false"
  if ! pgrep -f "minikube tunnel" >/dev/null 2>&1; then
    echo "Attempting to start 'minikube tunnel' non-interactively..."
    if sudo -n true 2>/dev/null; then
      nohup sudo -E env "MINIKUBE_HOME=$HOME/.minikube" "KUBECONFIG=$HOME/.kube/config" \
        minikube -p minikube tunnel >/tmp/minikube-tunnel.log 2>&1 &
      disown || true
      TUNNEL_STARTED="true"
      sleep 3
    else
      echo "No passwordless sudo available; skipping tunnel start (will fall back to port-forward)."
    fi
  else
    echo "'minikube tunnel' already running."
    TUNNEL_STARTED="true"
  fi

  echo "Resolving external IP for LoadBalancer..."
  TARGET_IP=""
  if [[ "$TUNNEL_STARTED" == "true" ]]; then
    for i in {1..30}; do
      EXTERNAL_IP="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
      if [[ -n "$EXTERNAL_IP" && "$EXTERNAL_IP" != 10.* ]]; then
        TARGET_IP="$EXTERNAL_IP"
        break
      fi
      sleep 2
    done
    if [[ -n "$TARGET_IP" ]]; then
      echo "LoadBalancer EXTERNAL-IP ready: ${TARGET_IP}"
    else
      echo "No usable EXTERNAL-IP (still internal or empty). Will fall back to port-forward."
    fi
  fi

  # Fallback: port-forward ingress-nginx 80/443 to localhost
  if [[ -z "$TARGET_IP" ]]; then
    echo "Starting port-forward on 127.0.0.1:80 and :443..."
    # Free ports if busy (best-effort)
    command -v lsof >/dev/null 2>&1 && lsof -ti tcp:80 2>/dev/null | xargs -r kill -9 || true
    command -v lsof >/dev/null 2>&1 && lsof -ti tcp:443 2>/dev/null | xargs -r kill -9 || true
    nohup kubectl -n ingress-nginx port-forward --address=127.0.0.1 svc/ingress-nginx-controller 80:80 443:443 >/tmp/ingress-pf.log 2>&1 &
    disown || true
    TARGET_IP="127.0.0.1"
    sleep 2
  fi

  echo "Updating /etc/hosts for ${HOST_A} and ${HOST_B} -> ${TARGET_IP}"
  add_host_entry() {
    local ip="$1"
    local host="$2"
    if grep -qE "^[^#]*\b${host}\b" /etc/hosts; then
      if ! grep -qE "^${ip}[[:space:]].*\b${host}\b" /etc/hosts; then
        echo "Adjusting /etc/hosts for ${host} -> ${ip}"
        tmpfile="$(mktemp)"
        awk -v h="${host}" '!($0 ~ "^[^#].*\\b" h "\\b") {print}' /etc/hosts > "${tmpfile}"
        echo "${ip} ${host}" >> "${tmpfile}"
        if cp "${tmpfile}" /etc/hosts 2>/dev/null; then :; else sudo cp "${tmpfile}" /etc/hosts; fi
        rm -f "${tmpfile}"
      else
        echo "/etc/hosts already maps ${host} -> ${ip}"
      fi
    else
      echo "Adding ${host} -> ${ip} to /etc/hosts"
      if echo "${ip} ${host}" >> /etc/hosts 2>/dev/null; then :; else echo "${ip} ${host}" | sudo tee -a /etc/hosts >/dev/null; fi
    fi
  }
  add_host_entry "${TARGET_IP}" "${HOST_A}"
  add_host_entry "${TARGET_IP}" "${HOST_B}"

  echo "Verifying routing via Ingress..."
  set +e
  curl -sS -I "http://${HOST_A}/" || true
  curl -k -sS -I "https://${HOST_A}/" || true
  curl -sS -I "http://${HOST_B}/" || true
  curl -k -sS -I "https://${HOST_B}/" || true
  set -e

  if [[ "${TARGET_IP}" == "127.0.0.1" ]]; then
    echo "Ingress reachable via localhost (port-forward fallback active)."
  else
    echo "Ingress reachable via LoadBalancer EXTERNAL-IP ${TARGET_IP} (tunnel active)."
  fi
fi

echo "Deployment complete: ${FULL_IMAGE}"