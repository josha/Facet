#!/usr/bin/env bash
# mkpair.sh <dest-dir> <facet-ref> <rr-ref> — a content-pinned export PAIR.
#
# WHY THIS EXISTS (2026-08-21, after the same failure bit three times in one
# day): a "pair" whose Facet sha was HEAD when an agent STARTED rather than
# when it MEASURED fabricates suite reds that survive an A/B, because both
# arms carry the same stale framework and the mis-pin is common-mode — a
# difference measurement cannot see a defect present in both arms. The
# retraction that earned this script is
# .superpowers/sdd/release-candidate-review/task-rr-reds-report.md.
#
# Both sides come from `git archive` at refs YOU name, resolved AT CALL TIME;
# neither working tree is ever read. The resolved pins land as ARTIFACTS
# (PIN_FACET / PIN_RR) inside the pair, so a mis-pin is visible in the pair
# itself instead of invisible in a transcript. The layout is forced by RR's
# own resolution (every RR spec requires ../../../../GameStudio/ui/Facet/…).
#
# Usage:
#   tools/mkpair.sh /path/to/pairs/mypair HEAD HEAD
#   ( cd <dest>/games/RascalRally/code && lune run tests/run )
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FACET_REPO="${FACET_REPO:-$HERE}"
RR_REPO="${RR_REPO:-$HERE/../../../games/RascalRally/code}"
PAIR="${1:?usage: mkpair.sh <dest-dir> <facet-ref> <rr-ref>}"
FREF="${2:?facet-ref}"
RREF="${3:?rr-ref}"
rm -rf "$PAIR"
mkdir -p "$PAIR/GameStudio/ui/Facet" "$PAIR/games/RascalRally/code"
git -C "$FACET_REPO" archive "$FREF" | tar -x -C "$PAIR/GameStudio/ui/Facet"
git -C "$RR_REPO" archive "$RREF" | tar -x -C "$PAIR/games/RascalRally/code"
git -C "$FACET_REPO" rev-parse "$FREF" > "$PAIR/PIN_FACET"
git -C "$RR_REPO" rev-parse "$RREF" > "$PAIR/PIN_RR"
echo "pair: $PAIR"
echo "  PIN_FACET $(cat "$PAIR/PIN_FACET")"
echo "  PIN_RR    $(cat "$PAIR/PIN_RR")"
