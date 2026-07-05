install_flannel_cni() {
  echo "Installing Flannel CNI..."
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/main/Documentation/kube-flannel.yml
}
