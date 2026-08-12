# Phase 1 of DC bootstrap: install AD-Domain-Services and promote this
# server to be the first domain controller of a new forest. Terraform runs
# this as CSE #1; a time_sleep buffer plus CSE #2 (finalize-dc.ps1) wait
# for the reboot that Install-ADDSForest triggers before doing anything
# that depends on AD/DNS actually being up.
#
# Dynamic values come in as environment variables (LAB_DOMAIN_NAME,
# LAB_NETBIOS_NAME, LAB_ADMIN_PASSWORD) set by a small wrapper Terraform
# builds in domain-controller.tf. This file itself is plain, untemplated
# PowerShell.

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path "C:\AzureData" | Out-Null
Start-Transcript -Path "C:\AzureData\promote-dc.log" -Append

Write-Output "=== promote-dc.ps1 started $(Get-Date -Format o) ==="

if (-not $env:LAB_DOMAIN_NAME -or -not $env:LAB_NETBIOS_NAME -or -not $env:LAB_ADMIN_PASSWORD) {
    throw "Required environment variables are missing (LAB_DOMAIN_NAME / LAB_NETBIOS_NAME / LAB_ADMIN_PASSWORD)."
}

$securePwd = ConvertTo-SecureString -String $env:LAB_ADMIN_PASSWORD -AsPlainText -Force

Write-Output "Installing AD-Domain-Services feature..."
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

Import-Module ADDSDeployment

Write-Output "Promoting to a new forest: $($env:LAB_DOMAIN_NAME) / $($env:LAB_NETBIOS_NAME)"
Install-ADDSForest `
    -DomainName $env:LAB_DOMAIN_NAME `
    -DomainNetbiosName $env:LAB_NETBIOS_NAME `
    -SafeModeAdministratorPassword $securePwd `
    -InstallDns:$true `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:$true `
    -NoRebootOnCompletion:$false

Write-Output "=== promote-dc.ps1 issued forest creation; the VM will now reboot to complete promotion ==="
Stop-Transcript
