#!/usr/bin/env bash
# Kubernetes app deployment and final status

kubernetes_deploy() {
  # 1) Ensure namespace exists
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

  # 2) Create or update the TLS Secret idempotently
  kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" \
    --cert="$HOST_CERT_PATH" \
    --key="$HOST_KEY_PATH" \
    --dry-run=client -o yaml | kubectl apply -f -

  # 3) Apply app manifests (Deployment, Service, Ingress, etc.)
  echo "Applying manifests from: ${MANIFEST_DIR}"
  kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR"

  # Ensure a Service exists; if not, create one for the Deployment (ClusterIP for Ingress)
  if ! kubectl -n "$NAMESPACE" get svc "${SERVICE_NAME}" >/dev/null 2>&1; then
    echo "No Service named '${SERVICE_NAME}' found. Creating one for Deployment '${DEPLOYMENT_NAME}'."
    kubectl -n "$NAMESPACE" expose deploy "$DEPLOYMENT_NAME" \
      --name "${SERVICE_NAME}" --port=80 --target-port=80 --type=ClusterIP
  fi

  # 4) Determine the container name (auto-detect if not provided)
  if [[ -z "$CONTAINER_NAME_IN_DEPLOY" ]]; then
    local CONTAINERS_IN_DEPLOY
    CONTAINERS_IN_DEPLOY="$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[*].name}')"
    if [[ -z "$CONTAINERS_IN_DEPLOY" ]]; then
      echo "Error: No containers found in deployment/${DEPLOYMENT_NAME}"
      exit 1
    fi
    CONTAINER_NAME_IN_DEPLOY="$(echo "$CONTAINERS_IN_DEPLOY" | awk '{print $1}')"
    if [[ "$(echo "$CONTAINERS_IN_DEPLOY" | wc -w)" -gt 1 ]]; then
      echo "Warning: Multiple containers in deployment/${DEPLOYMENT_NAME}: ${CONTAINERS_IN_DEPLOY}. Using '${CONTAINER_NAME_IN_DEPLOY}'."
    fi
  fi

  echo "Updating image for container '${CONTAINER_NAME_IN_DEPLOY}' in deployment/${DEPLOYMENT_NAME} to ${FULL_IMAGE}"
  kubectl -n "$NAMESPACE" set image deployment/"$DEPLOYMENT_NAME" "${CONTAINER_NAME_IN_DEPLOY}=${FULL_IMAGE}"

  # 5) Ensure we don't force pulls (so local image is used)
  kubectl -n "$NAMESPACE" patch deployment "$DEPLOYMENT_NAME" \
    --type='json' \
    -p="[
      {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/imagePullPolicy\",\"value\":\"IfNotPresent\"}
    ]" || true

  # 6) Optional: roll pods when certs change (handy for hot cert swaps)
  local TLS_CHECKSUM
  TLS_CHECKSUM="$(cat "$HOST_CERT_PATH" "$HOST_KEY_PATH" | sha256sum | awk '{print $1}')"
  kubectl -n "$NAMESPACE" annotate deployment/"$DEPLOYMENT_NAME" tls-checksum="$TLS_CHECKSUM" --overwrite

  # 7) Wait for rollout
  kubectl -n "$NAMESPACE" rollout status deployment/"$DEPLOYMENT_NAME" --timeout=240s
}

notes_and_status() {
  # Notes for router/NAT
  if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:80 and WAN 443 -> NODE_IP:443 (ingress-nginx hostNetwork)."
  else
    echo "- Router/NAT: forward WAN 80 -> NODE_IP:${HTTP_NODEPORT} and WAN 443 -> NODE_IP:${HTTPS_NODEPORT} (ingress-nginx NodePorts)."
  fi

  echo
  echo "Deployment done. Quick status:"
  kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o wide
  kubectl -n "$NAMESPACE" get svc "$SERVICE_NAME" -o wide || true
  if kubectl -n "$NAMESPACE" get ingress "$INGRESS_NAME" >/dev/null 2>&1; then
    kubectl -n "$NAMESPACE" get ingress "$INGRESS_NAME" -o wide
  fi

  local NODE_IPS PUB_IP
  NODE_IPS="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{" "}{end}')"
  PUB_IP="$(curl -s https://api.ipify.org || true)"
}