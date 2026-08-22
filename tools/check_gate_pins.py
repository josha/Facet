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

It also PARSES every run string with `bash -n`. A gate row is a shell command
line stored in a Lua string, and a dropped quote is invisible to every check
here: `1482571` deleted the closing `"` of one `grep -qF` needle and the whole
`d6-segmented` row became a syntax error — bash refused it, the gate read
FAIL_RECOVERABLE, and the twenty-two clauses AFTER the typo (including all eight
Rascal Rally suite greps) stopped running for a day without anybody's pin being
wrong. Parsing costs nothing and executes nothing.

What it deliberately does NOT check: suite-transcript pins
(`grep -q "✓.*case name"`), which need a suite run.
`tools/check_manifest_integrity.py` already owns their shape, and the suite
itself owns whether the case exists.

Usage:  python3 tools/check_gate_pins.py [--selftest] [--verbose]
Exit 0 = every resolvable pin matches; 1 = at least one does not.
"""

import os
import re
import subprocess
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


CONCAT = re.compile(r"\s*\.\.\s*(['\"])")


def _literal(source, i, quote):
    """The body of a Lua string literal opening at `i`, and the index past it."""
    start = i
    depth_escape = False
    while i < len(source):
        c = source[i]
        if depth_escape:
            depth_escape = False
        elif c == "\\":
            depth_escape = True
        elif c == quote:
            break
        i += 1
    return source[start:i], i + 1


def run_strings(source):
    """Every `run = '…'` / `run = "…"` value, one per gate row.

    A row may BUILD its command out of adjacent literals joined by `..` (two
    `studio-evidence` rows do, to keep an inline `python3 -c` readable), so the
    fragments are concatenated here. Reading only the first one truncates the
    command mid-quote, which the syntax check below would then report as a fault
    of the manifest rather than of this reader."""
    out = []
    for match in re.finditer(r"run = (['\"])", source):
        body, i = _literal(source, match.end(), match.group(1))
        while True:
            joined = CONCAT.match(source, i)
            if joined is None:
                break
            more, i = _literal(source, joined.end(), joined.group(1))
            body += more
        out.append(body)
    return out


LUA_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b",
                "f": "\f", "v": "\v", "\\": "\\", '"': '"', "'": "'"}


def lua_unescape(raw):
    """The string bash is handed. `gate.luau` runs `process.exec("bash", {"-c", run})`,
    so Lua's UNESCAPED value is the command line — a pin written with `\"` inside
    reaches the shell as a bare quote, which is a different command."""
    out = []
    i = 0
    while i < len(raw):
        if raw[i] == "\\" and i + 1 < len(raw):
            c = raw[i + 1]
            out.append(LUA_ESCAPES.get(c, "\\" + c))
            i += 2
        else:
            out.append(raw[i])
            i += 1
    return "".join(out)


def syntax_errors(runs):
    """Run strings bash cannot even parse. `-n` reads and refuses; it runs nothing."""
    bad = []
    for run in runs:
        command = lua_unescape(run)
        result = subprocess.run(["bash", "-n", "-c", command],
                                capture_output=True, text=True)
        if result.returncode != 0:
            first = (result.stderr.strip().splitlines() or ["(no message)"])[0]
            bad.append((command[:90], first))
    return bad


def check(root=REPO, verbose=False, manifest=None):
    with open(manifest or MANIFEST, encoding="utf-8") as fh:
        source = fh.read()
    checked = skipped = 0
    broken = []
    runs = run_strings(source)
    malformed = syntax_errors(runs)
    for run in runs:
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
    return checked, skipped, broken, malformed


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
        checked, _skipped, broken, malformed = check(manifest=scratch)
        absent = [b for b in broken if b[2] == "must be ABSENT"]
        present = [b for b in broken if b[2] == "must be PRESENT"]
        if checked != 3 or len(absent) != 1 or len(present) != 1 or malformed:
            print("check_gate_pins: SELFTEST FAIL — expected 3 pins with one of each "
                  f"failure and no syntax errors, got checked={checked} "
                  f"broken={broken} malformed={malformed}")
            return 1
        # ...and the dropped-quote class, which no pin comparison can see: the
        # row below is `1482571`'s typo in miniature.
        with open(scratch, "w") as fh:
            fh.write(
                "return {\n"
                '\trun = \'grep -qF "a needle whose quote was dropped src/gate_pin_probe_tmp.luau\',\n'
                "}\n"
            )
        _c, _s, _b, malformed = check(manifest=scratch)
        if len(malformed) != 1:
            print("check_gate_pins: SELFTEST FAIL — an unterminated quote in a run "
                  f"string was not reported (malformed={malformed})")
            return 1
    finally:
        for path in (probe, scratch):
            if os.path.exists(path):
                os.unlink(path)
    checked, skipped, broken, malformed = check()
    if broken or malformed:
        print("check_gate_pins: SELFTEST FAIL — the restored tree has broken pins:")
        for path, text, why in broken[:10]:
            print(f"  {path}: {text!r} {why}")
        for command, why in malformed[:10]:
            print(f"  bash cannot parse: {command!r} — {why}")
        return 1
    print("check_gate_pins: SELFTEST PASS — a matching pin passes, a negated pin over "
          "the same present sentence breaks, a pin over absent text breaks, an "
          "unterminated quote is reported, and the real manifest is clean "
          f"({checked} pins, {skipped} skipped)")
    return 0


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    checked, skipped, broken, malformed = check(verbose="--verbose" in sys.argv)
    if malformed:
        print(f"check_gate_pins: FAIL — {len(malformed)} run string(s) bash cannot "
              "parse. Every clause after the fault is dead:")
        for command, why in malformed:
            print(f"  {why}\n    {command!r}…")
    if broken:
        print(f"check_gate_pins: FAIL — {len(broken)} of {checked} gate file pins no "
              "longer match the tree:")
        for path, text, why in broken:
            print(f"  {path}: {text!r} {why}")
    if broken or malformed:
        sys.exit(1)
    print(f"check_gate_pins: PASS — {checked} gate file pins match the tree, and all "
          f"{len(run_strings(open(MANIFEST, encoding='utf-8').read()))} run strings "
          f"parse ({skipped} skipped: the needle or path carries a shell variable)")


if __name__ == "__main__":
    main()
