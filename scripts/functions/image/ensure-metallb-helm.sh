ensure_metallb_helm() {
  echo "Installing MetalLB..."

  # Install MetalLB chart (controller + speaker + RBAC)
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

  echo "Patching MetalLB speaker to add NET_ADMIN capability..."

  kubectl -n metallb-system patch daemonset metallb-speaker \
    --type merge \
    --patch "$(cat ${PROJECT_ROOT}/k8s/metallb/speaker-capabilities.yaml)"

  echo "MetalLB speaker patched."

  echo "Applying MetalLB L2 configuration..."

  # Apply CRDs
  kubectl apply -f "${PROJECT_ROOT}/k8s/metallb/ipaddresspool.yaml"
  kubectl apply -f "${PROJECT_ROOT}/k8s/metallb/l2advertisement.yaml"

  echo "MetalLB configuration applied."
}
