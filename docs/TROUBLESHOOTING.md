# Диагностика

## Базовая проверка

```bash
sudo /opt/deebot-x1-local/status.sh
sudo /opt/deebot-x1-local/diagnose.sh
sudo /opt/deebot-x1-local/ha-check.sh
```

## X1 не появляется в Bumper

1. Проверьте, что робот использует локальный DNS.
2. Выполните `dig` для доменов Ecovacs с DNS-сервера робота.
3. Проверьте `:8883` и логи Bumper.
4. Верните DNS через `disable-dns.sh` до дальнейшего анализа; factory reset не требуется.

## Карта есть, комнат нет

В Home Assistant откройте vacuum entity и выполните `Map vacuum segments to areas`. PWA показывает только Areas, реально присутствующие в `area_mapping` этой сущности.

## HA находится на другом сервере

Это штатный сценарий. Выполните:

```bash
sudo /opt/deebot-x1-local/configure-ha.sh http://HA_IP:8123
```

Bumper и Home Assistant не обязаны находиться на одном хосте.

## Существующий Pi-hole / AdGuard Home

Не запускайте второй DNS на том же `:53`. `enable-dns.sh` остановится и покажет необходимые rewrite. Добавьте их в уже существующий DNS и задайте этот DNS роботу.
