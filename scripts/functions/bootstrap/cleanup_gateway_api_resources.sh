cleanup_gateway_api_resources() {
  echo "Cleaning stale Gateway API resources..."

  if kubectl api-resources 2>/dev/null | awk '{print $1}' | grep -qx 'httproute'; then
    kubectl delete httproute -A --all --ignore-not-found
  else
    echo "Skipping httproute: not available in this cluster"
  fi

  if kubectl api-resources 2>/dev/null | awk '{print $1}' | grep -qx 'gateway'; then
    kubectl delete gateway -A --all --ignore-not-found
  else
    echo "Skipping gateway: not available in this cluster"
  fi

  if kubectl api-resources 2>/dev/null | awk '{print $1}' | grep -qx 'tcproute'; then
    kubectl delete tcproute -A --all --ignore-not-found
  else
    echo "Skipping tcproute: not available in this cluster"
  fi

  if kubectl api-resources 2>/dev/null | awk '{print $1}' | grep -qx 'udproute'; then
    kubectl delete udproute -A --all --ignore-not-found
  else
    echo "Skipping udproute: not available in this cluster"
  fi
}