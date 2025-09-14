ensure_ingress_nginx() {
  echo "Ensuring ingress-nginx controller is installed (bare-metal preset)..."
  if ! kubectl -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
  fi

  if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
    echo "Configuring ingress-nginx to use hostNetwork (binds to node ports 80/443)..."
    kubectl -n ingress-nginx patch deploy ingress-nginx-controller --type='json' -p='[
      {"op":"add","path":"/spec/template/spec/hostNetwork","value":true},
      {"op":"add","path":"/spec/template/spec/dnsPolicy","value":"ClusterFirstWithHostNet"}
    ]' || true

    kubectl -n ingress-nginx patch svc ingress-nginx-controller --type=merge -p='{
      "spec":{
        "type":"ClusterIP",
        "ports":[
          {"name":"http","port":80,"targetPort":"http","protocol":"TCP"},
          {"name":"https","port":443,"targetPort":"https","protocol":"TCP"}
        ]
      }
    }' || true
  else
    echo "Using ingress-nginx NodePort mode (router must forward WAN 80/443 to NodePorts)."
  fi

  echo "Waiting for ingress-nginx-controller to become Ready..."
  kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s || true

  echo "Ingress controller Service status:"
  kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide || true

  # Discover NodePort values for HTTP/HTTPS if in NodePort mode (fallback to common defaults if not found)
  if [[ "${INGRESS_HOSTNETWORK}" != "true" ]]; then
    HTTP_NODEPORT="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{range .spec.ports[?(@.name=="http")]}{.nodePort}{end}' 2>/dev/null || true)"
    HTTPS_NODEPORT="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{range .spec.ports[?(@.name=="https")]}{.nodePort}{end}' 2>/dev/null || true)"
    if [[ -z "${HTTP_NODEPORT}" ]]; then HTTP_NODEPORT="30080"; fi
    if [[ -z "${HTTPS_NODEPORT}" ]]; then HTTPS_NODEPORT="30443"; fi
  fi
}