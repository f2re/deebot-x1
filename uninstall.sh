#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ ${EUID} -eq 0 ]] || { echo "sudo required" >&2; exit 1; }
[[ -f "$INSTALL_DIR/.install.env" ]] && . "$INSTALL_DIR/.install.env"

echo "Перед остановкой будет создан backup Bumper/PWA."
[[ -x "$INSTALL_DIR/backup.sh" ]] && "$INSTALL_DIR/backup.sh" || true
[[ -d "$INSTALL_DIR/vendor/bumper" ]] && (cd "$INSTALL_DIR/vendor/bumper" && docker compose down) || true
[[ -f "$INSTALL_DIR/docker-compose.dashboard.yml" ]] && (cd "$INSTALL_DIR" && docker compose -f docker-compose.dashboard.yml down) || true
rm -f /etc/dnsmasq.d/02-deebot-bumper.conf
systemctl restart dnsmasq 2>/dev/null || true

echo "Bumper/PWA остановлены, DNS override удалён."
echo "Home Assistant не останавливался и не изменялся."
echo "Данные оставлены в $INSTALL_DIR для безопасного восстановления."
