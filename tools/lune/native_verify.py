#!/usr/bin/env python3
import argparse
import json
from functools import lru_cache
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from strip_comments import LuauScanner

ARTIFACTS = ROOT / "artifacts/verify/native"
HISTORICAL_BASELINE = "a8c8895673c0745506908b66dc89f8cead6b66f3"
EXTERNAL = ("@lune/", "@std/")
REQUIRES = re.compile(r'\brequire\s*\(?\s*(["\'])([^"\']+)\1\s*(\.\.)?')


def resolve(path, requested):
    dynamic = requested.startswith("dynamic:")
    requested = requested.removeprefix("dynamic:")
    if requested.startswith(EXTERNAL):
        return None
    if requested.startswith("@self/"):
        base = path.parent / requested.removeprefix("@self/") if path.name == "init.luau" else path.with_suffix("") / requested.removeprefix("@self/")
    elif requested.startswith("."):
        base = (path.parent.parent if path.name == "init.luau" else path.parent) / requested
    else:
        return False
    if dynamic and (base.is_dir() or any(base.parent.glob(base.name + "*.luau"))):
        return None
    if requested.endswith("/") and base.is_dir():
        return None
    for candidate in (base.with_suffix(base.suffix + ".luau"), base.with_suffix(base.suffix + ".lua"), base / "init.luau"):
        if candidate.is_file():
            return candidate.resolve()
    return False


@lru_cache(maxsize=None)
def imports(path):
    class ImportScanner(LuauScanner):
        def __init__(self, source):
            super().__init__(source)
            self.strings = []

        def quoted(self, index):
            end = super().quoted(index)
            self.strings.append((index, end))
            return end

        def interpolated(self, index):
            start = index
            index += 1
            while index < len(self.source):
                char = self.source[index]
                if char == "\\":
                    index += 2
                elif char == "`":
                    self.strings.append((start, index + 1))
                    return index + 1
                elif char == "{":
                    self.strings.append((start, index + 1))
                    index = self.code(index + 1, interpolation=True)
                    start = index - 1
                else:
                    index += 1
            raise ValueError("unterminated Luau interpolated string")

    source = path.read_text()
    scanner = ImportScanner(source)
    scanner.code()
    ignored = scanner.comments + scanner.strings + [(start, end) for start, end, _, _ in scanner.long_strings]
    return [("dynamic:" if match[3] else "") + match[2] for match in REQUIRES.finditer(source) if not any(start <= match.start() < end for start, end in ignored)]

def missing_dependencies(path, visited=None):
    visited = visited or set()
    path = path.resolve()
    if path in visited:
        return []
    visited.add(path)
    missing = []
    for requested in imports(path):
        resolved = resolve(path, requested)
        if resolved is False:
            missing.append(f"{path.relative_to(ROOT)}: {requested}")
        elif resolved is not None and "vendor/compose" not in str(resolved):
            missing.extend(missing_dependencies(resolved, visited))
    return sorted(set(missing))


