#!/usr/bin/env python3

import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

USAGE = "usage: python3 tools/check_doc_style.py [--selftest] [--warnings]"

SCANNED_DIRS = ("docs/guide", "docs/extending")

SCANNED_FILES = ("README.md", "docs/MAINTAINERS.md")

ARCHAEOLOGY_EXEMPT = {
    "docs/guide/14-choosing-a-ui-library.md",
    "docs/guide/11-device-verification.md",
}

ARCHAEOLOGY = (
    (re.compile(r"\b20\d\d-\d\d-\d\d\b"),
     "a date literal dates the page; say what is true instead of when it became true"),
    (re.compile(r"\bdirectors?\b", re.I),
     "names an internal reviewer; state the rule, not who asked for it"),
    (re.compile(r"\brulings?\b", re.I),
     "internal process vocabulary; call it a rule, or just state it"),
    (re.compile(r"\bmissions?\b", re.I),
     "internal process vocabulary; say what the work produced"),
)

MAX_INSTRUCTION_WORDS = 20
MAX_SENTENCE_WORDS = 25

COMMON = {
    "UI", "API", "ID", "IDS", "URL", "URI", "JSON", "XML", "HTML", "CSS",
    "CPU", "GPU", "RAM", "KB", "MB", "GB", "MS", "FPS", "DPI", "PPI", "RGB",
    "HTTP", "HTTPS", "IP", "USB", "TV", "VR", "AR", "OS", "PNG", "JPG", "SVG",
    "ASCII", "UTF", "LZ", "CSV", "CLI", "SDK", "IDE", "HUD", "TODO",
    "FAQ", "WASD", "DPAD", "LED", "AI", "NPC",
}

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

SHORTHAND_ALLOW = {
    "L1": "a gamepad shoulder button",
    "L2": "a gamepad trigger",
    "R1": "a gamepad shoulder button",
    "R2": "a gamepad trigger",
    "F6": "a keyboard function key",
    "F10": "a keyboard function key",
    "P1": "a display resolution class in the device matrix",
    "UTF8": "a text encoding",
    "UTF-8": "a text encoding",
    "UTF-16": "a text encoding",
}

SHORTHAND = re.compile(r"\b([A-Z]{1,5})-?([A-Z]?\d{1,3})\b")

ACRONYM = re.compile(r"\b([A-Z]{2,6})\b")

PASSIVE = re.compile(
    r"\b(?:is|are|was|were|be|been|being)\s+(?:\w+ly\s+)?(\w+(?:ed|en))\b",
    re.IGNORECASE,
)

PASSIVE_SKIP = {"used", "based", "named", "called", "fixed", "closed", "open",
                "needed", "allowed", "supposed", "intended", "limited"}


def documents(repo_root=REPO):
    found = []
    for rel in SCANNED_DIRS:
        root = os.path.join(repo_root, rel)
        if not os.path.isdir(root):
            continue
        for name in sorted(os.listdir(root)):
            if name.endswith(".md"):
                found.append(os.path.join(rel, name))
    for rel in SCANNED_FILES:
        if os.path.isfile(os.path.join(repo_root, rel)):
            found.append(rel)
    return found


def readable_lines(text):
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
        prose = prose.replace("**", "").replace("__", "")
        yield n, prose


def words(text):
    return re.findall(r"[A-Za-z0-9][A-Za-z0-9'/._-]*", text)


def expansion_lines(readable):
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
                reported.add(token)

        for match in SHORTHAND.finditer(prose):
            token = match.group(0)
            stem = match.group(1)
            if token in SHORTHAND_ALLOW or stem in SHORTHAND_ALLOW:
                continue
            if token.upper() in COMMON:
                continue
            fails.append(f"{path}:{n}: '{token}' is internal shorthand (an artifact "
                         "row, phase or finding code). Say what it means, or put an "
                         "exact identifier in inline code")

        step = re.match(r"^\s*\d+\.\s+(\S.*)$", prose)
        if step is not None:
            count = len(words(step.group(1)))
            if count > MAX_INSTRUCTION_WORDS:
                fails.append(f"{path}:{n}: numbered step is {count} words "
                             f"(limit {MAX_INSTRUCTION_WORDS}). Split it so each "
                             "step carries one instruction")

        if path.startswith("docs/guide/") and path not in ARCHAEOLOGY_EXEMPT:
            for pattern, why in ARCHAEOLOGY:
                found = pattern.search(prose)
                if found is not None:
                    fails.append(f"{path}:{n}: '{found.group(0)}' — {why}")

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
    for path in documents(root):
        full = os.path.join(root, path)
        if not os.path.isfile(full):
            continue
        with open(full, encoding="utf-8", errors="replace") as handle:
            check_document(path, handle.read(), fails, warns)
    return fails, warns


def probe_fails(probe_root, probe, body):
    with open(probe, "w") as handle:
        handle.write("# Probe\n\n" + body)
    fails, _warns = run(probe_root)
    return [f for f in fails if "style_probe_tmp" in f]


def selftest():
    red = [
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
        ("a bare contract id",
         "The contract themes-P5-41 still fails.\n",
         "internal shorthand"),
        ("a date literal in a guide chapter",
         "The default flipped on 2026-08-21 and has stayed that way.\n",
         "a date literal dates the page"),
        ("an internal reviewer named in a guide chapter",
         "The director asked for the taller row, so the theme grew one.\n",
         "names an internal reviewer"),
    ]
    green = [
        ("an identifier in inline code",
         "The contract `themes-P5-41` and the blocker `B1` still fail.\n"),
        ("a standard text encoding",
         "The tool reads each file as UTF-8 text.\n"),
    ]
    with tempfile.TemporaryDirectory(prefix="facet-doc-style-") as probe_root:
        probe = os.path.join(probe_root, "docs", "guide", "style_probe_tmp.md")
        os.makedirs(os.path.dirname(probe))
        for name, body, needle in red:
            fails = probe_fails(probe_root, probe, body)
            if not [f for f in fails if needle in f]:
                print(f"check_doc_style: SELFTEST FAIL — {name} was not reported")
                return 1
        for name, body in green:
            fails = probe_fails(probe_root, probe, body)
            if fails:
                print(f"check_doc_style: SELFTEST FAIL — {name} was reported:")
                print("\n".join(fails))
                return 1
    fails, warns = run()
    if fails:
        print("check_doc_style: SELFTEST FAIL — the working tree is not clean:")
        print("\n".join(fails[:20]))
        return 1
    print(f"check_doc_style: SELFTEST PASS — {len(red)} planted violations were "
          f"reported, {len(green)} valid forms passed, and the working tree is "
          f"clean ({len(warns)} warnings, which never fail)")
    return 0


def main():
    unknown = [a for a in sys.argv[1:] if a not in ("--selftest", "--warnings")]
    if unknown:
        print(USAGE)
        sys.exit(2)
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
          "instruction step, no unexpanded acronym, no internal shorthand, no "
          "maintainer archaeology in the guide "
          f"({len(warns)} warnings, reported with --warnings and never fatal)")


if __name__ == "__main__":
    main()
