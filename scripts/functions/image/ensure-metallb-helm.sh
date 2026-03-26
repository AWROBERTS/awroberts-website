ensure_metallb_helm() {
  echo "Installing MetalLB..."

  helm upgrade --install metallb "${PROJECT_ROOT}/k8s/metallb" \
    --namespace metallb-system \
    --create-namespace

  echo "Waiting for MetalLB webhook to become ready..."
  kubectl wait --for=condition=ready pod -n metallb-system --all --timeout=20s
}
