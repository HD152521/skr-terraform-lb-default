terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.74.0"
    }
  }
  backend "local" {}
}

provider "azurerm" {
  features {}
  #subscription_id = var.subscription_id
}
