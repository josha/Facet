#!/usr/bin/env python3
"""check_no_fusion — Facet's reactive core is its own, and this is what says so.

THE CLAIM. No Facet runtime, Roblox Package, example, skill, test, benchmark, or
Rascal Rally file requires or depends on Fusion, and no vendored copy of it (or
of anything else) is in the tree. Facet was once benchmarked against a thin
adapter over a vendored Fusion 0.3 (ADR-0002 chose the custom core over it); the
adapter, the vendored copy and the comparison documents were removed on
2026-08-30 and archived privately with checksums. This check is what keeps their
absence a rule rather than a fact about one afternoon.

WHY A NAME CHECK AND NOT A REQUIRE-GRAPH WALK. A require graph proves what runs.
It cannot see a dangling `vendor/Fusion` path in a comment that sends the next
author looking for a directory that is gone, and it cannot see a file that never
gets required but DOES get packaged — which is the specific accident this stage
exists to prevent: `tools/build_model.sh` maps all of `src/`, so a module nothing
imports still ships. So this reads NAMES, in sources AND in the built artifact.

WHAT IT SCANS

  * `src/`, `examples/`, `skills/`, `tests/`, `bench/`, `package/` in this
    repository (the last three of those may not exist yet; a missing root is
    reported and skipped, never silently passed);
  * THE BUILT MODEL — every script `Source` inside a `.rbxmx` twin of
    `build/Facet.rbxm`, built through `tools/build_model.sh` so it is the same
    Rojo mapping the distribution uses. A binary `.rbxm` is LZ4-chunked and a
    byte grep over it proves nothing; `tools/check_library_purity.py` learned
    this first and its `model_scripts` reader is imported here rather than
    rewritten, so the two checks cannot disagree about what "the model" is;
  * `games/RascalRally/code/{src,tests}` — the production consumer — when that
    directory is present. When it is not (a clone without the game beside it),
    that is reported as a SKIP and does not pass silently.

WHAT COUNTS AS A VIOLATION

  * `Fusion` as a whole word, CASE-SENSITIVE. Case-sensitive is load-bearing:
    `confusion` contains the letters and is ordinary English this repository
    uses in a dozen comments. Word-bounded, so `Fusions` and `FusionLike` are
    caught but `confusion` is not;
  * the removed module names `fusion_adapter`, `fusion_headless`,
    `fusion_lune_external`, and the path `vendor/Fusion`;
  * any require whose string contains `fusion` in any case;
  * any `vendor/` DIRECTORY anywhere in the tree. There is no vendored
    third-party source in this repository and there is not going to be one.

COMMENTS ARE NOT EXEMPT, and that is the opposite of `check_library_purity`'s
rule for theme-package names — deliberately. There, a comment naming a package
is a measured story and creates no dependency. Here, the name must not be in the
distribution at all: a comment citing a document that was removed sends a reader
to nothing, and a comment naming a vendored directory that is gone is worse than
useless. Rewrite the comment in Facet's own terms.

THE ONE STRUCTURAL EXCLUSION. `examples/gallery/examples/words/*.luau` are SCOWL
word lists — dictionary DATA for the word-game example — and the English word
"fusion" is in them. They are excluded by path rather than by pattern, because
the exclusion is about what the file IS, and a pattern narrow enough to excuse a
dictionary entry would be wide enough to excuse a real reference.

...AND TWO ALLOWED MENTIONS, each one path plus one rule, with its reason and the
condition that removes it (ALLOWLIST below). Both are the same shape as
`check_brand_drift`'s: a guard's own match data, and the one document a comparison
is allowed to live in. An allowed mention creates no dependency and sends no
reader anywhere that is gone — which is what the other rules are about. The
selftest plants an allowlisted pattern in a NON-allowlisted file, so an entry
cannot quietly widen past its own path.

    python3 tools/check_no_fusion.py [--selftest] [--skip-build] [--list]

`--selftest` builds a throwaway tree with a planted require, a planted bare
identifier and one clean file that says `confusion` on purpose, and requires all
three to behave. Nothing is planted in this repository's working tree.

Exit 0 = clean; 1 = violations; 2 = environment failure.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from check_library_purity import BUILD_MODEL, env, model_scripts  # noqa: E402

REPO = os.path.dirname(HERE)
RR = os.path.normpath(os.path.join(REPO, "..", "..", "..", "games", "RascalRally", "code"))

SCAN_ROOTS = ("src", "examples", "skills", "tests", "bench", "package")
RR_ROOTS = ("src", "tests")

# read every text file, not only Luau: a Fusion name in a JSON manifest, a
# markdown page under examples/, or a shell script is the same dangling
# reference. Binaries (.rbxl places, images, fonts) are skipped — they are
# built artifacts whose INPUTS are scanned instead.
TEXT_SUFFIXES = (".luau", ".lua", ".md", ".json", ".txt", ".sh", ".py", ".toml", ".yml", ".yaml")
SKIP_DIRS = {".git", "node_modules", "__pycache__", "build", ".venv"}

# SCOWL word-list data for the word-game example: the English word "fusion" is a
# dictionary entry, not a reference. Excluded by path, never by pattern.
WORDS_DIR = os.path.join("examples", "gallery", "examples", "words")

# ORDER IS REPORT ORDER, MOST SPECIFIC FIRST. A line is reported once, under the
# narrowest rule that sees it: `vendor/Fusion` is a vendored path rather than a
# bare identifier, and `require("…fusion…")` is a require rather than nothing at
# all. Putting the broad identifier rule first would make the other three
# unreachable on most real lines — and a rule that can never be the reported one
# is a rule nobody can prove still works.
RULES = (
    ("removed-module", re.compile(r"fusion_adapter|fusion_headless|fusion_lune_external")),
    ("vendored-path", re.compile(r"vendor/Fusion")),
    ("require", re.compile(r"""require\s*\(\s*["'][^"']*fusion[^"']*["']""", re.IGNORECASE)),
    ("identifier", re.compile(r"\bFusion\b")),
)

