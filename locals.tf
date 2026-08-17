locals {
  # Kerberos realms for AD are conventionally the uppercase DNS domain name.
  realm = upper(var.domain_name)

  # Relative, not the full "CN=Computers,DC=lab,..." DN: msktutil's --base
  # only treats a value as absolute when it ends with the domain base DN
  # it computes internally, using its own case convention (observed as
  # e.g. "dc=LAB,dc=CONTOSO,dc=LOCAL" -- derived from the realm, not
  # var.domain_name). A full DN built with our own casing doesn't match
  # that string, so msktutil treats it as relative anyway and appends its
  # base DN a second time, producing an invalid doubled DN. A relative
  # base sidesteps the mismatch entirely.
  computers_dn = "CN=Computers"

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
