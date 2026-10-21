data "azurerm_resources" "sub_resources" {
  for_each = local.namespace_commands_map
  type     = each.key
#   required_tags = {
#     icinga2 = "true"
#   }
}



data "azapi_resource_action" "provider" {
  for_each               = toset([for k in keys(local.namespace_commands_map) : split("/", k)[0]])
  type                   = "Microsoft.Resources/providers@2021-04-01"
  resource_id            = "${data.azurerm_subscription.current.id}/providers/${each.key}"
  method                 = "GET"
  response_export_values = ["resourceTypes"]
}

locals {
  # es. "Microsoft.Network/virtualNetworks" => ["2024-05-01", "2024-03-01", ...]
  api_versions = {
    for k, r in data.azurerm_resources.sub_resources : k => flatten([
      for rt in data.azapi_resource_action.provider[split("/", r.type)[0]].output.resourceTypes :
      rt.apiVersions
      if lower(rt.resourceType) == lower(trimprefix(r.type, "${split("/", r.type)[0]}/"))
    ])
  }

  # ultima versione stabile (esclude le preview)
  latest_stable = {
    for k, v in local.api_versions : k => reverse(sort([for x in v : x if !strcontains(x, "preview")]))[0]
  }

  resource_names_flat = merge([
    for k, v in data.azurerm_resources.sub_resources : {
      for r in v.resources : "${k}-${r.name}" => {
        name = r.name
        type = r.type
        id   = r.id
        domain = try(r.tags.domain,"notag")
      }
    }
  ]...)

  resources_full = {
    for k, v in local.resource_names_flat : k => merge(v, {
      icinga2_command = local.namespace_commands_map[v.type].icinga2_command
      property_value  = data.azapi_resource.this[k].output.value
    })
  }

  bp_resources = {
    for k, v in local.resources_full :
    replace(k, "/[^A-Za-z0-9_.-]/", "_") => {
      host   = v.property_value
      domain = replace(v.domain, "/[^A-Za-z0-9_.-]/", "_")
    } if v.property_value != null
  }

  # dominio => lista dei nodi
  bp_domains = {
    for node, r in local.bp_resources : r.domain => node...
  }

  bp_content = templatefile("${path.module}/bp.tftpl", {
    resources = local.bp_resources
    domains   = local.bp_domains
  })
}

data "azapi_resource" "this" {
  for_each  = local.resource_names_flat
  type      = "${each.value.type}@${local.latest_stable[each.value.type]}"
  
  resource_id = each.value.id
  response_export_values = {
    value = "${local.namespace_commands_map[each.value.type].resource_properties}"
  }
}


 output "bp" {
      value = local.bp_content
  
 }


resource "icinga2_host" "web-server" {
 for_each = data.azapi_resource.this
 address =  each.value.output.value
 hostname = each.value.output.value
 check_command = "ping4"
 zone = "master"
}

resource "icinga2_hostgroup" "my-hostgroup" {
  name         = "terraform-hostgroup-1"
  display_name = "Terraform Test HostGroup"
}