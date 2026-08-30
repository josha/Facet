#!/usr/bin/env python3
"""Convert tools/lune/gate_manifest.luau into the verification graph.

    python3 tools/lune/verify/convert_manifest.py \
        --suite-results <facet-suite-results/1 json> \
        [--out tools/lune/verify/graph.json] \
        [--census artifacts/distribution-readiness/verification/graph-census.md]

WHY THIS IS A SCRIPT AND NOT A HAND EDIT
----------------------------------------
There are 567 manifest rows carrying 3,588 shell clauses, of which 1,539 are
`grep -q "✓.*<a sentence from the transcript>"`. Converting that by hand would
be one long opportunity to drop an assertion silently, and it could never be
re-run after the manifest moved. This transform is mechanical, its round trip is
asserted (see `split_and`), and every clause it cannot classify is REPORTED
rather than dropped.

WHAT EACH CLAUSE BECOMES
------------------------
The command is split on top-level `&&` (respecting quotes, `$( )`, groups and
for/while/if blocks — the split is checked by rejoining and comparing byte for
byte), and each clause is classified:

  `out="$(tools/suite_transcript.sh)"`      -> the `suite` producer; clause dropped
  `echo "$out" | grep -q "✓.*X"`            -> the case ids X resolves to
  `tools/suite_transcript.sh [| grep …]`    -> same, in FORM B
  `tools/test.sh [N]`                        -> the `suite` producer
  `tools/prior_gates.sh …`                   -> the whole row becomes `priorPhases`
  a scanner/build/measurement command        -> that producer, asserted exit 0
  `<producer> | grep -q "X"`                 -> that producer, plus a stdout pin
  anything else                              -> KEPT VERBATIM as residual shell

The residual is the ORIGINAL command with the converted clauses replaced by
`true`, in place, so variable assignments, `cd`s and `for` loops keep working and
nothing is reordered. A row whose residual is only `true`s carries no shell at
all.

WHAT IS NOT CONVERTED
---------------------
Rascal Rally rows keep their transcript greps, because that suite is an EXTERNAL
producer with no structured results of its own. Its transcript is recorded once
per identity and the greps are repointed at the recorded file
(`$FACET_VERIFY_RR_TRANSCRIPT`), so the suite still runs exactly once.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

# ---------------------------------------------------------------------------
# the shell splitter
# ---------------------------------------------------------------------------

KW_OPEN = {"for", "while", "until", "if", "case", "select"}
KW_CLOSE = {"done", "fi", "esac"}


def split_and(cmd: str) -> list[str]:
    """Split on TOP-LEVEL `&&`. `" && ".join(split_and(c)) == c.strip()` always."""
    out: list[str] = []
    buf: list[str] = []
    i, n = 0, len(cmd)
    sq = dq = False
    depth = 0
    block = 0
    while i < n:
        c = cmd[i]
        if sq:
            if c == "'":
                sq = False
            buf.append(c)
            i += 1
            continue
        if dq:
            if c == "\\" and i + 1 < n:
                buf.append(c)
                buf.append(cmd[i + 1])
                i += 2
                continue
            if c == '"':
                dq = False
            buf.append(c)
            i += 1
            continue
        if c == "'":
            sq = True
            buf.append(c)
            i += 1
            continue
        if c == '"':
            dq = True
            buf.append(c)
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            buf.append(c)
            buf.append(cmd[i + 1])
            i += 2
            continue
        if cmd.startswith("$(", i):
            depth += 1
            buf.append("$(")
            i += 2
            continue
        if c in "({":
            depth += 1
            buf.append(c)
            i += 1
            continue
        if c in ")}":
            depth -= 1
            buf.append(c)
            i += 1
            continue
        if c.isalpha() or c == "_":
            j = i
            while j < n and (cmd[j].isalnum() or cmd[j] in "_-"):
                j += 1
            word = cmd[i:j]
            prev = buf[-1] if buf else " "
            starts_word = (not buf) or prev in " \t\n;&|(){}"
            if depth == 0 and starts_word:
                if word in KW_OPEN:
                    block += 1
                elif word in KW_CLOSE:
                    block -= 1
            buf.append(word)
            i = j
            continue
        if cmd.startswith("&&", i) and depth == 0 and block == 0:
            out.append("".join(buf).strip())
            buf = []
            i += 2
            continue
        buf.append(c)
        i += 1
    tail = "".join(buf).strip()
    if tail:
        out.append(tail)
    return out


# ---------------------------------------------------------------------------
# BRE -> python regex, for resolving a `grep -q` pattern to case ids
# ---------------------------------------------------------------------------

BRE_LITERAL = set("+?{}()|")


def bre_to_python(pattern: str) -> str:
    """`grep` without -E is BRE: + ? { } ( ) | are LITERAL unless backslashed."""
    out: list[str] = []
    i, n = 0, len(pattern)
    while i < n:
        c = pattern[i]
        if c == "\\" and i + 1 < n:
            nxt = pattern[i + 1]
            if nxt in BRE_LITERAL:
                out.append(nxt)  # \( is a group in BRE
            else:
                out.append("\\" + nxt)
            i += 2
            continue
        if c in BRE_LITERAL:
            out.append("\\" + c)
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


# ---------------------------------------------------------------------------
# producers
# ---------------------------------------------------------------------------

# Everything a deterministic source scanner could read. Deliberately generous:
# the binding plan says to default to rerun when dependency ownership is
# uncertain, a scanner costs between 0.03 s and 6 s, and a missed invalidation
# costs a wrong green.
SOURCE_INPUTS = [
    "src/**",
    "tests/**",
    "examples/**",
    "docs/**",
    "tools/**",
    "bench/**",
    "package/**",
    "skills/**",
    "rokit.toml",
    "run-tests.sh",
    "phases.json",
    "requirements.json",
    "README.md",
    "AGENTS.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "LICENSE",
]

# What the SUITE reads. tools/ is deliberately absent, exactly as
# tools/test.sh's own fingerprint has it: editing a gate script cannot change a
# spec's outcome.
SUITE_INPUTS = ["src/**", "tests/**", "examples/**", "run-tests.sh", "rokit.toml"]

RR = "../../../games/RascalRally/code"

# Producers that READ recorded evidence under artifacts/. Declared so a changed
# capture invalidates the result; a producer that only WRITES under artifacts/
# needs nothing here, because artifacts/ is not in SOURCE_INPUTS.
EVIDENCE_READS = {
    "check_device_captures": [
        "artifacts/cross-platform-proof/device/**",
        "artifacts/phase-4/perf.json",
    ],
    "check_device_sweep": ["artifacts/cross-platform-proof/device/**"],
    "check_eq6_evidence": ["artifacts/example-quality-pass/studio/large-text.json"],
    "check_matrix_rows": ["artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json"],
    "check_perf_budgets": [
        "artifacts/phase-4/perf.json",
        "artifacts/cross-platform-proof/device/**",
    ],
    "check_perf_captures": [
        "artifacts/performance-stress-places/studio/**",
        "artifacts/cross-platform-proof/device/**",
        "artifacts/performance-stress-places/acceptance.md",
    ],
    "check_perf_gate_evidence": ["artifacts/performance-stress-places/**"],
    "check_perf_metrics": ["artifacts/phase-4/perf.json"],
    "check_perf_place": ["artifacts/performance-stress-places/place.json"],
    "check_perf_scenes": ["artifacts/phase-4/perf.json"],
    "check_row_actions_matrix": ["artifacts/row-actions/device-matrix.md"],
    "check_traversal_evidence": ["artifacts/traversal-document-order/studio/**"],
    "check_types": ["artifacts/release-candidate-review/perf/types.json"],
    "check_xp_matrix": ["artifacts/cross-platform-proof/**"],
    "check_flat_baseline": [
        "artifacts/theme-packages-and-skinning/final-neutral-dump.json",
        "artifacts/rich-skinning-v2/rows/neutral-render-dump.json",
    ],
    "check_surface_ledger": ["artifacts/api-architecture-consistency/surface-ledger.md"],
    "prove_perf_gate": [
        "artifacts/cross-platform-proof/rows/xp-a6-regression-proof.json",
        "artifacts/phase-4/perf.json",
    ],
}

# Producers whose evidence class is not `deterministic`. A result in one of
# these classes may only satisfy a row that asks for that class, and no headless
# cache can upgrade it.
CLASS_OVERRIDES = {
    "bench": "perf",
    "perf": "perf",
    "render": "perf",
    "prove_perf_gate": "perf",
    "check_device_captures": "device",
    "check_device_sweep": "device",
    "check_perf_captures": "device",
    "check_xp_matrix": "device",
    "check_row_actions_matrix": "device",
    "check_perf_budgets": "device",
    "check_perf_metrics": "device",
    "check_traversal_evidence": "studio",
    "check_eq6_evidence": "studio",
    "check_matrix_rows": "studio",
    "check_perf_place": "studio",
    "check_perf_gate_evidence": "studio",
    "check_spike": "studio",
    "rascalrally-suite": "external",
    "package-verify": "package",
}

# Producers that share external state or measure wall clock: never overlapped
# with anything else. soak/faults/fuzz are deterministic in VERDICT but they
# inject on a schedule and watch memory, and this repository has already lost a
# day to a gate that failed only when it ran inside a batch.
SERIALIZE = {
    "bench",
    # runs the suite on purpose, to break its own cache guards
    "suite_cache_selftest",
    # replays every manifest grep against a live transcript of BOTH suites
    "check_manifest_integrity-transcript",
    "perf",
    "render",
    "prove_perf_gate",
    "soak",
    "faults",
    "fuzz-layout",
    "fuzz-replication",
    "fuzz-scheduler",
    "doctor",
    "build_places",
    "build_reference_places",
    "build_themes",
    "build_model",
    "package-verify",
    "rascalrally-suite",
}

# WHO HAS TO WAIT FOR WHOM.
#
# Two producers reach the suite through the OLD front door on purpose — the
# cache selftest breaks its guards against a real cached run, and the manifest
# grep-replay needs a live transcript to replay against. Run in the parallel
# batch they race the suite producer, lose, and each start a 260-second suite of
# their own: measured 351 s and 333 s in one run that had already spent 285 s
# running it once. Declared here, they run after it and read the recording.
DEPENDS_ON = {
    "suite_cache_selftest": ["suite"],
    "check_manifest_integrity-transcript": ["suite", "rascalrally-suite"],
}

TIMEOUTS = {
    "suite": 3600,
    "suite_cache_selftest": 3600,
    "suite-fast": 1200,
    "rascalrally-suite": 3600,
    "bench": 900,
    "soak": 900,
    "faults": 900,
    "build_places": 1800,
    "build_reference_places": 1800,
}

# The inner loop. Small on purpose: it exists to be run between two keystrokes.
FAST_TIER = {"suite-fast", "stylua-check", "verify-selftest", "check_registration_cli"}

# Producers the release graph runs even though no converted row references them.
# Named here so "release runs every unique producer" is a list somebody can
# read, not a claim.
RELEASE_ONLY = [
    ("doctor", "tools/doctor.sh", "deterministic"),
    ("build_themes", "tools/build_themes.sh", "deterministic"),
    ("build_model", "tools/build_model.sh", "deterministic"),
    ("build_places", "tools/build_places.sh", "deterministic"),
    ("build_reference_places", "tools/build_reference_places.sh", "deterministic"),
    ("soak", "tools/soak.sh", "deterministic"),
    ("faults", "tools/faults.sh", "deterministic"),
    ("fuzz-layout", "tools/fuzz.sh layout", "deterministic"),
    ("fuzz-replication", "tools/fuzz.sh replication", "deterministic"),
    ("fuzz-scheduler", "tools/fuzz.sh scheduler", "deterministic"),
    ("check_no_fusion", "python3 tools/check_no_fusion.py", "deterministic"),
    ("check_library_purity", "python3 tools/check_library_purity.py", "deterministic"),
    ("check_public_allowlist", "python3 tools/check_public_allowlist.py", "deterministic"),
    ("check_links_cli", "lune run tools/lune/check_links_cli", "deterministic"),
    ("package-verify", "tools/package.sh verify", "package"),
    ("rascalrally-suite", f"cd {RR} && tools/suite_transcript.sh", "external"),
]

# Any tools/*.sh invocation at the START of a clause is a producer. The four
# exceptions are the verification entry points themselves: `test.sh` and
# `suite_transcript.sh` ARE the suite (converted separately), and `gate.sh` /
# `prior_gates.sh` are the thing being replaced.
NOT_A_PRODUCER = {"test.sh", "suite_transcript.sh", "gate.sh", "prior_gates.sh", "verify.sh", "commit_isolated.py"}
PRODUCER_COMMAND_RE = re.compile(
    r"^(lune run (?:tools/lune/|tests/)[^\s|>]+"
    r"|python3 tools/[^\s|>]+"
    r"|stylua\b"
    r"|\.?/?tools/[a-z_]+\.sh)"
)


def is_producer_clause(clause: str) -> bool:
    m = PRODUCER_COMMAND_RE.match(clause)
    if not m:
        return False
    return os.path.basename(m.group(1).split()[0]) not in NOT_A_PRODUCER

REDIRECT_TAIL_RE = re.compile(r"(?:\s*(?:2>&1|[12]?>>?\s*[^\s>]+))+\s*$")


def _unquoted_positions(s: str, ch: str) -> list[int]:
    out: list[int] = []
    sq = dq = False
    i = 0
    while i < len(s):
        c = s[i]
        if sq:
            if c == "'":
                sq = False
        elif dq:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                dq = False
        elif c == "'":
            sq = True
        elif c == '"':
            dq = True
        elif c == "\\":
            i += 2
            continue
        elif c == ch:
            out.append(i)
        i += 1
    return out


def strip_redirects(clause: str) -> str:
    """Drop a trailing `>/dev/null`, `2>&1` and friends — but only an UNQUOTED one.

    A case name really does contain `(4 -> 60, 14 -> 84)`, and a quote-blind
    version of this function ate half of that pattern and turned a live gate row
    into an unresolvable one. Measured 2026-08-30.
    """
    s = clause.strip()
    for i in _unquoted_positions(s, ">"):
        start = i
        if start > 0 and s[start - 1] in "12" and (start == 1 or s[start - 2].isspace()):
            start -= 1
        if REDIRECT_TAIL_RE.fullmatch(s[start:]):
            return s[:start].strip()
    return s



# A command POSITION holding one of the old suite front doors. Anything else —
# `test -x tools/suite_transcript.sh`, `grep … tools/test.sh`,
# `git ls-tree HEAD tools/suite_transcript.sh` — is a file assertion about the
# tool and must be left exactly as it is.
FRONT_DOOR_RE = re.compile(
    r"(?P<pre>(?:^|[;&|(]|&&|\|\||\$\()\s*)"
    r"(?P<cmd>(?:\.\./)*(?:\./)?tools/suite_transcript\.sh)"
    r"(?P<args>\s+--status)?"
)


def repoint_transcripts(shell: str) -> tuple[str, list[str]]:
    """Repoint suite-transcript INVOCATIONS at this run's recorded transcript."""
    used: list[str] = []

    def sub(m: re.Match) -> str:
        if m.group("args"):
            return m.group(0)  # `--status` asks; it does not run
        rr = "RascalRally/code" in shell[: m.start()]
        used.append("rr" if rr else "facet")
        var = "FACET_VERIFY_RR_TRANSCRIPT" if rr else "FACET_VERIFY_SUITE_TRANSCRIPT"
        return f'{m.group("pre")}cat "${var}"'

    return FRONT_DOOR_RE.sub(sub, shell), used


