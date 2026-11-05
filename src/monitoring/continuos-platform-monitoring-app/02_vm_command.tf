data "azurerm_virtual_machine" "icinga_vm" {
  name                = "${local.project}-icinga-vm"
  resource_group_name = "${local.project}-icinga-rg"
}

# Business Process; lo stile della vista a tile è nel tema pagopa/default
# (continuos-platform-monitoring-common, 05_theme.tf)
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
    EOT
  }

  tags = module.tag_config.tags
}