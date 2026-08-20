#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ -f "$INSTALL_DIR/.install.env" ]] || { echo "Сначала install.sh" >&2; exit 1; }
. "$INSTALL_DIR/.install.env"
TARGET=""
COPY_MODE=0
while (($#)); do
  case "$1" in
    --target) TARGET="${2:-}"; [[ -n "$TARGET" ]] || { echo "--target требует путь" >&2; exit 2; }; COPY_MODE=1; shift 2 ;;
    -h|--help) echo "Использование: sudo $0 [--target /путь/к/HA-config]"; exit 0 ;;
    *) echo "Неизвестный параметр: $1" >&2; exit 2 ;;
  esac
done
STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -n "$TARGET" ]]; then
  OUT="${TARGET%/}/deebot-x1-local"
else
  OUT="$INSTALL_DIR/ha-export/deebot-x1-local-$STAMP"
fi
mkdir -p "$OUT"

cat > "$OUT/README.md" <<'EOFMD'
# DEEBOT X1 Local — подключение к существующему Home Assistant

Этот каталог **не содержит `.storage` и не изменяет `configuration.yaml` автоматически**.
Интеграция Ecovacs настраивается штатным config flow Home Assistant.

## Bumper

- REST: `http://__SERVER_IP__:8007`
- MQTT: `mqtts://__SERVER_IP__:8883`
- Verify MQTT SSL certificate: **OFF**

## Подключение

1. Home Assistant → **Настройки → Устройства и службы → Добавить интеграцию → Ecovacs**.
2. Выберите self-hosted.
3. Укажите REST/MQTT выше.
4. Если Bumper authentication отключён: в полях username/password допустимы произвольный корректный email и строка-пароль.
5. После появления `vacuum.*` откройте сущность робота → настройки → **Map vacuum segments to areas** и сопоставьте комнаты X1 с Areas Home Assistant.
6. В актуальном Home Assistant уборка комнат доступна через встроенный интерфейс **Clean by area**; отдельная карта не обязательна.

## Lovelace

`lovelace-deebot-x1.yaml` — безопасная заготовка на штатных карточках HA.
Замените `vacuum.REPLACE_WITH_X1` на вашу vacuum entity. Карта добавляется отдельно через entity `image.*`, если её отдаёт интеграция.

## Почему интеграция не копируется файлами

Ecovacs — UI/config-flow интеграция. Прямая запись в `/config/.storage/core.config_entries` не используется: это внутреннее хранилище HA, и его ручная модификация опасна для существующей инсталляции.
EOFMD
sed -i "s/__SERVER_IP__/$SERVER_IP/g" "$OUT/README.md"

cat > "$OUT/connection.txt" <<EOFCONN
DEEBOT X1 / Bumper
REST_URL=http://$SERVER_IP:8007
MQTT_URL=mqtts://$SERVER_IP:8883
VERIFY_MQTT_SSL=false
HOME_ASSISTANT_URL=${HA_URL:-not-set}
EOFCONN

cat > "$OUT/lovelace-deebot-x1.yaml" <<'EOFYAML'
title: DEEBOT X1
views:
  - title: DEEBOT X1
    path: deebot-x1
    icon: mdi:robot-vacuum
    type: sections
    sections:
      - type: grid
        cards:
          - type: tile
            entity: vacuum.REPLACE_WITH_X1
            name: DEEBOT X1
            features_position: bottom
            features:
              - type: vacuum-commands
                commands:
                  - start_pause
                  - stop
                  - locate
                  - return_home
          - type: entity
            entity: vacuum.REPLACE_WITH_X1
            name: Заряд
            attribute: battery_level
            unit: "%"
# Если Ecovacs создал image-сущность карты, можно добавить:
#          - type: picture-entity
#            entity: image.REPLACE_WITH_X1_MAP
#            show_name: false
#            show_state: false
EOFYAML

cat > "$OUT/DO-NOT-COPY-STORAGE.txt" <<'EOFWARN'
Не копируйте и не редактируйте вручную файлы Home Assistant:
  .storage/core.config_entries
  .storage/core.device_registry
  .storage/core.entity_registry
для добавления Ecovacs. Используйте UI/config flow.
EOFWARN

printf '%s\n' "$OUT"
if ((COPY_MODE)); then
  echo "Bundle подготовлен внутри указанного каталога. Существующие файлы HA вне '$OUT' не изменялись."
fi
