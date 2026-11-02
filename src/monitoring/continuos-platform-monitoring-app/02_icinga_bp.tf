data "azurerm_virtual_machine" "icinga_vm" {
  name                = "${local.project}-icinga-vm"
  resource_group_name = "${local.project}-icinga-rg"
}

resource "azurerm_virtual_machine_run_command" "icinga_vm_bp" {
  name               = "${local.project}-icinga-vm-bp-${local.bp_name}"
  location           = data.azurerm_virtual_machine.icinga_vm.location
  virtual_machine_id = data.azurerm_virtual_machine.icinga_vm.id

  source {
    script = <<-EOT
      set -euo pipefail
      mkdir -p ${local.bp_dir}
      TMP=$(mktemp ${local.bp_dir}/.${local.bp_name}.XXXXXX)
      echo '${base64encode(local.bp_content)}' | base64 -d > "$TMP"
      chown --reference=${local.bp_dir} "$TMP"
      chmod 0660 "$TMP"
      mv -f "$TMP" ${local.bp_file}
      echo "written ${local.bp_file} (sha256 ${sha256(local.bp_content)})"

      # tema Icinga Web per la vista a tile, impostato come default in icinga-configure.sh
      mkdir -p ${local.bp_theme_dir}
      TMP=$(mktemp ${local.bp_theme_dir}/.bp-tiles.XXXXXX)
      echo '${base64encode(local.bp_theme)}' | base64 -d > "$TMP"
      chmod 0644 "$TMP"
      mv -f "$TMP" ${local.bp_theme_file}
      echo "written ${local.bp_theme_file} (sha256 ${sha256(local.bp_theme)})"
    EOT
  }

  tags = module.tag_config.tags
}