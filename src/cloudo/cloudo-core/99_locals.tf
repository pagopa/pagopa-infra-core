
locals {
  product        = "${var.prefix}-${var.env_short}"
  product_region = "${var.prefix}-${var.env_short}-${var.location_short}"
  product_ita    = "${var.prefix}-${var.env_short}-${var.location_short_ita}"

  aks_integration_clusters = {
    weu = data.azurerm_kubernetes_cluster.aks_weu
  }

  aks_private_clusters = {
    for cluster_key, cluster in local.aks_integration_clusters :
    cluster_key => {
      node_resource_group = cluster.node_resource_group
      private_dns_zone_name = join(
        ".",
        slice(
          split(".", cluster.private_fqdn),
          1,
          length(split(".", cluster.private_fqdn))
        )
      )
    }
    if cluster.private_fqdn != null && cluster.private_fqdn != ""
  }

  container_registries = {
    weu = {
      name                = "${var.prefix}${var.env_short}commonacr"
      resource_group_name = "${local.product}-container-registry-rg"
    }
    itn = {
      name                = "${var.prefix}${var.env_short}itncoreacr"
      resource_group_name = "${local.product_ita}-acr-rg"
    }
    weu_bck = {
      name                = "${var.prefix}${var.env_short}weucoreacrbck"
      resource_group_name = "${local.product}-container-registry-${var.prefix}${var.env_short}commonacr-bck-rg"
    }
    itn_bck = {
      name                = "${var.prefix}${var.env_short}itncoreacrbck"
      resource_group_name = "${local.product}-container-registry-${var.prefix}${var.env_short}itncoreacr-bck-rg"
    }
  }

  container_registry_roles = ["AcrPull", "AcrDelete"]

  container_registry_role_assignments = flatten([
    for acr in data.azurerm_container_registry.acr : [
      for role in local.container_registry_roles : {
        role  = role
        scope = acr.id
      }
    ]
  ])
}
