resource "azurerm_network_interface" "icinga" {
  name                = "${local.project}-icinga-nic"
  location            = azurerm_resource_group.custom_image_rg.location
  resource_group_name = azurerm_resource_group.custom_image_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vm_icinga_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = module.vm_icinga_subnet.first_ip_address
  }

  tags = module.tag_config.tags
}

resource "azurerm_key_vault_secret" "icinga_vm_private_ip" {
  key_vault_id = data.azurerm_key_vault.domain_kv.id
  name         = "icinga-vm-private-ip"
  value        = module.vm_icinga_subnet.first_ip_address

  tags = module.tag_config.tags
}

resource "azurerm_linux_virtual_machine" "icinga" {
  name                            = "${local.project}-icinga-vm"
  location                        = azurerm_resource_group.custom_image_rg.location
  resource_group_name             = azurerm_resource_group.custom_image_rg.name
  size                            = local.icinga_vm_size
  admin_username                  = "icingaadmin"
  admin_password                  = data.azurerm_key_vault_secret.icinga_vm_admin_password.value
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.icinga.id]

  source_image_id = module.azure_custom_image.custom_image_id

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  tags = module.tag_config.tags

  depends_on = [module.azure_custom_image]
}

resource "azurerm_virtual_machine_run_command" "icinga_configure" {
  name               = "icinga-configure"
  location           = azurerm_linux_virtual_machine.icinga.location
  virtual_machine_id = azurerm_linux_virtual_machine.icinga.id

  source {
    script = file("${path.module}/templates/icinga-configure.sh")
  }

  # on Linux named parameters are exported as environment variables
  parameter {
    name  = "ICINGAWEB_ADMIN_USER"
    value = "admin"
  }

  protected_parameter {
    name  = "ICINGADB_DB_PASSWORD"
    value = data.azurerm_key_vault_secret.icingadb_db_password.value
  }

  protected_parameter {
    name  = "ICINGAWEB_DB_PASSWORD"
    value = data.azurerm_key_vault_secret.icingaweb_db_password.value
  }

  protected_parameter {
    name  = "ICINGAWEB_ADMIN_PASSWORD"
    value = data.azurerm_key_vault_secret.icingaweb_admin_password.value
  }

  tags = module.tag_config.tags
}
