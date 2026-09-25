#!/usr/bin/env bash



















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
