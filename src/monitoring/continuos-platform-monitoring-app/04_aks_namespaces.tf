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

# vedi azure_services_config
resource "terraform_data" "aks_namespace_services_config" {
  for_each = local.aks_namespace_services
  input = {
    service = each.value
    host    = local.hosts_flat[each.value.host_key]
  }
}

resource "icinga2_service" "aks_namespaces" {
  for_each      = local.aks_namespace_services
  hostname      = icinga2_host.hosts[each.value.host_key].hostname
  name          = each.value.name
  check_command = each.value.check_command
  vars          = each.value.vars

  lifecycle {
    replace_triggered_by = [terraform_data.aks_namespace_services_config[each.key]]
  }
}
