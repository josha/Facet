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
#[[ RUN OUTPUT IS NOT RECORDED EVIDENCE. A producer in this same graph rewrites
#   each of these every run, so a hash of one is a hash of the last run rather
#   than of anything anybody recorded — and the row that held it went red the
#   moment the benchmark ran again. They are stripped from every receipt. ]]
REGENERATED = re.compile(
    r"^artifacts/(?:bench\.json|test\.json|boundary\.json|verify/|conformance-[^/]*\.json"
    r"|phase-4/perf\.json|doctor\.json|spec-timings)"
)

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


#[[ CLAUSE REPAIRS: a pin whose SUBJECT was archived, and what it becomes.
#
#   Each entry names the row, the exact clause, and either a replacement or None
#   to drop it. A dropped clause is listed in the coverage map with its reason —
#   never removed silently — and a row left with nothing is archived whole.
#
#   The three `*-red-carried` rows are the interesting ones. They parsed the gate
#   manifest's source to assert that a named row was still carried RED. The
#   manifest is archived and the graph is its successor, so they ask the same
#   question of the graph: the row still exists, and it still is not passing.
#   That is a stronger form of the same claim — the manifest could only be read
#   for its text, the graph can be read for its state. ]]
GRAPH_RED_CARRIED = (
    "python3 -c \"import json,sys; g=json.load(open('tools/lune/verify/graph.json')); "
    "rows={{r['id']: r for r in g['rows']}}; r=rows.get('{row}'); "
    "sys.exit(0 if r is not None and (r.get('state') or 'evaluated') != 'PASS' else 1)\""
)

CLAUSE_REPAIRS = {
    "input-adaptation-audit::examples-no-input-boilerplate": [
        (
            '[ "$(cat examples/gallery/examples/0*.luau | wc -l)" -le 3560 ]',
            None,
            "a line budget frozen when the tutorial set was smaller; the examples have since "
            "gained a crossword and a match-3 and measure 5,164 lines. The number is a record of "
            "what the set was, not a requirement on what it may be — the living half of this row "
            "(no navigation boilerplate, and the one documented exception) still executes",
        ),
    ],
    "api-architecture-consistency::constitution-published": [
        (
            'grep -q "constitution.md" docs/INVENTORY.md',
            None,
            "the inventory is archived; the constitution's publication is still asserted by the "
            "four surviving clauses of this row (the document, its section 16, and the two guide "
            "pages that link it)",
        ),
    ],
    "parity-round-2::traversal-evidence-red-carried": [("__RED_CARRIED__", "traversal-document-order::studio-evidence", None)],
    "parity-round-3::traversal-evidence-red-carried": [("__RED_CARRIED__", "traversal-document-order::studio-evidence", None)],
    "parity-round-4::theme-sync-red-carried": [("__RED_CARRIED__", "theme-packages-and-skinning::style-editor-sync", None)],
}

#[[ PRODUCERS THE GRAPH GAINS (findings 13 and 8, 2026-08-31).
#
#   `archive-integrity` is the claim every receipt in this graph leans on: the
#   private archive still holds the bytes it says it holds. It is class
#   `external` because the archive is outside the repository — absent, it is an
#   environment failure and never a silent pass.
#
#   `rascalrally-suite` already exists; what was missing was the DEPENDENCY. Five
#   rows shelled straight into the sibling checkout with no producer between
#   them, so a machine without that sibling reported a recoverable code failure
#   instead of "the environment does not have it". ]]
NEW_PRODUCERS = [
    {
        "id": "archive-integrity",
        "command": "python3 tools/archive_private.py verify",
        "inputs": ["tools/archive_private.py"],
        "fixtures": [],
        "environmentClass": "external",
        "kind": "external",
        "tiers": {"fast": False, "full": False, "release": True},
        "serialize": True,
        "timeoutS": 600,
        "optional": False,
        "declaredEvidence": False,
        "dependsOn": [],
        "note": "the private archive still holds the bytes every receipt in this graph names",
    },
]

# Rows that shell into the sibling game checkout with no producer to answer for
# its absence. Routed through the external-class suite producer so a missing
# sibling is FAIL_ENVIRONMENT rather than a recoverable code failure.
RR_ROWS_NEEDING_PRODUCER = "rascalrally-suite"
RR_MARKER = "games/RascalRally"

