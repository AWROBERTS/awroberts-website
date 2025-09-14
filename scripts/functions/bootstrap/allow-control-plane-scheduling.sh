allow_control_plane_scheduling() {
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
}
