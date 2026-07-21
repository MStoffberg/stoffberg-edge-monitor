#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root
umask 077

SERVICE_DIR=${EDGE_SERVICE_DIR:-/opt/edge-services}
STABILITY_CHECKS=${EDGE_STABILITY_CHECKS:-3}
STABILITY_INTERVAL=${EDGE_STABILITY_INTERVAL:-5}
case "$INSTALL_BESZEL_AGENT:$INSTALL_CLOUDFLARED" in
  true:true|true:false|false:true|false:false) ;;
  *) echo "ERROR: INSTALL_BESZEL_AGENT and INSTALL_CLOUDFLARED must be true or false" >&2; exit 1 ;;
esac
for setting in "$STABILITY_CHECKS" "$STABILITY_INTERVAL"; do
  case "$setting" in ''|*[!0-9]*) echo "ERROR: stability settings must be positive integers" >&2; exit 1;; esac
  [ "$setting" -gt 0 ] || { echo "ERROR: stability settings must be positive integers" >&2; exit 1; }
done

# Invalid enabled credentials are a safety reconciliation, not a no-op: any
# stale privileged container is stopped and retained under a quarantine name.
quarantine_invalid() {
  name=$1
  docker container inspect "$name" >/dev/null 2>&1 || return 0
  saved="$name-invalid-$(date +%Y%m%d-%H%M%S)"
  docker stop "$name" >/dev/null
  docker rename "$name" "$saved"
  echo "ERROR: quarantined stale $name as $saved" >&2
}

if [ "$INSTALL_BESZEL_AGENT" = true ] && { [ -z "$BESZEL_KEY" ] || [ -z "$BESZEL_HUB_URL" ] || [ -z "$BESZEL_TOKEN" ]; }; then
  quarantine_invalid beszel-agent
  echo "ERROR: incomplete Beszel credentials" >&2
  exit 1
fi

if [ "$INSTALL_CLOUDFLARED" = true ]; then
  # The normal path has the same pathname-race boundary as cutover: protected
  # parent, non-symlink regular root file, one open descriptor for metadata and
  # content validation. Never chmod a caller-selected pathname.
  token_dir=$(dirname -- "$CLOUDFLARED_TOKEN_FILE")
  if [ "$CLOUDFLARED_TOKEN_FILE" = /etc/cloudflared/token.env ] && [ ! -e "$token_dir" ]; then
    install -d -m 700 -o root -g root "$token_dir"
  fi
  token_ok=true
  [ ! -L "$CLOUDFLARED_TOKEN_FILE" ] && [ -f "$CLOUDFLARED_TOKEN_FILE" ] || token_ok=false
  if [ "$token_ok" = true ]; then
    exec 3<"$CLOUDFLARED_TOKEN_FILE" || token_ok=false
  fi
  if [ "$token_ok" = true ]; then
    [ "$(stat -Lc '%u:%a:%F' "/proc/$$/fd/3")" = '0:600:regular file' ] || token_ok=false
    [ "$(stat -Lc '%u:%a:%F' "$token_dir")" = '0:700:directory' ] || token_ok=false
  fi
  if [ "$token_ok" = true ]; then
    grep -q '^TUNNEL_TOKEN=.' <&3 || token_ok=false
    exec 3<&-
  fi
  if [ "$token_ok" != true ]; then
    exec 3<&- 2>/dev/null || true
    quarantine_invalid cloudflared
    echo "ERROR: Cloudflared token must be a root-owned 0600 regular non-symlink file in a root-owned 0700 directory and contain TUNNEL_TOKEN=<token>" >&2
    exit 1
  fi
fi

log "Reconciling Tiny Edge containers (Beszel Agent and Cloudflared)"
mkdir -p "$SERVICE_DIR/beszel_agent_data"
chmod 700 "$SERVICE_DIR"

env_tmp=$(mktemp "$SERVICE_DIR/.env.candidate.XXXXXX")
compose_tmp=$(mktemp "$SERVICE_DIR/docker-compose.candidate.XXXXXX")
env_backup=$(mktemp "$SERVICE_DIR/.env.backup.XXXXXX")
compose_backup=$(mktemp "$SERVICE_DIR/docker-compose.backup.XXXXXX")
env_had=false; compose_had=false; installed=false; committed=false
beszel_rollback=; cloudflared_rollback=
rollback() {
  rc=$1
  trap - EXIT HUP INT TERM
  if [ "$committed" != true ]; then
    if [ -n "$beszel_rollback" ]; then
      docker rm -f beszel-agent >/dev/null 2>&1 || true
      docker rename "$beszel_rollback" beszel-agent >/dev/null 2>&1 || true
      docker start beszel-agent >/dev/null 2>&1 || true
    fi
    if [ -n "$cloudflared_rollback" ]; then
      docker rm -f cloudflared >/dev/null 2>&1 || true
      docker rename "$cloudflared_rollback" cloudflared >/dev/null 2>&1 || true
      docker start cloudflared >/dev/null 2>&1 || true
    fi
    if [ "$installed" = true ]; then
      if [ "$env_had" = true ]; then install -m 600 "$env_backup" "$SERVICE_DIR/.env"; else rm -f "$SERVICE_DIR/.env"; fi
      if [ "$compose_had" = true ]; then install -m 600 "$compose_backup" "$SERVICE_DIR/docker-compose.yml"; else rm -f "$SERVICE_DIR/docker-compose.yml"; fi
      if [ "$compose_had" = true ]; then (cd "$SERVICE_DIR" && docker compose up -d >/dev/null 2>&1) || true; fi
    fi
  fi
  rm -f "$env_tmp" "$compose_tmp" "$env_backup" "$compose_backup"
  exit "$rc"
}
trap 'rollback $?' EXIT
trap 'rollback 129' HUP
trap 'rollback 130' INT
trap 'rollback 143' TERM

