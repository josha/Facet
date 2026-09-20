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
# --check, NOT a bare materialize. The snapshot is COMMITTED, so the only thing
# an entry point can honestly do with it is VERIFY it. A bare run re-fetches and
# rewrites the vendored tree from the pin, which means a tampered or locally
# edited Compose would be silently repaired on the way into a build instead of
# reported -- the supply-chain failure this gate exists to catch, turned into a
# no-op. A mismatch here is a FINDING; restoring the snapshot is an explicit
# `python3 tools/sync_compose.py` a human runs, on purpose, by itself.
python3 tools/sync_compose.py --check || exit $?
exec python3 tools/package.py "$@"
