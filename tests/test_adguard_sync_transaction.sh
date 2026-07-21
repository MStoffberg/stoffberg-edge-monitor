#!/bin/sh
set -eu
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/adguard-sync-transaction.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail(){ echo "FAIL: $*" >&2; exit 1; }
ROOT="$TMP/root"; mkdir -p "$TMP/bin" "$TMP/scripts" "$ROOT/usr/local/bin" "$ROOT/etc/init.d" "$ROOT/etc/adguardhome-sync" "$ROOT/var/log"
cp "$REPO_DIR/scripts/install-adguardhome-sync.sh" "$REPO_DIR/scripts/lib.sh" "$TMP/scripts/"
sed "s#/etc/edge-monitor.env#$ROOT/etc/edge-monitor.env#g" "$TMP/scripts/lib.sh" >"$TMP/scripts/lib.tmp"
mv "$TMP/scripts/lib.tmp" "$TMP/scripts/lib.sh"
sed "s#/usr/local/bin/adguardhome-sync#$ROOT/usr/local/bin/adguardhome-sync#g; s#/etc/init.d/adguardhome-sync#$ROOT/etc/init.d/adguardhome-sync#g; s#/etc/adguardhome-sync#$ROOT/etc/adguardhome-sync#g; s#/var/log/adguardhome-sync.log#$ROOT/var/log/adguardhome-sync.log#g" \
  "$TMP/scripts/install-adguardhome-sync.sh" >"$TMP/scripts/install.tmp"
mv "$TMP/scripts/install.tmp" "$TMP/scripts/install-adguardhome-sync.sh"
mkdir -p "$TMP/config"
printf '%s\n' 'origin:' '  url: http://source' >"$TMP/config/adguardhome-sync.yaml.example"
# The installer resolves ../config from its copied script directory.
cp "$TMP/config/adguardhome-sync.yaml.example" "$ROOT/etc/adguardhome-sync/adguardhome-sync.yaml"

cat >"$TMP/bin/id" <<'EOF'
#!/bin/sh
echo 0
EOF
cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
out=; while [ "$#" -gt 0 ]; do [ "$1" = -o ] && { shift; out=$1; }; shift; done
: >"$out"
EOF
cat >"$TMP/bin/tar" <<'EOF'
#!/bin/sh
dir=; while [ "$#" -gt 0 ]; do [ "$1" = -C ] && { shift; dir=$1; }; shift; done
cat >"$dir/adguardhome-sync" <<'BIN'
#!/bin/sh
echo 'adguardhome-sync version new'
BIN
chmod 755 "$dir/adguardhome-sync"
EOF
cat >"$TMP/bin/rc-service" <<'EOF'
#!/bin/sh
printf 'rc-service %s\n' "$*" >>"$STATE_LOG"
case "$2" in
 status) [ "${WAS_RUNNING:-true}" = true ] ;;
 start) [ "${FAIL_START:-false}" != true ] ;;
 *) exit 0 ;;
esac
EOF
cat >"$TMP/bin/rc-update" <<'EOF'
#!/bin/sh
printf 'rc-update %s\n' "$*" >>"$STATE_LOG"
if [ "$1" = show ]; then [ "${WAS_ENABLED:-false}" = true ] && echo ' adguardhome-sync | default'; fi
exit 0
EOF
cat >"$TMP/bin/install" <<'EOF'
#!/bin/sh
last=
for arg in "$@"; do last=$arg; done
/usr/bin/install "$@"
if [ "${SIGNAL_CONFIG_INSTALL:-false}" = true ] && [ "$last" = "${CONFIG_PATH:-}" ]; then kill -TERM "$PPID"; sleep 1; fi
EOF
chmod 755 "$TMP/bin"/*

printf '%s\n' old-binary >"$ROOT/usr/local/bin/adguardhome-sync"; chmod 755 "$ROOT/usr/local/bin/adguardhome-sync"
printf '%s\n' old-init >"$ROOT/etc/init.d/adguardhome-sync"; chmod 755 "$ROOT/etc/init.d/adguardhome-sync"
printf '%s\n' 'ADGUARD_SYNC_CUTOVER_APPROVED=true' >"$ROOT/etc/adguardhome-sync/recurring-sync-cutover-approved"
: >"$TMP/state.log"
set +e
PATH="$TMP/bin:$PATH" STATE_LOG="$TMP/state.log" WAS_RUNNING=true WAS_ENABLED=false FAIL_START=true ADGUARDHOME_SYNC_VERSION=v1 \
  sh "$TMP/scripts/install-adguardhome-sync.sh" >"$TMP/install-fail.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'injected sync startup failure unexpectedly succeeded'
grep -qx old-binary "$ROOT/usr/local/bin/adguardhome-sync" || fail 'installer did not restore old binary'
grep -qx old-init "$ROOT/etc/init.d/adguardhome-sync" || fail 'installer did not restore old init script'
if ! grep -q '^rc-update del adguardhome-sync default$' "$TMP/state.log"; then
  printf '%s\n' '--- installer output ---' >&2
  cat "$TMP/install-fail.out" >&2
  printf '%s\n' '--- state log ---' >&2
  cat "$TMP/state.log" >&2
  fail 'installer did not restore disabled runlevel state'
fi
[ "$(grep -c '^rc-service adguardhome-sync start$' "$TMP/state.log")" -ge 2 ] || fail 'installer did not restore prior running state after failed candidate start'

# A configured file alone must not enable recurring writes before an explicit marker.
rm -f "$ROOT/etc/adguardhome-sync/recurring-sync-cutover-approved"
: >"$TMP/state.log"
PATH="$TMP/bin:$PATH" STATE_LOG="$TMP/state.log" WAS_RUNNING=false WAS_ENABLED=false FAIL_START=false ADGUARDHOME_SYNC_VERSION=v1 \
  sh "$TMP/scripts/install-adguardhome-sync.sh" >/dev/null
! grep -q '^rc-update add adguardhome-sync default$' "$TMP/state.log" || fail 'installer auto-enabled recurring sync before cutover approval'
! grep -q '^rc-service adguardhome-sync start$' "$TMP/state.log" || fail 'installer auto-started recurring sync before cutover approval'

# TERM immediately after creating a previously absent config removes it and
# restores a service that was running before the transaction.
rm -f "$ROOT/etc/adguardhome-sync/adguardhome-sync.yaml"
: >"$TMP/state.log"
set +e
PATH="$TMP/bin:$PATH" STATE_LOG="$TMP/state.log" WAS_RUNNING=true WAS_ENABLED=true SIGNAL_CONFIG_INSTALL=true \
  CONFIG_PATH="$ROOT/etc/adguardhome-sync/adguardhome-sync.yaml" ADGUARDHOME_SYNC_VERSION=v1 \
  sh "$TMP/scripts/install-adguardhome-sync.sh" >"$TMP/signal.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 143 ] || fail "AdGuard installer TERM returned $rc instead of 143"
[ ! -e "$ROOT/etc/adguardhome-sync/adguardhome-sync.yaml" ] || fail 'TERM left newly created config behind'
grep -q '^rc-service adguardhome-sync start$' "$TMP/state.log" || fail 'TERM did not restore prior running service'
grep -q '^rc-update add adguardhome-sync default$' "$TMP/state.log" || fail 'TERM did not restore prior runlevel'

echo 'PASS: adguardhome-sync installer restores state and requires explicit cutover approval'
