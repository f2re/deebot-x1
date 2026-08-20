#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ -f "$INSTALL_DIR/.install.env" ]] || { echo "Сначала install.sh" >&2; exit 1; }
# shellcheck source=/dev/null
. "$INSTALL_DIR/.install.env"
HA_URL_CHECK="${HA_URL:-}"
[[ -n "$HA_URL_CHECK" ]] || { echo "HA URL не задан. Выполните: sudo $INSTALL_DIR/configure-ha.sh http://HA:8123" >&2; exit 2; }

TOKEN="${HA_TOKEN:-}"
VERIFY=1
if [[ -f "$INSTALL_DIR/.dashboard.env" ]]; then
  # Читаем только локально; значение токена не печатается.
  set -a
  # shellcheck source=/dev/null
  . "$INSTALL_DIR/.dashboard.env"
  set +a
  TOKEN="${TOKEN:-${HA_TOKEN:-}}"
  VERIFY="${HA_VERIFY_TLS:-1}"
fi
curl_args=(-sS --max-time 8)
[[ "$VERIFY" == 0 ]] && curl_args+=(-k)

code="$(curl "${curl_args[@]}" -o /dev/null -w '%{http_code}' "${HA_URL_CHECK%/}/api/" 2>/dev/null || true)"
echo "Home Assistant: $HA_URL_CHECK -> HTTP ${code:-нет ответа}"
if [[ "$code" != 200 && "$code" != 401 ]]; then
  echo "HA недоступен с сервера Bumper/PWA." >&2
  exit 3
fi

if [[ -z "$TOKEN" ]]; then
  echo "Токен не настроен: проверена только сетевая доступность."
  echo "Для полной проверки задайте HA_TOKEN временно или настройте PWA через configure-dashboard.sh."
  exit 0
fi

states="$(curl "${curl_args[@]}" -fsS -H "Authorization: Bearer $TOKEN" "${HA_URL_CHECK%/}/api/states")"
echo
echo "Похожие сущности DEEBOT/Ecovacs:"
printf '%s' "$states" | jq -r '.[] | select((.entity_id|startswith("vacuum.")) or (.entity_id|startswith("image."))) | select(((.entity_id + " " + (.attributes.friendly_name // "")) | ascii_downcase) | test("deebot|ecovacs|x1|map|карт")) | "  \(.entity_id) = \(.state) [\(.attributes.friendly_name // "")]"' | head -40
