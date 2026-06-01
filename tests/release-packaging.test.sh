#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$("${ROOT_DIR}/scripts/package-release.sh" --check)"

grep -q 'CLI artifact' <<<"$output"
grep -q 'GUI artifact' <<<"$output"
grep -q 'Stoker.app' <<<"$output"
grep -q 'Applications' "${ROOT_DIR}/scripts/package-release.sh"
grep -q 'codex-probe' "${ROOT_DIR}/scripts/package-release.sh"

echo "release packaging test passed"
