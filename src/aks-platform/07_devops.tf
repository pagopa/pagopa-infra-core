module "devops_service_account" {
  source    = "./.terraform/modules/__v4__/kubernetes_service_account"
  name      = local.devops_admin_sa_name
  namespace = local.system_namespace
}


resource "azurerm_key_vault_secret" "aks_apiserver_url" {
  name         = "${local.aks_name}-apiserver-url"
  value        = "https://${local.aks_api_url}:443"
  content_type = "text/plain"

  key_vault_id = data.azurerm_key_vault.kv.id
}

#tfsec:ignore:AZU023
resource "azurerm_key_vault_secret" "azure_devops_sa_token" {
  name         = "${local.aks_name}-azure-devops-sa-token"
  value        = module.devops_service_account.sa_token # base64 value
  content_type = "text/plain"

  key_vault_id = data.azurerm_key_vault.kv.id
}

#tfsec:ignore:AZU023
resource "azurerm_key_vault_secret" "azure_devops_sa_cacrt" {
  name         = "${local.aks_name}-azure-devops-sa-cacrt"
  value        = module.devops_service_account.sa_ca_cert # base64 value
  content_type = "text/plain"

  key_vault_id = data.azurerm_key_vault.kv.id
}

resource "kubernetes_cluster_role_binding" "azdo_admin_cluster_binding" {

  depends_on = [module.devops_service_account]
  metadata {
    name = "azdo-admin-binding-cluster"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.azdo_cluster_admin.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.devops_admin_sa_name
    namespace = local.system_namespace
  }
}
