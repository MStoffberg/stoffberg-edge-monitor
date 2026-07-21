#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

log "Installing base packages"
apk update
apk add --no-cache bash ca-certificates curl docker docker-cli-compose doas git logrotate nftables openssh-server openssh-client shadow sudo tzdata chrony tar gzip

log "Setting hostname and timezone"
echo "$HOSTNAME" > /etc/hostname
hostname "$HOSTNAME" || true
if [ -f "/usr/share/zoneinfo/$TIMEZONE" ]; then cp "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime; echo "$TIMEZONE" > /etc/timezone; fi

log "Enabling core services"
rc-update add chronyd default || true; rc-service chronyd start || true
rc-update add docker default || true; rc-service docker start || true
rc-update add sshd default || true

sh "$SCRIPT_DIR/setup-ssh.sh"
sh "$SCRIPT_DIR/install-adguardhome.sh"
if [ "$INSTALL_ADGUARD_SYNC" = "true" ]; then
  sh "$SCRIPT_DIR/install-adguardhome-sync.sh"
else
  log "Disabling DNS sync controller"
  rc-service adguardhome-sync stop >/dev/null 2>&1 || true
  rc-update del adguardhome-sync default >/dev/null 2>&1 || true
fi
sh "$SCRIPT_DIR/install-edge-services.sh"
sh "$SCRIPT_DIR/install-cleanup-schedule.sh"

install -m 755 "$SCRIPT_DIR/status-check.sh" /usr/local/sbin/edge-status
install -m 755 "$SCRIPT_DIR/update-all.sh" /usr/local/sbin/edge-update
install -m 755 "$SCRIPT_DIR/install-edge-services.sh" /usr/local/sbin/install-edge-services.sh
install -m 755 "$SCRIPT_DIR/render-edge-compose.sh" /usr/local/sbin/render-edge-compose.sh
install -m 755 "$SCRIPT_DIR/setup-firewall-nftables.sh" /usr/local/sbin/edge-lockdown

if [ "$ENABLE_FIREWALL" = "true" ]; then
  sh "$SCRIPT_DIR/setup-firewall-nftables.sh"
else
  log "Firewall not enabled yet to avoid SSH lockout"
  echo "Prove a second SSH session, then run: ENABLE_FIREWALL=true edge-lockdown"
fi

log "Bootstrap finished"
echo "AdGuard: http://<edge-ip>:${ADGUARD_UI_PORT}"
echo "Run edge-status, edge-update, and edge-cleanup (dry-run by default)."
