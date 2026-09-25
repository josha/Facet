#!/usr/bin/env python3
import argparse
import importlib.util
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
        parity = json.loads(parity_path.read_text())
        for risk in parity.get("pendingLiveRisks", []):
            failures.append(f"pending live verification: {risk}")
        for item in parity["items"]:
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
    for folder in ("examples", "bench"):
        for path in sorted((ROOT / folder).rglob("*.luau")):
            for requested in imports(path):
                target = resolve(path, requested)
                if isinstance(target, Path) and target.is_relative_to(ROOT / "src") and target != ROOT / "src/init.luau":
                    failures.append(f"{path.relative_to(ROOT)}: requires private Facet module {target.relative_to(ROOT)}")
    vendor = ROOT / "src/vendor"
    if vendor.exists():
        failures.extend(f"src/vendor/{path.name}: unapproved vendor" for path in vendor.iterdir() if path.name != "compose")
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



TIER_ORDER = ("affected", "fast", "full", "release")


def gated_below(case, tier):
    gate = case.get("tier")
    return gate in TIER_ORDER and tier in TIER_ORDER and TIER_ORDER.index(gate) > TIER_ORDER.index(tier)


def deferred_cases(suite, tier):
    return {case.get("id") for case in suite.get("cases", []) if case.get("status") == "skip" and gated_below(case, tier)}


def validate_suite(suite, selected, tier):
    failures = []
    cases = suite.get("cases", [])
    identifiers = [case.get("id") for case in cases]
    reported = {case.get("spec") for case in cases}
    skipped = [case for case in cases if case.get("status") == "skip"]
    if suite.get("tier") != tier:
        failures.append(f"suite ran at tier {suite.get('tier')!r}, expected {tier!r}")
    if not cases:
        failures.append("suite reported no test cases")
    if len(identifiers) != len(set(identifiers)) or any(not isinstance(value, str) or not value for value in identifiers):
        failures.append("suite reported missing or duplicate case IDs")
    if reported != set(selected):
        failures.append(f"suite spec census differs: missing={sorted(set(selected) - reported)} unexpected={sorted(reported - set(selected))}")
    if suite.get("registeredSpecs") != len(selected) or suite.get("reportedSpecs") != len(selected):
        failures.append("suite spec totals do not match selected inventory")
    if any(not gated_below(case, tier) for case in skipped):
        failures.append("suite skipped a case that its tier must run")
    if suite.get("skipped", 0) != len(skipped):
        failures.append("suite skipped totals do not match its cases")
    if suite.get("passed") != len(cases) - len(skipped) or suite.get("failed") != 0 or any(case.get("status") not in ("pass", "skip") for case in cases):
        failures.append("suite did not pass every registered case")
    return failures


WORKING = ("affected", "fast", "full", "release")
COMPLETE = ("full", "release")
RELEASE = ("release",)
PERF_GATE_STUDIO = ("studio", "native-reference", "theme-cost", "large-text", "device-matrix")


def producer(name, command, tiers, environment="deterministic", replaces=()):
    return {"id": name, "command": command, "tiers": tiers, "environment": environment, "replaces": list(replaces)}


