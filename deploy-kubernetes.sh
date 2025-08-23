#!/usr/bin/env bash
set -euo pipefail

# ===== Cluster targeting (override if needed) =====
# Example:
#   KUBECONFIG_PATH=/etc/kubernetes/admin.conf KUBE_CONTEXT=kubernetes-admin@kubernetes ./deploy-kubernetes.sh
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

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-awroberts-web}"      # Deployment name
CONTAINER_NAME_IN_DEPLOY="${CONTAINER_NAME_IN_DEPLOY:-}"  # optional: leave empty to auto-detect
MANIFEST_DIR="${MANIFEST_DIR:-./k8s}"                     # folder with deployment/service/ingress YAMLs
INGRESS_NAME="${INGRESS_NAME:-awroberts-web}"             # optional: existing Ingress name to show status
SERVICE_NAME="${SERVICE_NAME:-awroberts-web}"             # Service referenced by the Ingress
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

# Bootstrap options (single-node kubeadm + Flannel)
CLUSTER_BOOTSTRAP="${CLUSTER_BOOTSTRAP:-true}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"     # Flannel default

# Ingress controller mode
# true  => hostNetwork: controller binds directly to node ports 80/443 (no NodePorts)
# false => NodePort: controller uses NodePorts (router forwards to high ports)
INGRESS_HOSTNETWORK="${INGRESS_HOSTNETWORK:-true}"

# Helper: sudo if not root
sudo_if_needed() { if [[ $EUID -ne 0 ]]; then sudo "$@"; else "$@"; fi; }

# Ensure current user has a readable kubeconfig if admin.conf exists
if [[ -f /etc/kubernetes/admin.conf ]]; then
  if [[ ! -r /etc/kubernetes/admin.conf ]]; then
    echo "Preparing kubeconfig for current user from /etc/kubernetes/admin.conf..."
    mkdir -p "$HOME/.kube"
    sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    export KUBECONFIG="$HOME/.kube/config"
  fi
fi

# ===== Pre-flight: core tools =====
command -v docker >/dev/null 2>&1 || { echo "docker not found"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl not found"; exit 1; }

# Enforce Docker Buildx availability (no fallback)
if ! docker buildx version >/dev/null 2>&1; then
  echo "Docker Buildx is required but not available."
  echo "On Debian/Ubuntu/Mint install: sudo apt-get install -y docker-buildx-plugin"
  echo "Docs: https://docs.docker.com/build/buildx/install/"
  exit 1
fi

# Ensure kubeadm/kubelet/kubectl are installed (auto-install if missing)
if ! command -v kubeadm >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
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

# Ensure containerd exists
if ! command -v containerd >/dev/null 2>&1; then
  echo "Installing containerd..."
  sudo_if_needed apt-get update
  sudo_if_needed apt-get install -y containerd
fi

[[ -f "$HOST_CERT_PATH" ]] || { echo "Cert not found at $HOST_CERT_PATH"; exit 1; }
[[ -f "$HOST_KEY_PATH" ]] || { echo "Key not found at $HOST_KEY_PATH"; exit 1; }
[[ -d "$MANIFEST_DIR" ]] || { echo "Manifest directory not found: $MANIFEST_DIR"; exit 1; }

# ===== Optional: bootstrap kubeadm single-node with Flannel if no cluster =====
if [[ "${CLUSTER_BOOTSTRAP}" == "true" ]]; then
  # If control plane is already present (files/ports), skip re-init and just ensure kubeconfig
  NEED_INIT="false"
  if kubectl get nodes >/dev/null 2>&1; then
    NEED_INIT="false"
  else
    if [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]] || \
       sudo_if_needed ss -lnt '( sport = :6443 )' | grep -q 6443; then
      echo "Existing kubeadm control plane detected; skipping kubeadm init."
      # Ensure kubeconfig for current user
      if [[ -f /etc/kubernetes/admin.conf ]]; then
        mkdir -p "$HOME/.kube"
        sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
        sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"
        export KUBECONFIG="$HOME/.kube/config"
      fi
      kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null 2>&1 || true
    else
      NEED_INIT="true"
    fi
  fi

  if [[ "${NEED_INIT}" == "true" ]]; then
    echo "No reachable Kubernetes cluster via kubectl. Bootstrapping control plane with kubeadm (Flannel)..."

    # 1) Prep: disable swap and set sysctls
    echo "Disabling swap and updating /etc/fstab..."
    sudo_if_needed swapoff -a || true
    if [[ -f /etc/fstab ]]; then
      sudo_if_needed sed -i.bak -E 's@^([^#].*\s+swap\s+)@#\1@' /etc/fstab || true
    fi

    echo "Configuring kernel sysctls for bridged traffic and forwarding..."
    sudo_if_needed modprobe br_netfilter || true
    sudo_if_needed tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    sudo_if_needed sysctl --system >/dev/null

    # 2) Ensure containerd uses systemd cgroups
    echo "Ensuring containerd uses systemd cgroups..."
    sudo_if_needed mkdir -p /etc/containerd
    if ! sudo_if_needed test -f /etc/containerd/config.toml; then
      containerd config default | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
    fi
    sudo_if_needed sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
    sudo_if_needed systemctl enable --now containerd
    sudo_if_needed systemctl restart containerd

    # 3) kubeadm init with Flannel pod CIDR
    echo "Initializing control plane with pod CIDR ${POD_CIDR}..."
    sudo_if_needed kubeadm init --pod-network-cidr="${POD_CIDR}"

    # 4) Configure kubectl for current user
    echo "Configuring kubeconfig for current user..."
    mkdir -p "$HOME/.kube"
    sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    export KUBECONFIG="$HOME/.kube/config"

    # 5) Install Flannel CNI
    echo "Installing Flannel CNI..."
    kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

    # 6) Allow scheduling on control plane (single-node)
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

    # 7) Wait for node Ready
    echo "Waiting for node to become Ready..."
    kubectl wait --for=condition=Ready node --all --timeout=300s || true
  fi
