ensure_metrics_server() {
  echo "📦 Ensuring metrics-server is installed..."

  # Only apply components.yaml if metrics-server Deployment does NOT already exist
  if ! kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  else
    echo "   metrics-server Deployment already exists; skipping components.yaml apply."
  fi

  echo "🔧 Patching metrics-server for bare-metal (full args replace)..."
  kubectl patch deployment metrics-server -n kube-system \
    --type='json' \
    -p='[
      {
        "op": "replace",
        "path": "/spec/template/spec/containers/0/args",
        "value": [
          "--cert-dir=/tmp",
          "--secure-port=4443",
          "--kubelet-insecure-tls",
          "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
          "--kubelet-use-node-status-port",
          "--metric-resolution=15s"
        ]
      }
    ]'

  echo "🔧 Ensuring metrics-server exposes correct containerPort..."
  kubectl patch deployment metrics-server -n kube-system \
    --type='json' \
    -p='[
      { "op": "remove", "path": "/spec/template/spec/containers/0/ports" },
      { "op": "add", "path": "/spec/template/spec/containers/0/ports", "value": [
          { "containerPort": 4443, "name": "https", "protocol": "TCP" }
      ]}
    ]'

  echo "🔧 Ensuring metrics-server Service uses correct ports..."
  kubectl patch service metrics-server -n kube-system \
    --type='json' \
    -p='[
      { "op": "replace", "path": "/spec/ports/0/port", "value": 443 },
      { "op": "replace", "path": "/spec/ports/0/targetPort", "value": 4443 }
    ]'

  echo "🧹 Removing old metrics-server Pods..."
  kubectl delete pod -n kube-system -l k8s-app=metrics-server

  echo "⏳ Waiting for metrics-server rollout..."
  kubectl rollout status deployment metrics-server -n kube-system --timeout=60s

  echo "🔍 Checking metrics API availability..."
  until kubectl get --raw /apis/metrics.k8s.io/v1beta1 >/dev/null 2>&1; do
    echo "   Metrics API not ready yet..."
    sleep 2
  done

  echo "📊 Metrics API is available."
}
