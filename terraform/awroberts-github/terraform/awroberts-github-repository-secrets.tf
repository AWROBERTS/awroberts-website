resource "github_actions_secret" "awroberts_secrets_github_repository" {
  repository      = var.awroberts_github_repository
  secret_name     = "awroberts_GITHUB_REPOSITORY"
  plaintext_value = var.awroberts_github_repository
}

resource "github_actions_secret" "awroberts_secrets_tfe_workspace_id" {
  repository      = var.awroberts_github_repository
  secret_name     = "TF_CLOUD_WORKSPACE_ID"
  plaintext_value = var.awroberts_tf_cloud_workspace_id
}

# TO-DO: Update Variable to be encrypted to Github Specs
resource "github_actions_secret" "awroberts_secrets_github_token" {
  repository      = var.awroberts_github_repository
  secret_name     = "AWROBERTS_GITHUB_TOKEN"
  plaintext_value = var.awroberts_github_token
}

resource "github_actions_secret" "awroberts_secrets_tf_cloud_terraform_version" {
  repository      = var.awroberts_github_repository
  secret_name     = "TF_CLOUD_TERRAFORM_VERSION"
  plaintext_value = var.awroberts_tf_cloud_terraform_version
}

# TO-DO: Update Variable to be encrypted to Github Specs
resource "github_actions_secret" "awroberts_secrets_tfe_token" {
  repository      = var.awroberts_github_repository
  secret_name      = "TFE_TOKEN"
  plaintext_value  = var.awroberts_tfe_token
}