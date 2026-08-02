#!/usr/bin/env bash
# LuauUI fault injection: async/teardown/locale/accessibility/input-switch
# fault paths (design §17 Phase 4). Wraps tools/lune/faults; artifact at
# artifacts/phase-4/faults.json.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
exec lune run tools/lune/faults
