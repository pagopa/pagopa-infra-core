terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.4"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
  backend "azurerm" {}
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

# un provider per cluster AKS (vedi local.aks_clusters)
provider "kubernetes" {
  alias       = "itn"
  config_path = local.aks_clusters["itn"].kube_config_path
}

provider "kubernetes" {
  alias       = "weu"
  config_path = local.aks_clusters["weu"].kube_config_path
}

data "azurerm_subscription" "current" {}

module "__v4__" {
  # https://github.com/pagopa/terraform-azurerm-v4/releases/tag/v10.45.0
  source = "git::https://github.com/pagopa/terraform-azurerm-v4.git?ref=PAYMCLOUD-1192_packer_vm_custom_image"
}