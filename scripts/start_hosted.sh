#!/usr/bin/env bash
# Run the verified bundle behind the hosting platform's HTTPS/access-control layer.
set -euo pipefail
roam_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${TRAVEL_DB_PATH:?Set TRAVEL_DB_PATH to a persistent absolute SQLite path}"
: "${BACKUP_HISTORY_DB_PATH:?Set BACKUP_HISTORY_DB_PATH to a persistent absolute SQLite path}"
for roam_store in "$TRAVEL_DB_PATH" "$BACKUP_HISTORY_DB_PATH"; do
  [[ "$roam_store" == /* ]] || { printf 'Database paths must be absolute\n' >&2; exit 1; }
  mkdir -p "$(dirname "$roam_store")"
done
[[ "$TRAVEL_DB_PATH" != "$BACKUP_HISTORY_DB_PATH" ]] || { printf 'Use separate trip and history databases\n' >&2; exit 1; }
roam_port="${PORT:-8000}"
[[ "$roam_port" =~ ^[0-9]+$ && "$roam_port" -ge 1 && "$roam_port" -le 65535 ]] || { printf 'Invalid PORT\n' >&2; exit 1; }
roam_jac="${JAC_BIN:-$roam_root/.tools/jac-0.37.23}"
roam_bundle="${ROAM_APP_BUNDLE:-$roam_root/.ci/artifacts/travel-planner.jab}"
[[ -f "$roam_bundle" ]] || { printf 'Build the deployment bundle with scripts/verify.sh first\n' >&2; exit 1; }
export JAC_PRECOMPILE_REQUIRED=1
exec "$roam_jac" run --no-dev --host "${ROAM_BIND_HOST:-127.0.0.1}" --port "$roam_port" "$roam_bundle"
