#!/usr/bin/env python3
"""Gate check: the Studio device capture carries the whole metric ledger, its
preflight, its fixture state and its build identity — and it lives in a file
that cannot be mistaken for a device result.

The physical evidence classes must appear here with NO ROWS. That is the point:
a reader has to be able to see that the phone and console rows are open, rather
than inferring it from their absence.
"""
import json
import os
import sys

PATH = "artifacts/cross-platform-proof/device/studio-emulated.json"
HEADLESS = "artifacts/phase-4/perf.json"
METRICS = [
    "M1_frameWorkMs",
    "M2_updateMs",
    "M3_instances",
    "M4_connections",
    "M5_memory",
    "M6_inputToCommittedWrite",
    "M7_themeSwap",
]
PHYSICAL = ("desktop-retail", "phone-physical", "console-physical")


def main() -> int:
    errors = []
    if not os.path.isfile(PATH):
        print(f"FAIL {PATH} does not exist")
        return 1
    d = json.load(open(PATH))

    # IMMUTABLE EVIDENCE: this capture was recorded before the Facet rename and
    # keeps the schema string it was written with. A frozen artifact is not
    # re-stamped by a rebrand.
    if d.get("schema") != "luauui-device-perf/1":
        errors.append(f"unexpected schema {d.get('schema')!r}")
    if d.get("evidenceClass") != "studio-emulated":
        errors.append("this capture must be labelled studio-emulated")
    if os.path.abspath(PATH) == os.path.abspath(HEADLESS):
        errors.append("the Studio capture and the headless trend file must be separate files")

    inst = d.get("instrument") or {}
    if not inst.get("cannotProve"):
        errors.append("the instrument does not state what it cannot prove")

    sep = d.get("separationOfClasses") or {}
    for cls in PHYSICAL:
        if cls not in sep:
            errors.append(f"the class separation does not mention {cls}")
        elif "NO ROWS" not in str(sep[cls]):
            errors.append(f"{cls} is not declared empty; a physical row must be visibly open, not silently absent")

    rows = d.get("rows") or []
    if len(rows) < 5:
        errors.append(f"only {len(rows)} rows captured; the canonical matrix has five views")
    for r in rows:
        where = r.get("row", "?")
        if r.get("evidenceClass") != "studio-emulated":
            errors.append(f"{where}: wrong evidence class {r.get('evidenceClass')!r}")
        pre = r.get("preflight") or {}
        if not pre.get("passed"):
            errors.append(f"{where}: no passing preflight stored with the numbers")
        if not r.get("fixtureState"):
            errors.append(f"{where}: no fixture state stored")
        ident = r.get("identity") or {}
        for field in ("studioVersion", "sourceStamp", "libraryVersion", "scenario"):
            if not ident.get(field):
                errors.append(f"{where}: identity missing {field}")
        metrics = r.get("metrics") or {}
        for m in METRICS:
            if m not in metrics:
                errors.append(f"{where}: metric {m} missing entirely")
                continue
            v = metrics[m]
            if isinstance(v, dict) and v.get("measured") is False and not v.get("reason"):
                errors.append(f"{where}: {m} is unmeasured but gives no reason")
        # M1 and M2 must both be real here — this is the instrument that can see them
        m1 = metrics.get("M1_frameWorkMs") or {}
        if isinstance(m1, dict) and m1.get("measured"):
            # and M1 must NAME its headline series: "frame work" is several
            # different quantities on Roblox and they do not always agree
            if not m1.get("headline"):
                errors.append(f"{where}: M1 does not name which series its headline numbers are")
            for series in ("renderCpu", "renderGpu", "frameTime", "heartbeatInterval"):
                if series not in m1:
                    errors.append(f"{where}: M1 omits the {series} series")
        for m in ("M1_frameWorkMs", "M2_updateMs"):
            v = metrics.get(m)
            if not (isinstance(v, dict) and v.get("measured")):
                errors.append(f"{where}: {m} must be measured in a Studio capture")

        # M5's GUI figure must be present OR explain itself. It dropped silently
        # out of every artifact once, because the producer published `guiMb` and
        # the consumer read `guiInstanceMb`.
        m5 = metrics.get("M5_memory") or {}
        if isinstance(m5, dict) and m5.get("measured"):
            if "guiMb" not in m5 and "guiMbUnavailable" not in m5:
                errors.append(f"{where}: M5 carries neither a GUI memory figure nor a reason it is absent")
            if "memoryTrackingEnabled" not in m5:
                errors.append(f"{where}: M5 does not record whether per-tag memory tracking was on")

    if errors:
        for e in errors:
            print(f"FAIL {e}")
        return 1
    # SAY WHAT THIS FILE DECLARES, NOT WHAT THE DIRECTORY HOLDS. The old summary
    # said "physical classes declared empty" full stop, and printed it unchanged
    # next to a physical capture sitting in the same directory — a sentence that
    # read as a check on the whole stage while only ever inspecting one file.
    others = sorted(
        f for f in os.listdir(os.path.dirname(PATH))
        if f.endswith(".json") and os.path.join(os.path.dirname(PATH), f) != PATH
    )
    alongside = f"; {len(others)} other capture file(s) in the same directory ({', '.join(others)}) — NOT checked here" if others else ""
    print(
        f"device capture ok: {len(rows)} studio-emulated rows with the full metric ledger; "
        f"this file declares every physical class empty{alongside}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
