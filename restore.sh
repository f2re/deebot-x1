#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ ${EUID} -eq 0 ]] || { echo "Запустите через sudo" >&2; exit 1; }
BACKUP="${1:-}"
if [[ -z "$BACKUP" ]]; then
  BACKUP="$(find "$INSTALL_DIR/backups" -maxdepth 1 -type f -name 'deebot-x1-local-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- || true)"
fi
[[ -f "$BACKUP" ]] || { echo "Backup не найден" >&2; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "Восстановление из: $BACKUP"
tar -C "$TMP" -xzf "$BACKUP"
BUMPER="$INSTALL_DIR/vendor/bumper"
if [[ -d "$BUMPER" ]]; then
  (cd "$BUMPER" && docker compose down) || true
fi
if [[ -f "$INSTALL_DIR/.dashboard.env" ]]; then
  (cd "$INSTALL_DIR" && docker compose -f docker-compose.dashboard.yml down) || true
fi

[[ -d "$TMP/certs" ]] && { rm -rf "$BUMPER/certs"; cp -a "$TMP/certs" "$BUMPER/certs"; }
[[ -f "$TMP/bumper.env" ]] && cp -a "$TMP/bumper.env" "$BUMPER/.env"
[[ -d "$TMP/map-archive" ]] && { mkdir -p "$INSTALL_DIR/data"; rm -rf "$INSTALL_DIR/data/maps"; cp -a "$TMP/map-archive" "$INSTALL_DIR/data/maps"; }
[[ -f "$TMP/.install.env" ]] && cp -a "$TMP/.install.env" "$INSTALL_DIR/.install.env"
[[ -f "$TMP/.dashboard.env" ]] && cp -a "$TMP/.dashboard.env" "$INSTALL_DIR/.dashboard.env"

# Возвращаем исходники Bumper к ревизии, записанной в backup, если она доступна.
if [[ -f "$INSTALL_DIR/.install.env" ]]; then
  # shellcheck source=/dev/null
  . "$INSTALL_DIR/.install.env"
  if [[ -n "${BUMPER_REF:-}" ]]; then
    git -C "$BUMPER" fetch --depth 1 origin "$BUMPER_REF" || true
  fi
  if [[ -n "${BUMPER_COMMIT:-}" ]] && git -C "$BUMPER" cat-file -e "${BUMPER_COMMIT}^{commit}" 2>/dev/null; then
    git -C "$BUMPER" checkout --detach "$BUMPER_COMMIT"
  fi
fi

"$INSTALL_DIR/scripts/prepare-bumper-compose.sh"
(cd "$BUMPER" && docker compose up -d bumper)
if [[ -s "$TMP/bumper-data.tar" ]]; then
  sleep 2
  (cd "$BUMPER" && docker compose exec -T bumper sh -c 'rm -rf /bumper/data/* /bumper/data/.[!.]* /bumper/data/..?* 2>/dev/null || true; tar -C /bumper/data -xf -') < "$TMP/bumper-data.tar"
  (cd "$BUMPER" && docker compose restart bumper)
fi
(cd "$BUMPER" && docker compose up -d)
[[ -f "$INSTALL_DIR/.dashboard.env" ]] && (cd "$INSTALL_DIR" && docker compose -f docker-compose.dashboard.yml up -d --build)

echo "Восстановление Bumper/PWA завершено. Home Assistant не изменялся."
echo "Проверьте: $INSTALL_DIR/diagnose.sh"
