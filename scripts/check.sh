#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

for file in ./*.sh scripts/*.sh; do
  [[ -f "$file" ]] || continue
  bash -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x ./*.sh scripts/*.sh
else
  echo "WARN: shellcheck not installed; skipping" >&2
fi

python3 -m py_compile dashboard/app.py tests/test_dashboard_logic.py
python3 -m unittest discover -s tests -v

if command -v node >/dev/null 2>&1; then
  node --check dashboard/static/app.js
else
  echo "WARN: node not installed; skipping JavaScript syntax check" >&2
fi

python3 - <<'PY'
from pathlib import Path
import yaml

yaml.safe_load(Path("docker-compose.dashboard.yml").read_text())
yaml.safe_load(Path(".github/workflows/ci.yml").read_text())
print("YAML: OK")
PY

echo "All available checks passed."
