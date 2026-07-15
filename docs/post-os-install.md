# Post-OS install checklist

Install **Alpine Linux Standard x86_64** in `sys` mode on the HP t520.

## 1. First login

Login as root on console.

```sh
setup-alpine
```

Recommended values:

```text
hostname: edge-monitor-01
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

## 6. Configure pve02 -> edge sync

```sh
cp config/adguardhome-sync.yaml.example /etc/adguardhome-sync/adguardhome-sync.yaml
vi /etc/adguardhome-sync/adguardhome-sync.yaml
chmod 600 /etc/adguardhome-sync/adguardhome-sync.yaml
rc-service adguardhome-sync restart
```

## 7. Verify

```sh
edge-status
nslookup example.com 127.0.0.1
```

Only after verification should DHCP/router clients be pointed at this box as main DNS.
