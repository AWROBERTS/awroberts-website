#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="${SCRIPT_DIR}/.."
PROJECT_ROOT="${SCRIPTS_ROOT}/.."
SHARED_DIR="${SCRIPTS_ROOT}/shared"

source "${SHARED_DIR}/sudo-if-needed.sh"
source "${SHARED_DIR}/load-env-file.sh"

# -----------------------------
# TAGGING (GIT SHA)
# -----------------------------
git_sha_tag() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git rev-parse --short HEAD
  else
    date -u +%Y%m%d-%H%M%S
  fi
}

# -----------------------------
# REMOTE HOSTS
# -----------------------------
ARM_NODE_HOST="awr-ffmpeg"
ARM_NODE_USER="awr"
ARM_NODE="${ARM_NODE_USER}@${ARM_NODE_HOST}"

# -----------------------------
# IMAGE VARS (PER IMAGE)
# -----------------------------
image_vars_for() {
  local NAME="$1"
  local TAG="$2"

  local BASE="${NAME%%:*}"
  local FULL="${BASE}:${TAG}"
  local LATEST="${BASE}:latest"

  IMAGE_NAME_BASE="${BASE}"
  IMAGE_TAG="${TAG}"
  FULL_IMAGE="${FULL}"
  LATEST_IMAGE="${LATEST}"
}

# -----------------------------
# BUILD (LOCAL X86)
# -----------------------------
build_image_x86() {
  local IMAGE="$1"
  local LATEST="$2"
  local CONTEXT="$3"
  local TAG="$4"
  local SOURCE_URL="$5"

  echo "🔨 [x86] Building ${IMAGE}"
  echo "   → Context: ${CONTEXT}"

  local start end duration
  start=$(date +%s)

  docker build \
    --no-cache \
    --build-arg BUILD_SHA="${TAG}" \
    --label "org.opencontainers.image.revision=${TAG}" \
    --label "org.opencontainers.image.version=${TAG}" \
    --label "org.opencontainers.image.title=${IMAGE_NAME_BASE}" \
    ${SOURCE_URL:+--label "org.opencontainers.image.source=${SOURCE_URL}"} \
    -t "${IMAGE}" \
    -t "${LATEST}" \
    "${CONTEXT}"

  end=$(date +%s)
  duration=$(( end - start ))

  echo "⏱️ [x86] Build completed in ${duration}s"
}

# -----------------------------
# BUILD (REMOTE ARM via TAR STREAMING)
# -----------------------------
build_image_arm() {
  local IMAGE="$1"
  local LATEST="$2"
  local CONTEXT="$3"
  local TAG="$4"
  local SOURCE_URL="$5"

  echo "🔨 [ARM] Building ${IMAGE}"
  echo "   → Context (streamed): ${CONTEXT}"

  tar -C "${CONTEXT}" -cf - . \
    | ssh "${ARM_NODE}" "
        docker build \
          --no-cache \
          --build-arg BUILD_SHA='${TAG}' \
          --label 'org.opencontainers.image.revision=${TAG}' \
          --label 'org.opencontainers.image.version=${TAG}' \
          --label 'org.opencontainers.image.title=${IMAGE_NAME_BASE}' \
          ${SOURCE_URL:+--label 'org.opencontainers.image.source=${SOURCE_URL}'} \
          -t '${IMAGE}' \
          -t '${LATEST}' \
          -
      "
}

