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

    FOCUS = "tests/focus.spec.luau"
    RUN = "tests/run.luau"
    SMOKE = "tests/smoke.spec.luau"
    GRAPH = "tools/lune/verify/graph.json"
    DOC = "docs/guide/01-your-first-screen.md"
    SRC = "src/init.luau"

    def result_file(producer="check_boundary"):
        root = os.path.join(SCRATCH, "artifacts/verify/results", producer)
        files = [os.path.join(root, f) for f in os.listdir(root) if f.endswith(".json")]
        return files[0]

    # ---- M1: a focus case's expectation is broken -------------------------
    def m1_apply():
        state["m1"] = _save([FOCUS])
        _edit(FOCUS, ".toBeTruthy()", ".toBeFalsy()")

    muts.append(Mutation(
        "M1", "a focus case's expectation is broken", "phase-0-foundation", "parity",
        m1_apply, lambda: _restore(state["m1"]),
        "the plain failing-test case: a red case must redden every row that cites it",
    ))

    # ---- M2: a spec's require is deleted (the silent zero) ----------------
    def m2_apply():
        state["m2"] = _save([RUN])
        _edit(RUN, 'require("./focus.spec")\n', "")

    muts.append(Mutation(
        "M2", "a spec's require is deleted from tests/run.luau", "api-architecture-consistency", "parity",
        m2_apply, lambda: _restore(state["m2"]),
        "an unregistered spec is a SILENT ZERO: the suite still exits 0, with a smaller number",
    ))

    # ---- M3: the suite is truncated by a main-thread yield -----------------
    def m3_apply():
        state["m3"] = _save([SMOKE])
        _append(SMOKE, '\nlocal __t = require("@lune/task")\n__t.wait(0.01)\n')

    muts.append(Mutation(
        "M3", "the suite is truncated by a main-thread yield", "phase-0-foundation", "parity",
        m3_apply, lambda: _restore(state["m3"]),
        "a main-thread yield ends the suite EARLY AND WITH EXIT 0, so the exit code proves nothing",
    ))

    # ---- M4: a case a gate row names is renamed ----------------------------
    def m4_apply():
        state["m4"] = _save([FOCUS])
        with open(os.path.join(SCRATCH, GRAPH)) as fh:
            graph = json.load(fh)
        cited = set()
        for row in graph["rows"]:
            for cid in (row.get("check") or {}).get("resultIds", []):
                if cid.startswith("focus::"):
                    cited.add(cid.rsplit("::", 1)[1])
        text = open(os.path.join(SCRATCH, FOCUS)).read()
        for name in sorted(cited):
            if f'it("{name}"' in text:
                _edit(FOCUS, f'it("{name}"', 'it("a name no gate row has ever heard of"')
                state["m4_name"] = name
                return
        raise AssertionError("no cited focus case found to rename")

    muts.append(Mutation(
        "M4", "an it() a gate row names is renamed", "phase-0-foundation", "parity",
        m4_apply, lambda: _restore(state["m4"]),
        "the changed-test-ID mutation: a missing id is a loud FAIL, never a satisfied lookup",
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
    def m8_apply():
        state["m8"] = _save([DOC])
        _append(DOC, "\nThis paragraph names a platform the product-language guard forbids: iPhone.\n")

    muts.append(Mutation(
        "M8", "a forbidden platform name is planted in a public guide", "release-candidate-review", "parity",
        m8_apply, lambda: _restore(state["m8"]),
        "a scanner producer that fails must redden every row that asserts its exit 0",
    ))

    # ---- M9: a Fusion require is planted -----------------------------------
    def m9_apply():
        state["m9"] = _save([SRC])
        _append(SRC, '\nlocal _bakeoff = require("Fusion")\n')

    muts.append(Mutation(
        "M9", "a require of the excised third-party core is planted in src/", "distribution-readiness", "parity",
        m9_apply, lambda: _restore(state["m9"]),
        "the hard no-third-party-core check, exercised as a producer",
    ))

    # ---- M13: a PENDING row is flipped to PASS -----------------------------
    def m13_apply():
        state["m13"] = _save([GRAPH])
        d = json.load(open(os.path.join(SCRATCH, GRAPH)))
        for row in d["rows"]:
            if row["phase"] == "distribution-readiness" and row.get("state") == "PENDING":
                row["state"] = "PASS"
                row["check"] = {}
        with open(os.path.join(SCRATCH, GRAPH), "w") as fh:
            json.dump(d, fh)

    muts.append(Mutation(
        "M13", "a PENDING row is flipped to PASS with nothing behind it", "distribution-readiness", "parity",
        m13_apply, lambda: _restore(state["m13"]),
        "the cheapest way to fake a gate; only the new path has a graph to fake",
    ))

    # ---- store-level mutations (the new path is the only one with a store) --
    def store_mutation(mid, title, why, mutate):
        def apply_fn():
            f = result_file()
            state[mid] = {f: open(f, "rb").read()}
            d = json.load(open(f))
            mutate(d)
            with open(f, "w") as fh:
                json.dump(d, fh)
        return Mutation(mid, title, "phase-0-foundation", "new-only", apply_fn,
                        lambda: _restore_abs(state[mid]), why)

    def edit_payload(d):
        d["payload"]["stdoutTail"] = "a line nobody printed"

    def stale_toolchain(d):
        d["payload"]["toolchain"] = "rokit=x;lune=lune 0.0.0;stylua=x;python=x"
        _rehash(d)

    def wrong_class(d):
        d["environmentClass"] = "perf"
        _rehash(d)

    muts.append(store_mutation("M5", "a stored result is edited after it was written",
                               "bodyHash: a hand-edited result must be refused, not served", edit_payload))
    muts.append(store_mutation("M6", "a result claims a different toolchain",
                               "re-hashed on purpose, so the toolchain rule is the only one that can fire",
                               stale_toolchain))
    muts.append(store_mutation("M12", "a perf-class result is offered to a deterministic row",
                               "re-hashed on purpose; evidence classes are never upgraded by a headless cache",
                               wrong_class))

    # ---- M10: a cache hit attempted with a changed input -------------------
    def m10_apply():
        target = "src/init.luau"
        state["m10"] = _save([target])
        _append(target, "\n-- a comment that changes nothing but the content hash\n")

    muts.append(Mutation(
        "M10", "a stored result is offered for a changed input", "phase-0-foundation", "reuse",
        m10_apply, lambda: _restore(state["m10"]),
        "identity: the suite's stored result must NOT be reused after a source edit",
    ))

    # ---- M11: a partial suite result --------------------------------------
    def m11_apply():
        f = result_file("suite")
        state["M11"] = {f: open(f, "rb").read()}
        d = json.load(open(f))
        cases = d["payload"]["results"]["cases"]
        d["payload"]["results"]["cases"] = cases[: len(cases) // 4]
        d["payload"]["results"]["passed"] = len(d["payload"]["results"]["cases"])
        d["payload"]["results"]["reportedSpecs"] = 3
        _rehash(d)
        with open(f, "w") as fh:
            json.dump(d, fh)

    muts.append(Mutation(
        "M11", "a partial suite result is offered", "phase-0-foundation", "new-only",
        m11_apply, lambda: _restore_abs(state["M11"]),
        "truncation: fewer specs reported than registered must be refused",
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
NEW = "tools/verify.sh full --gate {phase} --explain"


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
    elif m.kind == "reuse":
        # The question is not "does it go red" but "does it REFUSE TO REUSE".
        m.apply()
        try:
            code, out, secs = sh("tools/verify.sh full --gate " + m.phase + " --explain")
            record = json.load(open(os.path.join(SCRATCH, "artifacts/verify/latest-full.json")))
            suite = next((p for p in record["producers"] if p["id"] == "suite"), None)
            row["reused"] = bool(suite and suite["reused"])
            row["reason"] = (suite or {}).get("reason", "")
            row["verdict"] = "REFUSED-REUSE" if not row["reused"] else "REVIEW"
            print(f"  suite reused={row['reused']} reason={row['reason'][:80]} ({secs:.0f}s)")
        finally:
            m.restore()
    else:
        # A store-level defect: run the new path and require it to notice.
        before, _, _ = sh(NEW.format(phase=m.phase))
        row["newBefore"] = before
        m.apply()
        try:
            after, out, _ = sh(NEW.format(phase=m.phase))
            row["newAfter"] = after
            row["newDetail"] = _first_failure(out)
            row["reason"] = _reuse_reason(out)
        finally:
            m.restore()
        # A refused result is REPORTED and the producer re-runs, so the run may
        # still end green — what must be true is that it was NOT SERVED.
        row["verdict"] = "REFUSED" if row.get("reason") else "REVIEW"
        print(f"  new: before={before} after={row['newAfter']} refusal={row.get('reason', '')[:80]}")
    results.append(row)
    return row


def _reuse_reason(out):
    for line in out.splitlines():
        stripped = _strip_ansi(line).strip()
        if stripped.startswith("invalidation:") and "no stored result" not in stripped:
            return stripped
        if "body hash mismatch" in stripped or "different toolchain" in stripped or "evidence classes are never upgraded" in stripped or "silent zero" in stripped or "partial run" in stripped:
            return stripped
    return ""


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
