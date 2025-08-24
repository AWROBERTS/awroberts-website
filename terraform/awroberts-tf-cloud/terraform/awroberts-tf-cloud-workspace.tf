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