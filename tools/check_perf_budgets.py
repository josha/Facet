#!/usr/bin/env python3
"""Gate check: budgets come from a measured baseline AND a frame target, and no
device budget is ever satisfied by non-device data.

Three things must hold:

  1. every scene budget records both halves — the measured `observed_p95_ms`
     the trend budget derives from, and the `frameTargetHz`/`ceilingMs` the
     product target derives from. A budget with only one half cannot be
     argued with.
  2. the frame ceiling declares its one-way directionality in words, because
     the whole point is that passing it proves nothing.
  3. every declared device budget is `measured: false` while no hardware run
     exists, and the last perf run RECORDED that it skipped them. A silently
     omitted device budget reads as a passed one.
"""
import json
import os
import sys

BUDGETS = "bench/perf_budgets.json"
PERF = "artifacts/phase-4/perf.json"
DEVICE_DIR = "artifacts/cross-platform-proof/device"
DEVICE_CLASSES = {"phone-physical", "console-physical", "desktop-retail"}


def device_capture_rows(cls: str) -> int:
    """How many rows of `cls` exist in a stored capture. Zero means no evidence."""
    if not os.path.isdir(DEVICE_DIR):
        return 0
    total = 0
    for name in os.listdir(DEVICE_DIR):
        if not name.endswith(".json"):
            continue
        try:
            d = json.load(open(os.path.join(DEVICE_DIR, name)))
        except (OSError, ValueError):
            continue
        if d.get("evidenceClass") != cls:
            continue
        total += len(d.get("rows") or [])
    return total


def main() -> int:
    budgets = json.load(open(BUDGETS))
    errors = []

    if budgets.get("schema") != "luauui-perf-budgets/2":
        errors.append(f"unexpected schema {budgets.get('schema')!r}; expected luauui-perf-budgets/2")
    if budgets.get("evidenceClass") != "lune":
        errors.append("the scene budgets must be labelled with the evidence class that produced them")

    ceiling = budgets.get("frameCeiling") or {}
    if not (0 < (ceiling.get("uiShare") or 0) <= 1):
        errors.append(f"frameCeiling.uiShare is not a fraction: {ceiling.get('uiShare')!r}")
    if ceiling.get("directionality") != "one-way":
        errors.append("frameCeiling must declare its one-way directionality")
    if "proves NOTHING about a device" not in (ceiling.get("note") or ""):
        errors.append("frameCeiling.note must state that passing the ceiling proves nothing about a device")

    scenes = budgets.get("scenes") or {}
    if len(scenes) < 15:
        errors.append(f"only {len(scenes)} scene budgets; the Step-4 scene set is larger than that")
    for name, b in scenes.items():
        if not isinstance(b.get("observed_p95_ms"), (int, float)):
            errors.append(f"{name}: no measured baseline (observed_p95_ms)")
        if not isinstance(b.get("frameTargetHz"), (int, float)):
            errors.append(f"{name}: no frame target")
        if not isinstance(b.get("ceilingMs"), (int, float)):
            errors.append(f"{name}: no frame ceiling")
        elif b["ceilingMs"] <= 0:
            errors.append(f"{name}: non-positive frame ceiling")
        if not b.get("hint"):
            errors.append(f"{name}: no actionable hint")

    device = budgets.get("deviceBudgets") or {}
    missing = DEVICE_CLASSES - set(device)
    if missing:
        errors.append(f"device budgets missing for {sorted(missing)}")
    for cls, b in device.items():
        # CONDITIONAL ON THE EVIDENCE, not on the calendar. The first version
        # hard-failed on any measured:true, which meant the review packet's own
        # closing procedure for the physical rows would have broken this gate the
        # moment someone followed it. A device budget may be marked measured the
        # day a capture of that class exists, and not one minute before.
        if b.get("measured") is True:
            if not device_capture_rows(cls):
                errors.append(
                    f"device budget {cls} claims measured=true but no capture of that evidence class exists "
                    f"under {DEVICE_DIR}/ with rows in it — that would be a fabricated device claim"
                )
        elif b.get("measured") is not False:
            errors.append(f"device budget {cls}: measured must be true or false, not {b.get('measured')!r}")
        if not isinstance(b.get("budgetMs"), (int, float)) or b["budgetMs"] <= 0:
            errors.append(f"device budget {cls}: no positive budgetMs")
        if not isinstance(b.get("frameTargetHz"), (int, float)):
            errors.append(f"device budget {cls}: no frame target")

    report = json.load(open(PERF))
    budget_block = report.get("budget") or {}
    if budget_block.get("checked"):
        skipped = {s["class"] for s in budget_block.get("skippedDeviceBudgets") or []}
        # only the UNMEASURED budgets should appear as skipped. A measured one is
        # skipped by nobody — it was checked — so demanding that every declared
        # budget appear in the skip list failed the moment a reviewer followed
        # the packet and flipped one to measured.
        expected_skips = {cls for cls, b in device.items() if b.get("measured") is not True}
        if skipped != expected_skips:
            errors.append(
                f"the last perf run recorded skipped device budgets {sorted(skipped)} but "
                f"{sorted(expected_skips)} are declared unmeasured — an unreported skip reads as a pass"
            )

    if errors:
        for e in errors:
            print(f"FAIL {e}")
        return 1
    # COUNT, DO NOT ASSUME. This line used to say "all unmeasured" unconditionally
    # and printed it unchanged while a device budget was measured and being
    # enforced — a summary that describes the expected state rather than the
    # observed one is the same defect this stage exists to catch, one layer up.
    measured = sorted(k for k, v in device.items() if v.get("measured"))
    unmeasured = sorted(k for k, v in device.items() if not v.get("measured"))
    device_note = (
        f"{len(unmeasured)} device budget(s) declared and unmeasured (PENDING_PHYSICAL: {', '.join(unmeasured)})"
        if unmeasured
        else "0 unmeasured device budgets"
    )
    if measured:
        device_note += f"; {len(measured)} MEASURED and enforced ({', '.join(measured)})"
    print(f"perf budgets ok: {len(scenes)} scene budgets carry baseline+frame target; {device_note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
