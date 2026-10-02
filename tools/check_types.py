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
import resource
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "artifacts/verify/types"
LOCK = ROOT / "tools/typecheck/roblox.lock.json"
LUNE_LOCK = ROOT / "tools/typecheck/lune.lock.json"
PLUGIN_LOCK = ROOT / "tools/typecheck/roblox-plugin.lock.json"
SOLVERS = {"old": [], "new": ["LuauSolverV2=true"]}
DEFAULT_FLAGS = ["LuauTarjanChildLimit=100000"]
FLAGS = list(DEFAULT_FLAGS)
DIAGNOSTIC = re.compile(r"^(.+?\.lua(?:u)?)(?: \[[^\]]*\])?\((\d+),(\d+)\): (\w+): (.*)$", re.M)


def repository_files():
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.luau"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    )
    return sorted(set(path for path in result.stdout.split("\0") if path and (ROOT / path).is_file()))


def prepare_lune_types():
    lock = json.loads(LUNE_LOCK.read_text())
    version = subprocess.run(["lune", "--version"], capture_output=True, text=True, check=True).stdout.strip()
    if version != "lune " + lock["version"]:
        raise RuntimeError(f"Lune {version} differs from the pinned definitions; run rokit install")
    with tempfile.TemporaryDirectory() as scratch:
        shutil.copyfile(ROOT / "rokit.toml", Path(scratch) / "rokit.toml")
        subprocess.run(["lune", "setup"], cwd=scratch, capture_output=True, text=True, check=True)
    source = Path.home() / ".lune/.typedefs" / lock["version"]
    destination = ARTIFACTS / "lune"
    destination.mkdir(parents=True, exist_ok=True)
    for name, digest in lock["sha256"].items():
        body = (source / name).read_bytes()
        if hashlib.sha256(body).hexdigest() != digest:
            raise RuntimeError(f"Lune definition {name} differs from its pinned SHA-256")
        content = body.decode()
        if name == "roblox.luau":
            names = ["Axes", "BrickColor", "CFrame", "Color3", "ColorSequence", "ColorSequenceKeypoint", "Enum", "Faces", "Font", "NumberRange", "NumberSequence", "NumberSequenceKeypoint", "PhysicalProperties", "Ray", "Rect", "Region3", "Region3int16", "UDim", "UDim2", "Vector2", "Vector2int16", "Vector3", "Vector3int16"]
            exports = "\n".join(f"roblox.{name} = (nil :: unknown) :: typeof({name})" for name in names)
            content = content.replace("return roblox", exports + "\nreturn roblox")
        (destination / name).write_text(content)


def definitions(lock_file=LOCK):
    lock = json.loads(lock_file.read_text())
    path = ARTIFACTS / ("roblox-plugin.d.luau" if lock_file == PLUGIN_LOCK else "roblox.d.luau")
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


def analyze(files, name, extra=(), lock_file=LOCK):
    command = ["luau-lsp", "analyze", "--platform", "roblox", "--definitions=" + str(definitions(lock_file)), *extra, *["--flag:" + flag for flag in FLAGS], *files]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, errors="replace", timeout=600)
    output = result.stdout + result.stderr
    name = name + ("-v2" if "LuauSolverV2=true" in FLAGS else "")
    log = ARTIFACTS / f"{name}.log"
    log.write_text(output)
    matches = list(DIAGNOSTIC.finditer(output))
    diagnostics = []
    for index, match in enumerate(matches):
        file, line, column, kind, _ = match.groups()
        if kind not in {"TypeError", "SyntaxError"}:
            continue
        end = matches[index + 1].start() if index + 1 < len(matches) else len(output)
        diagnostics.append({
            "file": relative(file), "line": int(line), "column": int(column),
            "kind": kind, "message": output[match.start(5):end].strip(),
        })
    diagnostics = list({(item["file"], item["line"], item["column"], item["kind"], item["message"]): item for item in diagnostics}.values())
    if result.returncode not in (0, 1) or (result.returncode and not diagnostics):
        raise RuntimeError(f"Analyzer failed without usable diagnostics; see {log.relative_to(ROOT)}")
    return diagnostics, str(log.relative_to(ROOT))


def is_owned(path):
    return path.startswith("src/") and not path.startswith("src/vendor/")


def plugin_file(path):
    return path.startswith("tools/designer/") or path == "tools/studio/inject.luau"


