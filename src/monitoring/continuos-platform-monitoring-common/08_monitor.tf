# -----------------------------------------------------------------------------
# Alerts on the Icinga VM, from Azure Monitor: they still work when Icinga
# itself is down or blind (e.g. MySQL with a full disk). The Azure Monitor Agent
# sends the free space of "/" and its heartbeat to the core Log Analytics
# workspace, log alerts read them with the VM as scope.
# No action group yet: alerts are only shown in Azure Monitor
# -----------------------------------------------------------------------------
data "azurerm_log_analytics_workspace" "core" {
  name                = "${local.product}-${local.location_short}-core-law"
  resource_group_name = "${local.product}-${local.location_short}-core-monitor-rg"
}

# authenticates with the user-assigned identity, the only one of the VM.
# After the run commands: extension operations on the same VM can't overlap
resource "azurerm_virtual_machine_extension" "icinga_ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.icinga.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true

  settings = jsonencode({
    authentication = {
      managedIdentity = {
        identifier-name  = "mi_res_id"
        identifier-value = azurerm_user_assigned_identity.icinga.id
      }
    }
  })

  tags = module.tag_config.tags

  depends_on = [terraform_data.icinga_configure, terraform_data.icinga_theme]
}

# free space of "/" every minute (Perf table)
resource "azurerm_monitor_data_collection_rule" "icinga_vm" {
  name                = "${local.project}-icinga-vm-dcr"
  resource_group_name = azurerm_resource_group.icinga_rg.name
  location            = azurerm_resource_group.icinga_rg.location
  kind                = "Linux"

  destinations {
    log_analytics {
      name                  = "core-law"
      workspace_resource_id = data.azurerm_log_analytics_workspace.core.id
    }
  }

  data_sources {
    performance_counter {
      name                          = "disk"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = ["Logical Disk(*)\\% Free Space"]
    }
  }

  # only "/": Logical Disk(*) also returns "total" and a dozen virtual mounts
  # (/dev, /dev/shm, /run/credentials/...), not used by the alerts
  data_flow {
    streams       = ["Microsoft-Perf"]
    destinations  = ["core-law"]
    transform_kql = "source | where InstanceName == \"/\""
  }

  tags = module.tag_config.tags
}

resource "azurerm_monitor_data_collection_rule_association" "icinga_vm" {
  name                    = "${local.project}-icinga-vm-dcra"
  target_resource_id      = azurerm_linux_virtual_machine.icinga.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.icinga_vm.id
}

locals {
  # same thresholds as the "disk" service of Icinga (free space of "/")
  icinga_vm_disk_alerts = {
    warning  = { severity = 2, free_percent = 20 }
    critical = { severity = 1, free_percent = 10 }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "icinga_vm_disk" {
  for_each = local.icinga_vm_disk_alerts

  name                = "${local.project}-icinga-vm-disk-${each.key}"
  resource_group_name = azurerm_resource_group.icinga_rg.name
  location            = azurerm_resource_group.icinga_rg.location
  description         = "Icinga VM: less than ${each.value.free_percent}% free space on /"
  severity            = each.value.severity
  scopes              = [azurerm_linux_virtual_machine.icinga.id]

  evaluation_frequency    = "PT5M"
  window_duration         = "PT15M"
  auto_mitigation_enabled = true

  criteria {
    query                   = <<-KQL
      Perf
      | where ObjectName == "Logical Disk" and CounterName == "% Free Space" and InstanceName == "/"
    KQL
    time_aggregation_method = "Minimum"
    metric_measure_column   = "CounterValue"
    operator                = "LessThan"
    threshold               = each.value.free_percent

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  tags = module.tag_config.tags

  depends_on = [azurerm_monitor_data_collection_rule_association.icinga_vm]
}

# no heartbeat for 10 minutes: VM or agent down
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "icinga_vm_heartbeat" {
  name                = "${local.project}-icinga-vm-heartbeat"
  resource_group_name = azurerm_resource_group.icinga_rg.name
  location            = azurerm_resource_group.icinga_rg.location
  description         = "Icinga VM: no heartbeat from the Azure Monitor Agent for 10 minutes"
  severity            = 1
  scopes              = [azurerm_linux_virtual_machine.icinga.id]

  evaluation_frequency    = "PT5M"
  window_duration         = "PT10M"
  auto_mitigation_enabled = true

  criteria {
    query                   = "Heartbeat"
    time_aggregation_method = "Count"
    operator                = "LessThan"
    threshold               = 1

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  tags = module.tag_config.tags

  depends_on = [azurerm_monitor_data_collection_rule_association.icinga_vm]
}
