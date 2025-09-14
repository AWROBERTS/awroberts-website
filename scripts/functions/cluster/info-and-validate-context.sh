info_and_validate_context() {
  local CTX
  CTX="$(kubectl config current-context || true || echo)"
  if [[ -z "${CTX}" ]]; then
    echo "No current kubectl context is set. Set KUBECONFIG to your kubeadm admin.conf or run kubeadm init first."
    exit 1
  fi
  echo "Current kube-context: ${CTX}"
  echo "Assuming kubeadm/containerd runtime"
}