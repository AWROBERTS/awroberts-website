ensure_traefik_helm() {
  echo "🔧 Ensuring Traefik controller is installed via Helm..."

  echo "📡 Installing Gateway API CRDs (v1.5.1)..."

  # Delete all existing gateway CRDs before applying. This avoids the ValidatingAdmissionPolicy
  # that blocks experimental CRDs being installed on top of standard-channel CRDs.
  # GatewayClass/Gateway/HTTPRoute objects are recreated by the Helm deploy below.
  kubectl get crd -o name | grep gateway.networking.k8s.io | xargs --no-run-if-empty kubectl delete --ignore-not-found || true

  kubectl apply --server-side --force-conflicts \
    -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml

  echo "✅ Gateway API CRDs applied."

  helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1

  echo "📦 Installing Traefik with Gateway API enabled..."

  # Traefik must see the CRDs at install time to activate the gateway controller.
  helm upgrade --install traefik traefik/traefik \
    --namespace traefik \
    --create-namespace \
    -f "${PROJECT_ROOT}/traefik/traefik-values.yaml"

  echo "🔄 Restarting Traefik to ensure new args are loaded..."
  # With hostNetwork: true + Recreate strategy, rollout restart deadlocks.
  # Scale to 0 first to release host ports, then let the deployment scale back up.
  kubectl scale deploy/traefik --replicas=0 -n traefik
  kubectl wait --for=delete pod -l app.kubernetes.io/name=traefik -n traefik --timeout=60s 2>/dev/null || true
  kubectl scale deploy/traefik --replicas=1 -n traefik
  kubectl rollout status deploy/traefik -n traefik --timeout=120s

  echo "✅ Traefik installed or updated."
}
