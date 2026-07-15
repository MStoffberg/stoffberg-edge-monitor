# AdGuard sync direction

The HP t520 is allowed to be the main DNS server for clients, but not the config source of truth.

Source of truth:

```text
pve02 CT201 AdGuard Home: http://10.0.0.201:3000
```

Target replica:

```text
edge-monitor-01 HP t520: http://127.0.0.1:3000
```

Sync direction:

```text
10.0.0.201 ---> edge-monitor-01
```

## Why this direction?

- pve02 already holds the known-good AdGuard config.
- HP t520 can serve clients as primary DNS.
- If the HP is reinstalled, it can pull the same config again.
- Avoids accidentally overwriting pve02 with a fresh/empty HP config.

## First sync steps

1. Complete the HP AdGuard setup wizard.
2. Create/use a local HP AdGuard admin account.
3. Copy the example sync YAML to `/etc/adguardhome-sync/adguardhome-sync.yaml`.
4. Fill in pve02 and local credentials.
5. Restart the service.
6. Verify AdGuard settings on the HP match pve02.

```sh
rc-service adguardhome-sync restart
tail -n 100 /var/log/adguardhome-sync.log
```
