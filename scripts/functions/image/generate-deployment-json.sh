#!/usr/bin/env bash

generate_deployment_json() {
  local output_file="${1:-deployment.json}"

  resolve_image_sha() {
    local image_ref="$1"
    local repo_digest=""
    local image_id=""
    local label_sha=""
    local tag_sha=""

    repo_digest="$(
      docker image inspect "$image_ref" \
        --format '{{index .RepoDigests 0}}' 2>/dev/null
    )"

    if [[ -n "$repo_digest" && "$repo_digest" != "<no value>" ]]; then
      echo "${repo_digest#sha256:}"
      return 0
    fi

    image_id="$(
      docker image inspect "$image_ref" \
        --format '{{.Id}}' 2>/dev/null
    )"

    if [[ -n "$image_id" && "$image_id" != "<no value>" ]]; then
      echo "${image_id#sha256:}"
      return 0
    fi

    label_sha="$(
      docker image inspect "$image_ref" \
        --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' 2>/dev/null
    )"

    if [[ -n "$label_sha" && "$label_sha" != "<no value>" ]]; then
      echo "$label_sha"
      return 0
    fi

    tag_sha="${image_ref##*:}"
    if [[ -n "$tag_sha" && "$tag_sha" != "$image_ref" ]]; then
      echo "$tag_sha"
      return 0
    fi

    echo "unknown"
  }

  get_kubernetes_version() {
    kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion // "unknown"'
  }

  get_helm_version() {
    helm version --short 2>/dev/null || echo ""
  }

  get_first_running_pod_name() {
    kubectl get pod -n "${NAMESPACE}" \
      -l "app.kubernetes.io/instance=${HELM_RELEASE}" \
      --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
  }

  get_first_service_name() {
    kubectl get svc -n "${NAMESPACE}" \
      -l "app.kubernetes.io/instance=${HELM_RELEASE}" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
  }

  get_traefik_deployment_name() {
    kubectl get deploy -n traefik \
      -l "app.kubernetes.io/name=traefik" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
  }

  get_traefik_image() {
    local traefik_deploy_name="$1"
    kubectl get deploy "$traefik_deploy_name" -n traefik \
      -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null
  }

  get_traefik_version_from_image() {
    local traefik_image_ref="$1"
    local image_tag="${traefik_image_ref##*:}"

    if [[ -n "$image_tag" && "$image_tag" != "$traefik_image_ref" ]]; then
      echo "$image_tag"
    else
      echo "unknown"
    fi
  }

  local pod_name
  pod_name="$(get_first_running_pod_name)"

  if [[ -z "${pod_name:-}" ]]; then
    echo "❌ No running pod found for Helm release '${HELM_RELEASE}' in namespace '${NAMESPACE}'" >&2
    return 1
  fi

  local service_name
  service_name="$(get_first_service_name)"

  if [[ -z "${service_name:-}" ]]; then
    echo "❌ No service found for Helm release '${HELM_RELEASE}' in namespace '${NAMESPACE}'" >&2
    return 1
  fi

  local traefik_deployment_name
  traefik_deployment_name="$(get_traefik_deployment_name)"

  local traefik_version="unknown"
  if [[ -n "${traefik_deployment_name:-}" ]]; then
    local live_traefik_image
    live_traefik_image="$(get_traefik_image "$traefik_deployment_name")"
    if [[ -n "${live_traefik_image:-}" ]]; then
      traefik_version="$(get_traefik_version_from_image "$live_traefik_image")"
    fi
  fi

  local app_image="${APP_FULL_IMAGE:-${APP_IMAGE_NAME:-awroberts}:unknown}"
  local bg_image="${BG_FULL_IMAGE:-${BACKGROUND_IMAGE_NAME:-background-video}:unknown}"

  local app_sha
  local bg_sha
  app_sha="$(resolve_image_sha "$app_image")"
  bg_sha="$(resolve_image_sha "$bg_image")"

  local pod_ip
  pod_ip="$(kubectl get pod "$pod_name" -n "${NAMESPACE}" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")"

  local service_cluster_ip
  service_cluster_ip="$(kubectl get svc "$service_name" -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")"

  local kubernetes_version
  kubernetes_version="$(get_kubernetes_version)"

  local helm_version
  helm_version="$(get_helm_version)"

  cat > "$output_file" <<EOF
{
  "kubernetes": {
    "version": "${kubernetes_version}"
  },
  "helm": {
    "version": "${helm_version}"
  },
  "awroberts": {
    "service": {
      "clusterIP": "${service_cluster_ip}"
    },
    "build": {
      "sha": "${app_sha}"
    }
  },
  "traefik": {
    "build": {
      "version": "${traefik_version}"
    }
  },
  "pod": {
    "ip": "${pod_ip}"
  },
  "backgroundVideo": {
    "build": {
      "sha": "${bg_sha}"
    }
  }
}
EOF

  echo "deployment.json generated."
  echo
  echo "📤 Copying JSON into running pod"

  kubectl cp deployment.json "$NAMESPACE/$pod_name":/usr/share/nginx/html/deployment.json

  echo "deployment.json copied to pod: $pod_name"
}