# -----------------------------
# BUILD ALL IMAGES
# -----------------------------
build_all_images() {
  local TAG
  TAG="$(git_sha_tag)"

  echo "📦 Preparing to build images with tag: ${TAG}"
  echo "  APP_IMAGE_NAME_BASE: ${APP_IMAGE_NAME_BASE}"
  echo "  BG_IMAGE_NAME_BASE: ${BG_IMAGE_NAME_BASE}"

  echo "🚀 Building APP image on awr (x86)..."
  image_vars_for "${APP_IMAGE_NAME_BASE}" "${TAG}"
  APP_FULL_IMAGE="${FULL_IMAGE}"
  APP_LATEST_IMAGE="${LATEST_IMAGE}"
  APP_IMAGE_NAME_BASE="${IMAGE_NAME_BASE}"

  build_image_x86 \
    "${APP_FULL_IMAGE}" \
    "${APP_LATEST_IMAGE}" \
    "${PROJECT_ROOT}/docker/awroberts" \
    "${TAG}" \
    "${GIT_REMOTE_URL:-}"

  echo "🎞️ Building BACKGROUND VIDEO image on awr-ffmpeg (ARM)..."
  image_vars_for "${BG_IMAGE_NAME_BASE}" "${TAG}"
  BG_FULL_IMAGE="${FULL_IMAGE}"
  BG_LATEST_IMAGE="${LATEST_IMAGE}"
  BG_IMAGE_NAME_BASE="${IMAGE_NAME_BASE}"

  build_image_arm \
    "${BG_FULL_IMAGE}" \
    "${BG_LATEST_IMAGE}" \
    "${PROJECT_ROOT}/docker/background-video" \
    "${TAG}" \
    "${GIT_REMOTE_URL:-}"
}

