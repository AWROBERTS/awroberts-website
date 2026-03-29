  # ==============================
  # 📦 Generate JSON for p5 sketch
  # ==============================

  # Deployment info
  DEPLOY_READY=$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.status.readyReplicas}/{.status.replicas}' 2>/dev/null)
  DEPLOY_IMAGE=$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  DEPLOY_AGE=$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)

  # Pod info
  POD_NAME=$(kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/instance=$HELM_RELEASE" -o jsonpath='{.items[0].metadata.name}')
  POD_STATUS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.phase}')
  POD_RESTARTS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].restartCount}')
  POD_IP=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.podIP}')

  # Service info
  SERVICE_CLUSTER_IP=$(kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" -o jsonpath='{.spec.clusterIP}')
  SERVICE_PORT=$(kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" -o jsonpath='{.spec.ports[0].port}')

  # Node info
  NODE_INTERNAL_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
  NODE_PUBLIC_IP=$(curl -s https://api.ipify.org || echo "Unavailable")

  # Write JSON file
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
    "internal": "$NODE_INTERNAL_IP",
    "public": "$NODE_PUBLIC_IP"
  }
}
EOF

  echo "Generated deployment.json for p5 sketch."
