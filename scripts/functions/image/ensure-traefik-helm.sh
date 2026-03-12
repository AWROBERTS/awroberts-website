ensure_traefik_helm() {
  echo "🔧 Ensuring Traefik controller is installed via Helm..."

  helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1

  helm upgrade --install traefik traefik/traefik \
    --namespace traefik --create-namespace \
    --set ingressRoute.dashboard.enabled=false \
    --set providers.kubernetesCRD.enabled=true \
    --set providers.kubernetesIngress.enabled=false \
    --set service.type=NodePort \
    --set ports.web.nodePort=31509 \
    --set ports.websecure.nodePort=32545

  echo "✅ Traefik installed or updated."
}