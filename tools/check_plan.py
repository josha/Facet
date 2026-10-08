#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def check_plan():
    try:
        plan = json.loads((ROOT / "tests/plan.json").read_text())
    except (OSError, ValueError) as error:
        return [f"cannot read tests/plan.json: {error}"]
    units = plan.get("units") if isinstance(plan, dict) else None
    if not isinstance(units, list):
        return ["Verify plan must contain a units list"]
    sources = {}
    failures = []
    for path in sorted((ROOT / "tests").rglob("*.luau")):
        if not path.name.endswith((".spec.luau", "_spec.luau")):
            continue
        name = path.relative_to(ROOT / "tests").as_posix()[:-10]
        if name in sources:
            failures.append(f"spec files share the same ID: {name}")
        sources[name] = path.relative_to(ROOT).as_posix()
    declared = set()
    locators = set()
    for index, unit in enumerate(units):
        if not isinstance(unit, dict) or not isinstance(unit.get("id"), str) or not unit["id"]:
            failures.append(f"Verify plan unit {index + 1} needs a nonempty ID")
            continue
        name = unit["id"]
        if name in declared:
            failures.append(f"duplicate Verify plan ID: {name}")
        declared.add(name)
        locator = unit.get("locator")
        if not isinstance(locator, str):
            failures.append(f"Verify plan unit {name} needs a locator")
            continue
        if locator in locators:
            failures.append(f"duplicate Verify plan locator: {locator}")
        locators.add(locator)
        if name not in sources:
            failures.append(f"Verify plan spec is not on disk: {name}")
        elif locator != sources[name]:
            failures.append(f"Verify plan locator for {name} must be {sources[name]}")
    for name in sorted(set(sources) - declared):
        failures.append(f"spec is missing from the Verify plan: {name}")
    return failures


def main():
    argparse.ArgumentParser(description="Check that the Verify plan lists every spec file exactly once.").parse_args()
    failures = check_plan()
    print(f"plan: {len(failures)} findings")
    for finding in failures:
        print(f"  {finding}")
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
