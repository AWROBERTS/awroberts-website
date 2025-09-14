ensure_tls_secret() {
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
  kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" \
    --cert="$HOST_CERT_PATH" \
    --key="$HOST_KEY_PATH" \
    --dry-run=client -o yaml | kubectl apply -f -
}
