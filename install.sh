#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
BUMPER_REPO="${BUMPER_REPO:-https://github.com/MVladislav/bumper.git}"
BUMPER_REF="${BUMPER_REF:-v0.4.1}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVER_IP_ARG=""
HA_MODE_ARG=""
HA_URL_ARG=""
HA_CONFIG_DIR_ARG=""
DASHBOARD_ARG=""
BUMPER_REF_ARG=""
NONINTERACTIVE="${NONINTERACTIVE:-}"

log(){ printf '\033[1;34m[DEEBOT-X1]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
usage(){ cat <<'USAGE'
Использование:
  sudo ./install.sh [параметры]

Home Assistant НЕ устанавливается этим пакетом.

Параметры:
  --server-ip IP              LAN IPv4 сервера Bumper
  --ha-mode MODE              external | export | none
  --ha-url URL                адрес существующего Home Assistant
  --ha-config-dir PATH        каталог, куда подготовить HA bundle в режиме export
  --dashboard yes|no          сразу запускать отдельную PWA-панель (по умолчанию no)
  --bumper-ref REF            стабильный tag/branch Bumper (по умолчанию v0.4.1)
  --non-interactive           без вопросов; недостающие значения берутся из defaults/env
  -h, --help                  справка

Примеры:
  sudo ./install.sh --ha-url http://192.168.1.10:8123
  sudo ./install.sh --ha-mode export --ha-config-dir /mnt/homeassistant
  sudo ./install.sh --ha-mode none
USAGE
}

while (($#)); do
  case "$1" in
    --server-ip) [[ $# -ge 2 ]] || die "Для --server-ip нужен IP"; SERVER_IP_ARG="$2"; shift 2 ;;
    --ha-mode) [[ $# -ge 2 ]] || die "Для --ha-mode нужен external|export|none"; HA_MODE_ARG="$2"; shift 2 ;;
    --ha-url) [[ $# -ge 2 ]] || die "Для --ha-url нужен URL"; HA_URL_ARG="$2"; shift 2 ;;
    --ha-config-dir) [[ $# -ge 2 ]] || die "Для --ha-config-dir нужен путь"; HA_CONFIG_DIR_ARG="$2"; shift 2 ;;
    --dashboard) [[ $# -ge 2 ]] || die "Для --dashboard нужен yes|no"; DASHBOARD_ARG="$2"; shift 2 ;;
    --bumper-ref) [[ $# -ge 2 ]] || die "Для --bumper-ref нужен tag/branch"; BUMPER_REF_ARG="$2"; shift 2 ;;
    --non-interactive) NONINTERACTIVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Неизвестный параметр: $1" ;;
  esac
done

[[ ${EUID} -eq 0 ]] || die "Запустите: sudo ./install.sh"
[[ -r /etc/os-release ]] || die "Не удалось определить ОС"
. /etc/os-release
case "${ID:-}" in
  debian|ubuntu|raspbian) ;;
  *) warn "ОС ${PRETTY_NAME:-$ID} не тестировалась. Скрипт рассчитан на Debian/Ubuntu/Raspberry Pi OS." ;;
esac

log "Устанавливаю базовые системные зависимости"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git jq openssl rsync tar gzip dnsutils iproute2 lsof python3

ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
  amd64|arm64|aarch64) ;;
  *) warn "Архитектура $ARCH не является основной целью. Для Raspberry Pi рекомендуется 64-bit OS." ;;
esac

DEFAULT_IF="$(ip route show default 2>/dev/null | awk 'NR==1{print $5}')"
DEFAULT_IP="$(ip -4 addr show dev "${DEFAULT_IF:-}" 2>/dev/null | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')"
[[ -n "$DEFAULT_IP" ]] || DEFAULT_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$DEFAULT_IP" ]] || die "Не удалось определить LAN IPv4. Задайте --server-ip x.x.x.x"

SERVER_IP="${SERVER_IP_ARG:-${SERVER_IP:-$DEFAULT_IP}}"
if [[ -t 0 && -z "$NONINTERACTIVE" && -z "$SERVER_IP_ARG" ]]; then
  read -r -p "Локальный IP сервера Bumper [$SERVER_IP]: " ans || true
  SERVER_IP="${ans:-$SERVER_IP}"
fi
python3 - "$SERVER_IP" <<'PYIP' || die "Некорректный IPv4: $SERVER_IP"
import ipaddress, sys
ipaddress.IPv4Address(sys.argv[1])
PYIP

validate_url(){
  python3 - "$1" <<'PYURL'
import sys
from urllib.parse import urlparse
u=sys.argv[1].strip().rstrip('/')
p=urlparse(u)
if p.scheme not in ('http','https') or not p.hostname or p.username or p.password:
    raise SystemExit(1)
if any(ord(c)<32 or c.isspace() for c in u):
    raise SystemExit(1)
print(u)
PYURL
}

HA_MODE="${HA_MODE_ARG:-${HA_MODE:-}}"
HA_URL="${HA_URL_ARG:-${HA_URL:-}}"
HA_CONFIG_DIR="${HA_CONFIG_DIR_ARG:-${HA_CONFIG_DIR:-}}"
DASHBOARD_ENABLED="${DASHBOARD_ARG:-${DASHBOARD_ENABLED:-no}}"
BUMPER_REF="${BUMPER_REF_ARG:-$BUMPER_REF}"
[[ -n "$BUMPER_REF" && ! "$BUMPER_REF" =~ [[:space:]] ]] || die "Некорректный --bumper-ref"

if [[ -z "$HA_MODE" ]]; then
  if [[ -n "$HA_URL" ]]; then
    HA_MODE="external"
  elif [[ -n "$NONINTERACTIVE" ]]; then
    HA_MODE="none"
  else
    echo
    echo "Home Assistant уже установлен? Выберите способ интеграции:"
    echo "  1) Подключить существующий HA по URL (рекомендуется)"
    echo "  2) Подготовить файлы/инструкцию для копирования в HA"
    echo "  3) Пока не настраивать HA"
    read -r -p "Выбор [1]: " choice || true
    case "${choice:-1}" in
      1) HA_MODE="external" ;;
      2) HA_MODE="export" ;;
      3) HA_MODE="none" ;;
      *) die "Некорректный выбор" ;;
    esac
  fi
