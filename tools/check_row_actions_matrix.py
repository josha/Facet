#!/usr/bin/env python3
"""Gate check for artifacts/row-actions/device-matrix.md — the row-actions
five-view functional matrix + perf-budget evidence (Task 11/11b).

WHY THIS EXISTS (Task 12, director ruling 2026-08-11). The plan's own sketched
check was `test -f "$f" && ! grep -q "FAIL" "$f" && ! grep -qE "PENDING" "$f"`.
That is the exact can't-ever-pass-honestly shape the gate-integrity sweep
(2026-07-29) exists to catch from the OTHER direction: this artifact
legitimately contains the literal word "FAIL" in its own perf-budget verdict
prose ("Budget: <=5% added cost -- MISSED, on every drive shape", "still
FAIL") because Task 11/11b measured the wrapped-row cost honestly and it
misses the ORIGINAL <=5%/<=4-instance budget from the plan's Global
Constraints. A bare `! grep -q FAIL` would never pass this file as committed,
which means either the honest numbers get scrubbed from the artifact (lying
by omission) or the gate is permanently red — neither is acceptable.

The director's first fix (2026-08-11) re-baselined the perf gate, as an
INTERIM measure, to the numbers Task 11b actually measured and shipped
(steady scroll +57%, fling +81%, 5 wrapper instances/row -- mount-dominated,
see the "Task 11b" section of the artifact and
.superpowers/sdd/row-actions-implementation/task-11b-report.md) at a time
when every consumer went through the manual per-row `newRowActions` wrap
those numbers measured, with the VirtualList-gesture-hook mission chartered
as the closure path (docs/plans/row-actions-perf-mission.md).

BUDGET RESTORED (2026-08-12, row-actions-hosted-mode-plan Task 8). That
closure mission landed: `VirtualList`/`Table` now host `rowActions` directly
(`spec.rowActions`), and a closed row mounts no per-row `Hit` grip or
gesture engine -- the cost the 2026-08-10/08-11 numbers were dominated by.
Task 7's de-biased (ABBA-interleaved, >=5-run-mean) re-measurement of that
hosted integration found the real cost is small enough to sit back inside
the plan's *original* <=5% budget with real headroom (hosted steady -0.28%
mean, fling +2.83% mean -- see the artifact's "Current numbers" table and
.superpowers/sdd/row-actions-hosted-mode-plan/task-7-report.md Sec 0), so
the ceilings below are restored to that original shape on the timing side.

The instance ceiling is tightened to <=1, NOT restored to the plan's
original <=4: the hosted design's own closed-row instance cost is
integer-deterministic at +0.08 nodes/windowed-row (one shared overlay
instance for the whole list, not one per row), so <=4 would leave a 12x-wide
blind spot for any future regression that starts re-materializing per-row
wrapper instances. Two independent review rounds on this task both called
for <=1 as the sharp regression detector this deterministic a number
deserves.

So this check does three things a blanket grep cannot:

  1. FUNCTIONAL MATRIX: the "## The matrix" section (the five-view
     open/close/commit/table/diagnostics table) must exist and contain no
     "FAIL" cell and at least 20 "**PASS**" markers (5 views x 4 columns) --
     a REAL functional regression in this section still reddens the gate.
  2. MEASURED PERF NUMBERS: the artifact's "Current numbers" table must
     exist for steady scroll, fling, and wrapper instance count -- if the
     section is edited away, the check fails rather than silently passing
     on an absent measurement.
  3. RESTORED CEILINGS: those three measured numbers must not exceed the
     ceilings below. The artifact's OWN historical "still FAIL"/superseded
     prose (against the 2026-08-10/08-11 numbers, kept for the record) is
     never read by this script -- only the "Current numbers" table's own
     cells are -- so a documented rider row or a candid superseded-history
     section can never fail this check; only a future regression ABOVE the
     pinned ceiling can.

Usage: python3 tools/check_row_actions_matrix.py [path]
Exit 0 = clean; non-zero with a reason otherwise.
"""

import re
import sys

MATRIX = "artifacts/row-actions/device-matrix.md"

