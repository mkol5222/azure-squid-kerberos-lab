# Azure Squid + Kerberos (SPNEGO) Proxy Lab

Terraform that stands up a self-contained Azure lab for testing Squid's
Kerberos/Negotiate proxy authentication against a real Active Directory
domain, per the
[Squid wiki's Kerberos config example](https://wiki.squid-cache.org/ConfigExamples/Authenticate/Kerberos).

```
Azure Bastion (AzureBastionSubnet, 10.60.10.0/26)
  -> only path in: RDP to the DC/client, SSH to the proxy
  -> no VM below has a public IP

   ┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
   │ snet-dc             │ │ snet-proxy          │ │ snet-client         │
   │ 10.60.1.0/24        │ │ 10.60.2.0/24        │ │ 10.60.3.0/24 (opt)  │
   │                     │ │                     │ │                     │
   │ vm-dc1              │ │ vm-proxy            │ │ vm-client1          │
   │ Windows Server 2022 │ │ Ubuntu 24.04        │ │ Windows 11          │
   │ AD DS + DNS         │ │ Squid + msktutil    │ │ domain-joined       │
   │ 10.60.1.4           │ │ 10.60.2.4           │ │ 10.60.3.4           │
   └─────────────────────┘ └─────────────────────┘ └─────────────────────┘
```

The Squid VM is **not** domain-joined. `msktutil` talks to AD over
LDAP/Kerberos directly to create a computer object (`squid-http`) and a
keytab, which is all Kerberos/SPNEGO auth needs — no realmd/sssd/winbind.

## What gets created

| File | Purpose |
|---|---|
| `versions.tf` | Provider version pins (see "Why azurerm is pinned to 4.81" below) |
| `variables.tf` / `locals.tf` | All inputs, with validation, and computed names (realm, DNs, FQDNs) |
| `network.tf` | Resource group, VNet, subnets, NSGs |
| `bastion.tf` | Azure Bastion (default path to every VM) |
| `keyvault.tf` | Key Vault + generated passwords |
| `domain-controller.tf` | The DC VM and its two-phase promotion |
| `squid-proxy.tf` | The Squid VM and its Kerberos setup |
| `test-client.tf` | Optional Windows 11 client for end-to-end testing |
| `outputs.tf` | IPs, FQDNs, and ready-to-run `az network bastion` commands |
| `scripts/*.sh`, `scripts/*.ps1` | The actual provisioning logic, kept as plain files (see below) |

## Prerequisites

- Terraform >= 1.5.0
- An Azure subscription and `az login` (or another auth method Terraform's
  azurerm provider supports — see "Authenticating Terraform to Azure" below)
- An SSH key pair for the Squid VM (`ssh-keygen -t ed25519`) — you'll pass
  the **public** key content as a variable; there is no password login on
  that VM at all
- `terraform fmt`, `terraform init`, and `terraform validate` were **not**
  run against this configuration before delivery — the sandbox that built
  it has no network access to download providers. Run all three yourself
  before `plan`/`apply`. Every file was hand-reviewed for HCL syntax, but
  that's a poor substitute for the real parser.

## Security design notes (and why)

This lab handles credentials for a real (if disposable) AD forest, so it's
built the way Check Point's internal policies require production
infrastructure to be built, not loosened because it's "just a lab":

- **No public IP on any VM, ever.** Azure Bastion (`deploy_bastion`,
  default `true`) is the only path in. There's deliberately no
  public-IP-plus-restricted-NSG fallback variable — Check Point's Network
  Security Policy prohibits exposing admin ports like RDP/SSH externally,
  with no exception clause, so that option isn't offered here at all. If
  you already have private connectivity into this VNet (VPN, ExpressRoute,
  peering), you can set `deploy_bastion = false`, but nothing will put a
  public IP on a VM as an alternative.
- **Real micro-segmentation, not just a perimeter.** Azure attaches a
  default `AllowVnetInBound` rule (priority 65000) to every NSG, which
  would otherwise let any subnet reach any other subnet on any port. Each
  NSG here adds an explicit `Deny-VnetInBound-Override` rule (priority
  4096) plus specific allows above it, so e.g. the client subnet can reach
  the DC's domain-join ports but the proxy subnet can't.
- **No hardcoded secrets anywhere.** VM admin passwords are generated with
  `random_password`, injected only via each VM extension's
  `protected_settings` (which Azure encrypts and excludes from extension
  status/logs), and mirrored to Key Vault for you to retrieve after the
  fact. No script file contains a real password — the `.ps1`/`.sh` files
  in `scripts/` are static and read secrets only from environment
  variables set at run time.
- **AES-only Kerberos**, not the wiki's RC4/DES example — see "Deviations
  from the wiki page" below.
- **Trusted Launch** (Secure Boot + vTPM) on every VM, at no extra cost on
  the Gen2 images used here. This is good practice, not something any
  specific policy mandated for a lab.
- **Encryption at rest** on all OS disks via Azure Storage Service
  Encryption (AES-256), which is on by default and not something you can
  turn off — nothing to configure, just noting it's there.

### Terraform state will contain secrets in plaintext

`random_password.dc_admin` and `random_password.client_admin` end up in
Terraform state unencrypted, because Terraform state always contains
resource attribute values in plaintext. Local state (the default) is fine
to get started, but before you treat this as anything other than a
throwaway `terraform destroy`-tonight lab, move to a remote backend. A
commented-out example is in `versions.tf`:

```hcl
backend "azurerm" {
  resource_group_name  = "rg-tfstate"
  storage_account_name = "<globally-unique-name>"
  container_name       = "tfstate"
  key                  = "squid-kerberos-lab.tfstate"
  use_azuread_auth     = true   # keyless access via your az login/OIDC identity
}
```

You have to create that storage account by some means outside this config
first (there's a chicken-and-egg problem in having Terraform manage the
backend it's also using), then uncomment the block and run
`terraform init -migrate-state`.

### Authenticating Terraform to Azure

Don't create a long-lived Service Principal secret for this. Run
`az login` interactively and Terraform's azurerm provider will pick up
your Azure CLI session automatically, or use Workload Identity/OIDC if
you're running this from a CI pipeline. Either way, nothing in this
config expects or reads a static client secret.

## Deploying

```bash
cd azure-squid-kerberos-lab
az login
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set domain_name, netbios_name, admin_ssh_public_key

terraform fmt
terraform init
terraform validate
terraform plan -out=lab.tfplan
terraform apply lab.tfplan
```

A full apply takes roughly 25-35 minutes — most of it is the DC's forest
promotion, its reboot, and the buffer Terraform waits afterward.

### Retrieving the generated passwords

```bash
KV=$(terraform output -raw key_vault_name)

az keyvault secret show --vault-name "$KV" --name dc-local-admin-password --query value -o tsv
az keyvault secret show --vault-name "$KV" --name client-local-admin-password --query value -o tsv
```

The DC password is also the domain admin password (dcpromo carries local
Administrators-group members — which includes `var.local_admin_username`,
not the built-in `Administrator` account — into Domain Admins) and the
account the Squid VM used to create its keytab.

### Connecting (Bastion only, no public IPs)

```bash
terraform output connect_via_bastion
```

prints ready-to-run `az network bastion rdp`/`ssh` commands for the DC,
proxy, and client. You can also click **Connect > Bastion** on any VM in
the Azure Portal.

## Testing Kerberos SSO end-to-end

With `deploy_test_client = true` (the default), `vm-client1` is already
domain-joined. From that VM, as a domain user:

1. Set the browser/system proxy to `<proxy_fqdn output>:3128` — **use the
   FQDN, not the IP.** SPNEGO is tied to the service principal name
   `HTTP/proxy.<domain>`; browsing via the raw `10.60.2.4` address will
   fail Kerberos and (depending on your browser) either prompt for
   basic auth or fail outright.
2. Browse to any external site through the proxy. You should get through
   with **no credential prompt**.
3. Confirm the ticket: open a command prompt and run
   ```
   klist
   ```
   You should see a ticket for `HTTP/proxy.<your-domain>`.

If you didn't deploy the test client, any domain-joined Windows machine
with proxy settings pointed at `proxy.<domain>:3128` and line-of-sight to
`snet-proxy` (e.g. via Bastion tunnel or peering) works the same way.

## Troubleshooting

- **Prompted for a password instead of SSO working.** Almost always time
  skew or DNS. Kerberos tickets are only valid within a small clock-skew
  window (conventionally 5 minutes); `configure-squid.sh` points the
  proxy's `chrony` at the DC, but if the *client's* clock has drifted,
  fix that first.
- **`klist -k` on the proxy shows no entries, or `kinit` failed during
  provisioning.** Check `/var/log/configure-squid.log` on the proxy VM
  (via Bastion SSH). The most common cause is the proxy VM's DNS not
  resolving the DC yet — confirm `nslookup <domain_name>` and
  `nslookup <dc_fqdn>` both work from the proxy first.
- **Browser gets a 407 loop or basic-auth prompt instead of SSO.** Usually
  means the browser isn't sending a Negotiate/SPNEGO header — check that
  the proxy is addressed by its FQDN (see above), and that the client's
  browser has that proxy FQDN allow-listed for integrated auth (Chrome/
  Edge on a domain-joined machine do this automatically via
  `AuthServerAllowlist`; standalone/non-domain browsers may not).
- **`Install-ADDSForest` extension times out or the DC never becomes
  reachable.** RDP in via Bastion and check
  `C:\AzureData\promote-dc.log` (`Start-Transcript` output) and Windows'
  own `%windir%\debug\dcpromo.log`.
- **PTR records didn't get created** by `finalize-dc.ps1`.
  `Add-DnsServerResourceRecordA -CreatePtr` needs a matching reverse
  lookup zone to already exist, and `Install-ADDSForest` doesn't create
  one automatically. Harmless for the Kerberos/SPNEGO flow itself (which
  doesn't depend on reverse DNS), but add a reverse zone yourself first if
  you want PTR records.
- **Something in `terraform apply` fails with a provider-schema-looking
  error.** Re-read the error against `~> 4.81` — if it's complaining about
  an argument this README doesn't mention, you may have a cached 5.x
  provider from another project; run `terraform init -upgrade=false` and
  confirm `terraform providers` shows a 4.8x version.

## Tearing down

```bash
terraform destroy
```

Key Vault has purge protection enabled, so the vault itself lingers in a
soft-deleted state for the retention window (7 days here) after destroy —
this is intentional (accidental-deletion protection) but means a
same-named Key Vault can't be recreated immediately. Purge it explicitly
if you need the name back sooner:

```bash
az keyvault purge --name <kv-name> --location <location>
```

## Deviations from the linked wiki page, and why

The wiki page is the right starting reference for the Squid side of this,
but a couple of its specifics are dated or conflict with Check Point's
internal security policies, so this config deviates on purpose:

| Wiki example | This lab | Why |
|---|---|---|
| `krb5.conf` permits `rc4-hmac`, `des-cbc-crc`, `des-cbc-md5` (Windows 2003-era compat) | AES-only: `aes256-cts-hmac-sha1-96`, `aes128-cts-hmac-sha1-96` | Check Point's Data Protection Policy prohibits RC4/DES/3DES/MD5/SHA-1 outright. The DC here is Server 2022, which has never needed those legacy enctypes. |
| Keytab creation shown via both `msktutil` and Samba `net ads keytab` | `msktutil` only, with `--enctypes 24` | The wiki itself flags `net ads keytab` as unsafe when winbind is running; `msktutil` is its own recommended path and is what's used here. |
| `auth_param negotiate program /usr/sbin/squid_kerb_auth ...` | `/usr/lib/squid/negotiate_kerberos_auth` | `squid_kerb_auth` is the pre-rename helper name; current Ubuntu Squid packages ship it as `negotiate_kerberos_auth` under `/usr/lib/squid/`. |

## Upgrading to azurerm 5.x

`versions.tf` pins `azurerm ~> 4.81` (the last 4.x line) rather than the
5.0 release that shipped 2026-07-27, because that jump is a breaking major
version (it stops auto-registering Azure Resource Providers, among other
changes) and this configuration's syntax hasn't been verified against it.
If you want to move to 5.x, read HashiCorp's own upgrade guide first:
<https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/5.0-upgrade-guide>,
then bump the version constraint and run `terraform plan` to see the diff
before applying.

## Why the provisioning scripts are plain files, not `templatefile()`

`scripts/*.sh` and `scripts/*.ps1` are read with `file()`, not
`templatefile()`, and every dynamic value is injected as an environment
variable by a small wrapper Terraform builds and prepends at apply time.
This is deliberate: these scripts' *own* native syntax
(bash `${VAR}`, `${VAR:?msg}`) is visually identical to Terraform's
interpolation syntax. `templatefile()` would try to evaluate those as
Terraform expressions and fail (or worse, silently do the wrong thing).
`file()` just reads bytes — no interpolation happens on the script content
itself, only on the small wrapper Terraform controls directly.
