# Stoffberg Tiny Edge

Alpine bootstrap and operations for `tiny01.stoffy.lan` (`192.168.101.126`).

## Intended topology after explicit cutovers

The example configuration is fail-safe: Beszel and Cloudflared default to disabled, and recurring DNS synchronization remains disabled until credentials, one-shot validation, and owner approval are complete.

```text
Tiny Edge
  - Main client-facing DNS: AdGuard Home
  - DNS sync controller: pulls pve02 CT201 source and fans out to replicas
  - Cloudflare Tunnel connector: outbound-only Docker service
  - Beszel Agent
  - Conservative weekly cleanup
```

pve02 CT201 remains the AdGuard configuration source of truth. Tiny Edge is the controller and primary client DNS, not the policy authority.

## Install

Inspect first:

```sh
curl -fsSL https://raw.githubusercontent.com/MStoffberg/stoffberg-edge-monitor/main/install.sh -o /tmp/edge-install.sh
sed -n '1,240p' /tmp/edge-install.sh
sh /tmp/edge-install.sh
```

Or run directly on Alpine:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/MStoffberg/stoffberg-edge-monitor/main/install.sh)"
```

The firewall is not enabled until owner access is proven. Keep one SSH session open and test another before running `ENABLE_FIREWALL=true edge-lockdown`.

## Cloudflared cutover

For the staged two-phase migration, first move the credential into a root-only staging path, then run the cutover:

```sh
# The source file is temporary; never commit it.
doas install -m 600 -o root -g root /home/keiki/.cloudflared-token.env /root/cloudflared-token.env
rm -f /home/keiki/.cloudflared-token.env
doas sh scripts/apply-tiny-cutover.sh /root/cloudflared-token.env
```

Phase one transactionally installs/reconciles Cloudflared and Beszel only when Beszel has been explicitly enabled with complete Hub credentials. It leaves the firewall untouched. Verify public routes, WebSocket, Tiny Cloudflared stability, and—if enabled—Beszel Hub registration before disabling/removing the old connector. The installer preserves any replaced containers with `-before-edge-<timestamp>` names as rollback material; after external verification, inspect them with `docker ps -a --format '{{.Names}}'` and remove only the exact old names with `docker rm <name>`. The credential file must contain `TUNNEL_TOKEN=<token>`; the cutover requires a root-owned mode-`0600` regular file in a root-owned mode-`0700` directory, rejects symlinks, copies from an already-open descriptor, and removes the staging file after success.

## DNS sync

Copy `config/adguardhome-sync.yaml.example` to `/etc/adguardhome-sync/adguardhome-sync.yaml`, add credentials, remove or disable every currently unreachable replica, stop the old CT201 controller, and run the documented one-shot check. Only after every intended replica passes should you install the exact recurring-sync approval marker and enable the Tiny service. See `docs/adguard-sync.md`.

## Maintenance

```sh
edge-status
edge-update
edge-cleanup          # dry run
edge-cleanup --apply  # explicit cleanup
```

Explicit cleanup always performs bounded APK-cache, known installer-temp, aged temporary-file, and rotated-log cleanup. Docker image/build-cache pruning is additionally disk-threshold-gated. It never removes active/stopped containers or volumes.

## Firewall LAN ports

| Port | Purpose |
|---|---|
| 22/tcp | SSH |
| 53/tcp+udp | DNS |
| 3000/tcp | AdGuard UI |
| 45876/tcp | Beszel agent |

Cloudflared needs outbound HTTPS/QUIC access; it does not need an inbound port.