def inventory():
    mapping_path = ROOT / "tools/lune/native_verify_coverage.json"
    mappings = {"retiredMechanisms": [], "replacements": {}, "retirementReasons": {}}
    mapping_files = sorted((ROOT / "tools/lune").glob("coverage_*.json"))
    if mapping_path.exists():
        mapping_files.append(mapping_path)
    for file in mapping_files:
        data = json.loads(file.read_text())
        mappings["retiredMechanisms"].extend(data.get("retiredMechanisms", []))
        for group in data.get("groups", []) + data.get("groupRationales", []):
            for name in group.get("specs", []):
                mappings["retirementReasons"][name] = group.get("rationale")
        mappings["retirementReasons"].update(data.get("retirementReasons", {}))
        for name, replacement in data.get("replacements", {}).items():
            previous = mappings["replacements"].get(name)
            if previous and previous != replacement:
                raise ValueError(f"conflicting coverage mapping for {name} in {file}")
            mappings["replacements"][name] = replacement
    retired = set(mappings["retiredMechanisms"])
    replacements = mappings["replacements"]
    records, selected, failures = [], [], []
    for name in retired:
        if not mappings["retirementReasons"].get(name):
            failures.append(f"{name}: retired mechanism has no explicit rationale")
        if name in replacements:
            failures.append(f"{name}: retirement shadows behavioral replacement evidence")
    historical = subprocess.run(["git", "ls-tree", "-r", "--name-only", HISTORICAL_BASELINE, "tests"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.splitlines()
    paths = {ROOT / path for path in historical if path.endswith((".spec.luau", "_spec.luau"))}
    paths.update((ROOT / "tests").rglob("*.spec.luau"))
    paths.update((ROOT / "tests").rglob("*_spec.luau"))
    for path in sorted(paths):
        name = str(path.relative_to(ROOT / "tests"))[:-10]
        missing = missing_dependencies(path) if path.is_file() else ["spec removed from working tree"]
        record = {"spec": name, "missingDependencies": missing}
        if name in retired:
            record["classification"] = "removed-mechanism"
            record["retirementRationale"] = mappings["retirementReasons"].get(name)
        elif name in replacements:
            replacement = replacements[name]
            targets = replacement["specs"]
            unresolved = [target for target in targets if not (ROOT / "tests" / f"{target}.spec.luau").is_file() or missing_dependencies(ROOT / "tests" / f"{target}.spec.luau")]
            record.update(classification="behavior-replaced", replacement=replacement)
            if unresolved:
                failures.append(f"{name}: replacement specs unavailable: {', '.join(unresolved)}")
            if replacement.get("remaining"):
                failures.append(f"{name}: behavioral gaps: {'; '.join(replacement['remaining'])}")
        elif not missing:
            record["classification"] = "executed"
            selected.append(name)
        else:
            record["classification"] = "unmapped-behavior"
            failures.append(f"{name}: missing implementation and no behavioral replacement mapping")
        records.append(record)
    for name in retired | set(replacements):
        if not any(record["spec"] == name for record in records):
            records.append({"spec": name, "classification": "removed-mechanism" if name in retired else "behavior-replaced", "replacement": replacements.get(name), "retirementRationale": mappings["retirementReasons"].get(name)})
            if name in replacements and replacements[name].get("remaining"):
                failures.append(f"{name}: behavioral gaps: {'; '.join(replacements[name]['remaining'])}")
    workload_audit = ROOT / "bench/workload_fidelity.json"
    if workload_audit.exists():
        audit = json.loads(workload_audit.read_text())
        for scene in audit["scenes"]:
            if scene.get("remaining"):
                failures.append(f"workload {scene['name']}: {'; '.join(scene['remaining'])}")
    parity_path = ROOT / "tools/lune/parity_blockers.json"
    if parity_path.exists():
        for item in json.loads(parity_path.read_text())["items"]:
            records.append({"spec": f"product-parity/{item['id']}", "classification": "product-parity", "replacement": {"cases": item.get("cases", [])}, "parity": item})
            if item.get("remaining"):
                failures.append(f"product parity {item['id']}: {'; '.join(item['remaining'])}")
            elif not item.get("cases") and not item.get("liveEvidence"):
                failures.append(f"product parity {item['id']}: resolved without behavioral or live evidence")
    return records, selected, failures


def architecture():
    failures = []
    for folder in ("src", "examples", "bench"):
        for path in sorted((ROOT / folder).rglob("*.luau")):
            if "vendor/compose" in str(path):
                continue
            failures.extend(missing_dependencies(path))
            text = path.read_text()
            if re.search(r"\bFacet\.(new|createHost|newPresenter|newActionSystem|newFocusGraph)\s*\(", text):
                failures.append(f"{path.relative_to(ROOT)}: removed Facet scaffolding API")
            if re.search(r"\blocal\s+H\s*=\s*[^\n]*constructors", text):
                failures.append(f"{path.relative_to(ROOT)}: use Host for Roblox constructors")
    for removed in ("src/client/application.luau", "src/render/compose_scene.luau", "src/render/renderer.luau", "src/core/services.luau"):
        if (ROOT / removed).exists():
            failures.append(f"{removed}: removed architecture still exists")
    return sorted(set(failures))


def mapped_cases(replacement):
    cases = list(replacement.get("cases", []))
    for value in replacement.get("caseMappings", {}).values():
        cases.extend(value if isinstance(value, list) else [value])
    if not all(isinstance(case, str) for case in cases):
        raise ValueError("Replacement case ids must be strings or lists of strings")
    return cases


def run():
    parser = argparse.ArgumentParser(description="Verify the native Compose/Roblox Facet architecture.")
    parser.add_argument("tier", choices=("affected", "fast", "full", "release"), nargs="?", default="full")
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--explain", action="store_true")
    parser.add_argument("--rerun")
    args = parser.parse_args()
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    records, selected, missing_coverage = inventory()
    architecture_failures = architecture()
    (ARTIFACTS / "coverage.json").write_text(json.dumps({"schema": "facet-native-coverage/1", "specs": records, "unresolved": missing_coverage}, indent=2) + "\n")
    (ARTIFACTS / "specs.json").write_text(json.dumps(selected) + "\n")
    commands = [
        ("vendor", ["python3", "tools/sync_compose.py", "--check"]),
        ("verification-selftest", ["python3", "tools/lune/native_verify_selftest.py"]),
        ("comments", ["python3", "tools/strip_comments.py", "--check"]),
        ("comments-selftest", ["python3", "-m", "unittest", "discover", "-s", "tools/tests", "-p", "test_strip_comments.py"]),
        ("format", ["stylua", "--check", "src", "tests", "tools", "bench", "examples"]),
        ("suite", ["lune", "run", "tools/lune/native_verify_suite", args.tier]),
    ]
    if args.tier in ("full", "release"):
        commands.extend([
            ("types", ["python3", "tools/check_types.py"]),
            ("word-data", ["python3", "tools/build_word_lists.py", "--check"]),
            ("word-data-selftest", ["python3", "tools/build_word_lists.py", "--selftest"]),
            ("perf-budgets", ["python3", "tools/check_perf_budgets.py"]),
            ("gallery-build", ["rojo", "build", "examples/showcase.project.json", "-o", "artifacts/verify/native/gallery.rbxl"]),
            ("monitors-build", ["rojo", "build", "examples/virtual_monitors/default.project.json", "-o", "artifacts/verify/native/virtual-monitors.rbxl"]),
            ("performance-build", ["rojo", "build", "examples/performance.project.json", "-o", "artifacts/verify/native/performance.rbxl"]),
            ("package-build", ["bash", "tools/package.sh", "build"]),
            ("package-status", ["bash", "tools/package.sh", "status"]),
            ("package-canary", ["lune", "run", "tools/lune/package_canary"]),
            ("package-purity", ["python3", "tools/check_library_purity.py"]),
            ("theme-artifacts", ["python3", "tools/check_theme_artifacts.py", "--selftest"]),
        ])
    if args.tier in ("full", "release"):
        commands.extend([("bench", ["bash", "tools/bench.sh"]), ("perf", ["bash", "tools/perf.sh"]), ("perf-metrics", ["python3", "tools/check_perf_metrics.py"])])
    if args.rerun and args.rerun not in {"architecture", "coverage", *[name for name, _ in commands]}:
        parser.error(f"unknown producer: {args.rerun}")
    producers = [{"id": "architecture", "exitCode": int(bool(architecture_failures)), "findings": architecture_failures}, {"id": "coverage", "exitCode": int(bool(missing_coverage)), "findings": missing_coverage}]
    print(f"Facet native architecture verification: {args.tier}; {len(selected)} executable specs. Historical solver/renderer suite is not a native suite verdict.", flush=True)
    if args.tier in ("affected", "fast"):
        print("Working tier only: not full verification.", flush=True)
    for producer in producers:
        print(f"{producer['id']}: {'FAIL' if producer['exitCode'] else 'PASS'} ({len(producer['findings'])} findings)", flush=True)
        for finding in producer["findings"][:15]:
            print(f"  {finding}", flush=True)
    for name, command in commands:
        if args.rerun and args.rerun != name:
            continue
        print(f"{name}: RUN {' '.join(command)}", flush=True)
        started = time.monotonic()
        if name == "suite":
            (ARTIFACTS / "suite.json").unlink(missing_ok=True)
        with (ARTIFACTS / f"{name}.log").open("w") as output:
            result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=False)
        producers.append({"id": name, "exitCode": result.returncode, "seconds": time.monotonic() - started, "log": f"artifacts/verify/native/{name}.log"})
        print(f"{name}: {'PASS' if result.returncode == 0 else 'FAIL'} ({time.monotonic() - started:.1f}s)", flush=True)
        if result.returncode:
            print((ARTIFACTS / f"{name}.log").read_text()[-5000:], flush=True)
    if any(producer["id"] == "suite" for producer in producers):
        suite_path = ARTIFACTS / "suite.json"
        case_failures = []
        passed_cases = set()
        if suite_path.exists():
            suite = json.loads(suite_path.read_text())
            passed_cases = {case["id"] for case in suite["cases"] if case["status"] == "pass"}
        for record in records:
            replacement = record.get("replacement") or {}
            required = mapped_cases(replacement)
            for case in required:
                if case not in passed_cases:
                    case_failures.append(f"{record['spec']}: mapped replacement case did not pass: {case}")
        producers.append({"id": "replacement-cases", "exitCode": int(bool(case_failures)), "findings": case_failures})
        print(f"replacement-cases: {'FAIL' if case_failures else 'PASS'} ({len(case_failures)} findings)", flush=True)
    ok = all(producer["exitCode"] == 0 for producer in producers)
    report = {"schema": "facet-native-verification/1", "tier": args.tier, "completeTier": not bool(args.rerun), "ok": ok, "coverage": "coverage.json", "producers": producers, "studioEvidence": "External live Studio gallery and virtual monitors checks are required; these builds do not assert visual parity."}
    (ARTIFACTS / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"native {args.tier}: {'PASS' if ok else 'FAIL'}; artifacts/verify/native/report.json", flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(run())