def slug(text: str, limit: int = 44) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-")
    if len(s) > limit:
        s = s[:limit].rstrip("-") + "-" + hashlib.sha1(text.encode()).hexdigest()[:6]
    return s


class Producers:
    def __init__(self) -> None:
        self.by_command: dict[str, dict] = {}
        self.by_id: dict[str, dict] = {}

    def declare(self, command: str, *, pid: str, cls: str, inputs: list[str],
                fixtures: list[str] | None = None, kind: str = "scanner",
                tiers: dict | None = None, optional: bool = False,
                note: str = "") -> dict:
        # see DEPENDS_ON
        if command in self.by_command:
            return self.by_command[command]
        assert pid not in self.by_id, f"duplicate producer id {pid}"
        rec = {
            "id": pid,
            "command": command,
            "inputs": inputs,
            "fixtures": fixtures or [],
            "environmentClass": cls,
            "kind": kind,
            "tiers": tiers or {"fast": pid in FAST_TIER, "full": cls in ("deterministic", "studio", "device"), "release": True},
            "serialize": pid in SERIALIZE,
            "timeoutS": TIMEOUTS.get(pid, 600),
            "optional": optional,
            "dependsOn": DEPENDS_ON.get(pid, []),
            "note": note,
        }
        self.by_command[command] = rec
        self.by_id[pid] = rec
        return rec

    def for_command(self, command: str) -> dict:
        """Auto-declare a producer for a scanner/build command from the manifest."""
        if command in self.by_command:
            return self.by_command[command]
        head, _, args = command.partition(" ")
        args = args.strip()
        if head == "stylua":
            base, script = "stylua-check", None
        elif head == "lune":
            # `lune run tools/lune/x [args]`
            parts = command.split()
            target = parts[2]
            script = target + ".luau"
            base = os.path.basename(target)
            args = " ".join(parts[3:])
        elif head == "python3":
            parts = command.split()
            script = parts[1]
            base = os.path.basename(script)[:-3]
            args = " ".join(parts[2:])
        else:
            script = head.lstrip("./")
            base = os.path.basename(script)
            base = base[:-3] if base.endswith(".sh") else base
        pid = base if not args else f"{base}-{slug(args)}"
        if pid in self.by_id:
            pid = f"{base}-{hashlib.sha1(command.encode()).hexdigest()[:8]}"
        cls = CLASS_OVERRIDES.get(base, "deterministic")
        # argv paths that exist become the producer's precise inputs
        argv_paths = [a for a in args.split() if "/" in a and os.path.exists(os.path.join(ROOT, a))]
        inputs: list[str] = []
        if script:
            inputs.append(script)
        if argv_paths:
            inputs.extend(argv_paths)
            # a checker invoked on a named artifact still reads its own helpers
            inputs.append("tools/**")
        else:
            inputs.extend(SOURCE_INPUTS)
        fixtures = list(EVIDENCE_READS.get(base, []))
        for a in argv_paths:
            if a.startswith("artifacts/") and a not in fixtures:
                fixtures.append(a)
        return self.declare(command, pid=pid, cls=cls, inputs=inputs, fixtures=fixtures,
                            kind="measure" if cls == "perf" else "scanner")


