ensure_metallb_crds() {
  echo "📘 Installing MetalLB CRDs..."
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/crd.yaml
}
