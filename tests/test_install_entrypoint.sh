#!/bin/sh
set -eu
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/edge-install-entrypoint.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail(){ echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$TMP/bin" "$TMP/repo/.git" "$TMP/repo/config" "$TMP/repo/scripts"
printf '%s\n' '3.22.0' >"$TMP/alpine-release"
cp "$REPO_DIR/config/edge-monitor.env.example" "$TMP/repo/config/edge-monitor.env.example"

cat >"$TMP/bin/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { echo 0; exit 0; }
exit 1
EOF
cat >"$TMP/bin/apk" <<'EOF'
#!/bin/sh
printf 'apk %s\n' "$*" >>"$COMMAND_LOG"
EOF
cat >"$TMP/bin/git" <<'EOF'
#!/bin/sh
printf 'git %s\n' "$*" >>"$COMMAND_LOG"
EOF
cat >"$TMP/repo/scripts/bootstrap-alpine.sh" <<'EOF'
#!/bin/sh
printf 'bootstrap %s\n' "$*" >>"$COMMAND_LOG"
EOF
chmod 755 "$TMP/bin/"* "$TMP/repo/scripts/bootstrap-alpine.sh"
: >"$TMP/commands.log"

PATH="$TMP/bin:$PATH" COMMAND_LOG="$TMP/commands.log" \
ALPINE_RELEASE_FILE="$TMP/alpine-release" INSTALL_DIR="$TMP/repo" ENV_FILE="$TMP/edge-monitor.env" \
HOSTNAME=test-edge.stoffy.lan INSTALL_BESZEL_AGENT=true BESZEL_KEY=test-key \
BESZEL_HUB_URL=http://hub.test:8090 BESZEL_TOKEN=test-token \
INSTALL_CLOUDFLARED=false ENABLE_FIREWALL=false RUN_BOOTSTRAP=true \
  sh "$REPO_DIR/install.sh" >"$TMP/install.out"

[ "$(grep -c '^bootstrap ' "$TMP/commands.log")" -eq 1 ] || fail 'install.sh did not invoke bootstrap exactly once'
grep -q '^apk update$' "$TMP/commands.log" || fail 'entrypoint did not refresh package indexes'
grep -q '^apk add --no-cache ca-certificates curl git$' "$TMP/commands.log" || fail 'entrypoint did not install prerequisites'
grep -q '^git -C .* fetch --depth 1 origin main$' "$TMP/commands.log" || fail 'entrypoint did not update the existing checkout'
grep -qx 'HOSTNAME="test-edge.stoffy.lan"' "$TMP/edge-monitor.env" || fail 'hostname override was not persisted'
grep -qx 'INSTALL_BESZEL_AGENT="true"' "$TMP/edge-monitor.env" || fail 'Beszel enablement was not persisted'
grep -qx 'BESZEL_HUB_URL="http://hub.test:8090"' "$TMP/edge-monitor.env" || fail 'Beszel Hub override was not persisted'
[ "$(stat -c '%a' "$TMP/edge-monitor.env")" = 600 ] || fail 'operator config is not mode 0600'
! grep -q 'apply-tiny-cutover' "$REPO_DIR/install.sh" || fail 'entrypoint depends on a second cutover command'
grep -q '\[edge-installer\] Running bootstrap' "$TMP/install.out" || fail 'entrypoint did not report the bootstrap stage'

echo 'PASS: install.sh is the single mocked operator entrypoint'
