#!/usr/bin/env python3
import json
import os
import re
import sys

ART = "artifacts/performance-stress-places"
STUDIO_DIR = f"{ART}/studio"
PERF = "artifacts/phase-4/perf.json"
PROOF = f"{ART}/prove-perf-gate.json"
LAB = "examples/performance/lab"


class Pending(Exception):
    pass


def load(path):
    with open(path) as fh:
        return json.load(fh)


def source_version(path, pattern):
    with open(path) as fh:
        match = re.search(pattern, fh.read())
    assert match, f"cannot read the version from {path}"
    return match.group(1)


def current_versions():
    return {
        "scenarioVersion": source_version(f"{LAB}/perf_lab.luau", r'lab\.VERSION\s*=\s*"([^"]+)"'),
        "datasetVersion": source_version(f"{LAB}/dataset.luau", r'dataset\.VERSION\s*=\s*"([^"]+)"'),
        "rowVersion": source_version(f"{LAB}/rows.luau", r'\bVERSION\s*=\s*"([^"]+)"'),
    }


def studio_rows(evidence_class):
    rows = []
    if os.path.isdir(STUDIO_DIR):
        for name in sorted(os.listdir(STUDIO_DIR)):
            if not name.endswith(".json"):
                continue
            doc = load(os.path.join(STUDIO_DIR, name))
            candidates = [doc] if isinstance(doc, dict) and doc.get("schema") else []
            if isinstance(doc, dict):
                candidates += [r for key in ("rows", "captures") if isinstance(doc.get(key), list) for r in doc[key]]
            for row in candidates:
                if isinstance(row, dict) and row.get("schema") == "facet-perf-capture/1":
                    if row.get("evidenceClass") == evidence_class:
                        rows.append(row)
    versions = current_versions()
    return [r for r in rows if all(r.get(k) == v for k, v in versions.items())]


def require_rows(evidence_class, what):
    rows = studio_rows(evidence_class)
    if not rows:
        raise Pending(
            f"no {evidence_class} capture row at the current lab workload versions in {STUDIO_DIR}; "
            f"record {what} with the performance lab place (examples/performance.project.json)"
        )
    return rows


def studio():
    rows = require_rows("studio", "a clean Studio capture")
    clean = [r for r in rows if r.get("cleanCapture") is True]
    assert clean, "no Studio capture was taken with the overlay dismissed (cleanCapture)"
    for r in clean:
        viewport = r.get("viewport") or {}
        assert (viewport.get("x") or viewport.get("X") or 0) > 1, "the 1x1 viewport trap"
        assert (r.get("frame") or {}).get("measured") is True, "the frame samples are not measured"
    return f"studio: {len(clean)} clean Studio capture row(s) at the current workload versions"


def native_reference():
    rows = require_rows("studio", "the dense-scroll and dense-scroll-native pair")
    facet = [r for r in rows if r.get("scenario") == "dense-scroll" and r.get("cleanCapture") is True]
    native = [r for r in rows if r.get("scenario") == "dense-scroll-native" and r.get("cleanCapture") is True]
    if not facet or not native:
        raise Pending("the dense-scroll versus dense-scroll-native pair is not recorded")
    assert len(facet) >= 3 and len(native) >= 3, "three repeats per side"
    for r in facet + native:
        assert r.get("seed") == 1 and r.get("rows") == 2000, "the pair must use seed 1 and 2000 rows"
    return f"native reference: {len(facet)}+{len(native)} clean repeats at seed 1, 2000 rows"


def theme_cost():
    rows = require_rows("studio", "a neutral and an ornate theme capture")
    themes = {r.get("theme") for r in rows}
    if not {"facet-neutral", "fantasy_ornate"} <= themes:
        raise Pending(f"theme cost needs neutral and ornate captures; recorded themes: {sorted(t for t in themes if t)}")
    return "theme cost: neutral and ornate captures recorded"


def large_text():
    rows = require_rows("studio", "a preferred text size sweep")
    sizes = {(r.get("counters") or {}).get("preferredTextSize") for r in rows} - {None}
    if len(sizes) < 2:
        raise Pending("no capture records more than one preferred text size")
    return f"large text: {len(sizes)} preferred text sizes captured"


