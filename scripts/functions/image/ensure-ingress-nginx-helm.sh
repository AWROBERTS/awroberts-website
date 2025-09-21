ensure_ingress_nginx_helm() {
  echo "🔧 Ensuring ingress-nginx controller is installed via Helm..."

  if ! helm status ingress-nginx -n ingress-nginx >/dev/null 2>&1; then
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    helm install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx --create-namespace \
      --set controller.hostNetwork=true \
      --set controller.dnsPolicy=ClusterFirstWithHostNet \
      --set controller.service.type=ClusterIP \
      --set controller.service.ports.http=80 \
      --set controller.service.ports.https=443
  else
    echo "✅ ingress-nginx controller already installed via Helm."
  fi
}

