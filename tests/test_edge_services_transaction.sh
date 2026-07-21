#!/bin/sh
set -eu
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/edge-services-transaction.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail(){ echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$TMP/bin" "$TMP/scripts" "$TMP/service" "$TMP/etc/cloudflared"
cp "$REPO_DIR/scripts/install-edge-services.sh" "$REPO_DIR/scripts/render-edge-compose.sh" "$REPO_DIR/scripts/lib.sh" "$TMP/scripts/"
sed "s#/etc/edge-monitor.env#$TMP/etc/edge-monitor.env#g" "$TMP/scripts/lib.sh" >"$TMP/scripts/lib.tmp"
mv "$TMP/scripts/lib.tmp" "$TMP/scripts/lib.sh"
sed "s#/opt/edge-services#$TMP/service#g; s#/etc/cloudflared#$TMP/etc/cloudflared#g" "$TMP/scripts/install-edge-services.sh" >"$TMP/scripts/install-edge-services.tmp"
mv "$TMP/scripts/install-edge-services.tmp" "$TMP/scripts/install-edge-services.sh"
printf '%s\n' 'TUNNEL_TOKEN=test-only' >"$TMP/etc/cloudflared/token.env"
chmod 700 "$TMP/etc/cloudflared"
chmod 600 "$TMP/etc/cloudflared/token.env"
printf '%s\n' 'OLD_ENV=keep' >"$TMP/service/.env"
printf '%s\n' 'services: {legacy: {image: old}}' >"$TMP/service/docker-compose.yml"

cat >"$TMP/bin/id" <<'EOF'
#!/bin/sh
echo 0
EOF
cat >"$TMP/bin/stat" <<'EOF'
#!/bin/sh
case "$*" in */cloudflared) echo '0:700:directory';; *) echo '0:600:regular file';; esac
EOF
cat >"$TMP/bin/docker" <<'EOF'
#!/bin/sh
printf 'docker %s\n' "$*" >>"$DOCKER_LOG"
case "$*" in
  'compose '*config*'--services'|'compose config --services') printf '%s\n' beszel-agent cloudflared ;;
  'compose '*config*) exit 0 ;;
  'compose pull '*) exit 0 ;;
  'container inspect beszel-agent') [ "${OLD_BESZEL:-true}" = true ] ;;
  'container inspect cloudflared') [ "${OLD_CLOUDFLARED:-true}" = true ] ;;
  'inspect -f {{ index .Config.Labels "com.docker.compose.project" }} beszel-agent') echo legacy ;;
  'inspect -f {{.State.Running}} beszel-agent') echo true ;;
  'inspect -f {{.State.Running}} cloudflared') echo true ;;
  'inspect -f {{.RestartCount}} beszel-agent'|'inspect -f {{.RestartCount}} cloudflared') echo 0 ;;
  'compose up -d --no-deps cloudflared')
    [ "${SIGNAL_CLOUDFLARED_UP:-false}" != true ] || { kill -"${INJECT_SIGNAL:-TERM}" "$PPID"; sleep 1; }
    [ "${FAIL_CLOUDFLARED_UP:-false}" != true ]
    ;;
  'logs cloudflared') echo 'INF Registered tunnel connection connIndex=0' ;;
  *) exit 0 ;;
esac
EOF
cat >"$TMP/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$TMP/bin"/*

common_env="PATH=$TMP/bin:$PATH DOCKER_LOG=$TMP/docker.log INSTALL_BESZEL_AGENT=true BESZEL_AGENT_IMAGE=beszel:test BESZEL_LISTEN=45876 BESZEL_KEY=key BESZEL_HUB_URL=http://hub BESZEL_TOKEN=token INSTALL_CLOUDFLARED=true CLOUDFLARED_IMAGE=cloudflared:test CLOUDFLARED_TOKEN_FILE=$TMP/etc/cloudflared/token.env EDGE_STABILITY_CHECKS=2 EDGE_STABILITY_INTERVAL=1"
: >"$TMP/docker.log"
set +e
env $common_env FAIL_CLOUDFLARED_UP=true sh "$TMP/scripts/install-edge-services.sh" >"$TMP/failure.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'late Cloudflared failure unexpectedly succeeded'
grep -qx 'OLD_ENV=keep' "$TMP/service/.env" || fail 'late failure did not restore live env'
grep -qx 'services: {legacy: {image: old}}' "$TMP/service/docker-compose.yml" || fail 'late failure did not restore live compose'
grep -q 'docker rename beszel-agent-before-edge-.* beszel-agent' "$TMP/docker.log" || { cat "$TMP/docker.log" >&2; fail 'late failure did not restore legacy Beszel container'; }
grep -q '^docker start beszel-agent$' "$TMP/docker.log" || fail 'late failure did not restart legacy Beszel container'

# Incomplete desired credentials must fail closed while a stale privileged agent exists.
: >"$TMP/docker.log"
set +e
env PATH="$TMP/bin:$PATH" DOCKER_LOG="$TMP/docker.log" INSTALL_BESZEL_AGENT=true BESZEL_KEY= BESZEL_HUB_URL=http://hub BESZEL_TOKEN=token \
  INSTALL_CLOUDFLARED=false CLOUDFLARED_TOKEN_FILE="$TMP/etc/cloudflared/token.env" \
  sh "$TMP/scripts/install-edge-services.sh" >"$TMP/incomplete.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'incomplete Beszel credentials left stale container running'
grep -qi 'incomplete.*Beszel\|Beszel.*incomplete' "$TMP/incomplete.out" || fail 'incomplete credentials did not produce fail-closed diagnostic'
grep -q '^docker stop beszel-agent$' "$TMP/docker.log" || fail 'incomplete Beszel credentials did not stop stale agent'
grep -q 'docker rename beszel-agent beszel-agent-invalid-' "$TMP/docker.log" || fail 'incomplete Beszel credentials did not quarantine stale agent'

# A zero-length stability gate is forbidden.
: >"$TMP/docker.log"
set +e
env $common_env EDGE_STABILITY_CHECKS=0 sh "$TMP/scripts/install-edge-services.sh" >"$TMP/zero.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail 'zero stability checks were accepted'
[ ! -s "$TMP/docker.log" ] || fail 'invalid stability settings reached Docker'

# HUP, INT, and TERM during replacement must restore both old containers and
# return deliberate nonzero signal statuses.
for pair in HUP:129 INT:130 TERM:143; do
  signal=${pair%%:*}; expected=${pair#*:}
  : >"$TMP/docker.log"
  set +e
  env $common_env SIGNAL_CLOUDFLARED_UP=true INJECT_SIGNAL="$signal" sh "$TMP/scripts/install-edge-services.sh" >"$TMP/signal-$signal.out" 2>&1
  rc=$?
  set -e
  [ "$rc" -eq "$expected" ] || fail "edge installer $signal returned $rc instead of $expected"
  grep -q '^docker start beszel-agent$' "$TMP/docker.log" || fail "$signal did not restore Beszel"
  grep -q '^docker start cloudflared$' "$TMP/docker.log" || fail "$signal did not restore Cloudflared"
done

# Successful local checks preserve rollback containers pending external owner verification.
: >"$TMP/docker.log"
env $common_env sh "$TMP/scripts/install-edge-services.sh" >"$TMP/success.out" 2>&1
! grep -q '^docker rm .*before-edge' "$TMP/docker.log" || fail 'local gate deleted owner-verification rollback containers'
grep -q '^docker logs cloudflared$' "$TMP/docker.log" || fail 'Cloudflared gate did not inspect local logs'

echo 'PASS: whole edge-service transaction restores configuration and legacy container'
