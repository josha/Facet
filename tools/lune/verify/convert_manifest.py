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
    # runs the suite several times on purpose, to break its own cache guards
    "suite_cache_selftest",
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

RETIRED = {
    ("phase-0-foundation", "conformance-fusion-adapter"):
        "workstream K removed the vendored Fusion tree and src/core/fusion_adapter.luau; the "
        "conformance corpus itself still runs against the custom core inside the suite",
    ("phase-0-foundation", "conformance-imperative-baseline"):
        "workstream K moved src/core/imperative.luau to bench/cores/, so the imperative core is a "
        "benchmark comparison rather than a shipped core; the corpus still runs against the custom core",
    ("phase-0-foundation", "foundation-decision"):
        "the row pins totals in artifacts/decision-foundation.json, archived by workstream K with the "
        "rest of the Fusion comparison material",
    ("code-simplicity-cleanup", "conformance-all-cores"):
        "the loop runs the corpus over `custom fusion imperative`; two of the three cores left the "
        "product tree with workstream K",
    ("swiftui-parity-round4", "comparison-docs-honest"):
        "docs/reference/{fusion,react-lua}-comparison.md were deleted by workstream K; the public "
        "framework-choice guide (workstream E2) is their living replacement",
}

SWIFTUI_DOC = "docs/reference/swiftui-parity.md"
MIGRATION_LEDGER = "artifacts/distribution-readiness/swiftui-migration.md"


# ---------------------------------------------------------------------------
# conversion
# ---------------------------------------------------------------------------

def load_case_names(suite_results_path: str) -> list[tuple[str, str]]:
    data = json.load(open(suite_results_path))
    return [(c["name"], c["id"]) for c in data["cases"]]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite-results", required=True)
    ap.add_argument("--manifest", default="/tmp/facet-gate-manifest.json")
    ap.add_argument("--out", default="tools/lune/verify/graph.json")
    ap.add_argument("--census", default="artifacts/distribution-readiness/verification/graph-census.md")
    args = ap.parse_args()

    os.chdir(ROOT)
    if not os.path.exists(args.manifest):
        subprocess.run(["lune", "run", "tools/lune/verify/dump_manifest", args.manifest], check=True)

    manifest = json.load(open(args.manifest))
    phases = [p["gate"] for p in json.load(open("phases.json"))["phases"]]
    cases = load_case_names(args.suite_results)

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
    }
    unresolved: list[str] = []
    resolved_patterns = 0
    resolved_ids = 0
    migration_ready = os.path.exists(MIGRATION_LEDGER)

    for phase in phases:
        for entry in manifest.get(phase, []):
            name = entry["name"]
            row_id = f"{phase}::{name}"
            base = {
                "id": row_id,
                "phase": phase,
                "name": name,
                "requirements": entry.get("requirements") or [],
                "evidence": entry.get("evidence"),
                "releaseBlocking": bool(entry.get("releaseBlocking")),
                "note": entry.get("note") or "",
            }
            retired = RETIRED.get((phase, name))
            if retired is not None:
                base.update({"class": "retired", "state": "RETIRED", "retiredReason": retired,
                             "check": {}})
                census["retired"] += 1
                rows.append(base)
                continue
            run = entry.get("run")
            if run is None:
                state = entry.get("state") or "PENDING"
                base.update({"class": "declared", "state": state, "check": {}})
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
            pending_migration = False

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

                if SWIFTUI_DOC in stripped:
                    pending_migration = True
                residual.append(stripped)

            # `true` is the identity of `&&`, so the placeholders left by every
            # converted clause come straight back out. Nothing is reordered.
            kept = [c for c in residual if c.strip() != "true"]
            shell = " && ".join(kept) if kept else None

            if prior_phases:
                base.update({
                    "class": "prior-phases",
                    "check": {"priorPhases": True},
                    "state": None,
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
            base["check"] = check
            base["state"] = None
            if pending_migration and not migration_ready:
                base["pendingMigration"] = SWIFTUI_DOC
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
        "phases": phases,
        "producers": sorted(producers.by_id.values(), key=lambda p: p["id"]),
        "rows": rows,
    }
    with open(args.out, "w") as fh:
        json.dump(graph, fh, indent=1, sort_keys=True, ensure_ascii=False)
        fh.write("\n")

    graph["unresolvedPatterns"] = unresolved
    write_census(args.census, graph, census, resolved_patterns, resolved_ids, migration_ready)
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
                 migration_ready: bool) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    rows = graph["rows"]
    by_phase: dict[str, int] = {}
    for r in rows:
        by_phase[r["phase"]] = by_phase.get(r["phase"], 0) + 1
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
        f"| retired | {census['retired']} | the row's subject left the product tree in this stage (workstream K); reasons below |",
        f"| pending-migration | {census['pending-migration']} | the row pins `docs/reference/swiftui-parity.md`, which workstream E1 is moving; repointed when `artifacts/distribution-readiness/swiftui-migration.md` lands |",
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
    for p in graph["phases"]:
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


if __name__ == "__main__":
    sys.exit(main())
