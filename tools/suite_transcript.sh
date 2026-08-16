#!/usr/bin/env bash
# Prints ONE valid LuauUI suite transcript on stdout, running the suite at most
# once per tree state. This is what a gate check greps instead of re-running
# `./run-tests.sh` itself:
#
#   out="$(tools/suite_transcript.sh)" && echo "$out" | grep -q '✓.*<case name>'
#
# tools/test.sh owns the cache (fingerprint, transcript, exit code) — this is a
# thin front door onto it, so there is exactly one place that decides whether a
# transcript may be trusted.
#
# ON ANYTHING LESS THAN A GREEN, COMPLETE, FULL-TIER SUITE IT PRINTS NOTHING AND
# EXITS NON-ZERO. Both halves matter and neither is redundant:
#   - the non-zero exit reddens FORM A, whose `&&` chain carries our status;
#   - the empty stdout reddens FORM B (`tools/suite_transcript.sh | grep -q …`),
#     whose exit status is grep's and not ours, so the only way to fail it is to
#     give grep nothing to match.
# A helper that printed a cached transcript and exited 0 over a red suite would
# turn 241 gate checks into decoration in a single commit.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

CACHE_DIR="${LUAUUI_SUITE_CACHE_DIR:-artifacts/suite_cache}"

if ! tools/test.sh --ensure-cache >/dev/null; then
	echo "suite_transcript: no trustworthy transcript to serve (see the line above)" >&2
	exit 1
fi

cat "$CACHE_DIR/transcript.txt"
