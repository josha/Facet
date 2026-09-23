#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "artifacts/verify/types"
LOCK = ROOT / "tools/typecheck/roblox.lock.json"
WITNESS = ROOT / "tests/types/controls_witness.luau"
FLAGS = []
DIAGNOSTIC = re.compile(r"^(.+?\.lua(?:u)?)\((\d+),(\d+)\): (\w+): (.*)$", re.M)


def definitions():
    lock = json.loads(LOCK.read_text())
    path = ARTIFACTS / "roblox.d.luau"
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != lock["sha256"]:
        body = urllib.request.urlopen(lock["url"], timeout=45).read()
        if hashlib.sha256(body).hexdigest() != lock["sha256"]:
            raise RuntimeError("Roblox definitions differ from their pinned SHA-256")
        path.write_bytes(body)
    return path


def relative(path):
    resolved = Path(path)
    if not resolved.is_absolute():
        resolved = ROOT / resolved
    try:
        return str(resolved.resolve().relative_to(ROOT))
    except ValueError:
        return str(resolved)


def analyze(files, name):
    command = ["luau-lsp", "analyze", "--platform", "roblox", "--definitions=" + str(definitions()), *["--flag:" + flag for flag in FLAGS], *files]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
    output = result.stdout + result.stderr
    log = ARTIFACTS / f"{name}.log"
    log.write_text(output)
    diagnostics = [
        {"file": relative(file), "line": int(line), "column": int(column), "kind": kind, "message": message}
        for file, line, column, kind, message in DIAGNOSTIC.findall(output)
        if kind in {"TypeError", "SyntaxError"}
    ]
    diagnostics = list({(item["file"], item["line"], item["column"], item["kind"], item["message"]): item for item in diagnostics}.values())
    if result.returncode not in (0, 1) or (result.returncode and not diagnostics):
        raise RuntimeError(f"Analyzer failed without usable diagnostics; see {log.relative_to(ROOT)}")
    return diagnostics, str(log.relative_to(ROOT))


def is_owned(path):
    return path.startswith("src/") and not path.startswith("src/vendor/")


