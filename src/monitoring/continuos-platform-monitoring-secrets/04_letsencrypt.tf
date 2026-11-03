module "letsencrypt" {
  source = "./.terraform/modules/__v4__/letsencrypt_credential"

  prefix            = local.prefix
  env               = var.env_short
  key_vault_name    = module.key_vault.name
  subscription_name = data.azurerm_subscription.current.display_name
}