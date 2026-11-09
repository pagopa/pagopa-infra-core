# -----------------------------------------------------------------------------
# Entra ID application for the Icinga Web login (sso module, OIDC)
# client id and secret in domain_kv, together with the other Icinga secrets, and
# passed to icinga-configure.sh (sso/providers.ini) by the run command (03_vm.tf)
# -----------------------------------------------------------------------------
module "icinga_app" {
  source = "./.terraform/modules/__v4__/entra_oidc_application"

  display_name                 = "${local.project}-icinga"
  ad_user_owners               = local.application_owners
  authorized_group_names       = [] #local.entra_groups_allowed
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
