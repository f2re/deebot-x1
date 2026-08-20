# DEEBOT X1 Local

[![CI](https://github.com/f2re/deebot-x1/actions/workflows/ci.yml/badge.svg)](https://github.com/f2re/deebot-x1/actions/workflows/ci.yml)

Локальный контур для Ecovacs DEEBOT X1/X1 Omni. Bumper заменяет облачные сервисы Ecovacs, а Home Assistant остаётся отдельной существующей системой. Этот пакет **не устанавливает Home Assistant, не перезапускает его, не обновляет и не редактирует `.storage`**.

Проверенная upstream-совместимость Bumper включает **DEEBOT X1 Omni** с MQTT и прошивками `1.15.7` / `2.3.9`. По умолчанию установщик фиксирует стабильный Bumper `v0.4.1`; уже установленная ревизия не меняется повторным запуском `install.sh`.

Документы: [архитектура](docs/ARCHITECTURE.md) · [диагностика](docs/TROUBLESHOOTING.md) · [разработка](CONTRIBUTING.md) · [безопасность](SECURITY.md) · [сторонние компоненты](THIRD_PARTY.md).

## Рекомендуемая архитектура

```text
DEEBOT X1
   │ Wi‑Fi / MQTT/TLS + REST
   ▼
Bumper (Raspberry Pi / Debian / Ubuntu)
   │
   ├── локальный DNS override Ecovacs
   │
   └──────────────► существующий Home Assistant
                         │
                         ├── штатный Vacuum UI / Clean by area
                         └── опционально DEEBOT PWA :8090

Internet для X1 → блокируется только после проверки локального контура
```

Home Assistant может находиться:

- на другом Raspberry Pi;
- на Home Assistant OS;
- в Docker/VM/Proxmox;
- на NAS;
- на том же сервере, что Bumper.

Порт `8123` больше не резервируется и не считается конфликтом.

## 1. Установка с уже существующим Home Assistant

Пример:

```bash
git clone https://github.com/f2re/deebot-x1.git
cd deebot-x1
sudo ./install.sh \
  --server-ip 192.168.1.20 \
  --ha-url http://192.168.1.10:8123
```

Если параметры не заданы, установщик задаст вопросы интерактивно.

Что будет установлено на **сервер Bumper**:

- Docker/Compose, если их нет;
- Bumper;
- сертификаты Bumper;
- служебные скрипты;
- каталог резервных копий и карт.

Что **не** будет установлено/изменено:

- Home Assistant;
- `/config/configuration.yaml` существующего HA;
- `/config/.storage/*`;
- существующие HA add-ons/custom integrations;
- существующая база Recorder.

## 2. Режимы Home Assistant

### A. `external` — рекомендуемый

```bash
sudo ./install.sh --ha-mode external --ha-url https://ha.home.arpa:8123
```

URL сохраняется только как адрес внешнего HA. Для базовой работы Bumper токен HA не нужен.

Изменить URL позже:

```bash
sudo /opt/deebot-x1-local/configure-ha.sh http://192.168.1.10:8123
```

### B. `export` — подготовка файлов для существующего HA

Если файловая система `/config` Home Assistant примонтирована, например в `/mnt/ha-config`:

```bash
sudo ./install.sh \
  --ha-mode export \
  --ha-config-dir /mnt/ha-config
```

Будет создан только:

```text
/mnt/ha-config/deebot-x1-local/
├── README.md
├── connection.txt
├── lovelace-deebot-x1.yaml
└── DO-NOT-COPY-STORAGE.txt
```

Ничего за пределами этого подкаталога не меняется.

Создать bundle позже без прямого копирования:

```bash
sudo /opt/deebot-x1-local/export-ha-config.sh
```

Или непосредственно в примонтированный каталог HA:

```bash
sudo /opt/deebot-x1-local/export-ha-config.sh --target /mnt/ha-config
```

### C. `none`

Если HA пока не нужен:

```bash
sudo ./install.sh --ha-mode none
```

Bumper работает самостоятельно. HA можно подключить позднее через `configure-ha.sh`.

## 3. Почему нельзя безопасно просто скопировать Ecovacs в configuration.yaml

Актуальная интеграция Ecovacs в Home Assistant создаётся через **Settings → Devices & services → Add Integration → Ecovacs**.

Config entry хранится во внутреннем `.storage`. Пакет намеренно не генерирует и не патчит:

```text
.storage/core.config_entries
.storage/core.device_registry
.storage/core.entity_registry
```

Это позволяет интегрировать DEEBOT в уже работающий HA без риска повредить существующий registry.

## 4. Включение локального DNS

После запуска Bumper:

```bash
sudo /opt/deebot-x1-local/enable-dns.sh
```

Скрипт:

- не заменяет молча существующий Pi-hole/AdGuard;
- при занятом `:53` выдаёт необходимые DNS rewrite;
- перенаправляет Ecovacs-домены на Bumper.

Для X1 предпочтительно использовать отдельный DHCP reservation и применять локальный DNS только к роботу/IoT VLAN.

После изменения DNS полностью перезагрузите X1.

Откат:

```bash
sudo /opt/deebot-x1-local/disable-dns.sh
```

## 5. Подключение существующего Home Assistant

В HA:

```text
Настройки
→ Устройства и службы
→ Добавить интеграцию
→ Ecovacs
→ Self-hosted
```

Укажите:

```text
REST URL:  http://192.168.1.20:8007
MQTT URL:  mqtts://192.168.1.20:8883
Verify MQTT SSL certificate: OFF
```

Замените `192.168.1.20` на IP Bumper.

Если authentication в Bumper выключена, допустимы произвольный корректный email и строка-пароль для полей входа.

После появления X1 сопоставьте сегменты карты с Areas Home Assistant в настройках vacuum entity. В современных версиях HA это даёт штатный выбор комнат через `Clean by area`.

## 6. Проверка связи с HA

Без токена:

```bash
sudo /opt/deebot-x1-local/ha-check.sh
```

Будет проверена только сеть/HTTP.

Если PWA уже настроена, `ha-check.sh` использует локально сохранённый токен и покажет найденные `vacuum.*` / `image.*` сущности, не печатая сам токен.

Можно передать токен только в окружении текущей команды:

```bash
sudo HA_TOKEN='...' /opt/deebot-x1-local/ha-check.sh
```

## 7. Отдельная мобильная PWA — опционально

Она нужна только если штатный интерфейс HA не устраивает.

Сначала создайте Long-Lived Access Token в существующем HA, затем:

```bash
sudo /opt/deebot-x1-local/configure-dashboard.sh
```

Или с явным адресом:

```bash
sudo /opt/deebot-x1-local/configure-dashboard.sh \
  --ha-url https://ha.home.arpa:8123
```

Если HA использует локальный self-signed сертификат и сервер Bumper ему не доверяет:

```bash
sudo /opt/deebot-x1-local/configure-dashboard.sh \
  --ha-url https://ha.home.arpa:8123 \
  --insecure-ha
```

`--insecure-ha` относится **только** к server-to-server соединению PWA → HA. Предпочтительнее установить корректный локальный CA.

Панель:

```text
http://BUMPER_IP:8090/
```

Токен хранится только в:

```text
/opt/deebot-x1-local/.dashboard.env
```

с правами `0600`; браузеру токен не выдаётся.

Если уже есть Nginx/Caddy, рекомендуется reverse proxy и запуск PWA только на loopback:

```bash
sudo /opt/deebot-x1-local/configure-dashboard.sh --listen 127.0.0.1
```

Примеры:

```text
examples/nginx-dashboard.conf
examples/caddy-dashboard.txt
```

## 8. Что лучше использовать как основной UI

Для актуального Home Assistant предпочтителен штатный интерфейс:

1. `vacuum.*` entity DEEBOT X1;
2. mapping сегментов X1 → HA Areas;
3. встроенный `Clean by area`;
4. штатная Tile card с vacuum commands;
5. `image.*` карта, если её предоставляет Ecovacs integration.

`export-ha-config.sh` создаёт заготовку `lovelace-deebot-x1.yaml` только на встроенных карточках Home Assistant — без HACS-зависимостей.

## 9. Диагностика

```bash
sudo /opt/deebot-x1-local/status.sh
sudo /opt/deebot-x1-local/diagnose.sh
sudo /opt/deebot-x1-local/ha-check.sh
```

Диагностический архив:

```bash
sudo /opt/deebot-x1-local/collect-debug.sh
```

В архив намеренно не входят:

- HA token;
- `.dashboard.env`;
- приватные TLS-ключи;
- файлы `.storage` Home Assistant;
- конфигурация внешнего HA.

## 10. Backup / restore

```bash
sudo /opt/deebot-x1-local/backup.sh
```

Сохраняются Bumper, сертификаты, локальный архив карт и конфигурация PWA.

**Конфигурация Home Assistant не включается**, поскольку HA рассматривается как независимая инфраструктура.

Восстановление:

```bash
sudo /opt/deebot-x1-local/restore.sh /path/to/backup.tar.gz
```

`restore.sh` не останавливает и не изменяет HA.

## 11. Обновление

На последний **стабильный GitHub release** Bumper:

```bash
sudo /opt/deebot-x1-local/update.sh --latest
```

На конкретный tag/branch (для осознанного тестирования):

```bash
sudo /opt/deebot-x1-local/update.sh --ref v0.4.1
```

`install.sh` при повторном запуске Bumper не обновляет. Обновляются только Bumper и, если включена, наша PWA. Home Assistant не обновляется. Перед изменением ревизии автоматически создаётся backup.

## 12. Удаление

```bash
sudo /opt/deebot-x1-local/uninstall.sh
```

Останавливаются только Bumper/PWA и удаляется наш DNS override. Home Assistant не трогается.

## 13. Безопасная последовательность миграции X1

Не выполняйте factory reset и не удаляйте текущую карту.

Порядок:

1. поднять Bumper;
2. подключить/проверить существующий HA;
3. включить DNS override;
4. перезагрузить X1;
5. проверить MQTT/Bumper;
6. добавить Ecovacs Self-hosted в HA;
7. проверить карту, start/pause/dock и уборку комнат;
8. только после этого запретить X1 выход в WAN.

Пример firewall policy:

```text
X1 -> local DNS        ALLOW  TCP/UDP 53
X1 -> Bumper           ALLOW  необходимые локальные порты Bumper
X1 -> local NTP        ALLOW  UDP 123
X1 -> LAN              только необходимые адреса
X1 -> WAN              DENY
```

При проблемах сначала:

```bash
sudo /opt/deebot-x1-local/collect-debug.sh
sudo /opt/deebot-x1-local/disable-dns.sh
```

а не factory reset.

## 14. Миграция со старой версии этого пакета

Ранее пакет мог создавать контейнер `deebot-homeassistant`. Новая версия больше им не управляет.

Если установщик обнаружит такой контейнер, он только выдаст предупреждение. Он **не остановит его автоматически**, поскольку нельзя надёжно отличить нужную пользователю инсталляцию от временной.

После подключения к вашему основному HA старый контейнер можно остановить вручную:

```bash
docker stop deebot-homeassistant
docker rm deebot-homeassistant
```

Сначала убедитесь, что именно этот контейнер больше не используется.
