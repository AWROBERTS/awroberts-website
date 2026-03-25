ensure_metallb_config_helm() {
  echo "Applying MetalLB configuration..."
  kubectl apply -f "${PROJECT_ROOT}/k8s/metallb/ipaddresspool.yaml"
  kubectl apply -f "${PROJECT_ROOT}/k8s/metallb/l2advertisement.yaml"
}

