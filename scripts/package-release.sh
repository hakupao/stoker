#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.2.3}"
DIST_DIR="${ROOT_DIR}/dist"
CLI_NAME="stoker-cli-${VERSION}"
GUI_NAME="stoker-gui-${VERSION}"
APP_DIR="${DIST_DIR}/Stoker.app"
CLI_TARBALL="${DIST_DIR}/${CLI_NAME}.tar.gz"
GUI_ZIP="${DIST_DIR}/${GUI_NAME}.zip"
GUI_DMG="${DIST_DIR}/${GUI_NAME}.dmg"
DMG_STAGING="${DIST_DIR}/dmg-staging"
DMG_VOLNAME="Stoker"
DMG_BG_TIFF="${ROOT_DIR}/design/stoker-ui-pack/assets/dmg/dmg-background.tiff"
DMG_VOLICON="${ROOT_DIR}/design/stoker-ui-pack/assets/png/app-icon/Stoker.icns"

usage() {
  cat <<'USAGE'
Usage: scripts/package-release.sh [--check]

Builds two release artifacts:
  1. CLI artifact for advanced users who want the lightweight launchd scripts.
  2. GUI artifact for beginners who want the menu bar app package.
USAGE
}

required_paths=(
  "install.sh"
  ".env.example"
  "bin/activate-ai-window.sh"
  "bin/activation-state.sh"
  "scripts/install-launchd.sh"
  "app/StokerMenuBar/build-app.sh"
  "README.md"
  "README_CN.md"
  "INSTALL.md"
  "INSTALL_CN.md"
  "LICENSE"
)

check_inputs() {
  local missing=0
  local path
  for path in "${required_paths[@]}"; do
    if [[ ! -e "${ROOT_DIR}/${path}" ]]; then
      echo "Missing required release input: ${path}" >&2
      missing=1
    fi
  done

  if (( missing != 0 )); then
    return 1
  fi

  echo "CLI artifact: ${CLI_TARBALL}"
  echo "GUI artifact: ${GUI_DMG}"
  echo "GUI fallback zip: ${GUI_ZIP}"
  echo "App bundle: ${APP_DIR}"
}

build_cli_archive() {
  local staging
  staging="$(mktemp -d)"
  trap 'rm -rf "$staging"' RETURN

  local root="${staging}/${CLI_NAME}"
  mkdir -p "$root"

  cp "${ROOT_DIR}/install.sh" "$root/"
  cp "${ROOT_DIR}/.env.example" "$root/"
  cp "${ROOT_DIR}/CHANGELOG.md" "$root/"
  cp "${ROOT_DIR}/CONTRIBUTING.md" "$root/"
  cp "${ROOT_DIR}/LICENSE" "$root/"
  cp "${ROOT_DIR}/README.md" "$root/"
  cp "${ROOT_DIR}/README_CN.md" "$root/"
  cp "${ROOT_DIR}/INSTALL.md" "$root/"
  cp "${ROOT_DIR}/INSTALL_CN.md" "$root/"
  cp -R "${ROOT_DIR}/bin" "$root/bin"
  cp -R "${ROOT_DIR}/codex-probe" "$root/codex-probe"
  mkdir -p "$root/scripts"
  cp "${ROOT_DIR}/scripts/install-launchd.sh" "$root/scripts/"
  mkdir -p "$root/logs/raw" "$root/run" "$root/launchd"

  tar -czf "$CLI_TARBALL" -C "$staging" "$CLI_NAME"
}

# Regenerate the DMG background from its source renderer when the toolchain is available
# (mirrors the app-icon regeneration in build-app.sh), so the committed TIFF always reflects
# the current art. Falls back silently to the committed asset when swift/tiffutil are absent
# or rendering fails. Rendering is deterministic, so this produces no spurious git diffs.
regenerate_dmg_background() {
  command -v swift >/dev/null 2>&1 || return 0
  command -v tiffutil >/dev/null 2>&1 || return 0

  local tool="${ROOT_DIR}/design/stoker-ui-pack/tools/render_dmg_background.swift"
  local dir="${ROOT_DIR}/design/stoker-ui-pack/assets/dmg"
  [[ -f "$tool" ]] || return 0

  if ! swift "$tool" "$dir" >/dev/null 2>&1; then
    echo "WARNING: DMG background render failed; using committed asset" >&2
    return 0
  fi
  if ! tiffutil -cathidpicheck "${dir}/dmg-background.png" "${dir}/dmg-background@2x.png" \
        -out "${dir}/dmg-background.tiff" >/dev/null 2>&1; then
    echo "WARNING: DMG background TIFF build failed; using committed asset" >&2
  fi
}

# Plain, unstyled DMG: just the app + an Applications symlink. Used as a fallback when
# Finder window styling is unavailable (e.g. headless CI without Finder automation).
build_plain_dmg() {
  rm -rf "$DMG_STAGING"
  mkdir -p "$DMG_STAGING"
  cp -R "$APP_DIR" "$DMG_STAGING/"
  ln -s /Applications "${DMG_STAGING}/Applications"
  hdiutil create \
    -volname "$DMG_VOLNAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$GUI_DMG" >/dev/null
  rm -rf "$DMG_STAGING"
}

