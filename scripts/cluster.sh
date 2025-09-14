#!/usr/bin/env bash
# Cluster bootstrap, context, containerd, kubelet, ingress

cluster_targeting() {
  # Allow override by env:
  #   KUBECONFIG_PATH=/etc/kubernetes/admin.conf KUBE_CONTEXT=ctx ./deploy-kubernetes.sh
  if [[ -f "${KUBECONFIG_PATH}" ]]; then
    export KUBECONFIG="${KUBECONFIG_PATH}"
  fi
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl config use-context "${KUBE_CONTEXT}" >/dev/null 2>&1 || true
  fi

  # Ensure current user has a readable kubeconfig if admin.conf exists
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    if [[ ! -r /etc/kubernetes/admin.conf ]]; then
      echo "Preparing kubeconfig for current user from /etc/kubernetes/admin.conf..."
      mkdir -p "$HOME/.kube"
      sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
      sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"
      export KUBECONFIG="$HOME/.kube/config"
    fi
  fi
}

ensure_k8s_and_containerd_installed() {
  # Ensure kubeadm/kubelet/kubectl are installed (auto-install if missing)
  if ! command -v kubeadm >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
    echo "Installing kubeadm, kubelet, kubectl..."
    sudo_if_needed apt-get update
    sudo_if_needed apt-get install -y apt-transport-https ca-certificates curl gpg
    sudo_if_needed curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg \
      https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | \
      sudo_if_needed tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
    sudo_if_needed apt-get update
    sudo_if_needed apt-get install -y kubelet kubeadm kubectl
    sudo_if_needed systemctl enable --now kubelet
  fi

  # Ensure containerd exists
  if ! command -v containerd >/dev/null 2>&1; then
    echo "Installing containerd..."
    sudo_if_needed apt-get update
    sudo_if_needed apt-get install -y containerd
  fi
}

