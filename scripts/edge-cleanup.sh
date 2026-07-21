#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

apply=false
[ "${1:-}" = "--apply" ] && apply=true
lock=${CLEANUP_LOCK_DIR:-/run/edge-cleanup.lock}
log_file=${CLEANUP_LOG_FILE:-/var/log/edge-cleanup.log}
if ! mkdir "$lock" 2>/dev/null; then
  echo "ERROR: edge cleanup is already running" >&2
  exit 1
fi
cleanup_lock() { rc=$1; trap - EXIT HUP INT TERM; rmdir "$lock" 2>/dev/null || true; exit "$rc"; }
trap 'cleanup_lock $?' EXIT
trap 'cleanup_lock 129' HUP
trap 'cleanup_lock 130' INT
trap 'cleanup_lock 143' TERM

used=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
case "$used:$CLEANUP_MIN_DISK_PERCENT" in
  *[!0-9:]*|:*|*:) echo "ERROR: disk usage and cleanup threshold must be numeric" >&2; exit 1;;
esac
[ "$CLEANUP_MIN_DISK_PERCENT" -ge 1 ] && [ "$CLEANUP_MIN_DISK_PERCENT" -le 99 ] || { echo "ERROR: cleanup threshold must be between 1 and 99" >&2; exit 1; }
pressure=false
[ "$used" -ge "$CLEANUP_MIN_DISK_PERCENT" ] && pressure=true
mode=dry-run
[ "$apply" = "true" ] && mode=apply
printf '[edge-cleanup] mode=%s root_used=%s%% threshold=%s%% pressure=%s\n' "$mode" "$used" "$CLEANUP_MIN_DISK_PERCENT" "$pressure"

if [ "$apply" != "true" ]; then
  echo "[edge-cleanup] Would clean APK cache and known installer temp directories."
  echo "[edge-cleanup] Would delete regular files older than 7 days from /tmp, 14 days from /var/tmp, and rotated logs older than 30 days."
  find /tmp -xdev -type f -mtime +7 -print 2>/dev/null || true
  find /var/tmp -xdev -type f -mtime +14 -print 2>/dev/null || true
  find /var/log -xdev -type f \( -name '*.old' -o -name '*.gz' \) -mtime +30 -print 2>/dev/null || true
  if [ "$pressure" = "true" ] && [ "$CLEANUP_DOCKER_IMAGES" = "true" ]; then
    docker image ls --filter dangling=true 2>/dev/null || true
  else
    echo "[edge-cleanup] Docker prune is threshold-gated and would be skipped."
  fi
  echo "Dry run only. Re-run with --apply."
  exit 0
fi

{
  printf '\n[%s] edge cleanup start; root used %s%% pressure=%s\n' "$(date -Iseconds)" "$used" "$pressure"
  apk cache clean || true
  rm -rf /tmp/adguardhome-install /tmp/adguardhome-sync-install /tmp/adguardhome-sync-update.*
  find /tmp -xdev -type f -mtime +7 -delete 2>/dev/null || true
  find /var/tmp -xdev -type f -mtime +14 -delete 2>/dev/null || true
  find /var/log -xdev -type f \( -name '*.old' -o -name '*.gz' \) -mtime +30 -delete 2>/dev/null || true
  if [ "$pressure" = "true" ] && [ "$CLEANUP_DOCKER_IMAGES" = "true" ] && command -v docker >/dev/null 2>&1; then
    docker image prune -f --filter until=168h
  else
    echo "Docker image prune skipped (below threshold, disabled, or Docker absent)."
  fi
  if [ "$pressure" = "true" ] && [ "$CLEANUP_DOCKER_BUILD_CACHE" = "true" ] && command -v docker >/dev/null 2>&1; then
    docker builder prune -f --filter until=168h
  fi
  # Deliberately never run container, volume, or system prune.
  df -h /
  docker system df 2>/dev/null || true
  printf '[%s] edge cleanup complete\n' "$(date -Iseconds)"
} >>"$log_file" 2>&1

tail -n 30 "$log_file"
