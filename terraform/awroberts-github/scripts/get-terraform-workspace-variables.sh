#!/bin/sh

# Fetch workspace variables from Terraform Cloud
curl -fSL -H "Authorization: Bearer ${TFE_TOKEN}" \
    https://app.terraform.io/api/v2/workspaces/${TF_CLOUD_WORKSPACE_ID}/vars -o workspace_vars.json

# Temporary file to hold variables
TFVARS_FILE="terraform.auto.tfvars"

# Clear existing content
> "$TFVARS_FILE"

# Function to escape string values properly
escape_value() {
  local VALUE="$1"
  printf '%s' "$VALUE" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g'
}

# Function to convert JSON list to Terraform-compatible list
decode_json_list() {
  local VALUE="$1"
  echo "$VALUE" | jq -r '. | map("\"" + . + "\"") | join(", ")' | awk '{print "["$0"]"}'
}

# Parse JSON and generate terraform.auto.tfvars
jq -c '.data[]' workspace_vars.json | while IFS= read -r item; do
  KEY=$(echo "$item" | jq -r '.attributes.key')
  VALUE=$(echo "$item" | jq -r '.attributes.value')
  IS_HCL=$(echo "$item" | jq -r '.attributes.hcl')

  if [ -z "$KEY" ] || [ -z "$VALUE" ]; then
    continue
  fi

  if [ "$KEY" = "awroberts_github_organization_repos" ]; then
    DECODED_VALUE=$(decode_json_list "$VALUE")
    echo "$KEY = $DECODED_VALUE" >> "$TFVARS_FILE"
  elif [ "$IS_HCL" = "true" ]; then
    echo "$KEY = $VALUE" >> "$TFVARS_FILE"
  else
    ESCAPED_VALUE=$(escape_value "$VALUE")
    echo "$KEY = \"$ESCAPED_VALUE\"" >> "$TFVARS_FILE"
  fi
done