def negative_probes():
    names = sorted(set(re.findall(r"\bUI\.(\w+)\s*=", "\n".join(path.read_text() for path in (ROOT / "src/ui").glob("*.luau")))))
    probes = [(f"{name}: table required", f"UI.{name}(42)") for name in names]
    probes.extend([
        ("Button label", 'UI.Button({ label = 42 })'),
        ("Button native size", 'UI.Button({ label = "Save", Size = "large" })'),
        ("Button native visibility", 'UI.Button({ label = "Save", Visible = "yes" })'),
        ("Button nullable label", 'UI.Button({ label = nullableText })'),
        ("Button callback", 'UI.Button({ label = "Save", onActivate = "save" })'),
        ("Button size rung", 'UI.Button({ label = "Save", controlSize = "tiny" })'),
        ("Button native return", 'local wrong: number = UI.Button({ label = "Save" })'),
        ("Toggle cell value", 'UI.Toggle({ value = Facet.Compose.cell("on") })'),
        ("Toggle callback value", 'UI.Toggle({ value = Facet.Compose.cell(false), onChange = function(value: string) end })'),
        ("TextInput cell value", 'UI.TextInput({ value = Facet.Compose.cell(42) })'),
        ("TextInput callback value", 'UI.TextInput({ value = Facet.Compose.cell(""), onChange = function(value: number) end })'),
        ("Slider cell value", 'UI.Slider({ value = Facet.Compose.cell("loud") })'),
        ("Slider callback value", 'UI.Slider({ value = Facet.Compose.cell(0.5), onChange = function(value: string) end })'),
        ("Stepper numeric maximum", 'UI.Stepper({ value = Facet.Compose.cell(1), max = "ten" })'),
        ("Progress numeric value", 'UI.ProgressView({ value = "half" })'),
        ("Badge label", 'UI.Badge({ label = false })'),
        ("Avatar presence", 'UI.Avatar({ name = "Alder", presence = "unknown" })'),
        ("Status status", 'UI.StatusIndicator({ status = "busy" })'),
        ("Sheet writable presentation", 'UI.Sheet({ isPresented = "yes", detent = Facet.Compose.cell("large") })'),
        ("Radial native hold action", 'UI.RadialMenu({ items = {}, holdAction = "Interact" })'),
        ("Radial selected value", 'UI.RadialMenu({ items = {{id="choice", label="Choice", selected=Facet.Compose.cell("a"), value=42}} })'),
        ("Radial selected callback", 'UI.RadialMenu({ items = {{id="choice", label="Choice", selected=Facet.Compose.cell("a"), value="a", onChange=function(value: number) end}} })'),
        ("Radial checked callback", 'UI.RadialMenu({ items = {{id="choice", label="Choice", checked=Facet.Compose.cell(false), onChange=function(value: string) end}} })'),
        ("Radial geometry", 'UI.RadialMenu({ items={}, preset="triangle" })'),
        ("Slider controlled callback", 'UI.Slider({value=0.5})'),
        ("Toggle controlled callback", 'UI.Toggle({value=Facet.Compose.formula(function() return false end)})'),
        ("TextInput numeric model", 'UI.TextInput({value=Facet.Compose.cell("1"),presentation="number"})'),
        ("Shortcut neither source", 'UI.ShortcutHint({})'),
        ("Shortcut both sources", 'UI.ShortcutHint({keys={{"Ctrl","K"}},action=Instance.new("InputAction")})'),
        ("Progress presentation", 'UI.ProgressView({presentation="pie"})'),
        ("Image loader source", 'UI.AsyncImage({loader=function(source:number) end})'),
        ("Stage world model", 'UI.Stage({content=function(runtime:Facet.Runtime, world:Frame) end})'),
        ("Theme numeric metric", 'Facet.themes.define({metrics={controlSizes={regular={height="tall"}}}})'),
        ("Unknown control", 'UI.ThisControlDoesNotExist({})'),
    ])
    named = []
    for label, code in probes:
        if "({" in code and "UI." in code and not label.startswith("Unknown"):
            named.append((label + " named", re.sub(r"UI\.(\w+)\(\{", r'UI.\1("Typed")({', code, count=1)))
    probes.extend(named)
    lines = ['--!strict', 'local Facet = require("../../src")', 'local runtime = Facet.Roblox.createRuntime()', 'local UI = Facet.controls(runtime)', 'local nullableText: Facet.Cell<string?> = Facet.Compose.cell(nil :: string?)']
    expected = {}
    for label, code in probes:
        lines.append(code)
        expected[len(lines)] = label
    with tempfile.NamedTemporaryFile(mode="w", suffix=".luau", prefix="_negative_", dir=ROOT / "tests/types", delete=False) as file:
        file.write("\n".join(lines) + "\n")
        path = Path(file.name)
    try:
        diagnostics, log = analyze([str(path.relative_to(ROOT))], "negative")
        own = [item for item in diagnostics if item["file"] == str(path.relative_to(ROOT))]
        rejected = {item["line"] for item in own}
        unexpected = [item for item in own if item["line"] not in expected]
        return {
            "count": len(expected),
            "missed": [label for line, label in expected.items() if line not in rejected],
            "unexpected": unexpected,
            "log": log,
        }
    finally:
        path.unlink()


