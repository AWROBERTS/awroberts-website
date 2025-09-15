ensure_ingress_nginx_hostnetwork() {
  echo "🔍 Checking ingress-nginx controller networking mode..."

  if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
    echo "✅ hostNetwork mode enabled (binds to node ports 80/443)"
  else
    echo "🌐 Using NodePort mode (ensure WAN traffic is forwarded to NodePorts)"
    HTTP_NODEPORT="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{range .spec.ports[?(@.name=="http")]}{.nodePort}{end}' 2>/dev/null || true)"
    HTTPS_NODEPORT="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{range .spec.ports[?(@.name=="https")]}{.nodePort}{end}' 2>/dev/null || true)"
    if [[ -z "${HTTP_NODEPORT}" ]]; then HTTP_NODEPORT="30080"; fi
    if [[ -z "${HTTPS_NODEPORT}" ]]; then HTTPS_NODEPORT="30443"; fi
    echo "🔗 HTTP NodePort: ${HTTP_NODEPORT}"
    echo "🔗 HTTPS NodePort: ${HTTPS_NODEPORT}"
  fi

  echo "⏳ Waiting for ingress-nginx-controller to become Ready..."
  kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s || true

  echo "📡 Ingress controller Service status:"
  kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide || true
}
