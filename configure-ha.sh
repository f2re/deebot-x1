#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ ${EUID} -eq 0 ]] || { echo "Запустите через sudo" >&2; exit 1; }
[[ -f "$INSTALL_DIR/.install.env" ]] || { echo "Сначала install.sh" >&2; exit 1; }
. "$INSTALL_DIR/.install.env"

HA_URL_NEW="${1:-${HA_URL:-}}"
if [[ -z "$HA_URL_NEW" ]]; then
  read -r -p "URL существующего Home Assistant: " HA_URL_NEW
fi
HA_URL_NEW="$(python3 - "$HA_URL_NEW" <<'PY'
import sys
from urllib.parse import urlparse
u=sys.argv[1].strip().rstrip('/')
p=urlparse(u)
if p.scheme not in ('http','https') or not p.hostname or p.username or p.password or any(c.isspace() for c in u):
    raise SystemExit('Некорректный URL')
print(u)
PY
)"

code="$(curl -k -sS --max-time 8 -o /dev/null -w '%{http_code}' "$HA_URL_NEW/api/" 2>/dev/null || true)"
case "$code" in
  200|401) echo "Home Assistant доступен: HTTP $code" ;;
  *) echo "Предупреждение: $HA_URL_NEW сейчас не отвечает ожидаемо (HTTP ${code:-нет ответа})." >&2 ;;
esac

python3 - "$INSTALL_DIR/.install.env" "$HA_URL_NEW" <<'PY'
from pathlib import Path
import shlex, sys
p=Path(sys.argv[1]); url=sys.argv[2]
lines=p.read_text().splitlines()
out=[]; seen=set()
for line in lines:
    key=line.split('=',1)[0] if '=' in line else ''
    if key=='HA_MODE': out.append('HA_MODE='+shlex.quote('external')); seen.add(key)
    elif key=='HA_URL': out.append('HA_URL='+shlex.quote(url)); seen.add(key)
    else: out.append(line)
if 'HA_MODE' not in seen: out.append('HA_MODE='+shlex.quote('external'))
if 'HA_URL' not in seen: out.append('HA_URL='+shlex.quote(url))
p.write_text('\n'.join(out)+'\n')
PY
chmod 600 "$INSTALL_DIR/.install.env"

echo
echo "Сохранено. Пакет не менял конфигурацию HA."
echo "В HA: Настройки -> Устройства и службы -> Ecovacs -> Self-hosted"
echo "REST: http://$SERVER_IP:8007"
echo "MQTT: mqtts://$SERVER_IP:8883"
echo "Verify MQTT SSL certificate: OFF"
