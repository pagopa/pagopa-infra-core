terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5"
    }

    icinga2 = {
      source  = "Icinga/icinga2"
      version = "= 0.7.1"
    }

    azapi = {
      source  = "azure/azapi"
      version = ">= 2.13.0"
    }
  }
  backend "azurerm" {}
}

provider "icinga2" {
  api_url                  = "https://10.3.144.5:5665/v1"
  api_user                 = "icingadb-web-teo"
  api_password             = ""
  insecure_skip_tls_verify = true
}


provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_subscription" "current" {}
