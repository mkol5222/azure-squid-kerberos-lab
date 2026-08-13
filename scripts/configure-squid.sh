#!/bin/bash
# Configures Squid to authenticate proxy users via Kerberos/SPNEGO against
# an Active Directory domain, following
# https://wiki.squid-cache.org/ConfigExamples/Authenticate/Kerberos
#
# This file is intentionally a *plain* script (no Terraform templating).
# All dynamic values are passed in as LAB_* environment variables by the
# small wrapper that Terraform builds in squid-proxy.tf, so this file's
# native bash ${VAR} syntax never collides with Terraform's own ${...}
# interpolation syntax.
#
# Deviations from the wiki example, and why:
#  - Encryption is AES-only (--enctypes 24, aes256/aes128 in krb5.conf).
#    The wiki's krb5.conf example uses rc4-hmac/des-cbc-* for Windows 2003
#    compatibility; Check Point's Data Protection Policy prohibits RC4/DES/
#    3DES/MD5/SHA-1, and this lab's DC is Windows Server 2022, which has no
#    need for legacy enctypes.
#  - Uses msktutil (the wiki's first/recommended method) rather than
#    Samba net ads, since winbind is not installed here and the wiki
#    explicitly warns net ads keytab is unsafe to combine with winbindd.
#  - Helper path is /usr/lib/squid/negotiate_kerberos_auth (Ubuntu), not
#    the wiki's /usr/sbin/squid_kerb_auth (that name is the pre-rename
#    helper binary, and the Ubuntu package installs it under /usr/lib/squid).

set -euo pipefail
exec > >(tee -a /var/log/configure-squid.log) 2>&1
echo "=== configure-squid.sh started $(date -u -Iseconds) ==="

: "${LAB_DOMAIN_NAME:?LAB_DOMAIN_NAME not set}"
: "${LAB_REALM:?LAB_REALM not set}"
: "${LAB_DC_FQDN:?LAB_DC_FQDN not set}"
: "${LAB_DC_IP:?LAB_DC_IP not set}"
: "${LAB_PROXY_FQDN:?LAB_PROXY_FQDN not set}"
: "${LAB_COMPUTERS_DN:?LAB_COMPUTERS_DN not set}"
: "${LAB_DOMAIN_ADMIN_UPN:?LAB_DOMAIN_ADMIN_UPN not set}"
: "${LAB_DOMAIN_ADMIN_PASSWORD:?LAB_DOMAIN_ADMIN_PASSWORD not set}"
: "${LAB_MSKTUTIL_COMPUTER_NAME:=squid-http}"

export DEBIAN_FRONTEND=noninteractive

echo "--- Installing packages ---"
add-apt-repository -y universe || true
apt-get update -y
apt-get install -y squid krb5-user msktutil libsasl2-modules-gssapi-mit libsasl2-modules chrony

echo "--- Bypassing systemd-resolved's stub for DNS (see why below) ---"
# $LAB_DOMAIN_NAME ends in .local, which RFC 6762 reserves for multicast
# DNS. Ubuntu's systemd-resolved hard-routes any *.local query to its mDNS
# resolver only -- never to the real unicast DNS server configured for the
# link -- regardless of what /etc/resolv.conf or `resolvectl dns` say. mDNS
# is disabled on this link (and the DC doesn't speak it anyway), so every
# *.local lookup via the normal glibc/NSS path (getaddrinfo, and therefore
# kinit/msktutil) silently fails with EAI_AGAIN, which krb5 reports as
# "Resource temporarily unavailable" -- even though the DC's DNS server
# itself answers fine (confirmed with `dig @<dc-ip>`, which talks to it
# directly and bypasses the stub). Disabling the stub listener and
# symlinking /etc/resolv.conf to resolved's own "uplink" file (the plain
# nameserver list it learned via DHCP) restores normal DNS behavior with
# no mDNS special-casing.
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/no-stub.conf <<RESOLVEDEOF
[Resolve]
DNSStubListener=no
RESOLVEDEOF
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
getent ahosts "$LAB_DC_FQDN"

