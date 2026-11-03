output "token_secret_name" {
  value = azurerm_key_vault_secret.aks_icinga_token.name
}

output "aks_name" {
  value = var.aks_name
}

output "kubeconfig" {
  value     = local.kubeconfig
  sensitive = true
}

# per rilanciare la configurazione della VM quando cambiano token, CA o server
output "kubeconfig_hash" {
  value = nonsensitive(sha256(local.kubeconfig))
}
