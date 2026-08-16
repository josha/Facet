#!/usr/bin/env bash
# LuauUI test: runs the deterministic Lune suite ONCE PER TREE STATE and REFUSES
# a green verdict if the summary line is missing (a main-thread yield truncates
# the suite with exit 0 — docs/lessons/lune-main-thread-yield-truncates-suite.md).
# Writes artifacts/test.json.
#
# Usage:
#   tools/test.sh [N]        run/serve the suite, judge it, write artifacts/test.json.
#                            N = minimum expected pass count (default 1).
#   tools/test.sh --ensure-cache
#                            ensure a VALID cached transcript exists; exit 0 only if
#                            the suite is green, complete and full-tier. Writes no
#                            artifacts/test.json — this is the seam
#                            tools/suite_transcript.sh calls.
#   tools/test.sh --fingerprint   print the content hash of the tree under test.
#   tools/test.sh --status        print `hit` or `miss` WITHOUT running anything.
#
# ────────────────────────────────────────────────────────────────────────────
# WHY THERE IS A CACHE AT ALL (D0.1, 2026-08-16).
# A full 28-gate sweep invoked this suite 241 times to grep 1074 lines out of a
# byte-identical transcript. Measured: 83.4 s a run, 5618 passed — the better
# part of four hours per sweep regenerating one file. Nothing about the checks'
# meaning wants a fresh run; they all assert against the same tree.
#
# THE CACHE IS THE DANGEROUS PART, not the suite. Serve a stale or red
# transcript and 241 gate checks become decoration in one commit. Four guards,
# each drawn from this repo's own scar tissue, and each asserted by breaking it
# on purpose in tools/suite_cache_selftest.sh:
#
#   1. THE EXIT CODE RIDES WITH THE TRANSCRIPT. gate_manifest.luau:25-39
#      documents FORM A vs FORM B precisely because a pipeline loses
#      run-tests.sh's status. --ensure-cache re-derives the verdict from the
#      transcript on every call and refuses a red/short/truncated one, so the
#      existing `&&` chains keep working unchanged.
#   2. THE FINGERPRINT IS CONTENT, NEVER TIME. A clock- or session-keyed cache
#      outliving an edit is the "reads two checked-in files and executes
#      nothing" shape tools/prior_gates.sh exists to have removed (PG-2, ledger
#      C-08). Any edit under src/ tests/ examples/ vendor/, or to the toolchain
#      pins, busts it.
#   3. THE FAST TIER IS REFUSED BY A BASH MATCH, NOT A PIPELINE. `printf | grep
#      -q` returns 141 under pipefail when it MATCHES (grep exits at the first
#      hit, printf takes SIGPIPE), which passed a fast-tier transcript straight
#      through once already (mutation M9, 2026-08-13).
#   4. HIT-OR-RUN, NEVER TRUST-THE-FILE. A miss runs the suite. `tools/gate.sh
#      <one-gate>` outside a sweep stays exactly as honest as it was.
#
# PASS/FAIL COUNTS ARE RE-DERIVED FROM THE TRANSCRIPT, never read back from the
# cached metadata, so a transcript mutated on disk after caching cannot hide
# behind its own good bookkeeping. `exit_code` is the one field that cannot be
# re-derived and is therefore the only one trusted.
# ────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# (7.7.0-rc.1, Nov 2025) shadowed the rokit-managed 7.7.0 for months; its
# reflection database does not know `Workspace.PlayerScriptsUseInputActionSystem`,
# so a project declaring it FAILED THE BUILD with "Unknown property" while the
# pinned toolchain built it fine. Measured 2026-08-15.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

CACHE_DIR="${LUAUUI_SUITE_CACHE_DIR:-artifacts/suite_cache}"
TRANSCRIPT="$CACHE_DIR/transcript.txt"
META="$CACHE_DIR/meta"

# The tree the suite actually reads. examples/ is in here because the example
# drift and reference-app specs require those modules; vendor/ because the
# suite links against it. tools/ is deliberately NOT here — editing a gate
# script cannot change a spec's outcome.
suite_fingerprint() {
	{
		find src tests examples vendor -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 shasum -a 256
		shasum -a 256 run-tests.sh rokit.toml 2>/dev/null
		lune --version 2>&1
	} | shasum -a 256 | cut -d' ' -f1
}

meta_get() {
	[ -f "$META" ] || return 1
	sed -n "s/^$1=//p" "$META" | head -1
}

cache_status() {
	if [ ! -f "$TRANSCRIPT" ] || [ ! -f "$META" ]; then
		echo miss
		return
	fi
	if [ "$(meta_get fingerprint)" != "$1" ]; then
		echo miss
		return
	fi
	echo hit
}

