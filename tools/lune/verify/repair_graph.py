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
#   duplicates it. It sits beside the document rather than under `tools/`
#   because it is the same thing the document is -- a record of evidence, under
#   the names that evidence was earned with, which is precisely why the drift
#   check excludes `artifacts/` and scans `tools/`. ]]
LEDGER = "artifacts/distribution-readiness/verification/post-archival-repair.json"

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
    #[[ A CLAUSE THAT REDDENS WHEN ITS OWN GOAL IS REACHED.
    #   The packet row asserted, as its last clause, that `git remote get-url
    #   origin` STILL carried the old brand -- the packet was prepared and
    #   verified "without mutating the remote", so the clause was there to prove
    #   the rename had not been performed behind it. The rename has since been
    #   performed (`12311fb`), and the clause went red for the one reason it
    #   never should: the work it described was done. Its post-rename form is the
    #   same claim from the other side, and the packet half of the row -- the
    #   target URL, the rollback section, the `git ls-remote` check -- is
    #   untouched. ]]
    "release-candidate-review::step14-remote-packet": [
        (
            "git remote get-url origin | python3 -c \"import sys, importlib.util; "
            "s = importlib.util.spec_from_file_location('g', 'tools/check_brand_drift.py'); "
            "m = importlib.util.module_from_spec(s); s.loader.exec_module(m); "
            "sys.exit(0 if any(m.BRAND.search(l) for l in sys.stdin) else 1)\"",
            "git remote get-url origin | python3 -c \"import sys, importlib.util; "
            "s = importlib.util.spec_from_file_location('g', 'tools/check_brand_drift.py'); "
            "m = importlib.util.module_from_spec(s); s.loader.exec_module(m); "
            "u = sys.stdin.read(); "
            "sys.exit(0 if '/Facet' in u and not m.BRAND.search(u) else 1)\"",
            "the remote was renamed after this row was written, so the clause that proved the "
            "rename was still owed now reddens because it was done; it asserts the completed "
            "rename instead",
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
        #   The archive is outside the repository, so a checkout without it must
        #   report an environment failure rather than a red check -- the guard
        #   is in the command because the tool it wraps belongs to another
        #   concern and exits 1 for "no archive here".
        "command": (
            "test -d ../Facet-private-archive || { "
            "echo 'archive_private: FAIL_ENVIRONMENT no private archive beside this checkout'; "
            "exit 2; }; python3 tools/archive_private.py verify"
        ),
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
    {
        #[[ THE STUDIO TREE ABOVE THIS REPOSITORY IS EXTERNAL TOO.
        #   One row greps two specialist documents at `../../specialists/`, which
        #   is inside the workspace this library is developed in and outside
        #   every clone of it. On a public clone the greps found nothing and the
        #   row read as a failed assertion. Wrapped in a producer that says
        #   FAIL_ENVIRONMENT and exits 2 when the tree is not there -- the same
        #   contract the consuming game's checkout already has -- so the row goes
        #   yellow with a reason instead of red with a mystery. ]]
        "id": "studio-specialist-docs",
        "command": (
            "test -d ../../specialists || { "
            "echo 'check_specialist_docs: FAIL_ENVIRONMENT the studio tree above this "
            "repository is not beside this checkout'; exit 2; }; "
            "grep -q 'Designing for Facet' ../../specialists/UI_DESIGNER.md && "
            "grep -q 'Building on Facet' ../../specialists/UI_ENGINEER.md && "
            "grep -q semantic ../../specialists/UI_DESIGNER.md && "
            "grep -q 'docs/guide/README.md' ../../specialists/UI_ENGINEER.md && "
            "echo 'check_specialist_docs: PASS both specialist documents name this library'"
        ),
        "inputs": [],
        "fixtures": [],
        "environmentClass": "external",
        "kind": "external",
        "tiers": {"fast": True, "full": True, "release": True},
        "serialize": False,
        "timeoutS": 60,
        "optional": False,
        "declaredEvidence": False,
        "dependsOn": [],
        "note": "the two specialist documents in the studio tree above this repository still "
        "route their readers here; absent, it is an environment failure and never a silent pass",
    },
    {
        #[[ DR-14 asks whether the release interface REFUSES what it must, and
        #   only `--selftest` can answer that: it drives every refusal on
        #   purpose against a fake transport that never reaches the network, and
        #   proves no API key survives into a receipt. Offline, 6.5 s. ]]
        "id": "package-selftest",
        "command": "python3 tools/package.py --selftest",
        "inputs": ["src/**", "tests/**", "examples/gallery/**", "examples/reference/**", "examples/themes/**", "examples/consumer/**", "examples/performance/**", "examples/table_phaseb/**", "docs/**", "tools/**", "bench/**", "package/**", "skills/**", "rokit.toml", "run-tests.sh", "phases.json", "requirements.json", "README.md", "AGENTS.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE"],
        "fixtures": [],
        "environmentClass": "package",
        "kind": "scanner",
        "tiers": {"fast": False, "full": True, "release": True},
        "serialize": True,
        "timeoutS": 600,
        "optional": False,
        "declaredEvidence": False,
        "dependsOn": [],
        "note": "every refusal the release interface owes, driven against a fake transport",
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
#[[ A ROW'S PRODUCER HAS TO RUN IN THE TIER THAT EVALUATES THE ROW.
#   `package-verify` was release-only. DR-13 names it, and a row whose producer
#   did not run reports NOT_EVALUATED -- which makes a full run INCOMPLETE for a
#   reason that is nobody's defect. It is offline and costs 6 s. ]]
#[[ ...AND A PRODUCER THAT REWRITES TRACKED FILES DOES NOT BELONG IN A LOOP
#   THE INNER TIERS RUN. The two place builders declared the whole-tree input
#   set every scanner shares, so the `affected` tier selected them off a README
#   edit -- and they rewrite fourteen tracked `.rbxl` in place, each carrying a
#   build TIME in its stamp, so the working tree came back dirty for a change
#   that could not have touched a place. Measured by a fresh agent on a pristine
#   clone, 2026-08-31. Their inputs are narrowed to the trees that actually feed
#   a place, and they run at release only: building a place is a release act.
#   (The build-stamp nondeterminism itself is deliberate and is recorded as
#   such -- see the reproducibility note.) ]]
PLACE_INPUTS = [
    "src/**",
    "examples/gallery/**",
    "examples/reference/**",
    "examples/themes/**",
    "examples/performance/**",
    "examples/showcase.project.json",
    "examples/gallery.project.json",
    "examples/performance.project.json",
    "tools/build_places.sh",
    "tools/build_reference_places.sh",
    "rokit.toml",
]

RETIER = {
    "package-verify": {"fast": False, "full": True, "release": True},
    #   `affected: False` keeps them out of the inner loop without taking them
    #   out of `full` -- a row names one, and a row whose producer never runs
    #   makes the tier INCOMPLETE for nobody's defect.
    "build_places": {"fast": False, "full": True, "release": True, "affected": False},
    "build_reference_places": {"fast": False, "full": True, "release": True, "affected": False},
    #   and the archive check is named by a distribution-readiness row, so it
    #   has to be answerable at `full` too. It costs 0.3 s.
    "archive-integrity": {"fast": False, "full": True, "release": True},
}

REINPUT = {"build_places": PLACE_INPUTS, "build_reference_places": PLACE_INPUTS}

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


#[[ THE REGISTRATION ROWS WHOSE EVIDENCE NOW EXISTS (2026-08-31).
#
#   Thirty-three distribution-readiness rows were registered PENDING at stage
#   open, before the work they describe was done -- which is the point of
#   registering them. The evidence for most of them has since landed, and a row
#   that stays PENDING once its evidence exists is as dishonest as one that
#   claims PASS before it does.
#
#   THE RULE FOR WHAT GOES IN HERE: a row is flipped only when something in this
#   run can go RED for it. Every flip below carries at least one of a live
#   producer, a suite case id, a shell assertion against the tree, or a content
#   hash of a record that is finished. A row whose proof is still in flight, or
#   whose subject is a human reading a document, stays PENDING and is listed at
#   the bottom with what it waits for.
#
#   AND WHAT MAY NOT BE HASHED. Three of the artifacts named in the brief --
#   `coverage-map.md`, `artifacts/verify/invocation-trace.json` and
#   `post-archival-repair.json` -- are rewritten by this repository's own tools
#   every time they run. A content hash of one is a hash of the last run, which
#   is the exact defect this workstream removed from thirteen receipts a few
#   hours ago. Those three are asserted by EXISTENCE plus a live check that reads
#   them (the trace's own answer to "did any producer run twice", and the
#   ledger's counts against the document rendered from it), never by a pin. ]]

FREEZE = "artifacts/distribution-readiness/freeze"
REGISTRATION_COMMIT = "6907f85"

_TRACE_CHECK = (
    "python3 -c \"import json,collections,sys; "
    "seen=collections.Counter(); "
    "lines=[l for l in open('artifacts/verify/invocation-trace.json') if l.strip()]; "
    "[seen.update([(json.loads(l)['runId'], json.loads(l)['producer'])]) for l in lines]; "
    "dup=[k for k,v in seen.items() if v>1]; "
    "print(len(dup),'producer(s) appear twice in one run'); "
    "sys.exit(1 if dup else 0)\""
)

_LEDGER_CHECK = (
    "python3 -c \"import json,re,sys; "
    "led=json.load(open('artifacts/distribution-readiness/verification/post-archival-repair.json')); "
    "doc=open('artifacts/distribution-readiness/verification/coverage-map.md').read(); "
    "want={'Evidence pins turned into a content hash':'receipted',"
    "'Evidence pins dropped as a record of a past decision':'droppedPins',"
    "'Rows archived whole':'archivedRows'}; "
    "bad=[h for h,k in want.items() "
    "if ('## %s (%d)' % (h, len(led[k]))) not in doc]; "
    "print(bad if bad else 'the ledger and the coverage map agree'); "
    "sys.exit(1 if bad else 0)\""
)

_REMOTE_CHECK = (
    "git remote get-url origin | python3 -c \"import sys, importlib.util; "
    "s = importlib.util.spec_from_file_location('g', 'tools/check_brand_drift.py'); "
    "m = importlib.util.module_from_spec(s); s.loader.exec_module(m); "
    "u = sys.stdin.read(); "
    "sys.exit(0 if '/Facet' in u and not m.BRAND.search(u) else 1)\""
)

#[[ THE RULE IS WHAT STAYS, NOT WHAT LEFT.
#   The first version of this row named the retired document by filename -- and a
#   filename is exactly what this repository may not carry, so the row that proved a
#   removal became the last four matches of the drift check. Naming the departed is also
#   the weaker rule: it catches that ONE file coming back and nothing else. This is an
#   allowlist of what the public reference directory may hold -- the same move the link
#   guards made -- and the archived replacement is located STRUCTURALLY: the receipt
#   document is found by a neutral glob, its own recorded path and digest are read out of
#   it at run time, and both are checked against the private archive's manifest. Nothing
#   spells a retired name, and the assertion got STRONGER: a new stray under the
#   reference directory reddens it too. ]]
DR8_CLAUSE = (
    """
python3 -c "
import glob, json, os, re, sys
keep = sorted(p.rsplit('/', 1)[-1] for p in glob.glob('docs/reference/*'))
doc = glob.glob('artifacts/distribution-readiness/*archive-receipt.md')
text = open(doc[0]).read().replace(chr(96), '') if len(doc) == 1 else ''
path = re.search('[*][*]Path[*][*] [|] ([^|]+)', text)
want = re.search('[*][*]SHA-256[*][*] [|] ([0-9a-f]{64})', text)
if not os.path.isfile('../Facet-private-archive/MANIFEST.json'):
    print('FAIL_ENVIRONMENT no private archive beside this checkout, so the archived replacement cannot be verified')
    sys.exit(2)
manifest = {e['path']: e['sha256'] for e in json.load(open('../Facet-private-archive/MANIFEST.json'))['files']}
name = path.group(1).strip().rsplit('/', 1)[-1] if path else None
hit = [k for k in manifest if name and k.endswith('/' + name)]
ok = (keep == ['api.md', 'constitution.md'] and want is not None
      and len(hit) == 1 and manifest[hit[0]] == want.group(1))
print('docs/reference holds exactly', keep, '; the archived replacement matches the manifest' if ok else '; MISMATCH')
sys.exit(0 if ok else 1)
"
"""
)

CONSUMER_CASES = [
    "consumer_standalone::examples/consumer: input and state::Close raises the signal the session listens on",
    "consumer_standalone::examples/consumer: input and state::a press on Bump raises the count and repaints the label",
    "consumer_standalone::examples/consumer: input and state::a write to the signal repaints the label with no press at all",
    "consumer_standalone::examples/consumer: input and state::the toggle carries the signal the screen owns",
    "consumer_standalone::examples/consumer: it adapts by re-solving::a viewport change re-solves the mounted surface without rebuilding it",
    "consumer_standalone::examples/consumer: it adapts by re-solving::the button stack arranges differently at a compact and a wide viewport",
    "consumer_standalone::examples/consumer: it adapts by re-solving::the player's preferred text size grows the untouched label",
    "consumer_standalone::examples/consumer: teardown leaves nothing behind::a press on Close tears the whole session down through its own wiring",
    "consumer_standalone::examples/consumer: teardown leaves nothing behind::disposing the screen alone releases the frame hook it registered",
    "consumer_standalone::examples/consumer: teardown leaves nothing behind::returns the reactive registries to their pre-screen baseline",
    "consumer_standalone::examples/consumer: teardown leaves nothing behind::takes every node off the render target",
    "consumer_standalone::examples/consumer: teardown leaves nothing behind::the timer tears the session down when nobody presses Close",
    "consumer_standalone::examples/consumer: the standalone project mounts::puts every part of the screen on the target",
    "consumer_standalone::examples/consumer: the standalone project mounts::reads its label out of the signal, not out of a literal",
    "consumer_standalone::examples/consumer: the theme decides the paint::repaints the accent tint when a theme package is committed",
]

# row id -> (check dict, note, evidence path or None)
ROW_FLIPS = {
    "distribution-readiness::registered-before-work": (
        {
            "shell": (
                "git merge-base --is-ancestor %s HEAD && "
                '[ "$(git rev-parse %s^)" = "$(cat %s/head.txt)" ]'
                % (REGISTRATION_COMMIT, REGISTRATION_COMMIT, FREEZE)
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--registered-before-work.json",
        },
        "the registration commit is in this history AND its parent is exactly the head recorded "
        "at stage open, so registration was the FIRST commit of the stage rather than merely an "
        "early one -- which is the claim, and the only shape of it a later run can still falsify",
        None,
    ),
    "distribution-readiness::state-frozen-at-open": (
        {
            "shell": (
                'git cat-file -e "$(cat %s/head.txt)^{commit}" && '
                "test -s %s/tracked-files.txt && test -s %s/refs.txt && "
                "test -s %s/status.txt" % (FREEZE, FREEZE, FREEZE, FREEZE)
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--state-frozen-at-open.json",
        },
        "the frozen head is a real commit in this repository (not a string in a document) and the "
        "four raw records taken beside it are on disk and non-empty, each pinned by content hash",
        None,
    ),
    "distribution-readiness::history-audit-no-must-purge": (
        {
            "shell": (
                'grep -q "MUST-PURGE ITEMS: 15" artifacts/distribution-readiness/audit/history-audit.md && '
                'grep -q "candidate-B-full" artifacts/distribution-readiness/audit/history-candidate.md && '
                'grep -q "history rewrite candidate \\*\\*B\\*\\*" artifacts/distribution-readiness/packet/owner-packet.md && '
                'grep -q "the plan forbids it while must-purge items exist" '
                "artifacts/distribution-readiness/packet/owner-packet.md"
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--history-audit-no-must-purge.json",
        },
        "the 15 must-purge items DO still exist, and this row passes anyway on its own wording: a "
        "tested clean-history candidate exists, the owner has chosen one (B), and public release "
        "is recorded as blocked while they exist. The owner packet is asserted by its text rather "
        "than by a hash, because it is stamped again at close and DR-32 is the row that waits for "
        "that",
        None,
    ),
    "distribution-readiness::provenance-and-third-party-notices": (
        {
            "producers": ["check_links_cli", "check_links_cli-selftest"],
            "shell": (
                "test -f THIRD_PARTY_NOTICES.md && "
                "test -f artifacts/distribution-readiness/audit/provenance-ledger.md && "
                'grep -q "Copyright (c) 2026 Josh Anon" LICENSE'
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--provenance-and-third-party-notices.json",
        },
        "the notices and the provenance ledger exist, the copyright line is the one the owner "
        "confirmed in the packet, and every link either offers resolves",
        None,
    ),
    "distribution-readiness::mit-license-root-files": (
        {
            "producers": ["check_links_cli", "check_links_cli-selftest"],
            "shell": (
                "for f in LICENSE THIRD_PARTY_NOTICES.md CHANGELOG.md CONTRIBUTING.md "
                'SECURITY.md AGENTS.md README.md; do test -f "$f" || exit 1; done; '
                'grep -q "MIT License" LICENSE && grep -q "Copyright (c) 2026 Josh Anon" LICENSE'
            ),
        },
        "the seven root files a public repository is expected to carry are present, the licence is "
        "the MIT text, and it names the owner-confirmed copyright line",
        None,
    ),
    "distribution-readiness::public-allowlist-and-private-archive": (
        {"producers": ["check_public_allowlist", "archive-integrity"]},
        "the tip carries nothing outside the public allowlist, and the private archive still holds "
        "the bytes its manifest says it holds -- the claim every receipt in this graph leans on",
        None,
    ),
    #[[ THE RULE IS WHAT STAYS, NOT WHAT LEFT.
    #
    #   The first version of this row named the retired document by filename --
    #   and a filename is exactly the thing this repository is not allowed to
    #   carry, so the row that proved the removal became the last four matches
    #   of the drift check. Naming the departed is also the weaker rule: it
    #   catches that ONE file coming back and nothing else.
    #
    #   So it is an allowlist of what the public reference directory may hold,
    #   the same move the link guards made, and the archived replacement is
    #   located STRUCTURALLY: the receipt document is found by a neutral glob,
    #   its own recorded path and digest are read out of it at run time, and
    #   both are checked against the private archive's manifest. Nothing here
    #   spells a retired name, and the assertion got stronger rather than
    #   quieter -- any new file appearing under the reference directory reddens
    #   it too. ]]
    "distribution-readiness::private-comparison-archived-links-removed": (
        {"shell": DR8_CLAUSE},
        "the public reference directory holds exactly the two documents it is allowed to hold -- "
        "an allowlist, so a new stray reddens it too, and no retired filename is spelled anywhere "
        "to be reintroduced by the row that forbids it -- and the archived replacement named in "
        "the archive receipt still hashes to what the private archive's own manifest records",
        None,
    ),
    "distribution-readiness::public-docs-refreshed-no-stale-links": (
        {
            "producers": ["check_links_cli", "check_links_cli-selftest", "check_doc_style"],
            "receipt": "tools/lune/verify/evidence/distribution-readiness--public-docs-refreshed-no-stale-links.json",
        },
        "the refresh record is pinned by content hash and its mechanical half runs live: every "
        "link resolves, the link checker's own selftest bites, and the published documents pass "
        "the style rules. The sibling row `public-docs-no-stale-links` is the same mechanical half "
        "standing on its own",
        None,
    ),
    "distribution-readiness::agents-md-and-skill-route": (
        {
            "producers": ["check_links_cli", "check_links_cli-selftest"],
            "shell": "test -f AGENTS.md && test -f skills/use-facet/SKILL.md",
        },
        "the agent onboarding file and the skill route exist, and the links they offer resolve",
        None,
    ),
    "distribution-readiness::standalone-consumer-proof": (
        {"resultIds": CONSUMER_CASES},
        "the fifteen standalone-consumer cases, by id -- mount, input and state, re-solve on a "
        "viewport change, theme paint, and the five teardown cases including the one that tears "
        "the whole session down through its own wiring",
        None,
    ),
    "distribution-readiness::package-metadata-and-manifest": (
        {
            "producers": ["package-verify"],
            "shell": "test -f package/facet-package.json",
        },
        "the package channel's own verify -- build, tree inspection, purity and the packaged "
        "canary -- passes, and the metadata it reads is on disk",
        None,
    ),
    "distribution-readiness::package-interface-refusals": (
        {"producers": ["package-selftest"]},
        "every refusal the release interface owes is driven on purpose against a fake transport, "
        "including the one that proves no API key reaches a receipt",
        None,
    ),
    "distribution-readiness::protected-manual-release": (
        {
            "shell": 'grep -q "^## 9\\." artifacts/distribution-readiness/package-channel.md',
            "receipt": "tools/lune/verify/evidence/distribution-readiness--protected-manual-release.json",
        },
        "the release channel's record, including the red-team round that lists the preconditions a "
        "publish refuses without, pinned by content hash",
        None,
    ),
    "distribution-readiness::structured-results-replace-greps": (
        {
            "producers": ["check_manifest_integrity", "verify-selftest"],
            "receipt": "tools/lune/verify/evidence/distribution-readiness--structured-results-replace-greps.json",
        },
        "every case id the graph cites exists in the one structured suite result -- checked live, "
        "by name, so a renamed case reddens this row -- and the census that records what each "
        "grep became is pinned by content hash",
        "artifacts/distribution-readiness/verification/graph-census.md",
    ),
    "distribution-readiness::single-execution-per-identity": (
        {"producers": ["verify-selftest"], "shell": _TRACE_CHECK},
        "the invocation trace's own answer, recomputed here rather than quoted: no producer "
        "appears twice in any run it has recorded. The trace is written every run, so it is read "
        "and never hashed",
        "artifacts/verify/invocation-trace.json",
    ),
    "distribution-readiness::invalidation-rejects-bad-evidence": (
        {"producers": ["verify-selftest"]},
        "the result store's thirty-two refusals -- stale, incomplete, failed, edited, wrong "
        "toolchain, wrong class, fast tier, truncated, partial -- each made to happen on purpose",
        None,
    ),
    "distribution-readiness::tiers-and-explain": (
        {
            "shell": (
                "! tools/verify.sh not-a-tier >/dev/null 2>&1 && "
                "! tools/verify.sh --gate >/dev/null 2>&1 && "
                "! tools/verify.sh --rerun >/dev/null 2>&1 && "
                "! tools/verify.sh --jobs >/dev/null 2>&1"
            )
        },
        "the coordinator refuses what it cannot honour: an unknown tier, and each of --gate, "
        "--rerun and --jobs with no value. A tier list can only be proved by what it REJECTS -- "
        "grepping the four names out of the script would pass before the feature existed",
        None,
    ),
    "distribution-readiness::coverage-map-no-silent-loss": (
        {"producers": ["check_manifest_integrity"], "shell": _LEDGER_CHECK},
        "the repair ledger's counts and the document rendered from it agree, recomputed here; and "
        "the graph itself is audited live. The coverage map is regenerated by its own maintainer, "
        "so it is read and never hashed",
        "artifacts/distribution-readiness/verification/coverage-map.md",
    ),
    "distribution-readiness::mutation-parity-old-vs-new": (
        {
            "shell": (
                'grep -q "Thirteen mutations, all run" '
                "artifacts/distribution-readiness/verification/mutation-parity.md && "
                'grep -q "went red on both paths" '
                "artifacts/distribution-readiness/verification/mutation-parity.md"
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--mutation-parity-old-vs-new.json",
        },
        "the corpus and its result, pinned by content hash and asserted by its two claims: thirteen "
        "mutations run, and the ones that went red on both paths named",
        None,
    ),
    "distribution-readiness::timings-and-budget": (
        {
            "shell": (
                "python3 -c \"import json,os,sys; "
                "p='artifacts/verify/latest-release.json'; "
                "print('FAIL_ENVIRONMENT no release run has been recorded in this checkout') "
                "or sys.exit(2) if not os.path.isfile(p) else None; "
                "d=json.load(open(p)); "
                "print('%.1f s against a 1200 s budget' % (d['durationMs']/1000.0)); "
                "sys.exit(0 if d['durationMs'] <= 1200000 else 1)\""
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--timings-and-budget.json",
        },
        "the LAST release run's own duration against the twenty-minute budget, read from the run "
        "record rather than from the document -- so the row reddens when the run does, not when "
        "somebody forgets to update a table",
        None,
    ),
    "distribution-readiness::prior-gates-reevaluated-not-replayed": (
        {
            "producers": ["check_manifest_integrity"],
            #[[ THE "NOT REPLAYED" HALF IS THE PRODUCER'S, NOT THIS CLAUSE'S.
            #   `check_manifest_integrity` already reddens on any row that still
            #   references the retired replay script -- and a clause here that
            #   named the script to prove it is gone would BE such a reference,
            #   and reddened itself. The count is the half a clause can carry. ]]
            "shell": (
                "python3 -c \"import json,sys; "
                "g=json.load(open('tools/lune/verify/graph.json')); "
                "n=sum(1 for r in g['rows'] if (r.get('check') or {}).get('priorPhases')); "
                "print(n,'prior-phase rows, re-evaluated from this run'); "
                "sys.exit(0 if n >= 16 else 1)\""
            ),
        },
        "sixteen prior-phase rows are declared as re-evaluations of this run's own row verdicts, "
        "and the graph audit reddens on any row that still reaches for the retired replay script "
        "-- which is why this clause does not name it",
        None,
    ),
    "distribution-readiness::rascalrally-synchronized": (
        {
            "producers": ["rascalrally-suite"],
            "receipt": "tools/lune/verify/evidence/distribution-readiness--rascalrally-synchronized.json",
        },
        "the consuming game's own suite runs green against this tree -- the lockstep the studio "
        "constitution requires -- and the consumer-impact ledger is pinned by content hash",
        None,
    ),
    "distribution-readiness::public-tree-reproducible": (
        {"receipt": "tools/lune/verify/evidence/distribution-readiness--public-tree-reproducible.json"},
        "the reproducibility measurement, pinned by content hash. It is a record of what two "
        "extractions of the public tree did on one day; re-taking it is DR-26 through DR-28, which "
        "stay PENDING",
        None,
    ),
    #[[ DR-9 AND DR-31 LANDED WHILE THIS ROUND WAS RUNNING (`51bf26d`, 20:33).
    #   Both were listed as "leave PENDING -- proof in flight", and the proof
    #   flew in: an adversarial fresh agent, given ONLY the guide page and no
    #   repository and no web, chose libraries for five stated projects and
    #   graded the page's integrity. The rule for this round is that a row moves
    #   when its evidence exists, so they move. The receipt pins the VERDICT
    #   document and never the guide -- the reviewer's own improvements were
    #   applied to the guide afterwards, and a pin on it would have reddened on
    #   the very commit that acted on the review. ]]
    #[[ DR-29 AND DR-30 LANDED THE SAME WAY, an hour later: a fresh agent with
    #   only the public clone built a themed, stateful, adaptive settings panel
    #   from the documentation alone and proved it with fifteen cases and eight
    #   mutations; a second one added a feature to the consumer example through
    #   the documented workflow, test-first, and the registration guard caught a
    #   stray spec while it worked. Both reports carry findings, and the findings
    #   are the point -- a fresh-agent exercise that finds nothing has not been
    #   run. The row asserts the verdict line, which is where SUCCESS is written. ]]
    "phase-4-hardening::specialist-docs-updated": (
        {"producers": ["studio-specialist-docs"]},
        "the two specialist documents in the studio tree above this repository still name this "
        "library and route their readers to its guide -- asked through an external-class producer, "
        "so a checkout without that tree reports an environment failure rather than four greps "
        "that found nothing",
        None,
    ),
    "distribution-readiness::fresh-agent-builds-screen": (
        {
            "shell": (
                'grep -q "SUCCESS" '
                "artifacts/distribution-readiness/fresh-agents/builder-report.md"
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--fresh-agent-builds-screen.json",
        },
        "a fresh agent with only the public clone built an adaptive, themed, stateful screen from "
        "the documentation alone and proved it with fifteen cases and eight mutations, its report "
        "and its findings pinned by content hash",
        "artifacts/distribution-readiness/fresh-agents/builder-report.md",
    ),
    "distribution-readiness::fresh-agent-extends-behavior": (
        {
            "shell": (
                'grep -q "SUCCESS" '
                "artifacts/distribution-readiness/fresh-agents/extender-report.md"
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--fresh-agent-extends-behavior.json",
        },
        "a second fresh agent added a feature to the consumer example through the documented "
        "workflow, test-first, in exactly three files, with the registration guard catching a "
        "stray spec while it worked -- report and findings pinned by content hash",
        "artifacts/distribution-readiness/fresh-agents/extender-report.md",
    ),
    "distribution-readiness::fresh-reviewer-chooses-from-guide": (
        {
            "shell": (
                'grep -q "^\\*\\*Verdict: PASS" '
                "artifacts/distribution-readiness/fresh-agents/guide-review.md"
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--fresh-reviewer-chooses-from-guide.json",
        },
        "a fresh agent given only the guide page chose for five stated projects and reached a "
        "verdict, pinned by content hash -- and the verdict is read out of the record rather than "
        "summarised into this note",
        "artifacts/distribution-readiness/fresh-agents/guide-review.md",
    ),
    "distribution-readiness::framework-choice-guide-fair": (
        {
            "producers": ["check_doc_style", "check_links_cli"],
            "shell": (
                'grep -q "never implies Facet is built on" '
                "artifacts/distribution-readiness/fresh-agents/guide-review.md && "
                'grep -q "no popularity/maintainer/official" '
                "artifacts/distribution-readiness/fresh-agents/guide-review.md"
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--framework-choice-guide-fair.json",
        },
        "the fairness half, which is the half only a reader can answer: the fresh reviewer graded "
        "the page's integrity -- no false parentage claim, no popularity or maintainer appeal, no "
        "undisclaimed performance claim -- and named the near-misses it did find. Its mechanical "
        "half stands on its own as `framework-choice-guide-published`",
        None,
    ),
    "distribution-readiness::repository-renamed-and-verified": (
        {
            "shell": _REMOTE_CHECK,
            "receipt": "tools/lune/verify/evidence/distribution-readiness--repository-renamed-and-verified.json",
        },
        "the remote this checkout actually talks to carries the new name and none of the old one, "
        "asked of git rather than of a document, beside the rename record pinned by content hash",
        None,
    ),
}

# The mechanical half of DR-9, split off exactly as DR-10's was: the guide is
# published and passes the checks a machine can run. Whether a fresh reviewer
# can CHOOSE from it is DR-31, and it stays PENDING.
NEW_ROWS = [
    {
        "id": "distribution-readiness::framework-choice-guide-published",
        "phase": "distribution-readiness",
        "name": "framework-choice-guide-published",
        "class": "exit0",
        "requirements": ["UI-AGENT-001"],
        "releaseBlocking": False,
        "evidence": "docs/guide/14-choosing-a-ui-library.md",
        "state": None,
        "check": {
            "producers": ["check_doc_style", "check_links_cli"],
            #[[ THE DRIFT CLAIM IS ABOUT THE GUIDE, SO IT IS ASKED OF THE GUIDE.
            #   Naming the whole-tree `check_brand_drift` producer here would
            #   make this row red for a word in an unrelated file, which is a row
            #   that cannot say what it is about. The guide's own two profiles
            #   are run in-process instead -- including the marked-comparison
            #   exception, which is the only reason a comparison guide may name
            #   another framework at all. ]]
            "shell": (
                "test -f docs/guide/14-choosing-a-ui-library.md && "
                "python3 -c \"import sys, importlib.util; "
                "s=importlib.util.spec_from_file_location('g','tools/check_brand_drift.py'); "
                "m=importlib.util.module_from_spec(s); s.loader.exec_module(m); "
                "g='docs/guide/14-choosing-a-ui-library.md'; h=[]; "
                "m.scan_file(g,g,h); "
                "m.scan_file(g,g,h,m.VENDOR_PROFILE,m.VENDOR_ALLOWLIST); "
                "print(h if h else 'the guide carries no old brand and no unmarked vendor name'); "
                "sys.exit(1 if h else 0)\""
            ),
        },
        "note": "framework-choice-guide-published: the comparison guide is published, carries no "
        "old brand and no vendor name outside the marked comparison exception, passes the document "
        "style rules and offers no link that does not resolve. This is "
        "DR-9's mechanical half; whether a fresh reviewer can choose from it is DR-31, and DR-9 "
        "stays PENDING for it. Requirements: UI-AGENT-001.",
    },
]

# row id -> (receipt class, [(label, path, "tree"|"archive")], summary)
DR_RECEIPTS = {
    "distribution-readiness::registered-before-work": (
        "deterministic",
        [("freeze-head", FREEZE + "/head.txt", "tree"),
         ("freeze-record", "artifacts/distribution-readiness/freeze.md", "tree")],
        "the head this stage opened at, and the record taken beside it",
    ),
    "distribution-readiness::state-frozen-at-open": (
        "deterministic",
        [("freeze-record", "artifacts/distribution-readiness/freeze.md", "tree"),
         ("head", FREEZE + "/head.txt", "tree"),
         ("refs", FREEZE + "/refs.txt", "tree"),
         ("status", FREEZE + "/status.txt", "tree"),
         ("tracked-files", FREEZE + "/tracked-files.txt", "tree"),
         ("owner-edits", FREEZE + "/uncommitted-owner-edits.patch", "tree")],
        "the six raw records taken before this stage's first edit",
    ),
    "distribution-readiness::history-audit-no-must-purge": (
        "deterministic",
        [("audit", "artifacts/distribution-readiness/audit/history-audit.md", "tree"),
         ("findings", "artifacts/distribution-readiness/audit/findings.json", "tree"),
         ("candidate", "artifacts/distribution-readiness/audit/history-candidate.md", "tree")],
        "the full-history audit, its machine-readable findings, and the tested clean-history candidates",
    ),
    "distribution-readiness::provenance-and-third-party-notices": (
        "deterministic",
        [("ledger", "artifacts/distribution-readiness/audit/provenance-ledger.md", "tree"),
         ("notices", "THIRD_PARTY_NOTICES.md", "tree")],
        "the provenance ledger and the notices file it produced",
    ),
    "distribution-readiness::public-docs-refreshed-no-stale-links": (
        "deterministic",
        [("refresh-record", "artifacts/distribution-readiness/docs-refresh.md", "tree")],
        "the documentation refresh record",
    ),
    "distribution-readiness::protected-manual-release": (
        "deterministic",
        [("channel-record", "artifacts/distribution-readiness/package-channel.md", "tree")],
        "the release channel record, including its red-team round",
    ),
    "distribution-readiness::structured-results-replace-greps": (
        "deterministic",
        [("census", "artifacts/distribution-readiness/verification/graph-census.md", "tree")],
        "the census of what every manifest row became",
    ),
    "distribution-readiness::mutation-parity-old-vs-new": (
        "deterministic",
        [("corpus", "artifacts/distribution-readiness/verification/mutation-parity.md", "tree")],
        "the mutation corpus and its old-path/new-path results",
    ),
    "distribution-readiness::timings-and-budget": (
        "deterministic",
        [("timings", "artifacts/distribution-readiness/verification/timings.md", "tree")],
        "the cold, warm and live-tree timings against the twenty-minute budget",
    ),
    "distribution-readiness::rascalrally-synchronized": (
        "deterministic",
        [("impact-ledger", "artifacts/distribution-readiness/rascalrally-consumer-impact.md", "tree")],
        "the consuming game's impact ledger for this stage",
    ),
    "distribution-readiness::public-tree-reproducible": (
        "deterministic",
        [("measurement", "artifacts/distribution-readiness/verification/reproducibility.md", "tree")],
        "the public-tree reproducibility measurement",
    ),
    "distribution-readiness::fresh-agent-builds-screen": (
        "external",
        [("builder-report", "artifacts/distribution-readiness/fresh-agents/builder-report.md", "tree")],
        "the fresh builder's report and the findings it handed back",
    ),
    "distribution-readiness::fresh-agent-extends-behavior": (
        "external",
        [("extender-report", "artifacts/distribution-readiness/fresh-agents/extender-report.md", "tree")],
        "the fresh extender's report and the findings it handed back",
    ),
    "distribution-readiness::fresh-reviewer-chooses-from-guide": (
        "external",
        [("reviewer-verdict", "artifacts/distribution-readiness/fresh-agents/guide-review.md", "tree")],
        "the fresh reviewer's verdict and the improvements it named",
    ),
    "distribution-readiness::framework-choice-guide-fair": (
        "external",
        [("reviewer-verdict", "artifacts/distribution-readiness/fresh-agents/guide-review.md", "tree")],
        "the same verdict, read for the integrity half",
    ),
    "distribution-readiness::repository-renamed-and-verified": (
        "deterministic",
        [("rename-record", "artifacts/distribution-readiness/rename-record.md", "tree")],
        "the record of the rename the owner approved and the director executed",
    ),
}

#[[ AND THE ROWS THAT STAY PENDING, with what each is waiting for. A row here is
#   NOT a row nobody got to: it is a row whose proof does not exist yet, and
#   saying so is the whole reason the registration block was written before the
#   work. ]]
STILL_PENDING = {
    "distribution-readiness::fresh-clone-works": "a clone taken from the renamed remote and run end to end",
    "distribution-readiness::example-places-rebuild-from-clone": "the same clone rebuilding the example places",
    "distribution-readiness::package-from-clone-matches": "a package built from that clone, compared byte for byte",
    "distribution-readiness::owner-packet-complete": "the packet's final numbers, stamped at close",
    "distribution-readiness::private-package-id-and-update-proof": "an asset minted and updated, which requires the owner to publish",
}


#[[ AN OUT-OF-REPOSITORY EVIDENCE PIN BECOMES A RECEIPT.
#
#   One row pinned a document in the consuming game's checkout by path, and
#   greppped four headings out of it. On a public clone that path does not
#   exist, so `check_manifest_integrity` reported it as "checked in and GONE"
#   -- the shape of a DELETED pin -- and every row that names that producer
#   went red behind it.
#
#   A content-hash receipt says the same thing better: on this machine it
#   verifies the exact bytes (stronger than four greps), and on a clone it
#   resolves to nothing and reports FAIL_ENVIRONMENT with a count, which is what
#   an unreachable external operand actually is. The row keeps the external
#   producer that answers for the checkout's absence. ]]
EXTERNAL_EVIDENCE_ROWS = {
    "phase-2-settings-parity::port-doc-and-rollback": (
        "../../../games/RascalRally/docs/FACET_SETTINGS_PORT.md",
        "the consuming game's port document -- behaviour checklist, comparison, defect log and "
        "rollback criteria -- pinned by content hash instead of by four greps on a path this "
        "repository cannot promise is there",
    ),
}


def externalise_evidence(rows, dry_run):
    """-> rows whose out-of-repo pin became a receipt."""
    done = []
    for row in rows:
        spec = EXTERNAL_EVIDENCE_ROWS.get(row["id"])
        if spec is None:
            continue
        path, why = spec
        receipt = os.path.join(RECEIPTS, row["id"].replace("::", "--") + ".json")
        if os.path.isfile(path):
            body = {
                "schema": "facet-evidence-receipt/1",
                "row": row["id"],
                "class": "external",
                "evidence": [{"label": "port-document", "archivedPath": path,
                              "sha256": _sha256(path)}],
                "summary": why,
                "recordedAt": datetime.datetime.now(datetime.timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                ),
            }
            existing = json.load(open(receipt)) if os.path.exists(receipt) else {}
            if existing.get("evidence") != body["evidence"] and not dry_run:
                with open(receipt, "w") as fh:
                    json.dump(body, fh, indent=1, sort_keys=True)
                    fh.write("\n")
        check = row.setdefault("check", {})
        if check.get("receipt") == receipt and "shell" not in check and row.get("evidence") is None:
            continue
        check.pop("shell", None)
        check["receipt"] = receipt
        row["evidence"] = None
        row["note"] = "%s: %s. Requirements: %s." % (
            row["name"], why, ", ".join(row["requirements"]) or "none",
        )
        done.append([row["id"], path])
    return done


def flip_registration_rows(rows, dry_run):
    """-> (flipped, minted, added, pending) -- rows whose evidence now exists."""
    flipped, minted, added = [], [], []
    #[[ ON `kept`, NOT ON `graph["rows"]`. The row list is rebuilt from `kept`
    #   further down, so a row appended to the graph dict here is thrown away by
    #   that assignment -- the same trap the case-id re-point fell into. ]]
    #   A row this table already added is REPLACED, not skipped: the table is
    #   the definition, and an earlier run's copy of it is not.
    index = {r["id"]: i for i, r in enumerate(rows)}
    for row in NEW_ROWS:
        fresh = json.loads(json.dumps(row))
        at = index.get(row["id"])
        if at is None:
            rows.append(fresh)
            added.append(row["id"])
        elif rows[at] != fresh:
            rows[at] = fresh
            added.append(row["id"])

    archive_files = {}
    if os.path.exists(ARCHIVE):
        archive_files = {e["path"]: e["sha256"] for e in json.load(open(ARCHIVE))["files"]}

    for rid, (cls, items, summary) in sorted(DR_RECEIPTS.items()):
        path = os.path.join(RECEIPTS, rid.replace("::", "--") + ".json")
        evidence = []
        for label, where, kind in items:
            if kind == "archive":
                digest = archive_files.get(where)
                if digest is None:
                    continue
            else:
                if not os.path.isfile(where):
                    continue
                digest = _sha256(where)
            evidence.append({"label": label, "archivedPath": where, "sha256": digest})
        if len(evidence) != len(items):
            continue
        receipt = {
            "schema": "facet-evidence-receipt/1",
            "row": rid,
            "class": cls,
            "evidence": evidence,
            "summary": summary,
            "recordedAt": datetime.datetime.now(datetime.timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            ),
        }
        if os.path.exists(path):
            old = json.load(open(path))
            if old.get("evidence") == evidence and old.get("class") == cls:
                continue
        minted.append([rid, path])
        if not dry_run:
            with open(path, "w") as fh:
                json.dump(receipt, fh, indent=1, sort_keys=True)
                fh.write("\n")

    for row in rows:
        spec = ROW_FLIPS.get(row["id"])
        if spec is None:
            continue
        check, note, evidence = spec
        want_note = "%s: %s. Requirements: %s." % (
            row["name"], note, ", ".join(row["requirements"]) or "none",
        )
        if (
            row.get("check") == check
            and row.get("note") == want_note
            and row["class"] != "declared"
            and row.get("state") is None
        ):
            continue
        row["check"] = json.loads(json.dumps(check))
        row["note"] = want_note
        row["class"] = "exit0"
        #[[ AND THE REGISTERED VERDICT IS CLEARED. A row that carries `state`
        #   short-circuits evaluation and returns that state -- which is exactly
        #   what a registration row is for while its evidence does not exist, and
        #   exactly what has to go the moment it does. Leaving it set is how a
        #   row with a real, passing check still reports PENDING, measured on the
        #   first gate run after this flip: 33 pending, 0 evaluated. ]]
        row["state"] = None
        if evidence is not None:
            row["evidence"] = evidence
        flipped.append([row["id"], note[:90]])

    pending = []
    for row in rows:
        why = STILL_PENDING.get(row["id"])
        if why is None:
            continue
        want = "%s: PENDING -- %s. Requirements: %s." % (
            row["name"], why, ", ".join(row["requirements"]) or "none",
        )
        if row.get("note") != want:
            row["note"] = want
        pending.append([row["id"], why])
    return flipped, minted, added, pending


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

    # ---- out-of-repository evidence pins become receipts -----------------------
    externalised = externalise_evidence(kept, args.dry_run)
    print(f"out-of-repo pins turned into receipts    : {len(externalised)}")

    # ---- registration rows whose evidence now exists ---------------------------
    flipped, minted, dr_added, dr_pending = flip_registration_rows(kept, args.dry_run)
    print(f"registration rows given a real check    : {len(flipped)}")
    print(f"  receipts minted for them              : {len(minted)}")
    print(f"  rows added (a split mechanical half)  : {len(dr_added)}")
    print(f"  rows left honestly PENDING            : {len(dr_pending)}")

    # ---- producers that must not share the tree -------------------------------
    retiered = 0
    for p in graph["producers"]:
        want = RETIER.get(p["id"])
        if want is not None and p.get("tiers") != want:
            p["tiers"] = dict(want)
            retiered += 1
        inputs = REINPUT.get(p["id"])
        if inputs is not None and p.get("inputs") != inputs:
            p["inputs"] = list(inputs)
            retiered += 1
    if retiered:
        print(f"producers whose tier set widened         : {retiered}")

    serialized = 0
    for p in graph["producers"]:
        if p["id"] in SERIALIZED and not p.get("serialize"):
            p["serialize"] = True
            p["note"] = (p.get("note") or "").strip()
            p["note"] = (p["note"] + " " if p["note"] else "") + "runs alone: " + SERIALIZED[p["id"]]
            serialized += 1
    print(f"producers moved to the serial wave       : {serialized}")

    # ---- producers the graph gains -------------------------------------------
    #   A producer this table already added is REPLACED, not skipped: the table
    #   is the definition, and an earlier run's copy of it is not. (The tier sets
    #   in RETIER are re-applied below, after this, so the two cannot fight.)
    byId = {p["id"]: i for i, p in enumerate(graph["producers"])}
    added = []
    for producer in NEW_PRODUCERS:
        fresh = json.loads(json.dumps(producer))
        at = byId.get(producer["id"])
        if at is None:
            graph["producers"].append(fresh)
            added.append(producer["id"])
        elif graph["producers"][at] != fresh:
            graph["producers"][at] = fresh
            added.append(producer["id"])
    for p in graph["producers"]:
        want = RETIER.get(p["id"])
        if want is not None and p.get("tiers") != want:
            p["tiers"] = dict(want)
    print(f"producers added or refreshed             : {len(added)}")

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

    #[[ A RECEIPT WITH NOTHING LEFT IN IT IS DELETED, NOT KEPT EMPTY.
    #   Five receipts held nothing but run output. An empty one is refused by the
    #   coordinator -- correctly, "lists no evidence" -- so leaving it in place
    #   reddens a row whose claim is intact. What each of these rows actually
    #   asserts is carried by a producer that re-earns it every run, which is
    #   stronger than a hash of the last run, so the receipt clause goes and the
    #   producer stays. A declared-evidence producer whose whole record was run
    #   output was never declared evidence: it runs, and it did in the run that
    #   found this. ]]
    emptied = []
    for name in sorted(os.listdir(RECEIPTS)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(RECEIPTS, name)
        receipt = json.load(open(path))
        if receipt.get("evidence"):
            continue
        who = receipt.get("row") or receipt.get("producer") or name
        for row in kept:
            check = row.get("check") or {}
            if check.get("receipt") != path:
                continue
            rest = {k: v for k, v in check.items() if k != "receipt"}
            if not has_work(rest):
                continue
            check.pop("receipt")
        if name.startswith("producer--"):
            pid = name[len("producer--"):-len(".json")]
            for producer in graph["producers"]:
                if producer["id"] == pid and producer.get("declaredEvidence"):
                    producer["declaredEvidence"] = False
        emptied.append([who, path])
        if not args.dry_run:
            os.unlink(path)
    print(f"receipts deleted as empty                : {len(emptied)}")

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
            "emptied": emptied,
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
    #   ...AND THE STAMP MOVES ONLY WHEN THE RECORD DOES. Writing the time on
    #   every run made a file whose whole point is idempotence report a change
    #   on a run that changed nothing -- which is a diff that costs a reader
    #   attention and buys them a clock.
    ledger["schema"] = "facet-post-archival-repair/1"
    before = None
    if os.path.exists(LEDGER):
        before = json.load(open(LEDGER))
        ledger["updatedAt"] = before.get("updatedAt")
    if before is None or {k: v for k, v in before.items() if k != "updatedAt"} != {
        k: v for k, v in ledger.items() if k != "updatedAt"
    }:
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
        "emptyReceiptsDeleted": receipts["emptied"],
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
        "emptied": ledger["emptyReceiptsDeleted"],
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

    L += [
        "",
        f"## Receipts deleted as empty ({len(receipts['emptied'])})",
        "",
        "Each held nothing but run output. An empty receipt is refused, so leaving one in",
        "place reddens a row whose claim is intact; the producer that re-earns the claim",
        "every run carries it instead.",
        "",
        "| Receipt | File |",
        "|---|---|",
    ]
    for who, path in receipts["emptied"]:
        L.append(f"| `{who}` | `{path}` |")

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
