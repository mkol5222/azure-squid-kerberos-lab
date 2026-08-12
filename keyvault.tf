data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "lab" {
  name                = "kv-${local.name_suffix}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enable_rbac_authorization  = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  tags = local.tags
}

# Grants only the identity running `terraform apply` (your az login /
# OIDC identity) permission to read/write secrets -- least privilege
# rather than a broad access policy.
resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.lab.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "random_password" "dc_admin" {
  length  = 24
  upper   = true
  lower   = true
  numeric = true
  special = true
  # Kept to shell/PowerShell-safe punctuation since this value gets
  # `echo`-piped into kinit and embedded in PowerShell env-var assignments;
  # avoids characters (`, ", ', \, $, ;, &, |) that could otherwise break
  # quoting in those contexts.
  override_special = "!#%^*()-_=+"
}

resource "random_password" "client_admin" {
  count            = var.deploy_test_client ? 1 : 0
  length           = 24
  upper            = true
  lower            = true
  numeric          = true
  special          = true
  override_special = "!#%^*()-_=+"
}

# Secrets land in Key Vault (AES-256 at rest, Microsoft-managed by default)
# for YOU to retrieve later -- Terraform itself wires the same resource
# attributes directly into the VMs below rather than round-tripping
# through the vault mid-apply.
resource "azurerm_key_vault_secret" "dc_admin_password" {
  name         = "dc-local-admin-password"
  value        = random_password.dc_admin.result
  key_vault_id = azurerm_key_vault.lab.id
  depends_on   = [azurerm_role_assignment.kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "client_admin_password" {
  count        = var.deploy_test_client ? 1 : 0
  name         = "client-local-admin-password"
  value        = random_password.client_admin[0].result
  key_vault_id = azurerm_key_vault.lab.id
  depends_on   = [azurerm_role_assignment.kv_secrets_officer]
}
