module "icinga_app" {
  source = "./.terraform/modules/__v4__/keycloak_entra"

  prefix                 = local.prefix
  env                    = var.env
  ad_user_owners         = local.application_owners
  authorized_group_names = [] #local.entra_groups_allowed

  redirect_uris = [
    "http://api.dev.platform.pagopa.it/icingaweb2/sso/oidc/redirection-endpoint"
  ]
  logout_url = "http://api.dev.platform.pagopa.it/icingaweb2/sso/logout"
}

resource "azurerm_key_vault_secret" "keycloak_client_id" {
  name         = "icinga-azure-app-client-id"
  value        = module.icinga_app.azure_client_id
  key_vault_id = data.azurerm_key_vault.core.id

  tags = module.tag_config.tags
}


resource "azurerm_key_vault_secret" "keycloak_client_secret" {
  name         = "icinga-azure-app-secret-value"
  value        = module.icinga_app.azure_client_secret
  key_vault_id = data.azurerm_key_vault.core.id

  tags = module.tag_config.tags
}
