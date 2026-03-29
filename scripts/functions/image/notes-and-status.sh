#!/usr/bin/env bash
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
  echo "🚀 Application Deployment Status"
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
    ROLLOUT_OUTPUT=$(kubectl -n "$NAMESPACE" rollout status deploy/"$DEPLOYMENT_NAME" --watch=false 2>&1)

    if echo "$ROLLOUT_OUTPUT" | grep -q "successfully rolled out"; then
      echo "deployment \"$DEPLOYMENT_NAME\" successfully rolled out"
    else
      echo "⚠️ Rollout not complete, showing details:"
      kubectl -n "$NAMESPACE" rollout status deploy/"$DEPLOYMENT_NAME" --timeout=30s
    fi

    echo
    echo "Active Pods:"
    kubectl -n "$NAMESPACE" get pods \
      -l "app.kubernetes.io/instance=$HELM_RELEASE" \
      --field-selector=status.phase=Running \
      -o wide

    echo
    echo "Pod readiness conditions:"
    kubectl -n "$NAMESPACE" get pod \
      -l "app.kubernetes.io/instance=$HELM_RELEASE" \
      --field-selector=status.phase=Running \
      -o jsonpath='{range .items[*]}{.metadata.name}{" => Ready="}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

    echo
    echo "Active ReplicaSet:"
    kubectl -n "$NAMESPACE" get rs \
      -l "app.kubernetes.io/instance=$HELM_RELEASE" \
      --sort-by=.metadata.creationTimestamp \
      | tail -n 1

    echo
    echo "Service:"
    SERVICE_NAME=$(kubectl -n "$NAMESPACE" get svc \
      -l "app.kubernetes.io/instance=$HELM_RELEASE" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$SERVICE_NAME" ]]; then
      echo "Service not found"
    else
      kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" -o wide

      echo
      echo "Pods receiving traffic:"
      kubectl -n "$NAMESPACE" get endpointslice \
        -l "kubernetes.io/service-name=$SERVICE_NAME" \
        -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}' \
        || echo "No routing endpoints found"
    fi

    echo
    echo "HTTPRoutes:"
    HTTPROUTE_NAME="${DEPLOYMENT_NAME}-route"

    if kubectl -n "$NAMESPACE" get httproute "$HTTPROUTE_NAME" >/dev/null 2>&1; then
      echo "$HTTPROUTE_NAME"

      echo
      echo "HTTPRoute attachment conditions:"
      kubectl -n "$NAMESPACE" get httproute "$HTTPROUTE_NAME" \
        -o jsonpath='{range .status.parents[*].conditions[*]}{.type}{"="}{.status}{"\n"}{end}'
    else
      echo "HTTPRoute not found"
    fi

    echo
    echo "Middlewares (Gateway API):"
    kubectl -n "$NAMESPACE" get middleware 2>/dev/null || echo "Middleware not found"

    echo
    echo "Routing chain summary:"
    echo "- Gateway: ${DEPLOYMENT_NAME}-gateway"
    echo "- HTTPRoute: ${HTTPROUTE_NAME:-none}"
    echo "- Service: ${SERVICE_NAME:-none}"
    echo "- Pods receiving traffic:"
    kubectl -n "$NAMESPACE" get endpointslice \
      -l "kubernetes.io/service-name=$SERVICE_NAME" \
      -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}' \
      || echo "No routing endpoints found"
  fi

  echo
  echo "=============================="
  echo "🔍 Traefik Diagnostics"
  echo "=============================="

  echo "Traefik Deployment:"
  kubectl -n traefik get deploy traefik -o wide 2>/dev/null || echo "Traefik deployment not found"

  echo
  echo "Traefik Service:"
  kubectl -n traefik get svc traefik -o wide 2>/dev/null || echo "Traefik service not found"

  echo
  echo "Gateways:"
  kubectl -n "$NAMESPACE" get gateway 2>/dev/null || echo "No Gateways found in $NAMESPACE"

  echo
  echo "TLS Secrets:"
  kubectl -n "$NAMESPACE" get secret | grep tls 2>/dev/null || echo "No TLS secrets found in $NAMESPACE"

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
}
