install_flannel_cni() {
  echo "Removing any existing Flannel CNI..."

  kubectl delete daemonset kube-flannel-ds -n kube-flannel --ignore-not-found
  kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml --ignore-not-found

  echo "Installing upstream Flannel manifest..."
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

  echo "Detecting latest valid Flannel image tags from GHCR..."

  # Fetch tag lists from GHCR with required headers
  FLANNEL_TAGS=$(curl -s \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    -H "User-Agent: curl" \
    https://ghcr.io/v2/flannel-io/flannel/tags/list)

  CNI_TAGS=$(curl -s \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    -H "User-Agent: curl" \
    https://ghcr.io/v2/flannel-io/flannel-cni-plugin/tags/list)

  # Extract latest valid Flannel daemon version
  FLANNEL_VERSION=$(echo "$FLANNEL_TAGS" \
    | jq -r '.tags // [] | .[]' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n 1)

  # Extract latest valid Flannel CNI plugin version
  CNI_VERSION=$(echo "$CNI_TAGS" \
    | jq -r '.tags // [] | .[]' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+.*$' \
    | sort -V \
    | tail -n 1)

  # Fallbacks if GHCR fails or returns empty
  if [[ -z "$FLANNEL_VERSION" ]]; then
    echo "⚠️ GHCR returned no Flannel tags — using fallback v0.28.5"
    FLANNEL_VERSION="v0.28.5"
  fi

  if [[ -z "$CNI_VERSION" ]]; then
    echo "⚠️ GHCR returned no CNI plugin tags — using fallback v1.9.1-flannel2"
    CNI_VERSION="v1.9.1-flannel2"
  fi

  echo "Latest Flannel daemon tag: $FLANNEL_VERSION"
  echo "Latest Flannel CNI plugin tag: $CNI_VERSION"

  echo "Patching Flannel DaemonSet with valid image tags..."
  kubectl set image daemonset/kube-flannel-ds -n kube-flannel \
    kube-flannel=ghcr.io/flannel-io/flannel:$FLANNEL_VERSION \
    install-cni=ghcr.io/flannel-io/flannel-cni-plugin:$CNI_VERSION

  echo "Waiting for Flannel pods to become Ready..."
  kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel
}
