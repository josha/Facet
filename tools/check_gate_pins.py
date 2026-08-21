#!/usr/bin/env python3
"""check_gate_pins — a gate row's file pins must still match the tree.

A gate row proves something by grepping a fixed sentence out of a file:
`grep -qF "the words" src/controls/picker.luau`. Rewrite that sentence and the
row stops proving anything — it fails, and the failure names a gate rather than
the edit that caused it. Worse, a NEGATED pin (`! grep -qF …`) starts passing
for the wrong reason, silently.

This reads every literal file pin out of `tools/lune/gate_manifest.luau` and
checks it against the working tree without running a single gate:

  * `grep -qF "text" PATH`   the text must be present;
  * `! grep -qF "text" PATH` the text must be absent;
  * `grep -q` / `-qE`        SKIPPED: those are regex pins and grep's dialect is
                             not Python's, so a dialect difference would be
                             reported as a broken pin — a false alarm in a guard
                             whose whole job is false alarms;
  * `$f`                     resolved from the same run string's own
                             `f=<path>` assignment.

Pins whose needle contains an unresolved shell variable are counted as skipped
and reported, because this cannot know what they expand to.

What it deliberately does NOT check: suite-transcript pins
(`grep -q "✓.*case name"`), which need a suite run.
`tools/check_manifest_integrity.py` already owns their shape, and the suite
itself owns whether the case exists.

Usage:  python3 tools/check_gate_pins.py [--selftest] [--verbose]
Exit 0 = every resolvable pin matches; 1 = at least one does not.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MANIFEST = os.path.join(HERE, "lune", "gate_manifest.luau")

# `[!] grep -q[F|E] "needle" path` — the needle may carry escaped quotes.
PIN = re.compile(
    r"(!\s*)?grep\s+-q([FE]?i?[FE]?)\s+\\?\"((?:[^\"\\]|\\.)*?)\\?\"\s+"
    r"\\?\"?([A-Za-z0-9_./\-$]+)\\?\"?"
)
ASSIGN = re.compile(r"\b([a-z])=([A-Za-z0-9_./\-]+)")


def run_strings(source):
    """Every `run = '…'` / `run = "…"` value, one per gate row."""
    out = []
    for match in re.finditer(r"run = (['\"])", source):
        quote = match.group(1)
        i = match.end()
        depth_escape = False
        start = i
        while i < len(source):
            c = source[i]
            if depth_escape:
                depth_escape = False
            elif c == "\\":
                depth_escape = True
            elif c == quote:
                break
            i += 1
        out.append(source[start:i])
    return out


def check(root=REPO, verbose=False, manifest=None):
    with open(manifest or MANIFEST, encoding="utf-8") as fh:
        source = fh.read()
    checked = skipped = 0
    broken = []
    for run in run_strings(source):
        variables = dict(ASSIGN.findall(run))
        for match in PIN.finditer(run):
            negated, flags, needle, path = match.groups()
            if path.startswith("$"):
                path = variables.get(path[1:], path)
            if "$" in path or "$" in needle:
                skipped += 1
                continue
            full = os.path.join(root, path)
            if not os.path.isfile(full):
                continue  # a path outside this tree (frozen evidence, the consumer repo)
            text = needle.replace('\\"', '"').replace("\\\\", "\\")
            with open(full, encoding="utf-8", errors="replace") as fh:
                body = fh.read()
            if "F" not in flags:
                # `-q` and `-qE` are regex pins, and grep's dialect is not
                # Python's. Reporting a dialect difference as a broken pin would
                # be a false alarm in a guard whose whole job is false alarms.
                skipped += 1
                continue
            present = text in body
            checked += 1
            want_absent = negated is not None
            if present == want_absent:
                broken.append((path, text[:110], "must be ABSENT" if want_absent
                               else "must be PRESENT"))
            elif verbose:
                print(f"  ok {path}: {text[:70]!r}")
    return checked, skipped, broken


def selftest():
    """Prove both directions on a SCRATCH manifest: a sentence that is present
    satisfies its pin, and the negated pin over the same sentence breaks. The
    real manifest is never written to, so a concurrent reader never sees a
    planted row."""
    probe = os.path.join(REPO, "src", "gate_pin_probe_tmp.luau")
    scratch = os.path.join(REPO, "tools", "lune", "gate_pin_probe_manifest_tmp.luau")
    try:
        with open(probe, "w") as fh:
            fh.write("-- the sentence a gate pins\n")
        with open(scratch, "w") as fh:
            fh.write(
                "return {\n"
                '\trun = \'grep -qF "the sentence a gate pins" src/gate_pin_probe_tmp.luau\',\n'
                '\trun = \'! grep -qF "the sentence a gate pins" src/gate_pin_probe_tmp.luau\',\n'
                '\trun = \'grep -qF "a sentence nothing contains" src/gate_pin_probe_tmp.luau\',\n'
                "}\n"
            )
        checked, _skipped, broken = check(manifest=scratch)
        absent = [b for b in broken if b[2] == "must be ABSENT"]
        present = [b for b in broken if b[2] == "must be PRESENT"]
        if checked != 3 or len(absent) != 1 or len(present) != 1:
            print("check_gate_pins: SELFTEST FAIL — expected 3 pins with one of each "
                  f"failure, got checked={checked} broken={broken}")
            return 1
    finally:
        for path in (probe, scratch):
            if os.path.exists(path):
                os.unlink(path)
    checked, skipped, broken = check()
    if broken:
        print("check_gate_pins: SELFTEST FAIL — the restored tree has broken pins:")
        for path, text, why in broken[:10]:
            print(f"  {path}: {text!r} {why}")
        return 1
    print("check_gate_pins: SELFTEST PASS — a matching pin passes, a negated pin over "
          "the same present sentence breaks, a pin over absent text breaks, and the "
          f"real manifest is clean ({checked} pins, {skipped} skipped)")
    return 0


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    checked, skipped, broken = check(verbose="--verbose" in sys.argv)
    if broken:
        print(f"check_gate_pins: FAIL — {len(broken)} of {checked} gate file pins no "
              "longer match the tree:")
        for path, text, why in broken:
            print(f"  {path}: {text!r} {why}")
        sys.exit(1)
    print(f"check_gate_pins: PASS — {checked} gate file pins match the tree "
          f"({skipped} skipped: the needle or path carries a shell variable)")


if __name__ == "__main__":
    main()
