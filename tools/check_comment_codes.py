#!/usr/bin/env python3
"""check_comment_codes — a private code must resolve, or it is folklore.

The release plan's bar is that a maintained source comment carries no
UNEXPLAINED gate ID, finding code, phase label, evidence-row name or acronym. A
code that resolves is a citation and may stay; a code that resolves nowhere is
folklore and may not. So every site is classified, and the two classes carry
different ceilings.

WHAT A PRIVATE CODE IS. A token shaped like `AB-12`, `ABC-A7` or `SF-M9`: two to
five capitals, a hyphen, an optional letter, digits.

WHAT IS NOT ONE AT ALL, and each exclusion is a fact rather than a preference:

  * `ADR-nnnn`     a decision record that ships in docs/adr/ — a reader can open it;
  * `UI-XXX-nnn`   a requirement id that resolves in requirements.json, which ships;
  * `SW-nnn`       a citation id in the comparison document, which ships;
  * `UTF-8`        a text encoding, not a ledger row;
  * ISO dates, hex and version numbers are not this shape at all.

RESOLVABLE — the code has a referent a reader can reach, by one of four routes,
and the route is reported per site so the classification can be argued with:

  1. `requirements.json` names the code;
  2. the same comment block cites an `ADR-nnnn` that exists as a file;
  3. the same comment block names a `docs/**` file that exists;
  4. the same comment block DEFINES the code in plain language, in the same
     breath — `ADAPT-18: a collapsed column's heading leaves paint…`.

ORPHAN — none of the four. The code is the whole explanation and the explanation
is not in the repository. THE ORPHAN CEILING IS ZERO. There is no ratchet on
orphans and no allowance: a comment that needs one is rewritten in plain
language, or the missing referent is added where one genuinely exists.

THE TOTAL IS A RATCHET. Resolvable sites may not grow either, so a new code has
to displace an old one. Lower `TOTAL_CEILING` whenever a sweep lands; never
raise it.

The five modules held by the concurrent extraction work are counted SEPARATELY
and named, so their debt is visible rather than averaged away.

Usage:  python3 tools/check_comment_codes.py [--selftest] [--list] [--json]
Exit 0 = no orphan and at or under the total ceiling; 1 = otherwise.
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

# THE ORPHAN CEILING IS ZERO AND IS NOT A RATCHET. A code that resolves nowhere
# is the thing the rule prohibits, so there is no allowance for one.
ORPHAN_CEILING = 0

# THE TOTAL CEILING is measured, not chosen: the count on the commit that swept
# the orphans. It was 531 before this checker existed, 122 when the checker
# landed, and 25 once every orphan was rewritten. Lower it whenever a sweep
# lands; never raise it.
TOTAL_CEILING = 25

# A `docs/**` file named inside a comment block, and an ADR reference.
DOC_PATH = re.compile(r"docs/[A-Za-z0-9_./-]+\.(?:md|luau)")
ADR_REF = re.compile(r"\bADR-(\d{4})\b")


def tracked(paths):
    out = subprocess.run(["git", "-C", REPO, "ls-files", *paths],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("check_comment_codes: FAIL_ENVIRONMENT git ls-files")
        sys.exit(2)
    return [p for p in out.stdout.splitlines() if p.endswith(".luau")]


def comment_blocks(text):
    """Every comment block, as (first_line_number, block_text).

    A block is a `--[[ … ]]` comment or a run of consecutive `--` lines. The
    block is the unit a referent has to sit in: a code and the sentence that
    defines it belong to the same thought, and a citation three paragraphs away
    is not one a reader connects.
    """
    lines = text.split("\n")
    out, current, start, inside = [], [], None, False
    for n, line in enumerate(lines, 1):
        is_comment = False
        if inside:
            is_comment = True
            if "]]" in line:
                inside = False
        else:
            at = line.find("--[[")
            if at >= 0 and line.count('"', 0, at) % 2 == 0:
                inside = "]]" not in line[at:]
                is_comment = True
            else:
                at = line.find("--")
                if at >= 0 and line.count('"', 0, at) % 2 == 0 \
                   and line.count("'", 0, at) % 2 == 0:
                    is_comment = True
        if is_comment:
            if start is None:
                start = n
            current.append(line)
        elif start is not None:
            out.append((start, "\n".join(current)))
            current, start = [], None
    if start is not None:
        out.append((start, "\n".join(current)))
    return out


def is_public(line, match):
    """A code that resolves in something this repository ships.

    `UI-INPUT-001` reaches here as `INPUT-001`, because `UI-` is not followed by
    digits and the pattern starts at the second segment. So the character run
    BEFORE the match decides it, not the match alone.
    """
    if match.group(1) in PUBLIC_PREFIX:
        return True
    return line[:match.start()].endswith("UI-")


def _requirements():
    try:
        with open(os.path.join(REPO, "requirements.json"), encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


def _adr_numbers():
    root = os.path.join(REPO, "docs", "adr")
    if not os.path.isdir(root):
        return set()
    return {m.group(1) for m in
            (re.match(r"ADR-(\d{4})", n) for n in os.listdir(root)) if m}


def resolves(code, block, requirements, adrs):
    """The route by which a reader can reach this code, or None.

    Reported rather than returned as a boolean, so a reviewer can disagree with
    a particular site instead of with the count.
    """
    if code in requirements:
        return "requirements.json"
    for number in ADR_REF.findall(block):
        if number in adrs:
            return f"ADR-{number}"
    for path in DOC_PATH.findall(block):
        if os.path.isfile(os.path.join(REPO, path)):
            return path
    # …or the block says what the code means, in the same breath
    defined = re.compile(
        r"\b" + re.escape(code) + r"(?:'s)?\s*"
        r"(?:—|:|\bis\b|\bmeans\b|\bnames\b|\brecords\b|\bcontract\b|\bsays\b)"
    )
    if defined.search(block):
        return "defined-in-block"
    return None


def scan():
    """Every code site, classified. Returns (live, locked); a site is
    (path, line, code, route_or_None, text)."""
    requirements = _requirements()
    adrs = _adr_numbers()
    live, locked = [], []
    for rel in tracked(SCANNED):
        try:
            with open(os.path.join(REPO, rel), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        target = locked if rel in EXTRACTION_LOCKED else live
        for start, block in comment_blocks(text):
            for offset, line in enumerate(block.split("\n")):
                for match in CODE.finditer(line):
                    if is_public(line, match):
                        continue
                    code = match.group(0)
                    target.append((rel, start + offset, code,
                                   resolves(code, block, requirements, adrs),
                                   line.strip()[:110]))
    return live, locked


def split(sites):
    return ([s for s in sites if s[3] is None],
            [s for s in sites if s[3] is not None])


def selftest():
    """Plant one orphan and one resolvable code, and require the two to be
    classified differently. A classifier nobody has watched separate the two is
    a classifier nobody knows the shape of."""
    probe = os.path.join(REPO, "src", "comment_code_probe_tmp.luau")
    requirements = _requirements()
    adrs = _adr_numbers()

    def classify(text):
        found = []
        for _start, block in comment_blocks(text):
            for line in block.split("\n"):
                for match in CODE.finditer(line):
                    if is_public(line, match):
                        continue
                    code = match.group(0)
                    found.append((code, resolves(code, block, requirements, adrs)))
        return found

    try:
        # 1. an ORPHAN: a code, and nothing anywhere that says what it is
        orphan = classify("--!strict\n-- planted: this rule came from row TP-A12.\n")
        if orphan != [("TP-A12", None)]:
            print("check_comment_codes: SELFTEST FAIL — the orphan was not reported "
                  f"as one: {orphan}")
            return 1
        # 2. the SAME code, defined in the same breath -> resolvable
        defined = classify("-- TP-A12: a column collapses before it clips.\n")
        if defined != [("TP-A12", "defined-in-block")]:
            print("check_comment_codes: SELFTEST FAIL — a code defined in its own "
                  f"block was not resolvable: {defined}")
            return 1
        # 3. …and cited to a real ADR instead
        cited = classify("-- planted TP-A12, and the reason is in ADR-0011.\n")
        if cited != [("TP-A12", "ADR-0011")]:
            print("check_comment_codes: SELFTEST FAIL — a code beside a real ADR "
                  f"was not resolvable: {cited}")
            return 1
        # 4. the public prefixes are still not codes at all, and a string is not
        #    a comment
        public = classify("-- ADR-0011, UI-INPUT-001, SW-141, UTF-8\n"
                          'local s = "not a comment: XX-9"\n')
        if public:
            print("check_comment_codes: SELFTEST FAIL — a public id or a string "
                  f"literal was counted: {public}")
            return 1
        # the probe file must never be tracked
        listed = subprocess.run(["git", "-C", REPO, "ls-files", "src"],
                                capture_output=True, text=True).stdout
        if "comment_code_probe_tmp" in listed:
            print("check_comment_codes: SELFTEST FAIL — the probe is tracked")
            return 1
    finally:
        if os.path.exists(probe):
            os.unlink(probe)

    live, _locked = scan()
    orphans, resolvable = split(live)
    if orphans or len(live) > TOTAL_CEILING:
        print("check_comment_codes: SELFTEST FAIL — the restored tree is not clean: "
              f"{len(orphans)} orphans, {len(live)}/{TOTAL_CEILING} total")
        return 1
    print("check_comment_codes: SELFTEST PASS — a planted `TP-A12` with no referent "
          "is an ORPHAN, the same code defined in its own block or cited to a real "
          "ADR is RESOLVABLE, the public prefixes and a string literal are neither, "
          f"and the restored tree has {len(orphans)} orphans and "
          f"{len(resolvable)}/{TOTAL_CEILING} resolvable")
    return 0


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    live, locked = scan()
    orphans, resolvable = split(live)
    locked_orphans, locked_resolvable = split(locked)
    if "--json" in sys.argv:
        print(json.dumps({
            "orphanCeiling": ORPHAN_CEILING,
            "totalCeiling": TOTAL_CEILING,
            "orphans": len(orphans),
            "resolvable": len(resolvable),
            "total": len(live),
            "files": len({r for r, _n, _c, _w, _l in live}),
            "byRoute": {route: sum(1 for s in resolvable if s[3] == route)
                        for route in sorted({s[3] for s in resolvable})},
            "lockedOrphans": len(locked_orphans),
            "lockedResolvable": len(locked_resolvable),
            "lockedFiles": len({r for r, _n, _c, _w, _l in locked}),
        }, indent=2))
        return
    if "--list" in sys.argv:
        for rel, n, code, route, line in live:
            print(f"  {'ORPHAN    ' if route is None else 'resolvable'} "
                  f"{rel}:{n}: {code}  [{route or 'no referent'}]  {line}")
    if orphans:
        print(f"check_comment_codes: FAIL — {len(orphans)} private code(s) in "
              "maintained src/ comments resolve nowhere. Say what the code means, "
              "cite an ADR by number, or name the document that holds it:")
        for rel, n, code, _route, line in orphans[:40]:
            print(f"  {rel}:{n}: {code}  {line}")
        sys.exit(1)
    if len(live) > TOTAL_CEILING:
        print(f"check_comment_codes: FAIL — {len(live)} private codes in maintained "
              f"src/ comments, over the ceiling of {TOTAL_CEILING}. Every one "
              "resolves, but the total is a ratchet: a new code has to displace an "
              "old one.")
        sys.exit(1)
    routes = {route: sum(1 for s in resolvable if s[3] == route)
              for route in sorted({s[3] for s in resolvable})}
    print(f"check_comment_codes: PASS — {len(orphans)} orphans (ceiling "
          f"{ORPHAN_CEILING}) and {len(resolvable)} resolvable private codes "
          f"(ceiling {TOTAL_CEILING}) in maintained src/ comments across "
          f"{len({r for r, _n, _c, _w, _l in live})} files; routes {routes}; "
          f"{len(locked)} more in the {len(EXTRACTION_LOCKED)} extraction-locked "
          "modules, counted separately and owed to that extraction.")


if __name__ == "__main__":
    main()
