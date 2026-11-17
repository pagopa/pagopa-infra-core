# -----------------------------------------------------------------------------
# Icinga data disk: the state of the VM that must survive its recreation for a
# new icinga_image_version, separate from the OS disk. /var/lib/mysql (Icinga
# databases: history, SLA, reports, Director) and /var/lib/icinga2 (API objects,
# downtimes, acknowledgements, comments). Found by the VM on its fixed LUN
# (/dev/disk/azure/scsi1/lun<N>), never change it once created
# -----------------------------------------------------------------------------
resource "azurerm_managed_disk" "icinga_data" {
  name                 = "${local.project}-icinga-data-disk"
  location             = azurerm_resource_group.icinga_rg.location
  resource_group_name  = azurerm_resource_group.icinga_rg.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.icinga_data_disk_size_gb

  tags = module.tag_config.tags

  # the state of Icinga: remove this block to really delete it
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "icinga_data" {
  managed_disk_id    = azurerm_managed_disk.icinga_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.icinga.id
  lun                = local.icinga_data_disk_lun
  caching            = "ReadOnly"
}
# -----------------------------------------------------------------------------
# Before the detach of the disk (VM recreation, a new attachment) the destroy of
# this resource stops the Icinga services and unmounts the disk on the VM
# (resources/configure/icinga-data-release.sh), so MySQL isn't cut off while
# writing. Replaced with the attachment, destroyed before it. Skipped when the
# VM is not running: the disk is not in use. Requires the Azure CLI logged in
# -----------------------------------------------------------------------------
resource "terraform_data" "icinga_data_release" {
  triggers_replace = [azurerm_virtual_machine_data_disk_attachment.icinga_data.id]

  # a destroy provisioner can only read self
  input = {
    subscription_id = data.azurerm_subscription.current.subscription_id
    resource_group  = azurerm_resource_group.icinga_rg.name
    vm_name         = azurerm_linux_virtual_machine.icinga.name
    location        = azurerm_linux_virtual_machine.icinga.location
    run_command     = local.icinga_run_command
    script_path     = "${local.icinga_resources_dir}/configure/icinga-data-release.sh"
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      power_state="$(az vm show --show-details --subscription "$SUBSCRIPTION_ID" \
        --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query powerState --output tsv)"
      if [ "$power_state" != "VM running" ]; then
        echo "$VM_NAME: $power_state, data disk not in use"
        exit 0
      fi
      exec "$RUN_COMMAND"
    EOT

    environment = {
      SUBSCRIPTION_ID = self.input.subscription_id
      RESOURCE_GROUP  = self.input.resource_group
      VM_NAME         = self.input.vm_name
      LOCATION        = self.input.location
      RUN_COMMAND     = self.input.run_command
      RUN_NAME        = "icinga-data-release"
      SCRIPT_PATH     = self.input.script_path
    }
  }
}
