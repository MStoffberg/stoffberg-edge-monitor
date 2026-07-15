# Security model

This box is intended to be **local network only**.

## Hardened by bootstrap

- SSH root login disabled.
- Public-key SSH supported.
- Password SSH disabled automatically only if a public key was provided.
- `doas` enabled for the admin user via `wheel` group.
- `nftables` default inbound drop policy.
- LAN-only inbound access to SSH, DNS, AdGuard UI, and Kuma.
- No public reverse proxy or Cloudflare Tunnel configured by default.
- adguardhome-sync API disabled by default.

## Allowed inbound services

From configured `LAN_CIDRS` only:

- TCP 22 SSH
- TCP/UDP 53 DNS
- TCP 3000 AdGuard Home UI/setup
- TCP 3001 Uptime Kuma

## Secrets

Never commit:

- AdGuard admin password
- pve02 AdGuard credentials
- local AdGuard credentials
- SSH private keys
- Cloudflare tokens

Store real sync credentials in:

```text
/etc/adguardhome-sync/adguardhome-sync.yaml
```

with:

```sh
chmod 600 /etc/adguardhome-sync/adguardhome-sync.yaml
```

## Still manual

- Router/DHCP changes are not automated here.
- This repo does not expose the device publicly.
- Uptime Kuma admin user is created in the web UI after first start.
