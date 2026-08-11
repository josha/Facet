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

The director's fix (2026-08-11): re-baseline the perf gate to the numbers
Task 11b actually measured and shipped (steady scroll +57%, fling +81%, 5
wrapper instances/row -- mount-dominated, see the "Task 11b" section of the
artifact and .superpowers/sdd/row-actions-implementation/task-11b-report.md),
with the VirtualList-gesture-hook mission as the closure path, tracked
separately (docs/plans/row-actions-perf-mission.md).

So this check does three things a blanket grep cannot:

  1. FUNCTIONAL MATRIX: the "## The matrix" section (the five-view
     open/close/commit/table/diagnostics table) must exist and contain no
     "FAIL" cell and at least 20 "**PASS**" markers (5 views x 4 columns) --
     a REAL functional regression in this section still reddens the gate.
  2. MEASURED PERF NUMBERS: the "Task 11b (after, ...)" column of the
     Numbers table must exist for steady scroll, fling, and wrapper
     instance count -- if the section is edited away, the check fails
     rather than silently passing on an absent measurement.
  3. RE-BASELINED CEILINGS: those three measured numbers must not exceed
     the director-ruled ceilings below. The artifact's OWN historical "still
     FAIL" prose (against the ORIGINAL plan ceiling) is never read by this
     script -- only the numeric table cells are -- so a documented rider row
     or a candid "budget missed" sentence can never fail this check; only a
     future regression ABOVE the pinned ceiling can.

Usage: python3 tools/check_row_actions_matrix.py [path]
Exit 0 = clean; non-zero with a reason otherwise.
"""

import re
import sys

MATRIX = "artifacts/row-actions/device-matrix.md"

# Director ruling 2026-08-11: pin the numbers Task 11b actually shipped as
# ceilings. A future regression above these is a real perf regression; the
# gate does NOT re-litigate the plan's original (missed) <=5%/<=4 budget --
# that stays tracked as the follow-up mission, docs/plans/row-actions-perf-mission.md.
STEADY_CEILING_PCT = 57.0
FLING_CEILING_PCT = 81.0
INSTANCE_CEILING = 5.0

FUNCTIONAL_SECTION_RE = re.compile(r"## The matrix\n(.*?)\n### ", re.DOTALL)
MIN_PASS_MARKERS = 20  # 5 views x 4 result columns

STEADY_RE = re.compile(r"^\|\s*Steady scroll[^\n|]*\|[^|\n]*\|[^|\n]*\|\s*[\d.]+ms \(\+([\d.]+)%\)", re.MULTILINE)
FLING_RE = re.compile(r"^\|\s*Fling[^\n|]*\|[^|\n]*\|[^|\n]*\|\s*[\d.]+ms \(\+([\d.]+)%\)", re.MULTILINE)
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

    # ---- 2/3. measured perf numbers vs. the re-baselined ceilings ---------
    def check_metric(name, pattern, ceiling, unit):
        m = pattern.search(text)
        if m is None:
            problems.append(f"measured '{name}' row (Task 11b 'after' column) not found -- "
                             "the perf-budget evidence this gate exists to pin is missing")
            return
        value = float(m.group(1))
        if value > ceiling:
            problems.append(f"'{name}' regressed to {value}{unit}, above the re-baselined ceiling "
                             f"{ceiling}{unit} (director ruling 2026-08-11) -- a real perf regression")

    check_metric("Steady scroll", STEADY_RE, STEADY_CEILING_PCT, "%")
    check_metric("Fling", FLING_RE, FLING_CEILING_PCT, "%")
    check_metric("Wrapper instances/closed row", INSTANCES_RE, INSTANCE_CEILING, " instances")

    if problems:
        print(f"check_row_actions_matrix: {len(problems)} problem(s) in {path}\n", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    print(f"check_row_actions_matrix: {path} clean (functional matrix intact, perf numbers within "
          f"re-baselined ceilings: steady <= {STEADY_CEILING_PCT}%, fling <= {FLING_CEILING_PCT}%, "
          f"instances <= {INSTANCE_CEILING})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
