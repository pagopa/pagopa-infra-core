# -----------------------------------------------------------------------------
# Icinga Web theme: "pagopa" module (templates/theme), theme pagopa/default
# set as default in config.ini (icinga-configure.sh). Separate run command:
# a change to the theme doesn't re-run the whole Icinga configuration
# -----------------------------------------------------------------------------
locals {
  icinga_theme_dir = "${path.module}/templates/theme"

  # module path => content (base64)
  icinga_theme_files = {
    for f in sort(fileset(local.icinga_theme_dir, "**")) :
    f => filebase64("${local.icinga_theme_dir}/${f}")
  }

  icinga_theme_hash = substr(sha256(jsonencode([
    filesha256("${path.module}/templates/icinga-theme.sh.tftpl"),
    { for f, c in local.icinga_theme_files : f => sha256(c) },
  ])), 0, 8)
}

resource "azurerm_virtual_machine_run_command" "icinga_theme" {
  name               = "icinga-theme-${local.icinga_theme_hash}"
  location           = azurerm_linux_virtual_machine.icinga.location
  virtual_machine_id = azurerm_linux_virtual_machine.icinga.id

  source {
    script = templatefile("${path.module}/templates/icinga-theme.sh.tftpl", {
      files = local.icinga_theme_files
      hash  = local.icinga_theme_hash
    })
  }

  tags = module.tag_config.tags

  # Icinga Web configured (enabledModules, theme default in config.ini)
  depends_on = [azurerm_virtual_machine_run_command.icinga_configure]
}
