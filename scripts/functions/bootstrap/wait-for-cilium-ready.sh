wait_for_cilium_ready() {
  echo "Waiting for Cilium to become Ready..."
  kubectl -n kube-system rollout status daemonset/cilium
}
