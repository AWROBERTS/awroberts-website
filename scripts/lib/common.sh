#!/usr/bin/env bash
# Common config, defaults, and helpers. Source this first.

# Helper: sudo if not root
sudo_if_needed() { if [[ $EUID -ne 0 ]]; then sudo "$@"; else "$@"; fi; }

# Load all variables from the env file
ENV_FILE="./awroberts.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
else
  echo "❌ Environment file not found: $ENV_FILE"
  exit 1
fi

# Kernel networking setup for Kubernetes + Flannel
echo "🔧 Ensuring br_netfilter and sysctl settings for Kubernetes networking..."

sudo_if_needed modprobe br_netfilter || true
echo 'br_netfilter' | sudo_if_needed tee /etc/modules-load.d/br_netfilter.conf >/dev/null

sudo_if_needed tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo_if_needed sysctl --system

if [[ ! -f /proc/sys/net/bridge/bridge-nf-call-iptables ]]; then
  echo "❌ br_netfilter not loaded correctly. Networking may fail."
  exit 1
fi

echo "✅ Sysctl values applied:"
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.ipv4.ip_forward

# Derived values (only if not already set)
: "${IMAGE_NAME_BASE:=${IMAGE_NAME%%:*}}"
: "${IMAGE_TAG:=$(date -u +%Y%m%d-%H%M%S)}"
: "${FULL_IMAGE:=${IMAGE_NAME_BASE}:${IMAGE_TAG}}"
: "${LATEST_IMAGE:=${IMAGE_NAME_BASE}:latest}"

# TLS secret creation
ensure_tls_secret() {
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
  kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" \
    --cert="$HOST_CERT_PATH" \
    --key="$HOST_KEY_PATH" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# Preflight checks
preflight_core_tools() {
  command -v docker >/dev/null 2>&1 || { echo "❌ docker not found"; exit 1; }
  command -v curl >/dev/null 2>&1 || { echo "❌ curl not found"; exit 1; }
  docker buildx version >/dev/null 2>&1 || {
    echo "❌ Docker Buildx is required but not available."
    exit 1
  }
  [[ -f "$HOST_CERT_PATH" ]] || { echo "❌ Cert not found at $HOST_CERT_PATH"; exit 1; }
  [[ -f "$HOST_KEY_PATH" ]] || { echo "❌ Key not found at $HOST_KEY_PATH"; exit 1; }
  [[ -d "$MANIFEST_DIR" ]] || { echo "❌ Manifest directory not found: $MANIFEST_DIR"; exit 1; }

  if ! command -v helm &> /dev/null; then
    echo "📦 Helm not found. Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
  else
    echo "✅ Helm is already installed."
  fi
}
