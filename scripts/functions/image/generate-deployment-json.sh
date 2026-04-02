#!/usr/bin/env bash

generate_deployment_json() {
  local output_file="${1:-deployment.json}"

  resolve_image_sha() {
    local image_ref="$1"
    local label_sha=""
    local repo_digest=""
    local image_id=""
    local tag_sha=""

    # Try OCI revision label first
    label_sha="$(
      docker image inspect "$image_ref" \
        --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' 2>/dev/null
    )"

    if [[ -n "$label_sha" && "$label_sha" != "<no value>" ]]; then
      echo "$label_sha"
      return 0
    fi

    # Try repo digest if available
    repo_digest="$(
      docker image inspect "$image_ref" \
        --format '{{index .RepoDigests 0}}' 2>/dev/null
    )"

    if [[ -n "$repo_digest" && "$repo_digest" != "<no value>" ]]; then
      echo "$repo_digest"
      return 0
    fi

    # Try image ID as a fallback
    image_id="$(
      docker image inspect "$image_ref" \
        --format '{{.Id}}' 2>/dev/null
    )"

    if [[ -n "$image_id" && "$image_id" != "<no value>" ]]; then
      echo "${image_id#sha256:}"
      return 0
    fi

    # Final fallback: use the tag portion of the image reference
    tag_sha="${image_ref##*:}"
    if [[ -n "$tag_sha" && "$tag_sha" != "$image_ref" ]]; then
      echo "$tag_sha"
      return 0
    fi

    echo "unknown"
  }

  get_image_id_for_pod_container() {
    local pod_name="$1"
    local container_name="$2"

    kubectl get pod "$pod_name" -n "$NAMESPACE" \
      -o jsonpath="{.status.containerStatuses[?(@.name==\"${container_name}\")].imageID}" 2>/dev/null \
      | sed 's#^docker-pullable://##; s#^containerd://##'
  }

  local deployment_name
  deployment_name="$(kubectl get deploy -n "$NAMESPACE" \
    -l "app.kubernetes.io/instance=$HELM_RELEASE" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"

  if [[ -z "$deployment_name" ]]; then
    echo "❌ No deployment found for Helm release '$HELM_RELEASE' in namespace '$NAMESPACE'" >&2
    return 1
  fi

  local pod_name
  pod_name="$(kubectl get pod -n "$NAMESPACE" \
    -l "app.kubernetes.io/instance=$HELM_RELEASE" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"

  if [[ -z "$pod_name" ]]; then
    echo "❌ No running pod found for Helm release '$HELM_RELEASE' in namespace '$NAMESPACE'" >&2
    return 1
  fi

  local service_name
  service_name="$(kubectl get svc -n "$NAMESPACE" \
    -l "app.kubernetes.io/instance=$HELM_RELEASE" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"

  local app_image="${APP_FULL_IMAGE:-awroberts:unknown}"
  local bg_image="${BG_FULL_IMAGE:-background-video:unknown}"

  local app_sha
  local bg_sha

  app_sha="$(resolve_image_sha "$app_image")"
  bg_sha="$(resolve_image_sha "$bg_image")"

  local pod_image_id
  pod_image_id="$(get_image_id_for_pod_container "$pod_name" "awroberts-web" || true)"

  cat > "$output_file" <<EOF
{
  "deployment": {
    "name": "${deployment_name}",
    "ready": "$(kubectl get deploy "$deployment_name" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null)",
    "images": {
      "awroberts": "${app_image}",
      "backgroundVideo": "${bg_image}"
    },
    "age": "$(kubectl get deploy "$deployment_name" -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)"
  },
  "pod": {
    "name": "${pod_name}",
    "status": "$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)",
    "restarts": "$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)",
    "ip": "$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null)"
  },
  "service": {
    "clusterIP": "$(kubectl get svc "$service_name" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)",
    "port": "$(kubectl get svc "$service_name" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)"
  },
  "node": {
    "internal": "$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null | xargs -r kubectl get node -o jsonpath='{.items[?(@.metadata.name=="'"$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null)"'")].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)"
  },
  "build": {
    "awroberts": {
      "name": "awroberts",
      "tag": "${app_image##*:}",
      "sha": "${app_sha}"
    },
    "backgroundVideo": {
      "name": "background-video",
      "tag": "${bg_image##*:}",
      "sha": "${bg_sha}"
    }
  },
  "kubernetes": {
    "version": "$(kubectl version --client --short 2>/dev/null | awk '{print $3}')"
  },
  "helm": {
    "version": "$(helm version --short 2>/dev/null)"
  },
  "traefik": {
    "image": $(json_escape "$TRAEFIK_IMAGE"),
    "version": $(json_escape "$TRAEFIK_VERSION")
  }
}
EOF

  echo "deployment.json generated."
  echo
  echo "📤 Copying JSON into running pod"

  kubectl cp deployment.json "$NAMESPACE/$POD_NAME":/usr/share/nginx/html/deployment.json

  echo "deployment.json copied to pod: $POD_NAME"
}
