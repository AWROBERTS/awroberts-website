ensure_ingress_nginx_helm() {
  echo "🔧 Ensuring ingress-nginx controller is installed via Helm..."

  if ! helm status ingress-nginx -n ingress-nginx >/dev/null 2>&1; then
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    helm install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx --create-namespace \
      --set controller.service.type=NodePort \
      --set controller.service.nodePorts.http=32207 \
      --set controller.service.nodePorts.https=32047
  else
    echo "✅ ingress-nginx controller already installed via Helm."
  fi
}

