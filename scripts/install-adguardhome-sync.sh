#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

log "Installing adguardhome-sync $ADGUARDHOME_SYNC_VERSION"
version_no_v=$(printf '%s' "$ADGUARDHOME_SYNC_VERSION" | sed 's/^v//')
url="https://github.com/bakito/adguardhome-sync/releases/download/${ADGUARDHOME_SYNC_VERSION}/adguardhome-sync_${version_no_v}_linux_amd64.tar.gz"
work=/tmp/adguardhome-sync-install
rm -rf "$work"
mkdir -p "$work"
curl -fsSL "$url" -o "$work/adguardhome-sync.tar.gz"
tar -xzf "$work/adguardhome-sync.tar.gz" -C "$work"
install -m 755 "$work/adguardhome-sync" /usr/local/bin/adguardhome-sync
mkdir -p /etc/adguardhome-sync
if [ ! -f /etc/adguardhome-sync/adguardhome-sync.yaml ]; then
  cat > /etc/adguardhome-sync/adguardhome-sync.yaml <<'EOF'
# Edit this file after completing AdGuard Home setup on this HP t520.
# See config/adguardhome-sync.yaml.example in the repo.
cron: "*/10 * * * *"
runOnStart: false
origin:
  url: "http://10.0.0.201:3000"
  username: "CHANGE_ME"
  password: "CHANGE_ME"
replicas:
  - url: "http://127.0.0.1:3000"
    username: "CHANGE_ME"
    password: "CHANGE_ME"
api:
  port: 0
features:
  dhcp:
    serverConfig: false
    staticLeases: false
  tlsConfig: false
EOF
  chmod 600 /etc/adguardhome-sync/adguardhome-sync.yaml
fi

cat > /etc/init.d/adguardhome-sync <<'EOF'
#!/sbin/openrc-run
name="adguardhome-sync"
description="Sync AdGuard Home configuration from pve02 to edge-monitor-01"
command="/usr/local/bin/adguardhome-sync"
command_args="run --config /etc/adguardhome-sync/adguardhome-sync.yaml"
command_background=true
pidfile="/run/adguardhome-sync.pid"
output_log="/var/log/adguardhome-sync.log"
error_log="/var/log/adguardhome-sync.log"
depend() {
  need net
  after AdGuardHome
}
EOF
chmod 755 /etc/init.d/adguardhome-sync
rc-update add adguardhome-sync default || true
# Do not hard-fail before the user edits credentials.
rc-service adguardhome-sync start || true
adguardhome-sync --version || true
