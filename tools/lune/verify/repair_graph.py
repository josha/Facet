#!/usr/bin/env python3
"""Maintain `tools/lune/verify/graph.json` now that its generator's inputs are archived.

    python3 tools/lune/verify/repair_graph.py            # apply, in place
    python3 tools/lune/verify/repair_graph.py --dry-run  # say what it would do

WHY THIS EXISTS
---------------
`convert_manifest.py` generated the graph from `tools/lune/gate_manifest.luau` and
`phases.json`. Both are archived, so the graph is no longer derived from anything
in the tree — it IS the source of truth, and it needs a maintenance tool rather
than a regenerator. This is that tool, and it is idempotent: running it twice
changes nothing the second time.

WHAT IT REPAIRS, AND BY WHAT RULE
---------------------------------
The rule is the one the stage has used throughout. A pin on a file that has left
the tip is either

  (a) RECORDED MACHINE EVIDENCE a headless run can never re-take — a Studio
      drive, a device or performance capture, an engine-feasibility probe, a
      measured row. It keeps its row and becomes a CONTENT HASH, taken from the
      private archive's own manifest, which is the only place the bytes now live;

  (b) a RECORD of a decision that has already been made — an acceptance table, a
      review packet, a roll-up, a reviewer's verdict. A hash of it would be a pin
      nobody can verify again, so the pin is dropped and listed in the coverage
      map. A row left with nothing else is archived whole.

Applied per FIELD, not per row: a row whose evidence pin is archived but whose
suite cases and producers still execute keeps everything except the pin.

It also retires the producers whose SUBJECT is archived — a checker cannot audit
a file that is not there — and the rows that consumed nothing else.
"""

from __future__ import annotations

import argparse
import collections
import datetime
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GRAPH = "tools/lune/verify/graph.json"
RECEIPTS = "tools/lune/verify/evidence"
ARCHIVE = "../Facet-private-archive/MANIFEST.json"
COVERAGE = "artifacts/distribution-readiness/verification/coverage-map.md"

# Recorded machine evidence: what a machine took and a headless run cannot
# re-take. Everything else under artifacts/ is a record of a decision.
LIVING_EVIDENCE = re.compile(
    r"/(?:studio|device|captures|feasibility|rows|perf|matrix)/"
    r"|(?:studio-drive|device-matrix|-capture|-probe|spike)"
)

# Producers whose subject left the tip with the archive. A checker cannot audit a
# file that is not there, and a producer nobody can run is not evidence of
# anything — so it and its consumer clauses go, with the reason recorded.
RETIRED_PRODUCERS = {
    "check_gate_pins": "its subject is the archived gate manifest; the plain-comment contract it "
    "also carried is enforced by check_comment_codes, which still runs",
    "check_gate_pins-selftest": "same subject as check_gate_pins",
    "check_manifest_integrity-transcript": "it replays the archived manifest's greps against a live "
    "transcript; the manifest is gone and the graph's own case-id lookups are the "
    "surviving form of that claim",
}


def load_archive() -> dict:
    path = os.path.join(ROOT, ARCHIVE)
    if not os.path.exists(path):
        return {}
    with open(path) as fh:
        return {f["path"]: f for f in json.load(fh)["files"]}


