#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

if [ -x /opt/AdGuardHome/AdGuardHome ]; then
  log "AdGuard Home already installed"
  /opt/AdGuardHome/AdGuardHome --version || true
  exit 0
fi

log "Installing AdGuard Home $ADGUARDHOME_VERSION"
url="https://github.com/AdguardTeam/AdGuardHome/releases/download/${ADGUARDHOME_VERSION}/AdGuardHome_linux_amd64.tar.gz"
work=/tmp/adguardhome-install
rm -rf "$work"
mkdir -p "$work"
curl -fsSL "$url" -o "$work/AdGuardHome_linux_amd64.tar.gz"
tar -xzf "$work/AdGuardHome_linux_amd64.tar.gz" -C "$work"
rm -rf /opt/AdGuardHome
mkdir -p /opt
mv "$work/AdGuardHome" /opt/AdGuardHome
chmod 755 /opt/AdGuardHome/AdGuardHome
/opt/AdGuardHome/AdGuardHome -s install
/opt/AdGuardHome/AdGuardHome -s start || true
/opt/AdGuardHome/AdGuardHome --version || true
