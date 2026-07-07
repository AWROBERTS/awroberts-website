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

  echo "📦 Installing Cilium CNI..."

  helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  helm upgrade --install cilium cilium/cilium \
    --namespace kube-system \
    --set k8sServiceHost="${CONTROL_PLANE_IP}" \
    --set k8sServicePort=6443 \
    --set kubeProxyReplacement=true \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true

  echo "⏳ Waiting for Cilium DaemonSet to become Ready..."
  kubectl rollout status daemonset/cilium -n kube-system --timeout=120s

  echo "⏳ Waiting for Cilium CNI init containers to finish..."
  kubectl wait --for=condition=Ready pod -n kube-system -l k8s-app=cilium --timeout=120s

  echo "🔍 Verifying CNI plugin installation on all nodes..."

  for NODE in $(kubectl get nodes -o name | sed 's/node\///'); do
    echo "   → Checking CNI plugin on $NODE"

    kubectl debug node/$NODE -it --image=busybox -- chroot /host sh -c '
      if [ ! -f /opt/cni/bin/cilium-cni ]; then
        echo "ERROR: cilium-cni missing on node!"
        exit 1
      fi
    ' >/dev/null 2>&1

    if [ $? -ne 0 ]; then
      echo "❌ Cilium CNI plugin missing on node: $NODE"
      echo "   This will cause Pods to stay in ContainerCreating."
      exit 1
    else
      echo "   ✔ cilium-cni present on $NODE"
    fi
  done

  echo "🎉 Cilium installation complete and verified."
}
