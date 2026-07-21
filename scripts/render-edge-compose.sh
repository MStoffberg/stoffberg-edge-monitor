#!/bin/sh
set -eu

INSTALL_BESZEL_AGENT="${INSTALL_BESZEL_AGENT:-true}"
BESZEL_AGENT_IMAGE="${BESZEL_AGENT_IMAGE:-henrygd/beszel-agent}"
BESZEL_LISTEN="${BESZEL_LISTEN:-45876}"
BESZEL_KEY="${BESZEL_KEY:-}"
BESZEL_HUB_URL="${BESZEL_HUB_URL:-}"
BESZEL_TOKEN="${BESZEL_TOKEN:-}"
INSTALL_CLOUDFLARED="${INSTALL_CLOUDFLARED:-true}"
CLOUDFLARED_IMAGE="${CLOUDFLARED_IMAGE:-cloudflare/cloudflared:2026.7.2}"
CLOUDFLARED_TOKEN_FILE="${CLOUDFLARED_TOKEN_FILE:-/etc/cloudflared/token.env}"

emit_beszel=false
emit_cloudflared=false
if [ "$INSTALL_BESZEL_AGENT" = true ] && [ -n "$BESZEL_KEY" ] && [ -n "$BESZEL_HUB_URL" ] && [ -n "$BESZEL_TOKEN" ]; then
  emit_beszel=true
fi
if [ "$INSTALL_CLOUDFLARED" = true ] && [ -s "$CLOUDFLARED_TOKEN_FILE" ]; then
  emit_cloudflared=true
fi

if [ "$emit_beszel" = false ] && [ "$emit_cloudflared" = false ]; then
  printf '%s\n' 'services: {}'
  exit 0
fi
printf '%s\n' 'services:'

if [ "$emit_beszel" = true ]; then
  cat <<'EOF'
  beszel-agent:
    image: ${BESZEL_AGENT_IMAGE}
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./beszel_agent_data:/var/lib/beszel-agent
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      LISTEN: ${BESZEL_LISTEN}
      KEY: "${BESZEL_KEY}"
      HUB_URL: "${BESZEL_HUB_URL}"
      TOKEN: "${BESZEL_TOKEN}"
    security_opt:
      - no-new-privileges:true
EOF
fi

if [ "$emit_cloudflared" = true ]; then
  cat <<'EOF'
  cloudflared:
    image: ${CLOUDFLARED_IMAGE}
    container_name: cloudflared
    restart: unless-stopped
    network_mode: host
    command: tunnel --no-autoupdate run
    env_file:
      - ${CLOUDFLARED_TOKEN_FILE}
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp:size=16m,mode=1777
EOF
fi
