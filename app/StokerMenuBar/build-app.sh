#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PACKAGE_DIR}/../.." && pwd)"
APP_DIR="${ROOT_DIR}/dist/Stoker.app"
EXECUTABLE="${PACKAGE_DIR}/.build/release/StokerMenuBar"
ENGINE_DIR="${APP_DIR}/Contents/Resources/stoker"
ICON_DIR="${APP_DIR}/Contents/Resources"

cd "$PACKAGE_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS" "$ENGINE_DIR"
cp "$EXECUTABLE" "${APP_DIR}/Contents/MacOS/StokerMenuBar"

# App icon: the Stoker "Forge" mark (ember aperture on a transparent squircle), rendered from
# the designer's vector master (design/.../assets/logo/stoker-app-icon-master.pdf) by
# tools/build_app_icon_from_master.py — sips rasterize -> flood-fill transparent corners ->
# full iconset -> Stoker.icns. tools/generate_stoker_assets.py builds the rest of the pack
# (menu-bar template, cue/status icons, docs).
PACK_DIR="${ROOT_DIR}/design/stoker-ui-pack"
PACK_ICNS="${PACK_DIR}/assets/png/app-icon/Stoker.icns"
PACK_PREVIEW="${PACK_DIR}/assets/png/app-icon/AppIcon.iconset/icon_512x512@2x.png"

# Regenerate pack chrome (cue/status icons, menu-bar template, docs) from the SVG sources when
# a vector renderer is available; the committed assets are used as-is otherwise.
if command -v python3 >/dev/null 2>&1 && command -v rsvg-convert >/dev/null 2>&1; then
  python3 "${PACK_DIR}/tools/generate_stoker_assets.py" >/dev/null 2>&1 \
    || echo "WARNING: pack asset regeneration failed; using committed assets" >&2
fi
# Regenerate the app icon from the vector master. This needs only sips + Pillow (no rsvg), so
# it runs whenever python3 is present and OVERRIDES any app icon the SVG pass above produced.
# Falls back to the committed Stoker.icns if Pillow is unavailable.
if command -v python3 >/dev/null 2>&1; then
  python3 "${PACK_DIR}/tools/build_app_icon_from_master.py" >/dev/null 2>&1 \
    || echo "WARNING: app-icon build from master failed; using committed Stoker.icns" >&2
fi

if [[ -f "$PACK_ICNS" ]]; then
  cp "$PACK_ICNS" "${ICON_DIR}/AppIcon.icns"
  [[ -f "$PACK_PREVIEW" ]] && cp "$PACK_PREVIEW" "${ROOT_DIR}/dist/AppIcon-preview.png"
  # In-window badge: same AI-concept art (256px slot) so the window header icon matches the Dock.
  PACK_BADGE="${PACK_DIR}/assets/png/app-icon/AppIcon.iconset/icon_256x256.png"
  [[ -f "$PACK_BADGE" ]] && cp "$PACK_BADGE" "${ICON_DIR}/AppBadge.png"
  echo "Installed Stoker Forge app icon from ${PACK_ICNS}"
else
  echo "WARNING: design-pack Stoker.icns not found at ${PACK_ICNS}; falling back to legacy icon generator" >&2
  "${ROOT_DIR}/scripts/generate-app-icon.sh" "$ICON_DIR"
  cp "${ICON_DIR}/icon_512x512@2x.png" "${ROOT_DIR}/dist/AppIcon-preview.png"
  rm -rf "${ICON_DIR}/AppIcon.iconset" "${ICON_DIR}/icon_512x512@2x.png"
fi

# Menu bar icon: nothing to bundle. The menu bar flame is drawn in code
# (StokerFlameIcon.swift) and rasterized at runtime via ImageRenderer, so there is
# no menu-bar image asset to copy.

copy_path() {
  local source="$1"
  local destination="$2"
  if [[ -e "$source" ]]; then
    mkdir -p "$(dirname "$destination")"
    cp -R "$source" "$destination"
  fi
}

copy_path "${ROOT_DIR}/install.sh" "${ENGINE_DIR}/install.sh"
copy_path "${ROOT_DIR}/.env.example" "${ENGINE_DIR}/.env.example"
copy_path "${ROOT_DIR}/README.md" "${ENGINE_DIR}/README.md"
copy_path "${ROOT_DIR}/README_CN.md" "${ENGINE_DIR}/README_CN.md"
copy_path "${ROOT_DIR}/INSTALL.md" "${ENGINE_DIR}/INSTALL.md"
copy_path "${ROOT_DIR}/INSTALL_CN.md" "${ENGINE_DIR}/INSTALL_CN.md"
copy_path "${ROOT_DIR}/CHANGELOG.md" "${ENGINE_DIR}/CHANGELOG.md"
copy_path "${ROOT_DIR}/LICENSE" "${ENGINE_DIR}/LICENSE"
copy_path "${ROOT_DIR}/bin" "${ENGINE_DIR}/bin"
copy_path "${ROOT_DIR}/codex-probe" "${ENGINE_DIR}/codex-probe"

# Bundle jq so users without it installed can still use quota features.
_jq_src="${JQ_SRC:-$(command -v jq 2>/dev/null || true)}"
if [[ -n "$_jq_src" && -x "$_jq_src" ]]; then
  cp "$_jq_src" "${ENGINE_DIR}/bin/jq"
  chmod +x "${ENGINE_DIR}/bin/jq"
  codesign --force --sign - "${ENGINE_DIR}/bin/jq" 2>/dev/null || true
  echo "Bundled jq from ${_jq_src}"
else
  echo "WARNING: jq not found on build machine; app will require system jq" >&2
fi

copy_path "${ROOT_DIR}/scripts/install-launchd.sh" "${ENGINE_DIR}/scripts/install-launchd.sh"
mkdir -p "${ENGINE_DIR}/logs/raw" "${ENGINE_DIR}/run" "${ENGINE_DIR}/launchd"

cat >"${APP_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>StokerMenuBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.stoker.menu-bar</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Stoker</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.3.3</string>
  <key>CFBundleVersion</key>
  <string>10</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

# Seal the whole bundle with a deep ad-hoc signature as the FINAL step — after every
# resource, the bundled engine, and Info.plist are in place. Without this the bundle has
# no Contents/_CodeSignature/CodeResources, so on a quarantined (downloaded) first launch
# macOS reports it as damaged ("code has no resources but signature indicates they must be
# present") instead of the normal, user-approvable "unidentified developer". Ad-hoc keeps
# the app free/unnotarized; users still approve it once via System Settings on first open.
if codesign --force --deep --sign - "$APP_DIR" 2>/dev/null; then
  echo "Ad-hoc signed ${APP_DIR}"
  codesign --verify --deep --strict "$APP_DIR" 2>/dev/null \
    && echo "Signature verifies (valid ad-hoc bundle)" \
    || echo "WARNING: ad-hoc signature did not verify" >&2
else
  echo "WARNING: ad-hoc codesign failed; the app bundle is unsigned and may be blocked on first launch" >&2
fi

echo "Built ${APP_DIR}"
