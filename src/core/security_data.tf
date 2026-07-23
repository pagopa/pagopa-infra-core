data "azurerm_key_vault" "key_vault" {
  name                = format("%s-kv", local.project)
  resource_group_name = format("%s-sec-rg", local.project)
}
