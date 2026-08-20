#!/usr/bin/env bash
set -u
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ -f "$INSTALL_DIR/.install.env" ]] && . "$INSTALL_DIR/.install.env"
SERVER_IP="${SERVER_IP:-127.0.0.1}"
BUMPER="$INSTALL_DIR/vendor/bumper"

echo "=== DEEBOT X1 LOCAL DIAGNOSTICS ==="
date -Is
echo "Bumper server: $SERVER_IP"
echo "HA mode: ${HA_MODE:-none}"
echo "HA URL: ${HA_URL:-not configured}"
echo

echo "--- Local ports (HA :8123 не обязателен на этом хосте) ---"
for p in 443 8007 8883 1883 5223 8090 53; do
  if ss -lntup 2>/dev/null | grep -Eq "[:.]$p[[:space:]]"; then echo "OK   $p"; else echo "MISS $p"; fi
done

echo; echo "--- Docker ---"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true

echo; echo "--- Bumper HTTP ---"
curl -vk --max-time 4 "http://127.0.0.1:8007/" -o /tmp/deebot-bumper-http.$$ 2>&1 | tail -12
rm -f /tmp/deebot-bumper-http.$$

echo; echo "--- MQTT TLS ---"
timeout 5 openssl s_client -connect "127.0.0.1:8883" -servername jmq-ngiot-eu.dc.ww.ecouser.net </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null || echo "MQTT TLS check failed"

echo; echo "--- Existing Home Assistant ---"
if [[ -n "${HA_URL:-}" ]]; then
  code="$(curl -k -sS --max-time 5 -o /dev/null -w '%{http_code}' "${HA_URL%/}/api/" 2>/dev/null || true)"
  echo "$HA_URL -> HTTP ${code:-no response} (401 без токена является нормальным признаком доступности)"
else
  echo "HA URL не задан. Это не мешает работе Bumper."
fi

echo; echo "--- DNS redirect ---"
for d in portal-ww.ecouser.net jmq-ngiot-eu.dc.ww.ecouser.net api-app.dc-eu.ww.ecouser.net; do
  printf '%-42s ' "$d"
  dig +short @"$SERVER_IP" "$d" A 2>/dev/null | head -1 || true
done

echo; echo "--- Recent Bumper robot/MQTT events ---"
if [[ -d "$BUMPER" ]]; then
  (cd "$BUMPER" && docker compose logs --tail=250 bumper 2>/dev/null) | grep -Ei 'mqtt|connect|bot|deebot|error|exception' | tail -80 || true
fi

echo
echo "Ожидаемый признак успеха: X1 появляется в Bumper и есть MQTT connection на 8883."
