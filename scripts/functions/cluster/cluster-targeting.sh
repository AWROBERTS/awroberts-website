cluster_targeting() {
  # Allow override by env:
  #   KUBECONFIG_PATH=/etc/kubernetes/admin.conf KUBE_CONTEXT=ctx ./deploy-kubernetes.sh
  if [[ -f "${KUBECONFIG_PATH}" ]]; then
    export KUBECONFIG="${KUBECONFIG_PATH}"
  fi
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl config use-context "${KUBE_CONTEXT}" >/dev/null 2>&1 || true
  fi

  # Ensure current user has a readable kubeconfig if admin.conf exists
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    if [[ ! -r /etc/kubernetes/admin.conf ]]; then
      echo "Preparing kubeconfig for current user from /etc/kubernetes/admin.conf..."
      mkdir -p "$HOME/.kube"
      sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
      sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"
      export KUBECONFIG="$HOME/.kube/config"
    fi
  fi
}