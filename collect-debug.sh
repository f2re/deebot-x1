#!/usr/bin/env bash
set -u
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ -f "$INSTALL_DIR/.install.env" ]] && . "$INSTALL_DIR/.install.env"
OUT="${1:-/tmp/deebot-x1-debug-$(date +%Y%m%d-%H%M%S).tar.gz}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
{
  echo "date=$(date -Is)"
  echo "kernel=$(uname -a)"
  echo "server_ip=${SERVER_IP:-unknown}"
  echo "ha_mode=${HA_MODE:-none}"
  echo "ha_url=${HA_URL:-not-set}"
  echo "docker=$(docker --version 2>/dev/null || true)"
  echo "compose=$(docker compose version 2>/dev/null || true)"
  echo; ip -br addr; echo; ip route
} > "$TMP/system.txt" 2>&1
ss -lntup > "$TMP/ports.txt" 2>&1 || true
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' > "$TMP/docker-ps.txt" 2>&1 || true
journalctl -u dnsmasq --no-pager -n 300 > "$TMP/dnsmasq.log" 2>&1 || true
for d in portal-ww.ecouser.net jmq-ngiot-eu.dc.ww.ecouser.net api-app.dc-eu.ww.ecouser.net gl-de-api.ecovacs.com; do
  echo "### $d"; dig +short @"${SERVER_IP:-127.0.0.1}" "$d" A 2>&1
done > "$TMP/dns.txt"
if [[ -n "${HA_URL:-}" ]]; then
  curl -k -sS --max-time 5 -o /dev/null -w 'status=%{http_code}\n' "${HA_URL%/}/api/" > "$TMP/homeassistant-reachability.txt" 2>&1 || true
fi
BUMPER="$INSTALL_DIR/vendor/bumper"
[[ -d "$BUMPER" ]] && (cd "$BUMPER" && docker compose logs --no-color --tail=1500 bumper nginx) > "$TMP/bumper.log" 2>&1 || true
[[ -f "$INSTALL_DIR/.dashboard.env" ]] && (cd "$INSTALL_DIR" && docker compose -f docker-compose.dashboard.yml logs --no-color --tail=500 dashboard) > "$TMP/dashboard.log" 2>&1 || true
# Не включаем .env, HA token, сертификатные ключи и любые файлы внешнего Home Assistant.
tar -C "$TMP" -czf "$OUT" .
chmod 600 "$OUT"
echo "$OUT"
