#!/usr/bin/env python3
"""Gate check for the five-view device matrix.

Asserts the layout invariants the 2026-07-24 re-baseline established, AND that
every row's `capture` is a file that actually exists with the recorded content
hash. That last part is the point: before this, `capture` was a bare id that
pointed at nothing, so a row could claim visual evidence it could not produce.
"""
import hashlib
import json
import os
import sys

MATRIX = "artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json"
rows = json.load(open(MATRIX))["rows"]
errors = []

if len(rows) != 5:
    errors.append(f"expected 5 rows, found {len(rows)}")

for r in rows:
    rid = r.get("id", "?")
    if r["scroll"]["canvasShortBy"] > 0:
        errors.append(f"{rid}: scroll canvas is {r['scroll']['canvasShortBy']}px short of its content — the tail is unreachable")
    if r["solverDiagnostics"] != 0:
        errors.append(f"{rid}: solver reported {r['solverDiagnostics']} diagnostic(s); the layout does not fit")
    if not r["actionBar"]["pinnedBelowScroll"]:
        errors.append(f"{rid}: action bar is no longer pinned below the scroll region — the overlap defect is back")
    if not r["actionBar"]["onScreen"]:
        errors.append(f"{rid}: action bar falls outside the screen")
    if r["minVisibleButtonHeight"] < 44:
        errors.append(f"{rid}: smallest visible button is {r['minVisibleButtonHeight']}px, below the 44px floor")

    # director review 2026-07-24 — each of these was a real defect he spotted in
    # a capture, so each is now a thing the gate refuses to let back in
    bar = r.get("scrollBar")
    if bar and bar["contentUnderBarBy"] > 0:
        errors.append(
            f"{rid}: content runs {bar['contentUnderBarBy']}px under the scrollbar — "
            "the solver must reserve the bar's thickness off the cross axis"
        )
    ab = r["actionBar"]
    if not ab.get("heightsEqual", True):
        errors.append(f"{rid}: action buttons are ragged {ab.get('buttonHeights')} — the row's align=stretch is not reaching them")
    c = r.get("controlRowCentering")
    if c:
        # half a pixel is the integer grid's fault, not the layout's
        for field in ("labelMidY", "buttonMidY"):
            if abs(c[field] - c["rowMidY"]) > 0.5:
                errors.append(
                    f"{rid}: control row {field}={c[field]} vs rowMidY={c['rowMidY']} — "
                    "the row's children are no longer centred on its midline"
                )
        # the progress track must centre EXACTLY: an even track in an odd row
        # cannot, so the row's height is kept even by construction
        if abs(c.get("progressBarDelta", 0)) > 0.001:
            errors.append(
                f"{rid}: progress track is {c['progressBarDelta']}px off its row's midline — "
                "the row/track height parity has drifted"
            )
        btn = c.get("stepperButton")
        if btn and (btn["w"] < 44 or btn["h"] < 44):
            errors.append(f"{rid}: stepper target is {btn['w']}x{btn['h']}, below the 44px floor on an axis")

    cap = r.get("capture")
    if not cap:
        errors.append(f"{rid}: no capture recorded")
        continue
    if not os.path.isfile(cap):
        errors.append(f"{rid}: capture '{cap}' is not a file — a row cannot claim visual evidence it cannot produce")
        continue
    want = r.get("captureSha256_16")
    if want:
        got = hashlib.sha256(open(cap, "rb").read()).hexdigest()[:16]
        if got != want:
            errors.append(f"{rid}: capture '{cap}' hash {got} != recorded {want} — the row and its picture disagree")

if errors:
    for e in errors:
        print(f"matrix row check FAILED: {e}", file=sys.stderr)
    sys.exit(1)
print(f"matrix rows OK: {len(rows)} rows, invariants held, every capture present and matching")
