ensure_metallb_config_helm() {
  echo "Deploying MetalLB configuration..."
  helm upgrade --install metallb-config "${PROJECT_ROOT}/k8s/metallb" \
    --namespace metallb-system
}
