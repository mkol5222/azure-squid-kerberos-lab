# Phase 2 of DC bootstrap. Runs after Terraform's time_sleep buffer, once
# AD DS / DNS Server are confirmed up post-reboot. Adds:
#   - a conditional forwarder to Azure's recursive DNS (168.63.129.16) so
#     the DC (and everything pointed at it for DNS) can still resolve the
#     public internet for package/update downloads
#   - A/PTR records for the Squid proxy and (optionally) the test client,
#     since those machines are not doing a full Windows-style domain join
#     with dynamic DNS registration
#
# Dynamic values arrive as environment variables set by Terraform in
# domain-controller.tf; this file itself is plain, untemplated PowerShell.

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path "C:\AzureData" | Out-Null
Start-Transcript -Path "C:\AzureData\finalize-dc.log" -Append
Write-Output "=== finalize-dc.ps1 started $(Get-Date -Format o) ==="

if (-not $env:LAB_DOMAIN_NAME -or -not $env:LAB_PROXY_HOSTNAME -or -not $env:LAB_PROXY_IP) {
    throw "Required environment variables are missing (LAB_DOMAIN_NAME / LAB_PROXY_HOSTNAME / LAB_PROXY_IP)."
}

Import-Module DnsServer
Import-Module ActiveDirectory

Write-Output "Ensuring Azure DNS (168.63.129.16) is a forwarder for external resolution..."
$existingForwarders = (Get-DnsServerForwarder).IPAddress.IPAddressToString
if ($existingForwarders -notcontains "168.63.129.16") {
    Add-DnsServerForwarder -IPAddress "168.63.129.16"
}

Write-Output "Creating A/PTR record: $($env:LAB_PROXY_HOSTNAME).$($env:LAB_DOMAIN_NAME) -> $($env:LAB_PROXY_IP)"
Remove-DnsServerResourceRecord -ZoneName $env:LAB_DOMAIN_NAME -Name $env:LAB_PROXY_HOSTNAME -RRType A -Force -ErrorAction SilentlyContinue
Add-DnsServerResourceRecordA -ZoneName $env:LAB_DOMAIN_NAME -Name $env:LAB_PROXY_HOSTNAME -IPv4Address $env:LAB_PROXY_IP -CreatePtr

if ($env:LAB_CLIENT_HOSTNAME -and $env:LAB_CLIENT_IP) {
    Write-Output "Creating A/PTR record: $($env:LAB_CLIENT_HOSTNAME).$($env:LAB_DOMAIN_NAME) -> $($env:LAB_CLIENT_IP)"
    Remove-DnsServerResourceRecord -ZoneName $env:LAB_DOMAIN_NAME -Name $env:LAB_CLIENT_HOSTNAME -RRType A -Force -ErrorAction SilentlyContinue
    Add-DnsServerResourceRecordA -ZoneName $env:LAB_DOMAIN_NAME -Name $env:LAB_CLIENT_HOSTNAME -IPv4Address $env:LAB_CLIENT_IP -CreatePtr
}

Write-Output "--- Domain health check ---"
Get-ADDomain | Format-List DNSRoot, NetBIOSName, DomainMode
Get-Service DNS, NTDS, Netlogon | Format-Table Name, Status -AutoSize

Write-Output "=== finalize-dc.ps1 completed $(Get-Date -Format o) ==="
Stop-Transcript