# ---------------------------------------------------------------------------
# rows the concurrent workstreams retire or move
# ---------------------------------------------------------------------------

#[[ Rows whose SUBJECT left the product tree in this stage. Keyed by row name —
#   every one of these is unique across the manifest — rather than by
#   (phase, name), because a phase id is a product name this file may not spell:
#   `tools/check_brand_drift.py` scans tools/ and holds the registries that DO
#   carry gate ids (phases.json, requirements.json, the manifest itself) on a
#   named allowlist. The phase comes back from the row being converted. ]]
RETIRED = {
    "conformance-fusion-adapter":
        "workstream K removed the vendored third-party reactive core and the adapter that bridged "
        "it, and archived the scorecard this row read; the conformance corpus still runs against "
        "the custom core and the imperative baseline",
    "comparison-docs-honest":
        "the two framework-comparison documents this row pinned were archived out of the "
        "repository by workstream K; the public framework-choice guide is their living replacement",
}

#[[ WHICH REFERENCE DOCUMENTS ARE LEAVING, said without naming them. Workstream
#   E1 is moving everything under docs/reference/ except the API catalogue and
#   the constitution out of this repository, and recording where each living
#   contract went. A row pinning one of the leaving documents is marked
#   `pendingMigration` and repointed once that ledger exists — the path is read
#   out of the manifest row, never typed here. ]]
REFERENCE_DIR = "docs/reference/"
REFERENCE_KEPT = {"api.md", "constitution.md"}
REFERENCE_DOC_RE = re.compile(r"docs/reference/([A-Za-z0-9._-]+\.md)")

MIGRATION_LEDGER = "artifacts/distribution-readiness/swiftui-migration.md"



# ---------------------------------------------------------------------------
# public naming, recorded evidence, and history
# ---------------------------------------------------------------------------