#[[ THE ALLOWED MENTIONS: (path, rule, reason, removal). A match is excused only
#   when BOTH the path and the rule name agree, so a different kind of Fusion
#   reference in the same file is still reported. Nothing here is a dependency
#   and nothing here points at a file that was removed. ]]
ALLOWLIST = (
    (
        "tests/theme_docs.spec.luau",
        "identifier",
        "the fixture for docs/guide/14-choosing-a-ui-library.md, the ONE public document allowed to "
        "compare Facet with other Roblox UI libraries (owner ruling, 2026-08-30: it may describe them "
        "as separate alternatives, and must never call any of them Facet's foundation). A comparison "
        "fixture that cannot name what it compares proves nothing.",
        "when the comparison document stops naming the projects it compares",
    ),
    (
        "package/README.md",
        "removed-module",
        "the package verifier's own DENY LIST, written out in prose: these are the path components "
        "`tools/package.py` refuses to ship. Naming a forbidden token is the opposite of depending on it.",
        "when the package verifier drops the token from its deny list",
    ),
)


def allowed(label, rule):
    """Is this (path, rule) pair one of the named, reasoned exceptions?"""
    for path, allowed_rule, _reason, _removal in ALLOWLIST:
        if label == path and rule == allowed_rule:
            return True
    return False


def excluded(rel):
    """Is this repo-relative path structurally out of scope?"""
    rel = rel.replace(os.sep, "/")
    return rel.startswith(WORDS_DIR.replace(os.sep, "/") + "/")


def scan_text(label, text, problems):
    for number, line in enumerate(text.splitlines(), start=1):
        for rule, pattern in RULES:
            if pattern.search(line):
                if not allowed(label, rule):
                    problems.append(f"{label}:{number}: [{rule}] {line.strip()[:160]}")
                break


