#!/usr/bin/env bash
# Facet test: runs the deterministic Lune suite ONCE PER TREE STATE and REFUSES
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
#   5. TWO SWEEPS MAY RUN AT ONCE. Cache entries are named by fingerprint and a
#      live entry is never deleted, so a second agent cannot pull the file out
#      from under a reader mid-check. Deleting the metadata before rewriting it
#      — the obvious way to make a partial write un-hittable — made a concurrent
#      gate row go transiently red instead (observed 2026-08-16 during D2).
#      Transcript first, then metadata, both by atomic rename; the metadata's
#      existence is what makes an entry hittable, so a half-written entry is a
#      miss rather than a lie.
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

CACHE_DIR="${FACET_SUITE_CACHE_DIR:-artifacts/suite_cache}"
# Entries are keyed by fingerprint so two agents on two tree states never
# contend for one filename. Set once the fingerprint is known.
TRANSCRIPT=""
META=""
set_entry() {
	TRANSCRIPT="$CACHE_DIR/$1.txt"
	META="$CACHE_DIR/$1.meta"
}

# The tree the suite actually reads. examples/ is in here because the example
# drift and reference-app specs require those modules; vendor/ because the
# suite links against it. tools/ is deliberately NOT here — editing a gate
# script cannot change a spec's outcome.
suite_fingerprint() {
	{
		# 2>/dev/null on the HASH, not just the find: a sibling agent's temp file
		# can be listed by `find` and gone by the time shasum opens it
		# (`shasum: tests/_lpvfy.luau: No such file or directory`, measured
		# 2026-08-16 with four agents in one tree). That is noisy but SAFE — a
		# file that vanished mid-walk simply is not hashed, the fingerprint
		# differs from the settled one, and the cache reports a MISS and re-runs.
		# It degrades to slow, never to a wrong answer, which is the direction
		# this has to fail in.
		find src tests examples vendor -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 shasum -a 256 2>/dev/null
		shasum -a 256 run-tests.sh rokit.toml 2>/dev/null
		lune --version 2>&1
	} | shasum -a 256 | cut -d' ' -f1
}

meta_get() {
	[ -f "$META" ] || return 1
	sed -n "s/^$1=//p" "$META" | head -1
}

cache_status() {
	set_entry "$1"
	# The metadata is written LAST, so its presence means the transcript beside
	# it is complete. A half-written entry is a miss, never a lie.
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
# set_entry in the PARENT shell. cache_status also calls it, but it runs inside
# `$( )` — a subshell — so the paths it sets there are discarded on the way out.
set_entry "$fingerprint"
cached=0
if [ "$(cache_status "$fingerprint")" = "hit" ]; then
	plain="$(cat "$TRANSCRIPT")"
	code="$(meta_get exit_code)"
	cached=1
else
	# ONE SUITE RUN PER TREE STATE, ACROSS BOTH SYSTEMS (D7, 2026-08-30).
	# tools/verify.sh runs the suite as a producer and records its transcript
	# beside the structured result. During the parity period both paths are
	# live — gate rows still in the old manifest come through
	# tools/suite_transcript.sh, the graph comes through the result store — and
	# without this seam one tree state costs two 260-second runs.
	#
	# THE STORE DOES THE JUDGING, NOT THIS FILE. The helper prints a path only
	# for a stored result whose identity matches this source and which passed
	# every refusal in tools/lune/verify/results.luau (stale, incomplete,
	# failed, edited, wrong toolchain, wrong class, fast tier, truncated,
	# partial). What it hands back is then re-derived below exactly like any
	# other transcript, so the four guards in this file's header still apply to
	# it — including the fast-tier bash match.
	verified=""
	verified="$(lune run tools/lune/verify/suite_transcript_path 2>/dev/null)"
	if [ -n "$verified" ] && [ -f "$verified" ]; then
		plain="$(cat "$verified")"
		code=0
	else
		out="$(./run-tests.sh 2>&1)"
		code=$?
		# Strip ANSI color codes before parsing.
		plain="$(printf '%s' "$out" | sed $'s/\x1b\\[[0-9;]*m//g')"
	fi
fi
case "$code" in
	'' | *[!0-9]*) code=1 ;;
esac

passed="$(printf '%s' "$plain" | grep -Eo '^[0-9]+ passed' | grep -Eo '^[0-9]+' | tail -1)"
failed="$(printf '%s' "$plain" | grep -Eo '^[0-9]+ failed' | grep -Eo '^[0-9]+' | tail -1)"

if [ "$cached" -eq 0 ]; then
	# Transcript first, metadata last, each by atomic rename into the same
	# directory. Nothing live is ever removed, so a concurrent reader on this
	# same fingerprint sees either the previous complete entry or the new one.
	# Temp names carry $$ so two writers cannot collide on the staging file.
	mkdir -p "$CACHE_DIR"
	printf '%s\n' "$plain" >"$CACHE_DIR/.$$.transcript" && mv -f "$CACHE_DIR/.$$.transcript" "$TRANSCRIPT"
	{
		echo "fingerprint=$fingerprint"
		echo "exit_code=$code"
		echo "passed=${passed:-}"
		echo "failed=${failed:-}"
	} >"$CACHE_DIR/.$$.meta" && mv -f "$CACHE_DIR/.$$.meta" "$META"
	# Bounded, and deliberately not "keep the newest N": another agent may be
	# reading an entry for a tree state this one knows nothing about. A day is
	# far longer than any sweep.
	find "$CACHE_DIR" -maxdepth 1 -type f -mtime +1 -delete 2>/dev/null || true
fi

status=FAIL
reason=""
if [[ "$plain" == *FACET-FAST-TIER* ]]; then
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
		# Print the entry's path: the caller needs it, and recomputing the
		# fingerprint to re-derive it would both cost a second hash and open a
		# window in which the answer changed between the two calls.
		echo "$TRANSCRIPT"
		exit 0
	fi
	echo "tools/test.sh --ensure-cache: refusing this transcript - $reason" >&2
	exit 1
fi

cat >artifacts/test.json <<EOF
{
  "schema": "facet-test/1",
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
