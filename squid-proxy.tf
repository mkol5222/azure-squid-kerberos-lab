resource "azurerm_network_interface" "proxy" {
  name                = "nic-proxy"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.proxy.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.proxy_private_ip
  }
}

resource "azurerm_linux_virtual_machine" "proxy" {
  name                  = "vm-proxy"
  computer_name         = "proxy1"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.proxy_vm_size
  admin_username        = var.local_admin_username
  network_interface_ids = [azurerm_network_interface.proxy.id]
  tags                  = local.tags

  # SSH key only -- password authentication is disabled outright, so
  # there's no proxy-VM secret to generate, store, or leak in the first
  # place.
  disable_password_authentication = true
  admin_ssh_key {
    username   = var.local_admin_username
    public_key = var.admin_ssh_public_key
  }

  secure_boot_enabled = true
  vtpm_enabled        = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = var.proxy_image.publisher
    offer     = var.proxy_image.offer
    sku       = var.proxy_image.sku
    version   = var.proxy_image.version
  }
}

locals {
  squid_configure_script = <<-EOT
    export LAB_DOMAIN_NAME='${var.domain_name}'
    export LAB_REALM='${local.realm}'
    export LAB_DC_FQDN='${local.dc_fqdn}'
    export LAB_DC_IP='${var.dc_private_ip}'
    export LAB_PROXY_FQDN='${local.proxy_fqdn}'
    export LAB_COMPUTERS_DN='${local.computers_dn}'
    export LAB_DOMAIN_ADMIN_UPN='${local.domain_admin_upn}'
    export LAB_DOMAIN_ADMIN_PASSWORD='${random_password.dc_admin.result}'
    export LAB_MSKTUTIL_COMPUTER_NAME='${var.msktutil_computer_name}'

    ${file("${path.module}/scripts/configure-squid.sh")}
  EOT

  squid_configure_command = "bash -c \"echo '${base64encode(local.squid_configure_script)}' | base64 -d > /tmp/configure-squid.sh && bash /tmp/configure-squid.sh\""
}

resource "azurerm_virtual_machine_extension" "proxy_configure" {
  name                       = "configure-squid-kerberos"
  virtual_machine_id         = azurerm_linux_virtual_machine.proxy.id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true

  # The whole command (including the embedded domain-admin password) lives
  # in protected_settings, which Azure encrypts and hides from the
  # extension's status/logs. It is still visible in Terraform state --
  # see README.md "Remote state" for why that must be an encrypted,
  # access-restricted backend.
  protected_settings = jsonencode({
    commandToExecute = local.squid_configure_command
  })

  depends_on = [azurerm_virtual_machine_extension.dc_finalize]

  timeouts {
    create = "20m"
  }
}
