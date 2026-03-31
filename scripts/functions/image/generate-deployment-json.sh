generate_deployment_json() {

  echo "=============================="
  echo "📦 Generating deployment.json"
  echo "=============================="

  # Escape helper
  json_escape() {
    printf '%s' "$1" | jq -R .
  }

  # Image object helper
  json_image_obj() {
    local NAME="$1"
    local TAG="$2"
    local SHA="$3"

    cat <<EOF
{
      "name": $(json_escape "$NAME"),
      "tag": $(json_escape "$TAG"),
      "sha": $(json_escape "$SHA")
}
EOF
  }

  # -----------------------------
  # Kubernetes metadata
  # -----------------------------
  DEPLOYMENT_NAME=$(kubectl get deploy -n "$NAMESPACE" \
    -l "app.kubernetes.io/instance=$HELM_RELEASE" \
    -o jsonpath='{.items[0].metadata.name}')

  POD_NAME=$(kubectl get pods -n "$NAMESPACE" \
    -l "app.kubernetes.io/instance=$HELM_RELEASE" \
    -o jsonpath='{.items[0].metadata.name}')

  SERVICE_NAME=$(kubectl -n "$NAMESPACE" get svc \
    -l "app.kubernetes.io/instance=$HELM_RELEASE" \
    -o jsonpath='{.items[0].metadata.name}')

  DEPLOY_READY=$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.status.readyReplicas}/{.status.replicas}')
  DEPLOY_AGE=$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.metadata.creationTimestamp}')

  POD_STATUS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.phase}')
  POD_RESTARTS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].restartCount}')
  POD_IP=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.podIP}')

  SERVICE_CLUSTER_IP=$(kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" -o jsonpath='{.spec.clusterIP}')
  SERVICE_PORT=$(kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" -o jsonpath='{.spec.ports[0].port}')

  NODE_INTERNAL_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

  K8S_VERSION=$(kubectl version -o json | jq -r '.serverVersion.gitVersion')
  HELM_VERSION=$(helm version --short --client)

  TRAEFIK_IMAGE=$(kubectl -n traefik get deploy traefik \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  TRAEFIK_VERSION="${TRAEFIK_IMAGE##*:}"

  # -----------------------------
  # Image SHAs (separate)
  # -----------------------------
  APP_SHA=$(ctr -n k8s.io images ls | grep "${APP_IMAGE_NAME_BASE}:${IMAGE_TAG}" | awk '{print $3}')
  BG_SHA=$(ctr -n k8s.io images ls | grep "${BG_IMAGE_NAME_BASE}:${IMAGE_TAG}" | awk '{print $3}')

  # -----------------------------
  # Generate JSON
  # -----------------------------
  cat <<EOF > deployment.json
{
  "deployment": {
    "name": $(json_escape "$DEPLOYMENT_NAME"),
    "ready": $(json_escape "$DEPLOY_READY"),
    "images": {
      "awroberts": $(json_escape "${APP_IMAGE_NAME_BASE}:${IMAGE_TAG}"),
      "backgroundVideo": $(json_escape "${BG_IMAGE_NAME_BASE}:${IMAGE_TAG}")
    },
    "age": $(json_escape "$DEPLOY_AGE")
  },
  "pod": {
    "name": $(json_escape "$POD_NAME"),
    "status": $(json_escape "$POD_STATUS"),
    "restarts": $POD_RESTARTS,
    "ip": $(json_escape "$POD_IP")
  },
  "service": {
    "clusterIP": $(json_escape "$SERVICE_CLUSTER_IP"),
    "port": $SERVICE_PORT
  },
  "node": {
    "internal": $(json_escape "$NODE_INTERNAL_IP")
  },
  "build": {
    "awroberts": $(json_image_obj "$APP_IMAGE_NAME_BASE" "$IMAGE_TAG" "$APP_SHA"),
    "backgroundVideo": $(json_image_obj "$BG_IMAGE_NAME_BASE" "$IMAGE_TAG" "$BG_SHA")
  },
  "kubernetes": {
    "version": $(json_escape "$K8S_VERSION")
  },
  "helm": {
    "version": $(json_escape "$HELM_VERSION")
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
