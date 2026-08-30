#!/usr/bin/env python3
"""check_public_allowlist — every tracked path on the branch tip must be allowed.

The public repository boundary is an EXACT allowlist (tools/public_allowlist.txt),
not a denylist: a new internal file lands outside the allowed set by default and
this check names it, so private material cannot drift back into the public tip
one file at a time.

    python3 tools/check_public_allowlist.py            # check `git ls-files`; exit 1 on any stray
    python3 tools/check_public_allowlist.py --report   # list strays grouped by top-level dir, exit 0
    python3 tools/check_public_allowlist.py --selftest # a planted stray must be caught, a clean list must pass

Rules: a pattern ending in "/" allows the directory tree; any other pattern is an
exact path or an fnmatch glob against the repo-relative path; a "!" pattern denies
even inside an allowed tree (denies are evaluated after allows). Paths are
compared exactly as `git ls-files` prints them (LF, forward slashes).
"""
from __future__ import annotations
import fnmatch, os, subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIST = ROOT / "tools" / "public_allowlist.txt"


def load(text: str) -> tuple[list[str], list[str]]:
    allows, denies = [], []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        (denies if line.startswith("!") else allows).append(line.lstrip("!"))
    return allows, denies


def matches(path: str, pattern: str) -> bool:
    if pattern.endswith("/"):
        return path.startswith(pattern)
    if path == pattern:
        return True
    return fnmatch.fnmatchcase(path, pattern)


def strays(paths: list[str], allows: list[str], denies: list[str]) -> list[str]:
    out = []
    for p in paths:
        allowed = any(matches(p, a) for a in allows)
        denied = any(matches(p, d) for d in denies)
        if not allowed or denied:
            out.append(p)
    return out


def tracked() -> list[str]:
    res = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True)
    return [p for p in res.stdout.decode("utf-8").split("\0") if p]


def selftest() -> int:
    allows, denies = load("src/\nREADME.md\n!src/core/fusion_adapter.luau\n")
    clean = ["src/init.luau", "README.md", "src/core/custom.luau"]
    planted = clean + ["docs/plans/secret-plan.md", "src/core/fusion_adapter.luau"]
    ok = strays(clean, allows, denies) == [] and strays(planted, allows, denies) == [
        "docs/plans/secret-plan.md",
        "src/core/fusion_adapter.luau",
    ]
    print("check_public_allowlist selftest:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    allows, denies = load(LIST.read_text())
    bad = strays(tracked(), allows, denies)
    if "--report" in argv:
        groups: dict[str, list[str]] = {}
        for p in bad:
            groups.setdefault(p.split("/", 1)[0], []).append(p)
        for top, items in sorted(groups.items()):
            print(f"{top}: {len(items)} path(s)")
            for p in items[:12]:
                print(f"  {p}")
            if len(items) > 12:
                print(f"  … {len(items) - 12} more")
        print(f"strays: {len(bad)}")
        return 0
    if bad:
        for p in bad:
            print(f"not allowed on the public tip: {p}")
        print(f"check_public_allowlist: FAIL ({len(bad)} stray path(s); archive them with tools/archive_private.py or extend tools/public_allowlist.txt with a reason)")
        return 1
    print("check_public_allowlist: PASS (every tracked path is allowed)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
