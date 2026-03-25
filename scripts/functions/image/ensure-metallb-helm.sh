ensure_metallb_helm() {
  echo "Installing MetalLB..."
  helm repo add metallb https://metallb.github.io/metallb
  helm repo update

  helm upgrade --install metallb metallb/metallb \
    --namespace metallb-system \
    --create-namespace

  echo "Waiting for MetalLB webhook to become ready..."
  kubectl wait --for=condition=ready pod -n metallb-system --all --timeout=60s
}
