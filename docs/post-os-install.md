# Post-OS install checklist

Install **Alpine Linux Standard x86_64** in `sys` mode on the HP t520.

## 1. First login

Login as root on console.

```sh
setup-alpine
```

Recommended values:

```text
hostname: tiny01.stoffy.lan
ssh: openssh
disk mode: sys
```

## 2. Pull this public repo

```sh
apk add --no-cache git ca-certificates curl
cd /root
git clone https://github.com/MStoffberg/stoffberg-edge-monitor.git
cd stoffberg-edge-monitor
```

## 3. Local config

```sh
cp config/edge-monitor.env.example /etc/edge-monitor.env
vi /etc/edge-monitor.env
```

If you have your SSH public key, put it in `SSH_AUTHORIZED_KEYS` before bootstrap.

## 4. Bootstrap

```sh
sh scripts/bootstrap-alpine.sh
```

## 5. Complete AdGuard Home wizard

Open:

```text
http://<edge-ip>:3000
```

Use a strong admin password. Do not commit it.

## 6. Configure Tiny Edge DNS fan-out

Tiny Edge runs adguardhome-sync, pulling the authoritative configuration from pve02 CT201 and distributing it to the configured replicas:

```sh
cp config/adguardhome-sync.yaml.example /etc/adguardhome-sync/adguardhome-sync.yaml
vi /etc/adguardhome-sync/adguardhome-sync.yaml
chmod 600 /etc/adguardhome-sync/adguardhome-sync.yaml
# One write only: no scheduler and no API listener. Inspect every target first.
doas adguardhome-sync run --config /etc/adguardhome-sync/adguardhome-sync.yaml --cron "" --api-port 0
printf '%s\n' 'ADGUARD_SYNC_CUTOVER_APPROVED=true' | doas tee /etc/adguardhome-sync/recurring-sync-cutover-approved >/dev/null
doas chmod 600 /etc/adguardhome-sync/recurring-sync-cutover-approved
doas rc-update add adguardhome-sync default
doas rc-service adguardhome-sync start
```

## 7. Verify

```sh
edge-status
nslookup example.com 127.0.0.1
```

Only after verification should DHCP/router clients be pointed at this box as main DNS.
