#!/usr/bin/env python3
"""check_doc_style — the measurable half of the house writing style.

The release plan asks every document a person is expected to read to follow an
ASD-STE100-inspired clarity standard. This is a clarity standard, not a claim of
formal certification. Most of that standard is a judgement call and belongs to a
human reviewer. Three parts of it are mechanical, and this checker owns those:

  1. ONE INSTRUCTION PER STEP, AND KEEP IT SHORT. A numbered step is an
     instruction. Over MAX_INSTRUCTION_WORDS words it is carrying more than one.
  2. NO UNEXPLAINED ACRONYM. An acronym in NEEDS_EXPANSION must be expanded once
     in the document that uses it, before or on the line that first uses it.
     Acronyms in COMMON are ordinary technical English and need no expansion.
  3. NO INTERNAL SHORTHAND. A bare artifact row id, phase code, or finding code
     (`TP-A12`, `SF-D3`, `M8`) means nothing to a reader outside this repository.

Two more signals are reported as WARNINGS and never fail a run, because a
sentence-length rule and a passive-voice heuristic both misjudge real technical
prose often enough that failing on them would teach people to route around the
checker:

  4. a description sentence longer than MAX_SENTENCE_WORDS words;
  5. a likely passive construction.

What it must never reject: code blocks, inline code, tables' cell contents,
links, and exact API, Roblox-class, path, or command names. Fenced blocks and
inline code spans are removed before any rule looks at a line.

One deliberate exception to "must not reject links": a link's TARGET is removed,
but its LABEL is kept and scanned, because the label is the text a reader sees.
`[TP-A97](../artifacts/x.md)` therefore fails rule 3 — the shorthand is on the
page whatever it points at.

Usage:  python3 tools/check_doc_style.py [--selftest] [--warnings]
Exit 0 = clean; 1 = a FAIL-class violation; 2 = environment failure.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# Every document a Roblox developer is expected to read cover to cover.
SCANNED_DIRS = ("docs/guide", "docs/extending")

# ...and the front door, which is not in a directory of its own. Two
# fresh-context agents opened this repository on 2026-08-21 and both reported
# the same first friction: `cat README.md` failed, and the real entry point had
# to be found by listing `docs/`. The README that closed that gap is the one
# page most likely to be read and the one page least likely to be reviewed, so
# it is held to the same clarity standard as the guide it points at.
# ...and the maintainer map, which sits beside the directories rather than in one
# (release-candidate review row RC-11). It is the page a new owner reads before
# touching anything, so it is held to the same clarity standard as the guide.
SCANNED_FILES = ("README.md", "docs/MAINTAINERS.md")

MAX_INSTRUCTION_WORDS = 20
MAX_SENTENCE_WORDS = 25

# Acronyms that are ordinary technical English for a Roblox developer. No
# expansion is required, because expanding them adds noise rather than meaning.
COMMON = {
    "UI", "API", "ID", "IDS", "URL", "URI", "JSON", "XML", "HTML", "CSS",
    "CPU", "GPU", "RAM", "KB", "MB", "GB", "MS", "FPS", "DPI", "PPI", "RGB",
    "HTTP", "HTTPS", "IP", "USB", "TV", "VR", "AR", "OS", "PNG", "JPG", "SVG",
    "ASCII", "UTF", "LZ", "CSV", "CLI", "SDK", "IDE", "HUD", "TODO",
    "FAQ", "WASD", "DPAD", "LED", "AI", "NPC",
}

# Acronyms this repository uses that a new reader will not know. Each must be
# expanded once, in the document that uses it, at or before first use. The
# expansion this checker accepts is the acronym in parentheses after the words,
# or the words in parentheses after the acronym.
NEEDS_EXPANSION = {
    "IAS": "Input Action System",
    "CAS": "ContextActionService",
    "UIS": "UserInputService",
    "MCP": "Model Context Protocol",
    "VM": "virtual machine",
    "REPL": "read-eval-print loop",
    "CDN": "content delivery network",
    "GA": "general availability",
    "SF": "the framework icon set",
}

# Uppercase tokens that look like an internal row id but are a real technical
# name, with the reason. An entry without a reason is a hole, not an allowlist.
SHORTHAND_ALLOW = {
    "L1": "a gamepad shoulder button",
    "L2": "a gamepad trigger",
    "R1": "a gamepad shoulder button",
    "R2": "a gamepad trigger",
    "F6": "a keyboard function key",
    "F10": "a keyboard function key",
    "P1": "a display resolution class in the device matrix",
    "UTF8": "a text encoding",
}

# A bare artifact row id / phase code: two to five capitals, a hyphen, digits
# (`TP-A12`, `SF-D3`, `MAINT-2`), or a single capital and digits (`E4`, `M8`).
SHORTHAND = re.compile(r"\b([A-Z]{1,5})-?([A-Z]?\d{1,3})\b")

ACRONYM = re.compile(r"\b([A-Z]{2,6})\b")

PASSIVE = re.compile(
    r"\b(?:is|are|was|were|be|been|being)\s+(?:\w+ly\s+)?(\w+(?:ed|en))\b",
    re.IGNORECASE,
)

# Verbs whose past participle reads as an adjective, so the passive heuristic
# would cry wolf on ordinary description.
PASSIVE_SKIP = {"used", "based", "named", "called", "fixed", "closed", "open",
                "needed", "allowed", "supposed", "intended", "limited"}


def documents():
    found = []
    for rel in SCANNED_DIRS:
        root = os.path.join(REPO, rel)
        if not os.path.isdir(root):
            continue
        for name in sorted(os.listdir(root)):
            if name.endswith(".md"):
                found.append(os.path.join(rel, name))
    # ...and the individual files, which SCANNED_DIRS cannot express: the loop
    # above requires a directory and SILENTLY SKIPS anything that is not one, so
    # a file name added there would have been scanned by nothing while looking
    # exactly like it was covered.
    for rel in SCANNED_FILES:
        if os.path.isfile(os.path.join(REPO, rel)):
            found.append(rel)
    return found


def readable_lines(text):
    """Yield (line_number, prose) with code removed.

    Fenced blocks become empty, inline code spans become the single token CODE,
    and a link becomes its label. Every exact name a document has to keep is
    inside one of those three, which is why none of them reaches a rule.
    """
    fenced = False
    for n, raw in enumerate(text.split("\n"), 1):
        if raw.lstrip().startswith("```"):
            fenced = not fenced
            yield n, ""
            continue
        if fenced:
            yield n, ""
            continue
        prose = re.sub(r"`[^`]*`", "CODE", raw)
        prose = re.sub(r"<kbd>[^<]*</kbd>", "KEY", prose)
        prose = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", prose)
        prose = re.sub(r"<https?://[^>]*>", "LINK", prose)
        prose = re.sub(r"https?://\S+", "LINK", prose)
        prose = re.sub(r"<!--.*?-->", "", prose)
        # emphasis markers are formatting, not words: leaving them in would make
        # "**Input Action System** (IAS)" look like an unexpanded acronym
        prose = prose.replace("**", "").replace("__", "")
        yield n, prose


def words(text):
    return re.findall(r"[A-Za-z0-9][A-Za-z0-9'/._-]*", text)


def expansion_lines(readable):
    """The line each acronym is first EXPANDED on, or None.

    An expansion is matched over the whole document with line breaks flattened,
    because a sentence that wraps is still one sentence: requiring the words and
    the acronym on one physical line would fail correct prose for its width.
    """
    joined, offsets = [], []
    for n, prose in readable:
        offsets.append((len(" ".join(joined)) + (1 if joined else 0), n))
        joined.append(prose)
    flat = " ".join(joined)
    found = {}
    for acronym, expansion in NEEDS_EXPANSION.items():
        pattern = (rf"{re.escape(expansion)}\s*\(\s*{acronym}\s*\)"
                   rf"|\b{acronym}\b\s*[—-]?\s*\(\s*{re.escape(expansion)}")
        match = re.search(pattern, flat, re.I)
        if match is None:
            continue
        line = offsets[0][1]
        for start, n in offsets:
            if start <= match.start():
                line = n
            else:
                break
        found[acronym] = line
    return found


def check_document(path, text, fails, warns):
    readable = list(readable_lines(text))
    expandedAt = expansion_lines(readable)
    reported = set()
    for n, prose in readable:
        if not prose.strip():
            continue

        for match in ACRONYM.finditer(prose):
            token = match.group(1)
            if token in NEEDS_EXPANSION and token not in reported \
               and (expandedAt.get(token) is None or expandedAt[token] > n):
                fails.append(f"{path}:{n}: acronym '{token}' is used before it is "
                             f"expanded (write \"{NEEDS_EXPANSION[token]} ({token})\" "
                             "at first use)")
                reported.add(token)  # report once per document

        # 3. internal shorthand
        for match in SHORTHAND.finditer(prose):
            token = match.group(0)
            stem = match.group(1)
            if token in SHORTHAND_ALLOW or stem in SHORTHAND_ALLOW:
                continue
            if token.upper() in COMMON:
                continue
            fails.append(f"{path}:{n}: '{token}' is internal shorthand (an artifact "
                         "row, phase or finding code). Say what it means, or name "
                         "the shipped document that holds it")

        # 1. instruction length
        step = re.match(r"^\s*\d+\.\s+(\S.*)$", prose)
        if step is not None:
            count = len(words(step.group(1)))
            if count > MAX_INSTRUCTION_WORDS:
                fails.append(f"{path}:{n}: numbered step is {count} words "
                             f"(limit {MAX_INSTRUCTION_WORDS}). Split it so each "
                             "step carries one instruction")

        # 4/5. warnings
        for sentence in re.split(r"(?<=[.!?])\s+", prose.strip()):
            count = len(words(sentence))
            if count > MAX_SENTENCE_WORDS:
                warns.append(f"{path}:{n}: sentence is {count} words "
                             f"(target {MAX_SENTENCE_WORDS})")
        for match in PASSIVE.finditer(prose):
            if match.group(1).lower() in PASSIVE_SKIP:
                continue
            warns.append(f"{path}:{n}: likely passive voice: '{match.group(0)}'")


def run(root=REPO):
    fails, warns = [], []
    for path in documents():
        full = os.path.join(root, path)
        if not os.path.isfile(full):
            continue
        with open(full, encoding="utf-8", errors="replace") as handle:
            check_document(path, handle.read(), fails, warns)
    return fails, warns


def selftest():
    """Plant one violation of each FAIL rule, require each to be reported, then
    require the restored tree to pass. A checker nobody has watched fail proves
    nothing about the tree it passes."""
    probe = os.path.join(REPO, "docs", "guide", "style_probe_tmp.md")
    cases = [
        ("an over-long numbered step",
         "1. Open the place file, then find the client script, then read the "
         "mount call, then change the theme name, then save it and publish.\n",
         "numbered step is"),
        ("an unexpanded acronym",
         "Turn on IAS before you mount anything.\n",
         "acronym 'IAS'"),
        ("a bare artifact row id",
         "This behaviour is pinned by row TP-A12 in the ledger.\n",
         "internal shorthand"),
    ]
    try:
        for name, body, needle in cases:
            with open(probe, "w") as handle:
                handle.write("# Probe\n\n" + body)
            fails, _warns = run()
            hit = [f for f in fails if "style_probe_tmp" in f and needle in f]
            if not hit:
                print(f"check_doc_style: SELFTEST FAIL — {name} was not reported")
                print("\n".join(fails[:10]))
                return 1
    finally:
        if os.path.exists(probe):
            os.unlink(probe)
    fails, warns = run()
    if fails:
        print("check_doc_style: SELFTEST FAIL — the restored tree is not clean:")
        print("\n".join(fails[:20]))
        return 1
    print("check_doc_style: SELFTEST PASS — an over-long numbered step, an "
          "unexpanded acronym and a bare artifact row id were each reported; "
          f"the restored tree is clean ({len(warns)} warnings, which never fail)")
    return 0


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    fails, warns = run()
    if "--warnings" in sys.argv:
        for warning in warns:
            print("  warn: " + warning)
    if fails:
        print(f"check_doc_style: FAIL — {len(fails)} violation(s):")
        for failure in fails[:60]:
            print("  " + failure)
        if len(fails) > 60:
            print(f"  … and {len(fails) - 60} more")
        sys.exit(1)
    print(f"check_doc_style: PASS — {len(documents())} documents; no over-long "
          "instruction step, no unexpanded acronym, no internal shorthand "
          f"({len(warns)} warnings, reported with --warnings and never fatal)")


if __name__ == "__main__":
    main()
