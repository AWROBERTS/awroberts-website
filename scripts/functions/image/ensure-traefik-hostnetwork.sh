ensure_traefik_hostnetwork() {
  echo "🔍 Checking Traefik controller networking mode..."

  echo "🌐 Using NodePort mode (ensure WAN traffic is forwarded to NodePorts)"
  HTTP_NODEPORT="$(kubectl -n traefik get svc traefik -o jsonpath='{range .spec.ports[?(@.name=="web")]}{.nodePort}{end}' 2>/dev/null || true)"
  HTTPS_NODEPORT="$(kubectl -n traefik get svc traefik -o jsonpath='{range .spec.ports[?(@.name=="websecure")]}{.nodePort}{end}' 2>/dev/null || true)"

  if [[ -z "${HTTP_NODEPORT}" ]]; then
    HTTP_NODEPORT="31509"
  fi
  if [[ -z "${HTTPS_NODEPORT}" ]]; then
    HTTPS_NODEPORT="32545"
  fi

  echo "🔗 HTTP NodePort: ${HTTP_NODEPORT}"
  echo "🔗 HTTPS NodePort: ${HTTPS_NODEPORT}"

  echo "⏳ Waiting for Traefik to become Ready..."
  kubectl -n traefik rollout status deploy/traefik --timeout=300s || true

  echo "📡 Traefik Service status:"
  kubectl -n traefik get svc traefik -o wide || true
}