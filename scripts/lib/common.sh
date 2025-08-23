#!/usr/bin/env bash
# Common config, defaults, and helpers. Source this first.

# Respect env overrides by using :- defaults
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"

# App/Namespace
NAMESPACE="${NAMESPACE:-awroberts}"
SECRET_NAME="${SECRET_NAME:-awroberts-tls}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-awroberts-web}"
CONTAINER_NAME_IN_DEPLOY="${CONTAINER_NAME_IN_DEPLOY:-}"
MANIFEST_DIR="${MANIFEST_DIR:-./k8s}"
INGRESS_NAME="${INGRESS_NAME:-awroberts-web}"
SERVICE_NAME="${SERVICE_NAME:-awroberts-web}"

# Hosts
HOST_A="${HOST_A:-awroberts.co.uk}"
HOST_B="${HOST_B:-www.awroberts.co.uk}"

# TLS certs (full chain + unencrypted key)
HOST_CERT_PATH="${HOST_CERT_PATH:-/var/www/html/awroberts/awroberts-certs/fullchain.crt}"
HOST_KEY_PATH="${HOST_KEY_PATH:-/var/www/html/awroberts/awroberts-certs/awroberts_co_uk.key}"

# Local image build settings
IMAGE_NAME="${IMAGE_NAME:-awroberts}"
USE_TIMESTAMP="${USE_TIMESTAMP:-true}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
IMAGE_TAG="${IMAGE_TAG:-}"
IMAGE_NAME_BASE="${IMAGE_NAME%%:*}"
if [[ "${USE_TIMESTAMP}" == "true" && -z "${IMAGE_TAG}" ]]; then
  IMAGE_TAG="$(date -u +%Y%m%d-%H%M%S)"
fi
FULL_IMAGE="${IMAGE_NAME_BASE}:${IMAGE_TAG}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"
PLATFORM="${PLATFORM:-linux/amd64}"
BUILDER_NAME="${BUILDER_NAME:-localbuilder}"

# Bootstrap options (single-node kubeadm + Flannel)
CLUSTER_BOOTSTRAP="${CLUSTER_BOOTSTRAP:-true}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"

# Ingress controller mode
INGRESS_HOSTNETWORK="${INGRESS_HOSTNETWORK:-true}"

# Derived at runtime
HTTP_NODEPORT="${HTTP_NODEPORT:-}"
HTTPS_NODEPORT="${HTTPS_NODEPORT:-}"

# Helper: sudo if not root
sudo_if_needed() { if [[ $EUID -ne 0 ]]; then sudo "$@"; else "$@"; fi; }

# Preflight checks that apply globally
preflight_core_tools() {
  command -v docker >/dev/null 2>&1 || { echo "docker not found"; exit 1; }
  command -v curl >/dev/null 2>&1 || { echo "curl not found"; exit 1; }

  if ! docker buildx version >/dev/null 2>&1; then
    echo "Docker Buildx is required but not available."
    echo "On Debian/Ubuntu/Mint install: sudo apt-get install -y docker-buildx-plugin"
    echo "Docs: https://docs.docker.com/build/buildx/install/"
    exit 1
  fi

  [[ -f "$HOST_CERT_PATH" ]] || { echo "Cert not found at $HOST_CERT_PATH"; exit 1; }
  [[ -f "$HOST_KEY_PATH" ]] || { echo "Key not found at $HOST_KEY_PATH"; exit 1; }
  [[ -d "$MANIFEST_DIR" ]] || { echo "Manifest directory not found: $MANIFEST_DIR"; exit 1; }
}