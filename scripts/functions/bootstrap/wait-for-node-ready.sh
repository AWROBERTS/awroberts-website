wait_for_node_ready() {
  echo "Waiting for node to become Ready..."
  kubectl wait --for=condition=Ready node --all --timeout=300s || true
}