# -----------------------------
# CONTAINERD REF
# -----------------------------
# `ctr images import` stores images under their fully qualified name
# (docker.io/awroberts/app:tag), and `ctr images tag` doesn't normalise,
# so short Docker-style names must be expanded before tagging.
ctr_ref() {
  local REF="$1"
  local FIRST="${REF%%/*}"

  if [[ "${REF}" != */* ]]; then
    echo "docker.io/library/${REF}"
  elif [[ "${FIRST}" == *.* || "${FIRST}" == *:* || "${FIRST}" == "localhost" ]]; then
    echo "${REF}"
  else
    echo "docker.io/${REF}"
  fi
}

# -----------------------------
# IMPORT (LOCAL X86)
# -----------------------------
import_image_x86() {
  local IMAGE="$1"
  local LATEST="$2"

  echo "📦 [x86] Importing ${IMAGE} into containerd"
  docker save "${IMAGE}" | sudo_if_needed ctr -n k8s.io images import -
  sudo_if_needed ctr -n k8s.io images tag --force "$(ctr_ref "${IMAGE}")" "$(ctr_ref "${LATEST}")"
}

# -----------------------------
# IMPORT (REMOTE ARM)
# -----------------------------
import_image_arm() {
  local IMAGE="$1"
  local LATEST="$2"

  echo "📦 [ARM] Importing ${IMAGE} into containerd"
  ssh "${ARM_NODE}" 'docker save '"${IMAGE}"' | sudo ctr -n k8s.io images import - && sudo ctr -n k8s.io images tag --force '"$(ctr_ref "${IMAGE}")"' '"$(ctr_ref "${LATEST}")"''
}

# -----------------------------
# IMPORT ALL IMAGES
# -----------------------------
import_all_images() {
  import_image_x86 "${APP_FULL_IMAGE}" "${APP_LATEST_IMAGE}"
  import_image_arm "${BG_FULL_IMAGE}" "${BG_LATEST_IMAGE}"
}

# -----------------------------
# CLEANUP OLD IMAGES
# -----------------------------
cleanup_old_images() {
  local base="$1" days="$2" keep_image="$3"
  local now epoch_cutoff in_use_tmp

  now="$(date -u +%s)"
  epoch_cutoff=$(( now - days*24*3600 ))

  in_use_tmp="$(mktemp)"
  kubectl get pods -A -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' \
    | sort -u > "$in_use_tmp" || true

  _in_use() { grep -Fxq "$1" "$in_use_tmp"; }

  for ref in $(docker images --format '{{.Repository}}:{{.Tag}}'); do
    [[ "$ref" == ${base}:* ]] \
      && [[ "$ref" != "$keep_image" ]] \
      && ! _in_use "$ref" \
      && docker image rm "$ref" >/dev/null 2>&1 || true
  done

  rm -f "$in_use_tmp"
}

# -----------------------------
# ENSURE METRICS SERVER
# -----------------------------
ensure_metrics_server() {
  echo "📦 Ensuring metrics-server is installed..."

  if ! kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  else
    echo "   metrics-server Deployment already exists; skipping components.yaml apply."
  fi

  echo "🔧 Patching metrics-server for bare-metal..."
  kubectl patch deployment metrics-server -n kube-system \
    --type='json' \
    -p='[
      {
        "op": "replace",
        "path": "/spec/template/spec/containers/0/args",
        "value": [
          "--cert-dir=/tmp",
          "--secure-port=4443",
          "--kubelet-insecure-tls",
          "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
          "--kubelet-use-node-status-port",
          "--metric-resolution=15s"
        ]
      }
    ]'

  kubectl patch deployment metrics-server -n kube-system \
    --type='json' \
    -p='[
      { "op": "remove", "path": "/spec/template/spec/containers/0/ports" },
      { "op": "add", "path": "/spec/template/spec/containers/0/ports", "value": [
          { "containerPort": 4443, "name": "https", "protocol": "TCP" }
      ]}
    ]'

  kubectl patch service metrics-server -n kube-system \
    --type='json' \
    -p='[
      { "op": "replace", "path": "/spec/ports/0/port", "value": 443 },
      { "op": "replace", "path": "/spec/ports/0/targetPort", "value": 4443 }
    ]'

  kubectl delete pod -n kube-system -l k8s-app=metrics-server
  kubectl rollout status deployment metrics-server -n kube-system --timeout=60s

  until kubectl get --raw /apis/metrics.k8s.io/v1beta1 >/dev/null 2>&1; do
    echo "   Metrics API not ready yet..."
    sleep 2
  done

  echo "📊 Metrics API is available."
}

# -----------------------------
# ENSURE TRAEFIK HELM
# -----------------------------
ensure_traefik_helm() {
  echo "🔧 Ensuring Traefik controller is installed via Helm..."

  kubectl get crd -o name | grep gateway.networking.k8s.io \
    | xargs --no-run-if-empty kubectl delete --ignore-not-found || true

  kubectl apply --server-side --force-conflicts \
    -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml

  helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1

  helm upgrade --install traefik traefik/traefik \
    --namespace traefik \
    --create-namespace \
    -f "${PROJECT_ROOT}/traefik/traefik-values.yaml"

  kubectl scale deploy/traefik --replicas=0 -n traefik
  kubectl wait --for=delete pod -l app.kubernetes.io/name=traefik -n traefik --timeout=60s 2>/dev/null || true
  kubectl scale deploy/traefik --replicas=1 -n traefik
  kubectl rollout status deploy/traefik -n traefik --timeout=120s

  echo "✅ Traefik installed or updated."
}

generate_deployment_json() {
  local output_file="${1:-deployment.json}"

  # The cluster's version, not the local kubectl client's.
  get_kubernetes_version() {
    kubectl version -o json 2>/dev/null \
      | jq -r '.serverVersion.gitVersion // "unknown"' \
      | sed 's/^v\+//'
  }

  # `ctr version` needs root for the socket; the binary's own version doesn't.
  get_containerd_version() {
    local version
    version="$(containerd --version 2>/dev/null | awk '{print $3}' | sed 's/^v\+//')"
    echo "${version:-unknown}"
  }

  get_docker_version() {
    docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown"
  }

  # Image is tag@digest (quay.io/cilium/cilium:v1.20.2@sha256:...), so drop
  # the digest before taking the tag.
  get_cilium_version() {
    local image tag
    image="$(kubectl get ds -n kube-system cilium \
      -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
    image="${image%%@*}"
    tag="${image##*:}"
    if [[ -n "${tag}" && "${tag}" != "${image}" ]]; then
      echo "${tag#v}"
    else
      echo "unknown"
    fi
  }

  # The release bundle (e.g. 1.5.1), not the API version (v1).
  get_gateway_api_version() {
    local raw

    raw="$(kubectl get crd gatewayclasses.gateway.networking.k8s.io \
            -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null)"

    if [[ -z "$raw" ]]; then
      echo "unknown"
    else
      echo "$raw" | sed 's/^v\+//'
    fi
  }

  get_helm_version() {
    local version
    version="$(helm version --short 2>/dev/null | sed 's/^v\+//; s/+.*//')"
    echo "${version:-unknown}"
  }

  get_service_name() {
    if [[ -n "${SERVICE_NAME:-}" ]] && kubectl get svc "${SERVICE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      echo "${SERVICE_NAME}"
      return 0
    fi

    if [[ -n "${DEPLOYMENT_NAME:-}" ]] && kubectl get svc "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      echo "${DEPLOYMENT_NAME}"
      return 0
    fi

    kubectl get svc -n "${NAMESPACE}" \
      -l "app.kubernetes.io/instance=${HELM_RELEASE},app.kubernetes.io/component=web" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
  }

  get_first_running_pod_from_selector() {
    local selector="$1"
    if [[ -z "${selector:-}" ]]; then return 1; fi

    kubectl get pod -n "${NAMESPACE}" \
      -l "${selector}" \
      --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
  }

  get_first_running_pod_for_deployment() {
    local deployment_name="$1"
    local selector

    selector="$(
      kubectl get deploy "${deployment_name}" -n "${NAMESPACE}" \
        -o go-template='{{range $key, $value := .spec.selector.matchLabels}}{{printf "%s=%s," $key $value}}{{end}}' 2>/dev/null \
        | sed 's/,$//'
    )"

    if [[ -z "${selector:-}" ]]; then return 1; fi
    get_first_running_pod_from_selector "${selector}"
  }

  get_pod_ip() {
    local pod_name="$1"
    if [[ -z "${pod_name:-}" ]]; then echo ""; return 0; fi

    kubectl get pod "${pod_name}" -n "${NAMESPACE}" \
      -o jsonpath='{.status.podIP}' 2>/dev/null || echo ""
  }

  get_first_running_pod_ip_for_deployment() {
    local deployment_name="$1"
    local pod_name
    pod_name="$(get_first_running_pod_for_deployment "${deployment_name}" || true)"
    get_pod_ip "${pod_name}"
  }

  get_library_version_from_index_html() {
    local pod_name="$1"
    local library_name="$2"

    kubectl exec "${pod_name}" -n "${NAMESPACE}" -- \
      sh -c "grep -Eo '${library_name}(@|/)[0-9]+\\.[0-9]+\\.[0-9]+([^0-9]|$)' /usr/share/nginx/html/index.html | head -n 1" 2>/dev/null \
      | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' \
      | head -n 1
  }

  get_hls_js_version() {
    local pod_name="$1"
    local version=""
    version="$(get_library_version_from_index_html "${pod_name}" "hls.js" || true)"

    if [[ -n "${version:-}" ]]; then echo "${version}"; else echo "unknown"; fi
  }

  get_p5_js_version() {
    local pod_name="$1"
    local version=""
    version="$(get_library_version_from_index_html "${pod_name}" "p5.js" || true)"

    if [[ -z "${version:-}" ]]; then
      version="$(get_library_version_from_index_html "${pod_name}" "p5" || true)"
    fi

    if [[ -n "${version:-}" ]]; then echo "${version}"; else echo "unknown"; fi
  }

  get_traefik_deployment_name() {
    kubectl get deploy -n traefik \
      -l "app.kubernetes.io/name=traefik" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
  }

  get_traefik_image() {
    local traefik_deploy_name="$1"
    kubectl get deploy "${traefik_deploy_name}" -n traefik \
      -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null
  }

  get_traefik_version_from_image() {
    local traefik_image_ref="$1"
    local image_tag="${traefik_image_ref##*:}"

    if [[ -n "${image_tag}" && "${image_tag}" != "${traefik_image_ref}" ]]; then
      echo "${image_tag}" | sed 's/^v\+//'
    else
      echo "unknown"
    fi
  }

  local service_name
  service_name="$(get_service_name)"
  if [[ -z "${service_name:-}" ]]; then
    echo "❌ No web service found in namespace '${NAMESPACE}'" >&2
    return 1
  fi

  echo "Selected service: ${service_name}"

  local web_pod_name
  web_pod_name="$(get_first_running_pod_for_deployment "${DEPLOYMENT_NAME}" || true)"
  if [[ -z "${web_pod_name:-}" ]]; then
    echo "❌ No running web pod found" >&2
    return 1
  fi

  echo "Selected web pod for deployment metadata update."

  local traefik_deployment_name
  traefik_deployment_name="$(get_traefik_deployment_name)"

  local traefik_version="unknown"
  if [[ -n "${traefik_deployment_name:-}" ]]; then
    local live_traefik_image
    live_traefik_image="$(get_traefik_image "${traefik_deployment_name}")"
    if [[ -n "${live_traefik_image:-}" ]]; then
      traefik_version="$(get_traefik_version_from_image "${live_traefik_image}")"
    fi
  fi

  local web_pod_ip
  local background_video_pod_ip
  local background_ffmpeg_pod_ip
  web_pod_ip="$(get_pod_ip "${web_pod_name}")"
  background_video_pod_ip="$(get_first_running_pod_ip_for_deployment "${DEPLOYMENT_NAME}-background")"
  background_ffmpeg_pod_ip="$(get_first_running_pod_ip_for_deployment "${DEPLOYMENT_NAME}-background-ffmpeg")"

  local service_cluster_ip
  service_cluster_ip="$(kubectl get svc "${service_name}" -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")"

  local kubernetes_version
  kubernetes_version="$(get_kubernetes_version)"

  local containerd_version
  containerd_version="$(get_containerd_version)"

  local docker_version
  docker_version="$(get_docker_version)"

  local cilium_version
  cilium_version="$(get_cilium_version)"

  local gateway_api_version
  gateway_api_version="$(get_gateway_api_version)"

  local helm_version
  helm_version="$(get_helm_version)"

  local hls_js_version
  hls_js_version="$(get_hls_js_version "${web_pod_name}")"

  local p5_js_version
  p5_js_version="$(get_p5_js_version "${web_pod_name}")"

  cat > "${output_file}" <<EOF
{
  "containerd": {
    "version": "${containerd_version}"
  },
  "docker": {
    "version": "${docker_version}"
  },
  "cilium": {
    "version": "${cilium_version}"
  },
  "kubernetes": {
    "version": "${kubernetes_version}"
  },
  "gatewayAPI": {
    "version": "${gateway_api_version}"
  },
  "helm": {
    "version": "${helm_version}"
  },
  "awroberts": {
    "service": {
      "clusterIP": "${service_cluster_ip}"
    }
  },
  "traefik": {
    "build": {
      "version": "${traefik_version}"
    }
  },
  "pods": {
    "web": {
      "ip": "${web_pod_ip}"
    },
    "backgroundVideo": {
      "ip": "${background_video_pod_ip}"
    },
    "backgroundFfmpeg": {
      "ip": "${background_ffmpeg_pod_ip}"
    }
  },
  "libraries": {
    "hls.js": {
      "version": "${hls_js_version}"
    },
    "p5.js": {
      "version": "${p5_js_version}"
    }
  }
}
EOF

  echo "deployment.json generated."

  # Stored in a ConfigMap the web pod mounts (see templates/deployment.yaml),
  # so it survives pod restarts and updates in place without a rollout.
  local configmap_name="${DEPLOYMENT_NAME}-deployment-json"
  echo "📤 Storing JSON in ConfigMap ${configmap_name}"

  jq empty "${output_file}" || { echo "❌ Generated deployment.json is not valid JSON" >&2; return 1; }

  kubectl -n "${NAMESPACE}" create configmap "${configmap_name}" \
    --from-file=deployment.json="${output_file}" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "deployment.json published (served within ~1 minute)."
}

