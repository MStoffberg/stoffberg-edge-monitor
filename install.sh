#!/bin/sh
set -eu

REPO_URL="${REPO_URL:-https://github.com/MStoffberg/stoffberg-edge-monitor.git}"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/root/stoffberg-edge-monitor}"
ENV_FILE="${ENV_FILE:-/etc/edge-monitor.env}"
RUN_BOOTSTRAP="${RUN_BOOTSTRAP:-true}"

log() { printf '\n[edge-installer] %s\n' "$*"; }
fail() { printf '\n[edge-installer] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || fail "run as root"
[ -f /etc/alpine-release ] || fail "this installer targets Alpine Linux"

log "Installing prerequisites"
apk update
apk add --no-cache ca-certificates curl git

if [ -d "$INSTALL_DIR/.git" ]; then
  log "Updating existing repo at $INSTALL_DIR"
  git -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$INSTALL_DIR" checkout "$BRANCH"
  git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
else
  log "Cloning $REPO_URL#$BRANCH to $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

if [ ! -f "$ENV_FILE" ]; then
  log "Creating $ENV_FILE from example"
  cp "$INSTALL_DIR/config/edge-monitor.env.example" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
else
  log "Keeping existing $ENV_FILE"
fi

log "Applying optional environment overrides"
# These let a one-liner customize common values without editing the repo.
for key in HOSTNAME TIMEZONE LAN_CIDRS SSH_USER SSH_AUTHORIZED_KEYS SET_SSH_PASSWORD ENABLE_FIREWALL ADGUARD_UI_PORT UPTIME_KUMA_PORT; do
  eval "value=\${$key:-}"
  [ -n "$value" ] || continue
  if grep -q "^$key=" "$ENV_FILE"; then
    escaped=$(printf '%s' "$value" | sed 's/[&|]/\\&/g')
    sed -i "s|^$key=.*|$key=\"$escaped\"|" "$ENV_FILE"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$ENV_FILE"
  fi
done
chmod 600 "$ENV_FILE"

if [ "$RUN_BOOTSTRAP" = "true" ]; then
  log "Running bootstrap"
  sh "$INSTALL_DIR/scripts/bootstrap-alpine.sh"
else
  log "RUN_BOOTSTRAP=false; not running bootstrap"
  echo "Repo ready at: $INSTALL_DIR"
  echo "Config file:   $ENV_FILE"
  echo "Run manually:  sh $INSTALL_DIR/scripts/bootstrap-alpine.sh"
fi
