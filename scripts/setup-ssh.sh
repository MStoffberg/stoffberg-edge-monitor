#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"
load_env
require_root

log "Configuring SSH user: $SSH_USER"
if ! id "$SSH_USER" >/dev/null 2>&1; then
  adduser -D -s /bin/ash "$SSH_USER"
  echo "Created user $SSH_USER. Set its console password with: passwd $SSH_USER"
fi
addgroup "$SSH_USER" wheel >/dev/null 2>&1 || true

cat > /etc/doas.d/wheel.conf <<'EOF'
permit persist :wheel
EOF
chmod 600 /etc/doas.d/wheel.conf

mkdir -p "/home/$SSH_USER/.ssh"
chown "$SSH_USER:$SSH_USER" "/home/$SSH_USER/.ssh"
chmod 700 "/home/$SSH_USER/.ssh"
if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
  printf '%s\n' "$SSH_AUTHORIZED_KEYS" > "/home/$SSH_USER/.ssh/authorized_keys"
  chown "$SSH_USER:$SSH_USER" "/home/$SSH_USER/.ssh/authorized_keys"
  chmod 600 "/home/$SSH_USER/.ssh/authorized_keys"
fi

SSHD=/etc/ssh/sshd_config
cp "$SSHD" "$SSHD.bak.$(date +%Y%m%d%H%M%S)"
set_sshd() {
  key="$1"; value="$2"
  if grep -qE "^[# ]*$key[[:space:]]+" "$SSHD"; then
    sed -i "s|^[# ]*$key[[:space:]].*|$key $value|" "$SSHD"
  else
    printf '%s %s\n' "$key" "$value" >> "$SSHD"
  fi
}
set_sshd PermitRootLogin no
set_sshd PubkeyAuthentication yes
set_sshd X11Forwarding no
set_sshd AllowTcpForwarding no
set_sshd ClientAliveInterval 300
set_sshd ClientAliveCountMax 2

if [ -n "$SSH_AUTHORIZED_KEYS" ] && [ "$DISABLE_PASSWORD_SSH_IF_KEY_PRESENT" = "true" ]; then
  set_sshd PasswordAuthentication no
  set_sshd KbdInteractiveAuthentication no
else
  echo "No SSH_AUTHORIZED_KEYS provided; leaving password SSH enabled to avoid lockout."
  set_sshd PasswordAuthentication yes
fi

sshd -t
rc-service sshd restart || rc-service sshd start
