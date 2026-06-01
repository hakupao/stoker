#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"${ROOT_DIR}/scripts/generate-app-icon.sh" "$TMP_DIR"

test -s "$TMP_DIR/AppIcon.icns"
test -s "$TMP_DIR/icon_512x512@2x.png"
file "$TMP_DIR/AppIcon.icns" | grep -q 'Mac OS X icon'

grep -q 'CFBundleIconFile' "${ROOT_DIR}/app/StokerMenuBar/build-app.sh"
grep -q 'INSTALL_CN.md' "${ROOT_DIR}/app/StokerMenuBar/build-app.sh"
grep -q 'codex-probe' "${ROOT_DIR}/app/StokerMenuBar/build-app.sh"
grep -q '安装' "${ROOT_DIR}/INSTALL_CN.md"

echo "app bundle assets test passed"
