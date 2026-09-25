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
        san_dns_names = [
          local.forwarder_fqdn,
          "www.${local.forwarder_fqdn}"
        ]
      }
    } : {},
    {
      abc = {
        key_vault_name            = data.azurerm_key_vault.kv_nodo.name
        subject                   = "CN=abc.pagopa.it",
        rotation_minutes_override = 20
        validity_in_months        = 1
        san_dns_names = [
          "abc.pagopa.it"
        ]
      }
    }
  )
  stable_promotion_ids = var.stable_promotion_ids

  tags = module.tag_config.tags
}