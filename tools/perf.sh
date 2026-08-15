#!/usr/bin/env bash
# perf — controlled performance runner + floor-device suite (design §16.1, §17
# Phase 4). Runs named scenes across device profiles headless under Lune,
# writes artifacts/phase-4/perf.json, enforces bench/perf_budgets.json, and
# exits nonzero on a budget violation. `tools/perf.sh baseline` re-records the
# budgets file. Headless numbers are trend-only; device is authoritative (§14.3).
set -euo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# (7.7.0-rc.1, Nov 2025) shadowed the rokit-managed 7.7.0 for months; its
# reflection database does not know `Workspace.PlayerScriptsUseInputActionSystem`,
# so a project declaring it FAILED THE BUILD with "Unknown property" while the
# pinned toolchain built it fine. Measured 2026-08-15.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
exec lune run tools/lune/perf "$@"
