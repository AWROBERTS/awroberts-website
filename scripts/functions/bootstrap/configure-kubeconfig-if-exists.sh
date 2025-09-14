configure_kubeconfig_if_exists() {
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    mkdir -p "$HOME/.kube"
    sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    export KUBECONFIG="$HOME/.kube/config"
  fi
}
