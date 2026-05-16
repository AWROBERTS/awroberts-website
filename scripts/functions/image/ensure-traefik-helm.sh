ensure_traefik_helm() {
  echo "🔧 Ensuring Traefik controller is installed via Helm..."

  echo "📡 Installing Gateway API CRDs (v1.2.0)..."

  # Install stable v1 CRDs
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

  # Install extended CRDs (TLSRoute, BackendTLSPolicy, GRPCRoute, etc.)
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/experimental-install.yaml

  echo "✅ Gateway API CRDs applied."

  helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1

  echo "📦 Installing Traefik CRDs chart..."
  helm upgrade --install traefik-crds traefik/traefik-crds --namespace traefik --create-namespace

  echo "📦 Installing Traefik (skipping CRDs)..."
  helm upgrade --install traefik traefik/traefik \
    --namespace traefik \
    --skip-crds \
    -f "${PROJECT_ROOT}/traefik/traefik-values.yaml"

  echo "🔄 Restarting Traefik to load new CRDs..."
  kubectl rollout restart deploy/traefik -n traefik

  echo "✅ Traefik installed or updated."
}
