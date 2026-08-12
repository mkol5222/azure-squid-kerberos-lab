variable "location" {
  description = "Azure region for all lab resources."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group to create for the lab."
  type        = string
  default     = "rg-squid-kerberos-lab"
}

variable "project_name" {
  description = "Short name used to build globally-unique resource names (Key Vault, etc). Lowercase letters/numbers only, 3-10 chars."
  type        = string
  default     = "squidkrb"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.project_name))
    error_message = "project_name must be 3-10 lowercase alphanumeric characters, starting with a letter."
  }
}

variable "domain_name" {
  description = "Fully-qualified AD DNS domain name for the lab forest, e.g. lab.contoso.local. This is a throwaway lab domain -- don't use a domain you rely on elsewhere."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$", var.domain_name))
    error_message = "domain_name must be a valid FQDN with at least one dot, e.g. lab.contoso.local."
  }
}

variable "netbios_name" {
  description = "NetBIOS name for the AD domain, e.g. LAB. 1-15 characters (legacy Windows domain naming limit)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,15}$", var.netbios_name))
    error_message = "netbios_name must be 1-15 characters: letters, numbers, hyphens."
  }
}

variable "local_admin_username" {
  description = "Local admin username created on every VM. Kept off Azure's reserved-name list on purpose (\"administrator\" etc. are rejected by the platform at VM-creation time). On the DC, this account is what dcpromo carries over into Domain Admins."
  type        = string
  default     = "azlabadmin"
}

variable "proxy_hostname" {
  description = "Short hostname (no domain suffix) for the Squid proxy, used to build its FQDN and Kerberos SPN. This must be the name clients put in their proxy settings -- Kerberos SPNEGO will not work against a raw IP."
  type        = string
  default     = "proxy"
}

variable "msktutil_computer_name" {
  description = "AD computer object name msktutil creates for the proxy's keytab (<=15 chars, will be lower-cased). Independent of the Linux OS hostname."
  type        = string
  default     = "squid-http"
}

variable "client_hostname" {
  description = "Short hostname for the optional test client VM."
  type        = string
  default     = "client1"
}

variable "admin_ssh_public_key" {
  description = "Your SSH PUBLIC key content (e.g. contents of ~/.ssh/id_ed25519.pub) for SSH access to the Squid Linux VM. Never paste a private key -- password auth is disabled on this VM entirely."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) ", var.admin_ssh_public_key))
    error_message = "admin_ssh_public_key must be a public key starting with ssh-ed25519, ssh-rsa, or ecdsa-sha2-*."
  }
}

variable "deploy_bastion" {
  description = "Deploy Azure Bastion for browser-based RDP/SSH. Leave true unless you already have private connectivity (VPN/ExpressRoute/peering) into this VNet from your workstation. Either way, no VM in this config ever gets a public IP -- Check Point's Network Security Policy prohibits exposing admin ports like RDP/SSH externally, with no exception clause, so there is deliberately no public-IP fallback variable here."
  type        = bool
  default     = true
}

variable "deploy_test_client" {
  description = "Deploy a domain-joined Windows 11 client VM for end-to-end testing of Kerberos SSO through the proxy."
  type        = bool
  default     = true
}

variable "dc_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "proxy_vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "client_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "proxy_image" {
  description = "Ubuntu image for the Squid proxy VM."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

variable "dc_image" {
  description = "Windows Server image for the domain controller VM."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

variable "client_image" {
  description = "Windows 11 image for the optional test client VM. This is a standalone Pro SKU (not an -avd SKU, which carries AVD-specific licensing/deployment requirements). Check `az vm image list -p MicrosoftWindowsDesktop -f windows-11 --all -o table` for a newer -pro SKU in your region before applying, since these get superseded periodically."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-23h2-pro"
    version   = "latest"
  }
}

variable "vnet_cidr" {
  type    = string
  default = "10.60.0.0/16"
}

variable "dc_subnet_cidr" {
  type    = string
  default = "10.60.1.0/24"
}

variable "proxy_subnet_cidr" {
  type    = string
  default = "10.60.2.0/24"
}

variable "client_subnet_cidr" {
  type    = string
  default = "10.60.3.0/24"
}

variable "bastion_subnet_cidr" {
  description = "Must be /26 or larger; the subnet name AzureBastionSubnet is fixed by Azure and set automatically."
  type        = string
  default     = "10.60.10.0/26"
}

variable "dc_private_ip" {
  type    = string
  default = "10.60.1.4"
}

variable "proxy_private_ip" {
  type    = string
  default = "10.60.2.4"
}

variable "client_private_ip" {
  type    = string
  default = "10.60.3.4"
}

variable "tags" {
  type = map(string)
  default = {
    environment = "lab"
    purpose     = "squid-kerberos-poc"
  }
}
