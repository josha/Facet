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
import hashlib
import glob
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GRAPH = "tools/lune/verify/graph.json"
RECEIPTS = "tools/lune/verify/evidence"
ARCHIVE = "../Facet-private-archive/MANIFEST.json"
COVERAGE = "artifacts/distribution-readiness/verification/coverage-map.md"
#[[ WHAT THE REPAIR HAS DONE, NOT WHAT THE LAST RUN DID.
#   This script is idempotent, so its second run moves nothing -- and a coverage
#   section rendered from that run's deltas is an empty table where the record
#   should be. The deltas accumulate here instead, and the document is rendered
#   from the ledger, so running the repair again neither loses the history nor
#   duplicates it. ]]
LEDGER = "tools/lune/verify/data/post-archival-repair.json"

# Recorded machine evidence: what a machine took and a headless run cannot
# re-take. Everything else under artifacts/ is a record of a decision.
#[[ RUN OUTPUT IS NOT RECORDED EVIDENCE. A producer in this same graph rewrites
#   each of these every run, so a hash of one is a hash of the last run rather
#   than of anything anybody recorded — and the row that held it went red the
#   moment the benchmark ran again. They are stripped from every receipt. ]]
REGENERATED = re.compile(
    r"^artifacts/(?:bench\.json|test\.json|boundary\.json|verify/|conformance-[^/]*\.json"
    r"|phase-4/perf\.json|doctor\.json|spec-timings"
    #   `artifacts/<phase>/gate.json` is the per-phase verdict file the
    #   coordinator itself writes at the end of every `tools/verify.sh --gate`
    #   run. Twelve receipts had pinned one, so twelve producers went red on the
    #   run AFTER the run that recorded them — a receipt that cannot survive its
    #   own system running again is measuring the clock.
    r"|[a-z0-9-]+/gate\.json"
    #   ...and `prove_perf_gate` rewrites its own proof row on every run for the
    #   same reason: it is a live falsification, re-earned rather than recalled.
    r"|cross-platform-proof/rows/xp-a6-regression-proof\.json)"
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


#[[ PRODUCERS THAT WRITE INTO THE TREE UNDER TEST RUN ALONE.
#
#   `tools/check_types.py` generates a throwaway `tests/types/_negative_probe.luau`
#   and deletes it, and its `--selftest` rewrites `src/init.luau` and the type
#   witness three times and restores them. Both are correct, and both were in the
#   parallel batch beside each other: on 2026-08-31 the selftest deleted the probe
#   the plain check was still reading (`FileNotFoundError`, a red row for a check
#   that was working), and either window could be the moment another producer
#   hashed the tree.
#
#   The identity snapshot in `run.luau` closes the second half; this closes the
#   first. Serializing a five-second producer costs five seconds. ]]
SERIALIZED = {
    "check_types": "it generates and deletes a probe file inside tests/",
    "check_types-selftest": "it rewrites src/init.luau and the type witness, then restores them",
}


#[[ A CASE THE SUITE RENAMED, RE-POINTED BY HAND AND ON PURPOSE.
#
#   A row that cites a case id proves nothing once the case is renamed, and the
#   graph says so out loud -- `check_manifest_integrity` reddens on a citation
#   the suite no longer answers, which is the whole reason ids replaced greps.
#   Re-pointing is therefore a DELIBERATE edit with the new name written down,
#   never a fuzzy match: an automatic re-point would happily follow a rename
#   that changed what the case asserts.
#
#   Each entry is (old id, new id, who renamed it). ]]
CASE_ID_REPAIRS = [
    (
        "consumer_standalone::examples/consumer: input and state::"
        "Close reports itself, which is what the client script tears down on",
        "consumer_standalone::examples/consumer: input and state::"
        "Close raises the signal the session listens on",
        "the same case, renamed to name the signal rather than the caller",
    ),
]


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


#[[ A RECEIPT THAT NAMES NO READABLE FILE PINS NOTHING.
#
#   The converter took each receipt from the archived manifest's `run` string,
#   and three shapes came through it as text rather than as a path:
#
#     * an unexpanded loop variable — `artifacts/<phase>/rows/$f.json` is what
#       `for f in ...; do` looked like once the loop was gone;
#     * a bare directory — `artifacts/<phase>/captures/`, which was the operand
#       of a `find`, not a file;
#     * nothing at all, with the hash of a file whose name was lost.
#
#   All three verified nothing while reporting a class-shaped environment
#   failure, which is the worst of both: the row could not pass and nobody was
#   told a pin was empty. Each is repaired against what is actually on disk —
#   the loop variable and the directory by expansion, the nameless hash by
#   looking for a file that hashes to it — and an entry that still resolves to
#   no file is dropped with its reason, because a receipt is a claim about
#   recorded evidence and an entry naming none is not one. ]]
LOOP_VARIABLE = re.compile(r"\$\{?\w+\}?")


def _sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def _roots(path: str):
    return [path, os.path.join(os.path.dirname(ARCHIVE), path)]


def _expand(path: str):
    """-> the real files an unexpanded loop variable or a bare directory meant."""
    for root in _roots(path.rstrip("/")):
        if path.endswith("/") and os.path.isdir(root):
            found = sorted(
                os.path.join(root, n) for n in os.listdir(root)
                if os.path.isfile(os.path.join(root, n))
            )
            if found:
                return _not_run_output(found)
    if LOOP_VARIABLE.search(path):
        pattern = LOOP_VARIABLE.sub("*", path)
        for root in _roots(pattern):
            found = sorted(glob.glob(root))
            if found:
                return _not_run_output(found)
    return []


def _not_run_output(found):
    """A directory holds a producer's own output beside the record it took."""
    return [f for f in found if not REGENERATED.match("artifacts/" + f.split("artifacts/", 1)[-1])]


def _index_by_hash():
    """-> {sha256: path} over the record trees, built once and only if needed."""
    index = {}
    for base in _roots("artifacts"):
        for dirpath, _dirs, names in os.walk(base):
            if "/verify/" in dirpath + "/" or "/suite_cache" in dirpath:
                continue
            for name in names:
                full = os.path.join(dirpath, name)
                try:
                    index.setdefault(_sha256(full), full)
                except OSError:
                    pass
    return index


def repair_receipts(dry_run: bool):
    """-> (expanded, recovered, dropped) — receipts that name a readable file."""
    expanded, recovered, dropped = [], [], []
    index = None
    for name in sorted(os.listdir(RECEIPTS)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(RECEIPTS, name)
        receipt = json.load(open(path))
        who = receipt.get("row") or receipt.get("producer") or name
        before = receipt.get("evidence") or []
        after = []
        changed = False
        for entry in before:
            declared = entry.get("archivedPath") or ""
            if declared and (os.path.isfile(declared) or os.path.isfile(_roots(declared)[1])):
                after.append(entry)
                continue
            files = _expand(declared) if declared else []
            if files:
                changed = True
                for i, found in enumerate(files, 1):
                    inside = found.split("artifacts/", 1)[-1]
                    after.append({
                        "label": f"{entry['label']}.{i}",
                        "archivedPath": "artifacts/" + inside,
                        "sha256": _sha256(found),
                    })
                expanded.append((who, declared, len(files)))
                continue
            digest = entry.get("sha256")
            if digest and digest != "absent":
                if index is None:
                    index = _index_by_hash()
                found = index.get(digest)
                if found is not None:
                    changed = True
                    inside = found.split("artifacts/", 1)[-1]
                    entry = dict(entry, archivedPath="artifacts/" + inside)
                    after.append(entry)
                    recovered.append((who, entry["label"], entry["archivedPath"]))
                    continue
            changed = True
            dropped.append((who, entry.get("label"), declared or "(no path recorded)"))
        if not changed:
            continue
        receipt["evidence"] = after
        if not dry_run:
            with open(path, "w") as fh:
                json.dump(receipt, fh, indent=1, sort_keys=True)
                fh.write("\n")
    return expanded, recovered, dropped


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

    # ---- producers that must not share the tree -------------------------------
    serialized = 0
    for p in graph["producers"]:
        if p["id"] in SERIALIZED and not p.get("serialize"):
            p["serialize"] = True
            p["note"] = (p.get("note") or "").strip()
            p["note"] = (p["note"] + " " if p["note"] else "") + "runs alone: " + SERIALIZED[p["id"]]
            serialized += 1
    print(f"producers moved to the serial wave       : {serialized}")

    # ---- producers the graph gains -------------------------------------------
    have = {p["id"] for p in graph["producers"]}
    added = [p for p in NEW_PRODUCERS if p["id"] not in have]
    graph["producers"] = graph["producers"] + added
    print(f"producers added                          : {len(added)}")

    # ---- receipts that named no readable file ---------------------------------
    expanded, recovered, dropped_entries = repair_receipts(args.dry_run)
    print(f"receipt pins expanded to real files      : {len(expanded)}")
    print(f"receipt pins recovered by content hash   : {len(recovered)}")
    print(f"receipt pins dropped as empty            : {len(dropped_entries)}")
    for who, label, why in dropped_entries:
        print(f"  - {who} {label}: {why}")

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

    # ---- case ids the suite renamed under a row -------------------------------
    # LAST, and on the finished graph: `graph["rows"]` is rebuilt above from the
    # row objects this pass kept, so a substitution made before that assignment
    # is thrown away by it.
    repointed = 0
    graph_text = json.dumps(graph, sort_keys=True, ensure_ascii=False)
    for old, new_id, _why in CASE_ID_REPAIRS:
        if old in graph_text:
            graph_text = graph_text.replace(old, new_id)
            repointed += 1
    if repointed:
        graph = json.loads(graph_text)
    print(f"case ids re-pointed after a rename       : {repointed}")

    if args.dry_run:
        return 0

    with open(GRAPH, "w") as fh:
        json.dump(graph, fh, indent=1, sort_keys=True, ensure_ascii=False)
        fh.write("\n")

    append_coverage(
        receipted,
        dropped_pins,
        archived_rows,
        retired_clauses,
        repaired,
        {
            "expanded": expanded,
            "recovered": recovered,
            "dropped": dropped_entries,
            "stripped": stripped,
            "serialized": serialized,
        },
    )
    return 0


def merge_ledger(new: dict) -> dict:
    """Union this run's deltas into the durable record. Order is preserved."""
    ledger = {}
    if os.path.exists(LEDGER):
        ledger = json.load(open(LEDGER))
    for key, rows in new.items():
        if not isinstance(rows, list):
            ledger[key] = max(ledger.get(key, 0), rows)
            continue
        have = ledger.setdefault(key, [])
        seen = {json.dumps(r, sort_keys=True) for r in have}
        for row in rows:
            token = json.dumps(list(row), sort_keys=True)
            if token not in seen:
                seen.add(token)
                have.append(list(row))
    ledger["schema"] = "facet-post-archival-repair/1"
    ledger["updatedAt"] = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    with open(LEDGER, "w") as fh:
        json.dump(ledger, fh, indent=1, sort_keys=True)
        fh.write("\n")
    return ledger


def append_coverage(receipted, dropped_pins, archived_rows, retired_clauses, repaired, receipts) -> None:
    """Render the section from the DURABLE ledger, replacing any earlier copy."""
    ledger = merge_ledger({
        "receipted": receipted,
        "droppedPins": dropped_pins,
        "archivedRows": [[r["phase"], r["name"], ", ".join(r["requirements"]) or "—"]
                         for r in archived_rows],
        "retiredClauses": retired_clauses,
        "repairedClauses": [[a, b[:90], c] for a, b, c in repaired],
        "expandedPins": receipts["expanded"],
        "recoveredPins": receipts["recovered"],
        "droppedReceiptPins": receipts["dropped"],
        "strippedRunOutput": receipts["stripped"],
        "serializedProducers": receipts["serialized"],
    })
    receipted = ledger["receipted"]
    dropped_pins = ledger["droppedPins"]
    archived_rows = ledger["archivedRows"]
    retired_clauses = ledger["retiredClauses"]
    repaired = ledger["repairedClauses"]
    receipts = {
        "expanded": ledger["expandedPins"],
        "recovered": ledger["recoveredPins"],
        "dropped": ledger["droppedReceiptPins"],
        "stripped": ledger["strippedRunOutput"],
        "serialized": ledger["serializedProducers"],
    }
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
    for phase, name, requirements in archived_rows:
        L.append(f"| `{phase}` | `{name}` | {requirements} |")
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

    L += [
        "",
        f"## Receipt pins that named no readable file ({len(receipts['expanded'])} expanded, "
        f"{len(receipts['recovered'])} recovered, {len(receipts['dropped'])} dropped)",
        "",
        "The converter read each pin out of the archived manifest's `run` string, and three",
        "shapes arrived as text rather than as a path: an unexpanded loop variable, a bare",
        "directory that had been a `find` operand, and an entry with a hash and no name.",
        "Each verified nothing while reporting a class-shaped environment failure.",
        "",
        "| Receipt | Pin | Repair |",
        "|---|---|---|",
    ]
    for who, path, count in receipts["expanded"]:
        L.append(f"| `{who}` | `{path}` | expanded to {count} file(s) on disk |")
    for who, label, path in receipts["recovered"]:
        L.append(f"| `{who}` | {label} (no path recorded) | found `{path}` by content hash |")
    for who, label, why in receipts["dropped"]:
        L.append(f"| `{who}` | {label} | dropped: {why} resolves to no file |")

    L += [
        "",
        f"## Run output stripped from receipts ({len(receipts['stripped'])})",
        "",
        "A producer in this same graph rewrites each of these every run, so a hash of one is",
        "a hash of the last run. The row that held it went red the moment its own system ran",
        "again.",
        "",
        "| Receipt | File |",
        "|---|---|",
    ]
    for who, path in receipts["stripped"]:
        L.append(f"| `{who}` | `{path}` |")

    L += [
        "",
        f"## Producers moved to the serial wave ({receipts['serialized']})",
        "",
        "| Producer | Why it cannot share the tree |",
        "|---|---|",
    ]
    for pid, why in sorted(SERIALIZED.items()):
        L.append(f"| `{pid}` | {why} |")

    L.append("")

    #[[ IDEMPOTENT MEANS THE DOCUMENT TOO. The first draft appended, so a second
    #   run left a second copy of every empty table behind it. The section is
    #   replaced from its own heading down, which is what "run it again" has to
    #   mean for a file this one owns. ]]
    body = open(COVERAGE).read() if os.path.exists(COVERAGE) else ""
    marker = "\n---\n\n# Post-archival repair ("
    cut = body.find(marker)
    if cut != -1:
        body = body[:cut]
    with open(COVERAGE, "w") as fh:
        fh.write(body.rstrip("\n") + "\n" + "\n".join(L))


if __name__ == "__main__":
    sys.exit(main())
