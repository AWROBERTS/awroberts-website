install_cilium() {
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
