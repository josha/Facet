#!/usr/bin/env python3
"""EQ-6 evidence gate: the large-text header/toolbar overlap is closed, and the
artifact still carries the numbers that prove it.

Kept as a FILE rather than a `python3 -c` one-liner inside the gate manifest
because stylua rewrites single-quoted Luau strings to double-quoted ones and
silently mangles any embedded quote — the trap that has already produced two
green-by-accident gate checks in this repo.
"""
import json
import sys

PATH = "artifacts/example-quality-pass/studio/large-text.json"


def main() -> int:
    try:
        doc = json.load(open(PATH))
    except Exception as exc:  # missing or malformed evidence is a failure
        print(f"EQ-6: cannot read {PATH}: {exc}")
        return 1

    res = doc.get("eq6Resolution")
    if not isinstance(res, dict):
        print("EQ-6: no eq6Resolution block in the evidence")
        return 1
    if res.get("status") != "FIXED":
        print(f"EQ-6: status is {res.get('status')!r}, not 'FIXED'")
        return 1

    # the live A/B: the pre-fix source must have been measured OVERLAPPING, or
    # the 'after' numbers prove nothing
    before = res.get("liveProof", {}).get("before", {})
    if not isinstance(before.get("clearance"), int) or before["clearance"] >= 0:
        print(f"EQ-6: liveProof.before.clearance is {before.get('clearance')!r}; a negative number is what makes the after-numbers evidence")
        return 1

    cells = res.get("theFourReportedCells", {}).get("cells", {})
    if len(cells) != 4:
        print(f"EQ-6: expected the 4 originally-failing cells, found {len(cells)}")
        return 1
    for name, cell in cells.items():
        if not isinstance(cell.get("clearance"), int) or cell["clearance"] <= 0:
            print(f"EQ-6: cell {name} clearance is {cell.get('clearance')!r}, not positive")
            return 1

    print(f"EQ-6: FIXED — before {before['clearance']}px, all 4 reported cells now clear")
    return 0


if __name__ == "__main__":
    sys.exit(main())
