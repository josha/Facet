#!/usr/bin/env python3
import json
import pathlib
import sys

LAB = pathlib.Path(__file__).resolve().parent.parent
FACET = LAB.parent.parent
errors = []


def paths(node):
    if isinstance(node, dict):
        if "$path" in node:
            yield node["$path"]
        for key, child in node.items():
            if not key.startswith("$"):
                yield from paths(child)


for project in sorted(LAB.glob("*.project.json")):
    for raw in paths(json.loads(project.read_text())["tree"]):
        target = (project.parent / raw).resolve()
        if not target.is_relative_to(FACET) or not target.exists():
            errors.append(f"{project.name}: source {raw} must exist inside Facet")

for out in sys.argv[1:]:
    target = pathlib.Path(out).resolve()
    if not target.is_relative_to(LAB / "build"):
        errors.append(f"output {out} is outside the lab build directory")

if errors:
    print("BOUNDARY FAIL\n  " + "\n  ".join(errors))
    sys.exit(1)
print("boundary ok: repository sources, outputs in the lab build directory")
