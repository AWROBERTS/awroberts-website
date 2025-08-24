module "awroberts_github" {
  source = "./awroberts-github/terraform"

  awroberts_github_token               = var.awroberts_github_token
  awroberts_tf_cloud_terraform_version = var.awroberts_tf_cloud_terraform_version
  awroberts_tfe_token                  = var.awroberts_tfe_token
  awroberts_github_repository          = var.awroberts_github_repository

  awroberts_tf_cloud_workspace_id = module.awroberts_tf_cloud.awroberts_tf_cloud_workspace_id
}

module "awroberts_tf_cloud" {
  source = "./awroberts-tf-cloud/terraform"

  awroberts_tfe_token                  = var.awroberts_tfe_token
  awroberts_tf_cloud_terraform_version = var.awroberts_tf_cloud_terraform_version

  awroberts_kubeconfig_path          = var.awroberts_kubeconfig_path
  awroberts_kube_context             = var.awroberts_kube_context
  awroberts_namespace                = var.awroberts_namespace
  awroberts_secret_name              = var.awroberts_secret_name
  awroberts_deployment_name          = var.awroberts_deployment_name
  awroberts_container_name_in_deploy = var.awroberts_container_name_in_deploy
  awroberts_manifest_dir             = var.awroberts_manifest_dir
  awroberts_ingress_name             = var.awroberts_ingress_name
  awroberts_service_name             = var.awroberts_service_name
  awroberts_host_a                   = var.awroberts_host_a
  awroberts_host_b                   = var.awroberts_host_b
  awroberts_host_cert_path           = var.awroberts_host_cert_path
  awroberts_host_key_path            = var.awroberts_host_key_path
  awroberts_http_port                = var.awroberts_http_port
  awroberts_https_port               = var.awroberts_https_port
  awroberts_host_media_path          = var.awroberts_host_media_path
  awroberts_container_name           = var.awroberts_container_name
  awroberts_image_name               = var.awroberts_image_name
  awroberts_use_timestamp            = var.awroberts_use_timestamp
  awroberts_retention_days           = var.awroberts_retention_days
  awroberts_image_tag                = var.awroberts_image_tag
  awroberts_build_context            = var.awroberts_build_context
  awroberts_platform                 = var.awroberts_platform
  awroberts_builder_name             = var.awroberts_builder_name
  awroberts_cluster_bootstrap        = var.awroberts_cluster_bootstrap
  awroberts_pod_cidr                 = var.awroberts_pod_cidr
  awroberts_ingress_hostnetwork      = var.awroberts_ingress_hostnetwork
  awroberts_http_nodeport            = var.awroberts_http_nodeport
  awroberts_https_nodeport           = var.awroberts_https_nodeport
}