terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # NOTE: azurerm 5.0 shipped 2026-07-27 as a major, breaking release
      # (e.g. it stops auto-registering Azure Resource Providers). Pinned
      # to the last 4.x line here since that's the syntax this config was
      # verified against; see README.md "Upgrading to azurerm 5.x" before
      # bumping this.
      version = "~> 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  # Local state is fine for a first `terraform init`, but this config
  # generates real secrets (VM local admin / domain admin passwords) that
  # Terraform state will contain in plaintext. Once you've deployed once,
  # move to an encrypted remote backend -- see README.md "Remote state".
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "<globally-unique-name>"
  #   container_name       = "tfstate"
  #   key                  = "squid-kerberos-lab.tfstate"
  #   use_azuread_auth     = true   # keyless access via your az login/OIDC identity
  # }
}

provider "azurerm" {
  features {}
}