fi

# ===== Info =====
CTX="$(kubectl config current-context || true || echo)"
if [[ -z "${CTX}" ]]; then
  echo "No current kubectl context is set. Set KUBECONFIG to your kubeadm admin.conf or run kubeadm init first."
  exit 1
fi
echo "Current kube-context: ${CTX}"
echo "Assuming kubeadm/containerd runtime"

# ===== Ensure containerd config each run (idempotent) =====
echo "Ensuring containerd config exists and uses systemd cgroups..."
sudo_if_needed mkdir -p /etc/containerd
if ! sudo_if_needed test -f /etc/containerd/config.toml; then
  containerd config default | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
fi
sudo_if_needed sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
# Ensure CRI pause image matches kubeadm v1.30 recommendation (3.9)
if grep -q 'sandbox_image' /etc/containerd/config.toml; then
  sudo_if_needed sed -i 's#sandbox_image = ".*"#sandbox_image = "registry.k8s.io/pause:3.9"#' /etc/containerd/config.toml || true
else
  # Insert under the CRI plugin section
  sudo_if_needed awk '1;/\[plugins\."io.containerd.grpc.v1.cri"\]/{print "  sandbox_image = \"registry.k8s.io/pause:3.9\""}' /etc/containerd/config.toml | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
fi
sudo_if_needed systemctl enable --now containerd
sudo_if_needed systemctl restart containerd
sudo_if_needed ctr -n k8s.io images ls >/dev/null 2>&1 || true

# ===== Verify kubelet cgroup driver =====
if [[ -f /var/lib/kubelet/config.yaml ]]; then
  if ! grep -q '^cgroupDriver: systemd' /var/lib/kubelet/config.yaml; then
    echo "Warning: kubelet cgroupDriver is not 'systemd'. With containerd, 'systemd' is recommended."
    # Auto-fix if allowed (set AUTO_FIX_KUBELET_CGROUP=false to disable)
    if [[ "${AUTO_FIX_KUBELET_CGROUP:-true}" == "true" ]]; then
      echo "Setting kubelet cgroupDriver to systemd and restarting kubelet..."
      if grep -q '^cgroupDriver:' /var/lib/kubelet/config.yaml; then
        sudo_if_needed sed -i -E 's/^cgroupDriver: .*/cgroupDriver: systemd/' /var/lib/kubelet/config.yaml || true
      else
        echo "cgroupDriver: systemd" | sudo_if_needed tee -a /var/lib/kubelet/config.yaml >/dev/null
      fi
      sudo_if_needed systemctl restart kubelet || true
    fi
  fi
fi

# ===== Ensure ingress-nginx (bare-metal) is installed =====
echo "Ensuring ingress-nginx controller is installed (bare-metal preset)..."
if ! kubectl -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
fi

# If desired, switch ingress-nginx to hostNetwork so it binds to node ports 80/443
if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
  echo "Configuring ingress-nginx to use hostNetwork (binds to node ports 80/443)..."
  # Patch Deployment to use hostNetwork and appropriate DNS policy
  kubectl -n ingress-nginx patch deploy ingress-nginx-controller --type='json' -p='[
    {"op":"add","path":"/spec/template/spec/hostNetwork","value":true},
    {"op":"add","path":"/spec/template/spec/dnsPolicy","value":"ClusterFirstWithHostNet"}
  ]' || true

  # Ensure the Service is ClusterIP (no NodePorts required)
  kubectl -n ingress-nginx patch svc ingress-nginx-controller --type=merge -p='{
    "spec":{
      "type":"ClusterIP",
      "ports":[
        {"name":"http","port":80,"targetPort":"http","protocol":"TCP"},
        {"name":"https","port":443,"targetPort":"https","protocol":"TCP"}
      ]
    }
  }' || true
