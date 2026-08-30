#!/usr/bin/env python3
"""D9 — prove the new verification path fails where the old one failed.

    python3 tools/lune/verify/mutation_parity.py --prepare        build the scratch tree
    python3 tools/lune/verify/mutation_parity.py --list
    python3 tools/lune/verify/mutation_parity.py --run M1 M2 …    (default: all)

WHY A SCRATCH TREE AND NOT THIS ONE
-----------------------------------
Every mutation here is a deliberate defect — a broken expectation, a deleted
`require`, a planted brand word. Six agents share this working tree, and
`tools/commit_isolated.py` filters by HUNK, so a sibling committing the file a
mutation is sitting in would commit the mutation with it. The window is the
length of a suite run. So the corpus runs in a copy at
`/tmp/facet-mutation-parity/GameStudio/ui/Facet`, laid out with that exact
prefix and a `games` symlink beside it so `../../../games/RascalRally/code`
still resolves and the Rascal Rally rows mean what they mean here.

HOW A MUTATION IS JUDGED
------------------------
Baseline first: the phase must PASS on both paths before the mutation, or the
mutation proves nothing about that phase. Then apply, run both paths, restore,
and record the four exit codes. A mutation is PARITY when both paths were green
before and red after; NEW-ONLY when it is a defect the old system had no concept
of (a corrupted result file, a wrong evidence class) — those are marked, not
hidden.

  OLD path: lune run tools/lune/gate_legacy <phase>
  NEW path: tools/verify.sh full --gate <phase>
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time

REAL_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SCRATCH_BASE = "/tmp/facet-mutation-parity"
SCRATCH = os.path.join(SCRATCH_BASE, "GameStudio", "ui", "Facet")
GAMES = os.path.abspath(os.path.join(REAL_ROOT, "..", "..", "..", "games"))

ENV = dict(os.environ)
ENV["PATH"] = os.path.expanduser("~/.rokit/bin") + ":/opt/homebrew/bin:/usr/local/bin:" + ENV.get("PATH", "")


def sh(cmd, cwd=SCRATCH, timeout=3600):
    started = time.time()
    proc = subprocess.run(
        ["bash", "-c", cmd], cwd=cwd, capture_output=True, text=True, env=ENV, timeout=timeout
    )
    return proc.returncode, proc.stdout + proc.stderr, time.time() - started


def prepare():
    os.makedirs(SCRATCH_BASE, exist_ok=True)
    print(f"copying {REAL_ROOT} -> {SCRATCH} (this takes a minute)")
    subprocess.run(
        [
            "rsync", "-a", "--delete",
            "--exclude", "artifacts/verify/",
            "--exclude", "artifacts/suite_cache/",
            "--exclude", "build/",
            REAL_ROOT + "/", SCRATCH + "/",
        ],
        check=True,
    )
    link = os.path.join(SCRATCH_BASE, "games")
    if os.path.islink(link):
        os.remove(link)
    os.symlink(GAMES, link)
    print(f"symlinked {link} -> {GAMES}")
    print("warming the result store (one full run)")
    code, out, secs = sh("tools/verify.sh full")
    print(f"  warm-up exit={code} in {secs:.0f}s")
    print(out[-1500:])


# ---------------------------------------------------------------------------
# the corpus
# ---------------------------------------------------------------------------


def _edit(path, old, new):
    full = os.path.join(SCRATCH, path)
    with open(full) as fh:
        text = fh.read()
    assert old in text, f"{path}: anchor not found — {old[:60]!r}"
    with open(full, "w") as fh:
        fh.write(text.replace(old, new, 1))


def _append(path, text):
    with open(os.path.join(SCRATCH, path), "a") as fh:
        fh.write(text)


def _save(paths):
    return {p: open(os.path.join(SCRATCH, p), "rb").read() for p in paths}


def _restore(saved):
    for p, data in saved.items():
        with open(os.path.join(SCRATCH, p), "wb") as fh:
            fh.write(data)


class Mutation:
    def __init__(self, mid, title, phase, kind, apply_fn, restore_fn, why, tier="full"):
        self.id = mid
        self.title = title
        self.phase = phase
        self.kind = kind  # "parity" (both paths) | "new-only"
        self.apply = apply_fn
        self.restore = restore_fn
        self.why = why
        self.tier = tier


def build_corpus():
    muts = []
    state = {}

    # ---- M1: a focus case's expectation is broken -------------------------
    FOCUS = "tests/focus.spec.luau"

    def m1_apply():
        state["m1"] = _save([FOCUS])
        with open(os.path.join(SCRATCH, FOCUS)) as fh:
            text = fh.read()
        # first toBe in the file, negated
        i = text.index(".toBe(")
        j = text.index(")", i)
        _edit(FOCUS, text[i : j + 1], ".toBe(\"a value nothing in this suite equals\")")

    muts.append(Mutation(
        "M1", "a focus case's expectation is broken", "phase-0-foundation", "parity",
        m1_apply, lambda: _restore(state["m1"]),
        "the plain failing-test case: a red case must redden every row that cites it",
    ))

    # ---- M2: a spec's require is deleted (the silent zero) ----------------
    RUN = "tests/run.luau"

    def m2_apply():
        state["m2"] = _save([RUN])
        _edit(RUN, 'require("./focus.spec")\n', "")

    muts.append(Mutation(
        "M2", "a spec's require is deleted from tests/run.luau", "api-architecture-consistency", "parity",
        m2_apply, lambda: _restore(state["m2"]),
        "an unregistered spec is a SILENT ZERO: the suite still exits 0 with a smaller number",
    ))

    # ---- M3: the suite is truncated by a main-thread yield -----------------
    SMOKE = "tests/smoke.spec.luau"

    def m3_apply():
        state["m3"] = _save([SMOKE])
        _append(SMOKE, '\nlocal __task = require("@lune/task")\n__task.wait(0.01)\n')

    muts.append(Mutation(
        "M3", "the suite is truncated by a main-thread yield", "phase-0-foundation", "parity",
        m3_apply, lambda: _restore(state["m3"]),
        "docs/lessons/lune-main-thread-yield-truncates-suite.md: the suite ends EARLY WITH EXIT 0",
    ))

    # ---- M4: a case an old grep and a new id both name is renamed ----------
    def m4_apply():
        state["m4"] = _save([FOCUS])
        with open(os.path.join(SCRATCH, FOCUS)) as fh:
            text = fh.read()
        i = text.index('it("')
        j = text.index('"', i + 4)
        _edit(FOCUS, text[i : j + 1], 'it("a name no gate row has ever heard of"')

    muts.append(Mutation(
        "M4", "an it() a gate row names is renamed", "phase-0-foundation", "parity",
        m4_apply, lambda: _restore(state["m4"]),
        "the changed-test-ID mutation: a missing id is a loud FAIL, never a satisfied lookup",
    ))

    # ---- M5: a stored result's payload is edited without its bodyHash ------
    def result_files():
        root = os.path.join(SCRATCH, "artifacts/verify/results/check_boundary")
        return [os.path.join(root, f) for f in os.listdir(root) if f.endswith(".json")]

    def m5_apply():
        f = result_files()[0]
        state["m5"] = {f: open(f, "rb").read()}
        d = json.load(open(f))
        d["payload"]["stdoutTail"] = "a line nobody printed"
        with open(f, "w") as fh:
            json.dump(d, fh)

    muts.append(Mutation(
        "M5", "a stored result is edited after it was written", "phase-0-foundation", "new-only",
        m5_apply, lambda: _restore_abs(state["m5"]),
        "bodyHash: a hand-edited result must be refused, not served",
    ))

    # ---- M6: the toolchain recorded in a result is changed -----------------
    def m6_apply():
        f = result_files()[0]
        state["m6"] = {f: open(f, "rb").read()}
        d = json.load(open(f))
        d["payload"]["toolchain"] = "rokit=x;lune=lune 0.0.0;stylua=x;python=x"
        # rehash so ONLY the toolchain rule can fire
        _rehash(d)
        with open(f, "w") as fh:
            json.dump(d, fh)

    muts.append(Mutation(
        "M6", "a result claims a different toolchain", "phase-0-foundation", "new-only",
        m6_apply, lambda: _restore_abs(state["m6"]),
        "re-hashed on purpose, so the toolchain rule is the only one that can fire",
    ))

    # ---- M7: an evidence file a row pins is deleted ------------------------
    EVIDENCE = "artifacts/navigation-and-menus/sweep-economy.md"

    def m7_apply():
        state["m7"] = _save([EVIDENCE])
        os.remove(os.path.join(SCRATCH, EVIDENCE))

    muts.append(Mutation(
        "M7", "an evidence document a row pins is deleted", "navigation-and-menus", "parity",
        m7_apply, lambda: _restore(state["m7"]),
        "a row whose evidence is gone must not pass on the strength of its other clauses",
    ))

    # ---- M8: a brand-drift word is planted --------------------------------
    DOC = "docs/guide/01-your-first-screen.md"

    def m8_apply():
        state["m8"] = _save([DOC])
        _append(DOC, "\nThis paragraph mentions SwiftUI, which the brand scan forbids here.\n")

    muts.append(Mutation(
        "M8", "a brand-drift word is planted in a public guide", "release-candidate-review", "parity",
        m8_apply, lambda: _restore(state["m8"]),
        "a scanner producer that fails must redden every row that asserts its exit 0",
    ))

    # ---- M9: a Fusion require is planted -----------------------------------
    SRC = "src/init.luau"

    def m9_apply():
        state["m9"] = _save([SRC])
        _append(SRC, '\n-- local Fusion = require("@Packages/Fusion")\nlocal _fusion = require("Fusion")\n')

    muts.append(Mutation(
        "M9", "a Fusion require is planted in src/", "distribution-readiness", "parity",
        m9_apply, lambda: _restore(state["m9"]),
        "workstream K's hard no-Fusion check, exercised as a producer",
    ))

    # ---- M10: a cache hit is attempted with a changed input ----------------
    muts.append(Mutation(
        "M10", "a stored result is offered for a changed input", "phase-0-foundation", "new-only",
        lambda: None, lambda: None,
        "identity: measured directly rather than through a gate (see the transcript)",
    ))

    # ---- M11: a partial suite result (fewer cases than registered) ---------
    muts.append(Mutation(
        "M11", "a partial suite result is offered", "phase-0-foundation", "new-only",
        lambda: None, lambda: None,
        "truncation: passed < registeredSpecs must be refused",
    ))

    # ---- M12: a perf-class result offered to a deterministic row ----------
    muts.append(Mutation(
        "M12", "a perf-class result is offered to a deterministic row", "phase-0-foundation", "new-only",
        lambda: None, lambda: None,
        "evidence classes are never upgraded by a headless cache",
    ))

    # ---- M13: an unregistered PENDING row is flipped to PASS ---------------
    GRAPH = "tools/lune/verify/graph.json"

    def m13_apply():
        state["m13"] = _save([GRAPH])
        d = json.load(open(os.path.join(SCRATCH, GRAPH)))
        for row in d["rows"]:
            if row["phase"] == "distribution-readiness" and row.get("state") == "PENDING":
                row["state"] = "PASS"
        with open(os.path.join(SCRATCH, GRAPH), "w") as fh:
            json.dump(d, fh)

    muts.append(Mutation(
        "M13", "a PENDING distribution-readiness row is flipped to PASS", "distribution-readiness", "new-only",
        m13_apply, lambda: _restore(state["m13"]),
        "a row may not claim PASS without a producer, an id, or an evidence pin behind it",
    ))

    return muts


def _restore_abs(saved):
    for p, data in saved.items():
        with open(p, "wb") as fh:
            fh.write(data)


def _rehash(record):
    """Recompute bodyHash the way tools/lune/verify/results.luau does."""
    body = {k: v for k, v in record.items() if k != "bodyHash"}
    record["bodyHash"] = _canonical_sha256(body)


def _canonical_sha256(value):
    import hashlib

    return hashlib.sha256(_canonical(value).encode()).hexdigest()


def _canonical(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        if float(value) == int(value) and abs(value) < 2 ** 53:
            return "%d" % int(value)
        return "%.17g" % value
    if isinstance(value, str):
        out = []
        for ch in value:
            if ch == '"':
                out.append('\\"')
            elif ch == "\\":
                out.append("\\\\")
            elif ch == "\n":
                out.append("\\n")
            elif ch == "\r":
                out.append("\\r")
            elif ch == "\t":
                out.append("\\t")
            elif ord(ch) < 0x20:
                out.append("\\u%04x" % ord(ch))
            else:
                out.append(ch)
        return '"' + "".join(out) + '"'
    if isinstance(value, list):
        return "[" + ",".join(_canonical(v) for v in value) + "]"
    if isinstance(value, dict):
        return "{" + ",".join(f"{_canonical(k)}:{_canonical(value[k])}" for k in sorted(value)) + "}"
    raise TypeError(type(value))


OLD = "lune run tools/lune/gate_legacy {phase}"
NEW = "tools/verify.sh full --gate {phase}"


def run_mutation(m, results):
    print(f"\n=== {m.id} — {m.title} ({m.kind}) ===")
    row = {"id": m.id, "title": m.title, "phase": m.phase, "kind": m.kind, "why": m.why}
    if m.kind == "parity":
        old_before, _, _ = sh(OLD.format(phase=m.phase))
        new_before, _, _ = sh(NEW.format(phase=m.phase))
        row["oldBefore"], row["newBefore"] = old_before, new_before
        print(f"  baseline: old={old_before} new={new_before}")
        m.apply()
        try:
            new_after, new_out, secs = sh(NEW.format(phase=m.phase))
            old_after, old_out, _ = sh(OLD.format(phase=m.phase))
        finally:
            m.restore()
        row["oldAfter"], row["newAfter"] = old_after, new_after
        row["newDetail"] = _first_failure(new_out)
        row["oldDetail"] = _first_failure(old_out)
        row["verdict"] = (
            "PARITY" if (old_before == 0 and new_before == 0 and old_after != 0 and new_after != 0)
            else "REVIEW"
        )
        print(f"  mutated : old={old_after} new={new_after}  -> {row['verdict']} ({secs:.0f}s)")
    else:
        row["verdict"] = "NEW-ONLY"
    results.append(row)
    return row


def _first_failure(out):
    for line in out.splitlines():
        stripped = _strip_ansi(line).strip()
        if stripped.startswith("✗") or "FAIL" in stripped:
            return stripped[:180]
    return ""


def _strip_ansi(s):
    import re

    return re.sub(r"\x1b\[[0-9;]*m", "", s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prepare", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--run", nargs="*", default=None)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    if args.prepare:
        prepare()
        return 0

    corpus = build_corpus()
    if args.list:
        for m in corpus:
            print(f"{m.id:4s} {m.kind:9s} {m.phase:32s} {m.title}")
        return 0

    if not os.path.isdir(SCRATCH):
        print("run --prepare first", file=sys.stderr)
        return 2

    wanted = set(args.run or [])
    results = []
    for m in corpus:
        if wanted and m.id not in wanted:
            continue
        run_mutation(m, results)

    out = args.out or "/tmp/mutation-parity-results.json"
    with open(out, "w") as fh:
        json.dump(results, fh, indent=1)
    print(f"\nwrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