# Styled DMG: a beginner-friendly installer window with a branded "Forge" background
# (ember arrow + bilingual drag-to-install / first-launch steps), the app and Applications
# laid out either side of the arrow, and a custom volume icon. Returns non-zero (so the
# caller can fall back to a plain DMG) if any required tool or the Finder layout step fails.
build_styled_dmg() {
  command -v osascript >/dev/null 2>&1 || return 1
  regenerate_dmg_background
  [[ -f "$DMG_BG_TIFF" ]] || return 1

  local stage rw mnt attach_out size_mb
  stage="$(mktemp -d)"
  rw="$(mktemp -u).dmg"

  cp -R "$APP_DIR" "${stage}/Stoker.app"
  ln -s /Applications "${stage}/Applications"
  mkdir -p "${stage}/.background"
  cp "$DMG_BG_TIFF" "${stage}/.background/dmg-background.tiff"
  [[ -f "$DMG_VOLICON" ]] && cp "$DMG_VOLICON" "${stage}/.VolumeIcon.icns"

  # Detach any stale Stoker volume so the volume name is unambiguous for Finder.
  hdiutil detach "/Volumes/${DMG_VOLNAME}" -force >/dev/null 2>&1 || true

  size_mb=$(( $(du -sm "$stage" | cut -f1) + 60 ))
  if ! hdiutil create -volname "$DMG_VOLNAME" -srcfolder "$stage" -fs HFS+ \
        -format UDRW -ov "$rw" >/dev/null 2>&1; then
    rm -rf "$stage"; rm -f "$rw"; return 1
  fi
  hdiutil resize -size "${size_mb}m" "$rw" >/dev/null 2>&1 || true

  # Attach WITHOUT a custom -mountpoint: the volume must mount at /Volumes/Stoker so
  # Finder can address it by name. Parse the real mountpoint for file operations.
  attach_out="$(hdiutil attach "$rw" -readwrite -noverify -noautoopen 2>/dev/null)" || {
    rm -rf "$stage"; rm -f "$rw"; return 1
  }
  mnt="$(printf '%s\n' "$attach_out" | grep -o '/Volumes/.*' | tail -1)"
  if [[ -z "$mnt" || ! -d "$mnt" ]]; then
    hdiutil detach "/Volumes/${DMG_VOLNAME}" -force >/dev/null 2>&1 || true
    rm -rf "$stage"; rm -f "$rw"; return 1
  fi

  # Custom volume icon (so the mounted disk shows the Stoker ember mark).
  if [[ -f "${mnt}/.VolumeIcon.icns" ]] && command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$mnt" 2>/dev/null || true
  fi

  # Lay out the installer window via Finder. References the volume by NAME. The
  # close/open cycle forces Finder to render + persist the background into .DS_Store.
  if ! /usr/bin/osascript - "$DMG_VOLNAME" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  set volName to item 1 of argv
  tell application "Finder"
    tell disk volName
      open
      delay 1
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 120, 860, 540}
      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 128
      set text size of viewOptions to 12
      set background picture of viewOptions to file ".background:dmg-background.tiff"
      set position of item "Stoker.app" of container window to {170, 168}
      set position of item "Applications" of container window to {490, 168}
      -- NOTE: do NOT position the hidden ".background" folder here — repositioning it makes
      -- Finder bump the .app icon off-canvas. Left alone, Finder auto-places ".background"
      -- in the top-left corner, clear of the title. (.fseventsd/.Trashes are removed below.)
      update without registering applications
      delay 1
      close
      open
      delay 2
      close
    end tell
  end tell
end run
APPLESCRIPT
  then
    hdiutil detach "$mnt" -force >/dev/null 2>&1 || true
    rm -rf "$stage"; rm -f "$rw"; return 1
  fi

  # Drop OS-generated hidden cruft so it can't clutter the window for users who show
  # hidden files. On the read-only converted image these are never recreated.
  rm -rf "${mnt}/.fseventsd" "${mnt}/.Trashes" >/dev/null 2>&1 || true

  sync
  hdiutil detach "$mnt" -force >/dev/null 2>&1 || hdiutil detach "/Volumes/${DMG_VOLNAME}" -force >/dev/null 2>&1 || true

  rm -f "$GUI_DMG"
  if ! hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$GUI_DMG" >/dev/null 2>&1; then
    rm -rf "$stage"; rm -f "$rw"; return 1
  fi

  rm -rf "$stage"; rm -f "$rw"
  [[ -f "$GUI_DMG" ]]
}

build_gui_package() {
  "${ROOT_DIR}/app/StokerMenuBar/build-app.sh"

  rm -f "$GUI_ZIP" "$GUI_DMG"
  ditto -c -k --norsrc --keepParent "$APP_DIR" "$GUI_ZIP"

  if ! command -v hdiutil >/dev/null 2>&1; then
    echo "hdiutil not found; skipped DMG and kept ${GUI_ZIP}" >&2
    return 0
  fi

  if build_styled_dmg; then
    echo "Built styled ${GUI_DMG}"
  else
    echo "WARNING: styled DMG layout unavailable; built a plain DMG instead" >&2
    build_plain_dmg
  fi
}

case "${1:-}" in
  --check)
    check_inputs
    ;;
  -h|--help|help)
    usage
    ;;
  "")
    check_inputs
    mkdir -p "$DIST_DIR"
    build_cli_archive
    build_gui_package
    echo "Built ${CLI_TARBALL}"
    if [[ -f "$GUI_DMG" ]]; then
      echo "Built ${GUI_DMG}"
    fi
    echo "Built ${GUI_ZIP}"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