def scan_tree(root, label_root, problems, exclude_words=False):
    """Every text file under `root`. Returns the number of files read."""
    read = 0
    for base, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(names):
            path = os.path.join(base, name)
            if not name.endswith(TEXT_SUFFIXES):
                continue
            rel = os.path.relpath(path, label_root).replace(os.sep, "/")
            if exclude_words and excluded(rel):
                continue
            try:
                with open(path, encoding="utf-8", errors="replace") as handle:
                    text = handle.read()
            except OSError as error:
                problems.append(f"{rel}: unreadable ({error})")
                continue
            read += 1
            scan_text(rel, text, problems)
    return read


def vendor_directories(root, label_root):
    """Every directory named `vendor` under `root`, as repo-relative paths."""
    found = []
    for base, dirs, _names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in list(dirs):
            if name == "vendor":
                found.append(os.path.relpath(os.path.join(base, name), label_root).replace(os.sep, "/"))
    return sorted(found)


def build_model_xml(work):
    """The `.rbxmx` twin of build/Facet.rbxm, through the shipped builder."""
    out = os.path.join(work, "Facet.rbxmx")
    result = subprocess.run([BUILD_MODEL, out], cwd=REPO, env=env(), capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout + result.stderr)
        raise SystemExit(2)
    return out


def check(skip_build=False, quiet=False):
    problems, notes = [], []
    files = 0

    for root in SCAN_ROOTS:
        absolute = os.path.join(REPO, root)
        if not os.path.isdir(absolute):
            notes.append(f"SKIP  {root}/ does not exist in this repository")
            continue
        files += scan_tree(absolute, REPO, problems, exclude_words=True)

    for found in vendor_directories(REPO, REPO):
        problems.append(f"{found}: a vendor/ directory is present in the tree — Facet vendors no third-party source")

    if os.path.isdir(RR):
        for root in RR_ROOTS:
            absolute = os.path.join(RR, root)
            if not os.path.isdir(absolute):
                notes.append(f"SKIP  RascalRally {root}/ does not exist")
                continue
            files += scan_tree(absolute, os.path.dirname(RR), problems)
        for found in vendor_directories(RR, os.path.dirname(RR)):
            problems.append(f"{found}: a vendor/ directory is present in the consuming game")
    else:
        notes.append(f"SKIP  the consuming game is not beside this repository ({RR})")

    scripts = 0
    if not skip_build:
        work = tempfile.mkdtemp(prefix="facet-no-fusion-")
        try:
            for name, source in model_scripts(build_model_xml(work)):
                scripts += 1
                scan_text(f"build/Facet.rbxm:{name}", source, problems)
        finally:
            shutil.rmtree(work, ignore_errors=True)
        if scripts == 0:
            problems.append("build/Facet.rbxm: the built model contains no scripts at all — wrong artifact?")
    else:
        notes.append("SKIP  the built model (--skip-build)")

    if not quiet:
        for note in notes:
            print(f"  {note}")
        print(f"  read {files} source file(s) and {scripts} script(s) in the built model")
    return problems


# ── the negative controls ────────────────────────────────────────────────────
#
# A require and a bare identifier are the two shapes this check exists for: one
# creates a dependency, the other creates a dangling reference. The clean file
# says `confusion` on purpose — the word-boundary and case rules are the reason
# this check can be run over a repository full of English prose at all, and an
# exemption nobody watches hold quietly becomes a rule.
PLANTS = (
    (
        "a require of the vendored copy",
        "planted_require.luau",
        'local F = require("../../vendor/Fusion")\n',
        "vendored-path",
    ),
    ("a bare identifier", "planted_identifier.luau", "local value = Fusion.Value(0)\n", "identifier"),
    (
        "a comment naming a removed module",
        "planted_module.luau",
        "-- see fusion_adapter for the other arm\n",
        "removed-module",
    ),
    (
        # LOWERCASE ON PURPOSE: no other rule can see this line, so it is the
        # only plant that proves the require rule itself bites rather than
        # riding on the identifier rule.
        "a require string that names it only in lower case",
        "planted_lowercase.luau",
        'local shim = require("../lib/fusion_shim")\n',
        "require",
    ),
    (
        "a clean file that says 'confusion' (must NOT fire)",
        "clean.luau",
        '-- the confusion this fixture exists to not report\nlocal core = require("../src/core/custom")\n',
        None,
    ),
)