# row-actions-hosted-mode-plan Task 8 (2026-08-12): budget restored to the
# plan's original <=5%/<=5% timing shape now that the hosted integration
# (Tasks 1-7) measures back inside it (see the docstring above and
# .superpowers/sdd/row-actions-hosted-mode-plan/task-7-report.md Sec 0). The
# instance ceiling is tightened past the plan's original <=4 to <=1 -- the
# census is integer-deterministic at +0.08, so <=1 is the sharp regression
# detector two independent review rounds specified, not a re-litigation of
# the timing budget's own margin.
STEADY_CEILING_PCT = 5.0
FLING_CEILING_PCT = 5.0
INSTANCE_CEILING = 1.0

FUNCTIONAL_SECTION_RE = re.compile(r"## The matrix\n(.*?)\n### ", re.DOTALL)
MIN_PASS_MARKERS = 20  # 5 views x 4 result columns

# Signed percentage: the restored-budget hosted mean is NEGATIVE (steady
# -0.28%), so the sign is optional, not a required literal '+' -- a bare
# '(-0.28%)' must parse to -0.28, not fail to match at all.
STEADY_RE = re.compile(r"^\|\s*Steady scroll[^\n|]*\|[^|\n]*\|[^|\n]*\|\s*[\d.]+ms \(([+-]?[\d.]+)%\)", re.MULTILINE)
FLING_RE = re.compile(r"^\|\s*Fling[^\n|]*\|[^|\n]*\|[^|\n]*\|\s*[\d.]+ms \(([+-]?[\d.]+)%\)", re.MULTILINE)
INSTANCES_RE = re.compile(r"^\|\s*Wrapper instances/closed row\s*\|[^|\n]*\|[^|\n]*\|\s*([\d.]+)", re.MULTILINE)


def main(argv):
    path = argv[1] if len(argv) > 1 else MATRIX
    try:
        text = open(path).read()
    except FileNotFoundError:
        print(f"check_row_actions_matrix: missing artifact {path}", file=sys.stderr)
        return 1

    problems = []

    # ---- 1. functional five-view matrix -----------------------------------
    section = FUNCTIONAL_SECTION_RE.search(text)
    if section is None:
        problems.append("'## The matrix' section not found (or its closing '### ' heading moved) -- "
                         "the five-view functional table is the row-actions matrix's whole subject")
    else:
        body = section.group(1)
        if "FAIL" in body:
            problems.append("the functional five-view matrix table contains 'FAIL' -- a real regression "
                             "in open/close/commit/table/diagnostics, not a documented perf rider")
        pass_count = body.count("**PASS**")
        if pass_count < MIN_PASS_MARKERS:
            problems.append(f"functional matrix has only {pass_count} '**PASS**' markers, expected >= "
                             f"{MIN_PASS_MARKERS} (5 views x 4 columns) -- a cell went missing or unmarked")

    # ---- 2/3. measured perf numbers vs. the restored ceilings -------------
    def check_metric(name, pattern, ceiling, unit):
        m = pattern.search(text)
        if m is None:
            problems.append(f"measured '{name}' row (the 'Current numbers' hosted-mean column) not found -- "
                             "the perf-budget evidence this gate exists to pin is missing")
            return
        value = float(m.group(1))
        if value > ceiling:
            problems.append(f"'{name}' regressed to {value}{unit}, above the restored ceiling "
                             f"{ceiling}{unit} (row-actions-hosted-mode-plan Task 8, 2026-08-12) -- a real perf regression")

    check_metric("Steady scroll", STEADY_RE, STEADY_CEILING_PCT, "%")
    check_metric("Fling", FLING_RE, FLING_CEILING_PCT, "%")
    check_metric("Wrapper instances/closed row", INSTANCES_RE, INSTANCE_CEILING, " instances")

    if problems:
        print(f"check_row_actions_matrix: {len(problems)} problem(s) in {path}\n", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    print(f"check_row_actions_matrix: {path} clean (functional matrix intact, perf numbers within "
          f"restored ceilings: steady <= {STEADY_CEILING_PCT}%, fling <= {FLING_CEILING_PCT}%, "
          f"instances <= {INSTANCE_CEILING})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
