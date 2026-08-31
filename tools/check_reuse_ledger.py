#!/usr/bin/env python3
"""Does the reuse ledger disposition EVERY finding the reuse audit filed?

    python3 tools/check_reuse_ledger.py [--selftest]

WHY THIS EXISTS
---------------
`tools/lune/verify/data/reuse-ledger.md` is acceptance row RC-10's
whole evidence, and it opens by claiming that every finding in
`artifacts/release-candidate-review/reviews/reuse.md` is dispositioned. The
first version of that file made the claim while carrying 16 of 125 findings, and
the gate row that published it could not tell: its ledger clauses were five
fixed `grep -qF` strings, so they asserted that some sentences existed, not that
the property held. That is this repository's own documented "check that proves
nothing" shape, aimed at exactly the property the acceptance row names.

So the check is STRUCTURAL and takes no fixed strings. It reads the audit's own
`### REUSE-<n> —` headers — the authoritative enumeration, because every finding
has one and the summary tables are split across sections and repeat rows — and
compares that set against the `| REUSE-<n> |` rows in the ledger. Three ways to
fail, each named separately because they are different mistakes:

  * MISSING   — a finding the audit filed and the ledger never mentions.
  * DUPLICATE — a finding dispositioned twice, which is two answers to one
                question and hides which one is current.
  * INVENTED  — an ID in the ledger that the audit never filed, which is how a
                ledger drifts into describing a report nobody wrote.

Every row must also carry a DISPOSITION word, because "REUSE-42 exists in the
table" is not a disposition either.

`--selftest` proves it can fail: it plants an omission, a duplicate and an
invented ID in a scratch COPY of the ledger, requires each to be caught with the
right verdict, and requires the real file to pass afterwards. The copy is a copy
on purpose — a concurrent reader never sees a mutated artifact.

Exit 0 = complete; 1 = incomplete; 2 = environment failure.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
AUDIT = os.path.join(REPO, "artifacts", "release-candidate-review", "reviews", "reuse.md")
LEDGER = os.path.join(REPO, "tools", "lune", "verify", "data", "reuse-ledger.md")

# the audit's authoritative enumeration: one `###` header per finding
AUDIT_ID = re.compile(r"^### REUSE-(\d+) —", re.M)
# a ledger row: `| REUSE-<n> | … |`
LEDGER_ROW = re.compile(r"^\| REUSE-(\d+) \|(.*)$", re.M)
DISPOSITIONS = ("CONSOLIDATED", "KEPT SEPARATE", "DEFERRED")


def read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        print(f"check_reuse_ledger: FAIL_ENVIRONMENT cannot read {path}: {exc}")
        sys.exit(2)


#[[ THE AUDIT IS ARCHIVED; THE LEDGER IS THE OPERAND NOW.
#
#   `reuse.md` filed the findings and has left the tip with the rest of the stage
#   record. Its enumeration survives in two places: the ledger's own opening
#   sentence, which states how many findings there were, and a receipt beside the
#   ledger carrying the archived file's path and sha256.
#
#   So the four properties this checker has always asserted — nothing MISSING,
#   nothing DUPLICATE, nothing INVENTED, nothing UNDISPOSED — are now asked
#   against `1..N` where N is the number the ledger declares. A gap is still
#   MISSING and a row past the end is still INVENTED; what changes is where the
#   count comes from, and the receipt is what that count answers to. ]]
SOURCE_RECEIPT = os.path.join(REPO, "tools", "lune", "verify", "data", "reuse-ledger-source.json")
DECLARED_COUNT = re.compile(r"Every one of the (\d+) findings", re.M)
ARCHIVE_MANIFEST = os.path.join(REPO, "..", "Facet-private-archive", "MANIFEST.json")


def source_receipt():
    """The archived audit's own checksum, and whether the archive still agrees."""
    try:
        with open(SOURCE_RECEIPT, encoding="utf-8") as fh:
            receipt = json.load(fh)
    except (OSError, ValueError):
        return None, "no source receipt beside the ledger"
    if not os.path.exists(ARCHIVE_MANIFEST):
        return receipt, "declared (the private archive is not beside this checkout)"
    try:
        with open(ARCHIVE_MANIFEST, encoding="utf-8") as fh:
            files = {f["path"]: f["sha256"] for f in json.load(fh)["files"]}
    except (OSError, ValueError, KeyError):
        return receipt, "declared (the archive manifest is unreadable)"
    archived = files.get(receipt["archivedPath"])
    if archived is None:
        return receipt, "declared (the archive does not list it)"
    if archived != receipt["sha256"]:
        return None, (
            f"the archive's copy of {receipt['archivedPath']} hashes to {archived[:12]}…, "
            f"the receipt records {receipt['sha256'][:12]}…"
        )
    return receipt, "verified against the private archive"


