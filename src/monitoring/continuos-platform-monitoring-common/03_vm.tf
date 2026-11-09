resource "azurerm_network_interface" "icinga" {
  name                = "${local.project}-icinga-nic"
  location            = azurerm_resource_group.icinga_rg.location
  resource_group_name = azurerm_resource_group.icinga_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vm_icinga_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = module.vm_icinga_subnet.first_ip_address
  }

  tags = module.tag_config.tags
}

resource "azurerm_network_interface" "icinga_v2" {
  name                = "${local.project}-icinga-v2-nic"
  location            = azurerm_resource_group.icinga_rg.location
  resource_group_name = azurerm_resource_group.icinga_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vm_icinga_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = module.vm_icinga_subnet.last_ip_address
  }

  tags = module.tag_config.tags
}

resource "azurerm_key_vault_secret" "icinga_vm_private_ip" {
  key_vault_id = data.azurerm_key_vault.domain_kv.id
  name         = "icinga-vm-private-ip"
  value        = azurerm_network_interface.icinga.private_ip_address

  tags = module.tag_config.tags
}

resource "azurerm_user_assigned_identity" "icinga" {
  name                = "${local.project}-icinga-vm-identity"
  location            = azurerm_resource_group.icinga_rg.location
  resource_group_name = azurerm_resource_group.icinga_rg.name

  tags = module.tag_config.tags
}

resource "azurerm_key_vault_access_policy" "icinga_vm" {
  key_vault_id = data.azurerm_key_vault.domain_kv.id
  tenant_id    = data.azurerm_subscription.current.tenant_id
  object_id    = azurerm_user_assigned_identity.icinga.principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_linux_virtual_machine" "icinga" {
  name                            = "${local.project}-icinga-vm"
  location                        = azurerm_resource_group.icinga_rg.location
  resource_group_name             = azurerm_resource_group.icinga_rg.name
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

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.icinga.id]
  }

  tags = module.tag_config.tags

  depends_on = [module.azure_custom_image]
}

resource "azurerm_linux_virtual_machine" "icinga_v2" {
  name                            = "${local.project}-icinga-v2-vm"
  location                        = azurerm_resource_group.icinga_rg.location
  resource_group_name             = azurerm_resource_group.icinga_rg.name
  size                            = local.icinga_vm_size
  admin_username                  = "icingaadmin"
  admin_password                  = data.azurerm_key_vault_secret.icinga_vm_admin_password.value
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.icinga_v2.id]

  source_image_id = module.azure_custom_image.custom_image_id

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.icinga.id]
  }

  tags = module.tag_config.tags

  depends_on = [module.azure_custom_image]
}

resource "azurerm_virtual_machine_run_command" "icinga_configure" {
  name               = "icinga-configure-${local.icinga_configure_hash}"
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

  # Apache HTTPS virtual host, certificate synced from domain_kv by icinga-tls-sync
  # with the managed identity of the VM
  parameter {
    name  = "ICINGA_FQDN"
    value = local.icinga_fqdn
  }

  parameter {
    name  = "TLS_SECRET_URL"
    value = local.icinga_tls_secret_url
  }

  parameter {
    name  = "TLS_MSI_CLIENT_ID"
    value = azurerm_user_assigned_identity.icinga.client_id
  }

  # Icinga Web login with Entra ID (04_sso.tf), owners of the application as administrators
  parameter {
    name  = "SSO_TENANT_ID"
    value = data.azurerm_subscription.current.tenant_id
  }

  parameter {
    name  = "SSO_CLIENT_ID"
    value = module.icinga_app.azure_client_id
  }

  parameter {
    name  = "SSO_ADMIN_USERS"
    value = join(",", local.application_owners)
  }

  protected_parameter {
    name  = "SSO_CLIENT_SECRET"
    value = module.icinga_app.azure_client_secret
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

  protected_parameter {
    name  = "ICINGA_API_TERRAFORM_PASSWORD"
    value = data.azurerm_key_vault_secret.icinga_api_terraform_password.value
  }

  # Icinga for Kubernetes: "<chiave>=<nome cluster>" separati da spazi, il
  # kubeconfig (base64) di ogni cluster in AKS_KUBECONFIG_<CHIAVE>
  parameter {
    name  = "AKS_CLUSTERS"
    value = join(" ", [for k, m in local.aks_icinga : "${k}=${m.aks_name}"])
  }

  dynamic "protected_parameter" {
    for_each = local.aks_icinga
    content {
      name  = "AKS_KUBECONFIG_${upper(protected_parameter.key)}"
      value = base64encode(protected_parameter.value.kubeconfig)
    }
  }

  tags = module.tag_config.tags

  # icinga-tls-sync reads the certificate from domain_kv
  depends_on = [azurerm_key_vault_access_policy.icinga_vm]
}

resource "azurerm_virtual_machine_run_command" "icinga_configure_v2" {
  name               = "icinga-configure-${local.icinga_configure_hash}"
  location           = azurerm_linux_virtual_machine.icinga_v2.location
  virtual_machine_id = azurerm_linux_virtual_machine.icinga_v2.id

  source {
    script = file("${path.module}/templates/icinga-configure.sh")
  }

  # on Linux named parameters are exported as environment variables
  parameter {
    name  = "ICINGAWEB_ADMIN_USER"
    value = "admin"
  }

  # Apache HTTPS virtual host, certificate synced from domain_kv by icinga-tls-sync
  # with the managed identity of the VM
  parameter {
    name  = "ICINGA_FQDN"
    value = local.icinga_fqdn
  }

  parameter {
    name  = "TLS_SECRET_URL"
    value = local.icinga_tls_secret_url
  }

  parameter {
    name  = "TLS_MSI_CLIENT_ID"
    value = azurerm_user_assigned_identity.icinga.client_id
  }

  # Icinga Web login with Entra ID (04_sso.tf), owners of the application as administrators
  parameter {
    name  = "SSO_TENANT_ID"
    value = data.azurerm_subscription.current.tenant_id
  }

  parameter {
    name  = "SSO_CLIENT_ID"
    value = module.icinga_app.azure_client_id
  }

  parameter {
    name  = "SSO_ADMIN_USERS"
    value = join(",", local.application_owners)
  }

  protected_parameter {
    name  = "SSO_CLIENT_SECRET"
    value = module.icinga_app.azure_client_secret
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

  protected_parameter {
    name  = "ICINGA_API_TERRAFORM_PASSWORD"
    value = data.azurerm_key_vault_secret.icinga_api_terraform_password.value
  }

  # Icinga for Kubernetes: "<chiave>=<nome cluster>" separati da spazi, il
  # kubeconfig (base64) di ogni cluster in AKS_KUBECONFIG_<CHIAVE>
  parameter {
    name  = "AKS_CLUSTERS"
    value = join(" ", [for k, m in local.aks_icinga : "${k}=${m.aks_name}"])
  }

  dynamic "protected_parameter" {
    for_each = local.aks_icinga
    content {
      name  = "AKS_KUBECONFIG_${upper(protected_parameter.key)}"
      value = base64encode(protected_parameter.value.kubeconfig)
    }
  }

  tags = module.tag_config.tags

  # icinga-tls-sync reads the certificate from domain_kv
  depends_on = [azurerm_key_vault_access_policy.icinga_vm]
}