# -----------------------------
# DEPLOY WITH HELM
# -----------------------------
deploy_with_helm() {
  echo "🚀 Deploying with Helm using image tag ${IMAGE_TAG}"

  echo "📦 Ensuring namespace ${NAMESPACE} exists..."
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART_PATH}" \
    --namespace "${NAMESPACE}" \
    --set image.repository="${APP_IMAGE_NAME_BASE}" \
    --set image.tag="${IMAGE_TAG}" \
    --set image.pullPolicy="Never" \
    --set backgroundVideo.nginx.image.repository="${BG_IMAGE_NAME_BASE}" \
    --set backgroundVideo.nginx.image.tag="${IMAGE_TAG}" \
    --set backgroundVideo.nginx.image.pullPolicy="Never" \
    --set traefik.tls.secretName="${TLS_SECRET_NAME}"
}

# -----------------------------
# ENSURE TLS SECRET
# -----------------------------
# The Gateway's HTTPS listeners reference this secret; without it Traefik
# falls back to its self-signed default cert. Re-applied every deploy so a
# renewed cert on the host is picked up.
ensure_tls_secret() {
  echo "🔐 Ensuring TLS secret ${TLS_SECRET_NAME} in ${NAMESPACE}..."

  local f
  for f in "${HOST_CERT_PATH}" "${HOST_KEY_PATH}"; do
    if ! sudo_if_needed test -r "$f"; then
      echo "ERROR: TLS file not found or unreadable: $f" >&2
      exit 1
    fi
  done

  sudo_if_needed openssl x509 -in "${HOST_CERT_PATH}" -noout -subject -enddate

  # Refuse to replace a working secret with an expired cert or a mismatched key.
  if ! sudo_if_needed openssl x509 -in "${HOST_CERT_PATH}" -noout -checkend 0 >/dev/null; then
    echo "ERROR: ${HOST_CERT_PATH} has expired." >&2
    exit 1
  fi

  local cert_pub key_pub
  cert_pub="$(sudo_if_needed openssl x509 -in "${HOST_CERT_PATH}" -noout -pubkey)"
  key_pub="$(sudo_if_needed openssl pkey -in "${HOST_KEY_PATH}" -pubout)"
  if [[ "${cert_pub}" != "${key_pub}" ]]; then
    echo "ERROR: ${HOST_KEY_PATH} does not match ${HOST_CERT_PATH}." >&2
    exit 1
  fi

  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "${NAMESPACE}" create secret tls "${TLS_SECRET_NAME}" \
    --cert=<(sudo_if_needed cat "${HOST_CERT_PATH}") \
    --key=<(sudo_if_needed cat "${HOST_KEY_PATH}") \
    --dry-run=client -o yaml | kubectl apply -f -

  # Confirm the cluster now holds the same leaf cert as the host file.
  local file_fp secret_fp
  file_fp="$(sudo_if_needed openssl x509 -in "${HOST_CERT_PATH}" -noout -fingerprint -sha256)"
  secret_fp="$(kubectl -n "${NAMESPACE}" get secret "${TLS_SECRET_NAME}" -o jsonpath='{.data.tls\.crt}' \
    | base64 -d | openssl x509 -noout -fingerprint -sha256)"
  if [[ "${file_fp}" != "${secret_fp}" ]]; then
    echo "ERROR: ${TLS_SECRET_NAME} does not contain ${HOST_CERT_PATH}." >&2
    exit 1
  fi
  echo "   ${TLS_SECRET_NAME} up to date (${file_fp#*=})"
}

