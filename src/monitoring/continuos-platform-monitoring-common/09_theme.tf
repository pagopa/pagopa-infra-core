# -----------------------------------------------------------------------------
# Icinga Web theme: "pagopa" module (resources/theme/files), theme pagopa/default
# set as default in config.ini (icinga-configure.sh). Separate run: a change
# to the theme doesn't re-run the whole Icinga configuration
# -----------------------------------------------------------------------------
locals {
  icinga_theme_script = "${local.icinga_resources_dir}/theme/icinga-theme.sh"
  icinga_theme_dir    = "${local.icinga_resources_dir}/theme/files"

  icinga_theme_hash = substr(sha256(jsonencode([
    filesha256(local.icinga_theme_script),
    { for f in sort(fileset(local.icinga_theme_dir, "**")) : f => filesha256("${local.icinga_theme_dir}/${f}") },
  ])), 0, 8)
}

# Run once by resources/run-command/run-command.sh with a run command deleted
# at the end, the files of the theme added to icinga-theme.sh ("@FILES@").
# Re-run when the theme changes or Icinga is configured again (VM replaced).
# Requires the Azure CLI logged in
resource "terraform_data" "icinga_theme" {
  triggers_replace = [
    terraform_data.icinga_configure.id,
    local.icinga_theme_hash,
  ]

  provisioner "local-exec" {
    command = local.icinga_run_command

    environment = {
      SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
      RESOURCE_GROUP  = azurerm_resource_group.icinga_rg.name
      VM_NAME         = azurerm_linux_virtual_machine.icinga.name
      LOCATION        = azurerm_linux_virtual_machine.icinga.location
      RUN_NAME        = "icinga-theme-${local.icinga_theme_hash}"
      SCRIPT_PATH     = local.icinga_theme_script
      EMBED_DIR       = local.icinga_theme_dir
      PARAMETERS      = "THEME_HASH"
      THEME_HASH      = local.icinga_theme_hash
    }
  }
}
