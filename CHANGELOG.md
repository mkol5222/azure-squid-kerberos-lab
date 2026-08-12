# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Lowered the `required_version` constraint in `versions.tf` (and the
  README prerequisite) from `>= 1.7.0` to `>= 1.5.0`, since Homebrew's
  `terraform` formula is frozen at 1.5.7 (last MPL-licensed release before
  HashiCorp's BUSL change) and won't update further via `brew upgrade`.
- Renamed `azurerm_key_vault.lab`'s `enable_rbac_authorization` argument to
  `rbac_authorization_enabled`, following the azurerm provider's deprecation
  notice ahead of its removal in v5.0.
- Updated the default test-client image SKU (`var.client_image`) from
  `win11-23h2-pro` to `win11-25h2-pro`, since Microsoft retired the plain
  `-pro` SKU for the 23h2 release (only `-avd`/`-ent`/`-entn` variants remain
  for 23h2; 24h2/25h2 carry the current `-pro` SKU).

### Fixed

- Replaced `azurerm_virtual_machine_extension.dc_finalize` with
  `azurerm_virtual_machine_run_command.dc_finalize` in
  `domain-controller.tf`. Windows VMs only support one
  `Microsoft.Compute.CustomScriptExtension` handler at a time, and
  `dc_promote` already occupied it, so applying a second extension of the
  same type on `vm-dc1` failed with `BadRequest: Multiple VMExtensions per
  handler not supported for OS type 'Windows'`. VM Run Command has no such
  restriction and accepts the script directly, removing the need for the
  base64/write-file wrapper.
- `scripts/finalize-dc.ps1` failed on a clean DC with `Remove-DnsServerResourceRecord
  : Failed to get ... record` and aborted the whole script. That cmdlet
  throws a `CimException` when the record doesn't exist yet, which
  `-ErrorAction SilentlyContinue` does not suppress (a known `DnsServer`
  module quirk); combined with `$ErrorActionPreference = "Stop"` this
  killed the script on first run, before any record existed to remove.
  Replaced both `-ErrorAction SilentlyContinue` remove calls with
  `try`/`catch`, which reliably catches the exception.
- `scripts/finalize-dc.ps1` then failed on `Add-DnsServerResourceRecordA
  -CreatePtr` with `Failed to create PTR record`. `Install-ADDSForest`
  only creates the forward lookup zone, never a reverse one, so
  `-CreatePtr` had no reverse zone to place the PTR record in. Added
  `Ensure-ReverseZone`, which creates the `/24` reverse zone for each
  target IP (derived from its first three octets, matching this lab's
  fixed `/24` subnetting) before the A/PTR record is created.
- The Squid VM's `configure-squid-kerberos` extension failed with
  `kinit: Resource temporarily unavailable` (Kerberos over UDP/88 timing
  out, not erroring cleanly). Root cause: a brand-new forest's first DC
  often stays classified as network category `Public` after the
  post-promotion reboot, since Network Location Awareness needs a
  reachable DC to detect a domain and this machine only just became one.
  Stuck on `Public`, Windows Firewall's default rules silently drop
  inbound AD DS/Kerberos traffic from other subnets. Added a step to
  `finalize-dc.ps1` that forces the network profile to `Private` and
  enables the `Active Directory Domain Services`/`DNS Service` firewall
  rule groups for all profiles.
