ensure_metallb_helm() {
  echo "Installing MetalLB..."

  # Install CRDs first
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/crd/bases/metallb.io_ipaddresspools.yaml
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/crd/bases/metallb.io_l2advertisements.yaml

  helm upgrade --install metallb "${PROJECT_ROOT}/k8s/metallb" \
    --namespace metallb-system \
    --create-namespace

  echo "Waiting for MetalLB controller to become ready..."

  # Wait until the controller pod is ready
  until kubectl get pod -n metallb-system \
      -l app.kubernetes.io/component=controller \
      -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' \
      2>/dev/null | grep -q "True"; do
    sleep 1
  done

  echo "MetalLB controller is ready."
}

