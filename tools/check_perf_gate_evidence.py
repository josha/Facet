#!/usr/bin/env python3
"""Artifact assertions for the `performance-stress-places` gate (roadmap Step 9).

WHY THIS IS A FILE AND NOT INLINE IN THE MANIFEST. The gate manifest's `run` strings
are single-quoted Luau strings; an inline `python3 -c "..."` with real newlines in it
collapses the string and silently corrupts the manifest (it did, once, while this
stage was being built — the same trap `docs/lessons/luau-interpolated-strings-single-line.md`
records for a neighbouring shape). Putting the assertions here keeps every check a
one-liner, makes them readable, and lets them be mutation-tested directly.

Each section is one gate check. A section that finds nothing to assert is a bug in
this file, not a pass — every section must make at least one assertion.

Usage:  python3 tools/check_perf_gate_evidence.py <section>
Sections: native-reference | theme-cost | large-text | scopes | headless-linkage
          | studio | device-matrix | falsifiable | perf-gate | budgets | prior-gates
"""

import json
import os
import re
import sys

ART = "artifacts/performance-stress-places"


def load(path):
    with open(path) as fh:
        return json.load(fh)


def studio():
    return load(f"{ART}/studio/perf-lab.json")


def native_reference():
    c = studio()["denseScrollVsNativeReference"]
    assert c["cleanCapture"] is True, "the comparison must be taken with the overlay dismissed"
    # `luauui` is the key the pre-rename Studio capture recorded; the artifact is
    # immutable evidence and is read under the name it was written with.
    assert len(c["luauui"]["repeats"]) == 3, "three identical repeats per side"
    assert len(c["nativeReference"]["repeats"]) == 3
    assert c["luauui"]["ownGuiObjects"] > 0 and c["nativeReference"]["guiObjects"] > 0
    # the honest denominator: the floor's omissions travel with the ratio
    assert len(c["whatTheReferenceLacks"]) >= 6, "the reference's capability gaps must be recorded"
    assert c["settings"]["seed"] == 1 and c["settings"]["rows"] == 2000
    return "native reference: 3+3 repeats, clean capture, capability ledger present"


def theme_cost():
    d = studio()["themeCost"]
    assert d["ornatePackage"] == "fantasy_ornate", d["ornatePackage"]
    legs = {l["leg"]: l for l in d["legs"]}
    for k in ("install-ornate", "steady-ornate", "teardown-to-flat", "steady-flat"):
        assert k in legs, f"missing leg {k}"
    assert legs["install-ornate"]["packageCompiled"] is True, "the ornate package must actually compile"
    assert legs["install-ornate"]["instancesAfter"] > legs["install-ornate"]["instancesBefore"]
    # install and steady state are captured APART, and the ornate skin really is dearer
    assert legs["steady-ornate"]["steadyP50"] > legs["steady-flat"]["steadyP50"]
    return "theme cost: install/steady/teardown isolated, ornate steady > flat steady"


def large_text():
    d = studio()["largeTextAndPreference"]
    assert [x["offset"] for x in d["preferenceSweepMs"]] == [0, 4, 10, 14], "the four measured offsets"
    assert d["movingLabelBound"]["maxAllowed"] == 1
    assert d["movingLabelBound"]["observedFindings"] == 0
    return "large text: four offsets swept, moving-label cap 1 with 0 findings"


