#!/usr/bin/env python3
"""Rename inventory: every form of the old brand 'LuauUI' across the studio.

Scans tracked files of both git repos plus the untracked studio surfaces that
reference the framework. Emits JSON (machine-readable, recounted after the
rename) and a human summary. Classification is by path rule; persistent-name
candidates are flagged by content pattern for manual review.
"""
import json, os, re, subprocess, sys, unicodedata
from collections import defaultdict

ROOT = "/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame"
LUAUUI = os.path.join(ROOT, "GameStudio/ui/LuauUI")
FACET = os.path.join(ROOT, "GameStudio/ui/Facet")
REPO_UI = FACET if os.path.isdir(FACET) else LUAUUI
RR = os.path.join(ROOT, "games/RascalRally/code")

# Any case of: luauui, luau-ui, luau_ui, luau.ui, "luau ui" (word-bounded)
PAT = re.compile(r"luau[\s._-]?ui", re.IGNORECASE)

BINARY_EXT = {".rbxl", ".rbxm", ".rbxlx", ".png", ".jpg", ".jpeg", ".gif", ".gprx",
              ".zip", ".ttf", ".otf", ".pyc", ".webp", ".mp4", ".mov", ".pdf"}

def git_files(repo):
    out = subprocess.run(["git", "-C", repo, "ls-files"], capture_output=True, text=True)
    return [os.path.join(repo, f) for f in out.stdout.splitlines() if f]

def classify(path):
    rel = os.path.relpath(path, ROOT)
    p = rel.replace("\\", "/")
    if "/artifacts/" in p or p.startswith("GameStudio/ui/LuauUI/artifacts") \
       or p.startswith("GameStudio/ui/Facet/artifacts"):
        return "immutable-evidence"
    if "/build/" in p or p.endswith((".rbxl", ".rbxm", ".rbxlx")) or "/places/" in p:
        return "generated-output"
    if "/docs/lessons/" in p or "/docs/superpowers/" in p or "/playtests/" in p:
        return "immutable-evidence"
    return "current-source"

def scan_file(path):
    ext = os.path.splitext(path)[1].lower()
    base_hits = len(PAT.findall(os.path.basename(path)))
    if ext in BINARY_EXT:
        try:
            with open(path, "rb") as f:
                data = f.read()
            content_hits = len(PAT.findall(data.decode("latin-1")))
        except OSError:
            content_hits = -1
        return base_hits, content_hits, "binary"
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        return base_hits, len(PAT.findall(text)), "text"
    except OSError:
        return base_hits, -1, "unreadable"

def main():
    files = git_files(REPO_UI) + git_files(RR)
    # Untracked studio surfaces that name the framework
    extra_roots = [
        os.path.join(ROOT, ".claude/agents"),
        os.path.join(ROOT, "GameStudio/specialists"),
        os.path.join(ROOT, "games/RascalRally/docs"),
    ]
    extra_files = [os.path.join(ROOT, "CLAUDE.md"),
                   os.path.join(ROOT, "games/RascalRally/CLAUDE.md")]
    for r in extra_roots:
        for dirpath, _dirs, names in os.walk(r):
            for n in names:
                extra_files.append(os.path.join(dirpath, n))
    files += [f for f in extra_files if os.path.isfile(f)]

    rows, totals = [], defaultdict(int)
    for f in sorted(set(files)):
        name_hits, content_hits, kind = scan_file(f)
        if name_hits == 0 and content_hits <= 0:
            continue
        cls = classify(f)
        rel = os.path.relpath(f, ROOT)
        rows.append({"path": rel, "class": cls, "kind": kind,
                     "path_matches": name_hits, "content_matches": content_hits})
        totals[cls] += max(content_hits, 0) + name_hits
        totals["files"] += 1

    # Persistent/external identifier candidates: old name near storage APIs
    persist = []
    store_pat = re.compile(
        r"(DataStore|SetAttribute|GetAttribute|MemoryStore|MessagingService|"
        r"AnalyticsService|SetAsync|PolicyService|TeleportData)", re.I)
    for row in rows:
        if row["kind"] != "text" or row["content_matches"] <= 0:
            continue
        full = os.path.join(ROOT, row["path"])
        try:
            with open(full, "r", encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    if PAT.search(line) and store_pat.search(line):
                        persist.append({"path": row["path"], "line": i,
                                        "text": line.strip()[:200]})
        except OSError:
            pass

    out = {"pattern": PAT.pattern, "root": ROOT,
           "totals": dict(totals), "persistent_candidates": persist, "rows": rows}
    dest = sys.argv[1] if len(sys.argv) > 1 else "rename-inventory-before.json"
    with open(dest, "w") as f:
        json.dump(out, f, indent=1)
    print(f"files-with-matches={totals['files']}")
    for k in ("current-source", "generated-output", "immutable-evidence"):
        print(f"{k}={totals[k]}")
    print(f"persistent-candidates={len(persist)}")
    print(f"wrote {dest}")

if __name__ == "__main__":
    main()
