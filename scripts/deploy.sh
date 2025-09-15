#!/usr/bin/env bash
# Kubernetes app deployment using Helm, with TLS secret setup

notes_and_status() {
  if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:80 and WAN 443 -> NODE_IP:443"
  else
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:${HTTP_NODEPORT} and WAN 443 -> NODE_IP:${HTTPS_NODEPORT}"
  fi

  echo "Deployment complete. Quick status:"
  kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o wide
  kubectl -n "$NAMESPACE" get svc "$DEPLOYMENT_NAME" -o wide || true
  kubectl -n "$NAMESPACE" get ingress "$DEPLOYMENT_NAME" -o wide || true
  echo "Node IPs: $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')"
  echo "Public IP: $(curl -s https://api.ipify.org || true)"
}
