data "azurerm_key_vault" "core" {
  name                = local.core_key_vault_name
  resource_group_name = local.core_key_vault_resource_group_name
}

data "azurerm_key_vault_secret" "metabase_usr" {
  name         = "metabase-reader-login"
  key_vault_id = data.azurerm_key_vault.core.id
}

data "azurerm_key_vault_secret" "metabase_psw" {
  name         = "metabase-reader-password"
  key_vault_id = data.azurerm_key_vault.core.id
}