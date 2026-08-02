#!/usr/bin/env python3
"""Assert each fresh-context verifier artifact carries the verdict its gate claims.

WHY THIS EXISTS (gate-integrity sweep 2026-07-29, defect B-8). Seven
`opus-verification` checks asserted only that the report files were ON DISK. A
report whose verdict was REJECT passed the gate exactly as loudly as one that
passed, and the note beside each check asserted "PASS" / "all findings resolved"
on no evidence at all. Three other gates in the same manifest already read the
verdict FIELD, and their notes rightly call that out as the correct shape.

Each argument is `<path>=<expected-prefix>`. The file must parse, must carry a
`verdict` or `status` field, and that field must START WITH the expected string.
A prefix match is used because several of these verdicts are prose
("PASS - every workstream independently reviewed; ...").

The expected value is pinned PER FILE rather than to one global accept-list on
purpose: `expansion-textinput/platform-research.json` legitimately reports
`FINDINGS` — it is pre-implementation research that existed to produce findings,
not a pass/fail gate — and a global list containing FINDINGS would let a real
verifier report unresolved findings and still pass.

Usage: tools/check_verdicts.py <path>=<expected> [<path>=<expected> ...]
"""

import json
import sys

FIELDS = ("verdict", "status")


def check(path, expected):
    try:
        with open(path) as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        return f"missing verifier artifact {path}"
    except json.JSONDecodeError as exc:
        return f"{path} is not valid JSON ({exc})"

    if not isinstance(doc, dict):
        return f"{path} is not an object"

    for field in FIELDS:
        if field in doc:
            value = doc[field]
            if not isinstance(value, str):
                return f"{path} `{field}` is {type(value).__name__}, expected a string"
            if not value.startswith(expected):
                return (
                    f"{path} `{field}` is {value[:80]!r}, "
                    f"expected it to start with {expected!r}"
                )
            return None

    return (
        f"{path} carries neither `verdict` nor `status` — "
        "there is no machine-readable verdict to check"
    )


def main(argv):
    if len(argv) < 2:
        print("usage: tools/check_verdicts.py <path>=<expected> ...", file=sys.stderr)
        return 2

    problems = []
    for arg in argv[1:]:
        if "=" not in arg:
            print(f"check_verdicts: bad argument {arg!r}", file=sys.stderr)
            return 2
        path, expected = arg.split("=", 1)
        problem = check(path, expected)
        if problem:
            problems.append(problem)

    if problems:
        for p in problems:
            print(f"check_verdicts: {p}", file=sys.stderr)
        return 1

    print(f"check_verdicts: {len(argv) - 1} verifier verdicts as claimed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
