#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
NAMESPACE="${NAMESPACE:-awroberts}"
SECRET_NAME="${SECRET_NAME:-awroberts-tls}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-awroberts-web}"     # Deployment name
CONTAINER_NAME_IN_DEPLOY="${CONTAINER_NAME_IN_DEPLOY:-}" # leave empty to auto-detect
MANIFEST_DIR="${MANIFEST_DIR:-./k8s}"                    # folder with deployment/service/ingress YAMLs
INGRESS_NAME="${INGRESS_NAME:-awroberts-web}"            # optional: existing Ingress name to show status
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

# ===== Pre-flight checks =====
command -v docker >/dev/null 2>&1 || { echo "docker not found"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }

[[ -f "$HOST_CERT_PATH" ]] || { echo "Cert not found at $HOST_CERT_PATH"; exit 1; }
[[ -f "$HOST_KEY_PATH" ]] || { echo "Key not found at $HOST_KEY_PATH"; exit 1; }
[[ -d "$MANIFEST_DIR" ]] || { echo "Manifest directory not found: $MANIFEST_DIR"; exit 1; }

# Context (informational)
CTX="$(kubectl config current-context || true)"
echo "Current kube-context: ${CTX}"
echo "Assuming kubeadm/containerd runtime"

# ===== Verify containerd/kubelet setup (kubeadm) =====
if command -v ctr >/dev/null 2>&1; then
  echo "Verifying containerd..."
  CONTAINERD_STATUS="$(systemctl is-active containerd 2>/dev/null || true)"
  if [[ "${CONTAINERD_STATUS}" != "active" ]]; then
    echo "Warning: containerd service is not active (status: ${CONTAINERD_STATUS})."
    echo "         Start it with: sudo systemctl enable --now containerd"
  fi

  CONTAINERD_CFG="/etc/containerd/config.toml"
  if [[ -f "${CONTAINERD_CFG}" ]]; then
    if grep -q 'SystemdCgroup = false' "${CONTAINERD_CFG}"; then
      echo "Warning: SystemdCgroup=false in ${CONTAINERD_CFG}. Recommended: SystemdCgroup=true"
      echo "         Fix: sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' ${CONTAINERD_CFG} && sudo systemctl restart containerd"
    fi
  else
    echo "Note: ${CONTAINERD_CFG} not found. Consider generating a default config:"
    echo "      sudo mkdir -p /etc/containerd && containerd config default | sudo tee ${CONTAINERD_CFG} >/dev/null"
    echo "      sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' ${CONTAINERD_CFG} && sudo systemctl restart containerd"
  fi

  if ! sudo ctr -n k8s.io images ls >/dev/null 2>&1; then
    echo "Warning: Unable to list images via 'sudo ctr -n k8s.io images ls'."
    echo "         Ensure containerd is healthy and your user can run sudo."
  fi
else
  echo "Note: 'ctr' CLI not found; skipping containerd verification."
fi

if [[ -f /var/lib/kubelet/config.yaml ]]; then
  if ! grep -q '^cgroupDriver: systemd' /var/lib/kubelet/config.yaml; then
    echo "Warning: kubelet cgroupDriver is not 'systemd'."
    echo "         With containerd, 'systemd' is recommended for cgroup driver."
  fi
fi

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

# ===== Make the image available to the cluster (no external registry) =====
echo "Importing image into containerd (kubeadm)"
if docker save "${FULL_IMAGE}" | sudo ctr -n k8s.io images import -; then
  echo "Image imported into containerd."
else
  echo "Image import via pipe failed. Falling back to tar file..."
  TAR_NAME="$(echo "${IMAGE_NAME}_${IMAGE_TAG}" | tr '/:' '__').tar"
  docker save -o "${TAR_NAME}" "${FULL_IMAGE}"
  sudo ctr -n k8s.io images import "${TAR_NAME}"
fi

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

# 5) Ensure we don't force pulls (so local image is used)
kubectl -n "$NAMESPACE" patch deployment "$DEPLOYMENT_NAME" \
  --type='json' \
  -p="[
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/imagePullPolicy\",\"value\":\"IfNotPresent\"}
  ]" || true

# 6) Optional: roll pods when certs change (handy for hot cert swaps)
TLS_CHECKSUM="$(cat "$HOST_CERT_PATH" "$HOST_KEY_PATH" | sha256sum | awk '{print $1}')"
kubectl -n "$NAMESPACE" annotate deployment/"$DEPLOYMENT_NAME" tls-checksum="$TLS_CHECKSUM" --overwrite

# 7) Wait for rollout
kubectl -n "$NAMESPACE" rollout status deployment/"$DEPLOYMENT_NAME" --timeout=240s

# ===== No cluster networking magic here by default =====
# To be reachable from the Internet:
#  - Allow inbound TCP 80/443 on the node.
#  - Router/NAT: forward WAN 80 -> NODE_IP:80 and WAN 443 -> NODE_IP:443.
#  - Point your domain A/AAAA records at your public IP.

echo
echo "Deployment done. Quick status:"
kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o wide
kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" -o wide || true
if kubectl -n "$NAMESPACE" get ingress "$INGRESS_NAME" >/dev/null 2>&1; then
  kubectl -n "$NAMESPACE" get ingress "$INGRESS_NAME" -o wide
fi

NODE_IPS="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{" "}{end}')"
PUB_IP="$(curl -s https://api.ipify.org || true)"

echo
echo "Next steps to access from anywhere:"
echo "- Open firewall for inbound TCP 80 and 443 on the node."
echo "- Router/NAT: forward WAN 80 -> NODE_IP:80 and WAN 443 -> NODE_IP:443 (choose one of: ${NODE_IPS})."
echo "- DNS: set A/AAAA for:"
echo "  * ${HOST_A}"
echo "  * ${HOST_B}"
echo "  to your public IP: ${PUB_IP:-<your-public-ip>}."
echo
echo "Rebuild/redeploy loop (no registry):"
echo "  docker build -t ${FULL_IMAGE} ."
echo "  docker save ${FULL_IMAGE} | sudo ctr -n k8s.io images import -"
echo "  kubectl -n ${NAMESPACE} rollout restart deploy/${DEPLOYMENT_NAME}"
echo "  kubectl -n ${NAMESPACE} rollout status deploy/${DEPLOYMENT_NAME}"