#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ ${EUID} -eq 0 ]] || { echo "sudo required" >&2; exit 1; }
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$INSTALL_DIR/backups/deebot-x1-local-$STAMP.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$INSTALL_DIR/backups"
BUMPER="$INSTALL_DIR/vendor/bumper"

if [[ -d "$BUMPER" ]]; then
  (cd "$BUMPER" && docker compose exec -T bumper sh -c 'tar -C /bumper/data -cf - .' 2>/dev/null) > "$TMP/bumper-data.tar" || true
  cp -a "$BUMPER/certs" "$TMP/" 2>/dev/null || true
  cp -a "$BUMPER/.env" "$TMP/bumper.env" 2>/dev/null || true
fi
cp -a "$INSTALL_DIR/data/maps" "$TMP/map-archive" 2>/dev/null || true
cp -a "$INSTALL_DIR/.install.env" "$TMP/" 2>/dev/null || true
cp -a "$INSTALL_DIR/.dashboard.env" "$TMP/" 2>/dev/null || true
cp -a "$INSTALL_DIR/ha-export" "$TMP/" 2>/dev/null || true

# Home Assistant намеренно не архивируется: он внешняя инфраструктура и этим пакетом не управляется.
tar -C "$TMP" -czf "$OUT" .
chmod 600 "$OUT"
echo "$OUT"