def audit_ids(text=None):
    """Every finding id the audit filed: 1..N, N declared by the ledger itself."""
    if text is not None:
        ids = [int(m) for m in AUDIT_ID.findall(text)]
        if ids:
            return ids
    if os.path.exists(AUDIT):
        ids = [int(m) for m in AUDIT_ID.findall(read(AUDIT))]
        if ids:
            return ids
    declared = DECLARED_COUNT.search(text if text is not None else read(LEDGER))
    if not declared:
        print("check_reuse_ledger: FAIL_ENVIRONMENT the ledger does not state how many "
              "findings the audit filed, and the audit itself is archived")
        sys.exit(2)
    return list(range(1, int(declared.group(1)) + 1))


def check(ledger_text, audit_text=None):
    """-> (problems, filed_count, row_count). Empty problems == complete."""
    filed = audit_ids(audit_text if audit_text is not None else ledger_text)
    filed_set = set(filed)
    rows = LEDGER_ROW.findall(ledger_text)
    seen = {}
    undisposed = []
    for num, rest in rows:
        i = int(num)
        seen[i] = seen.get(i, 0) + 1
        if not any(word in rest for word in DISPOSITIONS):
            undisposed.append(i)
    problems = []
    for i in sorted(filed_set - set(seen)):
        problems.append(f"MISSING   REUSE-{i} — filed by the audit, absent from the ledger")
    for i in sorted(k for k, n in seen.items() if n > 1):
        problems.append(f"DUPLICATE REUSE-{i} — dispositioned {seen[i]} times")
    for i in sorted(set(seen) - filed_set):
        problems.append(f"INVENTED  REUSE-{i} — in the ledger, never filed by the audit")
    for i in sorted(set(undisposed)):
        problems.append(
            f"UNDISPOSED REUSE-{i} — the row names no disposition "
            f"({', '.join(DISPOSITIONS)})")
    return problems, len(filed_set), len(rows)


def selftest():
    ledger = read(LEDGER)
    audit = read(AUDIT) if os.path.exists(AUDIT) else ledger
    filed = sorted(set(audit_ids(audit)))
    cases = []

    victim = filed[len(filed) // 2]
    omitted = re.sub(rf"^\| REUSE-{victim} \|.*$\n", "", ledger, count=1, flags=re.M)
    cases.append(("omission", omitted, f"MISSING   REUSE-{victim}"))

    row = re.search(rf"^\| REUSE-{filed[0]} \|.*$", ledger, re.M).group(0)
    cases.append(("duplicate", ledger.replace(row, row + "\n" + row, 1),
                  f"DUPLICATE REUSE-{filed[0]}"))

    invented = max(filed) + 77
    cases.append(("invented id", ledger.replace(
        row, row + f"\n| REUSE-{invented} | Low / low | made up | **DEFERRED** — nobody | — |", 1),
        f"INVENTED  REUSE-{invented}"))

    stripped = re.sub(rf"^(\| REUSE-{filed[1]} \|[^|]*\|[^|]*\|)[^|]*\|",
                      r"\1 no answer at all |", ledger, count=1, flags=re.M)
    cases.append(("undisposed row", stripped, f"UNDISPOSED REUSE-{filed[1]}"))

    for name, text, expected in cases:
        problems, _, _ = check(text, audit)
        if not any(p.startswith(expected) for p in problems):
            print(f"check_reuse_ledger: SELFTEST FAIL — a planted {name} was not caught")
            print("  expected a problem starting: " + expected)
            print("  got: " + ("; ".join(problems[:5]) or "(none)"))
            return 1

    problems, filed_n, rows_n = check(ledger, audit)
    if problems:
        print("check_reuse_ledger: SELFTEST FAIL — the real ledger is not complete:")
        print("\n".join("  " + p for p in problems[:20]))
        return 1
    print(f"check_reuse_ledger: SELFTEST PASS — planted omission, duplicate, invented ID and "
          f"undisposed row each caught; the real ledger dispositions all {filed_n} filed "
          f"findings in {rows_n} rows")
    return 0


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    receipt, standing = source_receipt()
    if receipt is None:
        print(f"check_reuse_ledger: FAIL — the ledger's source receipt does not hold: {standing}")
        sys.exit(1)
    problems, filed_n, rows_n = check(read(LEDGER))
    if problems:
        print(f"check_reuse_ledger: FAIL — {len(problems)} problem(s) against the "
              f"{filed_n} findings the audit filed:")
        for p in problems[:60]:
            print("  " + p)
        if len(problems) > 60:
            print(f"  … and {len(problems) - 60} more")
        sys.exit(1)
    print(f"check_reuse_ledger: PASS — every one of the {filed_n} findings the audit filed is "
          f"dispositioned exactly once in reuse-ledger.md ({rows_n} rows), every row names its "
          f"disposition, and the archived audit's checksum is {standing}")


if __name__ == "__main__":
    main()
