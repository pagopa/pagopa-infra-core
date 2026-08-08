# Recupero di tutte le risorse di tipo Action Group

data "azurerm_resources" "all_ag" {
  type     = "microsoft.insights/actiongroups"
  resource_group_name = local.monitor_resource_group_name
}


locals {

# Mappa indicizzata su nome ag
  action_group_ids_by_name = {
    for name, ag in data.azurerm_resources.all_ag.resources : ag.name => ag.id
  }


# Array di ag di default a cui associare tutti gli alert
  default_action_group_ids = {
    "default" = concat ([
     local.action_group_ids_by_name["PagoPA"],
     local.action_group_ids_by_name["SlackPagoPA"],

    ], var.env_short == "p" ? [local.action_group_ids_by_name["InfraOpsgenie"]] : [])
  }

# Array di ag custom per namespace da aggiungere ai default 
   action_group_overrides = {
   "Microsoft.Web/sites" = [
     local.action_group_ids_by_name["SlackPagoPANODO"],
   ]
  }

# Array combinato ag di default + custom

  combined_action_group = distinct(flatten([
  values(local.default_action_group_ids),
  values(local.action_group_overrides),
]))

}

module "amba_alerts_core_platform" {
  source = "./.terraform/modules/__v4__/continuos_platform_alerting"

  # Scope: se omesso, la discovery avviene su tutta la subscription
  # del provider corrente.
  resource_group_name = local.monitor_resource_group_name

  # Solo i namespace validati nella fase di analisi. Vuoto = tutti i
  # namespace disponibili nel dataset AMBA sincronizzato.
  included_namespaces = [
    "Microsoft.ContainerService/managedClusters",  # AKS
    "Microsoft.ApiManagement/service",             # APIM
    "Microsoft.ContainerRegistry/registries",      # ACR
    "Microsoft.App/containerApps",                 # Container Apps
    "Microsoft.DBforPostgreSQL/flexibleServers",   # PostgreSQL
    "Microsoft.Network/natGateways",               # NatGateway
    "Microsoft.DocumentDB/databaseAccounts",       # CosmosDb
    "Microsoft.Cache/Redis",                       # Azure for Redis
    "Microsoft.Cache/redisEnterprise",             # Managed Redis
    "Microsoft.Web/sites",                         # App Service
    "Microsoft.App/jobs",                          # Container Jon (non ancora in AMBA)
    "Microsoft.Cdn/profiles",                      # CDN
    "Microsoft.ContainerRegistry/registries",      # ACR
    "Microsoft.Compute/virtualMachineScaleSets",   # VMSS
  ]

  # Solo le alert "Must Have" AMBA di default. Passare a false abilita
  # anche le "Nice to Have": aumenta sensibilmente il numero di alert.
  enabled_only = true

  action_group_ids = local.combined_action_group

  # Esempio di override puntuale: WorkingSetBytes su Container Apps ha
  # una soglia assoluta AMBA (500 MB) pensata come default generico,
  # da adattare al sizing reale delle vostre container apps.
  threshold_overrides = {
    "Microsoft.App/containerApps|WorkingSetBytes" = 900000000 # 900 MB, adattare a limits.memory reale
  }

  tags = {
    ManagedBy = "terraform"
    Source    = "amba"
  }
}


output "riepilogo_alert" {
  value = {
    namespaces         = module.amba_alerts_core_platform.target_namespaces
    risorse_per_ns     = module.amba_alerts_core_platform.discovered_resource_counts
    alert_per_ns       = module.amba_alerts_core_platform.alert_count_by_namespace
    totale_alert       = module.amba_alerts_core_platform.total_alert_count
    commit_amba_sorgente = module.amba_alerts_core_platform.amba_source_commit
  }
}
