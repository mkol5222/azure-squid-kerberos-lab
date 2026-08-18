resource "azurerm_network_interface" "dc" {
  name                = "nic-dc1"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.dc.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.dc_private_ip
  }
}

resource "azurerm_windows_virtual_machine" "dc" {
  name                  = "vm-dc1"
  computer_name         = local.dc_computer_name
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.dc_vm_size
  admin_username        = var.local_admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.dc.id]
  tags                  = local.tags

  # Trusted Launch: Secure Boot + vTPM, at no extra cost on Gen2 images.
  secure_boot_enabled = true
  vtpm_enabled        = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    # Encrypted at rest by Azure Storage Service Encryption (AES-256) by
    # default -- not something you can turn off, so nothing to configure.
  }

  source_image_reference {
    publisher = var.dc_image.publisher
    offer     = var.dc_image.offer
    sku       = var.dc_image.sku
    version   = var.dc_image.version
  }
}

# ---------------------------------------------------------------------------
# Phase 1: install AD-Domain-Services and promote to a new forest. This
# triggers a reboot partway through (Install-ADDSForest's own doing).
# ---------------------------------------------------------------------------
locals {
  dc_promote_script = <<-EOT
    $env:LAB_DOMAIN_NAME = "${var.domain_name}"
    $env:LAB_NETBIOS_NAME = "${var.netbios_name}"
    $env:LAB_ADMIN_PASSWORD = "${var.admin_password}"

    ${file("${path.module}/scripts/promote-dc.ps1")}
  EOT

  dc_promote_command = "powershell -ExecutionPolicy Bypass -Command \"New-Item -ItemType Directory -Force -Path C:\\AzureData | Out-Null; [IO.File]::WriteAllText('C:\\AzureData\\promote-dc.ps1', [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(local.dc_promote_script)}'))); powershell -ExecutionPolicy Bypass -File C:\\AzureData\\promote-dc.ps1\""
}

resource "azurerm_virtual_machine_extension" "dc_promote" {
  name                       = "promote-forest"
  virtual_machine_id         = azurerm_windows_virtual_machine.dc.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = local.dc_promote_command
  })

  # Install-ADDSForest reboots the VM partway through; the extension
  # reports completion once the script process returns, and the Azure
  # guest agent tolerates the subsequent reboot. The time_sleep below adds
  # a buffer before anything tries to talk to this DC.
  timeouts {
    create = "45m"
  }
}

resource "time_sleep" "wait_for_dc_reboot" {
  depends_on      = [azurerm_virtual_machine_extension.dc_promote]
  create_duration = "180s"
}

# ---------------------------------------------------------------------------
# Phase 2: DNS forwarder + A/PTR records for the proxy and (optional)
# client, now that AD DS / DNS Server are confirmed up post-reboot.
# ---------------------------------------------------------------------------
locals {
  dc_finalize_script = <<-EOT
    $env:LAB_DOMAIN_NAME = "${var.domain_name}"
    $env:LAB_PROXY_HOSTNAME = "${var.proxy_hostname}"
    $env:LAB_PROXY_IP = "${var.proxy_private_ip}"
    $env:LAB_CLIENT_HOSTNAME = "${var.deploy_test_client ? local.client_computer_name : ""}"
    $env:LAB_CLIENT_IP = "${var.deploy_test_client ? var.client_private_ip : ""}"

    ${file("${path.module}/scripts/finalize-dc.ps1")}
  EOT

}

# Windows VMs only support one CustomScriptExtension handler at a time, and
# dc_promote above already occupies it -- a second azurerm_virtual_machine_
# extension of the same type errors with "Multiple VMExtensions per handler
# not supported". VM Run Command has no such restriction and takes the raw
# script directly, so no base64/write-file wrapper is needed here.
resource "azurerm_virtual_machine_run_command" "dc_finalize" {
  name               = "finalize-dns"
  location           = azurerm_resource_group.lab.location
  virtual_machine_id = azurerm_windows_virtual_machine.dc.id

  source {
    script = local.dc_finalize_script
  }

  depends_on = [time_sleep.wait_for_dc_reboot]
}
