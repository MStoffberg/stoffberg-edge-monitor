# Security model

Tiny Edge is an outbound edge connector and LAN infrastructure host. It opens no router port forwards.

## Inbound LAN services

From configured `LAN_CIDRS` only:

- TCP 22: SSH
- TCP/UDP 53: AdGuard DNS
- TCP 3000: AdGuard administration
- TCP 45876: Beszel agent

Cloudflared makes outbound-only encrypted connections to Cloudflare.

## Access safety

- Root SSH is disabled.
- Password SSH is disabled only after a public key is proven.
- Firewall activation remains explicit; test a second SSH session before lockdown.
- `doas` provides named owner escalation.

## Secrets

Never commit AdGuard credentials, Cloudflare tokens, Beszel credentials, private keys, or backup databases.

- DNS sync credentials: `/etc/adguardhome-sync/adguardhome-sync.yaml` (`0600`)
- Tunnel token: `/etc/cloudflared/token.env` (`0600`), formatted as `TUNNEL_TOKEN=...`
- Local host settings: `/etc/edge-monitor.env` (`0600`)

The Cloudflare route is remotely managed. Publish only explicitly approved hostnames; do not expose SSH, AdGuard, Beszel, Proxmox, or other administration surfaces.

## Cleanup boundaries

`edge-cleanup` is dry-run by default. Its apply mode never prunes Docker containers or volumes and never uses `docker system prune`. Build-cache cleanup is separately disabled by default.
