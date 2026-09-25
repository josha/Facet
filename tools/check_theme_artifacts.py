#!/usr/bin/env python3


import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from strip_comments import strip_luau as strip_luau_comments  # noqa: E402

REPO = os.path.dirname(HERE)

BUILD_THEMES = os.path.join(HERE, "build_themes.sh")
MANIFEST = os.path.join(REPO, "build", "themes", "manifest.json")



COPIED_TREES = ("src",)
COPIED_FILES = (
    "rokit.toml",
    os.path.join("tests", "lib", "native_engine.luau"),
    os.path.join("tools", "lune", "theme_artifact_probe.luau"),
)

REQUIRE_CALL = re.compile(r"\brequire\s*[({\"']")


def env():
    e = dict(os.environ)
    e["PATH"] = os.path.expanduser("~/.rokit/bin") + ":/opt/homebrew/bin:/usr/local/bin:" + e.get("PATH", "")
    return e


def run(args, cwd=REPO, check=True):
    result = subprocess.run(args, cwd=cwd, env=env(), capture_output=True, text=True)
    if check and result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(2)
    return result


def build_one(source, name, out_path):
    run([BUILD_THEMES, "--one", source, name, out_path])


def artifact_source(xml_path, name, problems):

    root = ET.parse(xml_path).getroot()
    items = [child for child in root if child.tag == "Item"]
    if len(items) != 1:
        problems.append(f"{name}: the artifact holds {len(items)} root objects, expected exactly 1")
        return None
    item = items[0]
    if item.get("class") != "ModuleScript":
        problems.append(f"{name}: the artifact's root is a {item.get('class')}, not a ModuleScript")
        return None
    kids = [child for child in item if child.tag == "Item"]
    if kids:
        problems.append(
            f"{name}: the artifact's ModuleScript has {len(kids)} children — this package grew runtime data "
            f"and tools/build_themes.sh has not been taught to map it"
        )
        return None
    props = item.find("Properties")
    got_name = None
    source = None
    for prop in props if props is not None else []:
        if prop.get("name") == "Name":
            got_name = prop.text or ""
        elif prop.get("name") == "Source":
            source = prop.text or ""
    if got_name != name:
        problems.append(f"{name}: the artifact's ModuleScript is named '{got_name}'")
    if not source or not source.strip():
        problems.append(f"{name}: the artifact carries no Source — a consumer would install an empty module")
        return None
    return source


def check(keep=False, manifest_path=MANIFEST, plant=None):

    problems = []
    run([BUILD_THEMES])
    with open(manifest_path) as handle:
        manifest = json.load(handle)

    work = tempfile.mkdtemp(prefix="facet-theme-artifacts-")
    try:
        for tree in COPIED_TREES:
            shutil.copytree(os.path.join(REPO, tree), os.path.join(work, tree))
        for rel in COPIED_FILES:
            dest = os.path.join(work, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(os.path.join(REPO, rel), dest)
        installed = os.path.join(work, "installed")
        os.makedirs(installed)

        for entry in manifest["packages"]:
            name = entry["artifact"]
            rbxm = os.path.join(REPO, entry["file"])
            if not os.path.isfile(rbxm):
                problems.append(f"{name}: {entry['file']} was not built")
                continue
            if os.path.getsize(rbxm) != entry["bytes"]:
                problems.append(
                    f"{name}: the manifest records {entry['bytes']} bytes and the artifact on disk is "
                    f"{os.path.getsize(rbxm)} — the manifest describes a different build"
                )
            xml_path = os.path.join(work, f"{name}.rbxmx")
            build_one(os.path.join(REPO, "examples", "themes", entry["module"] + ".luau"), name, xml_path)
            source = artifact_source(xml_path, name, problems)
            if source is None:
                continue
            if plant is not None:
                source = plant(name, source)
            code = strip_luau_comments(source)
            for call in REQUIRE_CALL.finditer(code):
                line = code[: call.start()].count("\n") + 1
                problems.append(
                    f"{name}: the artifact's code calls require() at line ~{line}. A theme package is data "
                    f"handed the `themes` table by its caller; a require is a dependency the artifact cannot "
                    f"carry, and a consumer installing it alone would fail at that line"
                )
            with open(os.path.join(installed, f"{name}.luau"), "w") as handle:
                handle.write(source)

        with open(os.path.join(installed, "expected.json"), "w") as handle:
            json.dump(manifest, handle)

        result = subprocess.run(
            ["lune", "run", "tools/lune/theme_artifact_probe"],
            cwd=work,
            env=env(),
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            for line in (result.stdout + result.stderr).strip().splitlines():
                problems.append(f"probe: {line.strip()}")
        else:
            print(result.stdout.strip())
    finally:
        if keep:
            print(f"kept the isolated tree at {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)
    return problems


def selftest():

    plants = [
        (
            "a package that reaches into examples/ (the gallery's theme picker)",
            lambda name, src: (
                src.replace(
                    "local classic_desktop = {}",
                    'local picker = require("../../examples/gallery/client/theme_picker")\n'
                    "local classic_desktop = {}",
                )
                if name == "ClassicDesktop"
                else src
            ),
            "calls require()",
        ),
        (
            "an artifact whose identity stamp drifted from the manifest",
            lambda name, src: (src.replace('version = "1.0.0"', 'version = "9.9.9"') if name == "ScifiHud" else src),
            "artifact version",
        ),
        (
            "an artifact that lost its package body",
            lambda name, src: ("-- (emptied)\nreturn {}\n" if name == "PixelQuest" else src),
            "PixelQuest",
        ),
        (
            "a package whose semantic palette has unreadable text",
            lambda name, src: (
                src.replace("content = rgb(24, 24, 24)", "content = rgb(212, 208, 200)")
                if name == "ClassicDesktop"
                else src
            ),
            "ClassicDesktop",
        ),
    ]
    ok = True
    clean = check()
    if clean:
        print("SELFTEST FAILED: the unplanted tree is already red:")
        for problem in clean:
            print(f"  - {problem}")
        return False
    print("  selftest control: the unplanted tree passes")
    for label, plant, expect in plants:
        problems = check(plant=plant)
        matched = [problem for problem in problems if expect in problem]
        print(f"  [{'BITES' if matched else 'MISSED'}] {label}")




        for problem in (matched or problems)[:2]:
            print(f"      -> {problem}")
        if not matched:
            ok = False
    return ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--keep", action="store_true", help="leave the isolated tree on disk for inspection")
    args = parser.parse_args()

    if not os.path.isfile(BUILD_THEMES):
        sys.stderr.write("check_theme_artifacts: tools/build_themes.sh is missing\n")
        raise SystemExit(2)

    if args.selftest:
        print("check_theme_artifacts --selftest")
        raise SystemExit(0 if selftest() else 1)

    problems = check(keep=args.keep)
    if problems:
        print(f"check_theme_artifacts: {len(problems)} problem(s)")
        for problem in problems:
            print(f"  - {problem}")
        raise SystemExit(1)
    print("check_theme_artifacts: every shipped theme artifact installs against a bare library surface")
    raise SystemExit(0)


if __name__ == "__main__":
    main()
