#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root
umask 077

log "Installing adguardhome-sync $ADGUARDHOME_SYNC_VERSION as Tiny Edge controller"
version_no_v=${ADGUARDHOME_SYNC_VERSION#v}
url="https://github.com/bakito/adguardhome-sync/releases/download/${ADGUARDHOME_SYNC_VERSION}/adguardhome-sync_${version_no_v}_linux_amd64.tar.gz"
work=$(mktemp -d /tmp/adguardhome-sync-update.XXXXXX)
binary=/usr/local/bin/adguardhome-sync
init=/etc/init.d/adguardhome-sync
config=/etc/adguardhome-sync/adguardhome-sync.yaml
marker=/etc/adguardhome-sync/recurring-sync-cutover-approved
old_binary="$work/adguardhome-sync.old"
old_init="$work/adguardhome-sync.init.old"
old_config="$work/adguardhome-sync.yaml.old"
had_binary=false; had_init=false; had_config=false; was_running=false; was_enabled=false; committed=false

rc-service adguardhome-sync status >/dev/null 2>&1 && was_running=true || true
rc-update show default 2>/dev/null | grep -q '^[[:space:]]*adguardhome-sync[[:space:]]' && was_enabled=true || true
[ ! -e "$binary" ] || { cp -p "$binary" "$old_binary"; had_binary=true; }
[ ! -e "$init" ] || { cp -p "$init" "$old_init"; had_init=true; }
[ ! -e "$config" ] || { cp -p "$config" "$old_config"; had_config=true; }
cleanup() {
  rc=$1
  trap - EXIT HUP INT TERM
  if [ "$committed" != true ]; then
    rc-service adguardhome-sync stop >/dev/null 2>&1 || true
    if [ "$had_binary" = true ]; then install -m 755 "$old_binary" "$binary"; else rm -f "$binary"; fi
    if [ "$had_init" = true ]; then install -m 755 "$old_init" "$init"; else rm -f "$init"; fi
    if [ "$had_config" = true ]; then install -m 600 "$old_config" "$config"; else rm -f "$config"; fi
    if [ "$was_enabled" = true ]; then rc-update add adguardhome-sync default >/dev/null 2>&1 || true; else rc-update del adguardhome-sync default >/dev/null 2>&1 || true; fi
    [ "$was_running" = false ] || rc-service adguardhome-sync start >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
  exit "$rc"
}
# Rollback is armed before mkdir/config installation, the first owned mutation.
trap 'cleanup $?' EXIT
trap 'cleanup 129' HUP
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

curl -fsSL "$url" -o "$work/archive.tar.gz"
tar -xzf "$work/archive.tar.gz" -C "$work"
"$work/adguardhome-sync" --version >/dev/null

mkdir -p /etc/adguardhome-sync
if [ "$had_config" = false ]; then install -m 600 "$SCRIPT_DIR/../config/adguardhome-sync.yaml.example" "$config"; fi
init_tmp="$work/adguardhome-sync.init"
cat >"$init_tmp" <<'EOF'
#!/sbin/openrc-run
name="adguardhome-sync"
description="Tiny Edge AdGuard configuration sync controller"
command="/usr/local/bin/adguardhome-sync"
command_args="run --config /etc/adguardhome-sync/adguardhome-sync.yaml"
command_background=true
pidfile="/run/adguardhome-sync.pid"
output_log="/var/log/adguardhome-sync.log"
error_log="/var/log/adguardhome-sync.log"
depend() { need net; after AdGuardHome docker; }
EOF
chmod 755 "$init_tmp"

[ "$was_running" = false ] || rc-service adguardhome-sync stop
install -m 755 "$work/adguardhome-sync" "$binary"
install -m 755 "$init_tmp" "$init"

approved=false
if [ -f "$marker" ] && [ "$(cat "$marker")" = 'ADGUARD_SYNC_CUTOVER_APPROVED=true' ]; then approved=true; fi
if grep -q 'CHANGE_ME' "$config"; then
  log "DNS sync config contains placeholders; recurring service is disabled"
  rc-service adguardhome-sync stop >/dev/null 2>&1 || true
  rc-update del adguardhome-sync default >/dev/null 2>&1 || true
elif [ "$approved" != true ]; then
  log "Recurring sync remains disabled until manual one-shot verification and the exact cutover marker"
  rc-service adguardhome-sync stop >/dev/null 2>&1 || true
  rc-update del adguardhome-sync default >/dev/null 2>&1 || true
else
  rc-update add adguardhome-sync default >/dev/null
  rc-service adguardhome-sync start
  rc-service adguardhome-sync status >/dev/null
fi
committed=true
trap - EXIT HUP INT TERM
rm -rf "$work"
"$binary" --version