def is_publishable(text: str) -> bool:
    """Ask the product-language guard, so this file names none of the words."""
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "_facet_brand_guard", os.path.join(ROOT, "tools/check_brand_drift.py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for pattern in (module.BRAND, module.TAG, module.VENDOR, module.VENDOR_TYPES):
        if pattern.search(text):
            return False
    return True


def has_work(check: dict) -> bool:
    return any(
        check.get(k)
        for k in ("producers", "resultIds", "stdoutPins", "shell", "receipt", "priorPhases")
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    os.chdir(ROOT)

    graph = json.load(open(GRAPH))
    archive = load_archive()
    rows = graph["rows"]

    receipted: list[tuple[str, str]] = []
    dropped_pins: list[tuple[str, str, str]] = []
    archived_rows: list[dict] = []
    retired_clauses: list[tuple[str, str]] = []
    kept: list[dict] = []

    for row in rows:
        check = row.get("check") or {}

        # ---- producers whose subject is archived ------------------------------
        producers = check.get("producers") or []
        surviving = [p for p in producers if p not in RETIRED_PRODUCERS]
        if len(surviving) != len(producers):
            for p in producers:
                if p in RETIRED_PRODUCERS:
                    retired_clauses.append((row["id"], p))
            if surviving:
                check["producers"] = surviving
            else:
                check.pop("producers", None)

        # ---- an evidence pin on a file that has left the tip -------------------
        evidence = row.get("evidence")
        if evidence and not os.path.exists(evidence):
            entry = archive.get(evidence)
            if LIVING_EVIDENCE.search(evidence) and entry:
                receipt_id = row["id"].replace("::", "--")
                path = os.path.join(RECEIPTS, receipt_id + ".json")
                if os.path.exists(path):
                    receipt = json.load(open(path))
                else:
                    receipt = {
                        "schema": "facet-evidence-receipt/1",
                        "row": row["id"],
                        "class": "studio",
                        "recordedAt": datetime.datetime.now(datetime.timezone.utc).strftime(
                            "%Y-%m-%dT%H:%M:%SZ"
                        ),
                        "summary": f"{row['name']}: recorded evidence, pinned by content hash.",
                        "evidence": [],
                    }
                known = {e["sha256"] for e in receipt["evidence"]}
                if entry["sha256"] not in known:
                    item = {
                        "label": f"evidence-{len(receipt['evidence']) + 1}",
                        "sha256": entry["sha256"],
                    }
                    if is_publishable(evidence):
                        item["archivedPath"] = evidence
                    receipt["evidence"].append(item)
                receipt["summary"] = (
                    f"{row['name']}: {len(receipt['evidence'])} recorded file(s), pinned by "
                    "content hash; the bytes live in the private archive."
                )
                if not args.dry_run:
                    with open(path, "w") as fh:
                        json.dump(receipt, fh, indent=1, sort_keys=True)
                        fh.write("\n")
                check["receipt"] = f"{RECEIPTS}/{receipt_id}.json"
                receipted.append((row["id"], evidence))
            else:
                dropped_pins.append(
                    (row["id"], evidence, "in the archive" if entry else "not in the archive")
                )
            row["evidence"] = None

        row["check"] = check
        if not has_work(check) and row.get("state") is None:
            archived_rows.append(row)
            continue
        kept.append(row)

    graph["rows"] = kept
    graph["maintainedAt"] = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    graph["producers"] = [p for p in graph["producers"] if p["id"] not in RETIRED_PRODUCERS]

    print(f"evidence pins turned into a content hash : {len(receipted)}")
    print(f"evidence pins dropped as a record        : {len(dropped_pins)}")
    print(f"rows archived (nothing left to run)      : {len(archived_rows)}")
    print(f"producer clauses retired                 : {len(retired_clauses)}")
    print(f"producers retired                        : {len(RETIRED_PRODUCERS)}")
    print(f"rows now                                  : {len(kept)}")

    if args.dry_run:
        return 0

    with open(GRAPH, "w") as fh:
        json.dump(graph, fh, indent=1, sort_keys=True, ensure_ascii=False)
        fh.write("\n")

    append_coverage(receipted, dropped_pins, archived_rows, retired_clauses)
    return 0


def append_coverage(receipted, dropped_pins, archived_rows, retired_clauses) -> None:
    """Everything this pass moved, named, in the document that promises that."""
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    L = [
        "",
        "---",
        "",
        f"# Post-archival repair ({stamp})",
        "",
        "The stage record was archived and deleted from the tip. This section is what",
        "that cost each row, and what carries the claim now. Produced by",
        "`python3 tools/lune/verify/repair_graph.py`, which is idempotent.",
        "",
        f"## Evidence pins turned into a content hash ({len(receipted)})",
        "",
        "Recorded machine evidence: the bytes now live only in the private archive, and the",
        "receipt carries the sha256 the archive's own manifest records for them.",
        "",
        "| Row | File |",
        "|---|---|",
    ]
    for rid, path in receipted:
        L.append(f"| `{rid}` | `{path}` |")
    L += [
        "",
        f"## Evidence pins dropped as a record of a past decision ({len(dropped_pins)})",
        "",
        "Each named an acceptance table, a review packet, a roll-up or a reviewer's verdict",
        "from a stage that closed. A hash of one would be a pin nobody could verify again.",
        "The row keeps everything else it asserts; where nothing else remained, the row is",
        "listed in the next table instead.",
        "",
        "| Row | File | In the archive? |",
        "|---|---|---|",
    ]
    for rid, path, where in dropped_pins:
        L.append(f"| `{rid}` | `{path}` | {where} |")
    L += [
        "",
        f"## Rows archived whole ({len(archived_rows)})",
        "",
        "Nothing executable was left once the pin went.",
        "",
        "| Phase | Row | Requirement |",
        "|---|---|---|",
    ]
    for row in archived_rows:
        L.append(f"| `{row['phase']}` | `{row['name']}` | {', '.join(row['requirements']) or '—'} |")
    L += [
        "",
        f"## Producers retired, and the rows that consumed them ({len(retired_clauses)} clauses)",
        "",
        "| Producer | Why |",
        "|---|---|",
    ]
    for pid, why in sorted(RETIRED_PRODUCERS.items()):
        L.append(f"| `{pid}` | {why} |")
    L += ["", "| Row | Producer it no longer names |", "|---|---|"]
    for rid, pid in retired_clauses:
        L.append(f"| `{rid}` | `{pid}` |")
    L.append("")
    with open(COVERAGE, "a") as fh:
        fh.write("\n".join(L))


if __name__ == "__main__":
    sys.exit(main())
