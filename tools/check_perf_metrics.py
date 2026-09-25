#!/usr/bin/env python3

import json
import os
import sys

PERF = "artifacts/phase-4/perf.json"
METRICS = [
    "frameWorkMs",
    "updateMs",
    "instances",
    "connections",
    "memoryKb",
    "inputToVisibleMs",
    "themeSwap",
]

HEADLESS_CLASS = "lune"
DEVICE_CLASSES = {"desktop-retail", "phone-physical", "console-physical"}


def is_blind(value) -> bool:
    return isinstance(value, dict) and value.get("measured") is False and bool(value.get("reason"))








def _absent(path):
    print(
        "check_perf_metrics: FAIL_ENVIRONMENT — recorded evidence %s is not in this checkout "
        "(git-ignored, produced by a run); its row carries the content-hash "
        "receipt that stands for it" % path
    )
    return 2


def main() -> int:
    if not os.path.isfile(PERF):
        return _absent(PERF)
    report = json.load(open(PERF))
    errors = []
    if report.get("workloadComparability", {}).get("validForBaselineParity") is False:
        errors.append("workload fidelity explicitly invalidates this run for baseline parity")
    if report.get("workloadFidelity", {}).get("status") != "verified":
        errors.append("performance artifact has no verified workload fidelity audit")





    if report.get("injectedRegression"):
        errors.append(
            "the committed perf artifact carries an injectedRegression stamp: it came from a "
            "deliberate falsification run and is not a valid measurement"
        )

    classes = {c["id"]: c for c in report.get("evidenceClasses", [])}
    if not DEVICE_CLASSES <= set(classes):
        errors.append(
            "the evidence-class inventory does not declare every device class; "
            "absence must be stated, not inferred"
        )



    ingested_classes = {i.split(":")[0] for i in (report.get("ingestedDeviceRows") or [])}
    for cid in DEVICE_CLASSES & set(classes):
        rows = classes[cid].get("rows", 0)
        if rows != 0 and cid not in ingested_classes:
            errors.append(f"class {cid} claims {rows} rows that were never ingested from a stored capture")



    for r in report.get("rejectedDeviceRows") or []:
        print(f"NOTE rejected row {r.get('scene')}: file '{r.get('fileClass')}' vs row '{r.get('rowClass')}'")
    for cid, c in classes.items():
        for field in ("level", "instrument", "proves", "cannotProve"):
            if not c.get(field):
                errors.append(f"class {cid} declares no {field}")

    ingested = {i for i in (report.get("ingestedDeviceRows") or [])}
    for run in report["runs"]:
        where = f"{run.get('scene')}@{run.get('device')}"
        cls = run.get("evidenceClass")







        if cls in DEVICE_CLASSES:




            if run.get("evidenceLevel") != "E4":
                errors.append(f"{where}: a {cls} row must carry E4, not {run.get('evidenceLevel')!r}")
            m = run.get("metrics") or {}
            fw = m.get("frameWorkMs") or m.get("M1_frameWorkMs")
            if not isinstance(fw, dict):
                errors.append(f"{where}: an ingested {cls} row carries no frame-work metric")


            elif fw.get("measured") is not True:
                errors.append(f"{where}: an ingested {cls} row's frame work is not measured")
            else:
                p95 = fw.get("p95_ms")
                if not isinstance(p95, (int, float)) or p95 != p95 or p95 < 0:
                    errors.append(f"{where}: an ingested {cls} row's M1 p95_ms is {p95!r}")
            for name, aliases in (
                ("updateMs", ("updateMs", "M2_updateMs")),
                ("instances", ("instances", "M3_instances")),
                ("connections", ("connections", "M4_connections")),
                ("memoryKb", ("memoryKb", "M5_memory", "memory")),
            ):
                if not any(a in m for a in aliases):
                    errors.append(f"{where}: an ingested {cls} row is missing metric {name}")

            identity = run.get("identity") or {}
            if identity.get("studioVersion") is not None:
                errors.append(f"{where}: a {cls} row carries identity.studioVersion")
            device = run.get("device") or {}
            live = device.get("live") or {} if isinstance(device, dict) else {}
            if live.get("deviceId") is not None:
                errors.append(f"{where}: a {cls} row carries a Studio device-simulator preset id")
            if "DeviceSimulator" in str(live.get("scalingMode") or ""):
                errors.append(f"{where}: a {cls} row carries a Studio device-simulator scaling mode")





            prov = run.get("provenance")
            if not isinstance(prov, dict):
                errors.append(f"{where}: a {cls} row carries no provenance attestation")
            else:
                if prov.get("isStudio") is not False:
                    errors.append(f"{where}: provenance.isStudio must be the boolean false, stated")
                if prov.get("clientKind") != "retail":
                    errors.append(f"{where}: provenance.clientKind is {prov.get('clientKind')!r}, expected 'retail'")
                for field in ("instrument", "deviceModel", "capturedAt", "attestedBy"):
                    value = prov.get(field)
                    if not isinstance(value, str) or not value:
                        errors.append(f"{where}: provenance.{field} is missing or empty")
                model, name = prov.get("deviceModel"), device.get("name") if isinstance(device, dict) else None
                if isinstance(model, str) and model and isinstance(name, str) and name and model != name:
                    errors.append(f"{where}: provenance.deviceModel {model!r} disagrees with device.name {name!r}")
            continue

        if cls != HEADLESS_CLASS:
            errors.append(f"{where}: evidenceClass {cls!r}; a Lune process may only emit {HEADLESS_CLASS!r}")
        if run.get("evidenceLevel") != "E1":
            errors.append(f"{where}: evidenceLevel {run.get('evidenceLevel')!r}, expected E1")
        if run.get("authoritative") is not False or run.get("deviceRun") is not False:
            errors.append(f"{where}: a headless record must stay deviceRun=false / authoritative=false")

        metrics = run.get("metrics")
        if not isinstance(metrics, dict):
            errors.append(f"{where}: no metrics block")
            continue
        for m in METRICS:
            if m not in metrics:
                errors.append(f"{where}: metric {m} missing entirely (an absent metric reads as zero)")
                continue
            value = metrics[m]
            if isinstance(value, dict) and value.get("measured") is False and not value.get("reason"):
                errors.append(f"{where}: metric {m} is unmeasured but gives no reason")



        if not is_blind(metrics.get("frameWorkMs")):
            errors.append(f"{where}: frameWorkMs must be explicitly blind in a headless record")

        if not (isinstance(metrics.get("updateMs"), dict) and metrics["updateMs"].get("measured")):
            errors.append(f"{where}: updateMs must be measured")

        conn = metrics.get("connections")
        if not (isinstance(conn, dict) and conn.get("measured")):
            if not (is_blind(conn) and is_blind(conn.get("adapterHandlers")) and is_blind(conn.get("reactiveRegistrations"))):
                errors.append(f"{where}: connections require a measurement or explicit native ownership blind markers for both counts")
        mem = metrics.get("memoryKb")
        if not (isinstance(mem, dict) and mem.get("measured")):
            errors.append(f"{where}: memoryKb must be measured")

    measured_i2v = [
        r["scene"]
        for r in report["runs"]
        if isinstance(r.get("metrics", {}).get("inputToVisibleMs"), dict)
        and r["metrics"]["inputToVisibleMs"].get("measured")
    ]
    if not measured_i2v:
        errors.append("no scene measures input-to-visible latency (M6); the metric is declared but never taken")

    if errors:
        for e in errors:
            print(f"FAIL {e}")
        return 1




    device_rows = [r for r in report["runs"] if r.get("evidenceClass") in DEVICE_CLASSES]
    headless_rows = len(report["runs"]) - len(device_rows)
    device_note = (
        f"; {len(device_rows)} ingested device row(s) held to the device contract "
        f"(E4, measured M1, M2-M5 present, an affirmative provenance attestation that agrees with the "
        f"row's own device, and no Studio fingerprint)"
        if device_rows
        else "; 0 ingested device rows"
    )
    print(
        f"perf metrics ok: {headless_rows} headless record(s) carry all {len(METRICS)} metric rows"
        f"{device_note}; M6 measured in {len(set(measured_i2v))} scene(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
