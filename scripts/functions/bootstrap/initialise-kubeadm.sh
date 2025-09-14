initialise_kubeadm() {
  echo "Initialising control plane with pod CIDR ${POD_CIDR}..."
  sudo_if_needed kubeadm init --pod-network-cidr="${POD_CIDR}"
}
