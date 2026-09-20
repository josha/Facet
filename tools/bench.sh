#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# (7.7.0-rc.1, Nov 2025) shadowed the rokit-managed 7.7.0 for months; its
# reflection database does not know `Workspace.PlayerScriptsUseInputActionSystem`,
# so a project declaring it FAILED THE BUILD with "Unknown property" while the
# pinned toolchain built it fine. Measured 2026-08-15.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
# --check, NOT a bare materialize. The snapshot is COMMITTED, so the only thing
# an entry point can honestly do with it is VERIFY it. A bare run re-fetches and
# rewrites the vendored tree from the pin, which means a tampered or locally
# edited Compose would be silently repaired on the way into a build instead of
# reported -- the supply-chain failure this gate exists to catch, turned into a
# no-op. A mismatch here is a FINDING; restoring the snapshot is an explicit
# `python3 tools/sync_compose.py` a human runs, on purpose, by itself.
python3 tools/sync_compose.py --check || exit $?
exec lune run tools/lune/bench "$@"
