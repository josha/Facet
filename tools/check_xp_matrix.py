#!/usr/bin/env python3
"""Gate check: the Step-4 five-view device matrix was actually driven, and every
row's picture and trace agree.

The failures this prevents, in order of how easily they happen:

  1. a row cites a capture that does not exist, or that has been retaken since
     the trace was written — so the picture and the numbers describe different
     moments;
  2. a row claims a device the plan's role does not describe (a television in
     the tablet row, a handheld in the console row);
  3. the console row measures a large desktop, because the ten-foot facts never
     engaged;
  4. a row quietly forgets to say what it cannot prove.
"""
import hashlib
import json
import os
import sys

ROOT = "artifacts/cross-platform-proof"
MATRIX = f"{ROOT}/matrix.json"
EXPECTED_ROWS = [
    "compact-phone-portrait",
    "compact-phone-landscape",
    "tablet-landscape",
    "desktop-standard",
    "console-ten-foot",
]


def main() -> int:
    report = json.load(open(MATRIX))
    errors = []

    if report.get("schema") != "luauui-device-matrix/1":
        errors.append(f"unexpected schema {report.get('schema')!r}")
    if report.get("evidenceClass") != "studio-emulated":
        errors.append("the matrix must be labelled studio-emulated; it is not a device result")
    if report.get("problems"):
        errors.append(f"the assembler reported problems: {report['problems']}")

    rows = {r["row"]: r for r in report.get("rows", [])}
    missing = [r for r in EXPECTED_ROWS if r not in rows]
    if missing:
        errors.append(f"rows never driven: {missing}")

    phone_devices = set()
    for rid in EXPECTED_ROWS:
        r = rows.get(rid)
        if r is None:
            continue
        if not r.get("ok"):
            errors.append(f"{rid}: the driver failed this row")

        # capture and trace must describe the same moment
        cap = r.get("capture")
        if not cap:
            errors.append(f"{rid}: no capture")
        else:
            path = os.path.join(ROOT, cap)
            if not os.path.isfile(path):
                errors.append(f"{rid}: capture {path} does not exist")
            else:
                sha = hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]
                if sha != r.get("captureSha256_16"):
                    errors.append(f"{rid}: capture drifted since the trace was written ({path})")

        geom = r.get("geometry") or {}
        if geom.get("solverDiagnostics", -1) != 0:
            errors.append(f"{rid}: solver reported {geom.get('solverDiagnostics')} diagnostic(s)")
        if geom.get("offscreenNodes"):
            errors.append(f"{rid}: {len(geom['offscreenNodes'])} unclipped node(s) outside the viewport")
        if geom.get("unfitText"):
            errors.append(f"{rid}: {len(geom['unfitText'])} text node(s) do not fit")

        if not r.get("cannotProve"):
            errors.append(f"{rid}: does not state what it cannot prove")
        ident = r.get("identity") or {}
        for field in ("studioVersion", "sourceStamp", "libraryVersion", "scenario"):
            if not ident.get(field):
                errors.append(f"{rid}: identity is missing {field}")

        dev = r.get("device") or {}
        if not dev.get("why"):
            errors.append(f"{rid}: does not record WHY this device was chosen")

        # every row states its input situation: either a trace, or a reason there
        # is none. Silence used to be indistinguishable from "we forgot".
        inp = r.get("input")
        if not isinstance(inp, dict):
            errors.append(f"{rid}: no input block — a row must carry a trace or an explicit reason it has none")
        elif inp.get("path") == "none":
            if not inp.get("reason"):
                errors.append(f"{rid}: declares no input but gives no reason")
        else:
            raw = (inp.get("rawEvent") or {}).get("began")
            if not raw:
                errors.append(f"{rid}: claims an input path but records no raw native event")
            elif raw.get("gameProcessed") is not True:
                errors.append(f"{rid}: the raw input event was not consumed by the GUI — the press missed")
            if not inp.get("effect"):
                errors.append(f"{rid}: records a raw event but no paired effect")
            if inp.get("path") != "none" and not inp.get("calibration"):
                errors.append(f"{rid}: injected input with no recorded calibration")

        # role-specific: the two refusals the selection policy exists for
        if rid == "tablet-landscape":
            excluded = {e["id"] for e in dev.get("excluded", [])}
            if not excluded:
                errors.append("tablet-landscape: nothing was excluded; the density filter did not run")
        if rid == "console-ten-foot":
            derived = r.get("derived") or {}
            env = r.get("env") or {}
            if env.get("displaySize") != "Large":
                errors.append("console-ten-foot: displaySize is not Large — this row measured a desktop")
            if derived.get("distanceProfile") != "ten-foot":
                errors.append("console-ten-foot: the ten-foot presentation never engaged")
            if derived.get("typographyScale") != 1.5:
                errors.append("console-ten-foot: the ten-foot type floor did not apply")
            over = derived.get("effectiveOverscanInsets") or {}
            if not (over.get("left", 0) > 0 and over.get("top", 0) > 0):
                errors.append("console-ten-foot: no effective overscan margins — a TV would clip the edges")
        if rid.startswith("compact-phone"):
            phone_devices.add(dev.get("id"))

    if len(phone_devices) > 1:
        errors.append(
            f"the two phone rows used different devices {sorted(phone_devices)}; an orientation row must "
            "rotate ONE device, or it compares two layouts"
        )

    # ONE BUILD, or an explicit statement that it was not. The five rows are
    # presented as one coherent proof; if they came from different synced trees,
    # the reader has to be told rather than left to diff five stamps.
    stamps = {r.get("identity", {}).get("sourceStamp") for r in rows.values()}
    stamps.discard(None)
    if len(stamps) > 1 and not report.get("sourceStampsDiffer"):
        errors.append(
            f"the rows span {len(stamps)} source builds {sorted(stamps)} and the report does not say so; "
            "add a `sourceStampsDiffer` justification or re-drive them on one build"
        )

    if not report.get("honestBoundary"):
        errors.append("the matrix does not state its evidence boundary")

    if errors:
        for e in errors:
            print(f"FAIL {e}")
        return 1
    print(f"matrix ok: {len(EXPECTED_ROWS)} rows driven, captures hash-pinned, ten-foot presentation verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
