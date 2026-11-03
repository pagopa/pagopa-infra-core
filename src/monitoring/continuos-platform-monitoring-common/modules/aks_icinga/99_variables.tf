variable "aks_name" {
  type = string
}

variable "aks_resource_group_name" {
  type = string
}

variable "key_vault_id" {
  type        = string
  description = "Key Vault in cui salvare il token del ServiceAccount"
}

variable "tags" {
  type = map(string)
}
