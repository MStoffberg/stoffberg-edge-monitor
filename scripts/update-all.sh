#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

confirm_update() {
  prompt=$1
  [ "${ASSUME_YES:-false}" = "true" ] && return 0
  if [ ! -t 0 ]; then printf '[edge-monitor] Non-interactive: skipping %s\n' "$prompt"; return 1; fi
  printf '%s [y/N] ' "$prompt"; read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
latest_github_tag() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1; }

printf '[edge-monitor] Checking Alpine package updates\n'
apk update
package_updates=$(apk version -l '<' 2>/dev/null || true)
if [ -n "$package_updates" ]; then
  printf '%s\n' "$package_updates"
  if confirm_update "Apply Alpine updates?"; then apk upgrade --available; fi
else
  echo '[edge-monitor] Alpine packages are current'
fi

if [ -x /opt/AdGuardHome/AdGuardHome ]; then
  current=$(/opt/AdGuardHome/AdGuardHome --version 2>/dev/null | sed -n 's/.*version \(v[^ ,]*\).*/\1/p')
  latest=$(latest_github_tag AdguardTeam/AdGuardHome || true)
  if [ -n "$latest" ] && [ "$current" != "$latest" ] && confirm_update "Update AdGuard Home from $current to $latest?"; then /opt/AdGuardHome/AdGuardHome --update; fi
fi

if command -v adguardhome-sync >/dev/null 2>&1; then
  current=$(adguardhome-sync --version 2>/dev/null | sed -n 's/.*version[[:space:]]*//p' | sed 's/^/v/')
  latest=$(latest_github_tag bakito/adguardhome-sync || true)
  if [ -n "$latest" ] && [ "$current" != "$latest" ] && confirm_update "Update adguardhome-sync from $current to $latest?"; then
    version_no_v=${latest#v}
    work=$(mktemp -d /tmp/adguardhome-sync-update.XXXXXX)
    binary=/usr/local/bin/adguardhome-sync
    old="$work/adguardhome-sync.old"
    was_running=false; was_enabled=false; rollback=false
    rc-service adguardhome-sync status >/dev/null 2>&1 && was_running=true || true
    rc-update show default 2>/dev/null | grep -q '^[[:space:]]*adguardhome-sync[[:space:]]' && was_enabled=true || true
    restore_sync_update() {
      rc=$1
      trap - EXIT HUP INT TERM
      if [ "$rollback" = true ]; then
        rc-service adguardhome-sync stop >/dev/null 2>&1 || true
        install -m 755 "$old" "$binary"
        if [ "$was_enabled" = true ]; then rc-update add adguardhome-sync default >/dev/null 2>&1 || true; else rc-update del adguardhome-sync default >/dev/null 2>&1 || true; fi
        [ "$was_running" = false ] || rc-service adguardhome-sync start >/dev/null 2>&1 || true
      fi
      rm -rf "$work"
      exit "$rc"
    }
    trap 'restore_sync_update $?' EXIT
    trap 'restore_sync_update 129' HUP
    trap 'restore_sync_update 130' INT
    trap 'restore_sync_update 143' TERM
    curl -fsSL "https://github.com/bakito/adguardhome-sync/releases/download/$latest/adguardhome-sync_${version_no_v}_linux_amd64.tar.gz" -o "$work/archive.tar.gz"
    tar -xzf "$work/archive.tar.gz" -C "$work"
    "$work/adguardhome-sync" --version >/dev/null
    cp -p "$binary" "$old"
    rollback=true
    [ "$was_running" = false ] || rc-service adguardhome-sync stop
    install -m 755 "$work/adguardhome-sync" "$binary"
    [ "$was_running" = false ] || { rc-service adguardhome-sync start; rc-service adguardhome-sync status >/dev/null; }
    if [ "$was_enabled" = true ]; then rc-update add adguardhome-sync default >/dev/null; else rc-update del adguardhome-sync default >/dev/null 2>&1 || true; fi
    rollback=false
    trap - EXIT HUP INT TERM
    rm -rf "$work"
  fi
fi

if [ -f /opt/edge-services/docker-compose.yml ] && confirm_update "Transactionally reconcile pulled Beszel/Cloudflared images?"; then
  sh "$SCRIPT_DIR/install-edge-services.sh"
fi

if confirm_update "Run conservative edge cleanup now?"; then edge-cleanup --apply; else edge-cleanup; fi
printf '[edge-monitor] Done. Run edge-status.\n'
