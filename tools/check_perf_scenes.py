#!/usr/bin/env python3
import json
import os
import sys

PERF = "artifacts/phase-4/perf.json"
REFERENCE = "floorAndroid"
CONSOLE = "consoleTenFoot"


def _count(x, key):
    value = x.get(key)
    return value if isinstance(value, (int, float)) else 0


PRODUCTION = {
    "virtual-list-scroll": lambda x: (
        None
        if _count(x, "logicalRows") >= 1000 and 0 < _count(x, "windowedRows") < 100
        else f"windowing looks wrong: {x!r} (expect a small window over >=1000 rows)"
    ),
    "native-scroll-drag": lambda x: (
        None
        if _count(x, "dragMoves") > 0 and _count(x, "drops") > 0
        else f"the UIDragDetector path committed no drag: {x!r}"
    ),
    "dense-hud": lambda x: (
        None
        if _count(x, "activationCount") > 0 and x.get("activationText") == f"Boost x{x.get('activationCount')}"
        else f"the activate chain did not reach the mounted text: {x!r}"
    ),
    "stylesheet-state-churn": lambda x: (
        None if _count(x, "tagsPerPass") > 0 else f"no state tags classified: {x!r}"
    ),
    "async-image-grid": lambda x: None,
    "screen-lifecycle-churn": lambda x: None,
    "alert-present-dismiss": lambda x: (
        None
        if _count(x, "opens") > 0 and x.get("surfaceItems") == 3 and x.get("settled") == x.get("opens")
        else f"the alert did not present its three actions and settle dismissed each time: {x!r}"
    ),
    "picker-menu-open-close": lambda x: (
        None
        if _count(x, "opens") > 0
        and x.get("surfaceItems") == 6
        and x.get("presentation") == "picker"
        and x.get("settled") == x.get("opens")
        else f"the picker menu did not open with six rows and settle closed each time: {x!r}"
    ),
    "picker-segmented-textsize": lambda x: (
        None
        if isinstance(x.get("segmented"), dict)
        and x["segmented"].get("segments") == 3
        and x["segmented"].get("textSizeBefore") is not None
        and x["segmented"].get("textSizeBefore") != x["segmented"].get("textSizeAfter")
        else f"the segmented strip did not follow the preferred text size: {x!r}"
    ),
    "radial-menu-open-close": lambda x: (
        None
        if _count(x, "opens") > 0 and x.get("surfaceItems") == 6 and x.get("settled") == x.get("opens")
        else f"the radial did not open six sectors and settle closed each time: {x!r}"
    ),
    "dense-motion": lambda x: (
        None
        if _count(x, "springs") >= 20
        and _count(x, "springsMoving") >= 20
        and _count(x, "beats") > 0
        and _count(x, "beatCallbacks") > 0
        and 0 < _count(x, "windowedRows") < _count(x, "logicalRows")
        and _count(x, "motionSteps") > 0
        else f"the dense-motion frame did not do its work: {x!r}"
    ),
    "control-motion": lambda x: (
        None
        if _count(x, "rekeys") > 0
        and _count(x, "flips") > 0
        and _count(x, "pulses") > 0
        and _count(x, "pops") > 0
        and _count(x, "staggerHeld") > 0
        and _count(x, "flipsSeen") > 0
        and _count(x, "shakesSeen") > 0
        and _count(x, "popsSeen") > 0
        and _count(x, "motionSteps") > 0
        and _count(x, "motionTransactions") >= _count(x, "motionSteps")
        else f"the control-motion frame did not do its work: {x!r}"
    ),
}

THEMES = {
    "theme-swap-flat": (
        lambda s: s.get("metricChanges") == 0 and s.get("imageChanges") == 0 and _count(s, "paintChanges") > 0,
        "a palette-only swap must change paint rules and no metric rule or skin image",
    ),
    "theme-swap-metrics": (
        lambda s: _count(s, "metricChanges") > 0,
        "a metric-changing swap must change metric rules",
    ),
    "theme-swap-assets": (
        lambda s: _count(s, "metricChanges") > 0 and _count(s, "imageChanges") > 0,
        "an asset-backed swap must change metric rules and the skin images",
    ),
}


def _absent(path):
    print(f"check_perf_scenes: FAIL - {path} is missing; run tools/perf.sh first")
    return 1


def main() -> int:
    themes_mode = "--themes" in sys.argv
    if not os.path.isfile(PERF):
        return _absent(PERF)
    report = json.load(open(PERF))
    errors = []
    if report.get("schema") != "facet-perf/2":
        errors.append(f"unexpected schema {report.get('schema')!r}; expected facet-perf/2")
    if report.get("injectedRegression") is not None:
        errors.append("the artifact is an injected-regression run, not a workload record")
    by_scene = {}
    devices = set()
    for run in report["runs"]:
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
            predicate, why = THEMES[scene]
            swap = extras.get("themeSwap")
            if not isinstance(swap, dict) or not swap.get("measured"):
                errors.append(f"{scene}: no measured themeSwap in extras ({extras!r})")
                continue
            if not swap.get("controlsRetained"):
                errors.append(f"{scene}: the swap rebuilt the mounted controls ({swap!r})")
            if not predicate(swap):
                errors.append(f"{scene}: {why} ({swap!r})")
        else:
            problem = PRODUCTION[scene](extras)
            if problem:
                errors.append(f"{scene}: {problem}")
    if not themes_mode:
        grid = by_scene.get("async-image-grid")
        if grid is not None:
            stats = grid.get("async") or {}
            if stats.get("completed", 0) <= 0:
                errors.append(f"async-image-grid: the provider completed nothing ({stats!r})")
    if errors:
        for e in errors:
            print(f"FAIL {e}")
        stamp = report.get("generatedAt") or report.get("timestamp") or "unknown"
        print(f"note: read {PERF}, recorded {stamp}")
        return 1
    label = "theme-swap" if themes_mode else "production"
    print(f"perf scenes ok: {len(wanted)} {label} scenes did their work at {REFERENCE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
