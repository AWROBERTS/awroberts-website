initialise_kubeadm() {
  echo "Initialising control plane with pod CIDR ${POD_CIDR} and Kubernetes ${VERSION}..."
  sudo_if_needed kubeadm init \
    --kubernetes-version="${VERSION}" \
    --pod-network-cidr="${POD_CIDR}"
}
