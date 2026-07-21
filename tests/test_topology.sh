#!/bin/sh
set -eu
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/edge-topology-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
fail(){ echo "FAIL: $*" >&2; exit 1; }
contains(){ grep -F -- "$2" "$1" >/dev/null || fail "$1 missing $2"; }
not_contains(){ ! grep -F -- "$2" "$1" >/dev/null || fail "$1 unexpectedly contains $2"; }

token="$TMP/token.env"; printf '%s\n' 'TUNNEL_TOKEN=TEST_SECRET_MUST_NOT_RENDER' >"$token"
out="$TMP/compose.yml"
INSTALL_BESZEL_AGENT=true BESZEL_KEY='ssh-ed25519 TEST_KEY' BESZEL_HUB_URL='http://10.0.0.204:8090' BESZEL_TOKEN='TEST_BESZEL_TOKEN' \
INSTALL_CLOUDFLARED=true CLOUDFLARED_TOKEN_FILE="$token" CLOUDFLARED_IMAGE='cloudflare/cloudflared:test' \
sh "$REPO_DIR/scripts/render-edge-compose.sh" >"$out"
for expected in 'beszel-agent:' 'cloudflared:' 'tunnel --no-autoupdate run' 'network_mode: host' 'read_only: true' 'no-new-privileges:true'; do contains "$out" "$expected"; done
not_contains "$out" 'TEST_SECRET_MUST_NOT_RENDER'
not_contains "$out" 'uptime-kuma:'

empty="$TMP/empty"; : >"$empty"; out2="$TMP/no-services.yml"
INSTALL_BESZEL_AGENT=false INSTALL_CLOUDFLARED=true CLOUDFLARED_TOKEN_FILE="$empty" sh "$REPO_DIR/scripts/render-edge-compose.sh" >"$out2"
[ "$(cat "$out2")" = 'services: {}' ] || fail 'empty topology must still render a valid services mapping'

installer="$REPO_DIR/scripts/install-edge-services.sh"
contains "$installer" 'umask 077'
contains "$installer" 'docker compose --env-file "$env_tmp" -f "$compose_tmp" config >/dev/null'
contains "$installer" 'config --services)'
not_contains "$installer" 'docker compose config --services 2>/dev/null || true'
contains "$installer" 'quarantine_if_present()'
contains "$installer" 'docker rename "$name" "$saved"'
contains "$installer" 'docker rename "$beszel_rollback" beszel-agent'
contains "$installer" 'docker rename "$cloudflared_rollback" cloudflared'
contains "$installer" 'stable_container()'
contains "$installer" 'exec 3<"$CLOUDFLARED_TOKEN_FILE"'
contains "$installer" "0:600:regular file"
not_contains "$installer" 'chmod 600 "$CLOUDFLARED_TOKEN_FILE"'
contains "$REPO_DIR/config/edge-monitor.env.example" 'INSTALL_BESZEL_AGENT=false'
contains "$REPO_DIR/config/edge-monitor.env.example" 'INSTALL_CLOUDFLARED=false'

cutover="$REPO_DIR/scripts/apply-tiny-cutover.sh"
contains "$cutover" 'exec 3<"$TOKEN_SOURCE"'
contains "$cutover" "source_meta="
contains "$cutover" "0:600:regular file"
contains "$cutover" 'cat <&3 >"$token_candidate"'
not_contains "$cutover" 'HA_KUMA_URL'
not_contains "$cutover" 'edge-retire-kuma'
contains "$REPO_DIR/scripts/install-cleanup-schedule.sh" 'install -m 644 "$SCRIPT_DIR/lib.sh" /usr/local/sbin/lib.sh'

firewall="$REPO_DIR/scripts/setup-firewall-nftables.sh"
contains "$firewall" '/etc/nftables.nft'
contains "$firewall" "Docker's independent tables are untouched"
contains "$firewall" 'single nft batch atomically deletes'
not_contains "$firewall" 'chain forward'
not_contains "$firewall" 'rc-service nftables restart'
not_contains "$firewall" 'UPTIME_KUMA_PORT'

cleanup="$REPO_DIR/scripts/edge-cleanup.sh"
contains "$cleanup" '--apply'
contains "$cleanup" 'cleanup threshold must be between 1 and 99'
contains "$cleanup" 'docker image prune -f --filter until=168h'
not_contains "$cleanup" 'docker system prune'
not_contains "$cleanup" 'docker volume prune'
not_contains "$cleanup" 'docker container prune'

sync="$REPO_DIR/config/adguardhome-sync.yaml.example"
contains "$sync" 'http://10.0.0.201"'
not_contains "$sync" '10.0.0.201:3000'
contains "$sync" 'http://127.0.0.1:3000'
contains "$sync" 'http://10.0.0.102:3000'
contains "$sync" 'http://192.168.101.140:30004'
contains "$sync" 'CHANGE_ME'

sync_installer="$REPO_DIR/scripts/install-adguardhome-sync.sh"
contains "$sync_installer" '# Rollback is armed before mkdir/config installation, the first owned mutation.'
contains "$sync_installer" "trap 'cleanup \$?' EXIT"
contains "$sync_installer" 'adguardhome-sync.old'
contains "$sync_installer" 'rc-service adguardhome-sync status'

post="$REPO_DIR/docs/post-os-install.md"
contains "$post" 'doas adguardhome-sync run --config /etc/adguardhome-sync/adguardhome-sync.yaml --cron "" --api-port 0'
contains "$post" 'ADGUARD_SYNC_CUTOVER_APPROVED=true'

# HAOS Kuma migration/status belongs outside the Tiny service installer.
if grep -R -E 'HA_KUMA_URL|edge-retire-kuma|migrate-uptime-kuma' \
  "$REPO_DIR/install.sh" "$REPO_DIR/scripts" "$REPO_DIR/config" "$REPO_DIR/docs" "$REPO_DIR/README.md" >/dev/null 2>&1; then
  fail 'unrelated HAOS Kuma migration logic remains in Tiny installer repository'
fi

printf '%s\n' "PASS: Tiny Edge service topology, transactions, firewall, and DNS direction"
