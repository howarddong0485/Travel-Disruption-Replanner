#!/usr/bin/env bash
set -euo pipefail

roam_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
roam_jac="${JAC_BIN:-$roam_root/.tools/jac-0.37.23}"
roam_reports="$roam_root/.ci/reports"
roam_artifacts="$roam_root/.ci/artifacts"
roam_pid=""
mkdir -p "$roam_reports" "$roam_artifacts" "$roam_root/.ci/runtime"
roam_jac="$(cd "$(dirname "$roam_jac")" && pwd)/$(basename "$roam_jac")"
[[ "$("$roam_jac" --version)" == 'jac 0.37.23 '* ]] || { printf 'Jac 0.37.23 is required\n' >&2; exit 1; }
cleanup() {
  if [[ -n "$roam_pid" ]]; then
    kill "$roam_pid" 2>/dev/null || true
    wait "$roam_pid" 2>/dev/null || true
    roam_pid=""
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

step() {
  local roam_label="$1"
  shift
  printf '\n%s\n' "$roam_label"
  "$@" 2>&1 | tee "$roam_reports/$roam_label.log"
}

cd "$roam_root/travel-planner"
step version "$roam_jac" --version
step check "$roam_jac" check --nowarn
step tests "$roam_jac" test server/ backup/ planning/ profile/ filter/ budget/ schema/ policy/ risk/ assistant/
step travel-client "$roam_jac" build travel --as client
step backup-client "$roam_jac" build backup_refresh --as client
step planning-demo "$roam_jac" run planning/demo.jac
ROAM_BUILD_OUTPUT="$roam_artifacts" step sealed-build "$roam_jac" run --no-takeover "$roam_root/scripts/build_jab.jac"

smoke() {
  local roam_label="$1"
  local roam_target="$2"
  local roam_store
  roam_store="$(mktemp -d "$roam_root/.ci/runtime/$roam_label.XXXXXX")"
  local roam_port
  roam_port="$("$roam_root/travel-planner/.jac/venv/bin/python" - <<'PY'
import os, socket
with socket.socket() as listener:
    listener.bind(('127.0.0.1', int(os.environ.get('ROAM_SMOKE_PORT', '0'))))
    print(listener.getsockname()[1])
PY
)"
  (
    if [[ "$roam_label" == artifact ]]; then cd "$roam_store"; fi
    export TRAVEL_DB_PATH="$roam_store/travel.sqlite3"
    export BACKUP_HISTORY_DB_PATH="$roam_store/history.sqlite3"
    if [[ "$roam_label" == artifact ]]; then export JAC_PRECOMPILE_REQUIRED=1; fi
    exec "$roam_jac" run --no-dev --host 127.0.0.1 --port "$roam_port" "$roam_target"
  ) > "$roam_reports/$roam_label-server.log" 2>&1 &
  roam_pid=$!
  ROAM_SMOKE_URL="http://127.0.0.1:$roam_port" ROAM_SMOKE_JAC="$roam_jac" ROAM_SMOKE_PID="$roam_pid" \
    step "$roam_label-smoke" "$roam_jac" run --no-takeover "$roam_root/scripts/runtime_smoke.jac"
  cleanup
}

smoke source travel
roam_bundle="$roam_artifacts/travel-planner.jab"
[[ -f "$roam_bundle" ]] || { printf 'Expected sealed bundle missing: %s\n' "$roam_bundle" >&2; exit 1; }
smoke artifact "$roam_bundle"
printf '\nAll verification steps passed. Logs: %s\n' "$roam_reports"
