terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.6.0"
    }
  }
}

provider "github" {
  token = var.awroberts_github_token
  owner = "AWROBERTS"
}