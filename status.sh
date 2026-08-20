#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
# shellcheck source=/dev/null
[[ -f "$INSTALL_DIR/.install.env" ]] && . "$INSTALL_DIR/.install.env"
printf 'Bumper:         http://%s:8007/\n' "${SERVER_IP:-127.0.0.1}"
printf 'Home Assistant: %s\n' "${HA_URL:-не задан; внешняя система}"
if [[ -f "$INSTALL_DIR/.dashboard.env" ]]; then
  # shellcheck source=/dev/null
  . "$INSTALL_DIR/.dashboard.env"
  printf 'Dashboard:      http://%s:%s/\n' "${SERVER_IP:-127.0.0.1}" "${DASHBOARD_PORT:-8090}"
else
  printf 'Dashboard:      выключен\n'
fi
printf '\n'
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
