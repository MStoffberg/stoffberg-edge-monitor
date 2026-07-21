#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
require_root
umask 077

TOKEN_SOURCE=${1:-/root/cloudflared-token.env}
ENV_FILE=/etc/edge-monitor.env
TOKEN_DEST=/etc/cloudflared/token.env
[ ! -L "$TOKEN_SOURCE" ] && [ -f "$TOKEN_SOURCE" ] || { echo "ERROR: tunnel token must be a regular non-symlink file" >&2; exit 1; }

# The source must be immutable to non-root users. Open it once and copy from the
# descriptor, never from the pathname after validation.
exec 3<"$TOKEN_SOURCE"
source_meta=$(stat -Lc '%u:%a:%F' "/proc/$$/fd/3")
[ "$source_meta" = '0:600:regular file' ] || { echo "ERROR: tunnel token must be root-owned mode 0600 regular file" >&2; exit 1; }
token_dir=$(dirname -- "$TOKEN_SOURCE")
[ "$(stat -Lc '%u:%a:%F' "$token_dir")" = '0:700:directory' ] || { echo "ERROR: tunnel token directory must be root-owned mode 0700" >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE does not exist; run the normal bootstrap first" >&2; exit 1; }

mkdir -p /etc/cloudflared
chmod 700 /etc/cloudflared
env_backup=$(mktemp "$ENV_FILE.cutover-backup.XXXXXX")
token_backup=$(mktemp /etc/cloudflared/.token-backup.XXXXXX)
token_candidate=$(mktemp /etc/cloudflared/.token-candidate.XXXXXX)
cp -p "$ENV_FILE" "$env_backup"
had_token=false
[ ! -f "$TOKEN_DEST" ] || { cp -p "$TOKEN_DEST" "$token_backup"; had_token=true; }
committed=false
mutated=false
rollback() {
  rc=$1
  trap - EXIT HUP INT TERM
  if [ "$committed" != true ] && [ "$mutated" = true ]; then
    install -m 600 "$env_backup" "$ENV_FILE"
    if [ "$had_token" = true ]; then install -m 600 "$token_backup" "$TOKEN_DEST"; else rm -f "$TOKEN_DEST"; fi
    # The installer is itself transactional; reconciling the restored owner
    # config returns containers to the pre-cutover desired state.
    sh "$SCRIPT_DIR/install-edge-services.sh" >/dev/null 2>&1 || true
  fi
  rm -f "$env_backup" "$token_backup" "$token_candidate"
  exit "$rc"
}
trap 'rollback $?' EXIT
trap 'rollback 129' HUP
trap 'rollback 130' INT
trap 'rollback 143' TERM
cat <&3 >"$token_candidate"
exec 3<&-
chmod 600 "$token_candidate"
grep -q '^TUNNEL_TOKEN=.' "$token_candidate" || { echo "ERROR: staged credential has no TUNNEL_TOKEN entry" >&2; exit 1; }

set_key() {
  key=$1; value=$2
  tmp=$(mktemp "$ENV_FILE.tmp.XXXXXX")
  found=false
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$key="*) printf '%s=%s\n' "$key" "$value" >>"$tmp"; found=true;; *) printf '%s\n' "$line" >>"$tmp";; esac
  done <"$ENV_FILE"
  [ "$found" = true ] || printf '%s=%s\n' "$key" "$value" >>"$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$ENV_FILE"
}

mv "$token_candidate" "$TOKEN_DEST"
mutated=true
set_key INSTALL_CLOUDFLARED true
set_key CLOUDFLARED_TOKEN_FILE "$TOKEN_DEST"
set_key INSTALL_ADGUARD_SYNC true
set_key ENABLE_SCHEDULED_CLEANUP true

# This is the only delegated mutator. It validates candidates before atomic
# install and owns complete Compose/container rollback. The firewall remains
# intentionally outside this transaction and untouched.
sh "$SCRIPT_DIR/install-edge-services.sh"
[ "$TOKEN_SOURCE" = "$TOKEN_DEST" ] || rm -f "$TOKEN_SOURCE"
committed=true
trap - EXIT HUP INT TERM
rm -f "$env_backup" "$token_backup"
printf '%s\n' '[edge-monitor] Cloudflared installation complete; firewall retained unchanged.'
printf '%s\n' '[edge-monitor] Verify public routes and Beszel Hub registration before removing rollback containers.'
