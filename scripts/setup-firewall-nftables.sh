#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root
umask 077

for value in "$ADGUARD_UI_PORT" "$BESZEL_LISTEN"; do
  case "$value" in ''|*[!0-9]*) echo "ERROR: firewall ports must be numeric" >&2; exit 1;; esac
  [ "$value" -ge 1 ] && [ "$value" -le 65535 ] || { echo "ERROR: firewall ports must be between 1 and 65535" >&2; exit 1; }
done
command -v ipcalc >/dev/null 2>&1 || { echo "ERROR: ipcalc is required for firewall CIDR validation" >&2; exit 1; }
printf '%s\n' "$LAN_CIDRS" | tr ',' '\n' | while IFS= read -r cidr; do
  cidr=$(printf '%s' "$cidr" | tr -d ' ')
  case "$cidr" in
    ''|*:*|*/*/*) echo "ERROR: LAN_CIDRS must contain non-empty IPv4 CIDRs" >&2; exit 1 ;;
    */*) ;;
    *) echo "ERROR: LAN_CIDRS entry lacks a prefix: $cidr" >&2; exit 1 ;;
  esac
  ipcalc -s "$cidr" >/dev/null 2>&1 || { echo "ERROR: invalid IPv4 CIDR in LAN_CIDRS: $cidr" >&2; exit 1; }
done
log "Configuring nftables LAN-only host firewall for: $LAN_CIDRS"
persist=$(mktemp /tmp/edge-nft-persist.XXXXXX)
live_table=$(mktemp /tmp/edge-nft-table.XXXXXX)
live_tx=$(mktemp /tmp/edge-nft-live.XXXXXX)
old_live=$(mktemp /tmp/edge-nft-old-live.XXXXXX)
rollback_tx=$(mktemp /tmp/edge-nft-rollback.XXXXXX)
persist_backup=$(mktemp /tmp/edge-nft-persist-backup.XXXXXX)
had_live=false; had_persist=false; live_applied=false; persist_installed=false; committed=false
was_boot=false
rc-update show boot 2>/dev/null | grep -q '^[[:space:]]*nftables[[:space:]]' && was_boot=true || true
cleanup() {
  rc=$1
  trap - EXIT HUP INT TERM
  if [ "$committed" != true ]; then
    if [ "$live_applied" = true ]; then
      { printf '%s\n' 'delete table inet edge_filter'; [ "$had_live" = false ] || cat "$old_live"; } >"$rollback_tx"
      nft -f "$rollback_tx" >/dev/null 2>&1 || true
    fi
    if [ "$persist_installed" = true ]; then
      if [ "$had_persist" = true ]; then install -m 600 "$persist_backup" /etc/nftables.nft; else rm -f /etc/nftables.nft; fi
    fi
    if [ "$was_boot" = true ]; then rc-update add nftables boot >/dev/null 2>&1 || true; else rc-update del nftables boot >/dev/null 2>&1 || true; fi
  fi
  rm -f "$persist" "$live_table" "$live_tx" "$old_live" "$rollback_tx" "$persist_backup"
  exit "$rc"
}
trap 'cleanup $?' EXIT
trap 'cleanup 129' HUP
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

render_table() {
cat <<'EOF'
table inet edge_filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept
EOF
printf '%s\n' "$LAN_CIDRS" | tr ',' '\n' | while read -r cidr; do
  cidr=$(printf '%s' "$cidr" | tr -d ' ')
  [ -n "$cidr" ] || continue
  printf '    ip saddr %s tcp dport { 22, %s, %s } accept\n' "$cidr" "$ADGUARD_UI_PORT" "$BESZEL_LISTEN"
  printf '    ip saddr %s udp dport 53 accept\n' "$cidr"
  printf '    ip saddr %s tcp dport 53 accept\n' "$cidr"
done
cat <<'EOF'
    counter drop
  }
}
EOF
}

{
  printf '%s\n' '#!/usr/sbin/nft -f' 'flush ruleset' '# Host input policy only; Docker recreates its forwarding/NAT tables afterward.'
  render_table
  printf '%s\n' 'include "/var/lib/nftables/*.nft"'
} >"$persist"
render_table >"$live_table"
if nft list table inet edge_filter >"$old_live" 2>/dev/null; then had_live=true; fi
{ [ "$had_live" = false ] || printf '%s\n' 'delete table inet edge_filter'; cat "$live_table"; } >"$live_tx"

# Both candidates parse before mutation. A single nft batch atomically deletes
# and recreates only edge_filter; Docker's independent tables are untouched.
nft -c -f "$persist"
nft -c -f "$live_tx"
[ ! -f /etc/nftables.nft ] || { cp -p /etc/nftables.nft "$persist_backup"; had_persist=true; }
nft -f "$live_tx"
live_applied=true
install -m 600 "$persist" /etc/nftables.nft
persist_installed=true
rc-update add nftables boot >/dev/null
committed=true
trap - EXIT HUP INT TERM
rm -f "$persist" "$live_table" "$live_tx" "$old_live" "$rollback_tx" "$persist_backup"
log "Live host-input rules atomically replaced; persistent boot rules installed without touching Docker tables"
