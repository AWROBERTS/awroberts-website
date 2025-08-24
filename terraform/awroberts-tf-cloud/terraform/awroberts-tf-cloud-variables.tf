variable "awroberts_tfe_token" {
  type      = string
  sensitive = true
}

variable "awroberts_tf_cloud_terraform_version" {
  type      = string
}

variable "awroberts_kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig file on the runner/host"
}

variable "awroberts_kube_context" {
  type        = string
  nullable    = true
  description = "Optional Kubernetes context name to use"
}

variable "awroberts_namespace" {
  type        = string
  description = "Kubernetes namespace for the app"
}

variable "awroberts_secret_name" {
  type        = string
  description = "Kubernetes Secret name (e.g., TLS secret)"
}

variable "awroberts_deployment_name" {
  type        = string
  description = "Kubernetes Deployment name"
}

variable "awroberts_container_name_in_deploy" {
  type        = string
  nullable    = true
  description = "Optional container name within the Deployment (if multiple containers)"
}

variable "awroberts_manifest_dir" {
  type        = string
  description = "Directory containing Kubernetes manifests"
}

variable "awroberts_ingress_name" {
  type        = string
  description = "Kubernetes Ingress name"
}

variable "awroberts_service_name" {
  type        = string
  description = "Kubernetes Service name"
}

variable "awroberts_host_a" {
  type        = string
  description = "Primary host/domain"
}

variable "awroberts_host_b" {
  type        = string
  description = "Secondary host/domain (e.g., www)"
}

variable "awroberts_host_cert_path" {
  type        = string
  description = "Path to the public certificate/full chain"
}

variable "awroberts_host_key_path" {
  type        = string
  description = "Path to the TLS private key (contents are secret; path is not)"
}

variable "awroberts_http_port" {
  type        = number
  description = "HTTP service port"
}

variable "awroberts_https_port" {
  type        = number
  description = "HTTPS service port"
}

variable "awroberts_host_media_path" {
  type        = string
  description = "Path to media/static content on host"
}

variable "awroberts_container_name" {
  type        = string
  description = "Local image/container base name"
}

variable "awroberts_image_name" {
  type        = string
  description = "Full image name including tag reference used as base"
}

variable "awroberts_use_timestamp" {
  type        = bool
  description = "Whether to include a timestamp in image tagging"
}

variable "awroberts_retention_days" {
  type        = number
  description = "Retention period for images/logs/etc."
}

variable "awroberts_image_tag" {
  type        = string
  nullable    = true
  description = "Optional explicit image tag (leave null/empty to auto-generate)"
}

variable "awroberts_build_context" {
  type        = string
  description = "Docker build context path"
}

variable "awroberts_platform" {
  type        = string
  description = "Target platform for builds"
}

variable "awroberts_builder_name" {
  type        = string
  description = "Docker buildx builder name"
}

variable "awroberts_cluster_bootstrap" {
  type        = bool
  description = "Whether to bootstrap a single-node cluster"
}

variable "awroberts_pod_cidr" {
  type        = string
  description = "Pod network CIDR for the CNI"
}

variable "awroberts_ingress_hostnetwork" {
  type        = bool
  description = "Whether the ingress controller uses hostNetwork"
}

variable "awroberts_http_nodeport" {
  type        = number
  nullable    = true
  description = "Optional NodePort for HTTP (null/empty for dynamic)"
}

variable "awroberts_https_nodeport" {
  type        = number
  nullable    = true
  description = "Optional NodePort for HTTPS (null/empty for dynamic)"
}