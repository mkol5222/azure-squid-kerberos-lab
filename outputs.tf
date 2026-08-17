output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "key_vault_name" {
  description = "Retrieve generated passwords with: az keyvault secret show --vault-name <this> --name dc-local-admin-password --query value -o tsv"
  value       = azurerm_key_vault.lab.name
}

output "domain_name" {
  value = var.domain_name
}

output "dc_private_ip" {
  value = var.dc_private_ip
}

output "proxy_fqdn" {
  description = "Set this as the proxy hostname (port 3128) in the test client's browser/IE proxy settings -- Kerberos SPNEGO will not work against a raw IP."
  value       = local.proxy_fqdn
}

output "proxy_private_ip" {
  value = var.proxy_private_ip
}

output "client_fqdn" {
  value = var.deploy_test_client ? local.client_fqdn : null
}

output "bastion_name" {
  value = var.deploy_bastion ? azurerm_bastion_host.lab[0].name : null
}

output "connect_via_bastion" {
  description = "Example az cli commands to reach each VM with no public IP anywhere."
  value = var.deploy_bastion ? {
    rdp_to_dc     = "az network bastion rdp --name ${azurerm_bastion_host.lab[0].name} --resource-group ${azurerm_resource_group.lab.name} --target-resource-id ${azurerm_windows_virtual_machine.dc.id}"
    # -- -o IdentitiesOnly=yes: without it, an ssh-agent holding several
    # keys offers all of them before the one named by --ssh-key, and
    # tunneled bastion SSH's low MaxAuthTries rejects the connection
    # ("Too many authentication failures") before it ever gets there.
    ssh_to_proxy  = "az network bastion ssh --name ${azurerm_bastion_host.lab[0].name} --resource-group ${azurerm_resource_group.lab.name} --target-resource-id ${azurerm_linux_virtual_machine.proxy.id} --auth-type ssh-key --username ${var.local_admin_username} --ssh-key ~/.ssh/id_ed25519 -- -o IdentitiesOnly=yes"
    rdp_to_client = var.deploy_test_client ? "az network bastion rdp --name ${azurerm_bastion_host.lab[0].name} --resource-group ${azurerm_resource_group.lab.name} --target-resource-id ${azurerm_windows_virtual_machine.client[0].id}" : null
  } : null
}