def producers_for(tier):
    catalog = [
        producer("vendor", ["python3", "tools/sync_compose.py", "--check"], WORKING),
        producer("verification-selftest", ["python3", "tools/lune/native_verify_selftest.py"], WORKING, replaces=["verify-selftest"]),
        producer("comments", ["python3", "tools/strip_comments.py", "--check"], WORKING, replaces=["check_comment_codes"]),
        producer("comments-selftest", ["python3", "-m", "unittest", "discover", "-s", "tools/tests", "-p", "test_strip_comments.py"], WORKING, replaces=["check_comment_codes-selftest"]),
        producer("format", ["stylua", "--check", "src", "tests", "tools", "bench", "examples"], WORKING, replaces=["stylua-check-check-src-tests-tools-bench-examples", "stylua-check-check-src-tests-tools-examples"]),
        producer("suite", ["lune", "run", "tools/lune/native_verify_suite", tier], WORKING, replaces=["suite", "check_registration_cli", "corpus_cli"]),
        producer("no-fusion", ["python3", "tools/check_no_fusion.py"], WORKING, replaces=["check_no_fusion"]),
        producer("no-fusion-selftest", ["python3", "tools/check_no_fusion.py", "--selftest"], WORKING, replaces=["check_no_fusion-selftest"]),
        producer("experiment-markers", ["lune", "run", "tools/lune/check_experiment_markers_cli"], WORKING, replaces=["check_experiment_markers"]),
        producer("experiment-markers-selftest", ["lune", "run", "tools/lune/check_experiment_markers_cli", "--selftest"], WORKING),
        producer("screen-key-bindings", ["python3", "tools/check_no_screen_key_bindings.py"], WORKING, replaces=["check_no_screen_key_bindings"]),
        producer("screen-key-bindings-selftest", ["python3", "tools/check_no_screen_key_bindings.py", "--selftest"], WORKING, replaces=["check_no_screen_key_bindings-selftest"]),
        producer("doctor", ["bash", "tools/doctor.sh"], COMPLETE, replaces=["doctor"]),
        producer("links", ["lune", "run", "tools/lune/check_links_cli"], COMPLETE, replaces=["check_links_cli"]),
        producer("links-selftest", ["lune", "run", "tools/lune/check_links_cli", "--selftest"], COMPLETE, replaces=["check_links_cli-selftest"]),
        producer("doc-style", ["python3", "tools/check_doc_style.py"], COMPLETE, replaces=["check_doc_style"]),
        producer("doc-style-selftest", ["python3", "tools/check_doc_style.py", "--selftest"], COMPLETE, replaces=["check_doc_style-selftest"]),
        producer("maintainer-map", ["lune", "run", "tools/lune/check_maintainer_map_cli"], COMPLETE, replaces=["check_maintainer_map_cli"]),
        producer("maintainer-map-selftest", ["lune", "run", "tools/lune/check_maintainer_map_cli", "--selftest"], COMPLETE, replaces=["check_maintainer_map_cli-selftest"]),
        producer("example-drift", ["python3", "tools/check_example_drift.py"], COMPLETE, replaces=["check_example_drift_cli"]),
        producer("example-drift-selftest", ["python3", "tools/check_example_drift.py", "--selftest"], COMPLETE),
        producer("brand-drift", ["python3", "tools/check_brand_drift.py"], COMPLETE, replaces=["check_brand_drift"]),
        producer("brand-drift-selftest", ["python3", "tools/check_brand_drift.py", "--selftest"], COMPLETE, replaces=["check_brand_drift-selftest"]),
        producer("brand-drift-skip-builds", ["python3", "tools/check_brand_drift.py", "--skip-builds"], COMPLETE, replaces=["check_brand_drift-skip-builds"]),
        producer("call-shape-drift", ["python3", "tools/check_call_shape_drift.py"], COMPLETE, replaces=["check_call_shape_drift", "check_docs_cli"]),
        producer("call-shape-drift-selftest", ["python3", "tools/check_call_shape_drift.py", "--selftest"], COMPLETE, replaces=["check_call_shape_drift-selftest"]),
        producer("theme-drift", ["python3", "tools/check_theme_drift.py"], COMPLETE, replaces=["check_theme_drift_cli"]),
        producer("theme-drift-selftest", ["python3", "tools/check_theme_drift.py", "--selftest"], COMPLETE),
        producer("live-evidence", ["python3", "tools/check_live_evidence.py"], COMPLETE, "studio", replaces=["check_device_captures", "check_eq6_evidence", "check_matrix_rows", "check_row_actions_matrix", "check_traversal_evidence", "check_xp_matrix"]),
        producer("live-evidence-selftest", ["python3", "tools/check_live_evidence.py", "--selftest"], COMPLETE, replaces=["check_device_sweep-selftest"]),
        producer("source-size", ["python3", "tools/check_source_size.py"], COMPLETE, replaces=["check_source_size"]),
        producer("types", ["python3", "tools/check_types.py"], COMPLETE, replaces=["check_types"]),
        producer("types-selftest", ["python3", "tools/check_types.py", "--selftest"], COMPLETE, replaces=["check_types-selftest"]),
        producer("package-selftest", ["python3", "tools/package.py", "--selftest"], COMPLETE, "package", replaces=["package-selftest"]),
        producer("word-data", ["python3", "tools/build_word_lists.py", "--check"], COMPLETE, replaces=["build_word_lists-check"]),
        producer("word-data-selftest", ["python3", "tools/build_word_lists.py", "--selftest"], COMPLETE, replaces=["build_word_lists-selftest"]),
        producer("public-allowlist", ["python3", "tools/check_public_allowlist.py"], COMPLETE, replaces=["check_public_allowlist"]),
        producer("public-allowlist-selftest", ["python3", "tools/check_public_allowlist.py", "--selftest"], COMPLETE),
        producer("public-surface", ["lune", "run", "tools/lune/check_public_surface"], COMPLETE, replaces=["check_public_surface"]),
        producer("public-surface-selftest", ["lune", "run", "tools/lune/check_public_surface", "--selftest"], COMPLETE),
        producer("standalone-builds", ["bash", "tools/build_places.sh"], COMPLETE, replaces=["build_places"]),
        producer("reference-builds", ["bash", "tools/build_reference_places.sh"], COMPLETE, replaces=["build_reference_places"]),
        producer("consumer-build", ["rojo", "build", "examples/consumer/default.project.json", "-o", "artifacts/verify/native/consumer.rbxl"], COMPLETE),
        producer("theme-builds", ["bash", "tools/build_themes.sh"], COMPLETE, replaces=["build_themes"]),
        producer("gallery-build", ["rojo", "build", "examples/showcase.project.json", "-o", "artifacts/verify/native/gallery.rbxl"], COMPLETE),
        producer("monitors-build", ["rojo", "build", "examples/virtual_monitors/default.project.json", "-o", "artifacts/verify/native/virtual-monitors.rbxl"], COMPLETE),
        producer("performance-build", ["rojo", "build", "examples/performance.project.json", "-o", "artifacts/verify/native/performance.rbxl"], COMPLETE),
        producer("model-build", ["bash", "tools/build_model.sh"], COMPLETE, "package", replaces=["build_model"]),
        producer("package-build", ["bash", "tools/package.sh", "build"], COMPLETE, "package"),
        producer("package-status", ["bash", "tools/package.sh", "status"], COMPLETE, "package"),
        producer("package-verify", ["bash", "tools/package.sh", "verify"], COMPLETE, "package", replaces=["package-verify"]),
        producer("package-canary", ["lune", "run", "tools/lune/package_canary"], COMPLETE, "package"),
        producer("package-purity", ["python3", "tools/check_library_purity.py"], COMPLETE, "package", replaces=["check_library_purity"]),
        producer("theme-artifacts", ["python3", "tools/check_theme_artifacts.py", "--selftest"], COMPLETE),
        producer("bench", ["bash", "tools/bench.sh"], COMPLETE, "perf"),
        producer("perf", ["bash", "tools/perf.sh"], COMPLETE, "perf"),
        producer("perf-budgets", ["python3", "tools/check_perf_budgets.py"], COMPLETE, "perf", replaces=["check_perf_budgets"]),
        producer("perf-metrics", ["python3", "tools/check_perf_metrics.py"], COMPLETE, "perf", replaces=["check_perf_metrics"]),
        producer("perf-scenes", ["python3", "tools/check_perf_scenes.py"], COMPLETE, "perf", replaces=["check_perf_scenes"]),
        producer("perf-scenes-themes", ["python3", "tools/check_perf_scenes.py", "--themes"], COMPLETE, "perf", replaces=["check_perf_scenes-themes"]),
        producer("perf-captures", ["python3", "tools/check_perf_captures.py"], COMPLETE, "device", replaces=["check_perf_captures"]),
        producer("perf-place", ["python3", "tools/check_perf_place.py", "--no-build"], COMPLETE, "studio", replaces=["check_perf_place"]),
        producer("perf-gate-evidence-budgets", ["python3", "tools/check_perf_gate_evidence.py", "budgets"], COMPLETE, "perf", replaces=["check_perf_gate_evidence-budgets"]),
        producer("perf-gate-evidence-headless-linkage", ["python3", "tools/check_perf_gate_evidence.py", "headless-linkage"], COMPLETE, "perf", replaces=["check_perf_gate_evidence-headless-linkage"]),
        producer("perf-gate-evidence-perf-gate", ["python3", "tools/check_perf_gate_evidence.py", "perf-gate"], COMPLETE, "perf", replaces=["check_perf_gate_evidence-perf-gate"]),
    ]
    catalog += [
        producer(f"perf-gate-evidence-{mode}", ["python3", "tools/check_perf_gate_evidence.py", mode], COMPLETE, "studio", replaces=[f"check_perf_gate_evidence-{mode}"])
        for mode in PERF_GATE_STUDIO
    ]
    catalog += [
        producer("prove-perf-gate", ["lune", "run", "tools/lune/prove_perf_gate"], RELEASE, "perf"),
        producer("perf-gate-evidence-falsifiable", ["python3", "tools/check_perf_gate_evidence.py", "falsifiable"], RELEASE, "perf", replaces=["check_perf_gate_evidence-falsifiable"]),
    ]
    return [entry for entry in catalog if tier in entry["tiers"]]


