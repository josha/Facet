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
    r"|cross-platform-proof/rows/xp-a6-regression-proof\.json"
    #   ...and so does `check_perf_place`, whose whole output IS
    #   `performance-stress-places/place.json`: it re-scans the built place and
    #   rewrites the file, byte size and all. Twelve receipts pinned it, so every
    #   `check_perf_gate_evidence-*` producer went red the run after the
    #   performance place was rebuilt (3 061 361 -> 3 073 210 bytes) — the same
    #   "measuring the clock" defect the two entries above name, found 2026-09-01.
    r"|performance-stress-places/place\.json)"
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
    (
        "commit_walks_seam::the commit-walk seam: the shared WRITE surface, and who owns each lifetime::"
        "the module writes through exactly twelve of the twenty-one records it is handed",
        "commit_walks_seam::the commit-walk seam: the shared WRITE surface, and who owns each lifetime::"
        "the module writes through exactly sixteen of the twenty-six records it is handed",
        "the same case, renamed by P4 (36602eba, 2026-09-01) when the commit prune moved four "
        "rebuild-wholesale maps into the shared write surface and added a fifth minimal-write "
        "record, growing the parameter object from twenty-one fields to twenty-six and the "
        "written set from twelve to sixteen",
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

#[[ THE PUBLIC-CLONE RUN IS A MACHINE RECORD, AND THE ROWS READ IT.
#   `artifacts/distribution-readiness/verification/public-clone-full-run.json`
#   is the verbatim run record of `tools/verify.sh full` inside a clone with no
#   parent workspace. It carries all 131 producer outcomes and all 508 row
#   verdicts, so these three rows assert facts out of it rather than a sentence
#   about it -- and a receipt pins the bytes so the facts cannot be edited into
#   existence afterwards. ]]
CLONE_RECORD = "artifacts/distribution-readiness/verification/public-clone-full-run.json"


def _clone_check(body: str) -> str:
    """A shell clause that reads FACTS out of the clone run's own record.

    Real newlines, not the two characters `\\n`: the clause is handed to
    `bash -c` inside double quotes, where a backslash-n survives as a backslash
    and a letter, and `python3 -c` then reads it as a line continuation followed
    by rubbish. Measured, once, by all three of these clauses failing at the
    same character.
    """
    header = "\n".join([
        "",
        "import json, sys",
        "d = json.load(open('" + CLONE_RECORD + "'))",
        "producers = {p['id']: p['status'] for p in d['producers']}",
        "failedRows = [r for r in d['rows'] if r['state'] == 'FAIL_RECOVERABLE']",
        "failedProducers = [k for k, v in producers.items() if v == 'FAIL']",
        "",
    ])
    return 'python3 -c "' + header + body + '"' 


_BUDGET_CHECK = (
    "python3 -c \"import json,os,sys; "
    "p='artifacts/verify/latest-release.json'; "
    "print('FAIL_ENVIRONMENT no release run has been recorded in this checkout') "
    "or sys.exit(2) if not os.path.isfile(p) else None; "
    "d=json.load(open(p)); "
    "print('%.1f s against a 1200 s budget' % (d['durationMs']/1000.0)); "
    "sys.exit(0 if d['durationMs'] <= 1200000 else 1)\""
)

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

#[[ STEP 13.5's CLOSE-OUT ROWS, BOUND TO WHAT ACTUALLY SHIPPED (2026-08-31).
#
#   Twenty-two rows of `example-games-and-standalones` were registered honest-
#   PENDING and never earned a run string when the stage's missions landed on
#   2026-08-29/30. The work is in the tree -- the crossword, the match-3 motion,
#   the sensory demo, the outpost terminal, the two reference loops, the
#   manifest-driven places and the whole verification optimization -- so the
#   rows bind to it.
#
#   THE SAME RULE AS THE REGISTRATION FLIPS: existing evidence only. Every bind
#   below is a suite case id that exists in this run's result, a live producer,
#   or a content hash of a finished record. Nothing is bound to a claim without
#   an artifact, and one row is left PENDING because its evidence does not exist.
#
#   TWO KINDS OF EVIDENCE MOVED HOUSE, and the notes say so:
#     * the stage's verification-optimization artifacts are archived, and their
#       LIVING successors are this workstream's own census, parity, trace and
#       coverage documents plus the producers that re-earn them every run;
#     * several game rows were originally PLAYED IN STUDIO. A headless run
#       cannot re-play them, so the bind is the suite case that survives plus
#       the archived stage record as a receipt, and the note says the Studio
#       play predates this stage rather than pretending it was re-taken. ]]

TILE_CASES = [
    "example_tile_game::examples/06 crossword — axis, run and connection::ONE tile does not fix an axis — the board does",
    "example_tile_game::examples/06 crossword — axis, run and connection::a gap in the run is refused, and a gap CLOSED by a committed letter is not",
    "example_tile_game::examples/06 crossword — axis, run and connection::a turn's tiles lie in one row or one column, and scattered tiles are refused",
    "example_tile_game::examples/06 crossword — axis, run and connection::connection is ORTHOGONAL: touching diagonally is not touching",
    "example_tile_game::examples/06 crossword — axis, run and connection::the first turn must cover the starred centre, and later turns must not",
    "example_tile_game::examples/06 crossword — axis, run and connection::the main word is read THROUGH committed letters at both ends",
    "example_tile_game::examples/06 crossword — both endings, and the way back::reaching the goal wins, and the screen says which ending it was",
    "example_tile_game::examples/06 crossword — both endings, and the way back::restart returns EVERY observable to its seeded start",
    "example_tile_game::examples/06 crossword — both endings, and the way back::spending the budget without reaching the goal loses, and says so",
    "example_tile_game::examples/06 crossword — commit, refill, undo, budget::A REFUSED SUBMIT CHANGES NOTHING — every tile stays where the player put it",
    "example_tile_game::examples/06 crossword — commit, refill, undo, budget::a committed turn scores, banks the letters, and refills the rack to seven",
    "example_tile_game::examples/06 crossword — commit, refill, undo, budget::the legal-next-cell cue follows the rules, and locks with the axis",
    "example_tile_game::examples/06 crossword — commit, refill, undo, budget::the turn budget decrements only on a commit",
    "example_tile_game::examples/06 crossword — commit, refill, undo, budget::undo returns exactly the uncommitted tiles, to the slots they came from",
    "example_tile_game::examples/06 crossword — commit, refill, undo, budget::undo with nothing placed says so instead of doing nothing",
    "example_tile_game::examples/06 crossword — committed versus uncommitted is not a colour::...and the same fact a third time, in ASCII, for a screen with no colour at all",
    "example_tile_game::examples/06 crossword — committed versus uncommitted is not a colour::a committed letter wears a solid plate and an uncommitted one wears an outline",
    "example_tile_game::examples/06 crossword — committed versus uncommitted is not a colour::a spent rack slot is DISABLED, not a live-looking blank button",
    "example_tile_game::examples/06 crossword — determinism::a fixed script on a fixed seed lands on the same board, score and dump",
    "example_tile_game::examples/06 crossword — determinism::the same seed deals the same rack and the same bag",
    "example_tile_game::examples/06 crossword — every word a turn creates::a crossing word the dictionary does not know refuses the whole turn, BY NAME",
    "example_tile_game::examples/06 crossword — every word a turn creates::every perpendicular word a placed tile now sits inside is extracted and validated",
    "example_tile_game::examples/06 crossword — every word a turn creates::the score counts every letter in every word, once per word it appears in",
    "example_tile_game::examples/06 crossword — every word a turn creates::using five or more rack tiles in one turn adds ten",
    "example_tile_game::examples/06 crossword — forty-nine cells that are actually there, in every theme::...and the floor BITES: the plate the word game used to paint clears it nowhere",
    "example_tile_game::examples/06 crossword — forty-nine cells that are actually there, in every theme::every cell state paints a plate the player can see, under every theme",
    "example_tile_game::examples/06 crossword — forty-nine cells that are actually there, in every theme::sweeps a real set of themes, not an empty one",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::...and an uncommitted tile CAN be picked back up, which is what makes 9 a rule",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::...and tapping an empty square with nothing held explains itself too",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::1 — the first turn misses the centre",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::2 — the tiles are not in one line",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::3 — a gap in the run",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::4 — a later turn touches nothing",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::5 — the main word is unknown, and the sentence names it",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::6 — a crossing word is unknown, and the sentence names it AND its direction",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::7 — submit with nothing placed",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::8 — placing on an occupied square",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::9 — picking up a letter from an earlier turn",
    "example_tile_game::examples/06 crossword — nine refusals, nine sentences, on screen::the instruction line names the held tile, and clears on a placement",
    "example_tile_game::examples/06 crossword — robustness::rapid alternating input leaves no stale selection or held tile",
    "example_tile_game::examples/06 crossword — robustness::tears down to a registry baseline after dispose",
    "example_tile_game::examples/06 crossword — the deal guarantees an opening::...and so does every seed in a wide sweep, inside the attempt bound",
    "example_tile_game::examples/06 crossword — the deal guarantees an opening::openingWord finds a word from a SUBSET in any order, and nil when there is none",
    "example_tile_game::examples/06 crossword — the deal guarantees an opening::the shipped seed deals a rack that spells something across the centre",
    "example_tile_game::examples/06 crossword — the dictionary is the shared module::a run the dictionary CANNOT judge is refused by name, not called unknown",
    "example_tile_game::examples/06 crossword — the dictionary is the shared module::accepts and rejects through `words`, not through a list this game keeps",
    "example_tile_game::examples/06 crossword — the rules are pure::the bag is the 98-tile familiar multiset, with no blanks",
    "example_tile_game::examples/06 crossword — the rules are pure::the board, the rack, the budget and the goal are the design's numbers",
    "example_tile_game::examples/06 crossword — the rules are pure::the letter values are the familiar English ones",
]

MATCH3_CASES = [
    "example_match3_motion::match-3 motion: a reset mid-cascade leaves nothing behind::dispose mid-cascade unregisters the hook and leaves the registry at baseline",
    "example_match3_motion::match-3 motion: a reset mid-cascade leaves nothing behind::stops the machine, drops its tick hook, and leaves no retiring row or animation record",
    "example_match3_motion::match-3 motion: reduced motion changes the paint and nothing else::...and reduced motion installs NO animation records rather than substituting another effect",
    "example_match3_motion::match-3 motion: reduced motion changes the paint and nothing else::the example contains no reduced-motion branch at all",
    "example_match3_motion::match-3 motion: reduced motion changes the paint and nothing else::the same board, score, moves, phase log and replay under both policies",
    "example_match3_motion::match-3 motion: the anchored board still navigates in two dimensions::...and everything below the board is still reachable without a pointer",
    "example_match3_motion::match-3 motion: the anchored board still navigates in two dimensions::left/right walks the lane and up/down keeps it, before AND after a cascade",
    "example_match3_motion::match-3 motion: the example builds no animation system of its own::...and it really did scan the example, which uses the four public mechanisms by name",
    "example_match3_motion::match-3 motion: the example builds no animation system of its own::finds none of them in a single line of its code",
    "example_match3_motion::match-3 motion: the resolve sequence is visible, in order::a matched tile leaves the model and stays mounted-but-retiring while it fades",
    "example_match3_motion::match-3 motion: the resolve sequence is visible, in order::a refilled tile's FIRST painted position is above the board, not its resting one",
    "example_match3_motion::match-3 motion: the resolve sequence is visible, in order::a survivor DROPS: its painted position is between its old row and its new one",
    "example_match3_motion::match-3 motion: the resolve sequence is visible, in order::a tap while the board resolves is REFUSED in words, and costs nothing",
    "example_match3_motion::match-3 motion: the resolve sequence is visible, in order::removal precedes gravity precedes refill, and input unlocks after the last cascade",
    "example_match3_motion::match-3 motion: the two swapped tiles travel::a refused swap travels OUT and travels BACK, and says why",
    "example_match3_motion::match-3 motion: the two swapped tiles travel::halfway through the swap phase both tiles are painted at NEITHER endpoint",
    "example_match3_motion::match-3 motion: thirty-six tiles that are actually painted, in every shipped theme::...and the floor BITES: the role this example carried until this round drops under it",
    "example_match3_motion::match-3 motion: thirty-six tiles that are actually painted, in every shipped theme::every tile picture clears the visibility floor against the page it sits on",
    "example_match3_motion::match-3 motion: thirty-six tiles that are actually painted, in every shipped theme::sweeps a real set of themes, not an empty one",
    "example_match3_motion::match-3 motion: tile identity survives a move::every id on the board is unique, and a refill never reuses one",
    "example_match3_motion::match-3 motion: tile identity survives a move::the mounted node for a tile id is the same node it was before the swap",
]

SENSORY_FEEDBACK_CASES = [
    "sensory_feedback::UI.sensoryFeedback: the declaration is ruled on at the call site::accepts every one of the twelve verbs",
    "sensory_feedback::UI.sensoryFeedback: the declaration is ruled on at the call site::refuses a structural region — it would mount no node to emit for",
    "sensory_feedback::UI.sensoryFeedback: the declaration is ruled on at the call site::refuses a trigger that is not a Signal/Memo — a constant never changes",
    "sensory_feedback::UI.sensoryFeedback: the declaration is ruled on at the call site::refuses an event outside the closed twelve, listing the vocabulary",
    "sensory_feedback::UI.sensoryFeedback: the declaration is ruled on at the call site::refuses an unknown spec key rather than dropping it",
    "sensory_feedback::UI.sensoryFeedback: the declaration is ruled on at the call site::returns a NEW frozen blueprint and leaves the original untouched",
    "sensory_feedback::UI.sensoryFeedback: through the real presenter::is visible on handle.onFeedback, the per-surface filter",
    "sensory_feedback::UI.sensoryFeedback: through the real presenter::reaches presenter.onFeedback, carrying the surface it happened on",
    "sensory_feedback::UI.sensoryFeedback: what reaches the bus::composes: two declarations on one node both fire",
    "sensory_feedback::UI.sensoryFeedback: what reaches the bus::emits synchronously inside the write that moved the trigger",
    "sensory_feedback::UI.sensoryFeedback: what reaches the bus::emits the declared verb with the mounted path when the trigger changes",
    "sensory_feedback::UI.sensoryFeedback: what reaches the bus::fires once per change, and not at all for a write of the same value",
    "sensory_feedback::UI.sensoryFeedback: what reaches the bus::observes NOTHING when no sink is wired, and exactly one thing when one is",
    "sensory_feedback::UI.sensoryFeedback: what reaches the bus::stops emitting the moment the node unmounts",
]

SENSORY_PROFILE_CASES = [
    "sensory_profile::sensory profile: it is ENGINE-FREE, which is why any of this is provable::requires nothing and names no engine global — in CODE, not in prose",
    "sensory_profile::sensory profile: key() is what makes pooling possible::label() names a sensation for a reader — the waveform, or the preset, or nothing",
    "sensory_profile::sensory profile: key() is what makes pooling possible::the three default keys are distinct — three waveforms, three instances",
    "sensory_profile::sensory profile: key() is what makes pooling possible::two specs that would FEEL the same share a key; different ones do not",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::`Custom` may not be named as a PRESET — it is a silent no-op by construction",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::a Custom phase with NO keys is refused — it is the guaranteed silent no-op",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::a game SILENCES one phase, and silence is a decision rather than an omission",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::a game replaces ONE phase and keeps the other two",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::a game swaps a phase for a PRESET without touching any control",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::a preset naming something that is not a HapticEffectType is refused",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::a spec whose `kind` is not one of the three is refused",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::all three at once, in one call",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::an unknown phase key is an authoring error that names the three phases",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::nothing supplied is the defaults, value for value",
    "sensory_profile::sensory profile: resolve() merges a partial over the defaults::the result is frozen too, so a resolved profile cannot be edited behind the adapter",
    "sensory_profile::sensory profile: the preset FALLBACK, and the limitation it carries::fallbackFor(phase) hands back the phase's preset SPEC, ready to pool",
    "sensory_profile::sensory profile: the preset FALLBACK, and the limitation it carries::is TOTAL over the phases — a fourth phase would be a visible gap",
    "sensory_profile::sensory profile: the preset FALLBACK, and the limitation it carries::names one preset per phase, and every one is a real HapticEffectType",
    "sensory_profile::sensory profile: the preset FALLBACK, and the limitation it carries::release and select SHARE UIHover, and that is the documented limitation",
    "sensory_profile::sensory profile: the three defaults are the product, pinned exactly::every mode names a real Enum.KeyInterpolationMode member",
    "sensory_profile::sensory profile: the three defaults are the product, pinned exactly::no default key authors an intensity below the documented trigger floor",
    "sensory_profile::sensory profile: the three defaults are the product, pinned exactly::no default outlasts the overlap budget, and every key list rises in time from 0",
    "sensory_profile::sensory profile: the three defaults are the product, pinned exactly::press is `contact` — one short, crisp tap when the action goes down",
    "sensory_profile::sensory profile: the three defaults are the product, pinned exactly::release is `settle` — a lighter, rounder answer when the action completes",
    "sensory_profile::sensory profile: the three defaults are the product, pinned exactly::select is `tick` — the smallest audible-to-the-hand step for a changed choice",
    "sensory_profile::sensory profile: the three defaults are the product, pinned exactly::the defaults are FROZEN all the way down — a consumer cannot edit the product",
    "sensory_profile::sensory profile: the three defaults are the product, pinned exactly::the three names are distinct, and PHASES lists exactly the three phases",
]

TERMINAL_CASES = [
    "outpost_terminal::outpost authority: every refusal the server can make::REFUSAL 1 — nobody holds the console, or somebody else does",
    "outpost_terminal::outpost authority: every refusal the server can make::REFUSAL 2 — a stale session token, or no token at all",
    "outpost_terminal::outpost authority: every refusal the server can make::REFUSAL 3 — faster than a hand can press",
    "outpost_terminal::outpost authority: every refusal the server can make::REFUSAL 4 — too far, MEASURED, and an unmeasurable distance is not a pass",
    "outpost_terminal::outpost authority: every refusal the server can make::REFUSAL 5 — the allocation itself, through the same rules the terminal ran",
    "outpost_terminal::outpost authority: every refusal the server can make::THE ORDER IS PART OF THE CONTRACT: who you are beats how far, beats what you asked",
    "outpost_terminal::outpost authority: every refusal the server can make::the happy path: the holder, a fresh token, in range, with a legal allocation",
    "outpost_terminal::outpost rules: every refusal, and the exact sentence it uses::THE ORDER IS PART OF THE CONTRACT: a fraction that is also over budget says `whole`",
    "outpost_terminal::outpost rules: every refusal, and the exact sentence it uses::a fraction is refused as `whole`, naming the consumer and the value",
    "outpost_terminal::outpost rules: every refusal, and the exact sentence it uses::a missing consumer is refused as `missing`, and an extra one as `unknown`",
    "outpost_terminal::outpost rules: every refusal, and the exact sentence it uses::every declared refusal code has a sentence, and an undeclared one is loud",
    "outpost_terminal::outpost rules: every refusal, and the exact sentence it uses::the three server-only sentences are the ones the design specifies",
    "outpost_terminal::outpost rules: the ranges, walked rather than sampled::THE TRADE-OFF IS REAL: a fully-lit workshop can never leave all three running",
    "outpost_terminal::outpost rules: the ranges, walked rather than sampled::WHAT RUNNING MEANS is `at least what it needs`, over the whole product",
    "outpost_terminal::outpost rules: the ranges, walked rather than sampled::every value inside 0..capacity is legal, and capacity+1 and -1 are not",
    "outpost_terminal::outpost rules: the ranges, walked rather than sampled::the starting allocation is legal, and is a problem with an obvious first move",
    "outpost_terminal::outpost rules: the ranges, walked rather than sampled::the three declared ranges are the design's, and the goal is reachable inside them",
    "outpost_terminal::outpost rules: the ranges, walked rather than sampled::the total bound is exactly six, over the whole product",
    "outpost_terminal::outpost rules: what changed, which is what the terminal reports::only a CROSSING is news; a number that moved without crossing is not",
    "outpost_terminal::outpost rules: what changed, which is what the terminal reports::the outcome sentence has three cases and picks the player's one first",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::A REFUSAL IS SHOWN, NOT SWALLOWED — and the draft survives it",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::ADJUST moves the draft, and the budget line and the live verdict follow it",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::AN EDIT RETIRES THE LAST OUTCOME, so the line never stands over state it contradicts",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::AN ILLEGAL DRAFT IS REFUSED HERE and never reaches the wire",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::APPLY sends ONE intent carrying the draft, and `pending` is not success",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::ENGAGE seeds the draft from what the outpost is actually running",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::RESET IS A SERVER INTENT, not a local undo",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::SUCCESS: the verdict lands, the outpost moves, and the terminal says what changed",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::a SECOND apply while one is in flight is refused instead of throwing",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::a terminal nobody is standing at is idle, and says the objective",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::an allocation ANOTHER player applied lands without touching this draft",
    "outpost_terminal::outpost terminal: engage -> adjust -> apply -> success -> reset -> exit::every server refusal reaches the screen as its own sentence",
    "outpost_terminal::outpost terminal: every exit lands in the same place::EXIT IS IDEMPOTENT, because the two directions have to be one door",
    "outpost_terminal::outpost terminal: every exit lands in the same place::NO TRANSPORT IS A STATE, NOT A CRASH",
    "outpost_terminal::outpost terminal: every exit lands in the same place::all eight reasons produce the same terminal state, and each is recorded by name",
    "outpost_terminal::outpost terminal: every exit lands in the same place::an exited terminal sends nothing, and re-engaging is safe",
    "outpost_terminal::outpost terminal: the screen itself::EVERY CONTROL NEEDS ONLY ACTIVATION — there is not a drag on the terminal",
    "outpost_terminal::outpost terminal: the screen itself::THE CONTENT MODULE IS ENGINE-FREE, which is what lets two hosts share it",
    "outpost_terminal::outpost terminal: the screen itself::it declares the walk-up contract rather than leaving each host to derive it",
    "outpost_terminal::outpost terminal: the screen itself::it holds its own canvas at every text preference the player can choose",
    "outpost_terminal::outpost terminal: the screen itself::its canvas is declared once and the aspect is a real console's",
    "world_substrate::REUSE-88: the retired tuple order stays retired::every migrated file builds on the shared substrate rather than by hand",
    "world_substrate::REUSE-88: the retired tuple order stays retired::no spec returns the swapped order any more",
    "world_substrate::REUSE-88: the retired tuple order stays retired::the count of hand-rolled presenter builders only ever falls (R12 trigger)",
    "world_substrate::the headless world substrate (REUSE-88)::builds the six pieces, viewport first, one presenter per adapter",
    "world_substrate::the headless world substrate (REUSE-88)::named facts land on the environment, and `env` takes the ones with no name",
    "world_substrate::the headless world substrate (REUSE-88)::press is both edges, so the same key twice is two activations",
    "world_substrate::the headless world substrate (REUSE-88)::settle is N frames of clock AND solve, and never zero of them",
    "world_substrate::the headless world substrate (REUSE-88)::the default viewport is a phone portrait, and every named fact is optional",
]

SIPWORKS_CASES = [
    "reference/sipworks_spec::Sipworks nav — every placement is gamepad-traversable (enter, through, away, action)::bottom tabs (phone portrait)",
    "reference/sipworks_spec::Sipworks nav — every placement is gamepad-traversable (enter, through, away, action)::every structural number takes the ten-foot factor, not just the one with a helper",
    "reference/sipworks_spec::Sipworks nav — every placement is gamepad-traversable (enter, through, away, action)::inline bottom tabs (phone landscape)",
    "reference/sipworks_spec::Sipworks nav — every placement is gamepad-traversable (enter, through, away, action)::sidebar (pointer desktop)",
    "reference/sipworks_spec::Sipworks nav — every placement is gamepad-traversable (enter, through, away, action)::top tabs, driven as a PAD drives them: DPad across, ButtonA to act, DPad away",
    "reference/sipworks_spec::Sipworks reference proof — module contract and first mount::every player-facing string comes from the locale table (no key is missing)",
    "reference/sipworks_spec::Sipworks reference proof — module contract and first mount::exposes the scenario build contract",
    "reference/sipworks_spec::Sipworks reference proof — module contract and first mount::mounts headlessly with no core error and the whole menu visible",
    "reference/sipworks_spec::Sipworks §10 — the Blend Book unlock and the recipe view::locked rows are ABSENT until the purchase confirms, then they enter the list",
    "reference/sipworks_spec::Sipworks §10 — the Blend Book unlock and the recipe view::no buy button is mounted while the price is still loading",
    "reference/sipworks_spec::Sipworks §10 — the Blend Book unlock and the recipe view::the batch stepper rescales every measured quantity, and the checks are session-local",
    "reference/sipworks_spec::Sipworks §11 — the compact entry flow shares the same blueprints::BOTH entries reach the SAME row blueprint function",
    "reference/sipworks_spec::Sipworks §11 — the compact entry flow shares the same blueprints::boots straight into compact-link from an initial fact, deep-linked to the item",
    "reference/sipworks_spec::Sipworks §11 — the compact entry flow shares the same blueprints::enterFull restores the whole shell with the model intact",
    "reference/sipworks_spec::Sipworks §11 — the compact entry flow shares the same blueprints::the CTA is always pay-shaped in the compact entry, even at ten stamps",
    "reference/sipworks_spec::Sipworks §11 — the compact entry flow shares the same blueprints::the compact shell hides the nav, the sections and every favorite affordance",
    "reference/sipworks_spec::Sipworks §13 — localization: expansion, plurals, lists, measures::lists and measures are service calls, and the measure separator follows the locale",
    "reference/sipworks_spec::Sipworks §13 — localization: expansion, plurals, lists, measures::plural forms are selected in BOTH locales",
    "reference/sipworks_spec::Sipworks §13 — localization: expansion, plurals, lists, measures::the locale step reflows every mounted surface with no remount",
    "reference/sipworks_spec::Sipworks §13 — localization: expansion, plurals, lists, measures::the pseudo-locale expands every string by at least 1.4x and keeps placeholders",
    "reference/sipworks_spec::Sipworks §17 — reset determinism::reset returns a world to its seeded start, and replaying the loop reproduces the dump",
    "reference/sipworks_spec::Sipworks §17 — reset determinism::same seed + same steps => identical dump, in two independent worlds",
    "reference/sipworks_spec::Sipworks §17 — reset determinism::the seed decides the starting favorites, and a different seed differs",
    "reference/sipworks_spec::Sipworks §5 — the shell flips, and the model survives the flip::compact pushes the detail as its own surface; widening dismisses it and the pane keeps the selection",
    "reference/sipworks_spec::Sipworks §5 — the shell flips, and the model survives the flip::compact puts the TAB BAND BELOW the content and the accessory ABOVE the tabs",
    "reference/sipworks_spec::Sipworks §5 — the shell flips, and the model survives the flip::navPlacement gives every canvas its home: sidebar / bottom tabs / inline tabs / top tabs",
    "reference/sipworks_spec::Sipworks §5 — the shell flips, and the model survives the flip::no bottom-bar tab ellipsizes in the normal range (the short vocabulary is the point)",
    "reference/sipworks_spec::Sipworks §5 — the shell flips, and the model survives the flip::the flip is a re-solve: search text, selection and section all survive it",
    "reference/sipworks_spec::Sipworks §5 — the shell flips, and the model survives the flip::the top bar HUGS its tabs, centered — never full width (tablet/ten-foot shape)",
    "reference/sipworks_spec::Sipworks §6 — one row blueprint, search, suggestions, favorites::search matches a title OR a botanical name, and never the filler",
    "reference/sipworks_spec::Sipworks §6 — one row blueprint, search, suggestions, favorites::suggestions are botanical names, exclude the filler and the exact match, and cap at six",
    "reference/sipworks_spec::Sipworks §6 — one row blueprint, search, suggestions, favorites::the query is shared across sections",
    "reference/sipworks_spec::Sipworks §6 — one row blueprint, search, suggestions, favorites::the row heart is a real control on the shared favorites signal",
    "reference/sipworks_spec::Sipworks §6 — one row blueprint, search, suggestions, favorites::unfavoriting every blend reaches the empty state, and Browse returns to the menu",
    "reference/sipworks_spec::Sipworks §7 — the adaptive header, the tiles, and the facts flip::Cancel on the facts face flips to the front first; a second Cancel dismisses",
    "reference/sipworks_spec::Sipworks §7 — the adaptive header, the tiles, and the facts flip::a tile opens the botanical card, whose facts are scaled to THIS blend's measure",
    "reference/sipworks_spec::Sipworks §7 — the adaptive header, the tiles, and the facts flip::the flip swaps faces at the midpoint and only the visible face is mounted",
    "reference/sipworks_spec::Sipworks §7 — the adaptive header, the tiles, and the facts flip::the wide header candidate wins wide and loses on a phone",
    "reference/sipworks_spec::Sipworks §8 — the order flow: guard, rejection, confirmation, ready::the CTA runs idle -> pending -> rejected, shows a toast, and returns to idle",
    "reference/sipworks_spec::Sipworks §8 — the order flow: guard, rejection, confirmation, ready::the guard shows a reason, presents an alert on Activate, and never starts an order",
    "reference/sipworks_spec::Sipworks §8 — the order flow: guard, rejection, confirmation, ready::the second order confirms, presents Order-Placed, and the disc flips at t+4s",
    "reference/sipworks_spec::Sipworks §9 — Steam Stamps: accrual, the once-per-visit pop, redemption::at ten stamps the CTA is the redeem verb, and redeeming debits a flat ten",
    "reference/sipworks_spec::Sipworks §9 — Steam Stamps: accrual, the once-per-visit pop, redemption::one stamp per confirmed order, and a rejected order earns nothing",
    "reference/sipworks_spec::Sipworks §9 — Steam Stamps: accrual, the once-per-visit pop, redemption::the plural caption selects other / one / zero across the threshold",
    "reference/sipworks_spec::Sipworks §9 — Steam Stamps: accrual, the once-per-visit pop, redemption::the pop plays once per visit and the card is static on return",
    "reference/sipworks_spec::Sipworks — backdrop-finding sweep (task POP)::every section, the blend detail, a botanical tile and the order/rewards overlays are clean",
    "reference/sipworks_spec::Sipworks — reduced motion, themes, and reachability::...and on a COMPACT shape the same tab is a real destination",
    "reference/sipworks_spec::Sipworks — reduced motion, themes, and reachability::Cancel dismisses the compact detail and returns to the shell",
    "reference/sipworks_spec::Sipworks — reduced motion, themes, and reachability::build, drive and dispose are registry-neutral",
    "reference/sipworks_spec::Sipworks — reduced motion, themes, and reachability::every verb in the loop is a real focusable, on every input class",
    "reference/sipworks_spec::Sipworks — reduced motion, themes, and reachability::mounts under BOTH reference theme packages with no source edit",
    "reference/sipworks_spec::Sipworks — reduced motion, themes, and reachability::reduced motion fires the same events with no travel",
    "reference/sipworks_spec::Sipworks — reduced motion, themes, and reachability::the Steam Stamps tab PRESENTS the rewards card on a wide screen — it is not a destination",
    "reference/sipworks_spec::Sipworks — reduced motion, themes, and reachability::the five-view sweep is diagnostic-clean with a live scrollbar (matrix pin)",
    "reference/sipworks_spec::Sipworks — the declaration does not leak into the rest of the suite::retires its app namespace",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::desktop / en / preferred-text +0: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::desktop / en / preferred-text +14: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::desktop / xa / preferred-text +0: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::desktop / xa / preferred-text +14: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::phone-landscape / en / preferred-text +0: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::phone-landscape / en / preferred-text +14: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::phone-landscape / xa / preferred-text +0: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::phone-landscape / xa / preferred-text +14: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::phone-portrait / en / preferred-text +0: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::phone-portrait / en / preferred-text +14: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::phone-portrait / xa / preferred-text +0: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::phone-portrait / xa / preferred-text +14: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::tablet / en / preferred-text +0: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::tablet / en / preferred-text +14: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::tablet / xa / preferred-text +0: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::tablet / xa / preferred-text +14: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::ten-foot / en / preferred-text +0: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::ten-foot / en / preferred-text +14: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::ten-foot / xa / preferred-text +0: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the five-view sweep the solver itself signs off::ten-foot / xa / preferred-text +14: no solver diagnostics",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::'Serve another customer' returns EVERY observable to the seeded start",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::'What this shows' is collapsed by default and comes AFTER the play task",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::a refused order explains itself, keeps every stamp, and the retry is the same verb",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::on a landscape phone the strip yields and the CARD still carries the whole task",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::one accepted order takes the last stamp and the task becomes the free pour",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::redeeming the free pour ends in an unmistakable completion state with one reset",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::the compact-link entry carries NO task: there is no rewards context to finish it in",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::the named first action opens the blend it names, through the row's own path",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::the seeded start is ONE stamp short, and the opening screen says so",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::the strip costs ONE line box at every preference and in both locales",
    "reference/sipworks_spec::Sipworks — the played task: seeded start, the loop, and the reset::the task is placed ON the app: the catalogue and every destination survive it",
    "reference/sipworks_spec::Sipworks — the player surface names no stage, proof or ledger::no locale string a player can read carries test vocabulary",
    "reference/sipworks_spec::Sipworks — the player surface names no stage, proof or ledger::the module title is the place's name and nothing else",
    "reference/sipworks_spec::Sipworks — the standalone place and the showcase scenario import one module::exactly one directory on disk IS this app",
    "reference/sipworks_spec::Sipworks — the standalone place and the showcase scenario import one module::the scenario resolves the reference module and forks nothing",
    "reference/sipworks_spec::Sipworks — the standalone place and the showcase scenario import one module::the standalone place maps the same two folders the gallery does",
]

GLADE_CASES = [
    "reference/glade_spec::Glade S1: the overview grid (spec §7)::a visit suggestion fills the filter with that glade's name",
    "reference/glade_spec::Glade S1: the overview grid (spec §7)::mounts one card per seeded glade, in creation order",
    "reference/glade_spec::Glade S1: the overview grid (spec §7)::search filters case-insensitively and says so when nothing matches",
    "reference/glade_spec::Glade S1: the overview grid (spec §7)::shows all three supply states on the first frame — full, low and empty",
    "reference/glade_spec::Glade S1: the overview grid (spec §7)::the charm offer card is present while the tier is none and leaves on Dismiss",
    "reference/glade_spec::Glade S1: the overview grid (spec §7)::the favourite star is a SIBLING of the card, not inside its activation surface",
    "reference/glade_spec::Glade S2: the detail, in both of its hosts (spec §8)::a glade with no seeded visits shows the empty state, and one with visits lists them",
    "reference/glade_spec::Glade S2: the detail, in both of its hosts (spec §8)::compact presents the same body as a modal with a Back button",
    "reference/glade_spec::Glade S2: the detail, in both of its hosts (spec §8)::regular and wide mount the detail in the shell's own lane",
    "reference/glade_spec::Glade S2: the detail, in both of its hosts (spec §8)::the dew row is an instant refill: no confirmation, a commit event and a keyed toast",
    "reference/glade_spec::Glade S2: the detail, in both of its hosts (spec §8)::the low and empty chips are FORM, not a second hue: same ring tint in every state",
    "reference/glade_spec::Glade S3/S4: the purchase command's four phases (spec §9)::a premium nectar with nothing in the satchel opens the shop instead of using one",
    "reference/glade_spec::Glade S3/S4: the purchase command's four phases (spec §9)::a standard nectar assigns and refills in one act",
    "reference/glade_spec::Glade S3/S4: the purchase command's four phases (spec §9)::every declared rejection reason has player-facing copy, including the fallback",
    "reference/glade_spec::Glade S3/S4: the purchase command's four phases (spec §9)::idle → pending → confirmed: the button says Confirming…, then the count counts up",
    "reference/glade_spec::Glade S3/S4: the purchase command's four phases (spec §9)::premium with stock offers Use 1 and decrements the satchel; standard offers Choose",
    "reference/glade_spec::Glade S3/S4: the purchase command's four phases (spec §9)::the price is a service string the UI never composes",
    "reference/glade_spec::Glade S3/S4: the purchase command's four phases (spec §9)::the second attempt is the scripted `declined` rejection, with its copy under the card",
    "reference/glade_spec::Glade S3/S4: the purchase command's four phases (spec §9)::while a purchase is pending, the picker's card for that nectar refuses to pretend",
    "reference/glade_spec::Glade S5: the Keeper's Charm and its upgrade-only mode (spec §10)::Lumen drops the Frostwisp gate AND opens its early arrival window",
    "reference/glade_spec::Glade S5: the Keeper's Charm and its upgrade-only mode (spec §10)::a tier at or below the one held can never be sold again, whatever the fixture says next",
    "reference/glade_spec::Glade S5: the Keeper's Charm and its upgrade-only mode (spec §10)::buying a tier removes it from the offer and toasts the new standing",
    "reference/glade_spec::Glade S5: the Keeper's Charm and its upgrade-only mode (spec §10)::the offer card leaves S1 the moment a tier is held",
    "reference/glade_spec::Glade S5: the Keeper's Charm and its upgrade-only mode (spec §10)::the scripted `owned` rejection shows its own copy and the retry then confirms",
    "reference/glade_spec::Glade S6/S7: wisp info, restore, the edit form and Fresh Start (spec §10)::Fresh Start asks first, keeps the world on Keep, and reseeds it on Start over",
    "reference/glade_spec::Glade S6/S7: wisp info, restore, the edit form and Fresh Start (spec §10)::a visitor row opens the wisp modal, which offers the charm while gated",
    "reference/glade_spec::Glade S6/S7: wisp info, restore, the edit form and Fresh Start (spec §10)::restore runs the same three-phase command and toasts on confirm",
    "reference/glade_spec::Glade S6/S7: wisp info, restore, the edit form and Fresh Start (spec §10)::the edit form commits on Done and discards on Cancel",
    "reference/glade_spec::Glade S6/S7: wisp info, restore, the edit form and Fresh Start (spec §10)::the wisp modal states when and where a species was last seen",
    "reference/glade_spec::Glade detail — the locale x width x selection sweep the matrix pin could not see::an OPEN detail is diagnostic-clean in both locales at every canonical width",
    "reference/glade_spec::Glade nav — every placement is traversable (enter, through, away, action)::bottom tabs (phone portrait)",
    "reference/glade_spec::Glade nav — every placement is traversable (enter, through, away, action)::inline bottom tabs (phone landscape)",
    "reference/glade_spec::Glade nav — every placement is traversable (enter, through, away, action)::sidebar (pointer desktop)",
    "reference/glade_spec::Glade nav — every placement is traversable (enter, through, away, action)::top tabs, driven as a PAD drives them: DPad to the bar, across it, ButtonA, DPad away",
    "reference/glade_spec::Glade reference proof — module contract::exposes the scenario build contract",
    "reference/glade_spec::Glade reference proof — module contract::mounts headlessly through the public presenter with no core error",
    "reference/glade_spec::Glade reference proof — module contract::publishes its spec substitutions in the report rather than only in comments",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::'Prepare again' returns EVERY observable to the seeded start",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::'What this shows' is collapsed by default and comes AFTER the play task",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::either order finishes it: nectar first leaves the DEW row as the one thing left",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::on a landscape phone the strip yields and the CARD still carries the whole task",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::the clock can take a row back, and the task SAYS SO and stays finishable",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::the completion state is unmistakable, says what was accomplished, and offers ONE reset",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::the named first action opens the named glade, and each act ticks exactly its own row",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::the seeded start has BOTH rows undone, and the opening screen says what to do",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::the strip costs ONE line box at every preference and in both locales",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::the task is placed ON the app: every glade, section and browse verb survives it",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::the task names a glade, a wisp and a STANDARD nectar, so the shop is never on the path",
    "reference/glade_spec::Glade — the played task: seeded start, both orders, depletion, and the reset::the wisp ARRIVES when the glade is ready — not when it is merely opened",
    "reference/glade_spec::Glade — the player surface names no stage, proof or ledger::no locale string a player can read carries test vocabulary",
    "reference/glade_spec::Glade — the standalone place and the showcase scenario import one module::exactly one directory on disk IS this app",
    "reference/glade_spec::Glade — the standalone place and the showcase scenario import one module::the scenario resolves the reference module and forks nothing",
    "reference/glade_spec::Glade — the standalone place and the showcase scenario import one module::the standalone place maps the same two folders the gallery does",
    "reference/glade_spec::Glade: adaptation, one tree (spec §4)::a live resize moves the nav between homes and the world survives the move",
    "reference/glade_spec::Glade: adaptation, one tree (spec §4)::compact puts the TAB BAND BELOW the content, never over it",
    "reference/glade_spec::Glade: adaptation, one tree (spec §4)::navPlacement gives every canvas its home: sidebar / bottom tabs / inline tabs / top tabs",
    "reference/glade_spec::Glade: adaptation, one tree (spec §4)::no VISIBLE bottom tab is cut off in the normal text range",
    "reference/glade_spec::Glade: adaptation, one tree (spec §4)::the detail panes still adapt by MEASUREMENT: beside, then folded under",
    "reference/glade_spec::Glade: adaptation, one tree (spec §4)::the four sections are reachable from the nav in every home",
    "reference/glade_spec::Glade: adaptation, one tree (spec §4)::the terse vocabulary is REAL: the thumb-zone band reads a different word than the rail",
    "reference/glade_spec::Glade: adaptation, one tree (spec §4)::the top bar HUGS its tabs, centered — never full width (tablet / ten-foot shape)",
    "reference/glade_spec::Glade: determinism — same seed, same steps, same dump::Fresh Start returns a played world to its opening dump, byte for byte",
    "reference/glade_spec::Glade: determinism — same seed, same steps, same dump::the dump is stable across repeated reads with nothing changed in between",
    "reference/glade_spec::Glade: determinism — same seed, same steps, same dump::two independent worlds driven identically produce identical dumps",
    "reference/glade_spec::Glade: focus and reachability (spec §4, §14)::every modal can reach its own dismissal control from its focus map",
    "reference/glade_spec::Glade: focus and reachability (spec §4, §14)::focus order follows the nav's PLACEMENT: a leading rail leads the ring, a bottom band trails it",
    "reference/glade_spec::Glade: focus and reachability (spec §4, §14)::the base surface opens on the first glade card, not on the search field",
    "reference/glade_spec::Glade: focus and reachability (spec §4, §14)::the charm sheet opens on the recommended tier, and never on a card that is gone",
    "reference/glade_spec::Glade: focus and reachability (spec §4, §14)::the linear and directional readings cover the same nodes",
    "reference/glade_spec::Glade: focus and reachability (spec §4, §14)::the picker opens on the first premium card's action button",
    "reference/glade_spec::Glade: localization and the expansion locale (spec §13)::a locale swap relabels the live tree without a remount",
    "reference/glade_spec::Glade: localization and the expansion locale (spec §13)::an unknown locale falls back rather than blanking the screen",
    "reference/glade_spec::Glade: localization and the expansion locale (spec §13)::every key exists in both locales and `xa` expands by exactly 1.4×",
    "reference/glade_spec::Glade: localization and the expansion locale (spec §13)::expansion never eats a placeholder",
    "reference/glade_spec::Glade: localization and the expansion locale (spec §13)::remaining and relative times are proof-owned and single-unit",
    "reference/glade_spec::Glade: motion (spec §11)::reduced motion places the same states and fires the same events",
    "reference/glade_spec::Glade: motion (spec §11)::the ring's painted arc chases the level and lands on it",
    "reference/glade_spec::Glade: motion (spec §11)::the wisp fly-in runs once per visit and completes",
    "reference/glade_spec::Glade: supply drain, low and empty (spec §1, §6)::a refill stamps the clock, restores the level, and the ring drains again",
    "reference/glade_spec::Glade: supply drain, low and empty (spec §1, §6)::dew uses its own constants, and the two never share a threshold",
    "reference/glade_spec::Glade: supply drain, low and empty (spec §1, §6)::nectar crosses low at 7.5 minutes and empty at 9, on the injected clock alone",
    "reference/glade_spec::Glade: the responsibility ledger's forbidden list::no device-name or platform-name branch: facts and size classes only",
    "reference/glade_spec::Glade: the responsibility ledger's forbidden list::no engine reach-around: no Instance, no service, no input listener, no adapter write",
    "reference/glade_spec::Glade: the responsibility ledger's forbidden list::no raw colour reaches a role's place: identity hues ride the declared tint form",
    "reference/glade_spec::Glade: the responsibility ledger's forbidden list::no wall clock and no random anywhere in the proof",
    "reference/glade_spec::Glade: the responsibility ledger's forbidden list::scans the whole proof, and there is a whole proof to scan",
    "reference/glade_spec::Glade: the responsibility ledger's forbidden list::the bite is real: the scanner sees the patterns it bans when they are present",
    "reference/glade_spec::Glade: the scenario surface::Flora is browse-only: cards with a name and a species line, and no modal",
    "reference/glade_spec::Glade: the scenario surface::every step the scenario runner exposes is callable and answers something",
    "reference/glade_spec::Glade: the scenario surface::the five-view sweep is diagnostic-clean with a live scrollbar (matrix pin)",
    "reference/glade_spec::Glade: the scenario surface::the shop's hero card is the declared best value, with its own chip",
    "reference/glade_spec::Glade: the scenario surface::two fresh builds are identical (reset determinism) and dispose cleanly",
    "reference/glade_spec::Glade: the stage axes it can answer headlessly (RA-M3/M4/M5)::a theme-package swap re-solves the same tree — no remount, no source edit",
    "reference/glade_spec::Glade: the stage axes it can answer headlessly (RA-M3/M4/M5)::every preferred-text step re-solves without an error or a lost selection",
    "reference/glade_spec::Glade: the stage axes it can answer headlessly (RA-M3/M4/M5)::the expansion locale reflows the whole loop with no error and no lost state",
    "reference/glade_spec::Glade: the stray corner stroke and the circle doctrine (task PAINT, director items 11/12)::item 11 fix round 1: a plain surface no longer bundles chrome suppression with interaction suppression (fallback)",
    "reference/glade_spec::Glade: the stray corner stroke and the circle doctrine (task PAINT, director items 11/12)::item 11 fix round 1: a plain surface no longer bundles chrome suppression with interaction suppression (native)",
    "reference/glade_spec::Glade: the stray corner stroke and the circle doctrine (task PAINT, director items 11/12)::item 11 fix round 1: the press-dip and the hover/pressed fill are the mechanism this restores — both gate on exactly the flag the branches above now leave false for `plain`",
    "reference/glade_spec::Glade: the stray corner stroke and the circle doctrine (task PAINT, director items 11/12)::item 11: the card's activation Button classifies to NO chrome slot at all — surface = plain",
    "reference/glade_spec::Glade: the stray corner stroke and the circle doctrine (task PAINT, director items 11/12)::item 12: the dew ring's identity dot is CENTRED, not pinned to the top-left corner",
    "reference/glade_spec::Glade: the stray corner stroke and the circle doctrine (task PAINT, director items 11/12)::item 12: the nectar ring's identity mark (the Jar swap) is centred the same way",
    "reference/glade_spec::Glade: the stray corner stroke and the circle doctrine (task PAINT, director items 11/12)::item 12: the supply ring is a TRUE 1:1 box via shape = circle, byte-identical geometry to before",
    "reference/glade_spec::Glade: the stray corner stroke and the circle doctrine (task PAINT, director items 11/12)::item 12: whatisthis.png IS the deliberate glance plate, not a leaked mount — same rings, same fix",
    "reference/glade_spec::Glade: toasts (spec §12)::a refill toast is keyed per glade, so the same subject never doubles up",
    "reference/glade_spec::Glade: toasts (spec §12)::nothing in the loop depends on reading a toast: the state is visible in place",
    "reference/glade_spec::Glade: toasts (spec §12)::two different glades are two different subjects",
]

PLACEMENT_CASES = [
    "placement_audit::§2.1 the FOUR props this same phase shipped are in the watched set::`gridSpan` is reported under every parent that is not a GridRow",
    "placement_audit::§2.1 the FOUR props this same phase shipped are in the watched set::`layoutPriority` is reported under every parent that is not a stack, and still tiers under one",
    "placement_audit::§2.1 the FOUR props this same phase shipped are in the watched set::`lineAlign` is reported under every parent that is not a stack",
    "placement_audit::§2.1 the FOUR props this same phase shipped are in the watched set::`shrinkWeight` is reported under every parent that is not a stack, and still shrinks under one",
    "placement_audit::§2.1 the FOUR props this same phase shipped are in the watched set::the shrink pair's message names the reason AND the way out",
    "placement_audit::§2.1 the blank cells: every prop is authorable everywhere, so every parent is policed::a UI.Region refuses every placement prop at CONSTRUCTION — the schema closes that cell too",
    "placement_audit::§2.1 the blank cells: every prop is authorable everywhere, so every parent is policed::under a Region (its chosen form): ALL NINE are inert",
    "placement_audit::§2.1 the blank cells: every prop is authorable everywhere, so every parent is policed::under a ScrollView: `anchor`, both aligns, `lineAlign` and `gridSpan` are inert",
    "placement_audit::§2.1 the blank cells: every prop is authorable everywhere, so every parent is policed::under a ViewThatFits candidate: ALL NINE are inert — a candidate is placed by rank",
    "placement_audit::§2.1 the blank cells: every prop is authorable everywhere, so every parent is policed::under a ZStack: everything but the two aligns is inert",
    "placement_audit::§2.1 the blank cells: every prop is authorable everywhere, so every parent is policed::under a flow Grid: `anchor`, both offsets, `lineAlign` and `gridSpan` are inert",
    "placement_audit::§2.1 the blank cells: every prop is authorable everywhere, so every parent is policed::under a stack: everything but `lineAlign` and the shrink pair is inert, on BOTH axes",
    "placement_audit::§2.1 the blank cells: every prop is authorable everywhere, so every parent is policed::under an Anchor: the two aligns and `lineAlign` and `gridSpan` are inert; the three it reads are not",
    "placement_audit::§2.1 the hiddenDepth gate::a losing ViewThatFits candidate does not shout about its own children",
    "placement_audit::§2.1 the honoured cell is SILENT — a false positive here un-ships a screen::a ZStack's own alignH/alignV are the CONTAINER's default, never a placement request",
    "placement_audit::§2.1 the honoured cell is SILENT — a false positive here un-ships a screen::every honoured cell of the §2.1 table is silent",
    "placement_audit::§2.1 the inert cell reports, and nothing moved::`alignH` under a ViewThatFits candidate: reported (the live Rascal Rally shape)",
    "placement_audit::§2.1 the inert cell reports, and nothing moved::`alignH`/`alignV` under a VStack: reported, and `lineAlign` is the spelling that DOES move it",
    "placement_audit::§2.1 the inert cell reports, and nothing moved::`anchor` under a ZStack: reported, and the child is not placed by corner",
    "placement_audit::§2.1 the inert cell reports, and nothing moved::`anchor`/`offsetX`/`offsetY` on an Anchor under a Screen: reported (the live row-actions menu shape)",
    "placement_audit::§2.1 the inert cell reports, and nothing moved::`lineAlign` under a ZStack, and `gridSpan` outside a GridRow: both reported",
    "placement_audit::§2.1 the inert cell reports, and nothing moved::`offsetX`/`offsetY` under an HStack: reported as a pair, and the child does not shift",
    "placement_audit::§2.1 the inert cell reports, and nothing moved::a UI.GridRow refuses every placement prop at CONSTRUCTION — the schema closes that cell",
    "placement_audit::§2.1 the message names the REASON and the way out::`alignH` under an HStack points at lineAlign and says why nothing moved",
    "placement_audit::§2.1 the message names the REASON and the way out::`anchor` under a ZStack points at alignH/alignV, not at UI.Anchor",
    "placement_audit::§2.1 the message names the REASON and the way out::`offsetX` under a ZStack points at UI.Anchor",
    "placement_audit::§2.1 tier 2: the children a construction-time check cannot see::a UI.ForEach row is audited against the real parent kind",
    "placement_audit::§2.1 tier 2: the children a construction-time check cannot see::a UI.When child is audited against the parent it SPLICES into, not against the When",
]

WARDROBE_CASES = [
    "reference/wardrobe_spec::Wardrobe proof — filters, sections, locale, determinism::owned-only shrinks the catalog; price sort reorders; reset restores",
    "reference/wardrobe_spec::Wardrobe proof — filters, sections, locale, determinism::section stubs are honest and the worn set survives leaving and returning",
    "reference/wardrobe_spec::Wardrobe proof — filters, sections, locale, determinism::the locale swap reaches the BuyBar copy live",
    "reference/wardrobe_spec::Wardrobe proof — filters, sections, locale, determinism::the locale swap reaches the SECTION PICKER's option labels too",
    "reference/wardrobe_spec::Wardrobe proof — filters, sections, locale, determinism::two fresh builds are identical (reset determinism) and dispose cleanly",
    "reference/wardrobe_spec::Wardrobe proof — mount, stage seam, arrangement (RA-P5)::REDUCED MOTION STOPS THE TURNTABLE — and motion allowed still turns it",
    "reference/wardrobe_spec::Wardrobe proof — mount, stage seam, arrangement (RA-P5)::an orbit step drives a new camera write through the public host",
    "reference/wardrobe_spec::Wardrobe proof — mount, stage seam, arrangement (RA-P5)::mounts the boutique with categories, grids, pane, and no core error",
    "reference/wardrobe_spec::Wardrobe proof — mount, stage seam, arrangement (RA-P5)::the stage host is live headlessly (recording stub): lighting + camera recorded, fallback closed",
    "reference/wardrobe_spec::Wardrobe proof — mount, stage seam, arrangement (RA-P5)::wide solves the split arrangement; a phone box solves stacked — and worn state survives the flip",
    "reference/wardrobe_spec::Wardrobe proof — the purchase lifecycle::insufficient Sparks rejects with a visible reason; the wallet never moves; retry stays allowed",
    "reference/wardrobe_spec::Wardrobe proof — the purchase lifecycle::sold-out rejects once, then a retry confirms: balance debits, chip flips to Owned+Wearing, modal dismisses, BuyBar leaves",
    "reference/wardrobe_spec::Wardrobe proof — try-on and history::activating a card equips it: Wearing chip, selected state, rig re-dressed; activating again unequips",
    "reference/wardrobe_spec::Wardrobe proof — try-on and history::trying on an unowned item raises the BuyBar; an owned one does not",
    "reference/wardrobe_spec::Wardrobe proof — try-on and history::undo/redo walk the equip history and disable at the stack ends",
    "reference/wardrobe_spec::Wardrobe — Picked-for-you cards fill their lane and never overflow their card (item 15)::every Picked-for-you card is the same width, and the row tiles the grid exactly",
    "reference/wardrobe_spec::Wardrobe — Picked-for-you cards fill their lane and never overflow their card (item 15)::every Picked-for-you thumbnail is the SAME width — never a different width per card",
    "reference/wardrobe_spec::Wardrobe — Picked-for-you cards fill their lane and never overflow their card (item 15)::the catalog column claims the whole phone viewport — not just the grid's minColumnWidth floor",
    "reference/wardrobe_spec::Wardrobe — Picked-for-you cards fill their lane and never overflow their card (item 15)::the thumbnail never paints past its own Col — at the floor lane, not just a wide one",
    "reference/wardrobe_spec::Wardrobe — backdrop-finding sweep (task POP)::the purchase Confirm modal and the Refine filter modal are clean",
    "reference/wardrobe_spec::Wardrobe — the worn chips FLOW (parity round 3)::FIVE WORN PIECES SHARE ONE LINE, each at its own width — not five stacked lines",
    "reference/wardrobe_spec::Wardrobe — the worn chips FLOW (parity round 3)::IN A NARROW PANE THEY WRAP to a second line rather than paint past the plate",
]

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
    "distribution-readiness::fresh-clone-works": (
        {
            "shell": _clone_check(
                "ok = d['tier'] == 'full' and not failedRows and not failedProducers\n"
                "print(len(d['rows']), 'rows and', len(d['producers']), 'producers in a clone "
                "with no parent workspace;', len(failedRows), 'failing rows,', "
                "len(failedProducers), 'failing producers')\n"
                "sys.exit(0 if ok else 1)\n"
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--fresh-clone-works.json",
        },
        "a clone of this repository, in a directory with no parent workspace and an empty result "
        "store, ran the full tier end to end with no failing row and no failing producer -- read "
        "out of that run's own machine record, which is pinned by content hash. The clone was "
        "taken from the repository on disk and NOT fetched over the network, and the note beside "
        "the record says so",
        "artifacts/distribution-readiness/verification/public-clone.md",
    ),
    "distribution-readiness::example-places-rebuild-from-clone": (
        {
            "shell": _clone_check(
                "want = ['build_places', 'build_reference_places']\n"
                "bad = [k for k in want if producers.get(k) != 'PASS']\n"
                "print('place builders in the clone:', [producers.get(k) for k in want])\n"
                "sys.exit(1 if bad else 0)\n"
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--example-places-rebuild-from-clone.json",
        },
        "both place builders ran green inside that clone, so the example places rebuild from a "
        "checkout that carries nothing but the repository",
        None,
    ),
    "distribution-readiness::package-from-clone-matches": (
        {
            "shell": _clone_check(
                "bad = producers.get('package-verify') != 'PASS'\n"
                "print('package-verify in the clone:', producers.get('package-verify'))\n"
                "sys.exit(1 if bad else 0)\n"
            ),
            "receipt": "tools/lune/verify/evidence/distribution-readiness--package-from-clone-matches.json",
        },
        "the package channel's own verify -- build, tree inspection, purity and the packaged "
        "canary -- ran green inside that clone, against the model built there",
        None,
    ),
    # ---- Step 13.5: the verification-optimization rows ------------------------
    #   Their own artifacts are archived; these are the LIVING successors, and
    #   each is re-earned by a producer in this same run.
    "example-games-and-standalones::verification-mutations-bite": (
        {
            "producers": ["verify-selftest", "suite_cache_selftest", "check_manifest_integrity"],
            "receipt": "tools/lune/verify/evidence/example-games-and-standalones--verification-mutations-bite.json",
        },
        "targeted mutations still make the optimized system red: the result store's thirty-two "
        "refusals and the transcript cache's own broken-on-purpose guards run live, the graph "
        "audit reddens on a changed case id, and the recorded corpus is pinned by content hash",
        None,
    ),
    "example-games-and-standalones::verification-verdict-parity": (
        {
            "producers": ["check_manifest_integrity"],
            "shell": (
                'grep -q "went red on both paths" '
                "artifacts/distribution-readiness/verification/mutation-parity.md"
            ),
            "receipt": "tools/lune/verify/evidence/example-games-and-standalones--verification-verdict-parity.json",
        },
        "the old path and the new path return the same verdict, row by row -- the comparison this "
        "stage owed, taken by the workstream that replaced the old path, pinned by content hash "
        "and asserted by its own claim",
        None,
    ),
    "example-games-and-standalones::producer-runs-once-per-identity": (
        {"producers": ["verify-selftest"], "shell": _TRACE_CHECK},
        "each producer executes at most once per exact identity, recomputed here from the "
        "invocation trace rather than quoted from a document -- the trace is written every run, so "
        "it is read and never hashed",
        "artifacts/verify/invocation-trace.json",
    ),
    "example-games-and-standalones::headless-budget-twenty-minutes": (
        {"shell": _BUDGET_CHECK, "receipt": "tools/lune/verify/evidence/example-games-and-standalones--headless-budget-twenty-minutes.json"},
        "the deterministic headless work finishes inside twenty minutes, read from the LAST "
        "release run's own record; Studio, device, performance and external time are reported by "
        "class in the timings document beside it and never folded into that number",
        None,
    ),
    "example-games-and-standalones::verification-coverage-preserved": (
        {"producers": ["check_manifest_integrity"], "shell": _LEDGER_CHECK},
        "no coverage, assertion strength or negative control was removed for speed: the graph "
        "audit checks every case id and producer this run cites, and the coverage ledger's counts "
        "agree with the document rendered from them",
        "artifacts/distribution-readiness/verification/coverage-map.md",
    ),

    # ---- Step 13.5: the game loops -------------------------------------------
    "example-games-and-standalones::tile-game-crossword-loop": (
        {"resultIds": TILE_CASES, "receipt": "tools/lune/verify/evidence/example-games-and-standalones--tile-game-crossword-loop.json"},
        "the crossword's whole loop, by case id: the pure rules, the axis and connection laws, "
        "every perpendicular word a turn creates, the shared dictionary, the guaranteed opening, "
        "nine refusals in nine sentences, commit and undo and budget, both endings, determinism "
        "and teardown. Its design record is archived and pinned; the Studio play the original row "
        "also asked for predates this stage and is not re-taken here",
        None,
    ),
    "example-games-and-standalones::match3-motion-public-surface": (
        {
            "resultIds": MATCH3_CASES,
            "producers": ["check_boundary", "check_library_purity"],
            "receipt": "tools/lune/verify/evidence/example-games-and-standalones--match3-motion-public-surface.json",
        },
        "tile identity survives a move, the resolve sequence is visible IN ORDER, reduced motion "
        "changes the paint and nothing else, and the example builds no animation system of its "
        "own -- that last one asserted twice over, by its own case and by the boundary and purity "
        "checks that forbid an example reaching past the public surface",
        None,
    ),
    "example-games-and-standalones::sensory-demo-opens-useful": (
        {"resultIds": SENSORY_FEEDBACK_CASES, "receipt": "tools/lune/verify/evidence/example-games-and-standalones--sensory-demo-opens-useful.json"},
        "the declaration is ruled on at the call site, what reaches the bus is what was declared, "
        "and it survives the real presenter. The rendered-geometry half the original row asked "
        "for was a Studio capture; it predates this stage and is not re-taken here",
        None,
    ),
    "example-games-and-standalones::sensory-demo-four-comparisons": (
        {"resultIds": SENSORY_PROFILE_CASES, "receipt": "tools/lune/verify/evidence/example-games-and-standalones--sensory-demo-four-comparisons.json"},
        "the three shipped profiles pinned exactly, a partial merged over the defaults, the preset "
        "fallback with the limitation it carries, and the key that makes pooling possible -- all "
        "of it engine-free, which is the reason any of it is provable headlessly",
        None,
    ),
    "example-games-and-standalones::world-terminal-plays": (
        {"resultIds": TERMINAL_CASES, "receipt": "tools/lune/verify/evidence/example-games-and-standalones--world-terminal-plays.json"},
        "the terminal's whole path by case id -- engage, adjust, apply, success, reset, exit; "
        "every refusal and the exact sentence it uses; every refusal the server can make; and the "
        "headless world substrate under it. The played Studio session predates this stage",
        None,
    ),
    "example-games-and-standalones::world-terminal-guide-recipe": (
        {
            "producers": ["check_docs_cli", "check_links_cli"],
            "shell": (
                "grep -q '^#### .client.surface_target.' docs/reference/api.md && "
                "test -f docs/extending/new-render-target.md"
            ),
        },
        "the world render target is published where a reader can act on it: the surface target has "
        "its own reference entry and the render-target playbook is in the extending set, with the "
        "documentation drift check and the link checker both live",
        None,
    ),
    "example-games-and-standalones::sipworks-loop-complete": (
        {"resultIds": SIPWORKS_CASES, "receipt": "tools/lune/verify/evidence/example-games-and-standalones--sipworks-loop-complete.json"},
        "ninety-one cases: the shell flip, the row blueprint, the order flow, the stamps, the "
        "unlock, localization, the five-view sweep the solver signs off, reduced motion and "
        "reachability, gamepad traversal, the played task and its reset. Its design record is "
        "archived and pinned; the Studio play predates this stage",
        None,
    ),
    "example-games-and-standalones::glade-loop-complete": (
        {"resultIds": GLADE_CASES, "receipt": "tools/lune/verify/evidence/example-games-and-standalones--glade-loop-complete.json"},
        "a hundred and six cases: the overview grid, supply drain, the purchase command's four "
        "phases, the charm, the edit form, determinism, toasts, adaptation, focus, localization, "
        "motion, the responsibility ledger's forbidden list, and the played task. Same archived "
        "design record, same rule about the Studio play",
        None,
    ),

    # ---- Step 13.5: the manifest-driven places --------------------------------
    "example-games-and-standalones::one-manifest-drives-places": (
        {
            "producers": [
                "check_example_drift_cli",
                "check_registration_cli",
                "build_places",
                "build_reference_places",
            ]
        },
        "one declaration drives what ships: the drift checker reconciles the example set against "
        "what is registered, the registration checker refuses an unregistered surface, and both "
        "place builders build from it",
        None,
    ),
    "example-games-and-standalones::places-are-playable-not-fixtures": (
        {
            "resultIds": PLACEMENT_CASES,
            "producers": ["build_places", "build_reference_places"],
        },
        "the places build, and what they put on screen is policed rather than assumed: every "
        "authorable prop is watched in every parent, an inert cell reports itself, an honoured "
        "cell stays SILENT -- a false positive there would un-ship a screen -- and the message "
        "names the reason and the way out",
        None,
    ),
    "example-games-and-standalones::shared-theme-and-motion-chrome": (
        {
            "producers": ["check_theme_drift_cli", "build_themes", "check_elision_census"],
            "resultIds": [c for c in TILE_CASES if "in every theme" in c or "not a colour" in c],
        },
        "the shipped examples wear the same theme and motion chrome: theme drift is checked "
        "against the packages the builder produces, and the crossword proves the sweep bites -- "
        "every cell state paints a plate a player can see under every theme, and committed versus "
        "uncommitted is not a colour",
        None,
    ),
    "example-games-and-standalones::dead-example-audit": (
        {
            "resultIds": WARDROBE_CASES,
            "producers": ["check_example_drift_cli", "check_device_sweep-selftest"],
            "receipt": "tools/lune/verify/evidence/example-games-and-standalones--dead-example-audit.json",
        },
        "the retired example stays retired and stays proved: its cases still run as test evidence, "
        "the drift checker reconciles the live set against what is registered, and the inventory "
        "taken when it was retired is pinned by content hash",
        None,
    ),

    # ---- Step 13.5: the closing rows -----------------------------------------
    "example-games-and-standalones::rascalrally-consumer": (
        {"producers": ["rascalrally-suite"], "receipt": "tools/lune/verify/evidence/example-games-and-standalones--rascalrally-consumer.json"},
        "the consuming game's own suite runs green against this tree, and the consumer-impact "
        "ledger for the stage is pinned by content hash",
        None,
    ),
    "example-games-and-standalones::step-13-guards-hold": (
        {
            "producers": [
                "check_registration_cli",
                "check_surface_ledger",
                "check_source_size",
                "check_docs_cli",
                "check_prop_parity_cli",
                "check_theme_drift_cli",
            ]
        },
        "the guards the previous step installed still hold: registration, the surface ledger, the "
        "source cap, the documentation catalogue, property parity and theme drift -- each run in "
        "THIS run rather than recalled from the gate that installed it",
        None,
    ),
    "example-games-and-standalones::prior-gates-unregressed": (
        {"priorPhases": True},
        "every row of every earlier phase, re-evaluated from this same run rather than replayed",
        None,
    ),
    "example-games-and-standalones::suites-green-at-close": (
        {"producers": ["suite", "rascalrally-suite"]},
        "both suites are green at the tree this stage is judged at -- the library's own, and the "
        "consuming game's",
        None,
    ),
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
            "shell": _BUDGET_CHECK,
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
    "distribution-readiness::fresh-clone-works": (
        "deterministic",
        [("run-record", "artifacts/distribution-readiness/verification/public-clone-full-run.json", "tree"),
         ("note", "artifacts/distribution-readiness/verification/public-clone.md", "tree")],
        "the clone run's verbatim machine record, and the note that says what it is and is not",
    ),
    "distribution-readiness::example-places-rebuild-from-clone": (
        "deterministic",
        [("run-record", "artifacts/distribution-readiness/verification/public-clone-full-run.json", "tree")],
        "the same record, read for the two place builders",
    ),
    "distribution-readiness::package-from-clone-matches": (
        "deterministic",
        [("run-record", "artifacts/distribution-readiness/verification/public-clone-full-run.json", "tree")],
        "the same record, read for the package channel's verify",
    ),
    # ---- Step 13.5's archived stage record, pinned where a row leans on it ----
    "example-games-and-standalones::verification-mutations-bite": (
        "deterministic",
        [("mutation-corpus", "artifacts/distribution-readiness/verification/mutation-parity.md", "tree"),
         ("stage-plan", "artifacts/example-games-and-standalones/test-optimization/plan.md", "archive")],
        "the living mutation corpus, and the plan the stage wrote for the one it owed",
    ),
    "example-games-and-standalones::verification-verdict-parity": (
        "deterministic",
        [("parity", "artifacts/distribution-readiness/verification/mutation-parity.md", "tree")],
        "the old-path/new-path verdict comparison",
    ),
    "example-games-and-standalones::headless-budget-twenty-minutes": (
        "deterministic",
        [("timings", "artifacts/distribution-readiness/verification/timings.md", "tree"),
         ("stage-baseline", "artifacts/example-games-and-standalones/test-optimization/baseline.md", "archive")],
        "the living timings against the budget, and the stage's own before-measurement",
    ),
    "example-games-and-standalones::tile-game-crossword-loop": (
        "external",
        [("design", "artifacts/example-games-and-standalones/design/crossword-tile-game.md", "archive"),
         ("acceptance", "artifacts/example-games-and-standalones/acceptance-ledger.md", "archive")],
        "the crossword's design record and the stage's acceptance ledger, where the Studio play is recorded",
    ),
    "example-games-and-standalones::match3-motion-public-surface": (
        "external",
        [("design", "artifacts/example-games-and-standalones/design/match3-motion.md", "archive"),
         ("ownership", "artifacts/example-games-and-standalones/responsibility-ledger.md", "archive")],
        "the motion design record and the responsibility ledger that forbids an example-local animation system",
    ),
    "example-games-and-standalones::sensory-demo-opens-useful": (
        "external",
        [("design", "artifacts/example-games-and-standalones/design/sensory-demo.md", "archive")],
        "the sensory demo's design record, including the captures taken when it was built",
    ),
    "example-games-and-standalones::sensory-demo-four-comparisons": (
        "external",
        [("design", "artifacts/example-games-and-standalones/design/sensory-demo.md", "archive")],
        "the same record, read for the four-way comparison",
    ),
    "example-games-and-standalones::world-terminal-plays": (
        "external",
        [("design", "artifacts/example-games-and-standalones/design/outpost-power-terminal.md", "archive"),
         ("spike", "artifacts/example-games-and-standalones/spike/world-surface.md", "archive")],
        "the terminal's design record and the world-surface spike it was built on",
    ),
    "example-games-and-standalones::sipworks-loop-complete": (
        "external",
        [("design", "artifacts/example-games-and-standalones/design/sipworks-and-glade.md", "archive"),
         ("acceptance", "artifacts/example-games-and-standalones/acceptance-ledger.md", "archive")],
        "the two reference loops' design record and the stage's acceptance ledger",
    ),
    "example-games-and-standalones::glade-loop-complete": (
        "external",
        [("design", "artifacts/example-games-and-standalones/design/sipworks-and-glade.md", "archive"),
         ("acceptance", "artifacts/example-games-and-standalones/acceptance-ledger.md", "archive")],
        "the same record, read for the second loop",
    ),
    "example-games-and-standalones::dead-example-audit": (
        "external",
        [("inventory", "artifacts/example-games-and-standalones/wardrobe-inventory.md", "archive"),
         ("retirement", "artifacts/example-games-and-standalones/design/wardrobe-retirement.md", "archive")],
        "the inventory taken when the example was retired, and the retirement decision beside it",
    ),
    "example-games-and-standalones::rascalrally-consumer": (
        "deterministic",
        [("impact-ledger", "artifacts/distribution-readiness/rascalrally-consumer-impact.md", "tree")],
        "the consuming game's impact ledger",
    ),
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
#[[ EVERY ROW LEFT PENDING, AND WHETHER IT MAY BLOCK THE RUN.
#
#   `(why, releaseBlocking)`. The second half is a deliberate per-row ruling,
#   not a default: `graph.statePasses` treats a PENDING row as passing ONLY when
#   `releaseBlocking` is explicitly `false`, so a row nobody has ruled on keeps
#   failing the run.
#
#   FALSE means the row cannot be earned before the thing it is waiting for, and
#   that thing is gated on this run's own verdict -- the stage-closing pair each
#   pass only AFTER a release action that refuses to start unless the gate reads
#   PASS -- or it is a properly declared human procedure with its closing
#   procedure named, which is the same contract the device rows have carried
#   all along.
#
#   TRUE means the work is simply missing. Nothing external blocks it, somebody
#   has not done it, and the run should stay red until they do. ]]
STILL_PENDING = {
    "distribution-readiness::owner-packet-complete": (
        "the packet's final numbers, stamped at close -- it closes the stage, so it cannot be "
        "earned before the stage closes",
        False,
    ),
    "distribution-readiness::private-package-id-and-update-proof": (
        "an asset minted and updated, which is the owner's guarded release action -- and that "
        "action refuses to run unless this gate already reads PASS",
        False,
    ),
    "example-quality-pass::physical-and-human-rows": (
        "a human review packet at artifacts/example-quality-pass/review-packet.md -- a declared "
        "human row that names its own closing procedure, exactly as the device rows do",
        False,
    ),
    "example-games-and-standalones::fresh-phase-gate-review": (
        "an independent fresh-context reviewer that PLAYS the six touched loops and has its "
        "findings resolved. The four fresh-context exercises this stage ran do not cover that "
        "subject -- the red team read this workstream's verification graph, and the three fresh "
        "agents read the comparison guide, built a settings screen and extended the consumer "
        "example. None of them opened the crossword, the match-3 board, the sensory demo, the "
        "terminal, Sipworks or Glade. Nothing external blocks the dispatch, so this row keeps "
        "failing the run until it happens",
        True,
    ),
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
        spec = STILL_PENDING.get(row["id"])
        if spec is None:
            continue
        why, blocking = spec
        want = "%s: PENDING -- %s. %s Requirements: %s." % (
            row["name"],
            why,
            "It does not block the run." if not blocking else "It BLOCKS the run.",
            ", ".join(row["requirements"]) or "none",
        )
        if row.get("note") != want:
            row["note"] = want
        if row.get("releaseBlocking") != blocking:
            row["releaseBlocking"] = blocking
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

    #   THE STAMP MOVES ONLY WHEN THE GRAPH DOES, for the same reason the
    #   ledger's does: a maintainer that advertises idempotence and then reports
    #   a one-line diff on a run that moved nothing is teaching its readers to
    #   ignore its diffs.
    previous = json.load(open(GRAPH))
    stamp = graph.pop("maintainedAt", None)
    previous.pop("maintainedAt", None)
    if graph != previous:
        graph["maintainedAt"] = stamp
    else:
        graph["maintainedAt"] = json.load(open(GRAPH)).get("maintainedAt")
    if json.load(open(GRAPH)) != graph:
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
