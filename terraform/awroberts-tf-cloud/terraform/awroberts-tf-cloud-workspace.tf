resource "tfe_workspace" "awroberts" {
  name              = "awroberts_co_uk"
  organization      = "awroberts_co_uk"
  project_id        = tfe_project.awroberts.id
  terraform_version = var.awroberts_tf_cloud_terraform_version
}

output "awroberts_tf_cloud_workspace_id" {
  value = tfe_workspace.awroberts.id
  description = "Mahogany Teeth TF Cloud Workspace ID"
}

resource "tfe_variable" "awroberts_kubeconfig_path" {
  key          = "awroberts_kubeconfig_path"
  value        = jsonencode(var.awroberts_kubeconfig_path)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_kube_context" {
  key          = "awroberts_kube_context"
  value        = jsonencode(var.awroberts_kube_context)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_namespace" {
  key          = "awroberts_namespace"
  value        = jsonencode(var.awroberts_namespace)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_secret_name" {
  key          = "awroberts_secret_name"
  value        = jsonencode(var.awroberts_secret_name)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_deployment_name" {
  key          = "awroberts_deployment_name"
  value        = jsonencode(var.awroberts_deployment_name)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_container_name_in_deploy" {
  key          = "awroberts_container_name_in_deploy"
  value        = jsonencode(var.awroberts_container_name_in_deploy)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_manifest_dir" {
  key          = "awroberts_manifest_dir"
  value        = jsonencode(var.awroberts_manifest_dir)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_ingress_name" {
  key          = "awroberts_ingress_name"
  value        = jsonencode(var.awroberts_ingress_name)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_service_name" {
  key          = "awroberts_service_name"
  value        = jsonencode(var.awroberts_service_name)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_host_a" {
  key          = "awroberts_host_a"
  value        = jsonencode(var.awroberts_host_a)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_host_b" {
  key          = "awroberts_host_b"
  value        = jsonencode(var.awroberts_host_b)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_host_cert_path" {
  key          = "awroberts_host_cert_path"
  value        = jsonencode(var.awroberts_host_cert_path)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_host_key_path" {
  key          = "awroberts_host_key_path"
  value        = jsonencode(var.awroberts_host_key_path)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_http_port" {
  key          = "awroberts_http_port"
  value        = jsonencode(var.awroberts_http_port)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_https_port" {
  key          = "awroberts_https_port"
  value        = jsonencode(var.awroberts_https_port)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_host_media_path" {
  key          = "awroberts_host_media_path"
  value        = jsonencode(var.awroberts_host_media_path)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_container_name" {
  key          = "awroberts_container_name"
  value        = jsonencode(var.awroberts_container_name)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_image_name" {
  key          = "awroberts_image_name"
  value        = jsonencode(var.awroberts_image_name)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_use_timestamp" {
  key          = "awroberts_use_timestamp"
  value        = jsonencode(var.awroberts_use_timestamp)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_retention_days" {
  key          = "awroberts_retention_days"
  value        = jsonencode(var.awroberts_retention_days)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_image_tag" {
  key          = "awroberts_image_tag"
  value        = jsonencode(var.awroberts_image_tag)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_build_context" {
  key          = "awroberts_build_context"
  value        = jsonencode(var.awroberts_build_context)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_platform" {
  key          = "awroberts_platform"
  value        = jsonencode(var.awroberts_platform)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_builder_name" {
  key          = "awroberts_builder_name"
  value        = jsonencode(var.awroberts_builder_name)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_cluster_bootstrap" {
  key          = "awroberts_cluster_bootstrap"
  value        = jsonencode(var.awroberts_cluster_bootstrap)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_pod_cidr" {
  key          = "awroberts_pod_cidr"
  value        = jsonencode(var.awroberts_pod_cidr)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_ingress_hostnetwork" {
  key          = "awroberts_ingress_hostnetwork"
  value        = jsonencode(var.awroberts_ingress_hostnetwork)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_http_nodeport" {
  key          = "awroberts_http_nodeport"
  value        = jsonencode(var.awroberts_http_nodeport)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}

resource "tfe_variable" "awroberts_https_nodeport" {
  key          = "awroberts_https_nodeport"
  value        = jsonencode(var.awroberts_https_nodeport)
  category     = "terraform"
  workspace_id = tfe_workspace.awroberts.id
  hcl          = true
}