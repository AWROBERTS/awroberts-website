restart_kube_proxy() {
  echo "🔧 Applying kube-proxy ConfigMap..."
  kubectl apply -f "${PROJECT_ROOT}/scripts/deploy/kube-proxy-config.yaml"

  echo "🔁 Restarting kube-proxy..."
  kubectl delete pod -n kube-system -l k8s-app=kube-proxy
  kubectl rollout status daemonset/kube-proxy -n kube-system
}
