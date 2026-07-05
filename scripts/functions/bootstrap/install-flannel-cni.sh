install_flannel_cni() {
  echo "Removing Flannel CNI..."
  kubectl delete daemonset kube-flannel-ds -n kube-flannel --ignore-not-found
  kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml --ignore-not-found
  echo "Installing Flannel CNI..."
  kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
}
