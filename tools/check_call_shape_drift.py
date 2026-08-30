#!/usr/bin/env python3
"""check_call_shape_drift — no NEW composite control is created the old way.

The `Controls` namespace moved every composite control to
`Facet.Controls.<Name>(core, spec)`.
The nineteen `Facet.new<Name>(Facet, core, spec)` builders still work and are
declared in `Facet.DEPRECATIONS` with `removeNoEarlierThan = 0.12.0`, so nothing
published breaks — but a compatible migration that leaves the old form
mechanically undetectable is a migration that un-does itself: the next author
copies the nearest call site, and the nearest call site is whatever survived.

WHAT IS MATCHED, over `.luau` sources tracked by the framework repo and by the
Rascal Rally consumer:

  1. `<expr>.new<UpperCamel>(<expr>,`     — the two-argument spelling, whatever
     the library is bound to locally (`Facet`, `ctx.Facet`, an alias); the
     first argument must be the SAME expression the call is made on, which is
     precisely the "hands itself to its own builder" shape and nothing else.
  2. `:new<UpperCamel>(`                  — the colon spelling, which would put
     the library in `self` and make the same mistake invisible to (1).

WHY NOT `.md` TOO. The reference and the ADRs are REQUIRED to name the retiring
spelling — `docs/reference/api.md` marks all nineteen "deprecated" beside their
own name, and `tests/api_surface.spec.luau`'s ENF-3 rule fails the suite if that
marking disappears. Prose is governed there; this guard governs code.

Every permitted match lives in ALLOWLIST with a reason and a removal rule.

`--selftest` proves the guard can fail: it plants one old-form call, one
colon-spelling call and one WRAPPED old-form call (the shape stylua produces for
a long argument list, and the one the line-based first version let through)
inside scanned trees, requires all three to go red at the right line numbers,
removes them, and requires the restored tree to pass. It also plants an
allowlisted file's pattern in a NON-allowlisted file, to prove the allowlist is
scoped to its paths. `scan_file`'s docstring names the two shapes this scan
still cannot see and why neither is hiding anything today.

Usage:  python3 tools/check_call_shape_drift.py [--selftest]
Exit 0 = clean; 1 = drift found; 2 = environment failure.
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
STUDIO_ROOT = os.path.abspath(os.path.join(REPO, "..", "..", ".."))
RR = os.path.join(STUDIO_ROOT, "games", "RascalRally", "code")

# (1) `x.newFoo(x,` — the first argument is the very expression the call is made
# on. `\1` is what makes this specific: `Facet.newTable(core, …)` is not a match,
# and neither is `row_actions.newCoordinator(Facet.newCore())`.
# `\s` already spans newlines, so these match a wrapped call once the scan
# stops chopping the source into lines (see `scan_file`).
TWO_ARG = re.compile(r"([A-Za-z_][A-Za-z0-9_.]*)\.new([A-Z][A-Za-z0-9_]*)\s*\(\s*\1\s*,")
# (2) the colon spelling, which hides the library in `self`
COLON = re.compile(r":new[A-Z][A-Za-z0-9_]*\s*\(")

# Frozen-evidence trees: never scanned. Structural, not per-file — a gate
# artifact records the call shape it was earned under.
EXCLUDED_TREES = (
    "artifacts/",
    "docs/superpowers/",
    ".superpowers/",
)

# (path-prefix-or-exact, reason, removal rule). `rr:` prefixes a path in the
# Rascal Rally repo.
ALLOWLIST = [
    ("tests/controls_namespace.spec.luau",
     "the compatibility arm: every control is built BOTH ways from one spec and "
     "the two results compared, which is what proves the old form still works",
     "when the nineteen ledger rows reach removeNoEarlierThan and the old form goes"),
    ("tools/check_call_shape_drift.py",
     "the guard's own match data and selftest plants",
     "never (it IS the guard)"),
    ("tools/lune/_probe_t15_controls.luau",
     "the call-shape cost probe: it MEASURES the namespace form against the old "
     "two-argument form it replaced, so it has to call both. Deleting the old-form "
     "arm would delete the comparison, which is the whole instrument (wave T15 "
     "item 2: the closure hop is +0.000004 ms, proved <= noise)",
     "when the nineteen ledger rows reach removeNoEarlierThan and the old form goes "
     "— at which point there is nothing left to compare and the probe goes with it"),
]


def tracked(repo):
    out = subprocess.run(["git", "-C", repo, "ls-files"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print(f"check_call_shape_drift: FAIL_ENVIRONMENT git ls-files in {repo}")
        sys.exit(2)
    return out.stdout.splitlines()


def allowed(scope_path):
    for path, _reason, _removal in ALLOWLIST:
        if scope_path == path or scope_path.startswith(path.rstrip("/") + "/"):
            return True
    return False


def scan_file(abs_path, scope_path, hits):
    """Scan one file WHOLE, not line by line.

    WHY WHOLE (R5 review §6-2). The first version iterated lines and applied
    the patterns to each, so a call wrapped across lines was invisible:

        local x = Facet.newTable(
            Facet,
            core,
            {}
        )

    passed, while the identical call on one line failed. stylua wrapping a long
    call is the realistic way in, which makes the blind spot one the formatter
    can open by itself. The source is read once and matched with the patterns
    compiled `re.DOTALL`, and the line number is recovered by counting newlines
    up to the match, so the message still points at the call's first line.

    LIMITS, NAMED. Two shapes are still invisible and neither is a bug this
    scan can fix without a Luau parser:

      * DYNAMIC construction — `Facet[name](Facet, ...)` builds a composite
        without ever writing its name. `tests/spec_guard_sweep.spec.luau` does
        this deliberately over all 19 to prove the deprecated builders still
        work, which is the one thing that MUST keep constructing the old way.
      * An ALIASED receiver — `local F = Facet; F.newTable(Facet, ...)`. The
        backreference is what makes the two-argument pattern specific (it is
        what tells `x.newFoo(x, ...)` from `x.newFoo(core, ...)`), and an alias
        defeats it by construction.

    Measured at the time of writing: a DOTALL scan of every `.luau` in both
    repositories finds zero old-form calls, so nothing is hiding behind either
    limit today.
    """
    if allowed(scope_path):
        return
    try:
        with open(abs_path, encoding="utf-8", errors="replace") as fh:
            source = fh.read()
    except OSError:
        return

    def line_of(index):
        return source.count("\n", 0, index) + 1

    for m in TWO_ARG.finditer(source):
        hits.append(f"{scope_path}:{line_of(m.start())}: old two-argument form "
                    f"`{m.group(1)}.new{m.group(2)}({m.group(1)}, …)` — "
                    f"write `{m.group(1)}.Controls.{m.group(2)}(core, spec)` "
                    f"")
    for m in COLON.finditer(source):
        hits.append(f"{scope_path}:{line_of(m.start())}: colon spelling "
                    f"`:new<Name>(` puts the library in `self` — write "
                    f"`Facet.Controls.<Name>(core, spec)`")


def scan_repo(repo, prefix, hits):
    for rel in tracked(repo):
        p = rel.replace("\\", "/")
        if any(p.startswith(t) or f"/{t}" in p for t in EXCLUDED_TREES):
            continue
        if not p.endswith(".luau"):
            continue
        scan_file(os.path.join(repo, rel), prefix + p if prefix else p, hits)


def run_scan():
    hits = []
    scan_repo(REPO, "", hits)
    scan_repo(RR, "rr:", hits)
    return hits


def selftest():
    two_arg = os.path.join(REPO, "src", "call_shape_probe_tmp.luau")
    colon = os.path.join(REPO, "tests", "call_shape_colon_probe_tmp.luau")
    scoped = os.path.join(REPO, "src", "call_shape_allow_probe_tmp.luau")
    wrapped = os.path.join(REPO, "src", "call_shape_wrapped_probe_tmp.luau")
    try:
        with open(two_arg, "w") as f:
            f.write("local x = Facet.newTable(Facet, core, {})\nreturn x\n")
        with open(colon, "w") as f:
            f.write("local x = Facet:newSlider(core, {})\nreturn x\n")
        # the allowlisted SPEC's own pattern, in a file that is not allowlisted
        with open(scoped, "w") as f:
            f.write("local old = Facet.newLabel(Facet, core, {})\nreturn old\n")
        #[[ THE WRAPPED CALL (R5 review §6-2). The same construction stylua would
        #   produce for a long argument list. The line-based scan this replaced
        #   passed it while failing the identical call on one line, which made the
        #   FORMATTER a way through the guard. Planted here so the whole-file scan
        #   can never quietly go back to being line-based. ]]
        with open(wrapped, "w") as f:
            f.write("local x = Facet.newTable(\n\tFacet,\n\tcore,\n\t{}\n)\nreturn x\n")
        hits = []
        scan_file(two_arg, "src/call_shape_probe_tmp.luau", hits)
        scan_file(colon, "tests/call_shape_colon_probe_tmp.luau", hits)
        scan_file(scoped, "src/call_shape_allow_probe_tmp.luau", hits)
        scan_file(wrapped, "src/call_shape_wrapped_probe_tmp.luau", hits)
        # ...and the same content INSIDE the allowlisted path must be tolerated
        tolerated = []
        scan_file(two_arg, "tests/controls_namespace.spec.luau", tolerated)
        wrapped_hits = [h for h in hits if "call_shape_wrapped_probe_tmp" in h]
        # ...and it must point at the call's FIRST line, not at the file's start
        wrapped_line_ok = len(wrapped_hits) == 1 and wrapped_hits[0].split(":")[1] == "1"
        if (len([h for h in hits if "src/call_shape_probe_tmp" in h]) != 1
                or len([h for h in hits if "colon spelling" in h]) != 1
                or len([h for h in hits if "call_shape_allow_probe_tmp" in h]) != 1
                or not wrapped_line_ok
                or tolerated):
            print("check_call_shape_drift: SELFTEST FAIL — a planted violation "
                  "survived, or the allowlist did not apply to its own path")
            print("\n".join(hits + [f"tolerated: {t}" for t in tolerated]))
            return 1
    finally:
        for p in (two_arg, colon, scoped, wrapped):
            if os.path.exists(p):
                os.unlink(p)
    clean = run_scan()
    if clean:
        print("check_call_shape_drift: SELFTEST FAIL — restored tree not clean:")
        print("\n".join(clean[:20]))
        return 1
    print("check_call_shape_drift: SELFTEST PASS — planted two-argument call, "
          "planted colon call, planted WRAPPED call (reported at its first line), "
          "and out-of-scope allowlisted pattern each caught; the allowlisted path "
          "tolerates the same content; restored tree clean")
    return 0


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    hits = run_scan()
    if hits:
        print(f"check_call_shape_drift: FAIL — {len(hits)} old-form composite "
              "call site(s) outside the allowlist:")
        for h in hits[:60]:
            print("  " + h)
        if len(hits) > 60:
            print(f"  … and {len(hits) - 60} more")
        sys.exit(1)
    print("check_call_shape_drift: PASS — every composite control is created as "
          "Facet.Controls.<Name>(core, spec); the nineteen deprecated "
          "builders keep working and have no live call site outside the "
          "compatibility spec")


if __name__ == "__main__":
    main()
