module "client_certificate" {
  source              = "./.terraform/modules/__v4__/keyvault_client_certificates"
  root_key_vault_id   = data.azurerm_key_vault.kv_ca.id
  root_key_vault_name = data.azurerm_key_vault.kv_ca.name

  certificates = merge(
    var.enabled_forwarder_certificates ? {
      replace(local.forwarder_fqdn, ".", "-") = {
        key_vault_name             = data.azurerm_key_vault.kv_nodo.name
        subject                    = "CN=${local.forwarder_fqdn}",
        renewal_days_before_expiry = 60,
        validity_in_months         = 12
        key_vault_id               = data.azurerm_key_vault.kv_nodo.id
        san_dns_names = [
          local.forwarder_fqdn,
          "www.${local.forwarder_fqdn}"
        ]
      }
    } : {}
  )
  tags = module.tag_config.tags
}