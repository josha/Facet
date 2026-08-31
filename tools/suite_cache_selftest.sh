#!/usr/bin/env bash
# Proves the sweep's suite cache CAN FAIL. Run: tools/suite_cache_selftest.sh
#
# WHY THIS EXISTS. D0 replaced 241 suite runs per sweep with one run and 241
# greps of a cached transcript. A cache is exactly the shape that turns a real
# check into one that cannot fail: serve a stale or red transcript and 241 gate
# checks become decoration in a single commit. The gate-integrity sweep's
# standing rule (ledger C-08) is that a check is worthless until
# a mutation has been SEEN to fail it, so every guard below is asserted by
# breaking it on purpose.
#
# It runs the real suite AT MOST ONCE (only if the cache is cold), because the
# fingerprint and validity seams are readable without one:
#   tools/test.sh --fingerprint   the content hash of the tree under test
#   tools/test.sh --status        `hit` or `miss`, decided without running
# Every refusal case builds a synthetic cache in a temp dir pointed at by
# FACET_SUITE_CACHE_DIR, so the real cache is never clobbered.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

pass=0
fail=0
ok() { printf '  \xe2\x9c\x93 %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  \xe2\x9c\x97 %s\n' "$1"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; rm -f tests/.suite_cache_selftest_probe.luau' EXIT

# --- Build a synthetic cache in $1 whose meta claims fingerprint $2 -----------
# Body/exit/pass/fail are the axes each refusal case bends.
synth() {
	local dir="$1" fp="$2" body="$3" code="$4" passed="$5" failed="$6"
	mkdir -p "$dir"
	# Entries are keyed by fingerprint, exactly as tools/test.sh writes them —
	# a synthetic cache that used a different layout would prove nothing about
	# the real one.
	printf '%s\n' "$body" >"$dir/$fp.txt"
	{
		echo "fingerprint=$fp"
		echo "exit_code=$code"
		echo "passed=$passed"
		echo "failed=$failed"
	} >"$dir/$fp.meta"
}

GREEN_BODY=$'\xe2\x9c\x93 a case that passed\n5618 passed\n0 failed'

# --- Did the cache MISS, so nothing was measured? ----------------------------
# A synthetic entry only measures a refusal while it is a cache HIT. If the tree
# moves between keying the entry and reading it, `tools/test.sh` misses, RE-RUNS
# the real (green) suite and serves that — and the guard reads as broken when it
# was never exercised. The window is small but real: `suite_fingerprint`'s own
# header documents it (a sibling agent's temp file, listed by `find` and gone
# before `shasum` opens it), and it reddened
# `a transcript mutated on disk after caching is refused` in the
# navigation-and-menus gate run of 2026-08-21 while the same command passed on
# the next run.
#
# It is exactly detectable AFTER THE FACT rather than guessed at: a miss is the
# only path on which either helper writes, and it writes an entry keyed by the
# CURRENT fingerprint — so a case dir that holds a second entry is a case that
# raced. Re-key and try again; never score the race as a verdict.
served_a_miss() {
	[ "$(find "$1" -maxdepth 1 -name '*.meta' | wc -l)" -gt 1 ]
}
RACE_RETRIES=3

# A transcript is refused unless it is a green, complete, full-tier suite run.
# Each case asserts BOTH halves of the contract: a non-zero exit (so FORM A's
# `&&` chain short-circuits) and EMPTY STDOUT (so a FORM B pipeline, whose exit
# status is grep's and not ours, finds nothing to match and reddens too).
refuses() {
	local label="$1" body="$2" code="$3" passed="$4" failed="$5"
	local dir fp out rc attempt=0
	while :; do
		dir="$TMP/case-$RANDOM-$attempt"
		fp="$(tools/test.sh --fingerprint)"
		synth "$dir" "$fp" "$body" "$code" "$passed" "$failed"
		out="$(FACET_SUITE_CACHE_DIR="$dir" tools/suite_transcript.sh 2>/dev/null)"
		rc=$?
		served_a_miss "$dir" || break
		attempt=$((attempt + 1))
		if [ "$attempt" -ge "$RACE_RETRIES" ]; then
			no "$label — the tree moved under this case $RACE_RETRIES times; nothing was measured"
			return
		fi
	done
	if [ $rc -eq 0 ]; then
		no "$label — served it and exited 0 (FORM A checks would pass over this)"
	elif [ -n "$out" ]; then
		no "$label — exited $rc but printed $(printf '%s' "$out" | wc -l) lines (FORM B pipelines would still match)"
	else
		ok "$label"
	fi
}

echo "suite cache selftest"

# ---------------------------------------------------------------------------
# 1. The fingerprint is CONTENT, not time or session. Any edit under the tree
#    the suite reads busts it; a clock-keyed cache outliving an edit is the
#    "reads two checked-in files and executes nothing" shape PG-2 exists to
#    have removed.
# ---------------------------------------------------------------------------
# Assert the SHAPE, not merely non-emptiness. An unsupported flag makes
# tools/test.sh run the suite and print its own summary line, which is a
# non-empty string — so `[ -n ]` alone is a check that passes before the
# feature exists.
before="$(tools/test.sh --fingerprint)"
if [[ "$before" =~ ^[0-9a-f]{64}$ ]]; then
	ok "--fingerprint prints a content hash"
else
	no "--fingerprint prints a content hash — got ${before:0:70}"
fi

again="$(tools/test.sh --fingerprint)"
if [ "$before" = "$again" ]; then
	ok "fingerprint is stable across calls on an unchanged tree"
else
	no "fingerprint is stable across calls on an unchanged tree ($before vs $again)"
fi

printf -- '-- suite cache selftest probe\nreturn {}\n' >tests/.suite_cache_selftest_probe.luau
dirty="$(tools/test.sh --fingerprint)"
if [ "$dirty" != "$before" ]; then
	ok "a new file under tests/ changes the fingerprint"
else
	no "a new file under tests/ changes the fingerprint — INVALIDATION DOES NOT BITE"
fi

# AGAINST AN ISOLATED CACHE HOLDING THE PREVIOUS TREE STATE, not the real one.
# Asking the real cache "is the probe's fingerprint a miss?" is a check that can
# POISON ITSELF: a concurrent sweep running while the probe exists computes the
# probe's fingerprint, misses, runs the suite and caches an entry under it — and
# from then on this assertion is unpassable until that entry ages out. Observed
# 2026-08-16 by the D5 lane, and it is the same "a test that damages its own
# environment" family as a probe file under src/ that kills a live Rojo.
# Seeding a private cache with the ORIGINAL fingerprint also tests something
# strictly stronger: a POPULATED but stale cache must miss, not merely an empty one.
seeded="$TMP/seeded-previous-state"
synth "$seeded" "$before" "$GREEN_BODY" 0 5618 0
if [ "$(FACET_SUITE_CACHE_DIR="$seeded" tools/test.sh --status)" = "miss" ]; then
	ok "a cache holding the PREVIOUS tree state reports a MISS for the new one"
else
	no "a cache holding the PREVIOUS tree state reports a MISS — a stale transcript would be served"
fi

printf -- '-- suite cache selftest probe CHANGED\nreturn {}\n' >tests/.suite_cache_selftest_probe.luau
edited="$(tools/test.sh --fingerprint)"
if [ "$edited" != "$dirty" ]; then
	ok "editing a file's CONTENT changes the fingerprint"
else
	no "editing a file's CONTENT changes the fingerprint — INVALIDATION DOES NOT BITE"
fi

rm -f tests/.suite_cache_selftest_probe.luau
# Sweep up after ourselves in the REAL cache. A concurrent run that happened to
# fire while the probe existed may have cached an entry keyed to a tree state
# that will never exist again; left behind it is dead weight at best, and it is
# what made this check unpassable once already. Only the two fingerprints this
# script created are touched — never another agent's entry.
for junk in "$dirty" "$edited"; do
	[ -n "$junk" ] && rm -f "${FACET_SUITE_CACHE_DIR:-artifacts/suite_cache}/$junk.txt" \
		"${FACET_SUITE_CACHE_DIR:-artifacts/suite_cache}/$junk.meta"
done
restored="$(tools/test.sh --fingerprint)"
if [ "$restored" = "$before" ]; then
	ok "removing the edit restores the original fingerprint"
else
	no "removing the edit restores the original fingerprint"
fi

# ---------------------------------------------------------------------------
# 2. Hit-or-run, never trust-the-file: a cold cache RUNS the suite. Standalone
#    `tools/gate.sh <one-gate>` outside a sweep must still be honest.
# ---------------------------------------------------------------------------
if [ "$(FACET_SUITE_CACHE_DIR="$TMP/cold" tools/test.sh --status)" = "miss" ]; then
	ok "an absent cache reports MISS (hit-or-run, never trust-the-file)"
else
	no "an absent cache reports MISS"
fi

synth "$TMP/nometa" "$before" "$GREEN_BODY" 0 5618 0
rm -f "$TMP/nometa/$before.meta"
if [ "$(FACET_SUITE_CACHE_DIR="$TMP/nometa" tools/test.sh --status)" = "miss" ]; then
	ok "a transcript with no meta reports MISS"
else
	no "a transcript with no meta reports MISS — an unattributed transcript would be served"
fi

synth "$TMP/stale" "not-the-current-fingerprint" "$GREEN_BODY" 0 5618 0
if [ "$(FACET_SUITE_CACHE_DIR="$TMP/stale" tools/test.sh --status)" = "miss" ]; then
	ok "a foreign fingerprint reports MISS"
else
	no "a foreign fingerprint reports MISS — a cache from another tree would be served"
fi

# ---------------------------------------------------------------------------
# 3. THE EXIT CODE RIDES WITH THE TRANSCRIPT. gate_manifest.luau:25-39 documents
#    FORM A vs FORM B precisely because a pipeline loses run-tests.sh's status.
#    A helper that prints a cached transcript and exits 0 over a RED suite
#    converts every capture-then-grep check into decoration.
# ---------------------------------------------------------------------------
refuses "a RED suite (non-zero exit) is refused" "$GREEN_BODY" 1 5618 0
refuses "a suite with failures is refused" $'\xe2\x9c\x93 a case that passed\n5617 passed\n1 failed' 0 5617 1
refuses "a TRUNCATED transcript (no summary line) is refused" $'\xe2\x9c\x93 a case that passed' 0 "" ""
refuses "a FAST-TIER transcript is refused" $'FACET-FAST-TIER\n\xe2\x9c\x93 a case that passed\n1200 passed\n0 failed' 0 1200 0
refuses "an EMPTY transcript is refused" "" 0 5618 0

# A transcript mutated on disk after caching still has to redden the checks that
# read it. Deleting the summary line is the cheapest real corruption.
mutated_attempt=0
while :; do
	mutated="$TMP/mutated-$mutated_attempt"
	mutated_fp="$(tools/test.sh --fingerprint)"
	synth "$mutated" "$mutated_fp" "$GREEN_BODY" 0 5618 0
	printf '%s\n' $'\xe2\x9c\x93 a case that passed' >"$mutated/$mutated_fp.txt"
	out="$(FACET_SUITE_CACHE_DIR="$mutated" tools/suite_transcript.sh 2>/dev/null)"
	mutated_rc=$?
	served_a_miss "$mutated" || break
	mutated_attempt=$((mutated_attempt + 1))
	if [ "$mutated_attempt" -ge "$RACE_RETRIES" ]; then
		mutated_rc=0
		break
	fi
done
if [ "$mutated_attempt" -ge "$RACE_RETRIES" ]; then
	no "a transcript mutated on disk after caching is refused — the tree moved under this case $RACE_RETRIES times; nothing was measured"
elif [ "$mutated_rc" -ne 0 ] && [ -z "$out" ]; then
	ok "a transcript mutated on disk after caching is refused"
else
	no "a transcript mutated on disk after caching is refused"
fi

# THE RACE GUARD ITSELF, both directions and without paying for a suite run:
# the one-entry dir every refusal case builds must NOT read as a miss (it would
# retry forever), and the second entry a missed, re-run suite leaves behind must.
race="$TMP/race"
synth "$race" "$(tools/test.sh --fingerprint)" "$GREEN_BODY" 0 5618 0
if served_a_miss "$race"; then
	no "the race guard is silent on the dir a refusal case actually built"
else
	ok "the race guard is silent on the dir a refusal case actually built"
fi
synth "$race" "the-fingerprint-a-re-run-would-have-written" "$GREEN_BODY" 0 5618 0
if served_a_miss "$race"; then
	ok "...and it SEES the second entry a missed, re-run suite leaves behind"
else
	no "...and it SEES the second entry a missed, re-run suite leaves behind — a race would be scored as a failed guard"
fi

# ---------------------------------------------------------------------------
# 4. A VALID cache is served verbatim, and serving it does not re-run anything.
# ---------------------------------------------------------------------------
good="$TMP/good"
synth "$good" "$(tools/test.sh --fingerprint)" "$GREEN_BODY" 0 5618 0
out="$(FACET_SUITE_CACHE_DIR="$good" tools/suite_transcript.sh)"
rc=$?
if [ $rc -eq 0 ] && [ "$out" = "$GREEN_BODY" ]; then
	ok "a valid cache is served verbatim and exits 0"
else
	no "a valid cache is served verbatim and exits 0 (rc=$rc)"
fi

# The real cache, end to end: cold or warm, one call must leave it valid, and a
# second call must be a HIT that re-runs nothing. This is the only case that may
# pay for a suite run.
if ! tools/test.sh --ensure-cache; then
	no "tools/test.sh --ensure-cache leaves a valid cache (suite is red?)"
else
	ok "tools/test.sh --ensure-cache leaves a valid cache"
	# --ensure-cache reports the entry it validated; the filename is keyed by
	# fingerprint, so there is no fixed path to stat.
	entry="$(tools/test.sh --ensure-cache)"
	stamp_before="$(shasum -a 256 "$entry" | cut -d' ' -f1)"
	mtime_before="$(stat -f %m "$entry" 2>/dev/null || stat -c %Y "$entry")"
	start=$SECONDS
	tools/suite_transcript.sh >/dev/null
	elapsed=$((SECONDS - start))
	mtime_after="$(stat -f %m "$entry" 2>/dev/null || stat -c %Y "$entry")"
	stamp_after="$(shasum -a 256 "$entry" | cut -d' ' -f1)"
	if [ "$mtime_before" = "$mtime_after" ] && [ "$stamp_before" = "$stamp_after" ]; then
		ok "a warm call re-runs nothing (transcript untouched, ${elapsed}s)"
	else
		no "a warm call re-runs nothing — the transcript was rewritten"
	fi
	# INFORMATIONAL, DELIBERATELY NOT AN ASSERTION. The substantive claim —
	# "the warm call re-ran nothing" — is the mtime+hash check directly above,
	# and that one is load-independent. A wall-clock threshold measures the
	# MACHINE, and with four agents sweeping this tree at once a warm call was
	# measured at 94s against a 20s ceiling. A gate check that reddens under load
	# gets waived, and waiving this one silently disarms the 27 assertions around
	# it — so the number is printed and not judged.
	echo "    (warm call: ${elapsed}s wall — informational; the mtime check above is the claim)"
	if [ "$(tools/test.sh --status)" = "hit" ]; then
		ok "an unchanged tree reports a cache HIT"
	else
		no "an unchanged tree reports a cache HIT"
	fi
fi

# ---------------------------------------------------------------------------
# 5. RASCAL RALLY. Its 67 gate invocations ride the same cache, in its own repo,
#    against its own suite — and its fingerprint must ALSO cover
#    GameStudio/ui/Facet/{src,tests}, because its specs require Facet modules
#    directly (tests/facet_*.spec.luau, tests/hud_zone_model.spec.luau). A
#    Facet edit changes that suite's result, so a cache that misses it would
#    serve a stale green over a broken consumer — the exact lockstep failure
#    root CLAUDE.md exists to prevent.
# ---------------------------------------------------------------------------
RR=../../../games/RascalRally/code

# THE CONSUMER IS EXTERNAL (public-clone honesty round, 2026-08-31). On a public
# clone this directory does not exist, `cd` failed inside every helper below, and
# four cases scored `no` -- reporting the cache guards as BROKEN when they had
# simply not been asked. Skipped by name instead, and skipped is not passed:
# `skip` scores neither, and the summary line says how many.
skip=0
sk() { printf '  \xe2\x8a\x98 %s\n' "$1"; skip=$((skip + 1)); }

if [ ! -d "$RR" ]; then
	sk "RascalRally: the consuming game's checkout is not beside this one — its 8 cases were not run"
else

rr_fp() { (cd "$RR" && tools/suite_transcript.sh --fingerprint); }

rr_before="$(rr_fp)"
if [[ "$rr_before" =~ ^[0-9a-f]{64}$ ]]; then
	ok "RascalRally: --fingerprint prints a content hash"
else
	no "RascalRally: --fingerprint prints a content hash — got ${rr_before:0:70}"
fi

# THE PROBE GOES IN tests/, NEVER src/ — and that is not cosmetic.
# `examples/showcase.project.json` mounts `../src`, so a Rojo server running the
# dev loop watches it. Creating a file there and deleting it moments later RACES
# Rojo's change processor, which canonicalizes the path after the event and
# panics when it has already gone:
#     called `Result::unwrap()` on an `Err` value: Custom { kind: NotFound, …
#     path: ".../src/.suite_cache_selftest_probe.luau" } in change_processor.rs
# It killed a live server once and then survived the same sequence twice on
# retry, which is worse than a reliable failure: this is a gate check, so a
# sweep would kill the dev loop at random. `tests/` is mounted by no project
# file, and it is inside RascalRally's fingerprint for the same reason `src/` is
# — its specs require Facet's tests/lib directly.
printf -- '-- suite cache selftest probe\nreturn {}\n' >tests/.suite_cache_selftest_probe.luau
rr_dirty="$(rr_fp)"
rm -f tests/.suite_cache_selftest_probe.luau
if [ "$rr_dirty" != "$rr_before" ]; then
	ok "RascalRally: a Facet-side edit changes the RascalRally fingerprint"
else
	no "RascalRally: a Facet-side edit changes the RascalRally fingerprint — the consumer would serve a stale green"
fi

# The probe above proves the fingerprint is content-sensitive to a Facet edit.
# It cannot prove WHICH Facet roots are covered, and `src/` is the one that
# matters most — a game suite that missed it would serve a stale green over a
# framework change. Asserted as a declaration, and labelled as one.
rr_roots="$(cd "$RR" && tools/suite_transcript.sh --roots)"
if printf '%s\n' "$rr_roots" | grep -q '/Facet/src$'; then
	ok "RascalRally: Facet src/ is a declared fingerprint root"
else
	no "RascalRally: Facet src/ is a declared fingerprint root — got: $(printf '%s' "$rr_roots" | tr '\n' ' ')"
fi

rr_refuses() {
	local label="$1" body="$2" code="$3"
	local dir fp out rc attempt=0
	# Same race, wider surface: this fingerprint covers GameStudio/ui/Facet too,
	# so an edit in EITHER repo can turn the measurement into a re-run.
	while :; do
		dir="$TMP/rr-$RANDOM-$attempt"
		fp="$(rr_fp)"
		mkdir -p "$dir"
		printf '%s\n' "$body" >"$dir/$fp.txt"
		{ echo "fingerprint=$fp"; echo "exit_code=$code"; } >"$dir/$fp.meta"
		# $dir is absolute (mktemp -d), so it survives the cd into the other repo.
		out="$(cd "$RR" && RR_SUITE_CACHE_DIR="$dir" tools/suite_transcript.sh 2>/dev/null)"
		rc=$?
		served_a_miss "$dir" || break
		attempt=$((attempt + 1))
		if [ "$attempt" -ge "$RACE_RETRIES" ]; then
			no "RascalRally: $label — the tree moved under this case $RACE_RETRIES times; nothing was measured"
			return
		fi
	done
	if [ $rc -eq 0 ] || [ -n "$out" ]; then
		no "RascalRally: $label"
	else
		ok "RascalRally: $label"
	fi
}

rr_refuses "a RED suite is refused" "$GREEN_BODY" 1
rr_refuses "a suite with failures is refused" $'\xe2\x9c\x93 x\n3279 passed\n1 failed' 0
rr_refuses "a TRUNCATED transcript is refused" $'\xe2\x9c\x93 x' 0

if (cd "$RR" && tools/suite_transcript.sh >/dev/null); then
	ok "RascalRally: a valid transcript is served"
	rr_start=$SECONDS
	(cd "$RR" && tools/suite_transcript.sh >/dev/null)
	rr_elapsed=$((SECONDS - rr_start))
	echo "    (RascalRally warm call: ${rr_elapsed}s wall — informational, same reason)"
else
	no "RascalRally: a valid transcript is served (suite red?)"
fi

fi

echo
if [ "$skip" -gt 0 ]; then
	echo "suite cache selftest: $pass passed, $fail failed, $skip group(s) not run (external tree absent)"
else
	echo "suite cache selftest: $pass passed, $fail failed"
fi

mkdir -p artifacts/navigation-and-menus
{
	echo "# D0.1 — the sweep suite cache, with every guard broken on purpose"
	echo
	echo "Produced by \`tools/suite_cache_selftest.sh\`. A cache is exactly the shape that"
	echo "turns a real check into one that cannot fail, so each guard below is asserted by"
	echo "breaking it: the assertions are run against synthetic caches whose transcript is"
	echo "red, failing, truncated, empty, fast-tier, or mutated after the fact."
	echo
	echo "- assertions passed: **$pass**"
	echo "- assertions failed: **$fail**"
	echo
	echo "Every refusal asserts BOTH a non-zero exit (which reddens FORM A's \`&&\` chain)"
	echo "and empty stdout (which reddens a FORM B pipeline, whose exit status is grep's"
	echo "and not the helper's)."
} >artifacts/navigation-and-menus/suite-cache-selftest.md

[ "$fail" -eq 0 ]
