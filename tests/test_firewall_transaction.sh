#!/bin/sh
set -eu
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/edge-firewall-transaction.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail(){ echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$TMP/bin" "$TMP/scripts" "$TMP/etc"
cp "$REPO_DIR/scripts/setup-firewall-nftables.sh" "$REPO_DIR/scripts/lib.sh" "$TMP/scripts/"
sed "s#/etc/edge-monitor.env#$TMP/etc/edge-monitor.env#g" "$TMP/scripts/lib.sh" >"$TMP/scripts/lib.tmp"
mv "$TMP/scripts/lib.tmp" "$TMP/scripts/lib.sh"
sed "s#/etc/nftables.nft#$TMP/etc/nftables.nft#g; s#/var/lib/nftables#$TMP/var/lib/nftables#g" \
  "$TMP/scripts/setup-firewall-nftables.sh" >"$TMP/scripts/firewall.tmp"; mv "$TMP/scripts/firewall.tmp" "$TMP/scripts/setup-firewall-nftables.sh"
printf '%s\n' 'OLD_PERSISTENT_RULES' >"$TMP/etc/nftables.nft"
printf '%s\n' 'table inet edge_filter { chain input { type filter hook input priority 0; policy accept; } }' >"$TMP/live.state"
cat >"$TMP/bin/id" <<'EOF'
#!/bin/sh
echo 0
EOF
cat >"$TMP/bin/nft" <<'EOF'
#!/bin/sh
printf 'nft %s\n' "$*" >>"$NFT_LOG"
case "$1:$2:$3:$4" in
 list:table:inet:edge_filter) cat "$LIVE_STATE" ;;
 delete:table:inet:edge_filter) : >"$LIVE_STATE" ;;
 -c:-f:*)
   [ -z "${REAL_NFT_CHECK:-}" ] || "$REAL_NFT_CHECK" "$3"
   exit 0
   ;;
 -f:*)
   [ "${FAIL_LIVE:-false}" != true ] || exit 1
   cp "$2" "$LIVE_STATE"
   ;;
 *) exit 0 ;;
esac
EOF
cat >"$TMP/bin/rc-update" <<'EOF'
#!/bin/sh
printf 'rc-update %s\n' "$*" >>"${RC_LOG:-/dev/null}"
if [ "$1:$2" = 'show:boot' ]; then [ "${NFT_BOOT:-false}" != true ] || echo ' nftables | boot'; exit 0; fi
if [ "${SIGNAL_ON_ADD:-false}" = true ] && [ "$1:$2:$3" = 'add:nftables:boot' ]; then kill -TERM "$PPID"; sleep 1; fi
exit 0
EOF
cat >"$TMP/bin/ipcalc" <<'EOF'
#!/bin/sh
[ "$1" = -s ] || exit 1
case "$2" in 10.0.0.0/24) exit 0;; *) exit 1;; esac
EOF
chmod 755 "$TMP/bin"/*

# Invalid CIDRs and out-of-range ports must fail before nft mutates anything.
while IFS='|' read -r bad_cidrs bad_ui bad_beszel; do
  : >"$TMP/nft.log"
  set +e
  env PATH="$TMP/bin:$PATH" NFT_LOG="$TMP/nft.log" LIVE_STATE="$TMP/live.state" \
    LAN_CIDRS="$bad_cidrs" ADGUARD_UI_PORT="$bad_ui" BESZEL_LISTEN="$bad_beszel" \
    sh "$TMP/scripts/setup-firewall-nftables.sh" >"$TMP/invalid.out" 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "invalid firewall input was accepted: $bad_cidrs/$bad_ui/$bad_beszel"
  [ ! -s "$TMP/nft.log" ] || fail "invalid firewall input reached nft: $bad_cidrs/$bad_ui/$bad_beszel"
done <<'EOF'
2001:db8::/64|3000|45876
10.0.0.0/24;add-table|3000|45876
10.0.0.0/24|70000|45876
EOF

: >"$TMP/nft.log"
set +e
PATH="$TMP/bin:$PATH" NFT_LOG="$TMP/nft.log" LIVE_STATE="$TMP/live.state" FAIL_LIVE=true \
  LAN_CIDRS=10.0.0.0/24 ADGUARD_UI_PORT=3000 BESZEL_LISTEN=45876 \
  sh "$TMP/scripts/setup-firewall-nftables.sh" >"$TMP/out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'injected live nft failure unexpectedly succeeded'
grep -qx OLD_PERSISTENT_RULES "$TMP/etc/nftables.nft" || fail 'persistent rules changed despite live failure'
grep -q 'policy accept' "$TMP/live.state" || fail 'live firewall lost its old table after replacement failure'
! grep -q '^nft delete table inet edge_filter$' "$TMP/nft.log" || fail 'firewall used a non-atomic delete/load gap'

# TERM after enabling nftables restores its prior absent boot membership.
: >"$TMP/rc.log"
printf '%s\n' 'OLD_PERSISTENT_RULES' >"$TMP/etc/nftables.nft"
printf '%s\n' 'table inet edge_filter { chain input { type filter hook input priority 0; policy accept; } }' >"$TMP/live.state"
set +e
PATH="$TMP/bin:$PATH" NFT_LOG="$TMP/nft.log" RC_LOG="$TMP/rc.log" LIVE_STATE="$TMP/live.state" SIGNAL_ON_ADD=true NFT_BOOT=false \
  LAN_CIDRS=10.0.0.0/24 ADGUARD_UI_PORT=3000 BESZEL_LISTEN=45876 \
  sh "$TMP/scripts/setup-firewall-nftables.sh" >"$TMP/signal.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 143 ] || fail "firewall TERM returned $rc instead of 143"
grep -q '^rc-update del nftables boot$' "$TMP/rc.log" || fail 'firewall TERM did not restore boot membership'
grep -qx OLD_PERSISTENT_RULES "$TMP/etc/nftables.nft" || fail 'firewall TERM did not restore persistent rules'
grep -q 'policy accept' "$TMP/live.state" || fail 'firewall TERM did not restore live rules'

echo 'PASS: nft live replacement and persistence remain rollback-safe'
