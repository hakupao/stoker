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

# A retired model pinned in an old .env falls back to the current default with a
# WARNING, and dry-run shows the model actually used. A custom model is untouched.
# (Temp copy of the engine so these logs stay out of the real install.)
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin"
cp "$ROOT_DIR/bin/activate-ai-window.sh" "$TMP_DIR/bin/activate-ai-window.sh"

retired_output="$(CODEX_MODEL=gpt-5.4-mini "$TMP_DIR/bin/activate-ai-window.sh" --dry-run --tool codex)"
grep -F -- "WARNING: CODEX_MODEL=gpt-5.4-mini is retired" <<<"$retired_output" >/dev/null \
  || { echo "expected a retired-model warning" >&2; exit 1; }
grep -F -- "--model gpt-5.6-luna" <<<"$retired_output" >/dev/null \
  || { echo "expected dry-run to show the fallback model" >&2; exit 1; }
if grep -F -- "--model gpt-5.4-mini" <<<"$retired_output" >/dev/null; then
  echo "retired model must not reach the codex command" >&2
  exit 1
fi

custom_output="$(CODEX_MODEL=gpt-9-custom "$TMP_DIR/bin/activate-ai-window.sh" --dry-run --tool codex)"
grep -F -- "--model gpt-9-custom" <<<"$custom_output" >/dev/null \
  || { echo "expected a custom model to pass through" >&2; exit 1; }
if grep -F -- "is retired" <<<"$custom_output" >/dev/null; then
  echo "a custom model must not warn" >&2
  exit 1
fi

echo "codex probe command test passed"
