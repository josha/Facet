#!/usr/bin/env python3
CLI_HELP = """relink_archived — turn links into privately archived material into plain text.

WHY THIS EXISTS. Some material does not go public: the decision records, the
written-up defects, the internal plans, the handoff notes, the raw research
files, the stage evidence, and the comparison documents that move into the
private archive. A link whose target is not in the repository is worse than no
link: a reader clicks it, gets a 404, and learns nothing about why the sentence
is true.

The repair is mechanical and deliberately minimal. A markdown link whose target
is in the archived set becomes:

    <link text> `<old path>` (archived privately)

...and nothing else on the line changes. The sentence keeps its wording and its
citation; only the false promise that you can open the file goes away. When the
link text is itself the path in a code span, the path is not repeated.

Usage:
    python3 tools/relink_archived.py --check   # report every offender, exit 1 if any
    python3 tools/relink_archived.py --fix     # rewrite them, print before/after counts

Exit 0 = clean (or fixed); 1 = offenders found by --check; 2 = bad invocation.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)




SCANNED_DIRS = ("docs/guide", "docs/extending", "docs/reference")



ARCHIVED_PREFIXES = (
    "docs/adr/",
    "docs/lessons/",
    "docs/plans/",
    "docs/handoff/",
    "docs/research/",
    "artifacts/",
    ".superpowers/",
    "vendor/",
)
ARCHIVED_FILES = (
    "docs/INVENTORY.md",
    "ui_todo.md",
    "sweep.luau",
)







PUBLIC_REFERENCE = (
    "docs/reference/api.md",
    "docs/reference/constitution.md",
)

NOTE = "(archived privately)"



LINK = re.compile(r"\[((?:[^\[\]]|\[[^\[\]]*\])*)\]\(([^)\s]+)(\s+\"[^\"]*\")?\)")


def normalize(path: str) -> str:

    parts: list = []
    for part in path.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if parts:
                parts.pop()
            continue
        parts.append(part)
    return "/".join(parts)


def is_archived(target: str, doc_rel: str) -> bool:
    if target.startswith(("http://", "https://", "mailto:", "#")):
        return False
    path = target.split("#", 1)[0]
    if path == "":
        return False
    if path.startswith("/"):
        resolved = normalize(path.lstrip("/"))
    else:
        resolved = normalize(os.path.dirname(doc_rel) + "/" + path)
    if resolved in ARCHIVED_FILES:
        return True
    if resolved.startswith("docs/reference/") and resolved not in PUBLIC_REFERENCE:
        return True
    return any(resolved.startswith(prefix) for prefix in ARCHIVED_PREFIXES)


def resolve(path: str, doc_rel: str) -> str:

    if path.startswith("/"):
        return normalize(path.lstrip("/"))
    return normalize(os.path.dirname(doc_rel) + "/" + path)


def replacement(label: str, target: str, doc_rel: str) -> str:

    path_only = target.split("#", 1)[0]
    shown = resolve(path_only, doc_rel)
    bare = label.strip().strip("`").strip()
    same_path = bare in (target, path_only, os.path.basename(path_only), shown) or (
        "/" in bare and resolve(bare, doc_rel) == shown
    )
    if same_path:
        return f"`{shown}` {NOTE}"
    return f"{label} `{shown}` {NOTE}"


def documents():

    found = []
    for rel in SCANNED_DIRS:
        root = os.path.join(REPO, rel)
        if not os.path.isdir(root):
            continue
        for name in sorted(os.listdir(root)):
            if not name.endswith(".md"):
                continue
            doc = rel + "/" + name
            if doc.startswith("docs/reference/") and doc not in PUBLIC_REFERENCE:
                continue
            found.append(doc)
    return found


def rewrite(doc_rel: str, source: str):

    offenders = []

    def one(match):
        label, target = match.group(1), match.group(2)
        if not is_archived(target, doc_rel):
            return match.group(0)
        line = source.count("\n", 0, match.start()) + 1
        offenders.append((line, target))
        return replacement(label, target, doc_rel)

    return LINK.sub(one, source), offenders


def main(argv):
    mode = argv[1] if len(argv) == 2 else None
    if mode not in ("--check", "--fix"):
        print(CLI_HELP.strip(), file=sys.stderr)
        return 2

    total_links = 0
    total_offenders = 0
    changed_files = 0
    for doc_rel in documents():
        path = os.path.join(REPO, doc_rel)
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        total_links += len(LINK.findall(source))
        new_source, offenders = rewrite(doc_rel, source)
        if not offenders:
            continue
        total_offenders += len(offenders)
        changed_files += 1
        for line, target in offenders:
            print(f"{doc_rel}:{line}: links into archived material -> {target}")
        if mode == "--fix":
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(new_source)

    scanned = len(documents())
    if mode == "--fix":
        print(
            f"relink_archived: rewrote {total_offenders} link(s) in {changed_files} "
            f"file(s); {scanned} documents scanned, {total_links} links read"
        )
        return 0

    if total_offenders:
        print(
            f"relink_archived: FAIL — {total_offenders} link(s) into archived "
            f"material in {changed_files} file(s) of {scanned} scanned"
        )
        return 1
    print(
        f"relink_archived: PASS — {scanned} documents, {total_links} links, none "
        f"pointing into archived material"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