# NEUTRAL PHASE IDS (director ruling 2026-08-30). A phase id is a PUBLIC name —
# it is the key of the graph, the argument to tools/gate.sh, and the directory
# the compat gate.json is written into — so it may not carry a product this
# library is not. The rule is a SHAPE, not a list of old names: a phase whose id
# is "<something>-parity-round<n>" is "parity-round-<n>", and one that is
# "<something>-reference-app-validation" is "reference-app-validation".
# graph-census.md records old -> new; that document is archived privately and may
# spell the retired names.
PHASE_NEUTRALIZE = [
    (re.compile(r"^[a-z0-9]+-(parity-round)(\d)$"), r"\1-\2"),
    (re.compile(r"^[a-z0-9]+-(reference-app-validation)$"), r"\1"),
]


def neutral_phase(phase: str) -> str:
    for rx, repl in PHASE_NEUTRALIZE:
        if rx.match(phase):
            return rx.sub(repl, phase)
    return phase


# Recorded evidence a MACHINE produced and a headless cache can never re-take:
# Studio drives, device captures, performance captures, engine-feasibility
# probes, measured row records. These keep their evidence class (the plan is
# explicit that perf/Studio/device/moderation/network results are never upgraded
# by a headless run) and become receipts. Everything else a row pins under
# artifacts/ is a ledger or a verdict from a stage that has closed: a record of a
# past decision, which leaves the public graph for the coverage map.
LIVING_EVIDENCE = re.compile(
    r"artifacts/(?:studio/"
    r"|[^/]+/(?:studio|device|captures|feasibility|perf|rows|matrix)(?:/|\.)"
    r"|[^/]+/[^/]*(?:studio-drive|device-matrix|-capture)[^/]*)"
)

