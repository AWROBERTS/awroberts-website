# awroberts-website

![p5.js](https://img.shields.io/badge/p5.js-ED225D?logo=p5.js&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![NGINX](https://img.shields.io/badge/NGINX-009639?logo=nginx&logoColor=white)
![Traefik](https://img.shields.io/badge/Traefik-24A1C1?logo=traefikproxy&logoColor=white)

Source code for [awroberts.co.uk](https://awroberts.co.uk).

Currently deployed on a Linux Mint Mini PC in Saddleworth, England.

This repository contains the website frontend, deployment assets, and infrastructure scripts used to build and deploy the site with Docker, Kubernetes, Terraform, and Traefik.

## Overview

- **Frontend**: p5.js-based interactive homepage with background video, poster fallback, social links, and deployment info overlay
- **Containerization**: NGINX-based Docker image for serving the site
- **Kubernetes**: Helm chart and manifests for deploying the website and related services
- **Infrastructure**: Terraform for supporting GitHub and cloud deployment resources
- **Automation**: Shell scripts for cluster setup, image management, deployment, and maintenance

## Repository layout

- `docker/awroberts/` — site files, Dockerfile, NGINX config, assets, and sketch
- `k8s/awroberts-web/` — Helm chart and Kubernetes manifests
- `scripts/functions/` — deployment, bootstrap, and maintenance scripts
- `terraform/` — Terraform configuration
- `traefik/` — Traefik configuration and values
- `deploy-kubernetes.sh` — top-level deployment entrypoint

## Deployment

The site is deployed using:
- Docker for image packaging
- Kubernetes for running the application
- Traefik for ingress/routing
- Terraform for provisioning supporting infrastructure

## Notes

- The website uses a p5.js sketch for rendering the interface.
- Background video is handled with HLS, with a poster image fallback.
- Deployment metadata is injected into the site for visibility during runtime.
