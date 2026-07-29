terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "> 4.0.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "<= 3.0.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "<= 3.2.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "<= 2.25.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "<= 2.12.1"
    }
    local = {
      source = "hashicorp/local"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

data "azurerm_subscription" "current" {}

data "azurerm_client_config" "current" {}

module "__v4__" {
  # v10.16.2
  source = "git::https://github.com/pagopa/terraform-azurerm-v4?ref=372bf173e82d7ff1e705a37c1d4309e2f96ec4b6"
}
