terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "awroberts_co_uk"

    workspaces {
      name = "awroberts_co_uk"
    }
  }
}