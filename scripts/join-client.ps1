# Joins the optional Windows 11 test client to the lab domain so it can be
# used to test Kerberos SSO through the Squid proxy end-to-end. Runs only
# if var.deploy_test_client = true, after the DC's DNS finalize step.
#
# Dynamic values arrive as environment variables set by Terraform in
# test-client.tf; this file itself is plain, untemplated PowerShell.

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path "C:\Windows\Temp" | Out-Null
Start-Transcript -Path "C:\Windows\Temp\join-client.log" -Append
Write-Output "=== join-client.ps1 started $(Get-Date -Format o) ==="

if (-not $env:LAB_DOMAIN_NAME -or -not $env:LAB_NETBIOS_NAME -or -not $env:LAB_DOMAIN_ADMIN_USERNAME -or -not $env:LAB_ADMIN_PASSWORD) {
    throw "Required environment variables are missing."
}

$securePwd = ConvertTo-SecureString -String $env:LAB_ADMIN_PASSWORD -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(
    "$($env:LAB_NETBIOS_NAME)\$($env:LAB_DOMAIN_ADMIN_USERNAME)",
    $securePwd
)

Write-Output "Joining domain $($env:LAB_DOMAIN_NAME) as $($env:LAB_NETBIOS_NAME)\$($env:LAB_DOMAIN_ADMIN_USERNAME)..."
Add-Computer -DomainName $env:LAB_DOMAIN_NAME -Credential $cred -Force -Restart

Write-Output "=== join-client.ps1 issued domain join; the VM will now reboot ==="
Stop-Transcript
