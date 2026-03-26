wait_for_metallb() {
  echo "Waiting for MetalLB controller to become ready..."

  # Loop until the controller pod reports Ready=True
  until kubectl get pod -n metallb-system \
      -l app.kubernetes.io/component=controller \
      -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' \
      2>/dev/null | grep -q "True"; do
    sleep 1
  done

  echo "MetalLB controller is ready."
}
