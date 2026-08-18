#!/usr/bin/env bash
# Capture the Roblox Studio VIEWPORT to a real PNG on disk.
#
# Why this exists: the Studio MCP's `screen_capture` streams its image straight
# to the model and never writes a file (verified 2026-07-24 — nothing lands in
# the repo, the Roblox caches, or any temp dir). Every `capture` id in the
# acceptance artifacts therefore pointed at nothing, and a later session could
# not open a single one of them. This makes captures durable evidence.
#
# SAFETY — read before changing: this captures a SINGLE WINDOW by id
# (`screencapture -l`), which reads that window's own backing store. Anything
# stacked in front of Studio cannot appear in the output. Do NOT switch this to
# region capture (`screencapture -R`) or full-screen capture: those read screen
# pixels and will silently pull in whatever else is on the display.
#
# Usage:
#   tools/studio/capture_viewport.sh <out.png> [x y w h]
#
# x/y/w/h are the viewport rect in LOGICAL points inside the Studio window.
# They default to VIEWPORT_RECT below, which is Studio-layout dependent: it
# assumes the default docking (Explorer/Properties right, command bar bottom).
# If Studio's panels are rearranged, re-measure — capture with no rect to get
# the whole window, look at it, and pass the new rect explicitly.
#
# Verify the rect is still right by comparing the printed size against
# `workspace.CurrentCamera.ViewportSize` in the live session; they should match.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/capture"

# default viewport rect, measured 2026-07-24 against a 1928x1297 Studio window
# whose CurrentCamera.ViewportSize read 1233x1067
VIEWPORT_RECT=${VIEWPORT_RECT:-"3 154 1233 1067"}

OUT="${1:?usage: capture_viewport.sh <out.png> [x y w h]}"
shift || true

# STUDIO_WINDOW_MATCH: a substring the window TITLE must contain. Set it when
# more than one Studio window is open — a capture of the wrong place is silent.
read -r WIN_ID WIN_W WIN_H < <(swift "$SRC/window_id.swift" "${STUDIO_WINDOW_MATCH:-}")
if [ -z "${WIN_ID:-}" ]; then
	echo "capture_viewport: no Roblox Studio window" >&2
	exit 3
fi

TMP="$(mktemp -t facet_capture).png"
trap 'rm -f "$TMP"' EXIT

# -l<id>: this window's buffer only. -x: no shutter sound. -o: no drop shadow.
screencapture -x -o -l"$WIN_ID" "$TMP"

if [ "$#" -eq 4 ]; then
	RECT="$*"
else
	RECT="$VIEWPORT_RECT"
fi

# shellcheck disable=SC2086
SIZE="$(swift "$SRC/crop.swift" "$TMP" "$OUT" "$WIN_W" $RECT)"
echo "capture_viewport: $OUT  ${SIZE}px  (window $WIN_ID ${WIN_W}x${WIN_H}, rect $RECT)"
