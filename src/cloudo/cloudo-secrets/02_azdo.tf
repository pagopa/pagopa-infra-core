#
# Policy
#

data "azurerm_user_assigned_identity" "iac_federated_azdo" {
  for_each            = local.azdo_iac_managed_identities
  name                = each.key
  resource_group_name = local.azdo_managed_identity_rg_name
}

module "azdevops_iac_managed_identities_access_policy" {
  source = "./.terraform/modules/__v4__/IDH/key_vault_access_policy"
  for_each = local.azdo_iac_managed_identities

  product_name         = var.prefix
  idh_resource_tier    = "devops"
  env                  = var.env
  key_vault_id         = module.key_vault.id
  tenant_id            = data.azurerm_client_config.current.tenant_id
  object_id            = data.azurerm_user_assigned_identity.iac_federated_azdo[each.key].principal_id
}
