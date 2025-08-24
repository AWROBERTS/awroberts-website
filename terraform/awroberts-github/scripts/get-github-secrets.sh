#!/bin/sh

cat <<EOF > github-terraform.auto.tfvars
awroberts_github_repository = "${AWROBERTS_GITHUB_REPOSITORY}"
awroberts_github_token = "${AWROBERTS_GITHUB_TOKEN}"
awroberts_tf_cloud_terraform_version = "${TF_CLOUD_TERRAFORM_VERSION}"
awroberts_tfe_token = "${TFE_TOKEN}"
EOF