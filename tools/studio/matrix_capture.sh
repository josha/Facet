#!/usr/bin/env bash
# Capture one device-matrix row's picture to durable evidence.
#
#   tools/studio/matrix_capture.sh <row-id>
#
# Writes artifacts/cross-platform-proof/captures/<row-id>.png and prints its
# sha256 prefix, which the row's JSON trace records so a capture and its trace
# cannot drift apart.
#
# The rect is the Studio GAME-VIEW PANE, not the emulated device: under the
# device emulator the client viewport is letterboxed inside that pane, so a
# crop to the emulated frame would silently change size per row and a reader
# could not tell a phone capture from a badly cropped desktop one. The pane is
# stable, the device frame is visible inside it, and the row's trace records the
# emulator's own viewport alongside.
set -euo pipefail
cd "$(dirname "$0")/../.."

ROW="${1:?usage: matrix_capture.sh <row-id>}"
OUT="artifacts/cross-platform-proof/captures/${ROW}.png"
mkdir -p "$(dirname "$OUT")"

STUDIO_WINDOW_MATCH="${STUDIO_WINDOW_MATCH:-Place1}" \
	tools/studio/capture_viewport.sh "$OUT" 3 154 1280 1120 >/dev/null

SHA="$(shasum -a 256 "$OUT" | cut -c1-16)"
echo "{\"capture\":\"captures/${ROW}.png\",\"captureSha256_16\":\"${SHA}\",\"bytes\":$(wc -c <"$OUT" | tr -d ' ')}"
