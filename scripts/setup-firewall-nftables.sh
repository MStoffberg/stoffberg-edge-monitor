#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

log "Configuring nftables LAN-only firewall for: $LAN_CIDRS"
TMP=/tmp/edge-monitor-nftables.conf
{
cat <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  set lan4 {
    type ipv4_addr
    flags interval
    elements = {
EOF
# shellcheck disable=SC2086
printf '%s' "$LAN_CIDRS" | tr ',' '\n' | while read -r cidr; do
  cidr=$(printf '%s' "$cidr" | tr -d ' ')
  [ -n "$cidr" ] && printf '      %s,\n' "$cidr"
done
cat <<EOF
    }
  }

  chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    ip protocol icmp accept
    ip6 nexthdr ipv6-icmp accept

    ip saddr @lan4 tcp dport { 22, ${ADGUARD_UI_PORT}, ${UPTIME_KUMA_PORT} } accept
    ip saddr @lan4 udp dport 53 accept
    ip saddr @lan4 tcp dport 53 accept

    counter drop
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
EOF
} > "$TMP"

nft -c -f "$TMP"
install -m 600 "$TMP" /etc/nftables.conf
rc-update add nftables boot || true
rc-service nftables restart || rc-service nftables start
