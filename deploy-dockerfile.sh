#!/usr/bin/env bash
set -euo pipefail

# Explicitly load from awroberts.env (required)
ENV_FILE="awroberts.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "Error: $ENV_FILE not found. Create it with your env values."
  exit 1
fi

# Recreate container
sudo docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

sudo docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${HTTP_PORT}:80" -p "${HTTPS_PORT}:443" \
  -v "${HOST_CERT_PATH}:/etc/nginx/ssl/cert.crt:ro" \
  -v "${HOST_KEY_PATH}:/etc/nginx/ssl/key.key:ro" \
  -v "${HOST_MEDIA_PATH}:/usr/share/nginx/html/awroberts-media:ro" \
  "${IMAGE_NAME}"