#!/bin/sh
set -eu
if [ -f /etc/edge-monitor.env ]; then
  # shellcheck disable=SC1091
  . /etc/edge-monitor.env
fi
printf '== Host ==\n'; hostname; uname -a
printf '\n== Disk ==\n'; df -h /
printf '\n== Memory ==\n'; free -m || true
printf '\n== Services ==\n'
for s in sshd nftables chronyd docker AdGuardHome adguardhome-sync; do rc-service "$s" status || true; done
printf '\n== Docker ==\n'; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true
printf '\n== Docker resources ==\n'; docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' || true
printf '\n== DNS self-test ==\n'
if command -v dig >/dev/null 2>&1; then dig @127.0.0.1 example.com +short || true; else nslookup example.com 127.0.0.1 || true; fi
printf '\n== Cloudflared ==\n'
if docker container inspect cloudflared >/dev/null 2>&1; then docker inspect -f 'state={{.State.Status}} restarts={{.RestartCount}} image={{.Config.Image}}' cloudflared; else echo 'not installed'; fi
printf '\n== DNS sync controller ==\n'
ps -o pid,etime,args | grep '[a]dguardhome-sync' || true
tail -n 15 /var/log/adguardhome-sync.log 2>/dev/null || true
