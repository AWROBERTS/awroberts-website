resource "tfe_project" "awroberts" {
  name         = "awroberts_co_uk"
  organization = "awroberts_co_uk"
}

output "awroberts_tf_cloud_project_id" {
  value = tfe_project.awroberts.id
  description = "AWROBERTS TF Cloud Project ID"
}