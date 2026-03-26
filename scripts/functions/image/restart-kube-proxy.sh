restart_kube_proxy() {
  echo "🔧 Applying kube-proxy ConfigMap..."
  kubectl apply -f "${PROJECT_ROOT}/k8s/kube-proxy-config.yaml"

  echo "⏳ Waiting for ConfigMap to propagate..."
  sleep 3

  echo "🔁 Restarting kube-proxy pods..."
  kubectl delete pod -n kube-system -l k8s-app=kube-proxy

  echo "🔁 Forcing kube-proxy DaemonSet rollout restart..."
  kubectl rollout restart daemonset/kube-proxy -n kube-system

  echo "⏳ Waiting for kube-proxy rollout..."
  kubectl rollout status daemonset/kube-proxy -n kube-system
}