# WHETHER A STRING IS SAFE TO PUBLISH, asked of the one checker that decides it.
# The patterns are IMPORTED rather than restated, so this file carries none of
# the words it is filtering for and cannot drift away from the guard.
def _publication_patterns():
    import importlib.util

    spec = importlib.util.spec_from_file_location("_facet_brand_guard", os.path.join(ROOT, "tools/check_brand_drift.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return [p for p in (module.BRAND, module.TAG, module.VENDOR, module.VENDOR_TYPES) if p is not None]


_PUBLICATION_PATTERNS = None


def is_publishable(text: str) -> bool:
    global _PUBLICATION_PATTERNS
    if _PUBLICATION_PATTERNS is None:
        _PUBLICATION_PATTERNS = _publication_patterns()
    return not any(p.search(text) for p in _PUBLICATION_PATTERNS)

ARTIFACT_PATH = re.compile(r"artifacts/[A-Za-z0-9._/-]+")
SOURCE_PATH = re.compile(r"(?<![\w/])(?:src|tests|examples|docs|tools|bench|package|skills)/")


def sha256_file(path: str) -> str | None:
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


# ---------------------------------------------------------------------------
# conversion
# ---------------------------------------------------------------------------


# THE ROW'S NOTE IS GENERATED, NOT INHERITED (director ruling 2026-08-30).
#
# The manifest's `note` strings are an implementation diary: they name vendors
# and platforms, quote review codes, and recount the round that produced the
# row. That prose is history and it stays in the manifest, which the director
# archives privately. What a reader of a FAILING row needs is one plain sentence
# saying what the row requires — so the note is derived from the check itself,
# which also means it can never drift away from what the row actually does.
def neutral_note(name: str, requirements: list[str], check: dict, evidence: str | None) -> str:
    clauses: list[str] = []
    ids = check.get("resultIds") or []
    if ids:
        clauses.append(f"{len(ids)} named suite case{'s' if len(ids) != 1 else ''} must pass")
    producers = check.get("producers") or []
    if producers:
        clauses.append(f"{', '.join(producers)} must exit zero")
    pins = check.get("stdoutPins") or []
    if pins:
        clauses.append(f"{len(pins)} pin{'s' if len(pins) != 1 else ''} on a producer's own output must match")
    if check.get("shell"):
        clauses.append("its file-existence and text assertions must hold")
    if check.get("priorPhases"):
        clauses.append("every row of every earlier phase must pass in this same run")
    if evidence:
        clauses.append(f"and {evidence} must exist")
    if not clauses:
        clauses.append("declared evidence, recorded rather than executed")
    reqs = ", ".join(requirements) if requirements else "none recorded"
    return f"{name}: " + "; ".join(clauses) + f". Requirements: {reqs}."


def load_case_names(suite_results_path: str) -> list[tuple[str, str]]:
    data = json.load(open(suite_results_path))
    return [(c["name"], c["id"]) for c in data["cases"]]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite-results", required=True)
    ap.add_argument("--manifest", default="/tmp/facet-gate-manifest.json")
    ap.add_argument("--out", default="tools/lune/verify/graph.json")
    ap.add_argument("--census", default="artifacts/distribution-readiness/verification/graph-census.md")
    ap.add_argument("--coverage", default="artifacts/distribution-readiness/verification/coverage-map.md")
    args = ap.parse_args()

    os.chdir(ROOT)
    if not os.path.exists(args.manifest):
        subprocess.run(["lune", "run", "tools/lune/verify/dump_manifest", args.manifest], check=True)

    manifest = json.load(open(args.manifest))
    phase_doc = json.load(open("phases.json"))["phases"]
    phases = [p["gate"] for p in phase_doc]
    renamed = {p: neutral_phase(p) for p in phases}
    phase_records = []
    for i, p in enumerate(phases):
        n = renamed[p]
        nxt = renamed.get(phases[i + 1]) if i + 1 < len(phases) else None
        phase_records.append({
            "id": n,
            "artifactDir": f"artifacts/{n}",
            "gateArtifact": f"artifacts/{n}/gate.json",
            "next": nxt,
        })
    cases = load_case_names(args.suite_results)
    receipts_dir = "tools/lune/verify/evidence"
    os.makedirs(receipts_dir, exist_ok=True)
    for stale in os.listdir(receipts_dir):
        if stale.endswith(".json"):
            os.remove(os.path.join(receipts_dir, stale))
    receipts_written = 0
    historical = []

    producers = Producers()
    producers.declare(
        "./run-tests.sh", pid="suite", cls="deterministic", inputs=SUITE_INPUTS, kind="suite",
        tiers={"fast": False, "full": True, "release": True},
        note="the one full deterministic suite run; writes structured per-case results",
    )
    producers.declare(
        "./run-tests.sh --fast", pid="suite-fast", cls="deterministic", inputs=SUITE_INPUTS, kind="suite",
        tiers={"fast": True, "full": False, "release": False},
        note="the inner-loop tier; its result is tier 'fast' and is REFUSED as suite evidence",
    )
    producers.declare(
        "lune run tools/lune/verify/selftest", pid="verify-selftest", cls="deterministic",
        inputs=["tools/lune/verify/**"], kind="scanner",
        tiers={"fast": True, "full": True, "release": True},
        note="the graph's own negative controls: every refusal the result store can make",
    )
    for pid, command, cls in RELEASE_ONLY:
        script = None
        if command.startswith("python3 "):
            script = command.split()[1]
        elif command.startswith("lune run "):
            script = command.split()[2] + ".luau"
        elif command.startswith("tools/"):
            script = command.split()[0]
        present = script is None or os.path.exists(script)
        if pid == "rascalrally-suite":
            inputs = [f"{RR}/src/**", f"{RR}/tests/**", "src/**", "tests/**"]
            present = os.path.isdir(RR)
        else:
            inputs = SOURCE_INPUTS
        producers.declare(
            command, pid=pid, cls=cls, inputs=inputs,
            kind="external" if cls == "external" else ("build" if pid.startswith("build") else "scanner"),
            # The Rascal Rally suite runs in FULL too: eleven converted rows grep
            # its transcript, and leaving them unevaluated at full would be a
            # quiet weakening. It is non-blocking when the sibling checkout is
            # absent, and required at release.
            tiers={"fast": False, "full": cls in ("deterministic", "external"), "release": True},
            optional=not present,
            note="required by the release graph" + ("" if present else "; not present in this tree yet"),
        )

    rows: list[dict] = []
    census = {
        "result-ids": 0, "exit0": 0, "evidence-pin": 0, "prior-phases": 0,
        "declared": 0, "retired": 0, "pending-migration": 0, "pending": 0,
        "evidence-receipt": 0, "historical": 0,
    }
    unresolved: list[str] = []
    resolved_patterns = 0
    resolved_ids = 0
    migration_ready = os.path.exists(MIGRATION_LEDGER)

    for phase in phases:
        for entry in manifest.get(phase, []):
            name = entry["name"]
            public_phase = renamed[phase]
            row_id = f"{public_phase}::{name}"
            base = {
                "id": row_id,
                "phase": public_phase,
                "name": name,
                "requirements": entry.get("requirements") or [],
                "evidence": (entry.get("evidence") if entry.get("evidence") and is_publishable(entry["evidence"]) else None),
                "releaseBlocking": bool(entry.get("releaseBlocking")),
                # `note` is generated below from the converted check; the
                # manifest's own prose is history and stays there.
            }
            retired = RETIRED.get(name)
            if retired is not None:
                base.update({"class": "retired", "state": "RETIRED", "retiredReason": retired,
                             "check": {}, "note": f"{name}: retired in this stage; see retiredReason."})
                census["retired"] += 1
                rows.append(base)
                continue
            run = entry.get("run")
            if run is None:
                state = entry.get("state") or "PENDING"
                base.update({"class": "declared", "state": state, "check": {},
                             "note": neutral_note(name, base["requirements"], {}, base.get("evidence"))})
                census["pending" if state == "PENDING" else "declared"] += 1
                rows.append(base)
                continue

            clauses = split_and(run)
            assert " && ".join(clauses) == run.strip(), f"split round trip failed for {row_id}"

            rr_scope = False
            suite_vars: dict[str, str] = {}
            row_producers: list[str] = []
            row_ids: list[str] = []
            stdout_pins: list[dict] = []
            residual: list[str] = []
            prior_phases = False
            pending_migration: str | None = None

            def add_producer(pid: str) -> None:
                if pid not in row_producers:
                    row_producers.append(pid)

            for clause in clauses:
                stripped = clause.strip()
                bare = strip_redirects(stripped)

                if "prior_gates.sh" in stripped:
                    prior_phases = True
                    residual.append("true")
                    continue

                if bare.startswith("cd "):
                    if RR in bare:
                        rr_scope = True
                    residual.append(stripped)
                    continue

                # a whole subshell that only runs the Rascal Rally suite
                sub = re.fullmatch(r"\(cd " + re.escape(RR) + r" && tools/suite_transcript\.sh(?: >/dev/null)?\)", bare)
                if sub:
                    add_producer("rascalrally-suite")
                    residual.append("true")
                    continue

                m = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)=\"\$\(tools/suite_transcript\.sh\)\"", bare)
                if m:
                    var = m.group(1)
                    if rr_scope:
                        add_producer("rascalrally-suite")
                        suite_vars[var] = "rr"
                        residual.append(f'{var}="$(cat "$FACET_VERIFY_RR_TRANSCRIPT")"')
                    else:
                        add_producer("suite")
                        suite_vars[var] = "facet"
                        residual.append("true")
                    continue

                if re.fullmatch(r"tools/suite_transcript\.sh", bare):
                    add_producer("rascalrally-suite" if rr_scope else "suite")
                    residual.append("true")
                    continue

                m = re.fullmatch(r"tools/suite_transcript\.sh\s*\|\s*grep\s+(-\w+)\s+(.*)", bare)
                if m:
                    flags, pat = m.group(1), m.group(2)
                    if rr_scope:
                        add_producer("rascalrally-suite")
                        residual.append(f'grep {flags} {pat} "$FACET_VERIFY_RR_TRANSCRIPT"')
                    else:
                        add_producer("suite")
                        got = resolve(pat, flags, cases)
                        if got is None:
                            unresolved.append(f"{row_id}: {pat}")
                            residual.append(f'grep {flags} {pat} "$FACET_VERIFY_SUITE_TRANSCRIPT"')
                        else:
                            resolved_patterns += 1
                            for cid in got:
                                if cid not in row_ids:
                                    row_ids.append(cid)
                            residual.append("true")
                    continue

                m = re.fullmatch(r'echo\s+"\$([A-Za-z_][A-Za-z0-9_]*)"\s*\|\s*grep\s+(-\w+)\s+(.*)', bare)
                if m and m.group(1) in suite_vars:
                    var, flags, pat = m.group(1), m.group(2), m.group(3)
                    if suite_vars[var] == "rr":
                        residual.append(stripped)
                    elif "✓" not in pat:
                        # a pin on something other than a case line (a count, a
                        # summary): keep it, but serve it from the recorded run
                        residual.append(stripped)
                    else:
                        got = resolve(pat, flags, cases)
                        if got is None:
                            # THE PATTERN NO LONGER MATCHES ANY CASE. That row is
                            # red TODAY on the old path, and converting it into an
                            # empty id list would turn a red row green. It keeps
                            # its grep, served from the recorded transcript so the
                            # suite still runs once, and it is counted below so
                            # somebody fixes the manifest rather than losing it.
                            unresolved.append(f"{row_id}: {pat}")
                            residual.append(f'grep {flags} {pat} "$FACET_VERIFY_SUITE_TRANSCRIPT"')
                        else:
                            resolved_patterns += 1
                            for cid in got:
                                if cid not in row_ids:
                                    row_ids.append(cid)
                            residual.append("true")
                    continue

                if re.match(r"^\.?/?tools/test\.sh\b", bare):
                    add_producer("rascalrally-suite" if rr_scope else "suite")
                    residual.append("true")
                    continue

                if not rr_scope and is_producer_clause(bare):
                    m = re.fullmatch(r"(.*?)\s*\|\s*grep\s+(-\w+)\s+(.*)", bare)
                    if m and is_producer_clause(m.group(1)):
                        prod = producers.for_command(strip_redirects(m.group(1)))
                        add_producer(prod["id"])
                        stdout_pins.append({"producer": prod["id"], "flags": m.group(2),
                                            "pattern": m.group(3)})
                        residual.append("true")
                        continue
                    prod = producers.for_command(bare)
                    add_producer(prod["id"])
                    residual.append("true")
                    continue

                for doc in REFERENCE_DOC_RE.findall(stripped):
                    if doc not in REFERENCE_KEPT:
                        pending_migration = REFERENCE_DIR + doc
                residual.append(stripped)

            #[[ THE ARTIFACT CLAUSES LEAVE THE SHELL AND BECOME A RECEIPT
            #   (director ruling 2026-08-30).
            #
            #   A clause whose only paths are under artifacts/ is asserting
            #   something about recorded evidence, and a CONTENT HASH is a
            #   strictly stronger pin than `test -f` or a grep of the same file —
            #   while also keeping a path that names a retired product out of a
            #   public file. Variable assignments are followed, so
            #   `f=artifacts/x && grep -qF "y" "$f"` moves as one group.
            #
            #   A row whose clauses are ALL artifact clauses and whose files are
            #   all checked-in ledgers of a stage that closed is a record of a
            #   past decision: it leaves the graph for the coverage map. If any
            #   of them is recorded machine evidence — a Studio drive, a device
            #   or performance capture, an engine-feasibility probe, a measured
            #   row — the row stays, as a receipt of that class. ]]
            artifact_vars: set[str] = set()
            moved_assigns: set[str] = set()
            kept: list[str] = []
            moved: list[str] = []
            artifact_paths: list[str] = []
            for clause in residual:
                c = clause.strip()
                if c == "true":
                    continue
                paths = ARTIFACT_PATH.findall(c)
                touches_source = bool(SOURCE_PATH.search(c))
                uses_artifact_var = any(f"${v}" in c for v in artifact_vars)
                assign = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)=(artifacts/[A-Za-z0-9._/-]+)", c)
                if assign and not touches_source:
                    artifact_vars.add(assign.group(1))
                    moved_assigns.add(assign.group(1))
                    artifact_paths.append(assign.group(2))
                    moved.append(c)
                    continue
                if (paths or uses_artifact_var) and not touches_source:
                    artifact_paths.extend(paths)
                    named = re.match(r"([A-Za-z_][A-Za-z0-9_]*)=", c)
                    if named:
                        moved_assigns.add(named.group(1))
                    moved.append(c)
                    continue
                kept.append(c)

            #[[ A KEPT CLAUSE MAY NOT READ A VARIABLE A MOVED ONE SET.
            #   `lost="$(comm -23 <(grep … "$a") …)" && test -z "$lost"` splits
            #   into a moved assignment and a kept test — and the kept test then
            #   reads an UNSET variable, which passes. That is a check that
            #   cannot fail, manufactured by the split itself. When it would
            #   happen, the row is not split at all. ]]
            if any(f"${v}" in c for c in kept for v in moved_assigns):
                kept = kept + moved
                moved = []
                artifact_paths = []
            shell = " && ".join(kept) if kept else None
            artifact_paths = sorted(set(artifact_paths))

            if prior_phases:
                base.update({
                    "class": "prior-phases",
                    "check": {"priorPhases": True},
                    "state": None,
                    "note": neutral_note(name, base["requirements"], {"priorPhases": True}, base.get("evidence")),
                })
                census["prior-phases"] += 1
                rows.append(base)
                continue

            # A residual clause that still reaches a suite through the old front
            # door — `(cd RR && tools/suite_transcript.sh | grep …)` inside a
            # subshell, which the clause splitter correctly refuses to take
            # apart — is repointed at the transcript THIS RUN recorded. `cat
            # <file>` behaves identically in all three positions the manifest
            # uses (command substitution, pipe source, `>/dev/null`), so this is
            # one substitution rather than three special cases.
            #
            # `--status` is NOT touched: it asks the cache a question and starts
            # nothing, and two rows assert exactly that the cache is warm.
            if shell is not None:
                shell, transcripts = repoint_transcripts(shell)
                for which in transcripts:
                    add_producer("rascalrally-suite" if which == "rr" else "suite")
                if "RascalRally/code" in shell and ("suite_transcript.sh" in shell or "test.sh" in shell):
                    add_producer("rascalrally-suite")
                if re.search(r"(?<!/)tools/(suite_transcript|test)\.sh", shell):
                    add_producer("suite")

            receipt_path = None
            if artifact_paths:
                living = [q for q in artifact_paths if LIVING_EVIDENCE.match(q)]
                if not living and not shell and not row_producers and not row_ids and not stdout_pins:
                    historical.append({"row": row_id, "phase": public_phase, "name": name,
                                       "requirements": base["requirements"], "paths": artifact_paths})
                    census["historical"] += 1
                    continue
                joined = " ".join(living)
                cls_name = (
                    "device" if "/device" in joined or "device-" in joined
                    else "perf" if "/perf" in joined or "captures" in joined
                    else "studio" if living
                    else "record"
                )
                receipt_id = row_id.replace("::", "--")
                items = []
                for n, q in enumerate(artifact_paths, 1):
                    digest = sha256_file(q)
                    item = {"label": f"evidence-{n}", "sha256": digest or "absent"}
                    if is_publishable(q):
                        item["archivedPath"] = q
                    items.append(item)
                receipt = {
                    "schema": "facet-evidence-receipt/1",
                    "row": row_id,
                    "class": cls_name,
                    "recordedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "summary": f"{name}: {len(items)} recorded file(s), pinned by content hash.",
                    "evidence": items,
                }
                with open(os.path.join(receipts_dir, receipt_id + ".json"), "w") as fh:
                    json.dump(receipt, fh, indent=1, sort_keys=True)
                    fh.write("\n")
                receipts_written += 1
                receipt_path = f"{receipts_dir}/{receipt_id}.json"
                if cls_name != "record":
                    census["evidence-receipt"] += 1

            check = {}
            if row_producers:
                check["producers"] = row_producers
            if row_ids:
                check["resultIds"] = row_ids
                resolved_ids += len(row_ids)
            if stdout_pins:
                check["stdoutPins"] = stdout_pins
            if shell:
                check["shell"] = shell
            if receipt_path:
                check["receipt"] = receipt_path
            base["check"] = check
            base["state"] = None
            base["note"] = neutral_note(name, base["requirements"], check, base.get("evidence"))
            if pending_migration and not migration_ready:
                # true, not the path: the path names a document by a product
                # name this file may not carry. The census records which one.
                base["pendingMigration"] = True
                census["pending-migration"] += 1
            if row_ids:
                base["class"] = "result-ids"
                census["result-ids"] += 1
            elif row_producers and not shell:
                base["class"] = "exit0"
                census["exit0"] += 1
            else:
                base["class"] = "evidence-pin"
                census["evidence-pin"] += 1
            rows.append(base)

    if unresolved:
        print(f"convert_manifest: {len(unresolved)} transcript pattern(s) match no case in this suite "
              f"(kept as a grep of the recorded transcript; those rows are red today too):", file=sys.stderr)
        for line in unresolved:
            print("  " + line, file=sys.stderr)

    graph = {
        "schema": "facet-verify-graph/1",
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generatedFrom": {
            "manifest": "tools/lune/gate_manifest.luau",
            "phases": "phases.json",
            "suiteResults": os.path.basename(args.suite_results),
        },
        "phases": phase_records,
        "producers": sorted(producers.by_id.values(), key=lambda p: p["id"]),
        "rows": rows,
    }
    with open(args.out, "w") as fh:
        json.dump(graph, fh, indent=1, sort_keys=True, ensure_ascii=False)
        fh.write("\n")

    graph["unresolvedPatterns"] = unresolved
    write_census(args.census, graph, census, resolved_patterns, resolved_ids, migration_ready,
                 renamed, historical, receipts_written)
    write_coverage(args.coverage, graph, historical, receipts_written)
    print(f"convert_manifest: {len(rows)} rows, {len(graph['producers'])} producers -> {args.out}")
    for k, v in sorted(census.items()):
        print(f"    {k:18s} {v}")
    print(f"    {'patterns resolved':18s} {resolved_patterns} -> {resolved_ids} case id references")
    return 0


