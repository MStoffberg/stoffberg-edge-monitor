#!/bin/sh
set -eu

confirm_update() {
  prompt=$1
  if [ "${ASSUME_YES:-false}" = "true" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    printf '[edge-monitor] Non-interactive session: skipping %s\n' "$prompt"
    return 1
  fi
  printf '%s [y/N] ' "$prompt"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

latest_github_tag() {
  repo=$1
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
    sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n 1
}

printf '[edge-monitor] Checking Alpine package updates\n'
apk update
package_updates=$(apk version -l '<' 2>/dev/null || true)
if [ -n "$package_updates" ]; then
  printf '%s\n' "$package_updates"
  if confirm_update "Apply available Alpine package updates?"; then
    apk upgrade --available
  fi
else
  printf '[edge-monitor] Alpine packages are current\n'
fi

if [ -x /opt/AdGuardHome/AdGuardHome ]; then
  current=$(/opt/AdGuardHome/AdGuardHome --version 2>/dev/null | sed -n 's/.*version \(v[^ ,]*\).*/\1/p')
  latest=$(latest_github_tag AdguardTeam/AdGuardHome || true)
  if [ -n "$latest" ] && [ "$current" != "$latest" ]; then
    if confirm_update "Update AdGuard Home from $current to $latest?"; then
      /opt/AdGuardHome/AdGuardHome --update
    fi
  else
    printf '[edge-monitor] AdGuard Home is current (%s)\n' "${current:-unknown}"
  fi
fi

if command -v adguardhome-sync >/dev/null 2>&1; then
  current=$(adguardhome-sync --version 2>/dev/null | sed -n 's/.*version[[:space:]]*//p' | sed 's/^/v/')
  latest=$(latest_github_tag bakito/adguardhome-sync || true)
  if [ -n "$latest" ] && [ "$current" != "$latest" ]; then
    if confirm_update "Update adguardhome-sync from $current to $latest?"; then
      version_no_v=${latest#v}
      work=$(mktemp -d /tmp/adguardhome-sync-update.XXXXXX)
      trap 'rm -rf "$work"' EXIT
      curl -fsSL "https://github.com/bakito/adguardhome-sync/releases/download/$latest/adguardhome-sync_${version_no_v}_linux_amd64.tar.gz" -o "$work/archive.tar.gz"
      tar -xzf "$work/archive.tar.gz" -C "$work"
      rc-service adguardhome-sync stop || true
      install -m 755 "$work/adguardhome-sync" /usr/local/bin/adguardhome-sync
      rc-service adguardhome-sync start || true
      rm -rf "$work"
      trap - EXIT
    fi
  else
    printf '[edge-monitor] adguardhome-sync is current (%s)\n' "${current:-unknown}"
  fi
fi

if [ -f /opt/uptime-kuma/docker-compose.yml ]; then
  cd /opt/uptime-kuma
  for service in uptime-kuma beszel-agent; do
    docker compose config --services 2>/dev/null | grep -qx "$service" || continue
    container_id=$(docker compose ps -q "$service" 2>/dev/null || true)
    [ -n "$container_id" ] || continue
    running_image=$(docker inspect -f '{{.Image}}' "$container_id" 2>/dev/null || true)
    service_image=$(docker inspect -f '{{.Config.Image}}' "$container_id" 2>/dev/null || true)
    docker compose pull "$service"
    latest_image=$(docker image inspect -f '{{.Id}}' "$service_image" 2>/dev/null || true)
    if [ -n "$latest_image" ] && [ "$running_image" != "$latest_image" ]; then
      if confirm_update "Update $service to the downloaded newer image?"; then
        docker compose up -d --no-deps "$service"
      fi
    else
      printf '[edge-monitor] %s is current\n' "$service"
    fi
  done
fi

printf '[edge-monitor] Safe disk cleanup (caches, temporary files, and dangling images only)\n'
apk cache clean
rm -rf /tmp/adguardhome-install /tmp/adguardhome-sync-install /tmp/adguardhome-sync-update.*
docker image prune -f
printf '[edge-monitor] Done. Run edge-status to verify.\n'
