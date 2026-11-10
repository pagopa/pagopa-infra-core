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

  # time allowed to the extensions at provisioning and start (minimum PT15M)
  extensions_time_budget = "PT15M"

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

# -----------------------------------------------------------------------------
# Icinga configuration (icinga-configure.sh), run once by templates/run-command.sh
# with a run command deleted at the end. Re-run when the script, a secret
# version or a kubeconfig changes (local.icinga_configure_hash) or the VM is
# replaced. Requires the Azure CLI logged in
# -----------------------------------------------------------------------------
resource "terraform_data" "icinga_configure" {
  triggers_replace = [
    azurerm_linux_virtual_machine.icinga.id,
    local.icinga_configure_hash,
  ]

  provisioner "local-exec" {
    command = "${path.module}/templates/run-command.sh"

    environment = merge(
      {
        SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
        RESOURCE_GROUP  = azurerm_resource_group.icinga_rg.name
        VM_NAME         = azurerm_linux_virtual_machine.icinga.name
        LOCATION        = azurerm_linux_virtual_machine.icinga.location
        RUN_NAME        = "icinga-configure-${local.icinga_configure_hash}"
        SCRIPT_PATH     = "${path.module}/templates/icinga-configure.sh"

        PARAMETERS = join(" ", [
          "ICINGAWEB_ADMIN_USER", "ICINGA_FQDN", "TLS_SECRET_URL", "TLS_MSI_CLIENT_ID",
          "SSO_TENANT_ID", "SSO_CLIENT_ID", "ROLE_GROUPS", "AKS_CLUSTERS",
        ])
        PROTECTED_PARAMETERS = join(" ", concat([
          "SSO_CLIENT_SECRET", "ICINGADB_DB_PASSWORD", "ICINGAWEB_DB_PASSWORD",
          "ICINGAWEB_ADMIN_PASSWORD", "ICINGA_API_TERRAFORM_PASSWORD",
        ], [for k in keys(local.aks_icinga) : "AKS_KUBECONFIG_${upper(k)}"]))

        ICINGAWEB_ADMIN_USER = "admin"
        # Apache HTTPS virtual host, certificate synced from domain_kv by icinga-tls-sync
        # with the managed identity of the VM
        ICINGA_FQDN       = local.icinga_fqdn
        TLS_SECRET_URL    = local.icinga_tls_secret_url
        TLS_MSI_CLIENT_ID = azurerm_user_assigned_identity.icinga.client_id
        # Icinga Web login with Entra ID (06_sso.tf), roles of the Entra ID groups
        SSO_TENANT_ID = data.azurerm_subscription.current.tenant_id
        SSO_CLIENT_ID = module.icinga_app.azure_client_id
        ROLE_GROUPS   = local.icinga_role_groups
        # Icinga for Kubernetes: "<chiave>=<nome cluster>" separati da spazi, il
        # kubeconfig (base64) di ogni cluster in AKS_KUBECONFIG_<CHIAVE>
        AKS_CLUSTERS = join(" ", [for k, m in local.aks_icinga : "${k}=${m.aks_name}"])

        SSO_CLIENT_SECRET             = module.icinga_app.azure_client_secret
        ICINGADB_DB_PASSWORD          = data.azurerm_key_vault_secret.icingadb_db_password.value
        ICINGAWEB_DB_PASSWORD         = data.azurerm_key_vault_secret.icingaweb_db_password.value
        ICINGAWEB_ADMIN_PASSWORD      = data.azurerm_key_vault_secret.icingaweb_admin_password.value
        ICINGA_API_TERRAFORM_PASSWORD = data.azurerm_key_vault_secret.icinga_api_terraform_password.value
      },
      { for k, m in local.aks_icinga : "AKS_KUBECONFIG_${upper(k)}" => base64encode(m.kubeconfig) }
    )
  }

  # icinga-tls-sync reads the certificate from domain_kv
  depends_on = [azurerm_key_vault_access_policy.icinga_vm]
}
