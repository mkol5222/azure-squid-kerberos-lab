locals {
  # Kerberos realms for AD are conventionally the uppercase DNS domain name.
  realm = upper(var.domain_name)

  # "lab.contoso.local" -> "DC=lab,DC=contoso,DC=local"
  domain_dn    = join(",", [for part in split(".", var.domain_name) : "DC=${part}"])
  computers_dn = "CN=Computers,${local.domain_dn}"

  dc_computer_name     = "dc1"
  dc_fqdn              = "${local.dc_computer_name}.${var.domain_name}"
  proxy_fqdn           = "${var.proxy_hostname}.${var.domain_name}"
  client_computer_name = substr(var.client_hostname, 0, 15)
  client_fqdn          = "${local.client_computer_name}.${var.domain_name}"

  # UPN used to kinit as the lab admin. This is the custom local-admin
  # account (var.local_admin_username), NOT the built-in "Administrator"
  # account -- Azure forbids "administrator" as a VM-creation-time admin
  # username, so the built-in SID-500 account is never given a known
  # password here. dcpromo carries local Administrators-group members
  # (which includes this account) into Domain Admins during promotion.
  domain_admin_upn = "${var.local_admin_username}@${local.realm}"

  name_suffix = "${var.project_name}-${random_string.suffix.result}"

  tags = var.tags
}
