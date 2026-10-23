data "azurerm_virtual_machine" "icinga" {
  name                = "payment-superset"
  resource_group_name = "test-matteo"
}

# Scrive la config del Business Process direttamente sul filesystem della VM
# Il contenuto è incluso nello script, quindi ogni modifica a bp_content
# aggiorna la run command e la riesegue.
resource "azurerm_virtual_machine_run_command" "icinga_bp" {
  name               = "icinga-bp-${local.bp_name}"
  location           = data.azurerm_virtual_machine.icinga.location
  virtual_machine_id = data.azurerm_virtual_machine.icinga.id

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
