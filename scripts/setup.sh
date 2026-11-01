#!/usr/bin/env bash
set -euo pipefail

roam_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
roam_python="${ROAM_PYTHON:-python3.14}"
roam_version="0.37.23"
roam_jac="$roam_root/.tools/jac-$roam_version"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)
    roam_asset="macos-aarch64"
    roam_sha="76515787ec7707a8266890449fd43196df37ab1c415ba346bc1d63f10db24014" ;;
  Linux-x86_64)
    roam_asset="linux-x86_64"
    roam_sha="2c3c697616b08516caf01704571e7e7020f4b294cd2bef7f04e8ef1ceec9d6ad" ;;
  Linux-aarch64)
    roam_asset="linux-aarch64"
    roam_sha="a3d134beb520513677978051044400d3f5de0a644eb6b4f0b6330397586915c3" ;;
  *) printf 'Unsupported Jac platform: %s-%s\n' "$(uname -s)" "$(uname -m)" >&2; exit 1 ;;
esac

"$roam_python" -c 'import sys; assert sys.version_info[:2] == (3, 14), "Python 3.14 is required"'
mkdir -p "$roam_root/.tools"
if [[ ! -f "$roam_jac" ]]; then
  roam_download="$(mktemp "$roam_root/.tools/jac-download.XXXXXX")"
  trap 'rm -f "$roam_download"' EXIT
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
    "https://github.com/jaseci-labs/jac/releases/download/v$roam_version/jac-$roam_version-$roam_asset" \
    --output "$roam_download"
else
  roam_download="$roam_jac"
fi

if command -v sha256sum >/dev/null 2>&1; then
  roam_actual="$(sha256sum "$roam_download" | cut -d ' ' -f 1)"
else
  roam_actual="$(shasum -a 256 "$roam_download" | cut -d ' ' -f 1)"
fi
[[ "$roam_actual" == "$roam_sha" ]] || { printf 'Jac checksum mismatch\n' >&2; exit 1; }
if [[ "$roam_download" != "$roam_jac" ]]; then
  chmod +x "$roam_download"
  mv "$roam_download" "$roam_jac"
  trap - EXIT
fi
"$roam_jac" --version

cd "$roam_root/travel-planner"
# Create a real, independent venv. The bundled interpreter's macOS venv creation
# can fail with _PyExc_MemoryError; do not copy another project's environment.
if [[ ! -x .jac/venv/bin/python ]]; then
  "$roam_python" -m venv .jac/venv
fi
.jac/venv/bin/python -c 'import sys; assert sys.version_info[:2] == (3, 14)'
PYTHONNOUSERSITE=1 "$roam_jac" install --dev
printf '\nSetup complete. Run: bash scripts/verify.sh\n'
