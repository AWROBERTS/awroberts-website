allow_control_plane_scheduling() {
  echo "⚙️ Allowing workloads to schedule on the control plane node"

  kubectl taint nodes "$CONTROL_PLANE_HOST" node-role.kubernetes.io/control-plane:NoSchedule-
  kubectl taint nodes "$CONTROL_PLANE_HOST" node-role.kubernetes.io/master:NoSchedule- || true

  echo "✔️ Control plane node is now schedulable"
}
