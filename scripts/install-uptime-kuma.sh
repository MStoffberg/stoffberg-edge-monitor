#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

log "Installing Uptime Kuma compose stack"
mkdir -p /opt/uptime-kuma/data
cat > /opt/uptime-kuma/docker-compose.yml <<EOF
services:
  uptime-kuma:
    image: ${UPTIME_KUMA_IMAGE}
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "${UPTIME_KUMA_PORT}:3001"
    volumes:
      - ./data:/app/data
    security_opt:
      - no-new-privileges:true
EOF
chmod 600 /opt/uptime-kuma/docker-compose.yml
cd /opt/uptime-kuma
docker compose pull
docker compose up -d
