wait_for_flannel_ready() {
  echo "Waiting for Flannel DaemonSet to be fully available..."
  while true; do
    ready=$(kubectl get daemonset kube-flannel-ds -n kube-flannel -o jsonpath='{.status.numberAvailable}')
    desired=$(kubectl get daemonset kube-flannel-ds -n kube-flannel -o jsonpath='{.status.desiredNumberScheduled}')

    if [ "$ready" = "$desired" ] && [ -n "$ready" ]; then
      echo "Flannel is ready."
      break
    fi

    sleep 2
  done
}