def scopes():
    # READ THE DECLARED SET OUT OF THE SOURCE, never a hardcoded count. The first
    # version asserted `len(timers) == 8` against an artifact that claimed eight names
    # were "the whole closed set" — while the module declared nine. That froze a wrong
    # number into the gate: appending the truthful ninth timer would have REDDENED it.
    # (Phase-gate review F-2.) The ninth, `Facet/reset`, was simply not exercised in
    # that capture; a scope enters the timer table only once it has run.
    declared = set()
    for line in open("src/core/profile.luau"):
        line = line.strip()
        if line.startswith("--"):
            continue
        m = re.match(r'^(\w+) = "(Facet/[\w/]+)",$', line)
        if m:
            declared.add(m.group(2))
    assert len(declared) >= 8, f"could not read the scope set from src/core/profile.luau (got {declared})"

    d = studio()["microprofilerScopes"]
    # The capture is IMMUTABLE EVIDENCE recorded before the Facet rename, so its bar
    # names still carry the pre-rename prefix. Normalise the SPELLING of the prefix
    # before comparing; the claim — every declared scope was observed live and no
    # undeclared timer appeared — is exactly the one it always made.
    seen = {re.sub(r"^LuauUI/", "Facet/", t["name"]) for t in d["timers"]}
    for name in seen:
        assert name.startswith("Facet/"), name
    missing = declared - seen
    assert not missing, f"declared scopes never observed in a live capture: {sorted(missing)}"
    extra = seen - declared
    assert not extra, f"the capture contains Facet timers that are not declared: {sorted(extra)}"
    assert d["allDeclaredScopesVisible"] is True
    assert d["balanceLive"]["opens"] == d["balanceLive"]["closes"], d["balanceLive"]
    assert d["balanceLive"]["balanced"] is True
    return f"scopes: all {len(declared)} declared Facet/* timers found live, opens == closes"


def headless_linkage():
    src = open("bench/perf_scenes.luau").read()
    assert 'require("../examples/performance/lab/dataset")' in src, "scenes must share the lab dataset"
    assert 'require("../examples/performance/lab/rows")' in src, "scenes must share the lab row shape"
    d = load("artifacts/phase-4/perf.json")
    names = {r["scene"] for r in d["runs"]}
    assert "lab-dense-scroll" in names and "lab-collection-churn" in names
    assert d["status"] == "PASS", d["status"]
    assert d.get("injectedRegression") is None, "a falsification artifact is not a committed baseline"
    # and no headless row may wear a device class
    for r in d["runs"]:
        assert r.get("evidenceClass") != "phone-physical", r.get("scene")
    return "headless linkage: shared dataset/rows, both lab scenes in a clean PASS artifact"


def studio_section():
    d = studio()
    p = d["preflight"]
    for k in ("ok", "sourceStampChecked", "viewportNot1x1", "mountedExactlyOnce"):
        assert p[k] is True, k
    assert p["viewport"]["x"] > 1 and p["viewport"]["y"] > 1, "the 1x1 instrument trap"
    assert d["evidenceClass"] == "studio"
    f = d["boundedVirtualizationFaultProof"]
    assert f["mountRefused"] is True, "the window fault must be seen to bite live"
    assert "NOT bounded" in f["message"]
    assert d["captureRow"]["admissible"] is True
    for c in d["captures"]:
        assert os.path.exists(c), f"missing capture {c}"
    assert os.path.exists(f"{ART}/studio/pl9-capture-set.json")
    return "studio: preflight clean, fault proven live, capture admissible, images on disk"


def device_matrix():
    d = load(f"{ART}/studio/device-matrix.json")
    assert d["evidenceClass"] == "emulator", "these rows are emulation and must say so"
    # the boundary has to DENY the device claim in words, not merely omit it. Asserted
    # on substance rather than on a single word — the first version looked for "never"
    # and failed against a boundary paragraph that said the same thing differently.
    boundary = d["honestBoundary"]
    assert "EMULATION" in boundary, "the boundary must name what this evidence class is"
    assert "PENDING_PHYSICAL" in boundary, "the boundary must point at the rows it cannot close"
    rows = {r["row"]: r for r in d["rows"]}
    for k in (
        "compact-phone-portrait",
        "compact-phone-landscape",
        "tablet-landscape",
        "desktop-standard",
        "console-ten-foot",
    ):
        r = rows[k]
        assert r["selectOk"] is True, k
        assert r["status"] == "PASS_AUTOMATED", k
        assert r["mountedRows"] <= r["windowBound"], k
    assert d["simulationStopped"] is True
    return "device matrix: five rows selected, bounded window at each, simulation stopped"


