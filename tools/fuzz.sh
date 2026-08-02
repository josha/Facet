#!/usr/bin/env bash
# LuauUI fuzz: seeded property fuzzing of scheduler/layout/replication
# (design §15.2, §17 Phase 4). Wraps tools/lune/fuzz; artifacts land in
# artifacts/phase-4/fuzz-*.json. Usage: tools/fuzz.sh [target]
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
exec lune run tools/lune/fuzz "${1:-all}"
