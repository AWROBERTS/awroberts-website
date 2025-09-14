wait_for_flannel_ready() {
  echo "Waiting for Flannel pod to become Ready..."
  kubectl wait --for=condition=Ready pod -l app=flannel -n kube-flannel --timeout=180s || true
}
