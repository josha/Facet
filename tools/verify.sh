#!/usr/bin/env bash
# THE ONE VERIFICATION COMMAND (distribution-readiness D7).
#
#   tools/verify.sh affected      the smallest safe local set: producers whose
#                                 declared inputs match your changed paths, plus
#                                 tests/run_one for each changed spec
#   tools/verify.sh fast          the deterministic inner-loop spine
#   tools/verify.sh full          every deterministic producer once, every phase
#                                 view evaluated from that one run
#   tools/verify.sh release       the above plus perf, builds, package and the
#                                 Rascal Rally suite
#
#   --gate <phase>    make sure this phase's producers are in the run; every
#                     other phase is still evaluated from whatever results exist
#   --explain         print why each producer was selected and, for a reused
#                     result, why it was allowed to stand
#   --rerun <id>      ignore the stored result for one producer
#   --jobs N          concurrency cap for the parallel batch (default
#                     min(4, cores/4); serialized producers never overlap)
#
# AFFECTED AND FAST ARE NOT FULL. Both print a banner saying so, and their suite
# results are tier "fast"/"one", which the full/release reader REFUSES. That is
# the same defence ./run-tests.sh --fast has carried since 2026-08-13, when a
# `printf | grep -q` under pipefail let a fast-tier transcript through as a
# suite verdict.
set -uo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S toolchain, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# shadowed the rokit-managed one for months and failed builds that the pinned
# toolchain built fine (measured 2026-08-15).
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
exec lune run tools/lune/verify_cli "$@"
