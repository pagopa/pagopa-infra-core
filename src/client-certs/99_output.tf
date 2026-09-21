output "forwarder_certificate_chain_pem" {
  value = try(module.client_certificate.certificate_chain_pem[replace(local.forwarder_fqdn, ".", "-")], null)
}