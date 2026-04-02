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

  get_first_running_pod_name() {
    kubectl get pod -n "${NAMESPACE}" \
      -l "app.kubernetes.io/instance=${HELM_RELEASE}" \
      --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
  }

  get_all_pods_json() {
    local namespace="$1"
    kubectl get pods -n "$namespace" -o json 2>/dev/null
  }

  get_first_deployment_name() {
    kubectl get deploy -n "${NAMESPACE}" \
      -l "app.kubernetes.io/instance=${HELM_RELEASE}" \
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

  get_traefik_service_name() {
    kubectl get svc -n traefik \
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

  local deployment_name
  deployment_name="$(get_first_deployment_name)"

  if [[ -z "${deployment_name:-}" ]]; then
    echo "❌ No deployment found for Helm release '${HELM_RELEASE}' in namespace '${NAMESPACE}'" >&2
    return 1
  fi

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

  local traefik_service_name
  traefik_service_name="$(get_traefik_service_name)"

  local traefik_image="docker.io/traefik:v3.6.12"
  local traefik_version="v3.6.12"
  local traefik_sha="unknown"

  if [[ -n "${traefik_deployment_name:-}" ]]; then
    local live_traefik_image
    live_traefik_image="$(get_traefik_image "$traefik_deployment_name")"

    if [[ -n "${live_traefik_image:-}" ]]; then
      traefik_image="$live_traefik_image"
      traefik_version="$(get_traefik_version_from_image "$live_traefik_image")"
      traefik_sha="$(resolve_image_sha "$live_traefik_image")"
    fi
  fi

  local app_image="${APP_FULL_IMAGE:-${APP_IMAGE_NAME:-awroberts}:unknown}"
  local bg_image="${BG_FULL_IMAGE:-${BACKGROUND_IMAGE_NAME:-background-video}:unknown}"

  local app_sha
  local bg_sha
  app_sha="$(resolve_image_sha "$app_image")"
  bg_sha="$(resolve_image_sha "$bg_image")"

  local pod_status
  pod_status="$(kubectl get pod "$pod_name" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")"

  local pod_restarts
  pod_restarts="$(kubectl get pod "$pod_name" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")"

  local pod_ip
  pod_ip="$(kubectl get pod "$pod_name" -n "${NAMESPACE}" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")"

  local node_name
  node_name="$(kubectl get pod "$pod_name" -n "${NAMESPACE}" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")"

  local node_internal_ip=""
  if [[ -n "${node_name:-}" ]]; then
    node_internal_ip="$(
      kubectl get node "$node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo ""
    )"
  fi

  local deploy_ready
  deploy_ready="$(kubectl get deploy "$deployment_name" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null || echo "0/0")"

  local deploy_age
  deploy_age="$(kubectl get deploy "$deployment_name" -n "${NAMESPACE}" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "")"

  local service_cluster_ip
  service_cluster_ip="$(kubectl get svc "$service_name" -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")"

  local service_port
  service_port="$(kubectl get svc "$service_name" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "")"

  local traefik_deploy_ready
  traefik_deploy_ready="0/0"
  if [[ -n "${traefik_deployment_name:-}" ]]; then
    traefik_deploy_ready="$(kubectl get deploy "$traefik_deployment_name" -n traefik -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null || echo "0/0")"
  fi

  local traefik_deploy_age
  traefik_deploy_age=""
  if [[ -n "${traefik_deployment_name:-}" ]]; then
    traefik_deploy_age="$(kubectl get deploy "$traefik_deployment_name" -n traefik -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "")"
  fi

  local traefik_service_cluster_ip
  traefik_service_cluster_ip=""
  if [[ -n "${traefik_service_name:-}" ]]; then
    traefik_service_cluster_ip="$(kubectl get svc "$traefik_service_name" -n traefik -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")"
  fi

  local traefik_service_port
  traefik_service_port=""
  if [[ -n "${traefik_service_name:-}" ]]; then
    traefik_service_port="$(kubectl get svc "$traefik_service_name" -n traefik -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "")"
  fi

  local kubernetes_version
  kubernetes_version="$(
    kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion // "unknown"'
  )"

  local helm_version
  helm_version="$(helm version --short 2>/dev/null || echo "")"

  local app_pods_json
  app_pods_json="$(get_all_pods_json "${NAMESPACE}")"

  local traefik_pods_json
  traefik_pods_json="$(get_all_pods_json "traefik")"

  local pods_array="[]"
  if [[ -n "${app_pods_json:-}" || -n "${traefik_pods_json:-}" ]]; then
    pods_array="$(
      jq -nc \
        --argjson appPods "${app_pods_json:-{\"items\":[]}}" \
        --argjson traefikPods "${traefik_pods_json:-{\"items\":[]}}" \
        '
        {
          pods: (
            [
              $appPods.items[]? | {
                namespace: "awroberts",
                name: .metadata.name,
                status: .status.phase,
                restarts: ([.status.containerStatuses[]?.restartCount] | add // 0),
                ip: .status.podIP
              },
              $traefikPods.items[]? | {
                namespace: "traefik",
                name: .metadata.name,
                status: .status.phase,
                restarts: ([.status.containerStatuses[]?.restartCount] | add // 0),
                ip: .status.podIP
              }
            ]
          )
        } | .pods
        '
    )"
  fi

  cat > "$output_file" <<EOF
{
  "awroberts": {
    "deployment": {
      "name": "${deployment_name}",
      "ready": "${deploy_ready}",
      "age": "${deploy_age}"
    },
    "service": {
      "clusterIP": "${service_cluster_ip}",
      "port": ${service_port}
    },
    "build": {
      "image": "${app_image}",
      "tag": "${app_image##*:}",
      "sha": "${app_sha}"
    }
  },
  "traefik": {
    "deployment": {
      "name": "${traefik_deployment_name}",
      "ready": "${traefik_deploy_ready}",
      "age": "${traefik_deploy_age}"
    },
    "service": {
      "name": "${traefik_service_name}",
      "clusterIP": "${traefik_service_cluster_ip}",
      "port": ${traefik_service_port}
    },
    "build": {
      "image": "${traefik_image}",
      "version": "${traefik_version}",
      "sha": "${traefik_sha}"
    }
  },
  "pods": ${pods_array},
  "pod": {
    "name": "${pod_name}",
    "status": "${pod_status}",
    "restarts": ${pod_restarts},
    "ip": "${pod_ip}"
  },
  "node": {
    "internal": "${node_internal_ip}"
  },
  "kubernetes": {
    "version": "${kubernetes_version}"
  },
  "helm": {
    "version": "${helm_version}"
  }
}
EOF

  echo "deployment.json generated."
  echo
  echo "📤 Copying JSON into running pod"

  kubectl cp deployment.json "$NAMESPACE/$pod_name":/usr/share/nginx/html/deployment.json

  echo "deployment.json copied to pod: $pod_name"
}