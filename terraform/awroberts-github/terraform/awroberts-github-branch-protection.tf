data "github_repository" "awroberts" {
  full_name = var.awroberts_github_repository
}

resource "github_branch_protection" "awroberts_main" {
  repository_id = data.github_repository.awroberts.node_id
  pattern       = "main"

  required_status_checks {
    strict = true
  }

  enforce_admins = true
}