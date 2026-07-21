#!/bin/sh
set -eu
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/edge-safety-transactions.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }

make_fake() {
  name=$1; shift
  cat >"$TMP/bin/$name" <<EOF
#!/bin/sh
$*
EOF
  chmod 755 "$TMP/bin/$name"
}
mkdir -p "$TMP/bin"

# Explicit disable must reconcile an already installed/running sync controller.
boot="$TMP/bootstrap"
mkdir -p "$boot"
cp "$REPO_DIR/scripts/bootstrap-alpine.sh" "$REPO_DIR/scripts/lib.sh" "$boot/"
sed "s#/etc/edge-monitor.env#$TMP/edge-monitor.env#g" "$boot/lib.sh" >"$boot/lib.tmp"
mv "$boot/lib.tmp" "$boot/lib.sh"
# Redirect the fixture's host identity files; all other mutations are mocked commands.
sed "s#/etc/hostname#$TMP/hostname#g; s#/etc/localtime#$TMP/localtime#g; s#/etc/timezone#$TMP/timezone#g" \
  "$boot/bootstrap-alpine.sh" >"$boot/bootstrap-alpine.tmp"
mv "$boot/bootstrap-alpine.tmp" "$boot/bootstrap-alpine.sh"
for helper in setup-ssh.sh install-adguardhome.sh install-edge-services.sh install-cleanup-schedule.sh setup-firewall-nftables.sh; do
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$boot/$helper"
  chmod 755 "$boot/$helper"
done
make_fake id 'echo 0'
make_fake apk 'exit 0'
make_fake hostname 'exit 0'
make_fake install 'exit 0'
make_fake rc-service 'printf "rc-service %s\n" "$*" >>"$COMMAND_LOG"; exit 0'
make_fake rc-update 'printf "rc-update %s\n" "$*" >>"$COMMAND_LOG"; exit 0'
: >"$TMP/bootstrap.log"
PATH="$TMP/bin:$PATH" COMMAND_LOG="$TMP/bootstrap.log" INSTALL_ADGUARD_SYNC=false ENABLE_FIREWALL=false \
  sh "$boot/bootstrap-alpine.sh" >/dev/null
[ "$(grep -c '^rc-service adguardhome-sync stop$' "$TMP/bootstrap.log" || true)" -eq 1 ] || fail 'bootstrap disable did not stop adguardhome-sync'
[ "$(grep -c '^rc-update del adguardhome-sync default$' "$TMP/bootstrap.log" || true)" -eq 1 ] || fail 'bootstrap disable did not remove adguardhome-sync from default runlevel'

# Token intake must reject a symlink before touching the system configuration.
mkdir -p "$TMP/token-dir"
printf '%s\n' 'TUNNEL_TOKEN=test-only' >"$TMP/token-dir/real.env"
chmod 600 "$TMP/token-dir/real.env"
ln -s real.env "$TMP/token-dir/token.env"
set +e
PATH="$TMP/bin:$PATH" sh "$REPO_DIR/scripts/apply-tiny-cutover.sh" "$TMP/token-dir/token.env" >"$TMP/token.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'symlink tunnel token was accepted'
grep -qi 'symlink\|regular' "$TMP/token.out" || fail 'token symlink was not explicitly rejected'

# A delegated installer failure must restore the cutover-owned env and token.
cut="$TMP/cutover"; mkdir -p "$cut/scripts" "$cut/etc/cloudflared" "$cut/usr/local/sbin" "$cut/token-dir"
cp "$REPO_DIR/scripts/apply-tiny-cutover.sh" "$REPO_DIR/scripts/lib.sh" "$cut/scripts/"
sed "s#/etc/edge-monitor.env#$cut/etc/edge-monitor.env#g; s#/etc/cloudflared#$cut/etc/cloudflared#g; s#/usr/local/sbin#$cut/usr/local/sbin#g" \
  "$cut/scripts/apply-tiny-cutover.sh" >"$cut/scripts/apply.tmp"; mv "$cut/scripts/apply.tmp" "$cut/scripts/apply-tiny-cutover.sh"
for helper in status-check.sh update-all.sh; do printf '%s\n' '#!/bin/sh' 'exit 0' >"$cut/scripts/$helper"; done
printf '%s\n' '#!/bin/sh' 'exit 1' >"$cut/scripts/install-edge-services.sh"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$cut/scripts/install-cleanup-schedule.sh"
chmod 755 "$cut/scripts/"*.sh
printf '%s\n' 'INSTALL_CLOUDFLARED=false' 'OLD_ENV=keep' >"$cut/etc/edge-monitor.env"
printf '%s\n' 'TUNNEL_TOKEN=old-token' >"$cut/etc/cloudflared/token.env"
printf '%s\n' 'TUNNEL_TOKEN=new-token' >"$cut/token-dir/token.env"; chmod 600 "$cut/token-dir/token.env"; chmod 700 "$cut/token-dir"
make_fake stat 'case "$*" in *fd/3*) echo "0:600:regular file";; *) echo "0:700:directory";; esac'
make_fake install 'exec /usr/bin/install "$@"'
set +e
PATH="$TMP/bin:$PATH" sh "$cut/scripts/apply-tiny-cutover.sh" "$cut/token-dir/token.env" >"$TMP/cutover.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'injected cutover installer failure unexpectedly succeeded'
grep -qx 'OLD_ENV=keep' "$cut/etc/edge-monitor.env" || fail 'cutover did not restore the old env'
! grep -q '^INSTALL_CLOUDFLARED=true$' "$cut/etc/edge-monitor.env" || fail 'cutover retained mutated env keys'
grep -qx 'TUNNEL_TOKEN=old-token' "$cut/etc/cloudflared/token.env" || fail 'cutover did not restore the old token'

echo 'PASS: explicit disable, secure token intake, and cutover rollback'