def producer_status(exit_code, environment, reference_host=False):
    if exit_code == 0:
        return "PASS"
    if exit_code == 2 and environment in ("studio", "device"):
        return "FAIL_ENVIRONMENT"
    if exit_code == 2 and environment == "perf" and not reference_host:
        return "FAIL_ENVIRONMENT"
    return "FAIL"


def status_blocks(status, tier):
    return status == "FAIL" or (status == "FAIL_ENVIRONMENT" and tier == "release")


def git_output(*args):
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=False)
    return (getattr(result, "stdout", "") or "").strip()


def package_source_hash():
    path = ROOT / "tools/package.py"
    if not path.is_file():
        return None
    loader = importlib.util.spec_from_file_location("facet_package", path)
    module = importlib.util.module_from_spec(loader)
    loader.loader.exec_module(module)
    return module.source_hash()


def run():
    parser = argparse.ArgumentParser(description="Verify the native Compose/Roblox Facet architecture.")
    parser.add_argument("tier", choices=WORKING, nargs="?", default="full")
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--explain", action="store_true")
    parser.add_argument("--rerun")
    parser.add_argument("--reference-host", action="store_true", help="treat host timing failures as failures; use on the host that recorded the budgets")
    args = parser.parse_args()
    started_at = time.time()
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    gate_commit = git_output("rev-parse", "HEAD")
    gate_dirty = git_output("status", "--porcelain") != ""
    gate_source = package_source_hash()
    records, selected, missing_coverage = inventory()
    architecture_failures = architecture()
    (ARTIFACTS / "coverage.json").write_text(json.dumps({"schema": "facet-native-coverage/1", "specs": records, "unresolved": missing_coverage}, indent=2) + "\n")
    (ARTIFACTS / "specs.json").write_text(json.dumps(selected) + "\n")
    catalog = producers_for(args.tier)
    if args.rerun and args.rerun not in {"architecture", "coverage", *[entry["id"] for entry in catalog]}:
        parser.error(f"unknown producer: {args.rerun}")
    producers = [
        {"id": "architecture", "exitCode": int(bool(architecture_failures)), "status": "FAIL" if architecture_failures else "PASS", "environment": "deterministic", "replaces": ["check_boundary"], "findings": architecture_failures},
        {"id": "coverage", "exitCode": int(bool(missing_coverage)), "status": "FAIL" if missing_coverage else "PASS", "environment": "deterministic", "replaces": [], "findings": missing_coverage},
    ]
    print(f"Facet native architecture verification: {args.tier}; {len(selected)} executable specs; {len(catalog) + 3} producers selected.", flush=True)
    print("Historical parity: NOT ESTABLISHED. See docs/guide/20-verification-parity.md for the producer and assertion comparison with main.", flush=True)
    if args.explain:
        print(f"Selection: every producer whose tiers include '{args.tier}'. Each command runs afresh; no stored result is reused.", flush=True)
        print("Status: exit 0 is PASS. Exit 2 from a studio or device producer is FAIL_ENVIRONMENT: the live evidence is not recorded. Exit 2 from a perf producer is FAIL_ENVIRONMENT: a host timing budget failed; --reference-host makes it FAIL. FAIL_ENVIRONMENT is reported in full and blocks release.", flush=True)
        for entry in catalog:
            replaces = f" replaces {', '.join(entry['replaces'])}" if entry["replaces"] else ""
            print(f"  {entry['id']} [{entry['environment']}; tiers {'/'.join(entry['tiers'])}]{replaces}: {' '.join(entry['command'])}", flush=True)
    if args.tier in ("affected", "fast"):
        print("Working tier only: not full verification.", flush=True)
    for entry in producers:
        print(f"{entry['id']}: {entry['status']} ({len(entry['findings'])} findings)", flush=True)
        for finding in entry["findings"][:15]:
            print(f"  {finding}", flush=True)
    for entry in catalog:
        name, command = entry["id"], entry["command"]
        if args.rerun and args.rerun != name:
            continue
        print(f"{name}: RUN {' '.join(command)}", flush=True)
        started = time.monotonic()
        if name == "suite":
            (ARTIFACTS / "suite.json").unlink(missing_ok=True)
        with (ARTIFACTS / f"{name}.log").open("w") as output:
            result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=False)
        status = producer_status(result.returncode, entry["environment"], args.reference_host)
        producers.append({"id": name, "exitCode": result.returncode, "status": status, "environment": entry["environment"], "replaces": entry["replaces"], "seconds": time.monotonic() - started, "log": f"artifacts/verify/native/{name}.log"})
        print(f"{name}: {status} ({time.monotonic() - started:.1f}s)", flush=True)
        if result.returncode:
            print((ARTIFACTS / f"{name}.log").read_text()[-5000:], flush=True)
    if any(entry["id"] == "suite" for entry in producers):
        suite_path = ARTIFACTS / "suite.json"
        case_failures = []
        passed_cases = set()
        if suite_path.exists():
            suite = json.loads(suite_path.read_text())
            case_failures.extend(validate_suite(suite, selected, args.tier))
            passed_cases = {case["id"] for case in suite["cases"] if case["status"] == "pass"} | deferred_cases(suite, args.tier)
        else:
            case_failures.append("suite produced no current-run result file")
        for record in records:
            replacement = record.get("replacement") or {}
            for case in mapped_cases(replacement):
                if case not in passed_cases:
                    case_failures.append(f"{record['spec']}: mapped replacement case did not pass: {case}")
        producers.append({"id": "replacement-cases", "exitCode": int(bool(case_failures)), "status": "FAIL" if case_failures else "PASS", "environment": "deterministic", "replaces": ["check_manifest_integrity"], "findings": case_failures})
        print(f"replacement-cases: {'FAIL' if case_failures else 'PASS'} ({len(case_failures)} findings)", flush=True)
    ok = not any(status_blocks(entry["status"], args.tier) for entry in producers)
    complete = not bool(args.rerun)
    counts = {}
    for entry in producers:
        counts[entry["status"]] = counts.get(entry["status"], 0) + 1
    status = ("PASS" if ok else "FAIL") if args.tier in COMPLETE else ("PASS_PARTIAL" if ok else "FAIL")
    if not complete and status == "PASS":
        status = "INCOMPLETE"
    report = {
        "schema": "facet-native-verification/1",
        "tier": args.tier,
        "completeTier": complete,
        "ok": ok,
        "status": status,
        "statusCounts": counts,
        "coverage": "coverage.json",
        "historicalParity": "not-established",
        "producers": producers,
        "studioEvidence": "External live Studio gallery and virtual monitors checks are required; these builds do not assert visual parity.",
    }
    (ARTIFACTS / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    run_record = {
        "schema": "facet-verify-run/1",
        "gateEvidence": {
            "schema": "facet-release-gate/1",
            "tier": args.tier,
            "status": status,
            "commit": gate_commit,
            "treeDirty": gate_dirty,
            "sourceHash": gate_source,
            "completedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        },
        "tier": args.tier,
        "status": status,
        "durationMs": int((time.time() - started_at) * 1000),
        "producers": [{"id": entry["id"], "status": entry["status"], "exitCode": entry["exitCode"], "environment": entry["environment"]} for entry in producers],
    }
    if complete:
        (ROOT / "artifacts/verify").mkdir(parents=True, exist_ok=True)
        (ROOT / f"artifacts/verify/latest-{args.tier}.json").write_text(json.dumps(run_record, indent=2) + "\n")
    summary = ", ".join(f"{count} {name}" for name, count in sorted(counts.items()))
    print(f"producers: {len(producers)} selected; {summary}", flush=True)
    print(f"native {args.tier}: {status}; artifacts/verify/native/report.json", flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(run())
