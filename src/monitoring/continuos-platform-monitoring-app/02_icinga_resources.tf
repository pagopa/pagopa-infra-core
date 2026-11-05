# il provider icinga2 non supporta l'update di host e servizi: ogni modifica
# alla configurazione ne forza la ricreazione
resource "terraform_data" "azure_hosts_config" {
  for_each = local.hosts_flat
  input    = each.value
}

resource "icinga2_host" "hosts" {

  for_each      = local.hosts_flat
  hostname      = each.value.hostname
  address       = each.value.address
  check_command = each.value.check_command
  zone          = "master"
  vars          = each.value.vars

  lifecycle {
    replace_triggered_by = [terraform_data.azure_hosts_config[each.key]]
  }
}

# il provider icinga2 non supporta l'update di host e servizi: ogni modifica
# alla configurazione ne forza la ricreazione
resource "terraform_data" "azure_services_config" {
  for_each = local.services_flat
  input = {
    service = each.value
    host    = local.hosts_flat[each.value.host_key]
  }
}

resource "icinga2_service" "services" {
  for_each      = local.services_flat
  hostname      = icinga2_host.hosts[each.value.host_key].hostname
  name          = each.value.name
  check_command = each.value.check_command
  vars          = each.value.vars

  lifecycle {
    replace_triggered_by = [terraform_data.azure_services_config[each.key]]
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