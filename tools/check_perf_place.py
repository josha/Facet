#!/usr/bin/env python3


import json
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

PROJECT = "examples/performance.project.json"
BUILT = "examples/places/Facet-PerformanceLab.rbxl"
ARTIFACT = "artifacts/performance-stress-places/place.json"



REQUIRED = [

    ("ReplicatedStorage/Facet", "ModuleScript"),
    ("ReplicatedStorage/Facet/core/profile", "ModuleScript"),
    ("ReplicatedStorage/Facet/client/screen_target", "ModuleScript"),
    ("ReplicatedStorage/Facet/controls/virtual_list", "ModuleScript"),

    ("ReplicatedStorage/FacetScenarios", "ModuleScript"),
    ("ReplicatedStorage/FacetScenarios/runner", "ModuleScript"),
    ("ReplicatedStorage/FacetScenarios/perf_lab", "ModuleScript"),
    ("ReplicatedStorage/FacetScenarios/dataset", "ModuleScript"),
    ("ReplicatedStorage/FacetScenarios/rows", "ModuleScript"),
    ("ReplicatedStorage/FacetScenarios/capture", "ModuleScript"),
    ("ReplicatedStorage/FacetScenarios/overlay", "ModuleScript"),




    ("ReplicatedStorage/FacetScenarios/levers", "ModuleScript"),
    ("ReplicatedStorage/FacetScenarios/navigation_inventory", "ModuleScript"),
    ("ReplicatedStorage/FacetScenarios/transient_surfaces", "ModuleScript"),

    ("ReplicatedStorage/FacetThemes/fantasy_ornate", "ModuleScript"),

    ("StarterPlayer/StarterPlayerScripts/PerfLab", "Script"),
    ("StarterPlayer/StarterPlayerScripts/PerfLab/native_list", "ModuleScript"),

    ("Workspace/Baseplate", "Part"),
    ("Workspace/SpawnLocation", "SpawnLocation"),
]



VERSION_MARKERS = [
    ("ReplicatedStorage/FacetScenarios/dataset", 'dataset.VERSION = "perf-dataset/'),
    ("ReplicatedStorage/FacetScenarios/rows", 'rows.VERSION = "perf-row/'),
    ("ReplicatedStorage/FacetScenarios/perf_lab", 'local SCENARIO_VERSION = "perf-scenarios/'),
    ("ReplicatedStorage/FacetScenarios/capture", 'capture.SCHEMA = "facet-perf-capture/'),
    ("StarterPlayer/StarterPlayerScripts/PerfLab/native_list", 'native_list.VERSION = "perf-native/'),
]


def _name(item):
    for p in item.findall("Properties/string"):
        if p.get("name") == "Name":
            return p.text or ""
    return ""


def _source(item):
    for p in item.findall("Properties/ProtectedString"):
        if p.get("name") == "Source":
            return p.text or ""
    for p in item.findall("Properties/string"):
        if p.get("name") == "Source":
            return p.text or ""
    return ""


def index(root):

    out = {}

    def walk(node, prefix):
        for item in node.findall("Item"):
            path = f"{prefix}/{_name(item)}".lstrip("/")
            out[path] = (item.get("class"), _source(item))
            walk(item, path)

    walk(root, "")
    return out


def main():
    problems = []
    notes = []
    build = "--no-build" not in sys.argv

    if not os.path.isfile(PROJECT):
        print(f"check_perf_place: FAIL — missing {PROJECT}")
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        xml_path = os.path.join(tmp, "perflab.rbxlx")




        env = dict(os.environ)
        extra = [os.path.expanduser("~/.rokit/bin"), "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = os.pathsep.join([p for p in extra if os.path.isdir(p)] + [env.get("PATH", "")])
        if build:



            r1 = subprocess.run(
                ["rojo", "build", PROJECT, "-o", BUILT], capture_output=True, text=True, env=env
            )
            if r1.returncode != 0:
                problems.append(f"rojo build (.rbxl) failed: {r1.stderr.strip()}")
        r2 = subprocess.run(
            ["rojo", "build", PROJECT, "-o", xml_path], capture_output=True, text=True, env=env
        )
        if r2.returncode != 0:
            problems.append(f"rojo build (.rbxlx) failed: {r2.stderr.strip()}")
            tree = None
        else:
            tree = index(ET.parse(xml_path).getroot())

    if tree is not None:
        for path, klass in REQUIRED:
            got = tree.get(path)
            if got is None:
                problems.append(f"the built place has no {path}")
            elif got[0] != klass:
                problems.append(f"{path} is a {got[0]}, expected {klass}")

        for path, marker in VERSION_MARKERS:
            got = tree.get(path)
            if got is None:
                continue
            if marker not in got[1]:
                problems.append(f"{path} does not carry the version marker {marker!r}")





        joined_sources = "\n".join(src for (_k, src) in tree.values())
        for needle, why in (
            ("/Users/", "an absolute developer filesystem path"),
            ("game.PlaceId =", "an assigned PlaceId"),
            ("game.GameId =", "an assigned GameId"),
            ("plugin:", "a plugin dependency (the place must run without one)"),
        ):
            if needle in joined_sources:
                problems.append(f"the built place source contains {needle!r} — {why}")










        runner = tree.get("ReplicatedStorage/FacetScenarios/runner")
        if runner is None:
            problems.append("the built place has no scenario runner")
        else:
            with open(PROJECT) as fh:
                project = json.load(fh)
            mapped = (
                project["tree"]["ReplicatedStorage"]
                .get("FacetScenarios", {})
                .get("runner", {})
                .get("$path")
            )
            if mapped != "gallery/scenarios/runner.luau":
                problems.append(
                    f"the project maps the scenario runner to {mapped!r} — the lab must REUSE "
                    "examples/gallery/scenarios/runner.luau, not fork it"
                )
            elif os.path.isfile("examples/performance/lab/runner.luau"):
                problems.append(
                    "examples/performance/lab/runner.luau exists — a forked runner beside the mapping"
                )
            else:
                notes.append("scenario runner is mapped from the gallery (reused, not forked)")


    if not os.path.isfile(BUILT):
        problems.append(f"missing built place {BUILT}")
    else:
        size = os.path.getsize(BUILT)
        with open(BUILT, "rb") as fh:
            magic = fh.read(8)
        if magic != b"<roblox!":
            problems.append(f"{BUILT} is not a Roblox binary place (magic {magic!r})")
        if size < 200_000:
            problems.append(f"{BUILT} is only {size} bytes — the library alone is larger than that")
        notes.append(f"{BUILT}: {size} bytes, binary place")

    result = {
        "schema": "facet-perf-place/1",
        "status": "PASS" if not problems else "FAIL",
        "project": PROJECT,
        "built": BUILT,
        "rebuiltFromSource": build,
        "requiredInstances": len(REQUIRED),
        "versionMarkers": len(VERSION_MARKERS),
        "problems": problems,
        "notes": notes,
    }
    os.makedirs(os.path.dirname(ARTIFACT), exist_ok=True)
    with open(ARTIFACT, "w") as fh:
        json.dump(result, fh, indent=2)
        fh.write("\n")

    if problems:
        print(f"check_perf_place: FAIL — {len(problems)} problem(s)")
        for p in problems:
            print(f"  {p}")
        return 1
    print(
        f"check_perf_place: PASS — {len(REQUIRED)} required instances, "
        f"{len(VERSION_MARKERS)} version markers, publish-safe -> {ARTIFACT}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
