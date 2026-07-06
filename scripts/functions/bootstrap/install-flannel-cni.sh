install_flannel_cni() {
  echo "Removing any existing Flannel CNI..."

  kubectl delete daemonset kube-flannel-ds -n kube-flannel --ignore-not-found
  kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml --ignore-not-found

  echo "Installing upstream Flannel manifest..."
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

  echo "Detecting latest valid Flannel image tags from GHCR..."

  FLANNEL_VERSION=$(curl -s -H "Accept: application/vnd.oci.image.index.v1+json" \
    https://ghcr.io/v2/flannel-io/flannel/tags/list \
    | jq -r '.tags // [] | .[]' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n 1)

  CNI_VERSION=$(curl -s -H "Accept: application/vnd.oci.image.index.v1+json" \
    https://ghcr.io/v2/flannel-io/flannel-cni-plugin/tags/list \
    | jq -r '.tags // [] | .[]' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+.*$' \
    | sort -V \
    | tail -n 1)

  echo "Latest Flannel daemon tag: $FLANNEL_VERSION"
  echo "Latest Flannel CNI plugin tag: $CNI_VERSION"

  echo "Patching Flannel DaemonSet with valid image tags..."
  kubectl set image daemonset/kube-flannel-ds -n kube-flannel \
    kube-flannel=ghcr.io/flannel-io/flannel:$FLANNEL_VERSION \
    install-cni=ghcr.io/flannel-io/flannel-cni-plugin:$CNI_VERSION

  echo "Waiting for Flannel pods to become Ready..."
  kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel
}