def project_runs(files):
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*project.json"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    )
    targets = set(files)
    covered = set()
    runs = []
    for project in sorted(set(path for path in result.stdout.split("\0") if path)):
        name = "project-" + hashlib.sha256(project.encode()).hexdigest()[:12]
        sourcemap = ARTIFACTS / (name + ".sourcemap.json")
        subprocess.run(["rojo", "sourcemap", project, "--absolute", "-o", str(sourcemap)], cwd=ROOT, capture_output=True, text=True, check=True)
        mapped = set()

        def visit(node):
            mapped.update(relative(path) for path in node.get("filePaths", []) if path.endswith(".luau"))
            for child in node.get("children", []):
                visit(child)

        visit(json.loads(sourcemap.read_text()))
        selected = sorted(targets & mapped)
        if not selected:
            continue
        covered.update(selected)
        for plugin in (False, True):
            group = [path for path in selected if plugin_file(path) == plugin]
            if group:
                runs.append((group, name + ("-plugin" if plugin else ""), ["--sourcemap=" + str(sourcemap)], PLUGIN_LOCK if plugin else LOCK, project))
    remaining = sorted(targets - covered)
    for plugin in (False, True):
        group = [path for path in remaining if plugin_file(path) == plugin]
        if group:
            runs.append((group, "unmapped-plugin" if plugin else "unmapped", [], PLUGIN_LOCK if plugin else LOCK, None))
    return runs


def negative_probes():
    names = sorted(set(re.findall(r"\bUI\.(\w+)\s*=", "\n".join(path.read_text() for path in (ROOT / "src/ui").glob("*.luau")))))
    probes = [(f"{name}: table required", f"UI.{name}(42)") for name in names if name[0].isupper()]
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
        ("TextInput controlled callback", 'UI.TextInput({value=Facet.Compose.formula(function() return "" end)})'),
        ("NumberInput numeric model", 'UI.NumberInput({value=Facet.Compose.cell("1")})'),
        ("Civil date parse", 'local civilDay: number = Facet.civilDate.parse("09/03/2026")'),
        ("Shortcut neither source", 'UI.ShortcutHint({})'),
        ("Shortcut both sources", 'UI.ShortcutHint({keys={{"Ctrl","K"}},action=Instance.new("InputAction")})'),
        ("Progress presentation", 'UI.ProgressView({presentation="pie"})'),
        ("Image resource value", 'UI.AsyncImage({resource=function() return {value=12,state="ready"} end})'),
        ("Image loader source", 'UI.AsyncImage({loader=function(source:number) end})'),
        ("Stage world model", 'UI.Stage({content=function(runtime:Facet.Runtime, world:Frame) end})'),
        ("Theme numeric metric", 'Facet.themes.define({metrics={controlSizes={regular={height="tall"}}}})'),
        ("VStack spacing type", 'UI.VStack({ gap = true })'),
        ("HStack padding side", 'UI.HStack({ padding = { left = true } })'),
        ("VStack padding side name", 'UI.VStack({ padding = { start = 4 } })'),
        ("HStack align", 'UI.HStack({ align = "middle" })'),
        ("VStack distribute", 'UI.VStack({ distribute = "around" })'),
        ("VStack maximum width", 'UI.VStack({ maxWidth = "fill" })'),
        ("VStack width", 'UI.VStack({ width = "stretch" })'),
        ("VStack native size", 'UI.VStack({ Size = 42 })'),
        ("Screen gap", 'UI.Screen({ gap = false })'),
        ("ZStack alignment", 'UI.ZStack({ alignH = "stretch" })'),
        ("ScrollView axis", 'UI.ScrollView({ axis = "z" })'),
        ("ScrollView native canvas", 'UI.ScrollView({ CanvasSize = 3 })'),
        ("ScrollView native return", 'local wrong: Frame = UI.ScrollView({})'),
        ("Grid columns required", 'UI.Grid({ gap = "s" })'),
        ("Grid columns type", 'UI.Grid({ columns = "two" })'),
        ("Grid alignment", 'UI.Grid({ columns = 2, align = "stretch" })'),
        ("Fill weight", 'UI.fill("wide")'),
        ("Fill return", 'local wrong: Frame = UI.fill()'),
        ("Unknown control", 'UI.ThisControlDoesNotExist({})'),
        ("App parent", 'Facet.app({ parent = 42 })'),
        ("App theme", 'Facet.app({ theme = "dark" })'),
        ("App component", 'Facet.app().mount(42)'),
        ("App mount return", 'local wrong: number = Facet.app().mount(function() return UI.Label({ text = "Hi" }) end)'),
        ("App screen property", 'Facet.app({ screen = { DisplayOrder = "top" } })'),
        ("App sheet option", 'Facet.app({ sheet = { transition = "slow" } })'),
        ("App dispose argument", 'local wrong: string = Facet.app().dispose()'),
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
        print(f"types selftest ({'new' if 'LuauSolverV2=true' in FLAGS else 'old'} solver): {'PASS' if ok else 'FAIL'}; valid native type accepted, wrong scalar rejected; {log}")
        return 0 if ok else 1
    finally:
        path.unlink()


def cpu(started):
    ended = resource.getrusage(resource.RUSAGE_CHILDREN)
    return ended.ru_utime + ended.ru_stime - started.ru_utime - started.ru_stime


