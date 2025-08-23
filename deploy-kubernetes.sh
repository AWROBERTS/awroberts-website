#!/usr/bin/env bash
set -euo pipefail

# Cluster targeting (override if needed)
#   export KUBECONFIG_PATH=/etc/kubernetes/admin.conf
#   export KUBE_CONTEXT=kubernetes-admin@kubernetes
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"
if [[ -f "${KUBECONFIG_PATH}" ]]; then
  export KUBECONFIG="${KUBECONFIG_PATH}"
fi
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  kubectl config use-context "${KUBE_CONTEXT}" >/dev/null 2>&1 || true
fi

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
IMAGE_NAME="${IMAGE_NAME:-awroberts}"     # repository/name (can include registry)
USE_TIMESTAMP="${USE_TIMESTAMP:-true}"    # true -> auto timestamp tag if IMAGE_TAG not set
RETENTION_DAYS="${RETENTION_DAYS:-7}"     # prune timestamp-tagged images older than this
IMAGE_TAG="${IMAGE_TAG:-}"                # optional; if unset and USE_TIMESTAMP=true, a timestamp is used
IMAGE_NAME_BASE="${IMAGE_NAME%%:*}"       # strip any tag if present
if [[ "${USE_TIMESTAMP}" == "true" && -z "${IMAGE_TAG}" ]]; then
  IMAGE_TAG="$(date -u +%Y%m%d-%H%M%S)"
fi
FULL_IMAGE="${IMAGE_NAME_BASE}:${IMAGE_TAG}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"
PLATFORM="${PLATFORM:-linux/amd64}"       # set to your dev arch (e.g., linux/arm64)
BUILDER_NAME="${BUILDER_NAME:-localbuilder}"

# Optional kubeadm bootstrap (one-time) - set CLUSTER_BOOTSTRAP=true to enable
CLUSTER_BOOTSTRAP="${CLUSTER_BOOTSTRAP:-false}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"         # matches flannel default
CNI_TYPE="${CNI_TYPE:-flannel}"               # flannel|calico
ENABLE_INGRESS="${ENABLE_INGRESS:-true}"
SKIP_SWAP_DISABLE="${SKIP_SWAP_DISABLE:-false}"

# Helper to run sudo when not root
sudo_if_needed() {
  if [[ $EUID -ne 0 ]]; then sudo "$@"; else "$@"; fi
}

# If asked to bootstrap and no cluster is reachable, run kubeadm init flow
if [[ "${CLUSTER_BOOTSTRAP}" == "true" ]]; then
  if ! kubectl get nodes >/dev/null 2>&1; then
    echo "No Kubernetes cluster detected via kubectl. Bootstrapping single-node control plane with kubeadm..."

    # 1) Disable swap (required by kubelet)
    if [[ "${SKIP_SWAP_DISABLE}" != "true" ]]; then
      echo "Disabling swap..."
      sudo_if_needed swapoff -a || true
      if [[ -f /etc/fstab ]]; then
        sudo_if_needed sed -i.bak -E 's@^([^#].*\s+swap\s+)@#\1@' /etc/fstab || true
      fi
    fi

    # 2) Kernel params for Kubernetes networking
    echo "Configuring sysctl for bridged traffic and ip_forward..."
    sudo_if_needed modprobe br_netfilter || true
    sudo_if_needed tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    sudo_if_needed sysctl --system >/dev/null

    # 3) Install and configure containerd
    if ! command -v containerd >/dev/null 2>&1; then
      echo "Installing containerd..."
      sudo_if_needed apt-get update
      sudo_if_needed apt-get install -y containerd
    fi
    echo "Ensuring containerd uses systemd cgroups..."
    sudo_if_needed mkdir -p /etc/containerd
    if ! sudo_if_needed test -f /etc/containerd/config.toml; then
      containerd config default | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
    fi
    sudo_if_needed sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
    sudo_if_needed systemctl enable --now containerd

    # 4) Install kubeadm, kubelet, kubectl if missing
    if ! command -v kubeadm >/dev/null 2>&1; then
      echo "Installing kubeadm, kubelet, kubectl..."
      sudo_if_needed apt-get update
      sudo_if_needed apt-get install -y apt-transport-https ca-certificates curl gpg
      sudo_if_needed curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg \
        https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key
      echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | \
        sudo_if_needed tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
      sudo_if_needed apt-get update
      sudo_if_needed apt-get install -y kubelet kubeadm kubectl
      sudo_if_needed systemctl enable --now kubelet
    fi

    # 5) kubeadm init
    echo "Initializing control plane with pod CIDR ${POD_CIDR}..."
    sudo_if_needed kubeadm init --pod-network-cidr="${POD_CIDR}"

    # 6) Kubeconfig for current user (if not already set)
    mkdir -p "$HOME/.kube"
    sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    export KUBECONFIG="$HOME/.kube/config"

    # 7) Install CNI
    case "${CNI_TYPE}" in
      flannel|Flannel)
        echo "Installing Flannel CNI..."
        kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
        ;;
      calico|Calico)
        echo "Installing Calico CNI..."
        kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml
        ;;
      *)
        echo "Unknown CNI_TYPE='${CNI_TYPE}'. Supported: flannel, calico."
        exit 1
        ;;
    esac

    # 8) Allow scheduling on control plane (single-node)
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

    # 9) Optional ingress controller
    if [[ "${ENABLE_INGRESS}" == "true" ]]; then
      echo "Installing ingress-nginx..."
      kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
    fi

    echo "kubeadm bootstrap complete."
  else
    echo "Cluster detected; skipping kubeadm bootstrap."
  fi
