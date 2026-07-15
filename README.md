# Stoffberg Edge Monitor

Public bootstrap repo for the HP t520 / HPT520 thin client used as a **local-only DNS + monitoring appliance**.

Target hardware:

- HP t520 / HPT520
- 2 GB RAM
- 8 GB storage
- Alpine Linux Standard x86_64, installed in `sys` mode

Primary role:

```text
edge-monitor-01
  - Main LAN DNS: AdGuard Home
  - Monitoring: Uptime Kuma
  - SSH admin access
  - nftables firewall: LAN-only inbound
  - adguardhome-sync: pulls config from pve02 AdGuard Home
```

> Public repo rule: **no secrets live here**. Put passwords/API tokens only on the device in files under `/etc/*` with mode `600`.

## Quick start after Alpine OS install

On the HP t520, as `root`, use the Alpine-safe one-liner:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/MStoffberg/stoffberg-edge-monitor/main/install.sh)"
```

If you specifically want the Proxmox community-script style with `bash`, install bash first:

```sh
apk add --no-cache bash curl && bash -c "$(curl -fsSL https://raw.githubusercontent.com/MStoffberg/stoffberg-edge-monitor/main/install.sh)"
```

Optional safer inspect-first flow:

```sh
curl -fsSL https://raw.githubusercontent.com/MStoffberg/stoffberg-edge-monitor/main/install.sh -o /tmp/edge-install.sh
sed -n '1,220p' /tmp/edge-install.sh
sh /tmp/edge-install.sh
```

Optional one-liner with an SSH key and custom LAN CIDR:

```sh
SSH_AUTHORIZED_KEYS='ssh-ed25519 AAAA... keiki@pc' LAN_CIDRS='10.0.0.0/24' sh -c "$(curl -fsSL https://raw.githubusercontent.com/MStoffberg/stoffberg-edge-monitor/main/install.sh)"
```

Manual flow if you do not want the one-liner:

```sh
apk add --no-cache git ca-certificates curl
cd /root
git clone https://github.com/MStoffberg/stoffberg-edge-monitor.git
cd stoffberg-edge-monitor
cp config/edge-monitor.env.example /etc/edge-monitor.env
vi /etc/edge-monitor.env
sh scripts/bootstrap-alpine.sh
```

Then open:

```text
AdGuard Home setup: http://<edge-ip>:3000
Uptime Kuma:        http://<edge-ip>:3001
```

After AdGuard Home's first-run wizard is completed on the HP box, configure sync:

```sh
cp config/adguardhome-sync.yaml.example /etc/adguardhome-sync/adguardhome-sync.yaml
vi /etc/adguardhome-sync/adguardhome-sync.yaml
chmod 600 /etc/adguardhome-sync/adguardhome-sync.yaml
rc-service adguardhome-sync restart
rc-service adguardhome-sync status
```


## SSH / firewall safety

The installer is now interactive/safe by default:

- SSH user: `keiki`
- If no SSH key is provided, it prompts on console to set `keiki`'s password.
- Firewall lockdown is **not enabled on first install** unless `ENABLE_FIREWALL=true` is set.
- After SSH is confirmed working, enable lockdown with:

```sh
ENABLE_FIREWALL=true sh /root/stoffberg-edge-monitor/scripts/setup-firewall-nftables.sh
```

If you are locked out, see `docs/ssh-firewall-rescue.md`.

## Important sync direction

This box may be the **main DNS resolver for clients**, but its AdGuard configuration is pulled from the existing pve02 source:

```text
pve02 AdGuard Home / CT201 / 10.0.0.201  --->  HP t520 AdGuard Home / edge-monitor-01
                 source/origin                         target/replica/main-client-DNS
```

That means:

- edit allow/block lists, rewrites, clients, and DNS rules on **pve02**
- adguardhome-sync copies those settings to the HP t520
- clients can use the HP t520 as their primary DNS once tested

## What the bootstrap installs

- base security packages
- OpenSSH
- `doas` for admin escalation
- `nftables` firewall
- `chrony` time sync
- `logrotate`
- Docker + Docker Compose plugin
- AdGuard Home native binary/service
- Uptime Kuma via Docker Compose
- adguardhome-sync native binary/service
- status and update helper scripts

## LAN-only firewall policy

Default inbound policy is drop. It allows only from `LAN_CIDRS`:

| Port | Protocol | Service |
|---:|---|---|
| 22 | TCP | SSH |
| 53 | TCP/UDP | DNS / AdGuard Home |
| 3000 | TCP | AdGuard Home UI/setup |
| 3001 | TCP | Uptime Kuma |

Outbound traffic is allowed so the box can update packages, download blocklists, and sync from pve02.

## Files

```text
config/
  edge-monitor.env.example          # local bootstrap settings; copy to /etc/edge-monitor.env
  adguardhome-sync.yaml.example     # local sync settings; copy to /etc/adguardhome-sync/

docs/
  post-os-install.md                # Alpine install and first boot checklist
  security-model.md                 # what is locked down and what remains manual
  adguard-sync.md                   # pve02 -> edge-monitor-01 sync direction

scripts/
  bootstrap-alpine.sh               # full setup entrypoint
  install-adguardhome.sh
  install-uptime-kuma.sh
  install-adguardhome-sync.sh
  setup-firewall-nftables.sh
  setup-ssh.sh
  status-check.sh
  update-all.sh
```

## Safety notes

- Do **not** put this GitHub repo's files in charge of DHCP/router settings yet.
- Do **not** expose this box publicly for now.
- Do **not** store AdGuard admin passwords or sync credentials in Git.
- Test DNS before making it the only DNS server in DHCP.
