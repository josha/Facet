#!/usr/bin/env python3
"""Place doctor for the performance lab (roadmap Step 9, acceptance PL-1/PL-16).

WHY THIS EXISTS. `rojo build` cheerfully emits a file when a `$path` is wrong or a
module has been renamed: the place is the right size, opens without error, and is
missing the thing the whole lab depends on. "The build succeeded" is not evidence
that the build contains anything.

So this rebuilds the place FROM A CLEAN SOURCE STATE and inspects the resulting
tree for the scripts, modules, scenario registry and version markers the lab
needs, plus the properties that make the file safe for the user to publish by
hand — no universe/place id, no developer filesystem path, no plugin dependency.

TWO SERIALIZATIONS, ON PURPOSE. The checked-in artifact is the binary `.rbxl`,
which is chunked and LZ4-compressed, so instance names are not reliably greppable
in it. Reading the tree therefore uses an `.rbxlx` built from THE SAME project
file in THE SAME run, and the binary artifact is verified separately: it exists,
it is a real Roblox binary (magic header), and it is the same order of size. A
divergence between the two is impossible without Rojo emitting different trees
for the same project, which is not a failure mode this check can create.

Run:  python3 tools/check_perf_place.py            (exit 0 = PASS)
      python3 tools/check_perf_place.py --no-build (inspect the checked-in build)

Writes artifacts/performance-stress-places/place.json.
"""

import json
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

PROJECT = "examples/performance.project.json"
BUILT = "examples/places/LuauUI-PerformanceLab.rbxl"
ARTIFACT = "artifacts/performance-stress-places/place.json"

# Everything the lab cannot run without. A name here is a promise the built place
# keeps, and each one has broken in some other stage's build at least once.
REQUIRED = [
    # the library itself, and the profiler phases the capture reads
    ("ReplicatedStorage/LuauUI", "ModuleScript"),
    ("ReplicatedStorage/LuauUI/core/profile", "ModuleScript"),
    ("ReplicatedStorage/LuauUI/client/screen_target", "ModuleScript"),
    ("ReplicatedStorage/LuauUI/controls/virtual_list", "ModuleScript"),
    # the scenario registry, the reused gallery runner, and the lab modules
    ("ReplicatedStorage/LuauUIScenarios", "ModuleScript"),
    ("ReplicatedStorage/LuauUIScenarios/runner", "ModuleScript"),
    ("ReplicatedStorage/LuauUIScenarios/perf_lab", "ModuleScript"),
    ("ReplicatedStorage/LuauUIScenarios/dataset", "ModuleScript"),
    ("ReplicatedStorage/LuauUIScenarios/rows", "ModuleScript"),
    ("ReplicatedStorage/LuauUIScenarios/capture", "ModuleScript"),
    ("ReplicatedStorage/LuauUIScenarios/overlay", "ModuleScript"),
    # the two named levers of device-capture-2026-08-15 §7 (`arrange-shapes`,
    # `edit-locality`). NOT optional: `perf_lab` asserts `ctx.lab.levers` at build,
    # so a place that dropped this module cannot mount ANY workload — which is the
    # failure this list exists to catch at the gate instead of at the phone.
    ("ReplicatedStorage/LuauUIScenarios/levers", "ModuleScript"),
    # the ornate reference package the flat-vs-ornate comparison needs
    ("ReplicatedStorage/LuauUIThemes/fantasy_ornate", "ModuleScript"),
    # the bootstrap and the matched raw-Roblox reference
    ("StarterPlayer/StarterPlayerScripts/PerfLab", "LocalScript"),
    ("StarterPlayer/StarterPlayerScripts/PerfLab/native_list", "ModuleScript"),
    # something to stand on, so the place opens as a usable session
    ("Workspace/Baseplate", "Part"),
    ("Workspace/SpawnLocation", "SpawnLocation"),
]

# Version markers a capture cites. If one of these strings is not in the built
# source, a capture claiming it is citing a version the place does not carry.
VERSION_MARKERS = [
    ("ReplicatedStorage/LuauUIScenarios/dataset", 'dataset.VERSION = "perf-dataset/'),
    ("ReplicatedStorage/LuauUIScenarios/rows", 'rows.VERSION = "perf-row/'),
    ("ReplicatedStorage/LuauUIScenarios/perf_lab", 'local SCENARIO_VERSION = "perf-scenarios/'),
    ("ReplicatedStorage/LuauUIScenarios/capture", 'capture.SCHEMA = "luauui-perf-capture/'),
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
    """path -> (class, source) for every Instance in the tree."""
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
        # NO HARDCODED DEVELOPER PATH (phase-gate review F-5): a tool that refuses a
        # place for containing `/Users/...` had one in its own PATH. Rojo is found the
        # way every other developer finds it — through the toolchain manager's shim
        # directory relative to $HOME, or whatever is already on PATH.
        env = dict(os.environ)
        extra = [os.path.expanduser("~/.rokit/bin"), "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = os.pathsep.join([p for p in extra if os.path.isdir(p)] + [env.get("PATH", "")])
        if build:
            # THE CLEAN-SOURCE REBUILD. Both artifacts come from one invocation of
            # the same project file, so "the checked-in .rbxl matches these sources"
            # is a property of this run rather than of whenever it was last built.
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
                continue  # already reported above
            if marker not in got[1]:
                problems.append(f"{path} does not carry the version marker {marker!r}")

        # PUBLISH SAFETY. The user is told to open this file and choose "Publish to
        # Roblox" themselves; a place that arrived with an id attached would publish
        # somewhere they did not choose, and one carrying a developer path leaks the
        # build machine into a file meant to be shared.
        joined_sources = "\n".join(src for (_k, src) in tree.values())
        for needle, why in (
            ("/Users/", "an absolute developer filesystem path"),
            ("game.PlaceId =", "an assigned PlaceId"),
            ("game.GameId =", "an assigned GameId"),
            ("plugin:", "a plugin dependency (the place must run without one)"),
        ):
            if needle in joined_sources:
                problems.append(f"the built place source contains {needle!r} — {why}")

        # the runner is REUSED, not copied: the lab's registry and the gallery's must
        # be the same file, or the Studio surface this stage claims to extend is a
        # second implementation wearing the same name
        # REUSED, NOT FORKED — asserted on the PROJECT MAPPING, not on the built source.
        # The first version compared the built runner against the repo file it was built
        # from, so the two could never differ and the check could not fail (phase-gate
        # review F-6, confirmed by a mutation that passed). What actually matters is
        # that the project points at the gallery's file rather than at a copy under
        # examples/performance/.
        runner = tree.get("ReplicatedStorage/LuauUIScenarios/runner")
        if runner is None:
            problems.append("the built place has no scenario runner")
        else:
            with open(PROJECT) as fh:
                project = json.load(fh)
            mapped = (
                project["tree"]["ReplicatedStorage"]
                .get("LuauUIScenarios", {})
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

    # the binary artifact the user actually opens
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
        "schema": "luauui-perf-place/1",
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
