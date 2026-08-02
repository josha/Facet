#!/usr/bin/env python3
"""Assert a Studio spike / drive artifact actually RECORDS the rows a gate cites.

WHY THIS EXISTS (gate-integrity sweep 2026-07-29, defect B-9). A cluster of gate
checks made specific claims about live-engine findings — "explicit writes defeat
StyleRules silently", "dump rects applied exactly", "20 named probe results" —
and ran `test -f` on the artifact. Truncating the file to `{}` left them green.

These rows genuinely cannot be re-run headlessly: they are the record of a live
Studio session. The honest fix is not to pretend otherwise, but to check the
CONTENT of the record instead of its existence, so an artifact that no longer
carries the finding its gate cites fails that gate.

Usage: tools/check_spike.py <artifact.json> <row-id>[=<expected>] ...

Each argument names a row. The row list is found among the usual container keys
and the row is matched on its usual id field (both listed below). With an
`=<expected>`, the row's status field must START WITH that value; if the row has
no status-like field, `<expected>` must appear somewhere in the row's own text.
Without one, the row need only be present.
"""

import json
import sys

ROW_KEYS = ("results", "drives", "probes", "checks", "steps", "rows", "observations")
ID_FIELDS = ("check", "behavior", "name", "step", "id", "row", "probe")
STATUS_FIELDS = ("status", "verdict", "state")


def find_rows(doc):
    for key in ROW_KEYS:
        value = doc.get(key)
        if isinstance(value, list) and value and isinstance(value[0], dict):
            return key, value
    return None, None


def row_id(row):
    for field in ID_FIELDS:
        if isinstance(row.get(field), str):
            return row[field]
    return None


def row_status(row):
    for field in STATUS_FIELDS:
        if isinstance(row.get(field), str):
            return field, row[field]
    return None, None


def row_text(row):
    return " ".join(str(v) for v in row.values())


def main(argv):
    if len(argv) < 3:
        print("usage: tools/check_spike.py <artifact.json> <row-id>[=<expected>] ...", file=sys.stderr)
        return 2

    path = argv[1]
    try:
        with open(path) as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        print(f"check_spike: missing artifact {path}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"check_spike: {path} is not valid JSON ({exc})", file=sys.stderr)
        return 1

    if not isinstance(doc, dict):
        print(f"check_spike: {path} is not an object", file=sys.stderr)
        return 1

    key, rows = find_rows(doc)
    if rows is None:
        print(
            f"check_spike: {path} carries no row list "
            f"(looked for {', '.join(ROW_KEYS)})",
            file=sys.stderr,
        )
        return 1

    problems = []
    for arg in argv[2:]:
        wanted, _, expected = arg.partition("=")
        # a row id may be a prefix of the recorded one: live drives write prose ids
        matches = [r for r in rows if (row_id(r) or "").startswith(wanted)]
        if not matches:
            problems.append(
                f"{path} [{key}] has no row starting with {wanted!r} "
                f"(it has {', '.join(sorted(filter(None, (row_id(r) for r in rows))))[:220]})"
            )
            continue
        if not expected:
            continue
        row = matches[0]
        field, status = row_status(row)
        if field is not None:
            if not status.startswith(expected):
                problems.append(
                    f"{path} [{key}] row {wanted!r} has {field}={status[:60]!r}, "
                    f"expected it to start with {expected!r}"
                )
        elif expected not in row_text(row):
            problems.append(
                f"{path} [{key}] row {wanted!r} does not mention {expected!r}"
            )

    if problems:
        for p in problems:
            print(f"check_spike: {p}", file=sys.stderr)
        return 1

    print(f"check_spike: {path} [{key}] carries all {len(argv) - 2} cited rows")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
