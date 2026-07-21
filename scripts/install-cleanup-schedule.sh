#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

mkdir -p /etc/periodic/weekly
install -m 644 "$SCRIPT_DIR/lib.sh" /usr/local/sbin/lib.sh
install -m 755 "$SCRIPT_DIR/edge-cleanup.sh" /usr/local/sbin/edge-cleanup
if [ "$ENABLE_SCHEDULED_CLEANUP" = "true" ]; then
  cat > /etc/periodic/weekly/edge-cleanup <<'EOF'
#!/bin/sh
exec /usr/local/sbin/edge-cleanup --apply
EOF
  chmod 755 /etc/periodic/weekly/edge-cleanup
  log "Installed conservative weekly cleanup"
else
  rm -f /etc/periodic/weekly/edge-cleanup
  log "Scheduled cleanup disabled; use edge-cleanup for a dry run"
fi
