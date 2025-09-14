is_cluster_accessible() {
  kubectl get nodes >/dev/null 2>&1
}