def selftest():
    work = tempfile.mkdtemp(prefix="facet-no-fusion-selftest-")
    ok = True
    try:
        for _label, name, body, _rule in PLANTS:
            with open(os.path.join(work, name), "w") as handle:
                handle.write(body)
        problems = []
        scan_tree(work, work, problems)
        for label, name, _body, rule in PLANTS:
            mine = [problem for problem in problems if problem.startswith(name + ":")]
            if rule is None:
                good = not mine
                verdict = "CLEAN" if good else "WRONG"
            else:
                good = len(mine) == 1 and f"[{rule}]" in mine[0]
                verdict = "BITES" if good else "WRONG"
            print(f"  [{verdict}] {label}")
            for problem in mine:
                print(f"      -> {problem}")
            ok = ok and good

        # ...AND THE ALLOWLIST IS SCOPED TO ITS PATH. The same pattern, in a
        # file that is not the excused one, must still be reported — otherwise
        # an entry written for one document silently excuses the whole tree.
        for path, rule, _reason, _removal in ALLOWLIST:
            pattern = dict(RULES)[rule]
            sample = "vendor/Fusion" if rule == "vendored-path" else ("Fusion" if rule == "identifier" else "fusion_adapter")
            assert pattern.search(sample), sample
            excused, elsewhere = [], []
            scan_text(path, sample, excused)
            scan_text("some/other/file.luau", sample, elsewhere)
            good = not excused and len(elsewhere) == 1
            print(f"  [{'SCOPED' if good else 'WRONG'}] {path} [{rule}] is excused THERE and nowhere else")
            ok = ok and good

        # ...and the directory rule, which no file content can express
        os.makedirs(os.path.join(work, "nested", "vendor"))
        found = vendor_directories(work, work)
        good = found == ["nested/vendor"]
        print(f"  [{'BITES' if good else 'WRONG'}] a vendor/ directory is found by name (got {found})")
        ok = ok and good
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--skip-build", action="store_true", help="scan sources only (no rojo build)")
    parser.add_argument("--list", action="store_true", help="print what this check refuses, and where")
    args = parser.parse_args()

    if args.list:
        print("check_no_fusion refuses, in sources AND in the built model:")
        for rule, pattern in RULES:
            print(f"  {rule}: {pattern.pattern}")
        print("  ...and any directory named 'vendor' anywhere in the tree.")
        print("allowed mentions (path + rule, with the reason and what removes it):")
        for path, rule, reason, removal in ALLOWLIST:
            print(f"  {path} [{rule}]")
            print(f"      why: {reason}")
            print(f"      removed: {removal}")
        print("scanned roots: " + ", ".join(f"{root}/" for root in SCAN_ROOTS))
        print(f"               the built model, and {RR}/{{src,tests}} when present")
        print(f"structurally excluded: {WORDS_DIR}/ (SCOWL dictionary data)")
        raise SystemExit(0)

    if args.selftest:
        print("check_no_fusion --selftest")
        raise SystemExit(0 if selftest() else 1)

    problems = check(skip_build=args.skip_build)
    if problems:
        print(f"check_no_fusion: {len(problems)} violation(s)")
        for problem in problems:
            print(f"  {problem}")
        raise SystemExit(1)
    print("check_no_fusion: no Fusion name, require, path or vendored directory in the sources, the built model, or the game")
    raise SystemExit(0)


if __name__ == "__main__":
    main()
