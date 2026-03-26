ensure_metallb_helm() {
  echo "Installing MetalLB..."

  # Install official MetalLB chart (controller + CRDs)
  helm upgrade --install metallb metallb/metallb \
    --namespace metallb-system \
    --create-namespace \
    -f "${PROJECT_ROOT}/k8s/metallb/values.yaml"

  echo "Waiting for MetalLB controller to become ready..."

  # Wait until controller pod is ready
  until kubectl get pod -n metallb-system \
      -l app.kubernetes.io/component=controller \
      -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' \
      2>/dev/null | grep -q "True"; do
    sleep 1
  done

  echo "MetalLB controller is ready."

  # Install custom MetalLB config chart (speaker + IP pool + L2 advert)
  helm upgrade --install metallb-config "${PROJECT_ROOT}/k8s/metallb" \
    --namespace metallb-system

  echo "MetalLB configuration applied."
}
