#!/usr/bin/env bash
set -euo pipefail

saddleworth_nginx(){

  kubectl create namespace awroberts --dry-run=client -o yaml | kubectl apply -f -

  echo "Applying ingress-nginx customizations"
  kubectl apply -k "${PROJECT_ROOT}/k8s/saddleworth-nginx-customize"

  echo "Applying Saddleworth Machine Opportunity forwarding"
  kubectl apply -f "${PROJECT_ROOT}/k8s/saddleworth-nginx-customize/saddleworth-forwarding/saddleworth-machine-opportunity.yaml"
}