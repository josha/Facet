#!/usr/bin/env python3


import argparse
import hashlib
import json
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





TEXT_SUFFIXES = (".luau", ".lua", ".md", ".json", ".txt", ".sh", ".py", ".toml", ".yml", ".yaml")
SKIP_DIRS = {".git", "node_modules", "__pycache__", "build", ".venv"}



WORDS_DIR = os.path.join("examples", "gallery", "examples", "words")







RULES = (
    ("removed-module", re.compile(r"fusion_adapter|fusion_headless|fusion_lune_external")),
    ("vendored-path", re.compile(r"vendor/Fusion")),
    ("require", re.compile(r"""require\s*\(\s*["'][^"']*fusion[^"']*["']""", re.IGNORECASE)),
    ("identifier", re.compile(r"\bFusion\b")),
)





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

    for path, allowed_rule, _reason, _removal in ALLOWLIST:
        if label == path and rule == allowed_rule:
            return True
    return False


def excluded(rel):

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

    found = []
    for base, dirs, _names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        if os.path.relpath(base, root).replace(os.sep, "/") == "artifacts/verify":
            dirs[:] = [d for d in dirs if d != "tmp"]
        for name in list(dirs):
            if name == "vendor":
                found.append(os.path.relpath(os.path.join(base, name), label_root).replace(os.sep, "/"))
    return sorted(found)


def build_model_xml(work):

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
        if found != "src/vendor":
            problems.append(f"{found}: unexpected vendor directory")
    vendor = os.path.join(REPO, "src", "vendor")
    if os.path.isdir(vendor):
        if set(os.listdir(vendor)) != {"compose"}:
            problems.append("src/vendor: only the pinned Compose dependency is approved")
        compose = os.path.join(vendor, "compose")
        try:
            pin = json.load(open(os.path.join(compose, "UPSTREAM.lock")))
            expected = set(pin["sha256"]) | {"UPSTREAM.lock", "README.md"}
            actual = {os.path.relpath(os.path.join(base, name), compose).replace(os.sep, "/")
                      for base, _, names in os.walk(compose) for name in names}
            if actual != expected:
                problems.append("Compose: unlisted or missing files")
            for name, digest in pin["sha256"].items():
                with open(os.path.join(compose, name), "rb") as source:
                    if hashlib.sha256(source.read()).hexdigest() != digest:
                        problems.append(f"Compose: source integrity mismatch for {name}")
        except (OSError, ValueError, KeyError) as error:
            problems.append(f"Compose: missing or invalid pin: {error}")

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



        "a require string that names it only in lower case",
        "planted_lowercase.luau",
        'local shim = require("../lib/fusion_shim")\n',
        "require",
    ),
    (
        "a clean file that says 'confusion' (must NOT fire)",
        "clean.luau",
        '-- the confusion this fixture exists to not report\nlocal core = require("../src/core/services")\n',
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


        os.makedirs(os.path.join(work, "nested", "vendor"))
        found = vendor_directories(work, work)
        good = found == ["nested/vendor"]
        print(f"  [{'BITES' if good else 'WRONG'}] a vendor/ directory is found by name (got {found})")
        ok = ok and good



        os.makedirs(os.path.join(work, "artifacts", "verify", "tmp", "case", "src", "vendor"))
        os.makedirs(os.path.join(work, "artifacts", "shipped", "vendor"))
        found = vendor_directories(work, work)
        good = found == ["artifacts/shipped/vendor", "nested/vendor"]
        print(f"  [{'SCOPED' if good else 'WRONG'}] only verification scratch copies are excluded (got {found})")
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
        print("  ...and any vendor directory except the pinned src/vendor/compose dependency.")
        print("  Temporary source copies under artifacts/verify/tmp are excluded; built models are scanned separately.")
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
    print("check_no_fusion: retired dependency absent; approved Compose files match their integrity pin")
    raise SystemExit(0)


if __name__ == "__main__":
    main()
