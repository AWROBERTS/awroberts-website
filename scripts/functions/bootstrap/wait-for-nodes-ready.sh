wait_for_nodes_ready() {
  kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null 2>&1 || true
}
