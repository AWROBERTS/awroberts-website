ensure_ingress_nginx_helm() {
  if ! helm status ingress-nginx -n ingress-nginx >/dev/null 2>&1; then
    echo "🔧 Installing ingress-nginx controller via Helm..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx --create-namespace \
      --set controller.hostNetwork="${INGRESS_HOSTNETWORK:-false}" \
      --set controller.dnsPolicy="ClusterFirstWithHostNet"
  else
    echo "✅ ingress-nginx controller already installed via Helm."
  fi
}
