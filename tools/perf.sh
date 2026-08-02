#!/usr/bin/env bash
# perf — controlled performance runner + floor-device suite (design §16.1, §17
# Phase 4). Runs named scenes across device profiles headless under Lune,
# writes artifacts/phase-4/perf.json, enforces bench/perf_budgets.json, and
# exits nonzero on a budget violation. `tools/perf.sh baseline` re-records the
# budgets file. Headless numbers are trend-only; device is authoritative (§14.3).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
exec lune run tools/lune/perf "$@"
