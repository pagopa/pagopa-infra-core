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

data "azurerm_key_vault" "kv_domain" {
  name                = local.kv_domain_name
  resource_group_name = local.kv_domain_rg
}

data "azurerm_key_vault_secret" "icinga_vm_private_ip" {
  name         = "icinga-vm-private-ip"
  key_vault_id = data.azurerm_key_vault.kv_domain.id
}

data "azurerm_key_vault_secret" "icinga_web_admin_password" {
  name         = "icinga-web-admin-password"
  key_vault_id = data.azurerm_key_vault.kv_domain.id
}