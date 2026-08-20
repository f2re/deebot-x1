#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ ${EUID} -eq 0 ]] || { echo "Запустите через sudo" >&2; exit 1; }
[[ -f "$INSTALL_DIR/.install.env" ]] || { echo "Сначала install.sh" >&2; exit 1; }
. "$INSTALL_DIR/.install.env"

HA_URL_NEW="${HA_URL:-}"
HA_VERIFY_TLS="1"
DASHBOARD_HOST="0.0.0.0"
DASHBOARD_PORT="8090"
TOKEN_ARG=""
while (($#)); do
  case "$1" in
    --ha-url) HA_URL_NEW="${2:-}"; shift 2 ;;
    --insecure-ha) HA_VERIFY_TLS="0"; shift ;;
    --listen) DASHBOARD_HOST="${2:-}"; shift 2 ;;
    --port) DASHBOARD_PORT="${2:-}"; shift 2 ;;
    --token) TOKEN_ARG="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'HELP'
Использование:
  sudo configure-dashboard.sh [--ha-url URL] [--insecure-ha] [--listen IP] [--port PORT]

PWA опциональна. Home Assistant не изменяется. Токен хранится только на сервере PWA.
HELP
      exit 0 ;;
    *) echo "Неизвестный параметр: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$HA_URL_NEW" ]]; then
  read -r -p "URL существующего Home Assistant: " HA_URL_NEW
fi
HA_URL_NEW="${HA_URL_NEW%/}"
[[ "$HA_URL_NEW" =~ ^https?:// ]] || { echo "HA URL должен начинаться с http:// или https://" >&2; exit 2; }
[[ "$DASHBOARD_PORT" =~ ^[0-9]+$ ]] && ((DASHBOARD_PORT>=1 && DASHBOARD_PORT<=65535)) || { echo "Некорректный порт" >&2; exit 2; }

if [[ -n "$TOKEN_ARG" ]]; then
  HA_TOKEN="$TOKEN_ARG"
elif [[ -n "${HA_TOKEN:-}" ]]; then
  HA_TOKEN="$HA_TOKEN"
else
  read -r -s -p "Home Assistant Long-Lived Access Token: " HA_TOKEN
  echo
fi
[[ -n "$HA_TOKEN" ]] || { echo "Токен пуст" >&2; exit 1; }

curl_args=(-fsS --max-time 8 -H "Authorization: Bearer $HA_TOKEN")
[[ "$HA_VERIFY_TLS" == 0 ]] && curl_args+=(-k)
if ! curl "${curl_args[@]}" "$HA_URL_NEW/api/" | grep -q 'API running'; then
  echo "Home Assistant отклонил токен или недоступен: $HA_URL_NEW" >&2
  exit 2
fi

read -r -p "vacuum entity_id [автоопределение]: " VACUUM_ENTITY || true
read -r -p "map image entity_id [автоопределение]: " MAP_ENTITY || true

cat > "$INSTALL_DIR/.dashboard.env" <<EOFENV
HA_URL=$HA_URL_NEW
HA_TOKEN=$HA_TOKEN
HA_VERIFY_TLS=$HA_VERIFY_TLS
VACUUM_ENTITY=${VACUUM_ENTITY:-}
MAP_ENTITY=${MAP_ENTITY:-}
DASHBOARD_HOST=$DASHBOARD_HOST
DASHBOARD_PORT=$DASHBOARD_PORT
ARCHIVE_DIR=/data/maps
ARCHIVE_INTERVAL=180
ARCHIVE_KEEP=80
EOFENV
chmod 600 "$INSTALL_DIR/.dashboard.env"
mkdir -p "$INSTALL_DIR/data/maps"
chown -R 10001:10001 "$INSTALL_DIR/data/maps"

cd "$INSTALL_DIR"
docker compose -f docker-compose.dashboard.yml up -d --build

python3 - "$INSTALL_DIR/.install.env" "$HA_URL_NEW" <<'PY'
from pathlib import Path
import shlex,sys
p=Path(sys.argv[1]); url=sys.argv[2]
lines=p.read_text().splitlines(); out=[]; found=set()
for line in lines:
    k=line.split('=',1)[0] if '=' in line else ''
    if k=='HA_MODE': out.append('HA_MODE='+shlex.quote('external')); found.add(k)
    elif k=='HA_URL': out.append('HA_URL='+shlex.quote(url)); found.add(k)
    elif k=='DASHBOARD_ENABLED': out.append('DASHBOARD_ENABLED='+shlex.quote('yes')); found.add(k)
    else: out.append(line)
for k,v in [('HA_MODE','external'),('HA_URL',url),('DASHBOARD_ENABLED','yes')]:
    if k not in found: out.append(k+'='+shlex.quote(v))
p.write_text('\n'.join(out)+'\n')
PY
chmod 600 "$INSTALL_DIR/.install.env"

echo "Локальная панель: http://$SERVER_IP:$DASHBOARD_PORT/"
echo "HA остаётся внешней системой: $HA_URL_NEW"
echo "Токен находится только в $INSTALL_DIR/.dashboard.env (0600) и браузеру не передаётся."
echo "Для комнат предпочтительно сначала сопоставить сегменты Ecovacs с Areas в Home Assistant."
echo "Не пробрасывайте PWA напрямую в Интернет; используйте LAN/VPN или свой TLS reverse proxy."
