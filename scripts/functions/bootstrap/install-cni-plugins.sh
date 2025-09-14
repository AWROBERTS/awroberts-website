install_cni_plugins() {
  echo "Installing CNI plugins required by Flannel..."
  curl -L https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz | \
    sudo_if_needed tar -C /opt/cni/bin -xz
}
