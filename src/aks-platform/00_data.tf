data "azurerm_key_vault" "kv" {
  name                = "${local.product}-kv"
  resource_group_name = "${local.product}-sec-rg"
}

data "kubernetes_all_namespaces" "all_ns" {}
