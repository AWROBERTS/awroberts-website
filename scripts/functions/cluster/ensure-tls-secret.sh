ensure_tls_secret() {
  # Always ensure the traefik namespace exists
  kubectl get ns traefik >/dev/null 2>&1 || kubectl create namespace traefik

  kubectl -n traefik create secret tls "${SECRET_NAME}" \
    --cert="${HOST_CERT_PATH}" \
    --key="${HOST_KEY_PATH}" \
    --dry-run=client -o yaml | kubectl apply -f -
}
