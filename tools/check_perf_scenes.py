#!/usr/bin/env python3
"""Gate check: the Step-4 production-shaped perf scenes are present AND alive.

`test -f perf.json` proves nothing — a scene whose pointer path stopped
resolving, whose virtual list stopped windowing, or whose activate seam stopped
reaching paint would still emit a (faster) record. So each production scene
declares proof counters in `extras`, and this check asserts those counters show
work actually happened.

  python3 tools/check_perf_scenes.py            # the six production shapes
  python3 tools/check_perf_scenes.py --themes   # the three theme-swap shapes
"""
import json
import sys

PERF = "artifacts/phase-4/perf.json"
REFERENCE = "floorAndroid"
CONSOLE = "consoleTenFoot"

# scene -> (requirement, checker(extras) -> error message or None)
PRODUCTION = {
    "virtual-list-scroll": lambda x: (
        None
        if x.get("virtualRows", 0) >= 1000 and 0 < x.get("windowedRows", 0) < 100
        else f"windowing looks wrong: {x!r} (expect a small window over >=1000 rows)"
    ),
    "native-scroll-drag": lambda x: (
        None
        if x.get("dragMoves", 0) > 0 and x.get("dropsCommitted", 0) > 0
        else f"the pointer capture path committed no drag: {x!r}"
    ),
    "dense-hud": lambda x: (
        None
        if x.get("activates", 0) > 0 and str(x.get("boostText") or "").startswith("Boost x")
        else f"the activate chain did not reach the mounted text: {x!r}"
    ),
    "stylesheet-state-churn": lambda x: (
        None if x.get("tagsPerPass", 0) > 0 else f"no state tags classified: {x!r}"
    ),
    "async-image-grid": lambda x: None,  # proof lives in the async counters below
    "screen-lifecycle-churn": lambda x: None,
    # the dense-motion frame (row SF-M8): every axis has to be doing work, and the
    # one-transaction-per-stepped-frame contract has to still hold under all of it
    "dense-motion": lambda x: (
        None
        if x.get("springs", 0) >= 20
        and x.get("timelineBeats", 0) > 0
        and 0 < x.get("windowedRows", 0) < x.get("virtualRows", 0)
        and x.get("motionSteps", 0) > 0
        and x.get("motionSteps") == x.get("motionTransactions")
        else f"the dense-motion frame did not do its work: {x!r}"
    ),
}

THEMES = {
    # scene -> (kind, movedRects predicate, description of the invariant)
    "theme-swap-flat": (
        "palette-only",
        lambda m: m == 0,
        "a palette-only swap must move NO solved geometry; a non-zero count means a "
        "repaint has quietly become a reflow",
    ),
    "theme-swap-metrics": (
        "metric-changing",
        lambda m: m > 0,
        "a metric-changing swap must re-solve; zero moved rects means the metric "
        "authority stopped reaching the solver",
    ),
    "theme-swap-assets": (
        "asset-backed",
        lambda m: m > 0,
        "an asset-backed swap changes metrics too; zero moved rects means the same",
    ),
}


def main() -> int:
    themes_mode = "--themes" in sys.argv
    report = json.load(open(PERF))
    errors = []

    if report.get("schema") != "facet-perf/2":
        errors.append(f"unexpected schema {report.get('schema')!r}; expected facet-perf/2")

    by_scene = {}
    devices = set()
    for run in report["runs"]:
        # this checker is about the HEADLESS scene matrix. A report may also
        # carry ingested device rows, whose `device` is a descriptive table
        # rather than a profile name — skip them rather than crashing on one.
        if run.get("evidenceClass") != "lune":
            continue
        devices.add(run["device"])
        if run["device"] == REFERENCE:
            by_scene[run["scene"]] = run

    if not themes_mode and CONSOLE not in devices:
        errors.append(f"no {CONSOLE} runs: the ten-foot profile is missing from the matrix")

    wanted = THEMES if themes_mode else PRODUCTION
    for scene in wanted:
        run = by_scene.get(scene)
        if run is None:
            errors.append(f"{scene}: no {REFERENCE} run recorded")
            continue
        if not run.get("dataset"):
            errors.append(f"{scene}: no dataset recorded")
        extras = run.get("extras") or {}
        if themes_mode:
            kind, predicate, why = THEMES[scene]
            swap = extras.get("themeSwap")
            if not isinstance(swap, dict) or not swap.get("measured"):
                errors.append(f"{scene}: no measured themeSwap in extras ({extras!r})")
                continue
            if swap.get("kind") != kind:
                errors.append(f"{scene}: kind {swap.get('kind')!r}, expected {kind!r}")
            moved = swap.get("movedRects")
            if not isinstance(moved, int) or not predicate(moved):
                errors.append(f"{scene}: movedRects={moved} — {why}")
        else:
            problem = PRODUCTION[scene](extras)
            if problem:
                errors.append(f"{scene}: {problem}")

    if themes_mode:
        # the E3 half of XP-A3: the live Studio instance census. A flat theme
        # must genuinely cost nothing, an ornate one must genuinely cost
        # something, and the ornate package must have COMPILED — the first live
        # drive handed the adapter a theme module instead of a compiled package
        # and reported an empty census, which read as "the ornate skin is free".
        studio_path = "artifacts/cross-platform-proof/rows/xp-a3-theme-swap-studio.json"
        try:
            swaps = {x["package"]: x for x in json.load(open(studio_path))["swaps"]}
        except (OSError, KeyError, ValueError) as exc:
            errors.append(f"{studio_path}: unreadable ({exc})")
            swaps = {}
        flat = swaps.get("flat")
        ornate = swaps.get("fantasy_ornate")
        if flat is None or ornate is None:
            errors.append(f"{studio_path}: needs a flat swap and an ornate swap")
        else:
            if flat.get("layers", -1) != 0 or flat.get("actualLayerInstances", -1) != 0:
                errors.append(f"flat theme is no longer free: {flat!r}")
            if not ornate.get("compiled"):
                errors.append("the ornate package did not compile — its census is a broken instrument, not a cost")
            if ornate.get("instancesAfter", 0) <= ornate.get("instancesBefore", 0):
                errors.append(f"the ornate skin added no instances: {ornate!r}")
            if ornate.get("actualLayerInstances", 0) <= 0:
                errors.append("the ornate skin materialised no layer instances")

    if not themes_mode:
        grid = by_scene.get("async-image-grid")
        if grid is not None:
            stats = grid.get("async") or {}
            if stats.get("completed", 0) <= 0:
                errors.append(f"async-image-grid: the real provider completed nothing ({stats!r})")

    if errors:
        for e in errors:
            print(f"FAIL {e}")
        return 1
    label = "theme-swap" if themes_mode else "production"
    print(f"perf scenes ok: {len(wanted)} {label} scenes alive at {REFERENCE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
