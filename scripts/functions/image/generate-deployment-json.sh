#!/usr/bin/env bash

generate_deployment_json() {
  local output_file="${1:-deployment.json}"

  get_kubernetes_version() {
    kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion // "unknown"'
  }

  get_containerd_version() {
    # capture only the version line, ignore all warnings
    local version_line
    version_line="$(ctr version 2>&1 | grep -m1 'Version:' || true)"

    # extract the number cleanly
    echo "${version_line}" | sed 's/.*Version:[[:space:]]*//' | tr -d '[:space:]'
  }

  get_docker_version() {
    docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown"
  }

  get_flannel_version() {
    kubectl get ds -n kube-flannel kube-flannel-ds \
      -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null \
      | awk -F: '{print $NF}' \
      || echo "unknown"
  }

  get_gateway_api_version() {
    kubectl get crd gatewayclasses.gateway.networking.k8s.io \
      -o jsonpath='{.metadata.labels.gateway\.networking\.k8s\.io/version}' 2>/dev/null \
      || echo "unknown"
  }

  get_helm_version() {
    helm version --short 2>/dev/null || echo ""
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

    if [[ -z "${selector:-}" ]]; then
      return 1
    fi

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

    if [[ -z "${selector:-}" ]]; then
      return 1
    fi

    get_first_running_pod_from_selector "${selector}"
  }

  get_pod_ip() {
    local pod_name="$1"

    if [[ -z "${pod_name:-}" ]]; then
      echo ""
      return 0
    fi

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

    if [[ -n "${version:-}" ]]; then
      echo "${version}"
    else
      echo "unknown"
    fi
  }

  get_p5_js_version() {
    local pod_name="$1"
    local version=""

    version="$(get_library_version_from_index_html "${pod_name}" "p5.js" || true)"

    if [[ -z "${version:-}" ]]; then
      version="$(get_library_version_from_index_html "${pod_name}" "p5" || true)"
    fi

    if [[ -n "${version:-}" ]]; then
      echo "${version}"
    else
      echo "unknown"
    fi
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
      echo "${image_tag}"
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
    echo "❌ No running web pod found for deployment '${DEPLOYMENT_NAME}' in namespace '${NAMESPACE}'" >&2
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

  local flannel_version
  flannel_version="$(get_flannel_version)"

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
  "flannel": {
    "version": "${flannel_version}"
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
    if [[ -n "${copy_pod_name:-}" ]]; then
      break
    fi
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
