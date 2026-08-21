#!/usr/bin/env python3
"""Gate check: `Facet.Controls`'s fifteen typed signatures still carry their types.

WHY THIS EXISTS. Fifteen of the nineteen `Facet.Controls` entries declare a real
`spec` type, and they can only do it by holding a direct `local M = require(...)`
binding at the top of `src/init.luau` — so those fifteen requires are EAGER and
load-bearing for the types, and nothing else.

THE IDIOM THAT WOULD HAVE BOUGHT BOTH DOES NOT EXIST. An earlier draft of this
file claimed the requires were deferred into their closures with the parameter
types kept through `typeof(require(...))`, worth 831 KB. Both halves were
falsified by this check's own first run: a module's EXPORTED types enter scope
ONLY through a direct binding, and all four deferral spellings —
`type M = typeof(require(x))`, `local M = (nil :: any) :: typeof(require(x))`,
`local M: typeof(require(x)) = (nil :: any)`, and
`local M = if false then require(x) else (nil :: any)` — answer
`TypeError: Unknown type 'M.Spec'` under the pinned analyzer. The 831 KB was
subset arithmetic and was retracted with it
(artifacts/release-candidate-review/perf/requalification.md §7).

WHAT SHIPPED, and what it is worth: the FOUR entries that were already declared
`spec: any` (`Chip`, `VirtualList`, `VirtualGrid`, `AsyncImage`) need nothing from
their module at load, so their requires moved into their closures — **228 KB
[131..313]** of Lua heap, mode-matched. The other **632 KB** stays on the table
until the fifteen `export type Spec` declarations move to a module that costs
nothing to load, because deferring those fifteen means widening them to `any`.

Its entire justification is "the fifteen typed signatures survive", and until the
analyzer was pinned into `rokit.toml` (wave T15) nothing in this repository could
see a type. A change whose only claim is one no check can falsify is exactly what
this file stops: if one of the fifteen ever silently degrades to `spec: any` —
which is exactly what deferring its require would do — the authoring experience
the naming ADR bought disappears with no other symptom at all: the suite stays
green, the surface dump stays byte-identical, and autocomplete quietly stops
checking arguments.

IT IS NOT A LINT REGIME, ON PURPOSE. `luau-lsp analyze` walks the whole require
graph and this tree carries roughly 245 pre-existing diagnostics in modules
nobody has ever type-cleaned. Gating on those would be a different project and
would make this check impossible to keep green. So the rule is narrow and
mechanical: diagnostics whose file IS ONE OF THE TARGETS must be zero. Everything
in the dependency graph is reported by the analyzer and ignored here.

TWO HALVES, AND NEITHER IS SUFFICIENT ALONE.

  1. THE POSITIVE WITNESS (`tests/types/controls_witness.luau`) hands each entry a
     local declared with the control module's OWN `Spec` type. A parameter type
     that is some other type, or a narrower one, reddens it. A parameter type that
     WIDENED to `any` does not — `any` accepts everything, including this.

  2. THE NEGATIVE PROBE, below, is that missing direction. Each control is handed
     a NUMBER in a generated throwaway file. An entry carrying a real `Spec` must
     REJECT it; an entry that is `any` accepts it silently. The observed
     accept/reject split is compared against the split DECLARED in
     `src/init.luau`'s own source, so the two can never drift, and the four
     entries that are `any` today are additionally pinned BY NAME so the set
     cannot grow quietly.

Run:  python3 tools/check_types.py            (exit 0 = PASS)
      python3 tools/check_types.py --selftest (prove both halves bite)

Writes artifacts/release-candidate-review/perf/types.json.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ANALYZER = "luau-lsp"
PLATFORM = "standard"
INIT = "src/init.luau"
WITNESS = "tests/types/controls_witness.luau"
TARGETS = [INIT, WITNESS]
ARTIFACT = "artifacts/release-candidate-review/perf/types.json"

# The entries that take `spec: any` TODAY. This is a pre-existing fact about
# `src/init.luau`, not an endorsement: each of these four is a control whose spec
# was never given a published type. The set is pinned so it cannot GROW — which is
# precisely the failure a careless lazy-require refactor would cause — and so that
# narrowing one of them later is a deliberate edit here rather than a silent pass.
DECLARED_ANY = {"AsyncImage", "Chip", "VirtualGrid", "VirtualList"}


def _env():
    env = dict(os.environ)
    extra = [os.path.expanduser("~/.rokit/bin"), "/opt/homebrew/bin", "/usr/local/bin"]
    env["PATH"] = os.pathsep.join([p for p in extra if os.path.isdir(p)] + [env.get("PATH", "")])
    return env


def analyze(paths):
    """-> (list of diagnostic lines attributed to `paths`, whole stdout)."""
    r = subprocess.run(
        [ANALYZER, "analyze", "--platform", PLATFORM, *paths],
        capture_output=True,
        text=True,
        env=_env(),
    )
    out = r.stdout + r.stderr
    wanted = tuple(paths)
    own = [ln for ln in out.splitlines() if ln.startswith(wanted)]
    return own, out


def namespace_entries(source):
    """-> {entry name: the declared `spec:` annotation}, read from src/init.luau."""
    start = source.index("local Controls = table.freeze({")
    block = source[start:]
    block = block[: block.index("\n})")]
    return dict(re.findall(r"\n\t(\w+) = function\(core: any, spec: ([^)]+)\)", block))


def negative_probe(entries, tmpdir):
    """Hand every entry a NUMBER. -> {entry: True if the analyzer rejected it}."""
    lines = ['--!strict', 'local Facet = require("../../src")', "local core = Facet.newCore()"]
    order = sorted(entries)
    for i, name in enumerate(order):
        lines.append(f"local _n{i} = Facet.Controls.{name}(core, 42)")
    path = os.path.join("tests", "types", "_negative_probe.luau")
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    try:
        own, _ = analyze([path])
        rejected = set()
        for ln in own:
            m = re.match(r".*\((\d+),\d+\):", ln)
            if m is None:
                continue
            idx = int(m.group(1)) - 4  # 3 header lines, then one call per entry
            if 0 <= idx < len(order):
                rejected.add(order[idx])
        return {name: (name in rejected) for name in order}
    finally:
        os.unlink(path)
    _ = tmpdir


def run():
    problems = []
    notes = []

    if shutil.which(ANALYZER, path=_env()["PATH"]) is None:
        print(
            f"check_types: FAIL — `{ANALYZER}` is not on PATH. It is pinned in rokit.toml; "
            "run `rokit install` from the repository root."
        )
        return 1, {"status": "FAIL", "problems": ["analyzer missing"]}

    for t in TARGETS:
        if not os.path.isfile(t):
            problems.append(f"missing target {t}")
    if problems:
        return 1, {"status": "FAIL", "problems": problems}

    # ---- half 1: the targets themselves are clean --------------------------
    own, whole = analyze(TARGETS)
    for ln in own:
        problems.append(f"type error in a target file: {ln}")
    graph = len([ln for ln in whole.splitlines() if "TypeError" in ln or "SyntaxError" in ln])
    notes.append(
        f"{graph} diagnostic(s) in the require graph, IGNORED by design — this check gates "
        f"the {len(TARGETS)} target files only, never the tree"
    )

    # ---- half 2: the typed/any split is what src/init.luau declares ---------
    entries = namespace_entries(open(INIT).read())
    if len(entries) != 19:
        problems.append(f"src/init.luau declares {len(entries)} Controls entries, expected 19")
    declared_typed = {n for n, ann in entries.items() if ann.strip() != "any"}
    declared_any = set(entries) - declared_typed

    if declared_any != DECLARED_ANY:
        grew = declared_any - DECLARED_ANY
        shrank = DECLARED_ANY - declared_any
        if grew:
            problems.append(
                "these Controls entries lost their spec type and now take `any`: "
                + ", ".join(sorted(grew))
                + " — if that is intended, say so in DECLARED_ANY with a reason"
            )
        if shrank:
            problems.append(
                "these Controls entries GAINED a spec type: "
                + ", ".join(sorted(shrank))
                + " — good news; remove them from DECLARED_ANY"
            )

    with tempfile.TemporaryDirectory() as tmp:
        observed = negative_probe(entries, tmp)
    for name in sorted(entries):
        typed = name in declared_typed
        rejected = observed.get(name, False)
        if typed and not rejected:
            problems.append(
                f"`Facet.Controls.{name}` is DECLARED with a spec type but the analyzer "
                "accepted a number for it — the signature is not reaching the type checker "
                "(this is what deferring that control's `require` looks like: a module's "
                "exported types do not survive any deferral spelling, so the parameter has "
                "nowhere left to get its type from)"
            )
        if not typed and rejected:
            problems.append(
                f"`Facet.Controls.{name}` is declared `any` but the analyzer rejected a "
                "number for it — the declaration and the behaviour disagree"
            )

    report = {
        "schema": "facet-type-check/1",
        "status": "FAIL" if problems else "PASS",
        "analyzer": ANALYZER,
        "platform": PLATFORM,
        "targets": TARGETS,
        "entries": len(entries),
        "typedEntries": sorted(declared_typed),
        "anyEntries": sorted(declared_any),
        "negativeProbeRejected": sorted(n for n, v in observed.items() if v),
        "graphDiagnosticsIgnored": graph,
        "problems": problems,
        "notes": notes,
    }
    return (1 if problems else 0), report


def selftest():
    """Break each half on purpose and require the check to notice."""
    import shutil as sh

    backups = {p: open(p).read() for p in (INIT, WITNESS)}
    results = []
    try:
        code, _ = run()
        results.append(("unmutated", code == 0, "PASS expected"))

        # M1 — a Controls signature widened to `any`, which is exactly what
        # deferring that control's `require` into its closure would produce.
        s = backups[INIT].replace(
            "Table = function(core: any, spec: tableControl.Spec)",
            "Table = function(core: any, spec: any)",
            1,
        )
        assert s != backups[INIT], "M1 anchor missing"
        open(INIT, "w").write(s)
        code, rep = run()
        bit = code != 0 and any("Table" in p for p in rep["problems"])
        results.append(("M1 Controls.Table widened to `any`", bit, "FAIL expected"))
        open(INIT, "w").write(backups[INIT])

        # M2 — a Controls signature given the WRONG type. The witness hands it the
        # module's own Spec, so a different type reddens the witness itself.
        s = backups[INIT].replace(
            "Slider = function(core: any, spec: sliderControl.Spec)",
            "Slider = function(core: any, spec: tableControl.Spec)",
            1,
        )
        assert s != backups[INIT], "M2 anchor missing"
        open(INIT, "w").write(s)
        code, rep = run()
        bit = code != 0 and any(WITNESS in p for p in rep["problems"])
        results.append(("M2 Controls.Slider given the wrong Spec", bit, "FAIL expected"))
        open(INIT, "w").write(backups[INIT])

        # M3 — the witness stops exercising an entry. A witness that quietly shrank
        # would make every claim above narrower while failing nothing, which is the
        # way an instrument rots. It is caught, and by a mechanism worth naming: the
        # analyzer emits LINTS as well as type errors for the target files, so the
        # `Spec` local left behind reports `LocalUnused`. That is why this check
        # reads EVERY diagnostic attributed to a target rather than grepping for
        # `TypeError` — the lint is what makes the witness self-guarding.
        s = backups[WITNESS].replace(
            "local _rowactions = Facet.Controls.RowActions(core, rowActionsSpec)",
            "local _rowactions = Facet.Controls.RowActions(core, (nil :: any))",
            1,
        )
        assert s != backups[WITNESS], "M3 anchor missing"
        open(WITNESS, "w").write(s)
        code, rep = run()
        bit = code != 0 and any("LocalUnused" in p for p in rep["problems"])
        results.append(("M3 witness stops using a real Spec", bit, "FAIL expected"))
        open(WITNESS, "w").write(backups[WITNESS])
    finally:
        for p, text in backups.items():
            open(p, "w").write(text)
        _ = sh

    ok = all(bit for _label, bit, _want in results)
    print("check_types --selftest:", "PASS" if ok else "FAIL")
    for label, bit, want in results:
        print(f"  [{'ok' if bit else 'MISS'}] {label} ({want})")
    if ok:
        print(
            "  M1 is the shape a DEFERRED require leaves behind, M2 is a signature given the wrong\n"
            "  type, M3 is the witness itself decaying. The negative probe covers the direction\n"
            "  none of them do: it is GENERATED from `src/init.luau`'s own entry list, so it\n"
            "  cannot shrink while the namespace does not."
        )
    return 0 if ok else 1


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    code, report = run()
    os.makedirs(os.path.dirname(ARTIFACT), exist_ok=True)
    with open(ARTIFACT, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    if code == 0:
        print(
            f"check_types: PASS — {report['entries']} Controls entries "
            f"({len(report['typedEntries'])} typed, {len(report['anyEntries'])} declared `any`); "
            f"{len(TARGETS)} target files carry 0 diagnostics; "
            f"{report['graphDiagnosticsIgnored']} graph diagnostics ignored by design "
            f"-> {ARTIFACT}"
        )
    else:
        print("check_types: FAIL")
        for p in report["problems"]:
            print(f"  - {p}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
