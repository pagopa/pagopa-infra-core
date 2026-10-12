output "forwarder_certificate_chain_pem" {
  value = try(module.client_certificate.certificate_chain_pem[replace(local.forwarder_fqdn, ".", "-")], null)
}

output "client_certificates_key_vaults" {
  value = { for name, cert in local.client_certificates : name => cert.key_vault_name }
}
