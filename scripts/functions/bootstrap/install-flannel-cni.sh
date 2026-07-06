install_flannel_cni() {
  echo "Removing any existing Flannel CNI..."

  # Delete Flannel from the correct namespace (kube-flannel)
  kubectl delete daemonset kube-flannel-ds -n kube-flannel --ignore-not-found

  # Delete any old Flannel manifests
  kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml --ignore-not-found

  echo "Installing multi-arch Flannel CNI..."
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

  echo "Waiting for Flannel pods to become Ready..."
  kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel
}
