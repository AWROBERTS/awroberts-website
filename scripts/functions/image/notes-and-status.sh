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
    HTTPROUTE_NAME="${DEPLOYMENT_NAME}-route"

    if kubectl -n "$NAMESPACE" get httproute "$HTTPROUTE_NAME" >/dev/null 2>&1; then
      kubectl -n "$NAMESPACE" get httproute "$HTTPROUTE_NAME"
    else
      echo "HTTPRoute not found"
    fi
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
  kubectl -n traefik get gateway \
    -o 'custom-columns=NAME:.metadata.name,CLASS:.spec.gatewayClassName,PROGRAMMED:.status.conditions[?(@.type=="Programmed")].status,AGE:.metadata.creationTimestamp' \
    2>/dev/null || echo "No Gateways found in traefik namespace"

  echo
  echo "TLS Secrets:"
  kubectl -n traefik get secret | grep tls 2>/dev/null || echo "No TLS secrets found in traefik"

  echo
  echo "=============================="
  echo "🖥️ Node & Network Info"
  echo "=============================="

  echo "Node IPs:"
  kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
  echo

  echo "Public IP:"
  curl -s https://api.ipify.org || echo "Unavailable"
  echo
  echo
}