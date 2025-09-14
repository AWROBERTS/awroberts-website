is_control_plane_present() {
  [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]] || \
    sudo_if_needed ss -lnt '( sport = :6443 )' | grep -q 6443
}
