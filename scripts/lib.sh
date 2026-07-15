#!/bin/sh
set -eu

load_env() {
  if [ -f /etc/edge-monitor.env ]; then
    # shellcheck disable=SC1091
    . /etc/edge-monitor.env
  fi
  HOSTNAME="${HOSTNAME:-edge-monitor-01}"
  TIMEZONE="${TIMEZONE:-Africa/Johannesburg}"
  LAN_CIDRS="${LAN_CIDRS:-10.0.0.0/24}"
  SSH_USER="${SSH_USER:-keiki}"
  SSH_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS:-}"
  DISABLE_PASSWORD_SSH_IF_KEY_PRESENT="${DISABLE_PASSWORD_SSH_IF_KEY_PRESENT:-true}"
  ADGUARDHOME_VERSION="${ADGUARDHOME_VERSION:-v0.107.78}"
  ADGUARDHOME_SYNC_VERSION="${ADGUARDHOME_SYNC_VERSION:-v0.9.2}"
  UPTIME_KUMA_IMAGE="${UPTIME_KUMA_IMAGE:-louislam/uptime-kuma:2}"
  ADGUARD_UI_PORT="${ADGUARD_UI_PORT:-3000}"
  UPTIME_KUMA_PORT="${UPTIME_KUMA_PORT:-3001}"
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "ERROR: run as root" >&2
    exit 1
  fi
}

log() { printf '\n[edge-monitor] %s\n' "$*"; }
