#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/edge-beszel-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  file=$1
  text=$2
  grep -F "$text" "$file" >/dev/null || fail "$file does not contain: $text"
}

assert_not_contains() {
  file=$1
  text=$2
  if grep -F "$text" "$file" >/dev/null; then
    fail "$file unexpectedly contains: $text"
  fi
}

# Rendering without Beszel credentials must preserve a valid Kuma-only stack.
OUT="$TMP/kuma-only.yml"
INSTALL_BESZEL_AGENT=true \
UPTIME_KUMA_IMAGE=louislam/uptime-kuma:2 \
UPTIME_KUMA_PORT=3001 \
BESZEL_AGENT_IMAGE=henrygd/beszel-agent \
BESZEL_LISTEN=45876 \
BESZEL_KEY='' BESZEL_HUB_URL='' BESZEL_TOKEN='' \
  sh "$REPO_DIR/scripts/render-monitoring-compose.sh" >"$OUT"
assert_contains "$OUT" 'uptime-kuma:'
assert_not_contains "$OUT" 'beszel-agent:'

# Once all connection values exist, render the exact requested agent service.
OUT="$TMP/with-agent.yml"
INSTALL_BESZEL_AGENT=true \
UPTIME_KUMA_IMAGE=louislam/uptime-kuma:2 \
UPTIME_KUMA_PORT=3001 \
BESZEL_AGENT_IMAGE=henrygd/beszel-agent \
BESZEL_LISTEN=45876 \
BESZEL_KEY='ssh-ed25519 TEST_PUBLIC_KEY' \
BESZEL_HUB_URL='http://10.0.0.204:8090' \
BESZEL_TOKEN='TEST_TOKEN' \
  sh "$REPO_DIR/scripts/render-monitoring-compose.sh" >"$OUT"
for expected in \
  'beszel-agent:' \
  'image: ${BESZEL_AGENT_IMAGE}' \
  'container_name: beszel-agent' \
  'restart: unless-stopped' \
  'network_mode: host' \
  './beszel_agent_data:/var/lib/beszel-agent' \
  '/var/run/docker.sock:/var/run/docker.sock:ro' \
  'LISTEN: ${BESZEL_LISTEN}' \
  'KEY: "${BESZEL_KEY}"' \
  'HUB_URL: "${BESZEL_HUB_URL}"' \
  'TOKEN: "${BESZEL_TOKEN}"'
do
  assert_contains "$OUT" "$expected"
done
assert_not_contains "$OUT" 'TEST_PUBLIC_KEY'
assert_not_contains "$OUT" 'TEST_TOKEN'

# The LAN-only firewall must permit the configured Beszel listener for the Hub.
FIREWALL="$REPO_DIR/scripts/setup-firewall-nftables.sh"
assert_contains "$FIREWALL" '"$BESZEL_LISTEN"'

# Public example must expose placeholders/defaults but no real credentials.
ENV_EXAMPLE="$REPO_DIR/config/edge-monitor.env.example"
for expected in \
  'INSTALL_BESZEL_AGENT=true' \
  'BESZEL_AGENT_IMAGE=henrygd/beszel-agent' \
  'BESZEL_LISTEN=45876' \
  'BESZEL_KEY=""' \
  'BESZEL_HUB_URL=""' \
  'BESZEL_TOKEN=""'
do
  assert_contains "$ENV_EXAMPLE" "$expected"
done

# Update flow must prompt for native and container services, then clean conservatively.
UPDATE="$REPO_DIR/scripts/update-all.sh"
assert_contains "$UPDATE" 'confirm_update'
assert_contains "$UPDATE" 'Update AdGuard Home from'
assert_contains "$UPDATE" 'Update adguardhome-sync from'
assert_contains "$UPDATE" 'Update $service to the downloaded newer image?'
assert_contains "$UPDATE" 'docker image prune -f'
assert_contains "$UPDATE" 'apk cache clean'
assert_not_contains "$UPDATE" 'docker system prune'
assert_not_contains "$UPDATE" 'docker volume prune'
assert_not_contains "$UPDATE" 'docker container prune'

# Reconciliation must preserve existing Kuma and start only a missing agent.
INSTALLER="$REPO_DIR/scripts/install-uptime-kuma.sh"
assert_contains "$INSTALLER" 'docker container inspect uptime-kuma'
assert_contains "$INSTALLER" 'Keeping existing Uptime Kuma container unchanged'
assert_contains "$INSTALLER" 'docker compose up -d beszel-agent'

printf 'PASS: Beszel agent compose and update behavior\n'