bootstrap_cluster_if_needed() {
  # Optional bootstrap kubeadm single-node with Flannel if no cluster
  if [[ "${CLUSTER_BOOTSTRAP}" != "true" ]]; then
    return
  fi

  local NEED_INIT="false"
  if kubectl get nodes >/dev/null 2>&1; then
    NEED_INIT="false"
  else
    if [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]] \
       || sudo_if_needed ss -lnt '( sport = :6443 )' | grep -q 6443; then
      echo "Existing kubeadm control plane detected; skipping kubeadm init."
      # Ensure kubeconfig for current user
      if [[ -f /etc/kubernetes/admin.conf ]]; then
        mkdir -p "$HOME/.kube"
        sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
        sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"
        export KUBECONFIG="$HOME/.kube/config"
      fi
      kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null 2>&1 || true
    else
      NEED_INIT="true"
    fi
  fi

  if [[ "${NEED_INIT}" == "true" ]]; then
    echo "No reachable Kubernetes cluster via kubectl. Bootstrapping control plane with kubeadm (Flannel)..."

    # 1) Prep: disable swap and set sysctls, kernel modules
    echo "Disabling swap and updating /etc/fstab..."
    sudo_if_needed swapoff -a || true
    if [[ -f /etc/fstab ]]; then
      sudo_if_needed sed -i.bak -E 's@^([^#].*\s+swap\s+)@#\1@' /etc/fstab || true
    fi

    echo "Ensuring br_netfilter kernel module is loaded"
    sudo_if_needed modprobe br_netfilter || true
    echo 'br_netfilter' | sudo_if_needed tee /etc/modules-load.d/br_netfilter.conf >/dev/null

    echo "Configuring kernel sysctls for bridged traffic and forwarding..."
    sudo_if_needed tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    sudo_if_needed sysctl --system >/dev/null

    # 2) Ensure containerd uses systemd cgroups
    echo "Ensuring containerd uses systemd cgroups..."
    sudo_if_needed mkdir -p /etc/containerd
    if ! sudo_if_needed test -f /etc/containerd/config.toml; then
      containerd config default | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
    fi
    sudo_if_needed sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
    sudo_if_needed systemctl enable --now containerd
    sudo_if_needed systemctl restart containerd

    # 3) kubeadm init with Flannel pod CIDR
    echo "Initializing control plane with pod CIDR ${POD_CIDR}..."
    sudo_if_needed kubeadm init --pod-network-cidr="${POD_CIDR}"

    # 4) Configure kubectl for current user
    echo "Configuring kubeconfig for current user..."
    mkdir -p "$HOME/.kube"
    sudo_if_needed cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo_if_needed chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    export KUBECONFIG="$HOME/.kube/config"

    # 5) Prepare host paths for Flannel
    echo "Creating required host paths for Flannel..."
    sudo_if_needed mkdir -p /opt/cni/bin /etc/cni/net.d /run/flannel
    sudo_if_needed chmod 755 /etc/cni/net.d /run/flannel

    # Optional: clean up old CNI configs
    echo "Cleaning up old CNI configs..."
    sudo_if_needed rm -f /etc/cni/net.d/*.conf /etc/cni/net.d/*.conflist

    # 6) Install CNI plugins required by Flannel
    echo "Installing CNI plugins required by Flannel..."
    curl -L https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz | sudo_if_needed tar -C /opt/cni/bin -xz

    # 7) Install Flannel CNI
    echo "Installing Flannel CNI..."
    kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

    # 8) Wait for Flannel to become Ready
    echo "Waiting for Flannel pod to become Ready..."
    kubectl wait --for=condition=Ready pod -l app=flannel -n kube-flannel --timeout=180s || true

    # 9) Allow scheduling on control plane (single-node)
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

    # 10) Wait for node Ready
    echo "Waiting for node to become Ready..."
    kubectl wait --for=condition=Ready node --all --timeout=300s || true
  fi
}

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

ensure_containerd_config() {
  echo "Ensuring containerd config exists and uses systemd cgroups..."
  sudo_if_needed mkdir -p /etc/containerd
  if ! sudo_if_needed test -f /etc/containerd/config.toml; then
    containerd config default | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
  fi
  sudo_if_needed sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
  # Ensure CRI pause image matches kubeadm v1.30 recommendation (3.9)
  if grep -q 'sandbox_image' /etc/containerd/config.toml; then
    sudo_if_needed sed -i 's#sandbox_image = ".*"#sandbox_image = "registry.k8s.io/pause:3.9"#' /etc/containerd/config.toml || true
  else
    sudo_if_needed awk '1;/\[plugins\."io.containerd.grpc.v1.cri"\]/{print "  sandbox_image = \"registry.k8s.io/pause:3.9\""}' /etc/containerd/config.toml \
      | sudo_if_needed tee /etc/containerd/config.toml >/dev/null
  fi
  sudo_if_needed systemctl enable --now containerd
  sudo_if_needed systemctl restart containerd
  sudo_if_needed ctr -n k8s.io images ls >/dev/null 2>&1 || true
}

verify_kubelet_cgroup() {
  if [[ -f /var/lib/kubelet/config.yaml ]]; then
    if ! grep -q '^cgroupDriver: systemd' /var/lib/kubelet/config.yaml; then
      echo "Warning: kubelet cgroupDriver is not 'systemd'. With containerd, 'systemd' is recommended."
      if [[ "${AUTO_FIX_KUBELET_CGROUP:-true}" == "true" ]]; then
        echo "Setting kubelet cgroupDriver to systemd and restarting kubelet..."
        if grep -q '^cgroupDriver:' /var/lib/kubelet/config.yaml; then
          sudo_if_needed sed -i -E 's/^cgroupDriver: .*/cgroupDriver: systemd/' /var/lib/kubelet/config.yaml || true
        else
          echo "cgroupDriver: systemd" | sudo_if_needed tee -a /var/lib/kubelet/config.yaml >/dev/null
        fi
        sudo_if_needed systemctl restart kubelet || true
      fi
    fi
  fi
}

ensure_ingress_admission_secret() {
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
}

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