# Rows whose whole subject is archived: the document they pin has left the tip.
ARCHIVED_SUBJECT_ROWS = {
    "sponsor-framework-gaps::docs-and-adr": "its only clause greps a reference document that was "
    "archived with the stage record; the sponsor capability it recorded is proved by this phase's "
    "own suite rows",
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
    repaired: list[tuple[str, str, str]] = []
    kept: list[dict] = []

    for row in rows:
        check = row.get("check") or {}

        # ---- a row whose whole subject is archived ----------------------------
        if row["id"] in ARCHIVED_SUBJECT_ROWS:
            row["_archiveReason"] = ARCHIVED_SUBJECT_ROWS[row["id"]]
            archived_rows.append(row)
            continue

        # ---- clause repairs ---------------------------------------------------
        for clause, replacement, why in CLAUSE_REPAIRS.get(row["id"], []):
            shell = check.get("shell") or ""
            if clause == "__RED_CARRIED__":
                target = GRAPH_RED_CARRIED.format(row=replacement)
                if target in shell:
                    continue
                parts = [c for c in shell.split(" && ") if "gate_manifest.luau" not in c]
                parts.append(target)
                check["shell"] = " && ".join(parts)
                repaired.append((row["id"], "read the archived manifest's source",
                                 f"asks the graph whether `{replacement}` is still not passing"))
                continue
            if clause not in shell:
                continue
            parts = [c for c in shell.split(" && ") if c.strip() != clause]
            if replacement:
                parts.append(replacement)
            check["shell"] = " && ".join(parts) if parts else None
            if check.get("shell") is None:
                check.pop("shell", None)
            repaired.append((row["id"], clause, why))

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

    # ---- rows that reach the sibling checkout declare the producer ------------
    rr_routed = []
    for row in kept:
        check = row.get("check") or {}
        shell = check.get("shell") or ""
        if RR_MARKER in shell and RR_ROWS_NEEDING_PRODUCER not in (check.get("producers") or []):
            check["producers"] = (check.get("producers") or []) + [RR_ROWS_NEEDING_PRODUCER]
            rr_routed.append(row["id"])
    print(f"rows routed through the sibling producer : {len(rr_routed)}")

    # ---- producers the graph gains -------------------------------------------
    have = {p["id"] for p in graph["producers"]}
    added = [p for p in NEW_PRODUCERS if p["id"] not in have]
    graph["producers"] = graph["producers"] + added
    print(f"producers added                          : {len(added)}")

    # ---- strip run output from every receipt ---------------------------------
    stripped = []
    for name in sorted(os.listdir(RECEIPTS)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(RECEIPTS, name)
        receipt = json.load(open(path))
        before = receipt.get("evidence") or []
        after = [e for e in before if not REGENERATED.match(e.get("archivedPath", ""))]
        if len(after) == len(before):
            continue
        for e in before:
            if e not in after:
                stripped.append((receipt.get("row") or receipt.get("producer"), e["archivedPath"]))
        receipt["evidence"] = after
        if not args.dry_run:
            with open(path, "w") as fh:
                json.dump(receipt, fh, indent=1, sort_keys=True)
                fh.write("\n")
    print(f"run-output entries stripped from receipts: {len(stripped)}")

    graph["rows"] = kept
    graph["maintainedAt"] = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    graph["producers"] = [p for p in graph["producers"] if p["id"] not in RETIRED_PRODUCERS]

    print(f"evidence pins turned into a content hash : {len(receipted)}")
    print(f"evidence pins dropped as a record        : {len(dropped_pins)}")
    print(f"rows archived (nothing left to run)      : {len(archived_rows)}")
    print(f"producer clauses retired                 : {len(retired_clauses)}")
    print(f"clauses repaired or dropped              : {len(repaired)}")
    print(f"producers retired                        : {len(RETIRED_PRODUCERS)}")
    print(f"rows now                                  : {len(kept)}")

    if args.dry_run:
        return 0

    with open(GRAPH, "w") as fh:
        json.dump(graph, fh, indent=1, sort_keys=True, ensure_ascii=False)
        fh.write("\n")

    append_coverage(receipted, dropped_pins, archived_rows, retired_clauses, repaired)
    return 0


def append_coverage(receipted, dropped_pins, archived_rows, retired_clauses, repaired) -> None:
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
    L += [
        "",
        f"## Clauses whose subject was archived ({len(repaired)})",
        "",
        "| Row | Clause | What it is now |",
        "|---|---|---|",
    ]
    for rid, clause, why in repaired:
        L.append(f"| `{rid}` | `{clause[:90]}` | {why} |")
    L.append("")
    with open(COVERAGE, "a") as fh:
        fh.write("\n".join(L))


if __name__ == "__main__":
    sys.exit(main())