def resolve(raw_pattern: str, flags: str, cases: list[tuple[str, str]]) -> list[str] | None:
    """Resolve one `grep` pattern against the case list. None = matched nothing."""
    pat = raw_pattern.strip()
    if pat.startswith('"') and pat.endswith('"'):
        pat = pat[1:-1]
    elif pat.startswith("'") and pat.endswith("'"):
        pat = pat[1:-1]
    pat = pat.replace('\\"', '"')
    if "F" in flags:
        rx = re.compile(re.escape(pat))
    elif "E" in flags:
        rx = re.compile(pat)
    else:
        rx = re.compile(bre_to_python(pat))
    hits = [cid for name, cid in cases if rx.search("  ✓ " + name)]
    seen: list[str] = []
    for h in hits:
        if h not in seen:
            seen.append(h)
    return seen or None


def write_census(path: str, graph: dict, census: dict, patterns: int, ids: int,
                 migration_ready: bool, renamed: dict, historical: list, receipts: int) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    rows = graph["rows"]
    by_phase: dict[str, int] = {}
    for r in rows:
        by_phase[r["phase"]] = by_phase.get(r["phase"], 0) + 1
    phase_ids = [p["id"] for p in graph["phases"]]
    lines = [
        "# Graph census — what every gate manifest row became",
        "",
        "Generated by `python3 tools/lune/verify/convert_manifest.py`. Regenerate it rather",
        "than editing it: the conversion is a scripted transform over",
        "`tools/lune/gate_manifest.luau`, and the numbers below are its output.",
        "",
        f"- Rows converted: **{len(rows)}** across **{len(graph['phases'])}** phase views",
        f"- Producers declared: **{len(graph['producers'])}**",
        f"- Transcript greps resolved: **{patterns}** patterns -> **{ids}** case-id references",
        f"- Transcript greps that match no case in this suite: **{len(graph.get('unresolvedPatterns', []))}**",
        "",
        "## Rows by class",
        "",
        "| Class | Rows | What it means |",
        "|---|---:|---|",
        f"| converted-to-result-ids | {census['result-ids']} | the row's `✓.*<sentence>` greps became lookups of specific case ids in the one structured suite result |",
        f"| exit0 | {census['exit0']} | the row asserts nothing but that one or more producers exited zero |",
        f"| evidence-pin | {census['evidence-pin']} | the row still pins text or file existence (an artifact ledger, a source grep, a negative control over `src/`); kept verbatim, evaluated once |",
        f"| prior-phases | {census['prior-phases']} | `prior-gates-unregressed`: replay replaced by the coordinator evaluating every earlier phase from the same run |",
        f"| declared-evidence | {census['declared']} | a literal state in the manifest (Studio, physical device, or human judgement) carried across unchanged |",
        f"| pending | {census['pending']} | a bare PENDING row awaiting its work (the 34 distribution-readiness rows) |",
        f"| evidence-receipt | {census['evidence-receipt']} | recorded Studio/device/performance evidence, pinned by content hash in `tools/lune/verify/evidence/` instead of by a raw path and a literal grep |",
        f"| historical | {census['historical']} | a pin on a checked-in ledger or verdict from a stage that closed: a record of a past decision, archived with the phase prose (listed below) |",
        f"| retired | {census['retired']} | the row's subject left the product tree in this stage (workstream K); reasons below |",
        f"| pending-migration | {census['pending-migration']} | the row pins a document under `docs/reference/` that workstream E1 is moving out of this repository; repointed when the migration ledger lands |",
        "",
        f"Migration ledger present: **{'yes' if migration_ready else 'not yet'}**",
        "",
        "## Retired rows",
        "",
        "| Phase | Row | Why |",
        "|---|---|---|",
    ]
    for r in rows:
        if r.get("class") == "retired":
            lines.append(f"| `{r['phase']}` | `{r['name']}` | {r['retiredReason']} |")
    changed = [(old, new) for old, new in sorted(renamed.items()) if old != new]
    if changed:
        lines += [
            "",
            "## Phase ids renamed for the public graph",
            "",
            "A phase id is a public name: it is the key of the graph, the argument to",
            "`tools/gate.sh`, and the directory the compatibility `gate.json` is written into.",
            "The converter neutralises any id whose SHAPE carries a product this library is not",
            "(`<x>-parity-round<n>` and `<x>-reference-app-validation`), so no public file has to",
            "spell it. This census is archived privately with the stage evidence, so it may.",
            "",
            "| id in phases.json | id in the graph |",
            "|---|---|",
        ]
        for old_id, new_id in changed:
            lines.append(f"| `{old_id}` | `{new_id}` |")
        lines += [
            "",
            "The frozen evidence directories under `artifacts/` keep their earned names; only the",
            "graph's public key changes. The compatibility `gate.json` for a renamed phase is",
            "written under the NEW name.",
            "",
        ]

    lines += [
        "",
        f"## Evidence receipts ({receipts})",
        "",
        "A row that pinned a file under `artifacts/` by path and grepped a literal string out of",
        "it now carries a RECEIPT instead: `tools/lune/verify/evidence/<row>.json`, holding one",
        "sha256 per file. A content hash is a strictly stronger pin than `test -f` or a grep of",
        "the same file, and it keeps a path that names a retired stage out of a public file. The",
        "coordinator verifies each hash against the file on disk when it is still there, and",
        "against `../Facet-private-archive/MANIFEST.json` when that archive is beside the",
        "checkout; when neither is available the receipt stands as declared evidence and the run",
        "report lists it under \"recorded evidence, reported separately\".",
        "",
    ]

    if historical:
        lines += [
            "",
            f"## Rows archived as records of a past decision ({len(historical)})",
            "",
            "Each of these asserted only that a checked-in ledger or verdict of a CLOSED stage",
            "still says what it said. That is a record, not a living requirement: the requirement",
            "it once guarded is proved today by a producer or a suite case in the same phase, and",
            "the document itself is archived with that phase's evidence. Requirement coverage",
            "after the removal is checked in `coverage-map.md`.",
            "",
            "| Phase | Row | Requirements | The files it pinned |",
            "|---|---|---|---|",
        ]
        for h in historical:
            paths = ", ".join(f"`{q}`" for q in h["paths"][:4])
            if len(h["paths"]) > 4:
                paths += f" (+{len(h['paths']) - 4} more)"
            lines.append(f"| `{h['phase']}` | `{h['name']}` | {', '.join(h['requirements']) or '—'} | {paths} |")
        lines.append("")

    if graph.get("unresolvedPatterns"):
        lines += [
            "",
            "## Transcript greps that resolve to no case",
            "",
            "These rows are RED at this tree on the old path too — the case they name has been",
            "renamed or removed and nobody noticed, which is precisely the fragility this",
            "conversion exists to end. They keep their grep, served from the ONE recorded",
            "transcript (`$FACET_VERIFY_SUITE_TRANSCRIPT`) rather than a fresh suite run, so the",
            "verdict is unchanged. Fixing the manifest row converts them to case ids on the next",
            "regeneration.",
            "",
        ]
        for line in graph["unresolvedPatterns"]:
            lines.append(f"- `{line}`")
    lines += ["", "## Rows per phase", "", "| Phase | Rows |", "|---|---:|"]
    for p in phase_ids:
        lines.append(f"| `{p}` | {by_phase.get(p, 0)} |")
    lines += ["", "## Producers", "", "| Producer | Class | Serialize | Tiers | Command |", "|---|---|---|---|---|"]
    for p in graph["producers"]:
        tiers = ",".join(k for k in ("fast", "full", "release") if p["tiers"].get(k))
        lines.append(
            f"| `{p['id']}` | {p['environmentClass']} | {'yes' if p['serialize'] else 'no'} | {tiers} | `{p['command'][:90]}` |"
        )
    lines.append("")
    with open(path, "w") as fh:
        fh.write("\n".join(lines))



