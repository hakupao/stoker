#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$ROOT_DIR/codex-probe/probe.py" ]]; then
  echo "expected codex-probe/probe.py to exist" >&2
  exit 1
fi

output="$(
  ACTIVATION_TOOL=codex \
  "$ROOT_DIR/bin/activate-ai-window.sh" --dry-run
)"

grep -F -- "--cd $ROOT_DIR/codex-probe" <<<"$output" >/dev/null
grep -F -- "Read only ./probe.py" <<<"$output" >/dev/null
grep -F -- "Do not inspect any other path" <<<"$output" >/dev/null

if grep -F -- "Reply exactly READY" <<<"$output" >/dev/null; then
  echo "expected Codex probe dry-run prompt instead of READY-only prompt" >&2
  exit 1
fi

echo "codex probe command test passed"
