#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="${SCRIPT_DIR}/.."
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
  echo "  APP_IMAGE_NAME: ${APP_IMAGE_NAME}"
  echo "  BACKGROUND_IMAGE_NAME: ${BACKGROUND_IMAGE_NAME}"

  echo "🚀 Building APP image on awr (x86)..."
  image_vars_for "${APP_IMAGE_NAME}" "${TAG}"
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
  image_vars_for "${BACKGROUND_IMAGE_NAME}" "${TAG}"
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
# IMPORT (LOCAL X86)
# -----------------------------
import_image_x86() {
  local IMAGE="$1"

  echo "📦 [x86] Importing ${IMAGE} into containerd"
  docker save "${IMAGE}" | sudo_if_needed ctr -n k8s.io images import -
}

# -----------------------------
# IMPORT (REMOTE ARM)
# -----------------------------
import_image_arm() {
  local IMAGE="$1"

  echo "📦 [ARM] Importing ${IMAGE} into containerd"
  ssh "${ARM_NODE}" 'docker save '"${IMAGE}"' | sudo ctr -n k8s.io images import -'
}

# -----------------------------
# IMPORT ALL IMAGES
# -----------------------------
import_all_images() {
  import_image_x86 "${APP_FULL_IMAGE}"
  import_image_x86 "${APP_LATEST_IMAGE}"

  import_image_arm "${BG_FULL_IMAGE}"
  import_image_arm "${BG_LATEST_IMAGE}"
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

  get_kubernetes_version() {
    kubectl version --client -o json 2>/dev/null \
      | jq -r '.clientVersion.gitVersion // "unknown"' \
      | sed 's/^v\+//'
  }

  get_containerd_version() {
    local version_line
    version_line="$(ctr version 2>&1 | grep -m1 'Version:' || true)"
    echo "${version_line}" | sed 's/.*Version:[[:space:]]*//' | tr -d '[:space:]'
  }

  get_docker_version() {
    docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown"
  }

  get_cilium_version() {
    kubectl get ds -n kube-system cilium \
      -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null \
      | awk -F: '{print $NF}' \
      || echo "unknown"
  }

  get_gateway_api_version() {
    local raw

    raw="$(kubectl get crd gatewayclasses.gateway.networking.k8s.io \
            -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)"

    if [[ -z "$raw" ]]; then
      echo "unknown"
    else
      echo "$raw" | sed 's/^v\+//'
    fi
  }

  get_helm_version() {
    helm version --short 2>/dev/null \
      | sed 's/^v\+//' \
      || echo ""
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
  echo
  echo "📤 Copying JSON into running pod"

  local copy_pod_name
  for i in 1 2 3; do
    copy_pod_name="$(get_first_running_pod_for_deployment "${DEPLOYMENT_NAME}" || true)"
    if [[ -n "${copy_pod_name:-}" ]]; then break; fi
    echo "⏳ Waiting for a running pod (attempt ${i}/3)..."
    sleep 5
  done

  if [[ -z "${copy_pod_name:-}" ]]; then
    echo "❌ No running pod found to copy deployment.json into" >&2
    return 1
  fi

  kubectl cp "${output_file}" "${NAMESPACE}/${copy_pod_name}":/usr/share/nginx/html/deployment.json

  echo "deployment.json copied to pod."
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
    --set backgroundVideo.image.repository="${BG_IMAGE_NAME_BASE}" \
    --set backgroundVideo.image.tag="${IMAGE_TAG}" \
    --set backgroundVideo.image.pullPolicy="Never" \
    --set traefik.tls.secretName="${SECRET_NAME}" \
    --set traefik.hostnames[0]="${HOST_A}" \
    --set traefik.hostnames[1]="${HOST_B}" \
    --set volume.hostPath="${HOST_MEDIA_PATH}" \
    --set volume.mountPath="/usr/share/nginx/html/awroberts-media"
}

# -----------------------------
# NOTES AND STATUS
# -----------------------------
notes_and_status() {
  echo "=============================="
  echo "🌐 Network / NAT Information"
  echo "=============================="

  if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:80 and WAN 443 -> NODE_IP:443"
  else
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:${HTTP_NODEPORT} and WAN 443 -> NODE_IP:${HTTPS_NODEPORT}"
  fi

  echo
  echo "=============================="
  echo "🚀 Deployment, Pods, Services, Routes"
  echo "=============================="

  DEPLOYMENT_NAME=$(kubectl get deploy -n "$NAMESPACE" \
    -l "app.kubernetes.io/instance=$HELM_RELEASE" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [[ -z "$DEPLOYMENT_NAME" ]]; then
    echo "⚠️  No Deployment found for Helm release '$HELM_RELEASE' in namespace '$NAMESPACE'"
  else
    echo "Deployment:"
    kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o wide

    echo
    echo "Rollout status:"
    kubectl -n "$NAMESPACE" rollout status deploy/"$DEPLOYMENT_NAME" --timeout=30s

    echo
    echo "Active Pods:"
    kubectl -n "$NAMESPACE" get pods \
      -l "app.kubernetes.io/instance=$HELM_RELEASE" \
      --field-selector=status.phase=Running \
      -o wide

    echo
    echo "Service:"
    SERVICE_NAME=$(kubectl -n "$NAMESPACE" get svc \
      -l "app.kubernetes.io/instance=$HELM_RELEASE" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$SERVICE_NAME" ]]; then
      echo "Service not found"
    else
      kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" \
        -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,PORTS:.spec.ports[*].port,AGE:.metadata.creationTimestamp
    fi

    echo
    echo "HTTPRoutes:"
    kubectl -n "$NAMESPACE" get httproute \
      -o wide 2>/dev/null || echo "HTTPRoute not found"
    fi

  echo
  echo "=============================="
  echo "🔍 Traefik Diagnostics"
  echo "=============================="

  echo "Traefik Deployment:"
  kubectl -n traefik get deploy traefik -o wide 2>/dev/null || echo "Traefik deployment not found"

  echo
  echo "Traefik Service:"
  kubectl -n traefik get svc traefik \
    -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,PORTS:.spec.ports[*].port,AGE:.metadata.creationTimestamp \
    2>/dev/null || echo "Traefik service not found"

  echo
  echo "Gateways:"
  kubectl -n "$NAMESPACE" get gateway \
    -o 'custom-columns=NAME:.metadata.name,CLASS:.spec.gatewayClassName,PROGRAMMED:.status.conditions[?(@.type=="Programmed")].status,AGE:.metadata.creationTimestamp' \
    2>/dev/null || echo "No Gateways found in $NAMESPACE namespace"

  echo
  echo "TLS Secrets:"
  kubectl -n "$NAMESPACE" get secret | grep tls 2>/dev/null || echo "No TLS secrets found in $NAMESPACE"

  echo
  echo "=============================="
  echo "🖥️ Node & Network Info"
  echo "=============================="

  echo "Node IPs:"
  kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'
  echo

  echo "Public IP:"
  curl -s https://api.ipify.org || echo "Unavailable"
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