def check(args, solver):
    FLAGS[:] = DEFAULT_FLAGS + SOLVERS[solver] + args.flag
    files = args.files or repository_files()
    if args.source_only:
        files = [path for path in files if is_owned(path)]
    files = [relative(path) for path in files]
    public = not args.files and not args.source_only
    missing = [path for path in files if not (ROOT / path).is_file()]
    if missing:
        raise RuntimeError("Missing type targets: " + ", ".join(missing))
    directives = [path for path in files if not (ROOT / path).read_text().startswith("--!strict\n") or re.search(r"^--!(?:nocheck|nonstrict)\b", (ROOT / path).read_text(), re.M)]
    name = ("source" if args.source_only else "repository") if not args.files else "focused-" + hashlib.sha256("\n".join([*FLAGS, *files]).encode()).hexdigest()[:10]
    started = resource.getrusage(resource.RUSAGE_CHILDREN)
    diagnostics = []
    runs = project_runs(files) if not args.source_only else [(files, name, [], LOCK, None)]
    contexts = []
    for group, run_name, extra, lock_file, project in runs:
        found, log = analyze(group, run_name, extra, lock_file)
        diagnostics.extend(found)
        contexts.append({"project": project, "security": json.loads(lock_file.read_text())["security"], "targets": group, "log": log})
    diagnostics = list({(item["file"], item["line"], item["column"], item["kind"], item["message"]): item for item in diagnostics}.values())
    targets = set(files)
    owned = [item for item in diagnostics if public or item["file"] in targets]
    external = [item for item in diagnostics if item not in owned]
    probes = negative_probes() if public else None
    ok = not owned and not directives and (probes is None or not probes["missed"] and not probes["unexpected"])
    report = {"ok": ok, "solver": solver, "mode": "focused" if args.files else "owned-source" if args.source_only else "full", "targets": files, "flags": FLAGS, "missingStrict": directives, "diagnostics": owned, "dependencyDiagnostics": external, "publicProbes": probes, "contexts": contexts, "definitions": json.loads(LOCK.read_text()), "pluginDefinitions": json.loads(PLUGIN_LOCK.read_text()), "luneDefinitions": json.loads(LUNE_LOCK.read_text())}
    path = ARTIFACTS / (name + ("-v2" if solver == "new" else "") + ".json")
    path.write_text(json.dumps(report, indent=2) + "\n")
    print(f"types ({solver} solver): {'PASS' if ok else 'FAIL'}; {len(files)} targets, {len(owned)} blocking diagnostics, {len(external)} dependency diagnostics; {cpu(started):.1f}s analyzer CPU")
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
    print(f"report: {path.relative_to(ROOT)}; {len(contexts)} analysis contexts; raw logs are listed in the report")
    return ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--files", nargs="+", help="Check only these owned targets; report dependency diagnostics separately")
    parser.add_argument("--flag", action="append", default=[], help="Analyzer flag override, for example LuauSolverV2=true")
    parser.add_argument("--solver", choices=["old", "new", "both"], default="old", help="Luau type solver; every selected solver requires zero diagnostics")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--source-only", action="store_true", help="Check owned source without public witnesses")
    args = parser.parse_args()
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    prepare_lune_types()
    if not shutil.which("luau-lsp"):
        raise RuntimeError("Pinned luau-lsp is missing; run rokit install")
    version = subprocess.run(["luau-lsp", "--version"], capture_output=True, text=True, check=True).stdout.strip()
    if version != json.loads(LOCK.read_text())["analyzerVersion"]:
        raise RuntimeError(f"Analyzer {version} differs from the pinned toolchain; run rokit install")
    solvers = ["old", "new"] if args.solver == "both" else [args.solver]
    if args.selftest:
        tested = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tools/typecheck", "-p", "test_*.py"], cwd=ROOT)
        if tested.returncode:
            return tested.returncode
        results = []
        for solver in solvers:
            FLAGS[:] = DEFAULT_FLAGS + SOLVERS[solver] + args.flag
            results.append(selftest())
        return max(results)
    if not args.files:
        definitions()
        generated = subprocess.run([sys.executable, "tools/typecheck/generate_engine_types.py", "--check"], cwd=ROOT, capture_output=True, text=True)
        if generated.returncode:
            raise RuntimeError("Native engine type generation differs: " + generated.stdout + generated.stderr)
    syntax_files = args.files or repository_files()
    if args.source_only:
        syntax_files = [path for path in syntax_files if is_owned(path)]
    compiled = subprocess.run(["lune", "run", "tools/typecheck/compile", *syntax_files], cwd=ROOT, capture_output=True, text=True)
    syntax_log = ARTIFACTS / "syntax.log"
    syntax_log.write_text(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        raise RuntimeError(f"Pinned runtime compilation failed; see {syntax_log.relative_to(ROOT)}")
    results = [check(args, solver) for solver in solvers]
    return 0 if all(results) else 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"types: FAIL; {error}", file=sys.stderr)
        sys.exit(1)
