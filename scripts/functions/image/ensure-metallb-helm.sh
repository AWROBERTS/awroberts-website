ensure_metallb_helm() {
  echo "Deploying MetalLB configuration..."
  helm upgrade --install metallb-config "${PROJECT_ROOT}/k8s/metallb"
}
