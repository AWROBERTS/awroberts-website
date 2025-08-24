#!/bin/sh

GITHUB_REPOSITORY_WITH_REMOVED_ORGANIZATION_PREFIX=$(echo "${AWROBERTS_GITHUB_REPOSITORY}" | cut -d'/' -f2)

cat <<EOF > github-terraform.auto.tfvars
awroberts_github_repository = "${GITHUB_REPOSITORY_WITH_REMOVED_ORGANIZATION_PREFIX}"
awroberts_github_token = "${AWROBERTS_GITHUB_TOKEN}"
awroberts_tf_cloud_terraform_version = "${TF_CLOUD_TERRAFORM_VERSION}"
awroberts_tfe_token = "${TFE_TOKEN}"
EOF