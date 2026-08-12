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

# A brand-new forest's first DC often stays classified as "Public" by
# Network Location Awareness after the post-promotion reboot -- NLA needs
# a working DC to detect a domain, and this machine only just became one.
# Stuck on Public, Windows Firewall's default rules silently drop inbound
# AD DS/Kerberos traffic from other subnets (no RST/ICMP back), which
# looks like a timeout/EAGAIN ("Resource temporarily unavailable") to
# clients like kinit rather than a clean refusal. Force Private so the
# AD DS firewall rule group (which covers Kerberos/LDAP/DNS/etc.) applies.
Write-Output "Ensuring the network profile is Private and AD DS firewall rules are enabled..."
Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq "Public" } |
    Set-NetConnectionProfile -NetworkCategory Private
Get-NetFirewallRule -DisplayGroup "Active Directory Domain Services" |
    Set-NetFirewallRule -Profile Any -Enabled True
Get-NetFirewallRule -DisplayGroup "DNS Service" |
    Set-NetFirewallRule -Profile Any -Enabled True

Write-Output "Ensuring Azure DNS (168.63.129.16) is a forwarder for external resolution..."
$existingForwarders = (Get-DnsServerForwarder).IPAddress.IPAddressToString
if ($existingForwarders -notcontains "168.63.129.16") {
    Add-DnsServerForwarder -IPAddress "168.63.129.16"
}

# Install-ADDSForest only creates the forward lookup zone, never a reverse
# one -- Add-DnsServerResourceRecordA's -CreatePtr fails without a matching
# reverse zone to put the PTR record in. Every subnet in this lab is a
# /24 (see README's network diagram), so the zone for a given IP is
# derived from its first three octets.
function Ensure-ReverseZone {
    param([string]$IPv4Address)
    $octets = $IPv4Address.Split('.')
    $networkId = "$($octets[0]).$($octets[1]).$($octets[2]).0/24"
    $zoneName = "$($octets[2]).$($octets[1]).$($octets[0]).in-addr.arpa"
    $zoneExists = $true
    try {
        Get-DnsServerZone -Name $zoneName -ErrorAction Stop | Out-Null
    } catch {
        $zoneExists = $false
    }
    if (-not $zoneExists) {
        Write-Output "Creating reverse lookup zone $zoneName ($networkId)..."
        Add-DnsServerPrimaryZone -NetworkID $networkId -ReplicationScope "Forest"
    }
}

Write-Output "Creating A/PTR record: $($env:LAB_PROXY_HOSTNAME).$($env:LAB_DOMAIN_NAME) -> $($env:LAB_PROXY_IP)"
Ensure-ReverseZone -IPv4Address $env:LAB_PROXY_IP
# Remove-DnsServerResourceRecord throws a CimException (not a normal
# non-terminating error) when the record doesn't exist yet, so
# -ErrorAction SilentlyContinue can't suppress it -- only try/catch can.
try {
    Remove-DnsServerResourceRecord -ZoneName $env:LAB_DOMAIN_NAME -Name $env:LAB_PROXY_HOSTNAME -RRType A -Force -ErrorAction Stop
} catch {
    Write-Output "No existing A record for $($env:LAB_PROXY_HOSTNAME) to remove (first run) -- continuing."
}
Add-DnsServerResourceRecordA -ZoneName $env:LAB_DOMAIN_NAME -Name $env:LAB_PROXY_HOSTNAME -IPv4Address $env:LAB_PROXY_IP -CreatePtr

if ($env:LAB_CLIENT_HOSTNAME -and $env:LAB_CLIENT_IP) {
    Write-Output "Creating A/PTR record: $($env:LAB_CLIENT_HOSTNAME).$($env:LAB_DOMAIN_NAME) -> $($env:LAB_CLIENT_IP)"
    Ensure-ReverseZone -IPv4Address $env:LAB_CLIENT_IP
    try {
        Remove-DnsServerResourceRecord -ZoneName $env:LAB_DOMAIN_NAME -Name $env:LAB_CLIENT_HOSTNAME -RRType A -Force -ErrorAction Stop
    } catch {
        Write-Output "No existing A record for $($env:LAB_CLIENT_HOSTNAME) to remove (first run) -- continuing."
    }
    Add-DnsServerResourceRecordA -ZoneName $env:LAB_DOMAIN_NAME -Name $env:LAB_CLIENT_HOSTNAME -IPv4Address $env:LAB_CLIENT_IP -CreatePtr
}

Write-Output "--- Domain health check ---"
Get-ADDomain | Format-List DNSRoot, NetBIOSName, DomainMode
Get-Service DNS, NTDS, Netlogon | Format-Table Name, Status -AutoSize

Write-Output "=== finalize-dc.ps1 completed $(Get-Date -Format o) ==="
Stop-Transcript