echo "--- Time sync against the DC (Kerberos needs clocks within ~5 minutes) ---"
mkdir -p /etc/chrony/conf.d
cat >/etc/chrony/conf.d/lab-dc.conf <<CHRONYEOF
server $LAB_DC_IP iburst
CHRONYEOF
systemctl restart chrony
sleep 5
chronyc tracking || true
chronyc makestep || true

echo "--- Writing /etc/krb5.conf (AES-only, no RC4/DES per Check Point Data Protection Policy) ---"
cat >/etc/krb5.conf <<KRB5EOF
[libdefaults]
    default_realm = $LAB_REALM
    dns_lookup_realm = false
    dns_lookup_kdc = true
    rdns = false
    default_tgs_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
    default_tkt_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
    permitted_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96

[realms]
    $LAB_REALM = {
        kdc = $LAB_DC_FQDN
        admin_server = $LAB_DC_FQDN
        default_domain = $LAB_DOMAIN_NAME
    }

[domain_realm]
    .$LAB_DOMAIN_NAME = $LAB_REALM
    $LAB_DOMAIN_NAME = $LAB_REALM

[logging]
    default = FILE:/var/log/krb5lib.log
KRB5EOF

echo "--- Obtaining a TGT for the lab admin account (used only to create the AD computer object + keytab) ---"
echo "$LAB_DOMAIN_ADMIN_PASSWORD" | kinit "$LAB_DOMAIN_ADMIN_UPN"
klist

echo "--- Creating AD computer object + keytab with msktutil (AES only via --enctypes 24) ---"
mkdir -p /etc/squid
msktutil --create \
  --base "$LAB_COMPUTERS_DN" \
  --service "HTTP/$LAB_PROXY_FQDN" \
  --hostname "$LAB_PROXY_FQDN" \
  --keytab /etc/squid/HTTP.keytab \
  --computer-name "$LAB_MSKTUTIL_COMPUTER_NAME" \
  --upn "HTTP/$LAB_PROXY_FQDN" \
  --server "$LAB_DC_FQDN" \
  --enctypes 24 \
  --verbose

kdestroy || true

chown root:proxy /etc/squid/HTTP.keytab
chmod 640 /etc/squid/HTTP.keytab

echo "--- Verifying the keytab contents ---"
KRB5_KTNAME=/etc/squid/HTTP.keytab klist -k

echo "--- Writing squid.conf ---"
[ -f /etc/squid/squid.conf ] && cp /etc/squid/squid.conf /etc/squid/squid.conf.orig.bak
cat >/etc/squid/squid.conf <<SQUIDEOF
# Kerberos/SPNEGO authentication - see
# https://wiki.squid-cache.org/ConfigExamples/Authenticate/Kerberos
auth_param negotiate program /usr/lib/squid/negotiate_kerberos_auth -k /etc/squid/HTTP.keytab -s HTTP/$LAB_PROXY_FQDN@$LAB_REALM
auth_param negotiate children 10
auth_param negotiate keep_alive on

acl kerb_auth proxy_auth REQUIRED

acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl Safe_ports port 21
acl Safe_ports port 3128
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access deny !kerb_auth
http_access allow kerb_auth
http_access deny all

http_port 3128

cache_dir ufs /var/spool/squid 100 16 256
coredump_dir /var/spool/squid
SQUIDEOF

echo "--- systemd drop-in so squid.service always has KRB5_KTNAME set ---"
mkdir -p /etc/systemd/system/squid.service.d
cat >/etc/systemd/system/squid.service.d/override.conf <<OVERRIDEEOF
[Service]
Environment=KRB5_KTNAME=/etc/squid/HTTP.keytab
OVERRIDEEOF

systemctl daemon-reload
systemctl enable squid
systemctl restart squid
sleep 3
systemctl --no-pager status squid || true

echo "--- Scheduling msktutil auto-update (AD machine password rotates ~every 30 days) ---"
cat >/etc/cron.d/msktutil-autoupdate <<CRONEOF
0 3 * * * root KRB5_KTNAME=/etc/squid/HTTP.keytab msktutil --auto-update --verbose >> /var/log/msktutil-autoupdate.log 2>&1
CRONEOF

echo "=== configure-squid.sh finished $(date -u -Iseconds) ==="
