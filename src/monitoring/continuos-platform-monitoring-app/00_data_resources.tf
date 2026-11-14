# per i tipi con parent_type elenca i padri, altrimenti direttamente le risorse
data "azurerm_resources" "sub_resources" {
  for_each = local.namespace_commands_map
  type     = try(each.value.parent_type, each.key)
}

# risorse figlie lette dal padre (non compaiono in azurerm_resources)
data "azapi_resource_list" "children" {
  for_each               = local.parent_resources
  type                   = "${each.value.type}@${local.latest_stable[each.value.type]}"
  parent_id              = each.value.parent_id
  response_export_values = ["value"]
}

# endpoint e route dei profili Front Door, per associare i custom domain all'endpoint
data "azapi_resource_list" "afd_endpoints" {
  for_each               = local.afd_profiles
  type                   = "Microsoft.Cdn/profiles/afdEndpoints@${local.latest_stable[each.value.type]}"
  parent_id              = each.value.parent_id
  response_export_values = ["value"]
}

data "azapi_resource_list" "afd_routes" {
  for_each               = local.afd_endpoints
  type                   = "Microsoft.Cdn/profiles/afdEndpoints/routes@${local.latest_stable["Microsoft.Cdn/profiles/customdomains"]}"
  parent_id              = each.key
  response_export_values = ["value"]
}

data "azapi_resource_action" "provider" {
  for_each               = toset([for k in keys(local.namespace_commands_map) : split("/", k)[0]])
  type                   = "Microsoft.Resources/providers@2021-04-01"
  resource_id            = "${data.azurerm_subscription.current.id}/providers/${each.key}"
  method                 = "GET"
  response_export_values = ["resourceTypes"]
}

data "azapi_resource" "this" {
  for_each    = local.resource_names_flat
  type        = "${each.value.type}@${local.latest_stable[each.value.type]}"
  resource_id = each.value.id
  response_export_values = {
    value = local.namespace_commands_map[each.value.type].resource_properties
  }
}