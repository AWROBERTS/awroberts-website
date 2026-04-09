ensure_metrics_server() {
  echo "📦 Ensuring metrics-server is installed..."
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

  echo "🔧 Patching metrics-server for bare-metal..."
  kubectl patch deployment metrics-server -n kube-system \
    --type='json' \
    -p='[
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"},
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"}
    ]' || true

  echo "⏳ Waiting for metrics-server rollout..."
  kubectl rollout status deployment metrics-server -n kube-system --timeout=60s

  echo "🔍 Checking metrics API availability..."
  until kubectl get --raw /apis/metrics.k8s.io/v1beta1 >/dev/null 2>&1; do
    echo "   Metrics API not ready yet..."
    sleep 2
  done

  echo "📊 Metrics API is available."
}