def falsifiable():
    d = load(f"{ART}/prove-perf-gate.json")
    assert d["scene"] == "lab-dense-scroll", "the falsification must use a LAB-linked scene"
    assert d["injectedExitCode"] == 1
    assert d["namedTheScene"] is True
    assert d["artifactStampedAsInjected"] is True
    kinds = {v["kind"] for v in d["violations"]}
    assert "trend" in kinds and "frame-ceiling" in kinds, kinds
    assert "FACET_PERF_INJECT_REGRESSION" in open("tools/lune/perf.luau").read()
    return "falsifiable: an injected regression reddened both budgets on the lab scene"


def perf_gate():
    d = load("artifacts/phase-4/perf.json")
    assert d["status"] == "PASS", d["status"]
    assert len(d["budget"]["violations"]) == 0
    skipped = {s["class"] for s in d["budget"]["skippedDeviceBudgets"]}
    assert "phone-physical" in skipped, "the device budget must be SKIPPED, never satisfied from host rows"
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


def prior_gates():
    """Every red check must carry a recorded standalone verdict.

    This replaced an inherited rule that allowed a FAIL line to carry only four
    hardcoded bench check NAMES. That trusted a name instead of demanding evidence and
    would have excused a genuinely broken check called one of the four. The rule here is
    per-check: whatever came back red, the supplement must state what it does on its own.

    It is not a formality. It caught a real regression in this very stage —
    `performance-unregressed` was red in the sweep AND red standalone, which is the
    discriminator between load noise and a defect. See optimization-log.md L-6.
    """
    lines = open(f"{ART}/prior-gates.txt").read().splitlines()
    assert "DONE" in lines, "roll-up truncated — a sweep that did not finish cannot read as complete"
    passes = sum(1 for l in lines if l.startswith("PASS "))
    assert passes >= 18, f"structural PASS floor: {passes}"

    sup = open(f"{ART}/prior-gates-supplement.md").read()
    reds, i = [], 0
    while i < len(lines):
        if lines[i].startswith("FAIL "):
            gate = lines[i].split()[1]
            j = i + 1
            while j < len(lines) and lines[j].startswith("      "):
                parts = lines[j].split()
                # FAIL_ENVIRONMENT / PENDING* are the physical and human rows this
                # repository leaves open by design; they are not regressions.
                if parts[0] == "FAIL_RECOVERABLE":
                    reds.append((gate, parts[1]))
                j += 1
            i = j
        else:
            i += 1

    missing = []
    for gate, check in reds:
        if f"{gate} :: {check} :: standalone PASS" not in sup:
            missing.append(f"{gate} :: {check}")
    assert not missing, (
        "red check(s) with no recorded standalone verdict in prior-gates-supplement.md: "
        + "; ".join(missing)
    )
    return (
        f"prior gates: {passes} PASS, {len(reds)} red check(s), every one dispositioned "
        "with a standalone verdict"
    )


SECTIONS = {
    "native-reference": native_reference,
    "theme-cost": theme_cost,
    "large-text": large_text,
    "scopes": scopes,
    "headless-linkage": headless_linkage,
    "studio": studio_section,
    "device-matrix": device_matrix,
    "falsifiable": falsifiable,
    "perf-gate": perf_gate,
    "budgets": budgets,
    "prior-gates": prior_gates,
}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in SECTIONS:
        print(f"usage: {sys.argv[0]} <{' | '.join(SECTIONS)}>")
        return 2
    try:
        print(SECTIONS[sys.argv[1]]())
        return 0
    except AssertionError as exc:
        print(f"check_perf_gate_evidence [{sys.argv[1]}]: FAIL — {exc}")
        return 1
    except (OSError, KeyError, ValueError) as exc:
        print(f"check_perf_gate_evidence [{sys.argv[1]}]: FAIL — missing or malformed evidence: {exc!r}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