fi
case "$HA_MODE" in external|export|none) ;; *) die "--ha-mode: external|export|none" ;; esac

if [[ "$HA_MODE" == "external" ]]; then
  if [[ -z "$HA_URL" && -z "$NONINTERACTIVE" ]]; then
    local_ha=""
    if curl -sS --max-time 2 -o /dev/null "http://127.0.0.1:8123/" 2>/dev/null; then
      local_ha="http://$SERVER_IP:8123"
    fi
    read -r -p "URL существующего Home Assistant${local_ha:+ [$local_ha]}: " ans || true
    HA_URL="${ans:-$local_ha}"
  fi
  [[ -n "$HA_URL" ]] || die "Для external задайте --ha-url, например http://192.168.1.10:8123"
  HA_URL="$(validate_url "$HA_URL")" || die "Некорректный Home Assistant URL"
fi

if [[ "$HA_MODE" == "export" && -z "$HA_CONFIG_DIR" && -z "$NONINTERACTIVE" ]]; then
  read -r -p "Куда подготовить HA bundle [оставить внутри $INSTALL_DIR/ha-export]: " ans || true
  HA_CONFIG_DIR="${ans:-}"
fi

case "${DASHBOARD_ENABLED,,}" in
  y|yes|1|true|д|да) DASHBOARD_ENABLED=yes ;;
  n|no|0|false|н|нет|'') DASHBOARD_ENABLED=no ;;
  *) die "--dashboard: yes|no" ;;
esac
[[ "$DASHBOARD_ENABLED" == no || "$HA_MODE" == external ]] || die "--dashboard yes требует --ha-mode external и --ha-url"

TZ_NAME="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
TZ_NAME="${TZ_NAME:-Europe/Helsinki}"

if ! command -v docker >/dev/null 2>&1; then
  log "Устанавливаю Docker из пакетов ОС"
  apt-get install -y docker.io
fi
systemctl enable --now docker

if ! docker compose version >/dev/null 2>&1; then
  log "Устанавливаю Docker Compose v2"
  apt-get install -y docker-compose-v2 2>/dev/null || apt-get install -y docker-compose-plugin 2>/dev/null || true
