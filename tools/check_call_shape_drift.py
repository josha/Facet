#!/usr/bin/env python3
"""check_call_shape_drift — no NEW composite control is created the old way.

ADR-0037 moved every composite control to `Facet.Controls.<Name>(core, spec)`.
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

`--selftest` proves the guard can fail: it plants one old-form call and one
colon-spelling call inside scanned trees, requires both to go red, removes them,
and requires the restored tree to pass. It also plants an allowlisted file's
pattern in a NON-allowlisted file, to prove the allowlist is scoped to its paths.

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
TWO_ARG = re.compile(r"([A-Za-z_][A-Za-z0-9_.]*)\.new([A-Z][A-Za-z0-9_]*)\(\s*\1\s*,")
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
    if allowed(scope_path):
        return
    try:
        with open(abs_path, encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh, 1):
                m = TWO_ARG.search(line)
                if m:
                    hits.append(f"{scope_path}:{n}: old two-argument form "
                                f"`{m.group(1)}.new{m.group(2)}({m.group(1)}, …)` — "
                                f"write `{m.group(1)}.Controls.{m.group(2)}(core, spec)` "
                                f"(ADR-0037)")
                    continue
                if COLON.search(line):
                    hits.append(f"{scope_path}:{n}: colon spelling `:new<Name>(` puts "
                                f"the library in `self` — write "
                                f"`Facet.Controls.<Name>(core, spec)` (ADR-0037)")
    except OSError:
        pass


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
    try:
        with open(two_arg, "w") as f:
            f.write("local x = Facet.newTable(Facet, core, {})\nreturn x\n")
        with open(colon, "w") as f:
            f.write("local x = Facet:newSlider(core, {})\nreturn x\n")
        # the allowlisted SPEC's own pattern, in a file that is not allowlisted
        with open(scoped, "w") as f:
            f.write("local old = Facet.newLabel(Facet, core, {})\nreturn old\n")
        hits = []
        scan_file(two_arg, "src/call_shape_probe_tmp.luau", hits)
        scan_file(colon, "tests/call_shape_colon_probe_tmp.luau", hits)
        scan_file(scoped, "src/call_shape_allow_probe_tmp.luau", hits)
        # ...and the same content INSIDE the allowlisted path must be tolerated
        tolerated = []
        scan_file(two_arg, "tests/controls_namespace.spec.luau", tolerated)
        if (len([h for h in hits if "call_shape_probe_tmp" in h]) != 1
                or len([h for h in hits if "colon spelling" in h]) != 1
                or len([h for h in hits if "call_shape_allow_probe_tmp" in h]) != 1
                or tolerated):
            print("check_call_shape_drift: SELFTEST FAIL — a planted violation "
                  "survived, or the allowlist did not apply to its own path")
            print("\n".join(hits + [f"tolerated: {t}" for t in tolerated]))
            return 1
    finally:
        for p in (two_arg, colon, scoped):
            if os.path.exists(p):
                os.unlink(p)
    clean = run_scan()
    if clean:
        print("check_call_shape_drift: SELFTEST FAIL — restored tree not clean:")
        print("\n".join(clean[:20]))
        return 1
    print("check_call_shape_drift: SELFTEST PASS — planted two-argument call, "
          "planted colon call, and out-of-scope allowlisted pattern each caught; "
          "the allowlisted path tolerates the same content; restored tree clean")
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
          "Facet.Controls.<Name>(core, spec) (ADR-0037); the nineteen deprecated "
          "builders keep working and have no live call site outside the "
          "compatibility spec")


if __name__ == "__main__":
    main()
