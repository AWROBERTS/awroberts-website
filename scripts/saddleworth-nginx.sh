#!/usr/bin/env bash
set -euo pipefail

saddleworth_nginx(){
  echo "Applying ingress-nginx customizations"
  kubectl apply -k "${PROJECT_ROOT}/saddleworth-nginx-customize"

  echo "Applying Saddleworth Machine Opportunity forwarding"
  kubectl apply -f "${PROJECT_ROOT}/saddleworth-forwarding/saddleworth-machine-opportunity.yaml"
}