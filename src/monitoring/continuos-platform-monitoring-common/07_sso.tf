# -----------------------------------------------------------------------------
# Entra ID application for the Icinga Web login (sso module, OIDC)
# client id and secret in domain_kv, together with the other Icinga secrets, and
# passed to icinga-configure.sh (sso/providers.ini) by terraform_data.icinga_configure (05_vm.tf)
# -----------------------------------------------------------------------------
# Entra ID groups of the Icinga Web roles (local.icinga_roles)
data "azuread_group" "icinga_roles" {
  for_each     = toset(flatten(values(local.icinga_roles)))
  display_name = each.value
}

locals {
  # "<role>=<object id>,...;..." for icinga-configure.sh (roles.ini): the groups
  # claim of the token holds the object ids of the groups
  icinga_role_groups = join(";", [
    for role, groups in local.icinga_roles :
    "${role}=${join(",", [for g in groups : data.azuread_group.icinga_roles[g].object_id])}"
  ])
}

module "icinga_app" {
  source = "./.terraform/modules/__v4__/entra_oidc_application"

  display_name                 = "${local.project}-icinga"
  ad_user_owners               = local.application_owners
  authorized_group_names       = distinct(flatten(values(local.icinga_roles)))
  app_role_assignment_required = true

  redirect_uris = [
    "https://${local.icinga_fqdn}/icingaweb2/sso/oidc/redirection-endpoint"
  ]
  logout_url = "https://${local.icinga_fqdn}/icingaweb2/sso/logout"
}

resource "azurerm_key_vault_secret" "icinga_app_client_id" {
  name         = "icinga-azure-app-client-id"
  value        = module.icinga_app.azure_client_id
  key_vault_id = data.azurerm_key_vault.domain_kv.id

  tags = module.tag_config.tags
}

resource "azurerm_key_vault_secret" "icinga_app_client_secret" {
  name         = "icinga-azure-app-secret-value"
  value        = module.icinga_app.azure_client_secret
  key_vault_id = data.azurerm_key_vault.domain_kv.id

  tags = module.tag_config.tags
}
