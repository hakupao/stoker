#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash -n install.sh
bash -n bin/activate-ai-window.sh
bash -n bin/activation-state.sh
bash -n scripts/install-launchd.sh
bash -n scripts/package-release.sh
bash -n scripts/generate-app-icon.sh
bash -n app/StokerMenuBar/build-app.sh

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck install.sh bin/activate-ai-window.sh bin/activation-state.sh scripts/install-launchd.sh scripts/package-release.sh scripts/generate-app-icon.sh app/StokerMenuBar/build-app.sh
else
  echo "shellcheck not found; skipped"
fi

if command -v plutil >/dev/null 2>&1; then
  ./install.sh print-plist >/tmp/stoker-validate.plist
  plutil -lint /tmp/stoker-validate.plist >/dev/null
else
  echo "plutil not found; skipped"
fi

./install.sh dry-run >/tmp/stoker-dry-run.log
./install.sh app-status >/tmp/stoker-app-status.json
tests/activation-state.test.sh
tests/keep-awake-config.test.sh
tests/claude-oauth-token.test.sh
tests/claude-status-cache.test.sh
tests/codex-probe-command.test.sh
tests/codex-native-source.test.sh
tests/codex-appserver-source.test.sh
tests/swift-core.test.sh
tests/release-packaging.test.sh
tests/app-bundle-assets.test.sh

if command -v swift >/dev/null 2>&1; then
  swift build --package-path app/StokerMenuBar
else
  echo "swift not found; skipped menu bar app build"
fi

echo "Validation passed"
