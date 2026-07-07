install_cilium() {
  echo "🔧 Ensuring CNI directories exist on all nodes..."

  for NODE in $(kubectl get nodes -o name | sed 's/node\///'); do
    echo "   → Fixing CNI dirs on $NODE"

    kubectl debug node/$NODE -it --image=busybox -- chroot /host sh -c '
      mkdir -p /opt/cni/bin
      mkdir -p /etc/cni/net.d
    ' >/dev/null 2>&1 || true

    echo "   → Restarting kubelet on $NODE"
    kubectl debug node/$NODE -it --image=busybox -- chroot /host sh -c '
      systemctl restart kubelet
    ' >/dev/null 2>&1 || true
  done

  echo "Installing Cilium CNI..."

  helm repo add cilium https://helm.cilium.io
  helm repo update

  helm upgrade --install cilium cilium/cilium \
    --namespace kube-system \
    --set k8sServiceHost="${CONTROL_PLANE_IP}" \
    --set k8sServicePort=6443 \
    --set kubeProxyReplacement=true \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true

  echo "Cilium installation triggered."
}
