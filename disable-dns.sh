#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID} -eq 0 ]] || { echo "Запустите через sudo" >&2; exit 1; }
rm -f /etc/dnsmasq.d/02-deebot-bumper.conf
if command -v dnsmasq >/dev/null 2>&1 && dnsmasq --test; then
  systemctl restart dnsmasq || true
fi
echo "Локальные DNS-переопределения Ecovacs удалены. Не забудьте вернуть DNS робота в DHCP/роутере."
