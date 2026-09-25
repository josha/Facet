#!/usr/bin/env python3


import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from strip_comments import strip_luau as strip_luau_comments

REPO = os.path.dirname(HERE)
SRC = os.path.join(REPO, "src")
THEMES_DIR = os.path.join(REPO, "examples", "themes")
BUILD_MODEL = os.path.join(HERE, "build_model.sh")


NEUTRAL_ID = "facet-neutral"








IDENTITY_TABLE = re.compile(r"\bidentity\s*=\s*\{", re.MULTILINE)
IDENTITY_FIELD = re.compile(r"\bid\s*=\s*\"([^\"]+)\"")
IDENTITY_ASSIGN = re.compile(r"\bidentity\.id\s*=\s*\"([^\"]+)\"")


def package_stamps(code):

    found = set(IDENTITY_ASSIGN.findall(code))
    for match in IDENTITY_TABLE.finditer(code):
        depth, i, n = 0, match.end() - 1, len(code)
        while i < n:
            if code[i] == "{":
                depth += 1
            elif code[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        field = IDENTITY_FIELD.search(code, match.end(), min(i + 1, n))
        if field:
            found.add(field.group(1))
    return found



EXAMPLE_PATHS = ("examples/themes", "examples/gallery", "examples/performance")


def env():
    e = dict(os.environ)
    e["PATH"] = os.path.expanduser("~/.rokit/bin") + ":/opt/homebrew/bin:/usr/local/bin:" + e.get("PATH", "")
    return e


def package_vocabulary(themes_dir=THEMES_DIR):

    vocab = {}
    for entry in sorted(os.listdir(themes_dir)):
        if not entry.endswith(".luau"):
            continue
        module = entry[: -len(".luau")]
        with open(os.path.join(themes_dir, entry)) as handle:
            source = handle.read()
        names = {module}
        for pattern in (r"\.id\s*=\s*\"([^\"]+)\"", r"\.displayName\s*=\s*\"([^\"]+)\""):
            match = re.search(pattern, source)
            if match:
                names.add(match.group(1))
        vocab[module] = sorted(names)
    return vocab


def patterns_for(vocab):

    out = []
    for module, names in vocab.items():
        for name in names:
            out.append((module, name, re.compile(r"(?<![\w-])" + re.escape(name) + r"(?![\w-])")))
    for path in EXAMPLE_PATHS:
        out.append((path, path, re.compile(re.escape(path))))
    return out


def scan_text(label, source, patterns, problems):
    code = strip_luau_comments(source)
    for module, name, pattern in patterns:
        for hit in pattern.finditer(code):
            line = code[: hit.start()].count("\n") + 1
            problems.append(
                f"{label}:{line}: the shipped library names '{name}' in CODE. The library is facet-neutral "
                f"and '{module}' is an optional artifact a consumer may never have installed — say what the "
                f"rule IS, or move the mention into a comment, where a measured story belongs"
            )


def scan_sources(patterns, problems, root=SRC, label_root=None):
    label_root = label_root or os.path.dirname(root)
    for base, _dirs, files in os.walk(root):
        for name in sorted(files):
            if not name.endswith(".luau"):
                continue
            path = os.path.join(base, name)
            with open(path) as handle:
                scan_text(os.path.relpath(path, label_root), handle.read(), patterns, problems)


def model_scripts(xml_path):

    out = []
    for item in ET.parse(xml_path).getroot().iter("Item"):
        props = item.find("Properties")
        if props is None:
            continue
        name, source = item.get("class"), None
        for prop in props:
            if prop.get("name") == "Name":
                name = prop.text or name
            elif prop.get("name") == "Source":
                source = prop.text
        if source:
            out.append((name, source))
    return out


def scan_model(xml_path, patterns, problems):
    stamps = set()
    for name, source in model_scripts(xml_path):
        code = strip_luau_comments(source)
        scan_text(f"build/Facet.rbxm:{name}", source, patterns, problems)
        stamps.update(package_stamps(code))
    extra = sorted(stamps - {NEUTRAL_ID})
    if NEUTRAL_ID not in stamps:
        problems.append(
            f"build/Facet.rbxm: the model carries no '{NEUTRAL_ID}' package stamp at all — either the neutral "
            f"package left the library or this check is looking at the wrong artifact"
        )
    for slug in extra:
        problems.append(
            f"build/Facet.rbxm: the model stamps a second package, '{slug}'. Facet Neutral is the only theme "
            f"the library ships; every other package is its own artifact under build/themes/"
        )
    return stamps


def check(src_root=SRC, model_xml=None, skip_build=False, themes_dir=THEMES_DIR):
    problems = []
    patterns = patterns_for(package_vocabulary(themes_dir))
    scan_sources(patterns, problems, root=src_root, label_root=os.path.dirname(src_root))

    temp = None
    try:
        if model_xml is None and not skip_build:
            temp = tempfile.mkdtemp(prefix="facet-purity-")
            model_xml = os.path.join(temp, "Facet.rbxmx")
            result = subprocess.run(
                [BUILD_MODEL, model_xml], cwd=REPO, env=env(), capture_output=True, text=True
            )
            if result.returncode != 0:
                sys.stderr.write(result.stdout + result.stderr)
                raise SystemExit(2)
        if model_xml is not None:
            scan_model(model_xml, patterns, problems)
    finally:
        if temp:
            shutil.rmtree(temp, ignore_errors=True)
    return problems







PLANTS = (
    (
        "a require of a reference package in src/",
        "src",
        lambda source: 'local ornate = require("../../examples/themes/fantasy_ornate")\n' + source,
        "names 'fantasy_ornate' in CODE",
        True,
    ),
    (
        "a package id inside a diagnostic STRING",
        "src",
        lambda source: source.replace(
            "local package = {}",
            'local package = {}\nlocal HINT = "copy the pixel-quest package and edit it"',
            1,
        ),
        "names 'pixel-quest' in CODE",
        True,
    ),
    (
        "a package id inside a COMMENT (the exemption — this must NOT fire)",
        "src",
        lambda source: "-- measured live under fantasy-ornate at 1.5x: the frame did not move\n" + source,
        "fantasy-ornate",
        False,
    ),
    (




        "a second package stamp in the built model",
        "model",
        lambda source: source.replace(
            '<string name="Source">',
            '<string name="Source">local bundled = { identity = { id = "another-shipped-theme" } }\n',
            1,
        ),
        "stamps a second package, 'another-shipped-theme'",
        True,
    ),
)


def selftest():
    clean = check()
    if clean:
        print("SELFTEST FAILED: the tree is already red:")
        for problem in clean:
            print(f"  - {problem}")
        return False
    print("  selftest control: src/ and the built model are clean")

    work = tempfile.mkdtemp(prefix="facet-purity-selftest-")
    ok = True
    try:
        scratch_src = os.path.join(work, "src")
        shutil.copytree(SRC, scratch_src)
        model_xml = os.path.join(work, "Facet.rbxmx")
        result = subprocess.run([BUILD_MODEL, model_xml], cwd=REPO, env=env(), capture_output=True, text=True)
        if result.returncode != 0:
            sys.stderr.write(result.stdout + result.stderr)
            return False
        target_src = os.path.join(scratch_src, "themes", "package.luau")
        with open(target_src) as handle:
            pristine_src = handle.read()
        with open(model_xml) as handle:
            pristine_model = handle.read()

        for label, where, plant, expect, must_fire in PLANTS:
            if where == "src":
                with open(target_src, "w") as handle:
                    handle.write(plant(pristine_src))
                problems = check(src_root=scratch_src, skip_build=True)
                with open(target_src, "w") as handle:
                    handle.write(pristine_src)
            else:
                planted = os.path.join(work, "planted.rbxmx")
                with open(planted, "w") as handle:
                    handle.write(plant(pristine_model))
                problems = check(src_root=scratch_src, model_xml=planted)

            matched = [problem for problem in problems if expect in problem]
            fired = bool(matched)
            good = fired == must_fire
            verdict = "BITES" if (fired and must_fire) else ("EXEMPT" if (not fired and not must_fire) else "WRONG")
            print(f"  [{verdict}] {label}")
            for problem in matched[:1]:
                print(f"      -> {problem}")
            if not good:
                ok = False
                for problem in problems[:3]:
                    print(f"      {problem}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--list", action="store_true", help="print the derived vocabulary and exit")
    parser.add_argument("--skip-build", action="store_true", help="scan src/ only (no rojo)")
    args = parser.parse_args()

    if args.list:
        print("check_library_purity forbids these identifiers in the library's CODE (comments exempt):")
        for module, names in sorted(package_vocabulary().items()):
            print(f"  {module}: {', '.join(names)}")
        print("  plus any of: " + ", ".join(EXAMPLE_PATHS))
        print(f"  ...and the only package stamp the model may carry is '{NEUTRAL_ID}'.")
        print("")
        print("REWRITTEN RATHER THAN ALLOWLISTED (wave THEME-UNBUNDLE, 2026-08-21):")
        print("  src/themes/package.luau's identity.id hint used 'fantasy-parchment' as its example slug;")
        print("  its barFill refusal sent the reader to examples/themes/glossy_touch.luau, a file that is")
        print("  not in the distribution. Both now state the rule instead of naming a package.")
        raise SystemExit(0)

    if args.selftest:
        print("check_library_purity --selftest")
        raise SystemExit(0 if selftest() else 1)

    problems = check(skip_build=args.skip_build)
    if problems:
        print(f"check_library_purity: {len(problems)} problem(s)")
        for problem in problems:
            print(f"  - {problem}")
        raise SystemExit(1)
    print("check_library_purity: src/ and build/Facet.rbxm name no reference theme package in code")
    raise SystemExit(0)


if __name__ == "__main__":
    main()
