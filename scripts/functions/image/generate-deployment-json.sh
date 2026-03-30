generate_deployment_json() {

  echo "=============================="
  echo "📦 Generating deployment.json"
  echo "=============================="

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
  DEPLOY_IMAGE=$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].image}')
  DEPLOY_AGE=$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.metadata.creationTimestamp}')

  POD_STATUS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.phase}')
  POD_RESTARTS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].restartCount}')
  POD_IP=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.podIP}')

  SERVICE_CLUSTER_IP=$(kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" -o jsonpath='{.spec.clusterIP}')
  SERVICE_PORT=$(kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" -o jsonpath='{.spec.ports[0].port}')

  NODE_INTERNAL_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

  IMAGE_SHA=$(ctr -n k8s.io images ls | grep "$IMAGE_TAG" | awk '{print $3}')

  K8S_VERSION=$(kubectl version -o json | jq -r '.serverVersion.gitVersion')

  HELM_VERSION=$(helm version --short --client)

  TRAEFIK_IMAGE=$(kubectl -n traefik get deploy traefik \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  TRAEFIK_VERSION="${TRAEFIK_IMAGE##*:}"

  cat <<EOF > deployment.json
{
  "deployment": {
    "name": "$DEPLOYMENT_NAME",
    "ready": "$DEPLOY_READY",
    "image": "$DEPLOY_IMAGE",
    "age": "$DEPLOY_AGE"
  },
  "pod": {
    "name": "$POD_NAME",
    "status": "$POD_STATUS",
    "restarts": $POD_RESTARTS,
    "ip": "$POD_IP"
  },
  "service": {
    "clusterIP": "$SERVICE_CLUSTER_IP",
    "port": $SERVICE_PORT
  },
  "node": {
    "internal": "$NODE_INTERNAL_IP"
  },
  "build": {
    "imageTag": "$IMAGE_TAG",
    "image": "$FULL_IMAGE",
    "sha": "$IMAGE_SHA"
  },
  "kubernetes": {
    "version": "$K8S_VERSION"
  },
  "helm": {
    "version": "$HELM_VERSION"
  },
  "traefik": {
    "image": "$TRAEFIK_IMAGE",
    "version": "$TRAEFIK_VERSION"
  }
}
EOF

  echo "deployment.json generated."
  echo
  echo "📤 Copying JSON into running pod"

  kubectl cp deployment.json "$NAMESPACE/$POD_NAME":/usr/share/nginx/html/deployment.json

  echo "deployment.json copied to pod: $POD_NAME"
}
