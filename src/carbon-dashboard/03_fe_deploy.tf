locals {
  fe_path = "${path.module}/cdn_assets"

  fe_files = sort(setunion(
    fileset(local.fe_path, "src/**"),
    fileset(local.fe_path, "public/**"),
    ["index.html", "package.json", "package-lock.json", "tsconfig.json", "vite.config.ts"],
  ))
  fe_hash = sha256(join("", [for f in local.fe_files : filesha256("${local.fe_path}/${f}")]))
}

resource "terraform_data" "carbon_fe_deploy" {
  triggers_replace = [
    local.fe_hash,
    module.carbon_cdn.storage_account_name,
  ]

  # The purge needs the route and origin in place, not just the endpoint.
  depends_on = [module.carbon_cdn]

  provisioner "local-exec" {
    working_dir = local.fe_path
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      npm ci
      npm run build

      # data/ is owned by the external job after the first deploy: seed it only once,
      # so a frontend release never rolls the published data back to the repo copy.
      seeded=$(az storage blob exists \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name '$web' \
        --name data/index.json \
        --auth-mode key \
        --query exists -o tsv)
      if [ "$seeded" != "true" ]; then
        az storage blob upload-batch \
          --account-name "$STORAGE_ACCOUNT" \
          --destination '$web' \
          --destination-path data \
          --source dist/data \
          --auth-mode key \
          --only-show-errors
      fi
      rm -rf dist/data

      az storage blob upload-batch \
        --account-name "$STORAGE_ACCOUNT" \
        --destination '$web' \
        --source dist \
        --overwrite \
        --auth-mode key \
        --only-show-errors
      az afd endpoint purge \
        --resource-group "$RESOURCE_GROUP" \
        --profile-name "$PROFILE_NAME" \
        --endpoint-name "$ENDPOINT_NAME" \
        --content-paths '/*' \
        --only-show-errors
    EOT
    environment = {
      STORAGE_ACCOUNT = module.carbon_cdn.storage_account_name
      RESOURCE_GROUP  = azurerm_resource_group.carbon.name
      PROFILE_NAME    = module.carbon_cdn.profile_name
      ENDPOINT_NAME   = reverse(split("/", module.carbon_cdn.endpoint_ids["web"]))[0]
    }
  }
}
