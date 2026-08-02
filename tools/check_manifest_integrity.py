#!/usr/bin/env python3
"""Refuse a gate check that greps the test suite without anchoring to the PASS marker.

WHY THIS EXISTS (gate-integrity sweep 2026-07-29, defect D-1). `tests/lib/testkit.luau`
prints the case name on BOTH outcomes:

    ✓ modal traps navigation with wrap and restores previous focus on pop
    ✗ modal traps navigation with wrap and restores previous focus on pop

So `grep -q "<case name>"` proves the case is REGISTERED, not that it PASSES. Whether that
matters depends entirely on shell form:

  FORM A   out="$(./run-tests.sh 2>&1)" && echo "$out" | grep -q "X"
           SAFE. The command-substitution assignment carries run-tests.sh's exit code, so
           `&&` short-circuits and the check reddens on any suite failure.

  FORM B   ./run-tests.sh 2>&1 | grep -q 'X'
           BLIND. A pipeline's exit status is the LAST command's — grep's. The suite's
           exit 1 is masked, and the check stays green while the behaviour it names is
           broken. Twenty-six checks shipped in this shape; `phase-0-foundation`'s
           modal-focus-spike was proven green against a deliberately broken focus graph.

The fix in both forms is to anchor the pattern to the pass marker (`✓.*<name>`), which is
what this script enforces so the class cannot come back. Anchoring also refuses a grep
aimed at a describe-BLOCK header rather than a case name — headers print without a marker,
and five such checks (including one greping the bare word `examples`) were found unable to
fail at all.

Run: tools/check_manifest_integrity.py   (exit 0 = clean)
"""

import re
import subprocess
import sys
import json

MANIFEST = "tools/lune/gate_manifest.luau"

DUMPER = """
local serde = require("@lune/serde")
local manifest = require("./gate_manifest")
local out = {}
for gate, checks in manifest do
\tfor _, c in checks do
\t\tif c.run ~= nil then
\t\t\ttable.insert(out, { gate = gate, name = c.name, run = c.run })
\t\tend
\tend
end
print(serde.encode("json", out))
"""

# Both shapes that pipe the suite transcript into grep. Captures the quote and the pattern.
GREP_FORMS = (
    re.compile(r'echo "\$out" \| grep -q (["\'])(.*?)\1'),
    re.compile(r"\./run-tests\.sh 2>&1 \| grep -q ([\"'])(.*?)\1"),
)

MARKER = "✓"


def load_checks():
    """Read run strings from the PARSED manifest, never by regexing the Lua source.

    Lua escape handling differs between quote styles (a `\\"` means different things in
    '...' and "..."), and hand-unescaping is exactly how this sweep first drew a wrong
    conclusion. Let Luau do it.
    """
    path = "tools/lune/_check_manifest_integrity_dump.luau"
    with open(path, "w") as fh:
        fh.write(DUMPER)
    try:
        proc = subprocess.run(
            ["lune", "run", "tools/lune/_check_manifest_integrity_dump"],
            capture_output=True,
            text=True,
        )
    finally:
        import os

        os.remove(path)

    if proc.returncode != 0:
        print(f"check_manifest_integrity: manifest did not load\n{proc.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(proc.stdout)


def main():
    problems = []
    checked = 0

    for entry in load_checks():
        run = entry["run"]
        if "run-tests.sh" not in run:
            continue
        for form in GREP_FORMS:
            for _, pattern in form.findall(run):
                checked += 1
                if MARKER in pattern:
                    continue
                problems.append(
                    f"[{entry['gate']}] {entry['name']}: suite grep is not anchored to the "
                    f"pass marker — {pattern[:70]!r}\n"
                    f"      a failing case still prints its name, so this matches either way; "
                    f"use \"{MARKER}.*<case name>\""
                )

    if problems:
        print(
            f"check_manifest_integrity: {len(problems)} unanchored suite grep(s)\n",
            file=sys.stderr,
        )
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1

    print(f"check_manifest_integrity: {checked} suite greps, all anchored to the pass marker")
    return 0


if __name__ == "__main__":
    sys.exit(main())
