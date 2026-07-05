install_flannel_cni() {
  echo "Installing Flannel CNI..."
  kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
}
