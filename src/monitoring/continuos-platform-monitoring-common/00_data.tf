# -----------------------------------------------------------------------------
# Icinga VM
# -----------------------------------------------------------------------------
data "azurerm_key_vault" "domain_kv" {
  name                = "${local.product}-${var.location_short}-monitor-kv"
  resource_group_name = "${local.product}-${var.location_short}-monitor-sec-rg"
}

data "azurerm_key_vault_secret" "icinga_vm_admin_password" {
  name         = "icinga-vm-admin-password"
  key_vault_id = data.azurerm_key_vault.domain_kv.id
}

data "azurerm_key_vault_secret" "icingadb_db_password" {
  name         = "icinga-db-password"
  key_vault_id = data.azurerm_key_vault.domain_kv.id
}

data "azurerm_key_vault_secret" "icingaweb_db_password" {
  name         = "icinga-web-db-password"
  key_vault_id = data.azurerm_key_vault.domain_kv.id
}

data "azurerm_key_vault_secret" "icingaweb_admin_password" {
  name         = "icinga-web-admin-password"
  key_vault_id = data.azurerm_key_vault.domain_kv.id
}
