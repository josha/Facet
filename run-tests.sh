#!/usr/bin/env bash
# Single command to run the LuauUI deterministic test suite (pure Luau, headless).
# Usage: ./run-tests.sh
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
exec lune run tests/run
