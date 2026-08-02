#!/usr/bin/env bash
# LuauUI canonical aggregate gate. Usage: tools/gate.sh [phase-gate-name]
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
exec lune run tools/lune/gate "${1:-phase-0-foundation}"
