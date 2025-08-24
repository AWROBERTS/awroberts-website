module "awroberts_github" {
  source = "./awroberts-github/terraform"

  awroberts_github_token               = var.awroberts_github_token
  awroberts_tf_cloud_terraform_version = var.awroberts_tf_cloud_terraform_version
  awroberts_tfe_token                  = var.awroberts_tfe_token
  awroberts_github_repository          = var.awroberts_github_repository

  awroberts_tf_cloud_workspace_id      = module.awroberts_tf_cloud.awroberts_tf_cloud_workspace_id
}

module "awroberts_tf_cloud" {
  source = "./awroberts-tf-cloud/terraform"

  awroberts_tfe_token                      = var.awroberts_tfe_token
  awroberts_tf_cloud_terraform_version     = var.awroberts_tf_cloud_terraform_version
}