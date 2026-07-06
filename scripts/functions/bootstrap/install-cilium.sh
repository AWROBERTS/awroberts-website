install_cilium() {
  echo "Installing Cilium CNI..."

  helm repo add cilium https://helm.cilium.io
  helm repo update

  helm install cilium cilium/cilium \
    --version 1.16.3 \
    --namespace kube-system \
    --set kubeProxyReplacement=strict \
    --set k8sServiceHost="${CONTROL_PLANE_IP}" \
    --set k8sServicePort=6443 \
    --set ipam.mode=kubernetes \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true

  echo "Cilium installation triggered."
}
