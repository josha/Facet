#!/usr/bin/env bash
# The maintainer interface to Facet's Roblox Package release channel. This is a
# wrapper and nothing else: every decision, guard and request lives in
# tools/package.py, which is where to read and where to change behavior.
#
#   tools/package.sh build      rebuild build/Facet.rbxm + build/Facet.manifest.json
#   tools/package.sh status     this tree against the last receipt
#   tools/package.sh verify     build + tree inspection + purity + packaged canary
#   tools/package.sh create     mint the asset       (DRY RUN unless --confirm)
#   tools/package.sh publish    push a new revision  (DRY RUN unless --confirm)
#   tools/package.sh rollback   print both rollback procedures; never uploads
#   tools/package.sh stamp      record a Studio verification on a receipt
#
# build/status/verify are offline. create/publish read ROBLOX_API_KEY from the
# ENVIRONMENT only and never print it. See package/README.md.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
exec python3 tools/package.py "$@"
