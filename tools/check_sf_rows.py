#!/usr/bin/env python3
"""Assert a sponsor-framework-gaps row artifact actually COVERS the rows a gate
check claims it does.

WHY THIS EXISTS (gate-integrity sweep 2026-07-29, defect B-3). Fourteen checks in
the `sponsor-framework-gaps` gate made behavioural claims — "interruptible
velocity-seeded classes", "every mount/reset/dispose cycle returns registries to
baseline" — and ran `test -f` on a JSON file. Deleting src/motion/ entirely left
all fourteen green. A file's existence is not evidence for a claim about the tree.

The Studio half of those rows genuinely cannot be re-run headlessly, so the honest
fix has two parts: the gate check names the real spec cases for the headless half
(through ./run-tests.sh), and this script validates the CONTENT of the Studio
artifact instead of its existence — the schema is the one the drivers emit, and
the artifact must list every row the check is citing it for.

Usage: tools/check_sf_rows.py <row-artifact.json> ROW-ID [ROW-ID ...]
Exit 0 when every named row is covered; non-zero with a reason otherwise.
"""

import json
import sys

SCHEMA = "luauui-sf-row/1"


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip().splitlines()[-2], file=sys.stderr)
        return 2

    path, wanted = argv[1], argv[2:]

    try:
        with open(path) as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        print(f"check_sf_rows: missing artifact {path}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"check_sf_rows: {path} is not valid JSON ({exc})", file=sys.stderr)
        return 1

    if not isinstance(doc, dict):
        print(f"check_sf_rows: {path} is not an object", file=sys.stderr)
        return 1

    schema = doc.get("schema")
    if schema != SCHEMA:
        print(
            f"check_sf_rows: {path} schema is {schema!r}, expected {SCHEMA!r} "
            "(this is not a row artifact the drivers wrote)",
            file=sys.stderr,
        )
        return 1

    rows = doc.get("rows")
    if not isinstance(rows, list) or not rows:
        print(f"check_sf_rows: {path} has no non-empty `rows` list", file=sys.stderr)
        return 1

    missing = [r for r in wanted if r not in rows]
    if missing:
        print(
            f"check_sf_rows: {path} does not cover {', '.join(missing)} "
            f"(it lists {', '.join(map(str, rows))})",
            file=sys.stderr,
        )
        return 1

    print(f"check_sf_rows: {path} covers {', '.join(wanted)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
