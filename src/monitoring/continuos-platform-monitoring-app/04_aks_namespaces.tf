data "kubernetes_resources" "namespaces_itn" {
  provider = kubernetes.itn

  api_version = "v1"
  kind        = "Namespace"
}

data "kubernetes_resources" "namespaces_weu" {
  provider = kubernetes.weu

  api_version = "v1"
  kind        = "Namespace"
}

resource "terraform_data" "aks_namespace_services_config" {
  for_each = local.aks_namespace_services
  input = {
    service = each.value
    host    = local.hosts_flat[each.value.host_key]
  }
}
