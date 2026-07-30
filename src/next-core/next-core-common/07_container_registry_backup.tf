module "acr_backup_sync" {
  source = "./.terraform/modules/__v4__/acr_backup_sync"

  product         = local.product
  project         = local.project
  location_backup = local.location_acr_backup
  location        = var.location
  env_short       = var.env_short

  source_acr_id           = module.container_registry.id
  source_acr_login_server = "${module.container_registry.name}.azurecr.io"
  source_acr_name         = module.container_registry.name

  container_app_environment_id = azurerm_container_app_environment.tools_cae[0].id

  build_sync_image   = true
  build_context_path = "./.terraform/modules/__v4__/acr_backup_sync/build"
  tags               = module.tag_config.tags
}