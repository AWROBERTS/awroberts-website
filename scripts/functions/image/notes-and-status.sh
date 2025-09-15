#!/usr/bin/env bash
# Kubernetes app deployment using Helm, with TLS secret setup

notes_and_status() {
  if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:80 and WAN 443 -> NODE_IP:443"
  else
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:${HTTP_NODEPORT} and WAN 443 -> NODE_IP:${HTTPS_NODEPORT}"
  fi

  echo "Deployment complete. Quick status:"
  kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o wide || echo "Deployment $DEPLOYMENT_NAME not found"
  kubectl -n "$NAMESPACE" get svc -o wide | grep "$DEPLOYMENT_NAME" || echo "Service not found"
  kubectl -n "$NAMESPACE" get ingress -o wide | grep "$DEPLOYMENT_NAME" || echo "Ingress not found"
  kubectl -n "$NAMESPACE" get pods -l app="$DEPLOYMENT_NAME" -o wide || echo "Pods not found"
  echo "Node IPs: $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')"
  echo "Public IP: $(curl -s https://api.ipify.org || echo "Unavailable")"
}

