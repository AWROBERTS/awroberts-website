ensure_metallb_helm() {
  echo "Installing MetalLB..."
  helm repo add metallb https://metallb.github.io/metallb >/dev/null 2>&1 || true
  helm repo update

  helm upgrade --install metallb metallb/metallb \
    --namespace metallb-system \
    --create-namespace \
    -f "${PROJECT_ROOT}/k8s/metallb/values.yaml"

  echo "Waiting for MetalLB webhook to become ready..."
  kubectl wait --for=condition=ready pod -n metallb-system --all --timeout=20s
}
