resource "azurerm_network_interface" "client" {
  count               = var.deploy_test_client ? 1 : 0
  name                = "nic-client1"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.client[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.client_private_ip
  }
}

resource "azurerm_windows_virtual_machine" "client" {
  count                 = var.deploy_test_client ? 1 : 0
  name                  = "vm-client1"
  computer_name         = local.client_computer_name
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.client_vm_size
  admin_username        = var.local_admin_username
  admin_password        = random_password.client_admin[0].result
  network_interface_ids = [azurerm_network_interface.client[0].id]
  tags                  = local.tags

  secure_boot_enabled = true
  vtpm_enabled        = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = var.client_image.publisher
    offer     = var.client_image.offer
    sku       = var.client_image.sku
    version   = var.client_image.version
  }
}

locals {
  # Computed unconditionally -- harmless even when deploy_test_client is
  # false, since the only consumer (azurerm_virtual_machine_extension
  # .client_join below) is already count-gated on that same variable.
  client_join_script = <<-EOT
    $env:LAB_DOMAIN_NAME = "${var.domain_name}"
    $env:LAB_NETBIOS_NAME = "${var.netbios_name}"
    $env:LAB_DOMAIN_ADMIN_USERNAME = "${var.local_admin_username}"
    $env:LAB_ADMIN_PASSWORD = "${random_password.dc_admin.result}"

    ${file("${path.module}/scripts/join-client.ps1")}
  EOT

  client_join_command = "powershell -ExecutionPolicy Bypass -Command \"New-Item -ItemType Directory -Force -Path C:\\Windows\\Temp | Out-Null; [IO.File]::WriteAllText('C:\\Windows\\Temp\\join-client.ps1', [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(local.client_join_script)}'))); powershell -ExecutionPolicy Bypass -File C:\\Windows\\Temp\\join-client.ps1\""
}

resource "azurerm_virtual_machine_extension" "client_join" {
  count                      = var.deploy_test_client ? 1 : 0
  name                       = "join-domain"
  virtual_machine_id         = azurerm_windows_virtual_machine.client[0].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = local.client_join_command
  })

  depends_on = [azurerm_virtual_machine_run_command.dc_finalize]

  timeouts {
    create = "20m"
  }
}
