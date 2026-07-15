#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

log "Reconciling Uptime Kuma and Beszel Agent compose stack"
mkdir -p /opt/uptime-kuma/data /opt/uptime-kuma/beszel_agent_data

kuma_exists=false
agent_exists=false
docker container inspect uptime-kuma >/dev/null 2>&1 && kuma_exists=true
docker container inspect beszel-agent >/dev/null 2>&1 && agent_exists=true

cat > /opt/uptime-kuma/.env <<EOF
UPTIME_KUMA_IMAGE=$UPTIME_KUMA_IMAGE
UPTIME_KUMA_PORT=$UPTIME_KUMA_PORT
BESZEL_AGENT_IMAGE=$BESZEL_AGENT_IMAGE
BESZEL_LISTEN=$BESZEL_LISTEN
BESZEL_KEY=$BESZEL_KEY
BESZEL_HUB_URL=$BESZEL_HUB_URL
BESZEL_TOKEN=$BESZEL_TOKEN
EOF
chmod 600 /opt/uptime-kuma/.env

INSTALL_BESZEL_AGENT="$INSTALL_BESZEL_AGENT" \
UPTIME_KUMA_IMAGE="$UPTIME_KUMA_IMAGE" UPTIME_KUMA_PORT="$UPTIME_KUMA_PORT" \
BESZEL_AGENT_IMAGE="$BESZEL_AGENT_IMAGE" BESZEL_LISTEN="$BESZEL_LISTEN" \
BESZEL_KEY="$BESZEL_KEY" BESZEL_HUB_URL="$BESZEL_HUB_URL" BESZEL_TOKEN="$BESZEL_TOKEN" \
  sh "$SCRIPT_DIR/render-monitoring-compose.sh" > /opt/uptime-kuma/docker-compose.yml.tmp
mv /opt/uptime-kuma/docker-compose.yml.tmp /opt/uptime-kuma/docker-compose.yml
chmod 600 /opt/uptime-kuma/docker-compose.yml

cd /opt/uptime-kuma
if [ "$kuma_exists" = "false" ]; then
  docker compose pull uptime-kuma
  docker compose up -d uptime-kuma
else
  log "Keeping existing Uptime Kuma container unchanged; use edge-update for upgrades"
fi

if [ "$INSTALL_BESZEL_AGENT" != "true" ]; then
  log "Beszel Agent disabled (INSTALL_BESZEL_AGENT=false)"
elif [ -z "$BESZEL_KEY" ] || [ -z "$BESZEL_HUB_URL" ] || [ -z "$BESZEL_TOKEN" ]; then
  log "Beszel Agent deferred until BESZEL_KEY, BESZEL_HUB_URL, and BESZEL_TOKEN are configured"
elif [ "$agent_exists" = "false" ]; then
  docker compose pull beszel-agent
  docker compose up -d beszel-agent
else
  log "Keeping existing Beszel Agent container unchanged; use edge-update for upgrades"
fi
