#!/usr/bin/env bash


























set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/capture"



VIEWPORT_RECT=${VIEWPORT_RECT:-"3 154 1233 1067"}

OUT="${1:?usage: capture_viewport.sh <out.png> [x y w h]}"
shift || true



read -r WIN_ID WIN_W WIN_H < <(swift "$SRC/window_id.swift" "${STUDIO_WINDOW_MATCH:-}")
if [ -z "${WIN_ID:-}" ]; then
	echo "capture_viewport: no Roblox Studio window" >&2
	exit 3
fi

TMP="$(mktemp -t facet_capture).png"
trap 'rm -f "$TMP"' EXIT


screencapture -x -o -l"$WIN_ID" "$TMP"

if [ "$#" -eq 4 ]; then
	RECT="$*"
else
	RECT="$VIEWPORT_RECT"
fi

# shellcheck disable=SC2086
SIZE="$(swift "$SRC/crop.swift" "$TMP" "$OUT" "$WIN_W" $RECT)"
echo "capture_viewport: $OUT  ${SIZE}px  (window $WIN_ID ${WIN_W}x${WIN_H}, rect $RECT)"
