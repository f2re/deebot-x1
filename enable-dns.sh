#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ ${EUID} -eq 0 ]] || { echo "Запустите через sudo" >&2; exit 1; }
[[ -f "$INSTALL_DIR/.install.env" ]] || { echo "Сначала выполните install.sh" >&2; exit 1; }
# shellcheck source=/dev/null
. "$INSTALL_DIR/.install.env"

IFACE="$(ip route show default | awk 'NR==1{print $5}')"
UPSTREAM_DNS="${UPSTREAM_DNS:-1.1.1.1}"

# Если на LAN:53 уже живёт Pi-hole/AdGuard/dnsmasq, не ломаем его автоматически.
existing="$(ss -H -lunp 'sport = :53' 2>/dev/null || true)$(ss -H -ltnp 'sport = :53' 2>/dev/null || true)"
if [[ -n "$existing" ]] && ! systemctl is-active --quiet dnsmasq 2>/dev/null; then
  echo "Порт 53 уже занят другим DNS-сервисом:" >&2
  printf '%s\n' "$existing" >&2
  cat >&2 <<EOF
Автоматическая установка dnsmasq остановлена, чтобы не сломать существующий DNS.
Добавьте в ваш Pi-hole/AdGuard/router три локальных rewrite-записи:
  ecouser.net  -> $SERVER_IP   (включая поддомены)
  ecovacs.com  -> $SERVER_IP   (включая поддомены)
  ecovacs.net  -> $SERVER_IP   (включая поддомены)
После этого задайте DEEBOT X1 DNS=$SERVER_IP/адрес вашего локального DNS.
EOF
  exit 3
fi

echo "Будет установлен dnsmasq, слушающий LAN IP $SERVER_IP."
echo "Он перенаправит домены Ecovacs на локальный Bumper."
if [[ -t 0 && -z "${NONINTERACTIVE:-}" ]]; then
  read -r -p "Продолжить? [y/N]: " ok
  [[ "$ok" =~ ^[YyДд]$ ]] || exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y dnsmasq

cp -a /etc/dnsmasq.conf "/etc/dnsmasq.conf.deebot-backup.$(date +%s)" 2>/dev/null || true
cat > /etc/dnsmasq.d/02-deebot-bumper.conf <<EOF
# DEEBOT X1 -> local Bumper
interface=$IFACE
listen-address=$SERVER_IP
bind-interfaces
no-hosts
server=$UPSTREAM_DNS
address=/ecouser.net/$SERVER_IP
address=/ecovacs.com/$SERVER_IP
address=/ecovacs.net/$SERVER_IP
EOF

dnsmasq --test
if ! systemctl enable --now dnsmasq || ! systemctl restart dnsmasq; then
  echo "dnsmasq не запустился. Текущие владельцы порта 53:" >&2
  ss -lunpt | grep -E '(:53[[:space:]])' >&2 || true
  exit 4
fi
sleep 1

for d in portal-ww.ecouser.net api-app.dc-eu.ww.ecouser.net jmq-ngiot-eu.dc.ww.ecouser.net gl-de-api.ecovacs.com; do
  got="$(dig +short @"$SERVER_IP" "$d" A | head -1)"
  printf '%-42s -> %s\n' "$d" "${got:-NO ANSWER}"
done

echo
echo "Теперь в DHCP/роутере задайте для DEEBOT X1 DNS-сервер: $SERVER_IP"
echo "Предпочтительно применить DNS только к IoT VLAN/роботу, а не ко всей домашней сети."
echo "После этого полностью перезагрузите робот, чтобы очистился DNS-кэш."
