ensure_traefik_helm() {
  echo "🔧 Ensuring Traefik controller is installed via Helm..."

  helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1

  helm upgrade --install traefik traefik/traefik \
    --namespace traefik --create-namespace \
    -f "${PROJECT_ROOT}/traefik/traefik-values.yaml"

  echo "✅ Traefik installed or updated."
}