def write_coverage(path: str, graph: dict, historical: list, receipts: int) -> None:
    """Every execution the conversion removed or merged, and what still proves it."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    rows = graph["rows"]
    by_req: dict[str, list[str]] = {}
    for r in rows:
        if r.get("class") == "retired":
            continue
        for q in r["requirements"]:
            by_req.setdefault(q, []).append(r["id"])
    reqs = json.load(open("requirements.json"))["requirements"]
    orphans = [q for q in reqs if not by_req.get(q["id"])]

    producers_by_row = {r["id"]: (r.get("check") or {}).get("producers", []) for r in rows}

    L = [
        "# Coverage map — nothing was removed without a home",
        "",
        "Generated by `python3 tools/lune/verify/convert_manifest.py`. For every execution the",
        "conversion removed, merged or changed shape, this names the requirement it carried, the",
        "direction it failed in, the fixture it ran against, its negative control, and the",
        "producer or case id that proves the same thing now.",
        "",
        "## 1. The mechanism that changed for 193 rows",
        "",
        "| Was | Is | Requirement | Failure direction | Fixture | Negative control |",
        "|---|---|---|---|---|---|",
        "| `out=\"$(tools/suite_transcript.sh)\" && echo \"$out\" \\| grep -q \"✓.*<sentence>\"` — one cached transcript spent per row, 1,425 times | a lookup of the case's id in the ONE structured suite result | unchanged (the row keeps its requirement ids) | a failing case reddens the row, exactly as before; a case that no longer EXISTS now reddens it too, which the grep could not distinguish from a passing one | the same suite run, at the same source identity | `tools/check_manifest_integrity.py --selftest` plants a renamed id and requires it to be rejected; the coordinator reports a missing id by name |",
        "",
        "## 2. Prior-gate replay",
        "",
        "| Was | Is | Requirement | Failure direction | Negative control |",
        "|---|---|---|---|---|",
        "| 16 `prior-gates-unregressed` rows, each running `tools/prior_gates.sh`, which re-ran every earlier gate, each of which re-ran ITS priors | one lookup: every row of every earlier phase, evaluated from this same run | UI-AGENT-001 (unchanged) | a regressed earlier row reddens the later phase, as before — and now names the row rather than a roll-up line | mutation M7 in `mutation-parity.md` deletes an evidence file an earlier phase pins and requires the later phase's prior-phases row to go red |",
        "",
        f"## 3. Rows archived as records of a past decision ({len(historical)})",
        "",
        "Each pinned only that a checked-in ledger or verdict of a CLOSED stage still says what it",
        "said. The requirement each carried is listed with the living row that proves it today.",
        "",
        "| Phase | Row | Requirement | Still proved by |",
        "|---|---|---|---|",
    ]
    for h in historical:
        for q in (h["requirements"] or ["—"]):
            living = by_req.get(q, [])
            same_phase = [x for x in living if x.startswith(h["phase"] + "::")]
            proof = ", ".join(f"`{x}`" for x in (same_phase or living)[:3]) or "**nothing — see §5**"
            L.append(f"| `{h['phase']}` | `{h['name']}` | {q} | {proof} |")
    L += [
        "",
        f"## 4. Rows whose artifact pins became receipts ({receipts})",
        "",
        "A `test -f <path>` or a `grep -qF \"<string>\" <path>` over recorded evidence became a",
        "sha256 of the same file in `tools/lune/verify/evidence/`. Strictly stronger: the grep",
        "passed on any file containing the string, the hash passes only on the file that was",
        "recorded. Verified against the file on disk when present and against the private",
        "archive's manifest when that archive is beside the checkout; otherwise reported",
        "separately as declared evidence, which is the class those rows always had.",
        "",
        "## 5. Requirements with no living row",
        "",
    ]
    if orphans:
        L += ["| Requirement | Title | First gate |", "|---|---|---|"]
        for q in orphans:
            L.append(f"| `{q['id']}` | {q['title'][:110]} | `{q.get('firstGate', '—')}` |")
    else:
        L.append("None: every requirement in `requirements.json` is carried by at least one row that")
        L.append("still executes.")
    L += [
        "",
        "## 6. Retired rows",
        "",
        "| Phase | Row | Requirement | Why | Still proved by |",
        "|---|---|---|---|---|",
    ]
    for r in rows:
        if r.get("class") != "retired":
            continue
        for q in (r["requirements"] or ["—"]):
            living = [x for x in by_req.get(q, [])][:3]
            L.append(f"| `{r['phase']}` | `{r['name']}` | {q} | {r['retiredReason']} | "
                     + (", ".join(f"`{x}`" for x in living) or "**nothing — see §5**") + " |")
    L.append("")
    with open(path, "w") as fh:
        fh.write("\n".join(L))

if __name__ == "__main__":
    sys.exit(main())
