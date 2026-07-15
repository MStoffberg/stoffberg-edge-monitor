#!/bin/sh
set -eu
printf '== Host ==\n'
hostname
uname -a
printf '\n== Disk ==\n'
df -h /
printf '\n== Memory ==\n'
free -m || true
printf '\n== Services ==\n'
for s in sshd nftables chronyd docker AdGuardHome adguardhome-sync; do
  rc-service "$s" status || true
done
printf '\n== Docker ==\n'
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true
printf '\n== Docker resource usage ==\n'
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' || true
printf '\n== Listening ports ==\n'
ss -lntup || netstat -lntup || true
printf '\n== DNS self-test ==\n'
if command -v dig >/dev/null 2>&1; then
  dig @127.0.0.1 example.com +short || true
else
  nslookup example.com 127.0.0.1 || true
fi
