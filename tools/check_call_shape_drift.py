#!/usr/bin/env python3
"""Reject removed flat control-constructor calls in maintained Luau sources.

Controls use Facet.Controls.<Name>(core, spec) for explicit handles, or
app.controls.<Name>(spec) in a Compose-mounted application. This check catches
receivers passed to themselves and colon calls, including wrapped calls.
Run with --selftest to verify rejection and allowlist scope.
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
    ("tools/check_call_shape_drift.py", "the guard's own match data", "never"),
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
        this dynamically; runtime API tests check the exported constructor set.
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


#[[ THE CONSUMING GAME IS EXTERNAL (public-clone honesty round, 2026-08-31).
#   This scan reaches into the consuming game's checkout because a call shape
#   that drifted there is drift too. On a public clone that checkout does not
#   exist, and `git ls-files` in a directory that is not there exited 2 -- a
#   crash, not a verdict. The half that can run, runs, and the half that cannot
#   is NAMED, so an unscanned tree never reads as a clean one. ]]
SKIPPED_TREES = []


def run_scan():
    hits = []
    del SKIPPED_TREES[:]
    scan_repo(REPO, "", hits)
    if os.path.isdir(RR) and subprocess.run(
        ["git", "-C", RR, "ls-files"], capture_output=True, text=True
    ).returncode == 0:
        scan_repo(RR, "rr:", hits)
    else:
        SKIPPED_TREES.append("the consuming game's checkout")
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
        scan_file(two_arg, "tools/check_call_shape_drift.py", tolerated)
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
          "the maintained control constructors; no removed flat builders are called")
    for tree in SKIPPED_TREES:
        print(f"  NOT SCANNED: {tree} is not beside this checkout — that half of "
              "the claim is unproved here, and says so rather than passing quietly")


if __name__ == "__main__":
    main()
