#!/bin/sh
set -eu
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/edge-cleanup-runtime.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/scripts" "$TMP/etc"
cp "$REPO_DIR/scripts/edge-cleanup.sh" "$REPO_DIR/scripts/lib.sh" "$TMP/scripts/"
sed "s#/etc/edge-monitor.env#$TMP/etc/edge-monitor.env#g" "$TMP/scripts/lib.sh" >"$TMP/scripts/lib.tmp"
mv "$TMP/scripts/lib.tmp" "$TMP/scripts/lib.sh"
log="$TMP/commands.log"

cat >"$TMP/bin/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = "-u" ] && { echo 0; exit 0; }
exec /usr/bin/id "$@"
EOF
cat >"$TMP/bin/df" <<'EOF'
#!/bin/sh
use=${FAKE_DF_USE:-64}
if [ "${1:-}" = "-P" ]; then
  echo 'Filesystem 1024-blocks Used Available Capacity Mounted on'
  echo "/dev/root 100 $use $((100-use)) ${use}% /"
else
  echo "/dev/root 100M ${use}M $((100-use))M ${use}% /"
fi
EOF
for cmd in apk docker find rm; do
  cat >"$TMP/bin/$cmd" <<EOF
#!/bin/sh
printf '%s %s\n' '$cmd' "\$*" >>'${log}'
exit 0
EOF
done
cat >"$TMP/bin/apk" <<EOF
#!/bin/sh
printf '%s %s\n' apk "\$*" >>'${log}'
[ "\${SIGNAL_APK:-false}" != true ] || { kill -TERM "\$PPID"; sleep 1; }
exit 0
EOF
chmod 755 "$TMP/bin"/*

run_cleanup() {
  use=$1
  : >"$log"
  PATH="$TMP/bin:$PATH" FAKE_DF_USE="$use" CLEANUP_LOCK_DIR="$TMP/lock" CLEANUP_LOG_FILE="$TMP/cleanup.log" \
    CLEANUP_MIN_DISK_PERCENT=70 CLEANUP_DOCKER_IMAGES=true CLEANUP_DOCKER_BUILD_CACHE=false \
    sh "$TMP/scripts/edge-cleanup.sh" --apply >/dev/null
}

run_cleanup 64
grep -q '^apk cache clean' "$log"
grep -q '^find /tmp ' "$log"
! grep -q '^docker image prune' "$log"

run_cleanup 80
grep -q '^docker image prune -f --filter until=168h' "$log"
! grep -q '^docker system prune' "$log"
! grep -q '^docker volume prune' "$log"
! grep -q '^docker container prune' "$log"

: >"$log"
set +e
PATH="$TMP/bin:$PATH" SIGNAL_APK=true FAKE_DF_USE=80 CLEANUP_LOCK_DIR="$TMP/lock" CLEANUP_LOG_FILE="$TMP/cleanup.log" \
  CLEANUP_MIN_DISK_PERCENT=70 CLEANUP_DOCKER_IMAGES=true CLEANUP_DOCKER_BUILD_CACHE=false \
  sh "$TMP/scripts/edge-cleanup.sh" --apply >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 143 ] || { echo "FAIL: cleanup TERM returned $rc instead of 143" >&2; exit 1; }
[ ! -d "$TMP/lock" ] || { echo 'FAIL: cleanup TERM left lock behind' >&2; exit 1; }
! grep -q '^rm ' "$log" || { echo 'FAIL: cleanup continued destructively after TERM' >&2; exit 1; }

echo 'PASS: cleanup runtime threshold and prune safety'
