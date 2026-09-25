#!/usr/bin/env bash





set -euo pipefail
cd "$(dirname "$0")/.."





export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
exec lune run tools/lune/perf "$@"
