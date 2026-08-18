#!/usr/bin/env bash
# Facet fuzz: seeded property fuzzing of scheduler/layout/replication
# (design §15.2, §17 Phase 4). Wraps tools/lune/fuzz; artifacts land in
# artifacts/phase-4/fuzz-*.json. Usage: tools/fuzz.sh [target]
set -uo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# (7.7.0-rc.1, Nov 2025) shadowed the rokit-managed 7.7.0 for months; its
# reflection database does not know `Workspace.PlayerScriptsUseInputActionSystem`,
# so a project declaring it FAILED THE BUILD with "Unknown property" while the
# pinned toolchain built it fine. Measured 2026-08-15.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
exec lune run tools/lune/fuzz "${1:-all}"
