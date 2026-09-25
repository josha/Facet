#!/usr/bin/env python3
import json
import os
import re
import sys

STUDIO_DIR = "artifacts/performance-stress-places/studio"
DEVICE_DIR = "artifacts/cross-platform-proof/device"
ACCEPTANCE = "artifacts/performance-stress-places/acceptance.md"

REQUIRED = [
    "schema", "evidenceClass", "capturedAtIso", "repeat_",
    "scenario", "scenarioVersion", "datasetVersion", "rowVersion", "implementation",
    "rows", "seed", "content", "theme", "datasetDigest", "resourceState",
    "frameworkVersion", "sourceStamp", "placeName", "viewport", "orientation",
    "graphicsQualityLevel", "frameTarget", "studioVersion", "deviceLabel", "thermalNote",
    "warmupFrames", "captureFrames", "cleanCapture", "profilerScopes",
    "frame", "counters", "scopes",
]
REQUIRED_DEVICE = ["deviceModel", "osVersion", "clientVersion", "powerState"]
DEVICE_CLASSES = {"phone-physical", "desktop-retail"}
HOST_CLASSES = {"lune", "studio", "emulator"}

SCHEMA = "facet-perf-capture/1"
SCHEMAS = (SCHEMA, "luauui-perf-capture/1")

VERSION_SOURCES = {
    "rowVersion": ("examples/performance/lab/rows.luau", r'\bVERSION\s*=\s*"([^"]+)"'),
    "datasetVersion": ("examples/performance/lab/dataset.luau", r'dataset\.VERSION\s*=\s*"([^"]+)"'),
    "scenarioVersion": ("examples/performance/lab/perf_lab.luau", r'lab\.VERSION\s*=\s*"([^"]+)"'),
}


def capture_contract():
    with open("examples/performance/lab/capture.luau") as fh:
        source = fh.read()
    block = re.search(r"capture\.REQUIRED\s*=\s*\{(.*?)\n\}", source, re.S)
    device = re.search(r"capture\.REQUIRED_DEVICE\s*=\s*\{([^}]*)\}", source)
    if block is None or device is None:
        raise SystemExit("check_perf_captures: cannot read capture.REQUIRED from capture.luau")
    return re.findall(r'"([^"]+)"', block.group(1)), re.findall(r'"([^"]+)"', device.group(1))


def source_versions():
    out = {}
    for field, (path, pattern) in VERSION_SOURCES.items():
        with open(path) as fh:
            m = re.search(pattern, fh.read())
        if m is None:
            raise SystemExit(f"check_perf_captures: cannot read {field} from {path}")
        out[field] = m.group(1)
    return out


def missing(row, keys):
    out = []
    for k in keys:
        v = row.get(k)
        if v is None or v == "" or (isinstance(v, str) and "unknown" in v):
            out.append(k)
    return out


def check_row(row, where):
    problems = []
    if row.get("schema") not in SCHEMAS:
        problems.append(f"{where}: schema is {row.get('schema')!r}, expected one of {SCHEMAS!r}")
    cls = row.get("evidenceClass")
    if cls not in DEVICE_CLASSES and cls not in HOST_CLASSES:
        problems.append(f"{where}: unknown evidenceClass {cls!r}")
    for k in missing(row, REQUIRED):
        problems.append(f"{where}: missing or unrecorded {k}")
    if cls in DEVICE_CLASSES:
        for k in missing(row, REQUIRED_DEVICE):
            problems.append(f"{where}: a {cls} row is missing {k}")
        sv = row.get("studioVersion")
        if sv not in (None, "", "n/a"):
            problems.append(f"{where}: a {cls} row carries studioVersion {sv!r}; a retail client has none")
    digest = row.get("datasetDigest")
    if digest is not None and len(str(digest)) != 8:
        problems.append(f"{where}: datasetDigest {digest!r} is not the 8-hex-digit fingerprint")
    return problems


def collect_rows(path):
    with open(path) as fh:
        doc = json.load(fh)
    if isinstance(doc, dict) and doc.get("schema") in SCHEMAS:
        return [(doc, os.path.basename(path))]
    if isinstance(doc, dict) and isinstance(doc.get("row"), dict) and doc["row"].get("schema") in SCHEMAS:
        return [(doc["row"], os.path.basename(path))]
    rows = []
    for key in ("rows", "captures"):
        for i, r in enumerate(doc.get(key, []) or []):
            if isinstance(r, dict) and r.get("schema") in SCHEMAS:
                rows.append((r, f"{os.path.basename(path)}[{key}][{i}]"))
    return rows


def main():
    problems, checked, classes, all_rows = [], 0, {}, []
    for d in (STUDIO_DIR, DEVICE_DIR):
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if not name.endswith(".json"):
                continue
            for row, where in collect_rows(os.path.join(d, name)):
                checked += 1
                classes[row.get("evidenceClass")] = classes.get(row.get("evidenceClass"), 0) + 1
                all_rows.append((row, where))
                problems += check_row(row, where)

    current = source_versions()
    required, required_device = capture_contract()
    if required != REQUIRED:
        problems.append(f"capture.luau REQUIRED {required} differs from this checker {REQUIRED}")
    if required_device != REQUIRED_DEVICE:
        problems.append(f"capture.luau REQUIRED_DEVICE {required_device} differs from this checker {REQUIRED_DEVICE}")

    def is_current(row):
        return all(row.get(f) == v for f, v in current.items())

    current_rows = [w for r, w in all_rows if is_current(r)]
    stale_rows = [w for r, w in all_rows if not is_current(r)]
    if all_rows and not current_rows:
        problems.append(
            "no admissible capture carries the workload versions the source declares "
            f"({current}) — the whole set describes a workload that no longer exists"
        )
    for r, w in all_rows:
        if is_current(r):
            continue
        if not r.get("supersededBy") and not r.get("supersededNote"):
            problems.append(
                f"{w}: recorded at "
                f"{ {f: r.get(f) for f in current} } while the source declares {current}, "
                "and the row does not say it was superseded"
            )

    device_rows = sum(classes.get(c, 0) for c in DEVICE_CLASSES)
    if os.path.isfile(ACCEPTANCE):
        with open(ACCEPTANCE) as fh:
            text = fh.read()
        claims_budget = re.search(r"\|\s*PASS_PHYSICAL\s*\|", text) is not None
        if claims_budget and device_rows == 0:
            problems.append(
                "the acceptance ledger claims a PASS_PHYSICAL row while no phone-physical or "
                "desktop-retail capture exists — a device claim needs a device row"
            )

    result = {
        "schema": "facet-perf-captures-check/1",
        "status": "PASS" if not problems else "FAIL",
        "rowsChecked": checked,
        "byClass": classes,
        "deviceRows": device_rows,
        "sourceWorkloadVersions": current,
        "rowsAtCurrentWorkload": current_rows,
        "rowsSuperseded": stale_rows,
        "problems": problems,
        "note": (
            "no device-class row exists yet, which is the honest state: PL-P1/PL-P2 are "
            "PENDING_PHYSICAL. This check exists so that stops being true only when a real "
            "capture lands."
        ),
    }
    os.makedirs("artifacts/performance-stress-places", exist_ok=True)
    with open("artifacts/performance-stress-places/captures.json", "w") as fh:
        json.dump(result, fh, indent=2)
        fh.write("\n")

    if problems:
        print(f"check_perf_captures: FAIL — {len(problems)} problem(s)")
        for p in problems:
            print(f"  {p}")
        return 1
    print(
        f"check_perf_captures: PASS — {checked} row(s) admissible, classes={classes or '{}'}, "
        f"{device_rows} device row(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
