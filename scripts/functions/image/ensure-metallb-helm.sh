ensure_metallb_helm() {
  echo "Installing MetalLB..."
  helm repo add metallb https://metallb.github.io/metallb
  helm repo update

  helm upgrade --install metallb metallb/metallb \
    --namespace metallb-system \
    --create-namespace
}