# -----------------------------
# PUBLISH DEPLOYMENT JSON
# -----------------------------
# The site's diagnostics panel fetches /deployment.json, served from a
# ConfigMap so it survives pod restarts. Generated after the rollout so it
# describes the pods that are actually running.
publish_deployment_json() {
  echo "🧾 Publishing deployment.json..."

  DEPLOYMENT_NAME="$(
    kubectl -n "${NAMESPACE}" get deploy -l "app.kubernetes.io/instance=${HELM_RELEASE}" -o name \
      | sed 's|.*/||' | grep -v -- '-background' | head -1
  )"
  if [[ -z "${DEPLOYMENT_NAME}" ]]; then
    echo "⚠️  No web Deployment found for release ${HELM_RELEASE}; skipping deployment.json" >&2
    return 0
  fi

  # Describe the new pod, not one that's about to be terminated.
  kubectl -n "${NAMESPACE}" rollout status "deploy/${DEPLOYMENT_NAME}" --timeout=180s

  local json_file
  json_file="$(mktemp)"
  generate_deployment_json "${json_file}" || echo "⚠️  deployment.json not published" >&2
  rm -f "${json_file}"
}

# -----------------------------
# DEPLOY IMAGES (wrapper)
# -----------------------------
deploy_images() {
  build_all_images
  import_all_images

  ensure_metrics_server
  ensure_traefik_helm
  ensure_tls_secret
  deploy_with_helm
  publish_deployment_json

  cleanup_old_images "${APP_IMAGE_NAME_BASE}" "${RETENTION_DAYS}" "${APP_FULL_IMAGE}"
  cleanup_old_images "${BG_IMAGE_NAME_BASE}" "${RETENTION_DAYS}" "${BG_FULL_IMAGE}"

  notes_and_status || echo "⚠️  notes_and_status report incomplete" >&2
}

