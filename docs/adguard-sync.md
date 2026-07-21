# Tiny Edge DNS synchronization

Tiny Edge (`tiny01.stoffy.lan`, `192.168.101.126`) is the **adguardhome-sync controller** and the main client-facing DNS server. It is not the configuration authority.

```text
pve02 CT201 / 10.0.0.201 (source of truth)
                    |
                    v
       Tiny Edge adguardhome-sync controller
          |              |                |
          v              v                v
 local AdGuard      pve CT101       TrueNAS AdGuard
 127.0.0.1          10.0.0.102      192.168.101.140:30004
```

This is deliberately one-way. Make policy changes on pve02 CT201; Tiny Edge distributes them every five minutes. DHCP and TLS synchronization stay disabled.

## Cutover

1. Copy `config/adguardhome-sync.yaml.example` to `/etc/adguardhome-sync/adguardhome-sync.yaml`.
2. Add each endpoint's real credentials, remove/comment any unavailable replica, and `chmod 600` the file.
3. Stop and disable the old CT201 sync service so two controllers do not overlap.
4. On Tiny Edge, run exactly one foreground sync (the explicit empty `--cron` overrides the file's recurring schedule):

   ```sh
   doas adguardhome-sync run --config /etc/adguardhome-sync/adguardhome-sync.yaml --cron "" --api-port 0
   ```

5. Inspect the command result, every intended replica, and direct DNS queries. Do not approve recurring sync while any intended target is unavailable or credentials remain placeholders.
6. Install the exact approval marker and enable/start Tiny's recurring service:

   ```sh
   printf '%s\n' 'ADGUARD_SYNC_CUTOVER_APPROVED=true' | doas tee /etc/adguardhome-sync/recurring-sync-cutover-approved >/dev/null
   doas chmod 600 /etc/adguardhome-sync/recurring-sync-cutover-approved
   doas rc-update add adguardhome-sync default
   doas rc-service adguardhome-sync start
   ```

7. Verify the next scheduled run and query Tiny Edge DNS:

   ```sh
   doas tail -n 100 /var/log/adguardhome-sync.log
   nslookup example.com 127.0.0.1
   ```

If a replica is intentionally offline, `continueOnError: true` lets remaining replicas synchronize. The web API remains disabled (`port: 0`).
