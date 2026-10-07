#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import subprocess
import sys

from check_architecture import missing_dependencies

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "artifacts/verify/native"
HISTORICAL_BASELINE = "a8c8895673c0745506908b66dc89f8cead6b66f3"


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
    plan_path = ROOT / "tests/plan.json"
    if plan_path.is_file():
        plan = json.loads(plan_path.read_text())
        units = plan.get("units", [])
        declared = [unit.get("id") for unit in units]
        if len(declared) != len(set(declared)) or set(declared) != set(selected):
            failures.append("executable specs differ from the committed Verify plan")
        if any(unit.get("locator") != f"tests/{unit.get('id')}.spec.luau" for unit in units):
            failures.append("Verify plan locators do not match their declared spec IDs")
        selected = [name for name in declared if name in selected]
    return records, selected, failures


def mapped_cases(replacement):
    cases = list(replacement.get("cases", []))
    for value in replacement.get("caseMappings", {}).values():
        cases.extend(value if isinstance(value, list) else [value])
    if not all(isinstance(case, str) for case in cases):
        raise ValueError("Replacement case ids must be strings or lists of strings")
    return cases


def suite_cases(run, selected):
    sources = {f"tests/{name}.spec.luau" for name in selected}
    cases = set()
    for path in (ROOT / "artifacts/verify/native/gate" / run).glob("suite-worker-*/*-result.json"):
        for result in json.loads(path.read_text())["report"]["results"]:
            if result.get("source") in sources:
                cases.add(result["id"])
    return cases


def replacement_findings(records, selected, run):
    reported = suite_cases(run, selected)
    if not reported:
        return [f"gate run {run} has no suite result for a planned source"]
    failures = []
    for record in records:
        for case in mapped_cases(record.get("replacement") or {}):
            if case not in reported:
                failures.append(f"{record['spec']}: mapped replacement case is not in the suite result of gate run {run}: {case}")
    return failures


def main():
    parser = argparse.ArgumentParser(description="Check the historical coverage mappings against the committed Verify plan.")
    parser.add_argument("--cases", metavar="RUN", help="require every mapped replacement case in the suite result of this gate run")
    args = parser.parse_args()
    records, selected, failures = inventory()
    name = "coverage"
    if args.cases:
        name = "replacement-cases"
        failures = replacement_findings(records, selected, args.cases)
    else:
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        (ARTIFACTS / "coverage.json").write_text(json.dumps({"schema": "facet-native-coverage/1", "specs": records, "unresolved": failures}, indent=2) + "\n")
    print(f"{name}: {len(failures)} findings")
    for finding in failures[:40]:
        print(f"  {finding}")
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
