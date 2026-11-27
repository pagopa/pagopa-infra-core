# -----------------------------------------------------------------------------
# Cosmos DB for NoSQL: ruolo data-plane per il check cosmos_nosql (common)
# Per ogni account NoSQL monitorato un ruolo custom con la sola readMetadata
# (elenco di database e container, nessun accesso ai dati), assegnato alla
# managed identity della VM Icinga (continuos-platform-monitoring-common)
# -----------------------------------------------------------------------------
data "azurerm_user_assigned_identity" "icinga" {
  name                = "${local.project}-icinga-vm-identity"
  resource_group_name = "${local.project}-icinga-rg"
}

locals {
  # chiave di local.resources_full => account NoSQL (nome e resource group)
  cosmos_nosql_accounts = {
    for k, r in local.resources_full : k => {
      id                  = r.id
      name                = r.name
      resource_group_name = split("/", r.id)[4]
    }
    if r.type == "Microsoft.DocumentDB/databaseAccounts" && r.variant == "GlobalDocumentDB"
  }
}

resource "azurerm_cosmosdb_sql_role_definition" "icinga_read_metadata" {
  for_each = local.cosmos_nosql_accounts

  name                = "icinga-read-metadata"
  resource_group_name = each.value.resource_group_name
  account_name        = each.value.name
  type                = "CustomRole"
  assignable_scopes   = [each.value.id]

  permissions {
    data_actions = ["Microsoft.DocumentDB/databaseAccounts/readMetadata"]
  }
}

resource "azurerm_cosmosdb_sql_role_assignment" "icinga_read_metadata" {
  for_each = local.cosmos_nosql_accounts

  resource_group_name = each.value.resource_group_name
  account_name        = each.value.name
  role_definition_id  = azurerm_cosmosdb_sql_role_definition.icinga_read_metadata[each.key].id
  principal_id        = data.azurerm_user_assigned_identity.icinga.principal_id
  scope               = each.value.id
}
