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
    echo "Service:"
    kubectl -n "$NAMESPACE" get svc -l "app.kubernetes.io/instance=$HELM_RELEASE" -o wide || echo "Service not found"

    echo
    echo "HTTPRoutes:"
    kubectl -n "$NAMESPACE" get httproute -l "app.kubernetes.io/instance=$HELM_RELEASE" 2>/dev/null || echo "HTTPRoute not found"

    echo
    echo "Middlewares (Gateway API):"
    kubectl -n "$NAMESPACE" get middleware 2>/dev/null || echo "Middleware not found"
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
