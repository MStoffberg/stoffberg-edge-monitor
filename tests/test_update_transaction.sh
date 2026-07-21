#!/bin/sh
set -eu
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/edge-update-transaction.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail(){ echo "FAIL: $*" >&2; exit 1; }
ROOT="$TMP/root"; mkdir -p "$TMP/bin" "$TMP/scripts" "$ROOT/usr/local/bin" "$ROOT/opt" "$ROOT/etc"
cp "$REPO_DIR/scripts/update-all.sh" "$REPO_DIR/scripts/lib.sh" "$TMP/scripts/"
sed "s#/etc/edge-monitor.env#$ROOT/etc/edge-monitor.env#g" "$TMP/scripts/lib.sh" >"$TMP/scripts/lib.tmp"
mv "$TMP/scripts/lib.tmp" "$TMP/scripts/lib.sh"
sed "s#/usr/local/bin/adguardhome-sync#$ROOT/usr/local/bin/adguardhome-sync#g; s#/opt/AdGuardHome#$ROOT/opt/AdGuardHome#g; s#/opt/edge-services#$ROOT/opt/edge-services#g" \
  "$TMP/scripts/update-all.sh" >"$TMP/scripts/update.tmp"; mv "$TMP/scripts/update.tmp" "$TMP/scripts/update-all.sh"
cat >"$ROOT/usr/local/bin/adguardhome-sync" <<'EOF'
#!/bin/sh
echo 'adguardhome-sync version 0.9.1'
EOF
chmod 755 "$ROOT/usr/local/bin/adguardhome-sync"
cat >"$TMP/bin/id" <<'EOF'
#!/bin/sh
echo 0
EOF
cat >"$TMP/bin/apk" <<'EOF'
#!/bin/sh
if [ "$1" = version ]; then [ "${PACKAGE_UPDATE:-false}" != true ] || echo 'pkg-1 < pkg-2'; exit 0; fi
[ "$1" != upgrade ] || [ "${FAIL_APK_UPGRADE:-false}" != true ]
EOF
cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
case "$*" in
 *api.github.com*) printf '%s\n' '{"tag_name": "v0.9.2"}' ;;
 *) out=; while [ "$#" -gt 0 ]; do [ "$1" = -o ] && { shift; out=$1; }; shift; done; : >"$out" ;;
esac
EOF
cat >"$TMP/bin/tar" <<'EOF'
#!/bin/sh
dir=; while [ "$#" -gt 0 ]; do [ "$1" = -C ] && { shift; dir=$1; }; shift; done
cat >"$dir/adguardhome-sync" <<'BIN'
#!/bin/sh
echo 'adguardhome-sync version 0.9.2'
BIN
chmod 755 "$dir/adguardhome-sync"
EOF
cat >"$TMP/bin/rc-service" <<'EOF'
#!/bin/sh
printf 'rc-service %s\n' "$*" >>"$STATE_LOG"
case "$2" in
  status) exit 0;;
  stop)
    if [ "${SIGNAL_UPDATE:-false}" = true ] && [ ! -e "$SIGNAL_ONCE" ]; then
      : >"$SIGNAL_ONCE"
      kill -"${INJECT_SIGNAL:-TERM}" "$PPID"
      sleep 1
    fi
    exit 0
    ;;
  start) [ "${FAIL_SYNC_START:-false}" != true ];;
  *) exit 0;;
esac
EOF
cat >"$TMP/bin/rc-update" <<'EOF'
#!/bin/sh
printf 'rc-update %s\n' "$*" >>"$STATE_LOG"
[ "$1" = show ] && echo ' adguardhome-sync | default'
exit 0
EOF
cat >"$TMP/bin/edge-cleanup" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$TMP/scripts/install-edge-services.sh" <<'EOF'
#!/bin/sh
printf '%s\n' delegated >>"$EDGE_INSTALL_LOG"
exit 0
EOF
chmod 755 "$TMP/bin"/* "$TMP/scripts/install-edge-services.sh"
: >"$TMP/state.log"

# A requested Alpine upgrade failure must abort instead of reporting success.
set +e
PATH="$ROOT/usr/local/bin:$TMP/bin:$PATH" STATE_LOG="$TMP/state.log" PACKAGE_UPDATE=true FAIL_APK_UPGRADE=true ASSUME_YES=true \
  sh "$TMP/scripts/update-all.sh" >"$TMP/apk-failure.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'failed apk upgrade was masked'
! grep -q 'Done' "$TMP/apk-failure.out" || fail 'failed apk upgrade reported completion'

# A failed candidate restart must restore the old binary and service state.
: >"$TMP/state.log"
set +e
PATH="$ROOT/usr/local/bin:$TMP/bin:$PATH" STATE_LOG="$TMP/state.log" FAIL_SYNC_START=true ASSUME_YES=true sh "$TMP/scripts/update-all.sh" >"$TMP/out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'injected updater restart failure unexpectedly succeeded'
"$ROOT/usr/local/bin/adguardhome-sync" --version | grep -q '0.9.1' || fail 'updater did not restore old binary'
[ "$(grep -c '^rc-service adguardhome-sync start$' "$TMP/state.log")" -ge 2 ] || fail 'updater did not attempt to restore prior running state'
grep -q '^rc-update add adguardhome-sync default$' "$TMP/state.log" || fail 'updater did not restore prior runlevel membership'

# Every supported signal must restore the old candidate and return deliberately.
for pair in HUP:129 INT:130 TERM:143; do
  signal=${pair%%:*}; expected=${pair#*:}
  cat >"$ROOT/usr/local/bin/adguardhome-sync" <<'EOF'
#!/bin/sh
echo 'adguardhome-sync version 0.9.1'
EOF
  chmod 755 "$ROOT/usr/local/bin/adguardhome-sync"
  : >"$TMP/state.log"; rm -f "$TMP/signal.once"
  set +e
  PATH="$ROOT/usr/local/bin:$TMP/bin:$PATH" STATE_LOG="$TMP/state.log" SIGNAL_UPDATE=true SIGNAL_ONCE="$TMP/signal.once" INJECT_SIGNAL="$signal" ASSUME_YES=true \
    sh "$TMP/scripts/update-all.sh" >"$TMP/signal-$signal.out" 2>&1
  rc=$?
  set -e
  [ "$rc" -eq "$expected" ] || fail "updater $signal returned $rc instead of $expected"
  "$ROOT/usr/local/bin/adguardhome-sync" --version | grep -q '0.9.1' || fail "updater $signal did not restore old binary"
  grep -q '^rc-service adguardhome-sync start$' "$TMP/state.log" || fail "updater $signal did not restore running service"
done

# Routine container reconciliation must delegate to the transactional installer.
cat >"$ROOT/usr/local/bin/adguardhome-sync" <<'EOF'
#!/bin/sh
echo 'adguardhome-sync version 0.9.2'
EOF
chmod 755 "$ROOT/usr/local/bin/adguardhome-sync"
mkdir -p "$ROOT/opt/edge-services"
printf '%s\n' 'services: {}' >"$ROOT/opt/edge-services/docker-compose.yml"
: >"$TMP/edge-install.log"
PATH="$ROOT/usr/local/bin:$TMP/bin:$PATH" STATE_LOG="$TMP/state.log" EDGE_INSTALL_LOG="$TMP/edge-install.log" ASSUME_YES=true \
  sh "$TMP/scripts/update-all.sh" >"$TMP/delegation.out" 2>&1
grep -qx delegated "$TMP/edge-install.log" || fail 'updater bypassed the transactional edge installer'

echo 'PASS: routine updates abort safely, restore signals, and delegate container transactions'