else
  echo "Using ingress-nginx NodePort mode (router must forward WAN 80/443 to NodePorts)."
fi

echo "Waiting for ingress-nginx-controller to become Ready..."
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s || true

echo "Ingress controller Service status:"
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide || true

# Discover NodePort values for HTTP/HTTPS if in NodePort mode (fallback to common defaults if not found)
HTTP_NODEPORT=""
HTTPS_NODEPORT=""
if [[ "${INGRESS_HOSTNETWORK}" != "true" ]]; then
  HTTP_NODEPORT="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{range .spec.ports[?(@.name=="http")]}{.nodePort}{end}' 2>/dev/null || true)"
  HTTPS_NODEPORT="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{range .spec.ports[?(@.name=="https")]}{.nodePort}{end}' 2>/dev/null || true)"
  if [[ -z "${HTTP_NODEPORT}" ]]; then HTTP_NODEPORT="30080"; fi
  if [[ -z "${HTTPS_NODEPORT}" ]]; then HTTPS_NODEPORT="30443"; fi
fi

# ===== Safe pruning: keep current image and any image in use by pods =====
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
          sudo_if_needed ctr -n k8s.io images rm "$ref" || true
        fi
      fi
    done < <(sudo_if_needed ctr -n k8s.io images ls -q 2>/dev/null || true)
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

# ===== Build local image with Buildx (strict; no docker build fallback) =====
if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
  docker buildx create --name "$BUILDER_NAME" --use >/dev/null
else
  docker buildx use "$BUILDER_NAME" >/dev/null
fi

echo "Building local image ${FULL_IMAGE} for ${PLATFORM} (buildx)"
docker buildx build \
  --platform "${PLATFORM}" \
  -t "${FULL_IMAGE}" \
  --load \
  "${BUILD_CONTEXT}"

# ===== Make the image available to the cluster (no external registry) =====
echo "Importing image into containerd (kubeadm)"
if docker save "${FULL_IMAGE}" | sudo_if_needed ctr -n k8s.io images import -; then
  echo "Image imported into containerd."
else
  echo "Image import via pipe failed. Falling back to tar file..."
  TAR_NAME="$(echo "${IMAGE_NAME}_${IMAGE_TAG}" | tr '/:' '__').tar"
  docker save -o "${TAR_NAME}" "${FULL_IMAGE}"
  sudo_if_needed ctr -n k8s.io images import "${TAR_NAME}"
fi

# Prune old images (keeps current and anything in use)
cleanup_old_images "${IMAGE_NAME_BASE}" "${RETENTION_DAYS}" "${FULL_IMAGE}"

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

# ===== Notes =====
# To be reachable from the Internet:
#  - Allow inbound TCP 80/443 on the node.
#  - Router/NAT:
if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
  echo "- Router/NAT: forward WAN 80 -> NODE_IP:80 and WAN 443 -> NODE_IP:443 (ingress-nginx hostNetwork)."
else
  echo "- Router/NAT: forward WAN 80 -> NODE_IP:${HTTP_NODEPORT} and WAN 443 -> NODE_IP:${HTTPS_NODEPORT} (ingress-nginx NodePorts)."
fi
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
if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
  echo "- Router/NAT: forward WAN 80 -> NODE_IP:80 and WAN 443 -> NODE_IP:443."
else
  echo "- Router/NAT: forward WAN 80 -> NODE_IP:${HTTP_NODEPORT} and WAN 443 -> NODE_IP:${HTTPS_NODEPORT}."
fi
echo "- DNS: set A/AAAA for:"
echo "  * ${HOST_A}"
echo "  * ${HOST_B}"
echo "  to your public IP: ${PUB_IP:-<your-public-ip>}."
echo
echo "Rebuild/redeploy loop (no registry):"
echo "  docker buildx build --platform ${PLATFORM} -t ${FULL_IMAGE} --load ${BUILD_CONTEXT}"
echo "  docker save ${FULL_IMAGE} | sudo ctr -n k8s.io images import -"
echo "  kubectl -n ${NAMESPACE} rollout restart deploy/${DEPLOYMENT_NAME}"
echo "  kubectl -n ${NAMESPACE} rollout status deploy/${DEPLOYMENT_NAME}"