ensure_only=0
min_expected=1
case "${1:-}" in
	--fingerprint)
		suite_fingerprint
		exit 0
		;;
	--status)
		cache_status "$(suite_fingerprint)"
		exit 0
		;;
	--ensure-cache)
		ensure_only=1
		;;
	"")
		;;
	# An unknown flag must NOT fall through to min_expected. It used to: the
	# comparison `[ "$passed" -lt "--whatever" ]` errors, the else branch never
	# runs, and the script prints its own summary line — a non-empty string that
	# a caller checking `[ -n ]` reads as a successful answer.
	-*)
		echo "tools/test.sh: unknown option '$1' (expected --ensure-cache, --fingerprint, --status, or a minimum pass count)" >&2
		exit 2
		;;
	*)
		min_expected="$1"
		;;
esac

mkdir -p artifacts

fingerprint="$(suite_fingerprint)"
cached=0
if [ "$(cache_status "$fingerprint")" = "hit" ]; then
	plain="$(cat "$TRANSCRIPT")"
	code="$(meta_get exit_code)"
	cached=1
else
	out="$(./run-tests.sh 2>&1)"
	code=$?
	# Strip ANSI color codes before parsing.
	plain="$(printf '%s' "$out" | sed $'s/\x1b\\[[0-9;]*m//g')"
fi
case "$code" in
	'' | *[!0-9]*) code=1 ;;
esac

passed="$(printf '%s' "$plain" | grep -Eo '^[0-9]+ passed' | grep -Eo '^[0-9]+' | tail -1)"
failed="$(printf '%s' "$plain" | grep -Eo '^[0-9]+ failed' | grep -Eo '^[0-9]+' | tail -1)"

if [ "$cached" -eq 0 ]; then
	# Meta goes away FIRST and comes back LAST, so a crash mid-write leaves no
	# fingerprint to hit and the next call re-runs. The opposite order can pair
	# an old fingerprint with a new transcript.
	mkdir -p "$CACHE_DIR"
	rm -f "$META"
	printf '%s\n' "$plain" >"$CACHE_DIR/.transcript.tmp" && mv -f "$CACHE_DIR/.transcript.tmp" "$TRANSCRIPT"
	{
		echo "fingerprint=$fingerprint"
		echo "exit_code=$code"
		echo "passed=${passed:-}"
		echo "failed=${failed:-}"
	} >"$CACHE_DIR/.meta.tmp" && mv -f "$CACHE_DIR/.meta.tmp" "$META"
fi

status=FAIL
reason=""
if [[ "$plain" == *LUAUUI-FAST-TIER* ]]; then
	# The inner-loop tier (./run-tests.sh --fast) prints that marker. It runs a
	# SUBSET of the specs, so its "N passed" is not a suite result and must never
	# be written into artifacts/test.json as one.
	#
	# A BASH MATCH, NOT A PIPELINE. `printf ... | grep -q X` under `set -o pipefail`
	# returns 141, not 0, when it matches: grep -q exits at the first hit, printf
	# takes SIGPIPE, and pipefail reports the pipeline as FAILED. Written that way
	# this guard passed a fast-tier transcript straight through (mutation M9,
	# 2026-08-13) — the shape the gate-integrity sweep calls a check that cannot
	# fail.
	reason="fast tier transcript - tools/test.sh gates on the FULL suite only (run ./run-tests.sh with no arguments)"
elif [ "$code" -ne 0 ]; then
	reason="suite exited $code"
elif [ -z "$passed" ]; then
	reason="no 'N passed' summary line - suite truncated (see lessons)"
elif [ -n "$failed" ] && [ "$failed" != "0" ]; then
	reason="$failed tests failed"
elif [ "$passed" -lt "$min_expected" ]; then
	reason="only $passed passed; expected >= $min_expected (unregistered spec is a silent zero)"
else
	status=PASS
fi

if [ "$ensure_only" -eq 1 ]; then
	if [ "$status" = "PASS" ]; then
		exit 0
	fi
	echo "tools/test.sh --ensure-cache: refusing this transcript - $reason" >&2
	exit 1
fi

cat >artifacts/test.json <<EOF
{
  "schema": "luauui-test/1",
  "status": "$status",
  "requirement": "UI-AGENT-001",
  "passed": ${passed:-0},
  "failed": ${failed:-0},
  "minExpected": $min_expected,
  "exitCode": $code,
  "cached": $(if [ "$cached" -eq 1 ]; then echo true; else echo false; fi),
  "fingerprint": "$fingerprint",
  "reason": "$reason"
}
EOF
echo "test: $status passed=${passed:-0} ${reason:+($reason)}$(if [ "$cached" -eq 1 ]; then echo " [cached]"; fi) (artifacts/test.json)"
[ "$status" = "PASS" ]
