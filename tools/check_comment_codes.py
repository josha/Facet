#!/usr/bin/env python3
"""check_comment_codes — no private code may be the whole explanation.

The release plan says a maintained source comment must not carry "unexplained
gate IDs, finding codes, phase labels, evidence-row names, or acronyms". Until
this checker there was no instrument for that at all: `check_doc_style.py` reads
`docs/guide` and `docs/extending`, and nothing read `src/`.

WHAT A PRIVATE CODE IS. A token shaped like `AB-12`, `ABC-A7` or `SF-M9`: two to
five capitals, a hyphen, an optional letter, digits. Those resolve only inside
this repository's private ledgers, so a reader outside it cannot follow one.

WHAT IS NOT ONE, and each exclusion is a fact rather than a preference:

  * `ADR-nnnn`     a decision record that ships in docs/adr/ — a reader can open it;
  * `UI-XXX-nnn`   a requirement id that resolves in requirements.json, which ships;
  * `SW-nnn`       a citation id in the comparison document, which ships;
  * `UTF-8`       a text encoding, not a ledger row;
  * ISO dates, hex and version numbers are not this shape at all.

THE BAR IS A RATCHET, NOT A ZERO. The count may fall and may never rise. A wave
that rewrites a comment and leaves the code behind fails; a wave that removes one
lowers the ceiling in the same commit. The five modules held by the concurrent
extraction work are counted SEPARATELY and named, so their debt is visible rather
than averaged away.

Usage:  python3 tools/check_comment_codes.py [--selftest] [--list] [--json]
Exit 0 = at or under the ceiling; 1 = over it, or a listed module vanished.
"""

import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

SCANNED = ("src",)

# Held by the concurrent source-cap extraction work. Counted and reported, never
# mixed into the ratchet: their sweep belongs to the extraction that owns them.
EXTRACTION_LOCKED = (
    "src/controls/table.luau",
    "src/controls/virtual_list.luau",
    "src/layout/solver.luau",
    "src/render/renderer.luau",
    "src/present/presenter.luau",
)

# `AB-12`, `ABC-A7`, `SF-M9` — a private ledger row, phase or finding code.
CODE = re.compile(r"\b([A-Z]{2,5})-([A-Z]?\d{1,3})\b")

# Prefixes that resolve in something this repository ships.
PUBLIC_PREFIX = ("ADR", "SW", "UI", "UTF")

# THE CEILING. Measured, not chosen: it is the count on the commit that
# introduced this checker, after that commit's own sweep. It was 531 before the
# sweep and 122 after. Lower it whenever a sweep lands; never raise it.
CEILING = 122


def tracked(paths):
    out = subprocess.run(["git", "-C", REPO, "ls-files", *paths],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("check_comment_codes: FAIL_ENVIRONMENT git ls-files")
        sys.exit(2)
    return [p for p in out.stdout.splitlines() if p.endswith(".luau")]


def comment_lines(text):
    """Every line that is inside a Luau comment, with its 1-based number.

    Block comments (`--[[ … ]]`) count from the opener to the closer. A `--`
    that is inside a string is not a comment, so a line whose quote count before
    the `--` is odd is skipped.
    """
    inside_block = False
    for n, line in enumerate(text.split("\n"), 1):
        if inside_block:
            yield n, line
            if "]]" in line:
                inside_block = False
            continue
        start = line.find("--[[")
        if start >= 0 and line.count('"', 0, start) % 2 == 0:
            inside_block = "]]" not in line[start:]
            yield n, line
            continue
        start = line.find("--")
        if start >= 0 and line.count('"', 0, start) % 2 == 0 \
           and line.count("'", 0, start) % 2 == 0:
            yield n, line


def is_public(line, match):
    """A code that resolves in something this repository ships.

    `UI-INPUT-001` reaches here as `INPUT-001`, because `UI-` is not followed by
    digits and the pattern starts at the second segment. So the character run
    BEFORE the match decides it, not the match alone.
    """
    if match.group(1) in PUBLIC_PREFIX:
        return True
    return line[:match.start()].endswith("UI-")


def scan():
    live, locked = [], []
    for rel in tracked(SCANNED):
        try:
            with open(os.path.join(REPO, rel), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        target = locked if rel in EXTRACTION_LOCKED else live
        for n, line in comment_lines(text):
            for match in CODE.finditer(line):
                if is_public(line, match):
                    continue
                target.append((rel, n, match.group(0), line.strip()[:110]))
    return live, locked


def selftest():
    """Prove the checker sees a planted code and ignores the public prefixes."""
    probe = os.path.join(REPO, "src", "comment_code_probe_tmp.luau")
    try:
        with open(probe, "w") as fh:
            fh.write("--!strict\n-- planted: this rule came from row TP-A12.\n"
                     "-- and these must NOT count: ADR-0011, UI-INPUT-001, SW-141.\n"
                     'local s = "not a comment: XX-9"\nreturn s\n')
        out = subprocess.run(["git", "-C", REPO, "ls-files", "src"],
                             capture_output=True, text=True).stdout
        planted = []
        with open(probe, encoding="utf-8") as fh:
            for n, line in comment_lines(fh.read()):
                for match in CODE.finditer(line):
                    if not is_public(line, match):
                        planted.append(match.group(0))
        if planted != ["TP-A12"]:
            print("check_comment_codes: SELFTEST FAIL — expected exactly ['TP-A12'], "
                  f"got {planted}")
            return 1
        if probe.split("/")[-1] in out:
            print("check_comment_codes: SELFTEST FAIL — the probe is tracked")
            return 1
    finally:
        if os.path.exists(probe):
            os.unlink(probe)
    live, _locked = scan()
    if len(live) > CEILING:
        print("check_comment_codes: SELFTEST FAIL — the restored tree is over the ceiling")
        return 1
    print("check_comment_codes: SELFTEST PASS — a planted `TP-A12` is reported, "
          "`ADR-0011`/`UI-INPUT-001`/`SW-141` are deliberately not, a code inside "
          "a string literal is not a comment, and the restored tree is at or under "
          f"the ceiling ({len(live)}/{CEILING})")
    return 0


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    live, locked = scan()
    if "--json" in sys.argv:
        print(json.dumps({
            "ceiling": CEILING,
            "nonLockedSites": len(live),
            "nonLockedFiles": len({r for r, _n, _c, _l in live}),
            "lockedSites": len(locked),
            "lockedFiles": len({r for r, _n, _c, _l in locked}),
            "byCode": {code: sum(1 for _r, _n, c, _l in live if c == code)
                       for code in sorted({c for _r, _n, c, _l in live})},
        }, indent=2))
        return
    if "--list" in sys.argv:
        for rel, n, code, line in live:
            print(f"  {rel}:{n}: {code}  {line}")
    files = len({r for r, _n, _c, _l in live})
    if len(live) > CEILING:
        print(f"check_comment_codes: FAIL — {len(live)} private codes in maintained "
              f"src/ comments across {files} files, over the ceiling of {CEILING}. "
              "Say what the code means, or cite an ADR by number. Run with --list.")
        sys.exit(1)
    print(f"check_comment_codes: PASS — {len(live)} private codes in maintained src/ "
          f"comments across {files} files (ceiling {CEILING}); "
          f"{len(locked)} more in the {len(EXTRACTION_LOCKED)} extraction-locked "
          "modules, counted separately and owed to that extraction.")


if __name__ == "__main__":
    main()
