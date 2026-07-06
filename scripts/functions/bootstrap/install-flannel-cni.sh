install_flannel_cni() {
  echo "Removing any existing Flannel CNI..."

  kubectl delete daemonset kube-flannel-ds -n kube-flannel --ignore-not-found
  kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml --ignore-not-found

  echo "Installing upstream Flannel manifest..."
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

  echo "Using stable Flannel daemon version..."

  FLANNEL_VERSION="v0.28.5"

  echo "Flannel daemon: $FLANNEL_VERSION"

  echo "Patching the Flannel daemon image..."
  kubectl set image daemonset/kube-flannel-ds -n kube-flannel \
    kube-flannel=ghcr.io/flannel-io/flannel:$FLANNEL_VERSION

  echo "Waiting for Flannel pods to become Ready..."
  kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel
}