def selftest():
    with tempfile.NamedTemporaryFile(mode="w", suffix=".luau", prefix="_checker_", dir=ROOT / "tests/types", delete=False) as file:
        file.write('--!strict\nlocal valid: UDim2 = UDim2.fromOffset(24, 24)\nlocal invalid: string = 42\nreturn valid, invalid\n')
        path = Path(file.name)
    try:
        diagnostics, log = analyze([str(path.relative_to(ROOT))], "selftest")
        own = [item for item in diagnostics if item["file"] == str(path.relative_to(ROOT))]
        ok = len(own) == 1 and own[0]["line"] == 3
        print(f"types selftest: {'PASS' if ok else 'FAIL'}; valid native type accepted, wrong scalar rejected; {log}")
        return 0 if ok else 1
    finally:
        path.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--files", nargs="+", help="Check only these owned targets; report dependency diagnostics separately")
    parser.add_argument("--flag", action="append", default=[], help="Analyzer flag override, for example LuauSolverV2=true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--source-only", action="store_true", help="Check owned source without public witnesses")
    args = parser.parse_args()
    FLAGS[:] = args.flag
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    if not shutil.which("luau-lsp"):
        raise RuntimeError("Pinned luau-lsp is missing; run rokit install")
    version = subprocess.run(["luau-lsp", "--version"], capture_output=True, text=True, check=True).stdout.strip()
    if version != json.loads(LOCK.read_text())["analyzerVersion"]:
        raise RuntimeError(f"Analyzer {version} differs from the pinned toolchain; run rokit install")
    if args.selftest:
        return selftest()
    if not args.files:
        definitions()
        generated = subprocess.run([sys.executable, "tools/typecheck/generate_engine_types.py", "--check"], cwd=ROOT, capture_output=True, text=True)
        if generated.returncode:
            raise RuntimeError("Native engine type generation differs: " + generated.stdout + generated.stderr)
    files = args.files or [str(path.relative_to(ROOT)) for path in sorted((ROOT / "src").rglob("*.luau")) if "vendor" not in path.parts]
    files = [relative(path) for path in files]
    public = not args.files and not args.source_only
    if public:
        files.append(str(WITNESS.relative_to(ROOT)))
        files.extend(str(path.relative_to(ROOT)) for path in sorted((ROOT / "tests/types").glob("*_witness.luau")) if path != WITNESS)
    missing = [path for path in files if not (ROOT / path).is_file()]
    if missing:
        raise RuntimeError("Missing type targets: " + ", ".join(missing))
    directives = [path for path in files if not (ROOT / path).read_text().startswith("--!strict\n")]
    name = "source" if not args.files else "focused-" + hashlib.sha256("\n".join([*FLAGS, *files]).encode()).hexdigest()[:10]
    diagnostics, log = analyze(files, name)
    targets = set(files)
    owned = [item for item in diagnostics if item["file"] in targets or (not args.files and is_owned(item["file"]))]
    external = [item for item in diagnostics if item not in owned]
    probes = negative_probes() if public else None
    ok = not owned and not directives and (probes is None or not probes["missed"] and not probes["unexpected"])
    report = {"ok": ok, "mode": "focused" if args.files else "owned-source" if args.source_only else "full", "targets": files, "flags": FLAGS, "missingStrict": directives, "diagnostics": owned, "dependencyDiagnostics": external, "publicProbes": probes, "log": log, "definitions": json.loads(LOCK.read_text())}
    path = ARTIFACTS / (name + ".json")
    path.write_text(json.dumps(report, indent=2) + "\n")
    print(f"types: {'PASS' if ok else 'FAIL'}; {len(files)} targets, {len(owned)} owned diagnostics, {len(external)} dependency diagnostics reported separately")
    for item in owned[:35]:
        print(f"{item['file']}:{item['line']}:{item['column']}: {item['message'][:320]}")
    for missing in directives:
        print(f"missing strict directive: {missing}")
    if probes:
        print(f"public negative probes: {probes['count'] - len(probes['missed'])}/{probes['count']} rejected")
        for label in probes["missed"]:
            print(f"missed: {label}")
        for item in probes["unexpected"]:
            print(f"probe setup error: {item['message'][:320]}")
    print(f"report: {path.relative_to(ROOT)}; raw analyzer log: {log}")
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"types: FAIL; {error}", file=sys.stderr)
        sys.exit(1)
