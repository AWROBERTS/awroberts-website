terraform {
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "0.68.2"
    }
  }
}

provider "tfe" {
  hostname = "app.terraform.io"
  token    = var.awroberts_tfe_token
}