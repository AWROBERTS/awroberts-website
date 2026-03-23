cleanup_gateway_api_resources() {
  echo "Cleaning stale Gateway API resources..."
  kubectl delete httproute -A --all --ignore-not-found
  kubectl delete gateway -A --all --ignore-not-found
  kubectl delete tcproute -A --all --ignore-not-found 2>/dev/null || true
  kubectl delete udproute -A --all --ignore-not-found 2>/dev/null || true
}
