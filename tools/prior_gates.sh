#!/usr/bin/env bash
# Re-run every gate that precedes a given stage and write the PASS/FAIL roll-up
# the `prior-gates-unregressed` checks compare against.
#
# WHY THIS EXISTS (verifier PG-2, Step 5.5): the roll-up used to be produced by
# hand and then compared to a stored baseline by the gate — so the check read two
# checked-in text files, executed nothing against the current tree, and would have
# stayed green through any regression introduced after the file was written. That
# is the same can't-ever-fail shape ledger C-08 removed from
# theme-packages-and-skinning. The comparison is only worth anything if the
# `after` side is regenerated at the source being judged, which is what this does.
#
# Usage: tools/prior_gates.sh <output-path> [stage]
#   stage defaults to code-simplicity-cleanup. The stage's OWN gate is never in
#   the list (that would recurse); the list is every gate before it in
#   phases.json order.
#
# Output format, consumed by the `comm -23` in the gate check:
#   PASS <gate>            for a gate that exits zero
#   FAIL <gate> (exit N)   for one that does not
#   <indented lines>       each non-PASS check the gate printed, for diagnosis
#   DONE                   final line, so a truncated run cannot read as complete
#
# RECURSION GUARD (gate-integrity sweep, 2026-07-29). Seven more gates had a
# `prior-gates-unregressed` that only grepped a stored text file — the same
# can't-ever-fail shape as PG-2, still carrying each stage's headline integrity
# claim. Making them real means each of them calls this script, and this script
# calls tools/gate.sh, which runs THAT gate's own prior-gates check, which calls
# this script again: the work becomes factorial in the number of regenerating
# gates rather than linear, and the terminal gate never finishes.
#
# So this script exports LUAUUI_PRIOR_GATES_NESTED=1 around the gate runs. Every
# `prior-gates-unregressed` check tests that variable first and skips
# regeneration when it is set. The claim survives intact: a gate run STANDALONE
# genuinely re-runs all of its priors, and when it is itself being re-run as
# somebody else's prior, the outer run is already re-running that same list, so
# the nested regeneration would be pure duplicated work. The skip is printed into
# the check's detail string and therefore lands in gate.json — it is recorded,
# not silent.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

out="${1:?usage: tools/prior_gates.sh <output-path> [stage]}"
stage="${2:-code-simplicity-cleanup}"

# Every gate before `stage`, in phases.json order — read from the manifest of
# record rather than hard-coded, so a newly registered gate is covered the day it
# lands instead of the day someone remembers to edit this list.
#
# `mapfile` is bash 4+; macOS ships bash 3.2, so this reads into an array the
# portable way rather than failing at the shebang on the only machine that runs it.
gates=()
while IFS= read -r g; do
	[ -n "$g" ] && gates+=("$g")
done < <(python3 -c "
import json, sys
stage = sys.argv[1]
phases = json.load(open('phases.json'))['phases']
for p in phases:
    if p['gate'] == stage:
        break
    print(p['gate'])
" "$stage")

if [ "${#gates[@]}" -eq 0 ]; then
	echo "prior_gates: no gates precede '$stage' in phases.json" >&2
	exit 2
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# SETTLE BETWEEN GATES. Several prior gates contain timing- and
# resource-sensitive checks (phase-3-pilot's `no-leak-regression` runs
# tools/soak.sh AND tools/bench.sh; others run bench.sh directly), and the bench
# fails a scene at 1.5x its frozen p95. Run back to back for ~11 minutes, the
# machine never settles and those checks measure the PREVIOUS gate's tail:
# phase-3-pilot failed in-batch 2/2 and passed standalone 2/2 while nothing in
# the tree changed. A gate that goes red from its own scheduling is a flaky gate,
# and a flaky gate is just a slower version of one that proves nothing.
#
# This waits for the 1-minute load average to fall below a threshold, capped so a
# genuinely busy machine still finishes. It is a mitigation, not a fix: the real
# fix is headroom in the tight bench scenes (see
# artifacts/code-simplicity-cleanup/perf-after.md).
settle() {
	local waited=0
	while [ "$waited" -lt "${PRIOR_GATES_SETTLE_MAX:-45}" ]; do
		local load
		load="$(uptime | sed 's/.*load averages*: *//' | awk '{print $1}' | tr -d ',')"
		# integer compare without bc: strip the decimal
		local whole="${load%%.*}"
		[ -z "$whole" ] && whole=0
		if [ "$whole" -lt "${PRIOR_GATES_SETTLE_LOAD:-2}" ]; then
			return 0
		fi
		sleep 3
		waited=$((waited + 3))
	done
	echo "prior_gates: load did not settle within ${PRIOR_GATES_SETTLE_MAX:-45}s (load $load) — continuing anyway" >&2
}

# See RECURSION GUARD in the header. Exported here rather than per-invocation so
# it reaches tools/gate.sh -> lune -> the check's own `bash -c`.
export LUAUUI_PRIOR_GATES_NESTED=1

for g in "${gates[@]}"; do
	settle
	log="$(tools/gate.sh "$g" 2>&1)"
	code=$?
	if [ "$code" -eq 0 ]; then
		echo "PASS $g"
	else
		echo "FAIL $g (exit $code)"
	fi
	# carry the non-PASS rows through for diagnosis; they are informational and
	# the gate check only ever compares the `^PASS ` lines
	echo "$log" | grep -E "^  (FAIL|PENDING|SKIP)" | sed 's/^/    /' || true
done >"$tmp"

echo "DONE" >>"$tmp"
mv "$tmp" "$out"
trap - EXIT
echo "prior_gates: ${#gates[@]} gates re-run -> $out" >&2