def device_matrix():
    rows = require_rows("emulator", "the Studio device emulator matrix")
    viewports = {json.dumps(r.get("viewport"), sort_keys=True) for r in rows}
    assert len(viewports) >= 5, f"five emulated viewports needed, found {len(viewports)}"
    return f"device matrix: {len(viewports)} emulated viewports recorded as emulator class"


def headless_linkage():
    src = open("bench/perf_scenes.luau").read()
    assert 'require("../examples/performance/lab/dataset")' in src, "scenes must share the lab dataset"
    assert 'require("../examples/performance/lab/rows")' in src, "scenes must share the lab row shape"
    assert 'require("../examples/performance/lab/workloads")' in src, "scenes must share the lab workloads"
    d = load(PERF)
    names = {r["scene"] for r in d["runs"]}
    assert "lab-dense-scroll" in names and "lab-collection-churn" in names
    assert d["status"] in ("PASS", "FAIL"), f"the perf run did not complete: {d['status']}"
    assert d.get("injectedRegression") is None, "a falsification artifact is not a committed baseline"
    for r in d["runs"]:
        assert r.get("evidenceClass") == "lune", r.get("scene")
    return f"headless linkage: shared dataset, rows and workloads; both lab scenes in a clean {d['status']} artifact"


def falsifiable():
    d = load(PROOF)
    assert d["scene"] == "lab-dense-scroll", "the falsification must use a lab-linked scene"
    assert d["injectedExitCode"] == 1
    assert d["namedTheScene"] is True
    assert d["artifactStampedAsInjected"] is True
    kinds = {v["kind"] for v in d["violations"] if v.get("scene") == d["scene"]}
    assert "trend" in kinds and "frame-ceiling" in kinds, kinds
    if d["cleanRunPassed"] is not True:
        raise Pending("the clean rerun failed its host timing budgets, so the injected failure is not isolated")
    assert "FACET_PERF_INJECT_REGRESSION" in open("tools/lune/perf.luau").read()
    return "falsifiable: an injected regression reddened both budgets on the lab scene"


def perf_gate():
    d = load(PERF)
    assert d.get("injectedRegression") is None, "a falsification artifact is not a gate verdict"
    skipped = {s["class"] for s in d["budget"]["skippedDeviceBudgets"]}
    assert "phone-physical" in skipped, "the device budget must be skipped, never satisfied from host rows"
    violations = d["budget"]["violations"]
    if d["status"] != "PASS" or violations:
        raise Pending(f"{len(violations)} host timing violation(s): {sorted({(v['scene'], v['kind']) for v in violations})}")
    return "perf gate: PASS with the phone budget explicitly unchecked"


def budgets():
    d = load("bench/perf_budgets.json")
    assert d["deviceBudgets"]["phone-physical"]["measured"] is False, (
        "the low-end budget must stay unmeasured until a real device capture exists"
    )
    for scene in ("lab-dense-scroll", "lab-collection-churn"):
        e = d["scenes"][scene]
        assert e.get("scopedBaseline") is True, f"{scene} must be a scoped baseline"
        assert e["total_p95_ms"] > e["observed_p95_ms"], scene
    return "budgets: phone budget unmeasured; both lab scenes scoped-baselined"


SECTIONS = {
    "native-reference": native_reference,
    "theme-cost": theme_cost,
    "large-text": large_text,
    "headless-linkage": headless_linkage,
    "studio": studio,
    "device-matrix": device_matrix,
    "falsifiable": falsifiable,
    "perf-gate": perf_gate,
    "budgets": budgets,
}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in SECTIONS:
        print(f"usage: {sys.argv[0]} <{' | '.join(SECTIONS)}>")
        return 2
    try:
        print(SECTIONS[sys.argv[1]]())
        return 0
    except Pending as exc:
        print(f"check_perf_gate_evidence [{sys.argv[1]}]: FAIL_ENVIRONMENT - {exc}")
        return 2
    except AssertionError as exc:
        print(f"check_perf_gate_evidence [{sys.argv[1]}]: FAIL - {exc}")
        return 1
    except (OSError, KeyError, ValueError) as exc:
        print(f"check_perf_gate_evidence [{sys.argv[1]}]: FAIL - missing or malformed evidence: {exc!r}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