fi

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

# Safe pruning: keep current image and any image in use by pods
cleanup_old_images() {
  local base="$1" days="$2" keep_image="$3"
  local now epoch_cutoff in_use_tmp
  now="$(date -u +%s)"
  epoch_cutoff=$(( now - days*24*3600 ))
  in_use_tmp="$(mktemp)"
  kubectl get pods -A -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}{range .items[*].spec.initContainers[*]}{.image}{"\n"}{end}' \
    2>/dev/null | awk 'NF' | sort -u > "$in_use_tmp" || true
  echo "Pruning timestamp-tagged images older than ${days} days for base '${base}:'"
  echo "Keeping current image: ${keep_image}"
  echo "Also keeping any image currently used by running pods."
  _in_use() { grep -Fxq "$1" "$in_use_tmp"; }
  if command -v ctr >/dev/null 2>&1; then
    while IFS= read -r ref; do
      [[ "$ref" == ${base}:* ]] || continue
      [[ "$ref" == "$keep_image" ]] && continue
      _in_use "$ref" && continue
      local tag="${ref#${base}:}"
      if [[ "$tag" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
        local d="${tag:0:4}-${tag:4:2}-${tag:6:2} ${tag:9:2}:${tag:11:2}:${tag:13:2} UTC"
        local ts; ts="$(date -u -d "$d" +%s 2>/dev/null || echo 0)"
        if (( ts > 0 && ts < epoch_cutoff )); then
          echo "  Removing containerd image: $ref (tag time: $d)"
          sudo ctr -n k8s.io images rm "$ref" || true
        fi
      fi
    done < <(sudo ctr -n k8s.io images ls -q 2>/dev/null || true)
  fi
  while IFS= read -r ref; do
    [[ "$ref" == ${base}:* ]] || continue
    [[ "$ref" == "$keep_image" ]] && continue
    _in_use "$ref" && continue
    local tag="${ref#${base}:}"
    if [[ "$tag" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
      local d="${tag:0:4}-${tag:4:2}-${tag:6:2} ${tag:9:2}:${tag:11:2}:${tag:13:2} UTC"
      local ts; ts="$(date -u -d "$d" +%s 2>/dev/null || echo 0)"
      if (( ts > 0 && ts < epoch_cutoff )); then
        echo "  Removing docker image: $ref (tag time: $d)"
        docker image rm "$ref" >/dev/null 2>&1 || true
      fi
    fi
  done < <(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)
  rm -f "$in_use_tmp"
}

# ===== Build local image with Buildx (loaded into local Docker daemon) =====
if ! docker buildx version >/dev/null 2%; then
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

# Prune old images (keeps current and anything in use)
cleanup_old_images "${IMAGE_NAME_BASE}" "${RETENTION_DAYS}" "${FULL_IMAGE}"

# ===== Kubernetes deploy =====
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" \
  --cert="$HOST_CERT_PATH" \
  --key="$HOST_KEY_PATH" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "Applying manifests from: ${MANIFEST_DIR}"
kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR"
if ! kubectl -n "$NAMESPACE" get svc "${SERVICE_NAME}" >/dev/null 2>&1; then
  echo "No Service named '${SERVICE_NAME}' found. Creating one for Deployment '${DEPLOYMENT_NAME}'."
  kubectl -n "$NAMESPACE" expose deploy "$DEPLOYMENT_NAME" \
    --name "${SERVICE_NAME}" --port=80 --target-port=80 --type=ClusterIP
fi
if [[ -z "$CONTAINER_NAME_IN_DEPLOY" ]]; then
  CONTAINERS_IN_DEPLOY="$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[*].name}')"
  if [[ -z "$CONTAINERS_IN_DEPLOY" ]]; then
    echo "Error: No containers found in deployment/${DEPLOYMENT_NAME}"; exit 1
  fi
  CONTAINER_NAME_IN_DEPLOY="$(echo "$CONTAINERS_IN_DEPLOY" | awk '{print $1}')"
  if [[ "$(echo "$CONTAINERS_IN_DEPLOY" | wc -w)" -gt 1 ]]; then
    echo "Warning: Multiple containers in deployment/${DEPLOYMENT_NAME}: ${CONTAINERS_IN_DEPLOY}. Using '${CONTAINER_NAME_IN_DEPLOY}'."
  fi
fi
echo "Updating image for container '${CONTAINER_NAME_IN_DEPLOY}' in deployment/${DEPLOYMENT_NAME} to ${FULL_IMAGE}"
kubectl -n "$NAMESPACE" set image deployment/"$DEPLOYMENT_NAME" "${CONTAINER_NAME_IN_DEPLOY}=${FULL_IMAGE}"
kubectl -n "$NAMESPACE" patch deployment "$DEPLOYMENT_NAME" \
  --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]' || true
TLS_CHECKSUM="$(cat "$HOST_CERT_PATH" "$HOST_KEY_PATH" | sha256sum | awk '{print $1}')"
kubectl -n "$NAMESPACE" annotate deployment/"$DEPLOYMENT_NAME" tls-checksum="$TLS_CHECKSUM" --overwrite
kubectl -n "$NAMESPACE" rollout status deployment/"$DEPLOYMENT_NAME" --timeout=240s

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