fi
if ! docker compose version >/dev/null 2>&1; then
  MACHINE="$(uname -m)"
  case "$MACHINE" in
    x86_64) COMPOSE_ARCH=x86_64 ;;
    aarch64|arm64) COMPOSE_ARCH=aarch64 ;;
    *) die "Docker Compose v2 не найден для архитектуры $MACHINE" ;;
  esac
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -fL --retry 3 --connect-timeout 10 \
    "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${COMPOSE_ARCH}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi
docker compose version >/dev/null 2>&1 || die "Не удалось установить Docker Compose v2"

# Для X1 на хост публикуются только необходимые порты:
# 443 = Ecovacs HTTPS/MQTT через SNI, 8007 = REST, 8883 = MQTTS для HA.
# Порт 80, plain MQTT 1883 и XMPP 5223 остаются внутренними и не занимают хост.
if [[ ! -f "$INSTALL_DIR/.install.env" ]]; then
  conflicts=()
  ports=(443 8007 8883)
  [[ "$DASHBOARD_ENABLED" == yes ]] && ports+=(8090)
  for p in "${ports[@]}"; do
    if ss -H -ltn "sport = :$p" 2>/dev/null | grep -q .; then conflicts+=("$p"); fi
  done
  if ((${#conflicts[@]})); then
    warn "Уже заняты необходимые TCP-порты Bumper/PWA: ${conflicts[*]}"
    warn "Для DEEBOT X1 порт 80 не используется и намеренно не публикуется. Home Assistant :8123 также не затрагивается."
    [[ "${ALLOW_PORT_CONFLICTS:-0}" == 1 ]] || exit 2
  fi
fi

mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/vendor" "$INSTALL_DIR/data/maps" "$INSTALL_DIR/backups" "$INSTALL_DIR/ha-export"
if [[ "$SOURCE_DIR" != "$INSTALL_DIR" ]]; then
  rsync -a --delete \
    --exclude 'vendor/' --exclude 'data/' --exclude 'backups/' --exclude 'ha-export/' --exclude '__pycache__/' \
    "$SOURCE_DIR/" "$INSTALL_DIR/"
fi

if [[ ! -d "$INSTALL_DIR/vendor/bumper/.git" ]]; then
  log "Клонирую Bumper $BUMPER_REF"
  git clone --depth 1 --branch "$BUMPER_REF" "$BUMPER_REPO" "$INSTALL_DIR/vendor/bumper"
else
  current_bumper_commit="$(git -C "$INSTALL_DIR/vendor/bumper" rev-parse --short HEAD 2>/dev/null || true)"
  current_bumper_ref="$(git -C "$INSTALL_DIR/vendor/bumper" describe --tags --exact-match HEAD 2>/dev/null || git -C "$INSTALL_DIR/vendor/bumper" rev-parse HEAD 2>/dev/null || true)"
  log "Использую существующий Bumper @ ${current_bumper_commit:-unknown}"
  warn "Повторный запуск install.sh не обновляет Bumper. Для обновления используйте update.sh."
  BUMPER_REF="${current_bumper_ref:-existing}"
fi

BUMPER="$INSTALL_DIR/vendor/bumper"
"$INSTALL_DIR/scripts/prepare-bumper-compose.sh"
cat > "$BUMPER/.env" <<EOFENV
COMPOSE_FILE=docker-compose.x1.yaml
NETWORK_MODE=bridge
BUMPER_ANNOUNCE_IP=$SERVER_IP
BUMPER_LISTEN=0.0.0.0
BUMPER_DEBUG_LEVEL=INFO
BUMPER_DEBUG_VERBOSE=1
TZ=$TZ_NAME
VERSION_BUMPER=latest
EOFENV

log "Создаю локальный CA и TLS-сертификаты Bumper"
(cd "$BUMPER" && bash scripts/create-cert.sh)
chmod 600 "$BUMPER/certs"/*.key 2>/dev/null || true

# В .install.env используем shell quoting, т.к. файл source-ится служебными скриптами.
{
  printf 'SERVER_IP=%q\n' "$SERVER_IP"
  printf 'TZ=%q\n' "$TZ_NAME"
  printf 'BUMPER_REPO=%q\n' "$BUMPER_REPO"
  printf 'BUMPER_REF=%q\n' "$BUMPER_REF"
  printf 'BUMPER_COMMIT=%q\n' "$(git -C "$BUMPER" rev-parse HEAD)"
  printf 'HA_MODE=%q\n' "$HA_MODE"
  printf 'HA_URL=%q\n' "$HA_URL"
  printf 'HA_CONFIG_DIR=%q\n' "$HA_CONFIG_DIR"
  printf 'DASHBOARD_ENABLED=%q\n' "$DASHBOARD_ENABLED"
  printf 'INSTALLED_AT=%q\n' "$(date -Is)"
} > "$INSTALL_DIR/.install.env"
chmod 600 "$INSTALL_DIR/.install.env"

if docker ps -a --format '{{.Names}}' | grep -qx 'deebot-homeassistant'; then
  warn "Обнаружен контейнер deebot-homeassistant из старой версии пакета."
  warn "Новая версия его НЕ управляет: не останавливает, не обновляет и не удаляет."
fi

log "Проверяю конфигурацию Bumper"
(cd "$BUMPER" && docker compose config >/dev/null)
log "Запускаю Bumper"
(cd "$BUMPER" && docker compose up -d --build)

log "Проверяю Bumper"
for _ in {1..60}; do
  if curl -fsS --max-time 2 "http://127.0.0.1:8007/" >/dev/null 2>&1 || ss -ltnH | grep -q ':8007 '; then
    break
  fi
  sleep 2
done

if [[ "$HA_MODE" == "external" ]]; then
  log "Проверяю доступность существующего Home Assistant: $HA_URL"
  code="$(curl -k -sS --max-time 5 -o /dev/null -w '%{http_code}' "$HA_URL/api/" 2>/dev/null || true)"
  case "$code" in
    200|401) log "Home Assistant доступен (HTTP $code)" ;;
    *) warn "Home Assistant пока не отвечает ожидаемо через $HA_URL (HTTP ${code:-нет ответа}). Bumper продолжает работать независимо." ;;
  esac
fi

if [[ "$HA_MODE" == "export" ]]; then
  args=()
  [[ -n "$HA_CONFIG_DIR" ]] && args+=(--target "$HA_CONFIG_DIR")
  "$INSTALL_DIR/export-ha-config.sh" "${args[@]}"
fi

if [[ "$DASHBOARD_ENABLED" == yes ]]; then
  if [[ -n "$NONINTERACTIVE" && -z "${HA_TOKEN:-}" ]]; then
    die "Для --dashboard yes --non-interactive задайте HA_TOKEN в окружении"
  fi
  "$INSTALL_DIR/configure-dashboard.sh" --ha-url "$HA_URL"
fi

HOST_PORTS="443/tcp, 8007/tcp, 8883/tcp"
[[ "$DASHBOARD_ENABLED" == yes ]] && HOST_PORTS+=", 8090/tcp"

cat <<EOFMSG

Базовая установка завершена.

Bumper:          http://$SERVER_IP:8007/
Home Assistant:  ${HA_URL:-не управляется этим пакетом}
Отдельная PWA:   ${DASHBOARD_ENABLED}
Host-порты:      $HOST_PORTS
Порт 80:         не используется

Пакет НЕ устанавливал и НЕ изменял Home Assistant.

Следующие шаги:
  1. Пока НЕ блокируйте Интернет X1 и НЕ удаляйте текущую карту.
  2. Включите DNS-перехват: sudo $INSTALL_DIR/enable-dns.sh
  3. В DHCP назначьте X1 постоянный IP и локальный DNS.
  4. Перезагрузите X1 и выполните: sudo $INSTALL_DIR/diagnose.sh
  5. В существующем HA добавьте Ecovacs -> Self-hosted:
       REST: http://$SERVER_IP:8007
       MQTT: mqtts://$SERVER_IP:8883
       Verify MQTT SSL certificate: OFF
EOFMSG

if [[ "$HA_MODE" == "external" ]]; then
  cat <<EOFMSG
  6. HA адрес для этой установки: $HA_URL
EOFMSG
fi
cat <<EOFMSG
  7. Опциональная отдельная мобильная панель:
       sudo $INSTALL_DIR/configure-dashboard.sh

Для генерации файлов/инструкции для HA в любой момент:
  sudo $INSTALL_DIR/export-ha-config.sh
EOFMSG