# -----------------------------
# NOTES AND STATUS
# -----------------------------
notes_and_status() {
  # Report only: called as `notes_and_status || true`, so nothing here can
  # fail a deploy that has otherwise succeeded.
  local web_deploy="${DEPLOYMENT_NAME:-${HELM_RELEASE}-deploy}"
  local site_host
  site_host="$(kubectl -n "${NAMESPACE}" get gateway -o jsonpath='{.items[0].spec.listeners[0].hostname}' 2>/dev/null)"
  site_host="${site_host:-awroberts.co.uk}"

  echo
  echo "=============================="
  echo "🧭 Cluster Setup"
  echo "=============================="
  echo "Nodes:"
  kubectl get nodes \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status,ROLES:.metadata.labels.node-role\.kubernetes\.io/control-plane,ARCH:.status.nodeInfo.architecture,IP:.status.addresses[?(@.type=="InternalIP")].address,OS:.status.osImage,KUBELET:.status.nodeInfo.kubeletVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion'
  echo
  echo "Workload placement (web on the control plane, HLS on the ARM worker):"
  kubectl -n "${NAMESPACE}" get pods \
    -l "app.kubernetes.io/instance=${HELM_RELEASE}" \
    -o custom-columns='POD:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,NODE:.spec.nodeName,IP:.status.podIP'

  echo
  echo "=============================="
  echo "🌐 Network / NAT Information"
  echo "=============================="
  local host_network http_port https_port
  host_network="$(kubectl -n traefik get deploy traefik -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null)"
  if [[ "${host_network}" == "true" ]]; then
    echo "- Traefik uses hostNetwork on $(kubectl -n traefik get pod -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)"
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:80 and WAN 443 -> NODE_IP:443"
  else
    http_port="$(kubectl -n traefik get svc traefik -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}' 2>/dev/null)"
    https_port="$(kubectl -n traefik get svc traefik -o jsonpath='{.spec.ports[?(@.name=="websecure")].nodePort}' 2>/dev/null)"
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:${http_port:-?} and WAN 443 -> NODE_IP:${https_port:-?}"
  fi
  echo "- Worker VM network ${WORKER_IP%.*}.0/24 routed via the Mac mini ($(getent hosts "${MAC_HOST:-}" 2>/dev/null | awk '{print $1}'))"

  echo
  echo "=============================="
  echo "🚀 Deployment, Services, Routes"
  echo "=============================="
  echo "Deployments:"
  kubectl -n "${NAMESPACE}" get deploy -l "app.kubernetes.io/instance=${HELM_RELEASE}" -o wide

  echo
  echo "Rollout status (${web_deploy}):"
  kubectl -n "${NAMESPACE}" rollout status "deploy/${web_deploy}" --timeout=30s

  echo
  echo "Services:"
  kubectl -n "${NAMESPACE}" get svc -l "app.kubernetes.io/instance=${HELM_RELEASE}" \
    -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,PORTS:.spec.ports[*].port

  echo
  echo "HTTPRoutes:"
  kubectl -n "${NAMESPACE}" get httproute -o wide 2>/dev/null || echo "HTTPRoute not found"

  echo
  echo "=============================="
  echo "🔍 Traefik / Gateway / TLS"
  echo "=============================="
  echo "Traefik Deployment:"
  kubectl -n traefik get deploy traefik -o wide 2>/dev/null || echo "Traefik deployment not found"

  echo
  echo "Gateways:"
  kubectl -n "${NAMESPACE}" get gateway \
    -o 'custom-columns=NAME:.metadata.name,CLASS:.spec.gatewayClassName,PROGRAMMED:.status.conditions[?(@.type=="Programmed")].status' \
    2>/dev/null || echo "No Gateways found in ${NAMESPACE} namespace"

  echo
  echo "TLS (${TLS_SECRET_NAME}):"
  kubectl -n "${NAMESPACE}" get secret "${TLS_SECRET_NAME}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null \
    | base64 -d 2>/dev/null | openssl x509 -noout -subject -issuer -enddate 2>/dev/null \
    || echo "TLS secret ${TLS_SECRET_NAME} not found"

  echo
  echo "=============================="
  echo "🎞️ Live Checks (https://${site_host})"
  echo "=============================="
  local path code
  for path in / /stream/index.m3u8 /stream/mobile/index.m3u8 /background-poster.png /deployment.json; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${site_host}${path}")"
    printf '  %-28s %s\n' "${path}" "${code:-error}"
  done
  echo "  served cert: $(echo | openssl s_client -connect "${site_host}:443" -servername "${site_host}" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null || echo unavailable)"

  echo
  echo "=============================="
  echo "🖥️ Public IP"
  echo "=============================="
  curl -s --max-time 10 https://api.ipify.org || echo "Unavailable"
  echo
  echo
}

