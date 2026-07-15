#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

log "Installing base packages"
apk update
apk upgrade --available
apk add --no-cache \
  bash ca-certificates curl docker docker-cli-compose doas git logrotate \
  nftables openssh-server openssh-client shadow sudo tzdata chrony tar gzip

log "Setting hostname and timezone"
echo "$HOSTNAME" > /etc/hostname
hostname "$HOSTNAME" || true
if [ -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
  cp "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
  echo "$TIMEZONE" > /etc/timezone
fi

log "Enabling core services"
rc-update add chronyd default || true
rc-service chronyd start || true
rc-update add docker default || true
rc-service docker start || true
rc-update add nftables boot || true
rc-update add sshd default || true

sh "$SCRIPT_DIR/setup-ssh.sh"
sh "$SCRIPT_DIR/install-adguardhome.sh"
sh "$SCRIPT_DIR/install-uptime-kuma.sh"
sh "$SCRIPT_DIR/install-adguardhome-sync.sh"
sh "$SCRIPT_DIR/setup-firewall-nftables.sh"

install -m 755 "$SCRIPT_DIR/status-check.sh" /usr/local/sbin/edge-status
install -m 755 "$SCRIPT_DIR/update-all.sh" /usr/local/sbin/edge-update

log "Bootstrap finished"
echo "Next: open AdGuard at http://<edge-ip>:${ADGUARD_UI_PORT}, complete setup wizard, then edit /etc/adguardhome-sync/adguardhome-sync.yaml."
echo "Run: edge-status"
