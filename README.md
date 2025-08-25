# awroberts-website
Code for awroberts.co.uk

Deployed using Terraform and Kubernetes on Linux Mint.

Terraform deploys Github Pipeline and Secrets, and TF Cloud Workspace and Variables used in Kubernetes Deployment.
Kubernetes manifest for deploying website using NGINX, with Dockerfile deployment of p5.js based site.
Shell Script for deploying Kubernetes manifest using kubeadm.