# -----------------------------
# VALIDATE BACKGROUND VIDEO
# -----------------------------
validate_background_video() {
  local source_path="$BACKGROUND_VIDEO_SOURCE"

  echo "🔍 Validating background video source on ARM node: $source_path"

  kubectl debug node/awr-ffmpeg -it --image=alpine -- chroot /host sh -c "
    if [ ! -f '$source_path' ]; then
      echo 'ERROR: HLS playlist not found: $source_path' >&2
      exit 1
    fi

    echo '📄 Parsing playlist for segment references…'
    playlist_dir=\$(dirname '$source_path')
    mapfile -t segments < <(grep -F '.ts' '$source_path')

    if [ \${#segments[@]} -eq 0 ]; then
      echo 'ERROR: No segments found in playlist.' >&2
      exit 1
    fi

    echo '📦 Found \${#segments[@]} segments — validating in parallel (P=8)…'

    tmp_failures=\$(mktemp)

    printf '%s\n' \"\${segments[@]}\" \
      | sed \"s|^|\$playlist_dir/|\" \
      | xargs -P8 -I{} ffprobe -v error -select_streams v:0 \
          -show_entries stream=codec_name -of csv=p=0 '{}' \
          >/dev/null 2>>\"\$tmp_failures\"

    if [ -s \"\$tmp_failures\" ]; then
      echo '❌ Segment validation failed:'
      cat \"\$tmp_failures\" >&2
      rm -f \"\$tmp_failures\"
      exit 1
    fi

    rm -f \"\$tmp_failures\"
    echo '✅ All \${#segments[@]} HLS segments validated successfully.'
  "
}
