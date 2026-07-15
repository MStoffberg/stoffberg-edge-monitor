#!/bin/sh
set -eu

UPTIME_KUMA_IMAGE="${UPTIME_KUMA_IMAGE:-louislam/uptime-kuma:2}"
UPTIME_KUMA_PORT="${UPTIME_KUMA_PORT:-3001}"
INSTALL_BESZEL_AGENT="${INSTALL_BESZEL_AGENT:-true}"
BESZEL_AGENT_IMAGE="${BESZEL_AGENT_IMAGE:-henrygd/beszel-agent}"
BESZEL_LISTEN="${BESZEL_LISTEN:-45876}"
BESZEL_KEY="${BESZEL_KEY:-}"
BESZEL_HUB_URL="${BESZEL_HUB_URL:-}"
BESZEL_TOKEN="${BESZEL_TOKEN:-}"

cat <<'EOF'
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

if [ "$INSTALL_BESZEL_AGENT" = "true" ] && \
   [ -n "$BESZEL_KEY" ] && [ -n "$BESZEL_HUB_URL" ] && [ -n "$BESZEL_TOKEN" ]; then
  cat <<'EOF'
  beszel-agent:
    image: ${BESZEL_AGENT_IMAGE}
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./beszel_agent_data:/var/lib/beszel-agent
      - /var/run/docker.sock:/var/run/docker.sock:ro
      # Monitor another disk by mounting a folder under /extra-filesystems.
      # - /mnt/disk1/.beszel:/extra-filesystems/disk1:ro
    environment:
      LISTEN: ${BESZEL_LISTEN}
      KEY: "${BESZEL_KEY}"
      HUB_URL: "${BESZEL_HUB_URL}"
      TOKEN: "${BESZEL_TOKEN}"
EOF
fi