cat >"$env_tmp" <<EOF
BESZEL_AGENT_IMAGE=$BESZEL_AGENT_IMAGE
BESZEL_LISTEN=$BESZEL_LISTEN
BESZEL_KEY=$BESZEL_KEY
BESZEL_HUB_URL=$BESZEL_HUB_URL
BESZEL_TOKEN=$BESZEL_TOKEN
CLOUDFLARED_IMAGE=$CLOUDFLARED_IMAGE
CLOUDFLARED_TOKEN_FILE=$CLOUDFLARED_TOKEN_FILE
EOF
chmod 600 "$env_tmp"
INSTALL_BESZEL_AGENT="$INSTALL_BESZEL_AGENT" BESZEL_AGENT_IMAGE="$BESZEL_AGENT_IMAGE" BESZEL_LISTEN="$BESZEL_LISTEN" \
BESZEL_KEY="$BESZEL_KEY" BESZEL_HUB_URL="$BESZEL_HUB_URL" BESZEL_TOKEN="$BESZEL_TOKEN" \
INSTALL_CLOUDFLARED="$INSTALL_CLOUDFLARED" CLOUDFLARED_IMAGE="$CLOUDFLARED_IMAGE" CLOUDFLARED_TOKEN_FILE="$CLOUDFLARED_TOKEN_FILE" \
  sh "$SCRIPT_DIR/render-edge-compose.sh" >"$compose_tmp"
chmod 600 "$compose_tmp"

docker compose --env-file "$env_tmp" -f "$compose_tmp" config >/dev/null
services=$(docker compose --env-file "$env_tmp" -f "$compose_tmp" config --services)
for service in beszel-agent cloudflared; do
  if printf '%s\n' "$services" | grep -qx "$service"; then docker compose --env-file "$env_tmp" -f "$compose_tmp" pull "$service"; fi
done

[ ! -f "$SERVICE_DIR/.env" ] || { cp -p "$SERVICE_DIR/.env" "$env_backup"; env_had=true; }
[ ! -f "$SERVICE_DIR/docker-compose.yml" ] || { cp -p "$SERVICE_DIR/docker-compose.yml" "$compose_backup"; compose_had=true; }
mv "$env_tmp" "$SERVICE_DIR/.env"
mv "$compose_tmp" "$SERVICE_DIR/docker-compose.yml"
installed=true
cd "$SERVICE_DIR"

quarantine_if_present() {
  name=$1
  case "$name" in beszel-agent) [ -z "$beszel_rollback" ] || return 0;; cloudflared) [ -z "$cloudflared_rollback" ] || return 0;; esac
  docker container inspect "$name" >/dev/null 2>&1 || return 0
  saved="$name-before-edge-$(date +%Y%m%d-%H%M%S)"
  docker stop "$name" >/dev/null
  docker rename "$name" "$saved"
  case "$name" in beszel-agent) beszel_rollback=$saved;; cloudflared) cloudflared_rollback=$saved;; esac
}

# Quarantine Compose-managed and legacy containers alike. This makes an image
# replacement rollback-capable instead of allowing Compose to destroy the old
# container before the candidate has passed its local gate.
if [ "$INSTALL_BESZEL_AGENT" = true ]; then
  legacy=false
  if docker container inspect beszel-agent >/dev/null 2>&1; then
    project=$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' beszel-agent 2>/dev/null || true)
    [ "$project" = edge-services ] || legacy=true
  fi
  quarantine_if_present beszel-agent
  if [ "$legacy" = true ] && [ -d /opt/uptime-kuma/beszel_agent_data ]; then cp -a /opt/uptime-kuma/beszel_agent_data/. "$SERVICE_DIR/beszel_agent_data/"; fi
  docker compose up -d --no-deps beszel-agent
else
  quarantine_if_present beszel-agent
fi
if [ "$INSTALL_CLOUDFLARED" = true ]; then quarantine_if_present cloudflared; docker compose up -d --no-deps cloudflared; else quarantine_if_present cloudflared; fi

stable_container() {
  name=$1
  [ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ] || { echo "ERROR: $name did not start" >&2; return 1; }
  restarts=$(docker inspect -f '{{.RestartCount}}' "$name")
  count=0
  while [ "$count" -lt "$STABILITY_CHECKS" ]; do
    sleep "$STABILITY_INTERVAL"
    [ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ] || { echo "ERROR: $name stopped during stability check" >&2; return 1; }
    now=$(docker inspect -f '{{.RestartCount}}' "$name")
    [ "$now" = "$restarts" ] || { echo "ERROR: $name restart count changed during stability check" >&2; return 1; }
    count=$((count + 1))
  done
}
[ "$INSTALL_BESZEL_AGENT" != true ] || stable_container beszel-agent
if [ "$INSTALL_CLOUDFLARED" = true ]; then
  stable_container cloudflared
  docker logs cloudflared 2>&1 | grep -Eq 'Registered tunnel connection|Connection [^ ]+ registered' || {
    echo "ERROR: cloudflared has no local tunnel-registration evidence" >&2
    exit 1
  }
fi

# Local acceptance is not external route or Beszel Hub verification. Preserve
# every quarantined old container until the owner explicitly verifies those
# external systems and removes the named rollback material.
[ -z "$beszel_rollback" ] || log "Preserved rollback container pending Beszel Hub owner verification: $beszel_rollback"
[ -z "$cloudflared_rollback" ] || log "Preserved rollback container pending external route owner verification: $cloudflared_rollback"
committed=true
trap - EXIT HUP INT TERM
rm -f "$env_backup" "$compose_backup"
