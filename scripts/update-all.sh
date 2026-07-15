#!/bin/sh
set -eu
printf '[edge-monitor] Updating Alpine packages\n'
apk update
apk upgrade --available
printf '[edge-monitor] Updating Uptime Kuma container\n'
if [ -f /opt/uptime-kuma/docker-compose.yml ]; then
  cd /opt/uptime-kuma
  docker compose pull
  docker compose up -d
fi
printf '[edge-monitor] Done. Run edge-status to verify.\n'
