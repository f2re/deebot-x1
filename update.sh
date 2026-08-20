#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/deebot-x1-local}"
[[ ${EUID} -eq 0 ]] || { echo "sudo required" >&2; exit 1; }
[[ -f "$INSTALL_DIR/.install.env" ]] || { echo "Сначала install.sh" >&2; exit 1; }
# shellcheck source=/dev/null
. "$INSTALL_DIR/.install.env"
BUMPER="$INSTALL_DIR/vendor/bumper"
[[ -d "$BUMPER/.git" ]] || { echo "Bumper repository not found" >&2; exit 2; }

REF=""
case "${1:---latest}" in
  --latest)
    REF="$(curl -fsSL --max-time 15 'https://api.github.com/repos/MVladislav/bumper/releases/latest' | jq -r '.tag_name // empty')"
    [[ -n "$REF" ]] || { echo "Не удалось определить latest stable Bumper release" >&2; exit 3; }
    ;;
  --ref)
    REF="${2:-}"
    [[ -n "$REF" ]] || { echo "Использование: $0 [--latest | --ref TAG_OR_BRANCH]" >&2; exit 2; }
    ;;
  -h|--help)
    echo "Использование: sudo $0 [--latest | --ref TAG_OR_BRANCH]"
    echo "По умолчанию обновляет Bumper на последний GitHub release, а не на нестабильный main."
    exit 0
    ;;
  *)
    echo "Использование: sudo $0 [--latest | --ref TAG_OR_BRANCH]" >&2
    exit 2
    ;;
esac
[[ ! "$REF" =~ [[:space:]] ]] || { echo "Некорректный ref" >&2; exit 2; }

CURRENT="$(git -C "$BUMPER" rev-parse HEAD)"
"$INSTALL_DIR/backup.sh"

echo "Bumper: $CURRENT -> $REF"
git -C "$BUMPER" fetch --depth 1 origin "$REF"
TARGET="$(git -C "$BUMPER" rev-parse FETCH_HEAD)"
if [[ "$TARGET" == "$CURRENT" ]]; then
  echo "Bumper уже на выбранной ревизии: $TARGET"
else
  git -C "$BUMPER" checkout --detach "$TARGET"
fi

(cd "$BUMPER" && bash scripts/create-cert.sh)
(cd "$BUMPER" && docker compose config >/dev/null && docker compose up -d --build)
[[ -f "$INSTALL_DIR/.dashboard.env" ]] && (cd "$INSTALL_DIR" && docker compose -f docker-compose.dashboard.yml up -d --build)

python3 - "$INSTALL_DIR/.install.env" "$REF" "$TARGET" <<'PY'
from pathlib import Path
import shlex
import sys

path = Path(sys.argv[1])
updates = {"BUMPER_REF": sys.argv[2], "BUMPER_COMMIT": sys.argv[3]}
lines = path.read_text().splitlines()
out = []
seen = set()
for line in lines:
    key = line.split("=", 1)[0] if "=" in line else ""
    if key in updates:
        out.append(f"{key}={shlex.quote(updates[key])}")
        seen.add(key)
    else:
        out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={shlex.quote(value)}")
path.write_text("\n".join(out) + "\n")
PY
chmod 600 "$INSTALL_DIR/.install.env"

echo "Home Assistant не обновлялся: он управляется отдельно."
"$INSTALL_DIR/diagnose.sh"
