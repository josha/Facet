#!/usr/bin/env python3
"""Refuse a gate check whose suite grep is unanchored — or, with --transcript, one that no longer MATCHES.

Run: tools/check_manifest_integrity.py               anchoring only, no suite needed
     tools/check_manifest_integrity.py --transcript  also prove every pattern still matches

═══════════════════════════════════════════════════════════════════════════════
PART 1 — ANCHORING (gate-integrity sweep 2026-07-29, defect D-1)

`tests/lib/testkit.luau` prints the case name on BOTH outcomes:

    ✓ modal traps navigation with wrap and restores previous focus on pop
    ✗ modal traps navigation with wrap and restores previous focus on pop

So `grep -q "<case name>"` proves the case is REGISTERED, not that it PASSES. Whether that
matters depends entirely on shell form:

  FORM A   out="$(tools/suite_transcript.sh)" && echo "$out" | grep -q "X"
           SAFE. The command-substitution assignment carries the helper's exit code, so
           `&&` short-circuits and the check reddens on any suite failure.

  FORM B   tools/suite_transcript.sh 2>&1 | grep -q 'X'
           BLIND. A pipeline's exit status is the LAST command's — grep's. The suite's
           failure is masked, and the check stays green while the behaviour it names is
           broken. Twenty-six checks shipped in this shape; `phase-0-foundation`'s
           modal-focus-spike was proven green against a deliberately broken focus graph.

The fix in both forms is to anchor the pattern to the pass marker (`✓.*<name>`), which is
what this script enforces so the class cannot come back. Anchoring also refuses a grep
aimed at a describe-BLOCK header rather than a case name — headers print without a marker,
and five such checks (including one greping the bare word `examples`) were found unable to
fail at all.

═══════════════════════════════════════════════════════════════════════════════
PART 2 — MATCHING (D0.2, 2026-08-16)

Director: *"Nothing verifies our test-greps still match anything — only that they're
correctly anchored. Two consecutive stages have now found a rename by hand."*

Anchoring is a SYNTACTIC property. Rename a spec case and its grep stays perfectly
anchored and matches nothing; the gate does redden, but only when someone runs that gate.
Hence: found by hand, twice. `--transcript` closes it by running every pattern against a
real green transcript — free now that `tools/suite_transcript.sh` keeps exactly one.

FOUR TRAPS, ALL HIT WHILE MEASURING THIS. They are not hypothetical:

 1. `grep`, NEVER `grep -E`. The manifest is BRE. Under ERE a pattern like `traverse(+1)`
    is a different expression or a syntax error, and grep's exit 2 reads as "no match".
    This alone inflated the first count from 13 to 95.
 2. Route each pattern to the transcript ITS OWN CAPTURE came from, positionally. A check
    may capture `$out` from the Facet suite and THEN `cd` into Rascal Rally for a later
    assertion; the mention of RascalRally anywhere in the run string is not the test. The
    capture belongs to Rascal Rally only when a `cd .../RascalRally/code` precedes the
    `out=` assignment and has not been closed by a subshell `)`. Getting this wrong
    reported 15 false positives in one check.
 3. A NEGATED grep (`-v`, `-vE`) asserts that nothing matches. Zero matches is its whole
    point, so it is excluded from the report rather than counted as a stale pattern.
 4. FINDING NOTHING IS A FAILURE, NOT A PASS. When the manifest moved off
    `./run-tests.sh`, this script's own invocation filter stopped recognising any suite
    grep and printed "0 suite greps, all anchored" — green, and proving nothing. A floor
    on the discovered count is the durable fix; see MIN_EXPECTED_GREPS.

═══════════════════════════════════════════════════════════════════════════════
PART 3 — THE GRAPH (distribution-readiness D7/D8, 2026-08-30)

`tools/lune/verify/graph.json` is generated from this same manifest and is what
`tools/verify.sh` actually evaluates. Parts 1 and 2 keep the SOURCE honest; this part
keeps the GENERATED ARTEFACT honest, and it is a different set of ways to be wrong:

  * a `resultIds` entry that no longer exists in the suite — the renamed-case defect
    that Part 2 catches for greps, caught here for ids. A stale id is a FAILURE, never
    a silently satisfied lookup;
  * a row naming a producer the graph does not declare;
  * a row pinning an evidence file that is gone AND is tracked by git (a regenerable,
    git-ignored artifact under artifacts/ is produced by a run, so its absence before
    that run is not a defect and is reported as a note);
  * a row that still reaches the suite through `tools/prior_gates.sh` (retired) or by
    INVOKING `tools/suite_transcript.sh` / `tools/test.sh` (`--status`, which asks the
    cache a question and starts nothing, is allowed and is asserted by two rows).

`--selftest` plants each of those four defects into a copy of the graph and requires this
script to reject every one. A check that has not been seen to fail is decoration.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

MANIFEST = "tools/lune/gate_manifest.luau"
GRAPH = "tools/lune/verify/graph.json"
SUITE_RESULTS_DIR = "artifacts/verify/results/suite"

# THE FLOOR (trap 4). If a future refactor renames the invocation again, the discovery
# regexes below go quiet and this script would otherwise pass over an unchecked manifest.
# It is a floor, not a pin: adding checks is normal, losing them silently is not.
MIN_EXPECTED_GREPS = 900

RR_CD = "cd ../../../games/RascalRally/code"
RR_TRANSCRIPT_CMD = ["tools/suite_transcript.sh"]
RR_ROOT = "../../../games/RascalRally/code"

DUMPER = """
local serde = require("@lune/serde")
local manifest = require("./gate_manifest")
local out = {}
for gate, checks in manifest do
\tfor _, c in checks do
\t\tif c.run ~= nil then
\t\t\ttable.insert(out, { gate = gate, name = c.name, run = c.run })
\t\tend
\tend
end
print(serde.encode("json", out))
"""

# The two shapes that put a suite transcript in front of grep. `./run-tests.sh` stays
# recognised so a check written the old way is still audited rather than skipped.
SUITE_CMD = r"(?:tools/suite_transcript\.sh|\./run-tests\.sh(?:\s+2>&1)?)"
CAPTURE = re.compile(r'(\w+)="\$\(' + SUITE_CMD + r'\)"')
FORM_A = re.compile(r'echo "\$(\w+)" \| grep (-[^\s]+) (["\'])(.*?)\3')
FORM_B = re.compile(SUITE_CMD + r' \| grep (-[^\s]+) (["\'])(.*?)\2')

MARKER = "✓"


def load_checks():
    """Read run strings from the PARSED manifest, never by regexing the Lua source.

    Lua escape handling differs between quote styles (a `\\"` means different things in
    '...' and "..."), and hand-unescaping is exactly how this sweep first drew a wrong
    conclusion. Let Luau do it.
    """
    path = "tools/lune/_check_manifest_integrity_dump.luau"
    with open(path, "w") as fh:
        fh.write(DUMPER)
    try:
        proc = subprocess.run(
            ["lune", "run", "tools/lune/_check_manifest_integrity_dump"],
            capture_output=True,
            text=True,
        )
    finally:
        os.remove(path)

    if proc.returncode != 0:
        print(f"check_manifest_integrity: manifest did not load\n{proc.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(proc.stdout)


def paren_depth(text, index):
    """Subshell nesting depth just before `index`. `$(` opens and its `)` closes, so
    counting both characters keeps command substitutions balanced and leaves only real
    `( ... )` groups affecting the depth."""
    depth = 0
    for ch in text[:index]:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
    return depth


def repo_at(run, index):
    """Which repo's suite is `index` running against (trap 2).

    Rascal Rally only when a `cd` into it precedes this point AND that `cd` has not been
    closed by a subshell `)` — `(cd .../RascalRally/code && …) && tools/bench.sh` runs its
    tail back in Facet.
    """
    here = paren_depth(run, index)
    start = 0
    result = "facet"
    while True:
        found = run.find(RR_CD, start)
        if found == -1 or found >= index:
            break
        if paren_depth(run, found) <= here:
            result = "rascalrally"
        start = found + 1
    return result


def suite_greps(run):
    """Every (flags, pattern, repo) this run string greps a suite transcript with."""
    captures = [(m.start(), m.group(1), repo_at(run, m.start())) for m in CAPTURE.finditer(run)]
    found = []

    for m in FORM_A.finditer(run):
        var = m.group(1)
        # The capture the pattern belongs to is the most recent assignment of THAT
        # variable before this grep. A `$out` fed by `lune run check_x` is not a suite
        # grep and must not be audited as one.
        owner = None
        for pos, name, repo in captures:
            if name == var and pos < m.start():
                owner = repo
        if owner is not None:
            found.append((m.group(2), m.group(4), owner))

    for m in FORM_B.finditer(run):
        found.append((m.group(1), m.group(3), repo_at(run, m.start())))

    return found


def read_transcript(cwd):
    proc = subprocess.run(RR_TRANSCRIPT_CMD, cwd=cwd, capture_output=True, text=True)
    if proc.returncode != 0 or not proc.stdout.strip():
        return None, (proc.stderr.strip() or "helper printed nothing")
    return proc.stdout, None



# ═══════════════════════════════════════════════════════════════════════════════
# PART 3 — the generated verification graph


# A command POSITION holding one of the retired suite front doors. Anything else —
# `test -x tools/suite_transcript.sh`, `grep … tools/test.sh` — is a file assertion
# about the tool itself and is fine.
FRONT_DOOR = re.compile(
    r"(?:^|[;&|(]|&&|\|\||\$\()\s*(?:\.\./)*(?:\./)?tools/(suite_transcript|test)\.sh(\s+--status)?"
)


def latest_suite_results():
    """The newest stored full-tier suite result, or None. Returns (cases, path)."""
    if not os.path.isdir(SUITE_RESULTS_DIR):
        return None, None
    candidates = [
        os.path.join(SUITE_RESULTS_DIR, f)
        for f in os.listdir(SUITE_RESULTS_DIR)
        if f.endswith(".json")
    ]
    if not candidates:
        return None, None
    newest = max(candidates, key=os.path.getmtime)
    try:
        with open(newest) as fh:
            record = json.load(fh)
        suite = record["payload"]["results"]
        if suite.get("tier") != "full":
            return None, newest
        return {c["id"] for c in suite["cases"]}, newest
    except (KeyError, ValueError, OSError):
        return None, newest


def is_regenerable(path):
    """Is this evidence path something a run produces, rather than a checked-in file?

    The line is git-ignore, and it is the right line: `artifacts/bench.json` is
    ignored precisely because `tools/bench.sh` writes it, so its absence before a
    run is normal. A TRACKED evidence file that is gone is a broken row.
    """
    return subprocess.run(["git", "check-ignore", "-q", path], capture_output=True).returncode == 0


def graph_problems(graph, case_ids, regenerable=None):
    """Every way the generated graph can be internally wrong."""
    regenerable = regenerable or is_regenerable
    problems = []
    notes = []
    declared = {p["id"] for p in graph.get("producers", [])}
    stale_ids = 0
    for row in graph.get("rows", []):
        check = row.get("check") or {}
        rid = row["id"]
        for pid in check.get("producers", []):
            if pid not in declared:
                problems.append(f"[{rid}] names producer {pid!r}, which the graph does not declare")
        for pin in check.get("stdoutPins", []):
            if pin["producer"] not in declared:
                problems.append(
                    f"[{rid}] pins the output of producer {pin['producer']!r}, which the graph does not declare"
                )
        if case_ids is not None:
            for cid in check.get("resultIds", []):
                if cid not in case_ids:
                    stale_ids += 1
                    problems.append(
                        f"[{rid}] cites case id {cid!r}, which no longer exists in the suite\n"
                        "      re-point the manifest row and regenerate with "
                        "tools/lune/verify/convert_manifest.py"
                    )
        evidence = row.get("evidence")
        if evidence and row.get("class") not in ("declared", "retired") and not os.path.exists(evidence):
            if regenerable(evidence):
                notes.append(f"[{rid}] evidence {evidence!r} is absent (git-ignored: a run regenerates it)")
            else:
                problems.append(
                    f"[{rid}] pins evidence {evidence!r}, which is checked in and is GONE"
                )
        shell = check.get("shell")
        if shell:
            if "prior_gates.sh" in shell:
                problems.append(f"[{rid}] still references tools/prior_gates.sh, which is retired")
            for m in FRONT_DOOR.finditer(shell):
                if not m.group(2):
                    problems.append(
                        f"[{rid}] INVOKES tools/{m.group(1)}.sh — the graph reaches the suite through its "
                        "producer, not the old front door"
                    )
    return problems, notes, stale_ids


def run_graph_check(graph_path=GRAPH, quiet=False):
    if not os.path.exists(graph_path):
        print(
            f"check_manifest_integrity: {graph_path} is missing — regenerate it with "
            "tools/lune/verify/convert_manifest.py",
            file=sys.stderr,
        )
        return 1
    with open(graph_path) as fh:
        graph = json.load(fh)
    if graph.get("schema") != "facet-verify-graph/1":
        print(f"check_manifest_integrity: unexpected graph schema {graph.get('schema')!r}", file=sys.stderr)
        return 1
    case_ids, results_path = latest_suite_results()
    problems, notes, stale = graph_problems(graph, case_ids)
    if problems:
        if not quiet:
            print(f"check_manifest_integrity: {len(problems)} graph problem(s)\n", file=sys.stderr)
            for p in problems:
                print(f"  {p}", file=sys.stderr)
        return 1
    if not quiet:
        rows = len(graph["rows"])
        ids = sum(len((r.get("check") or {}).get("resultIds", [])) for r in graph["rows"])
        if case_ids is None:
            where = "no stored full-tier suite result yet, so case ids were NOT checked here (the coordinator checks them on every run)"
        else:
            where = f"{ids} case-id references all exist in {results_path}"
        print(
            f"check_manifest_integrity: graph OK — {rows} rows, {len(graph['producers'])} producers, {where}"
        )
        for n in notes:
            print(f"  note: {n}")
    return 0


def graph_selftest():
    """Plant each class of graph defect and require this script to reject it."""
    with open(GRAPH) as fh:
        graph = json.load(fh)
    case_ids, _ = latest_suite_results()
    if case_ids is None:
        # Synthesise one, so the selftest never depends on a run having happened.
        case_ids = set()
        for row in graph["rows"]:
            for cid in (row.get("check") or {}).get("resultIds", []):
                case_ids.add(cid)
    ok = True

    # The planted path stands in for a checked-in evidence file that was deleted;
    # `git check-ignore` cannot say that about a path that never existed, so the
    # seam is passed in rather than faked on disk.
    def seam(p):
        return not p.endswith(".this-was-deleted") and is_regenerable(p)

    baseline, _, _ = graph_problems(graph, case_ids, regenerable=seam)
    baseline_set = set(baseline)

    def expect_caught(label, mutate):
        nonlocal ok
        import copy

        mutated = copy.deepcopy(graph)
        mutate(mutated)
        problems, _, _ = graph_problems(mutated, case_ids, regenerable=seam)
        # ONLY A NEW PROBLEM COUNTS. A graph that is already dirty would
        # otherwise "catch" every plant by reporting the same pre-existing
        # defect, which proves nothing about the plant.
        added = [p for p in problems if p not in baseline_set]
        if added:
            print(f"  ✓ {label} — rejected: {added[0].splitlines()[0][:110]}")
        else:
            print(f"  ✗ {label} — NOT rejected")
            ok = False

    def a_row_with(pred):
        for row in graph["rows"]:
            if pred(row):
                return row["id"]
        raise AssertionError("no row of that shape in the graph")

    target_ids = a_row_with(lambda r: (r.get("check") or {}).get("resultIds"))
    target_prod = a_row_with(lambda r: (r.get("check") or {}).get("producers"))

    def stale_id(g):
        for row in g["rows"]:
            if row["id"] == target_ids:
                row["check"]["resultIds"][0] = "layout::a describe that::an it that was renamed"

    def unknown_producer(g):
        for row in g["rows"]:
            if row["id"] == target_prod:
                row["check"]["producers"][0] = "a-producer-nobody-declared"

    def missing_evidence(g):
        g["rows"].append({
            "id": "selftest::missing-evidence", "phase": "phase-0-foundation",
            "name": "missing-evidence", "requirements": [], "class": "evidence-pin",
            "evidence": "README.md.this-was-deleted", "releaseBlocking": False,
            "note": "", "state": None, "check": {},
        })

    def retired_front_door(g):
        g["rows"].append({
            "id": "selftest::front-door", "phase": "phase-0-foundation", "name": "front-door",
            "requirements": [], "class": "evidence-pin", "releaseBlocking": False, "note": "",
            "state": None, "check": {"shell": 'out="$(tools/suite_transcript.sh)" && test -n "$out"'},
        })

    def replayed_priors(g):
        g["rows"].append({
            "id": "selftest::replay", "phase": "phase-0-foundation", "name": "replay",
            "requirements": [], "class": "evidence-pin", "releaseBlocking": False, "note": "",
            "state": None, "check": {"shell": 'tools/prior_gates.sh /tmp/x phase-1-minimal-screen'},
        })

    print("check_manifest_integrity --selftest: planting graph defects")
    expect_caught("a renamed case id", stale_id)
    expect_caught("a row naming an undeclared producer", unknown_producer)
    expect_caught("a row pinning a tracked evidence file that is gone", missing_evidence)
    expect_caught("a row invoking the retired suite front door", retired_front_door)
    expect_caught("a row replaying prior gates", replayed_priors)

    # ...and the state of the real graph, reported either way. A dirty baseline no
    # longer invalidates the plants above (each is credited only for a NEW
    # problem), but it is still something the reader must be told.
    if baseline:
        print(f"  ! the real graph carries {len(baseline)} standing problem(s):")
        for p in baseline[:5]:
            print(f"      {p}")
    else:
        print("  ✓ the unmutated graph is clean")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument(
        "--transcript",
        action="store_true",
        help="also prove every pattern still matches a line in a green transcript",
    )
    ap.add_argument(
        "--selftest",
        action="store_true",
        help="plant each class of graph defect and require this script to reject it",
    )
    args = ap.parse_args()

    if args.selftest:
        return graph_selftest()

    problems = []
    unanchored = 0
    direct = 0
    entries = []

    for entry in load_checks():
        # D0.1: a check must grep the shared transcript, not spawn its own suite.
        # Recognised (so it is still audited for anchoring and matching) and then
        # refused, because one of these in a 465-check manifest costs 83 s a sweep
        # and re-opens the four hours this stage closed.
        if re.search(r"\./run-tests\.sh", entry["run"]):
            direct += 1
            problems.append(
                f"[{entry['gate']}] {entry['name']}: runs `./run-tests.sh` directly\n"
                "      use tools/suite_transcript.sh — it serves one cached transcript per tree "
                "state and\n"
                "      still exits non-zero (printing nothing) on a red, failing, truncated or "
                "fast-tier suite"
            )
        for flags, pattern, repo in suite_greps(entry["run"]):
            entries.append((entry["gate"], entry["name"], flags, pattern, repo))
            if MARKER not in pattern:
                unanchored += 1
                problems.append(
                    f"[{entry['gate']}] {entry['name']}: suite grep is not anchored to the "
                    f"pass marker — {pattern[:70]!r}\n"
                    f"      a failing case still prints its name, so this matches either way; "
                    f'use "{MARKER}.*<case name>"'
                )

    checked = len(entries)

    if checked < MIN_EXPECTED_GREPS:
        print(
            f"check_manifest_integrity: found only {checked} suite greps, expected at least "
            f"{MIN_EXPECTED_GREPS}.\n"
            "      The discovery regexes have gone blind — almost certainly the manifest's "
            "suite invocation was\n"
            "      renamed again. A green run over an unaudited manifest is the exact defect "
            "this script exists to prevent.",
            file=sys.stderr,
        )
        return 1

    if problems:
        print(
            f"check_manifest_integrity: {unanchored} unanchored suite grep(s), "
            f"{direct} direct suite invocation(s)\n",
            file=sys.stderr,
        )
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1

    if not args.transcript:
        print(f"check_manifest_integrity: {checked} suite greps, all anchored to the pass marker")
        return run_graph_check()

    transcripts = {}
    for repo, cwd in (("facet", "."), ("rascalrally", RR_ROOT)):
        text, err = read_transcript(cwd)
        if text is None:
            print(
                f"check_manifest_integrity: cannot read the {repo} transcript — {err}\n"
                "      --transcript needs BOTH suites green; run them and try again.",
                file=sys.stderr,
            )
            return 1
        transcripts[repo] = text

    files = {}
    tmpdir = tempfile.mkdtemp(prefix="manifest-integrity-")
    for repo, text in transcripts.items():
        path = os.path.join(tmpdir, f"{repo}.txt")
        with open(path, "w") as fh:
            fh.write(text)
        files[repo] = path

    stale = []
    negated = 0
    matched = 0
    for gate, name, flags, pattern, repo in entries:
        # Trap 3: a negated grep asserts the ABSENCE of a line. Zero matches is correct.
        if "v" in flags.lstrip("-"):
            negated += 1
            continue
        # Trap 1: BRE. `grep`, never `grep -E`. -F is honoured because the manifest uses it.
        cmd = ["grep", "-q"]
        if "F" in flags.lstrip("-"):
            cmd.append("-F")
        cmd += ["-e", pattern, files[repo]]
        if subprocess.run(cmd, capture_output=True).returncode == 0:
            matched += 1
        else:
            stale.append((gate, name, repo, pattern))

    if stale:
        print(
            f"check_manifest_integrity: {len(stale)} pattern(s) match ZERO lines in a fully "
            "green run\n"
            "      Each one is a check that can no longer prove its case passed. Re-point a "
            "rename, or delete\n"
            "      the pattern if the case is genuinely gone.\n",
            file=sys.stderr,
        )
        for gate, name, repo, pattern in stale:
            print(f"  [{gate}] {name} ({repo})\n      {pattern!r}", file=sys.stderr)
        return 1

    by_repo = {}
    for _, _, _, _, repo in entries:
        by_repo[repo] = by_repo.get(repo, 0) + 1

    os.makedirs("artifacts/navigation-and-menus", exist_ok=True)
    with open("artifacts/navigation-and-menus/grep-match-check.md", "w") as fh:
        fh.write(
            "# D0.2 — every manifest suite grep replayed against a live green transcript\n\n"
            "Produced by `tools/check_manifest_integrity.py --transcript`. Anchoring is a\n"
            "syntactic property; this is the semantic one. A renamed spec case leaves its grep\n"
            "perfectly anchored and matching nothing, which is how two consecutive stages found\n"
            "a rename by hand instead of in the commit that caused it.\n\n"
            f"- suite greps discovered: **{checked}**"
            f" ({', '.join(f'{k} {v}' for k, v in sorted(by_repo.items()))})\n"
            f"- matched a line in a green transcript: **{matched}**\n"
            f"- negated (`grep -v`), not match-checked: **{negated}**\n"
            f"- matching ZERO lines: **0**\n\n"
            "Patterns are routed to the transcript their own capture came from, positionally —\n"
            "a check may capture `$out` from the Facet suite and only then `cd` into Rascal\n"
            "Rally. Mis-routing all 65 Rascal Rally patterns to the Facet transcript reports 63\n"
            "false positives, which is the measurement error the round's brief itself made.\n"
        )

    print(
        f"check_manifest_integrity: {checked} suite greps, all anchored to the pass marker; "
        f"{matched} matched a green transcript ({negated} negated, not match-checked)"
    )
    return run_graph_check()


if __name__ == "__main__":
    sys.exit(main())
