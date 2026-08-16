#!/usr/bin/env python3
"""DK-16: no control under `src/controls/` reaches for the raw keyboard.

WHAT THE ROW CLAIMS. A screen adds ZERO key listeners — mounting public controls
and presenting is the whole setup — and the ONE sanctioned seam for a control
that genuinely needs a key is `bindActionSystem`, contribution-scoped and
focus-gated. So no module here may name `UserInputService`, `ContextActionService`
or `Enum.KeyCode`, and the lowercase `keyCode =` binding sites are pinned exactly:
four in `row_actions.luau` (Delete, Backspace, ButtonX, Shift+Return), two in
`text_input.luau` (its text-entry Swallow and Cancel). A third file appearing, or
either count drifting, reddens this check.

WHY THIS FILE EXISTS (2026-08-15). The row used to be a chain of `grep -rn`
clauses inside `tools/lune/gate_manifest.luau`, each piped through

    grep -qvE ":[0-9]+:[[:space:]]*--"

to let explanatory prose name a service without tripping the guard. That filter
recognises exactly one of Luau's four lexical forms: the `--` LINE comment. It
does not know `--[[ ]]`, whose interior lines start with whatever the prose
starts with. Commit `3eb97fb` added a block comment to `src/controls/table.luau`
recording a live measurement — "ContextActionService priority and
InputContext.Priority are not one arbitration space" — and the gate read those
two lines as a control binding keys. The row has been RED since, and
`traversal-document-order`'s `step8-debt-cleared` (which reads this gate's
`gate.json` status) went red behind it.

THE FIX IS THE PARSER, NOT THE ALLOWLIST. Widening the filter to excuse
`table.luau`, or dropping the clause, would be a check edited to agree with the
code that broke it — the failure mode `tools/check_traversal_evidence.py`'s
header is written about, and the one `docs/lessons/` keeps a ledger of. The check
was RIGHT; it was reading a comment as code. So the comment stripper became a
real (small) Luau lexer, and every clause of the row now runs over stripped
source instead of raw text.

WHAT THE LEXER HANDLES, and why each form is load-bearing:

  * `--` to end of line.
  * `--[[ ]]`, `--[=[ ]=]`, `--[==[ ]==]` … long brackets at ARBITRARY level,
    closed only by a `]` run of the SAME level. The defect above.
  * `[[ ]]` / `[=[ ]=]` long STRINGS. Not stripped (see the policy below) but
    lexed, because a long string may contain `--` or `]]`, and a stripper that
    does not know where one starts will either open a comment inside a string or
    close a comment at a bracket that was never its own.
  * `"…"`, `'…'` with backslash escapes, and Luau's `` `…` `` interpolated
    strings. Same reason: `local sep = "--"` must not blank the rest of the line.

WHAT IS DELIBERATELY *NOT* STRIPPED: string CONTENTS. The most plausible real
bypass in this codebase is `game:GetService("ContextActionService")`, where the
forbidden token lives inside a string literal — a stripper that blanked strings
would be blind to precisely the thing this row exists to catch. Prose therefore
gets an exemption only when it is a COMMENT, which is where prose belongs. A
string literal that happens to spell a service name reddens the check; that is
fail-closed, and no such string exists in `src/controls/` today.

SHOULD THIS BE A REAL READ INSTEAD OF A TEXT SCAN? It cannot fully be, at
proportionate cost. The honest ground truth is what a module DOES at runtime, and
these controls only reach the engine through the arbitrated seam, so a runtime
guard (a mocked `GetService` that fails on the two services) would only see the
paths a given test happens to execute — a coverage-limited instrument reported as
a total one, which is worse than an honest static scan. What this scan still
cannot see, for whoever hits the edge next:

  * a computed service name — `game:GetService(SERVICES[i])`, concatenation, a
    name arriving from another module, `loadstring`;
  * indirection — a control calling a helper OUTSIDE `src/controls/` that binds
    the key on its behalf (the require graph in `tools/lune/check_boundary.luau`
    is the instrument for that class, not this one);
  * a WRONG key bound through the sanctioned seam: the pins count binding SITES,
    so changing `"Delete"` to `"Tab"` in place moves nothing here. The suite's
    DK-8..DK-15 cases are what cover the behaviour.

Run: `python3 tools/check_no_screen_key_bindings.py` from the repo root
     `python3 tools/check_no_screen_key_bindings.py --selftest` for the lexer's
     own named cases (both mutation directions included). Exit 0 = clean; any
     other exit prints why, on stderr.

`strip_luau_comments` is importable: two other gate checks carry the same
one-line-comment-only filter over Luau source and therefore the same latent
defect — `tools/lune/gate_manifest.luau`'s `layout-purity` (line-comment filter
over `src/layout/`) and `swiftui-reference-app-validation`'s
`responsibility-ledger` (over `examples/reference/`). They are reported, not
silently rewritten; fixing them is their own change.
"""

import os
import re
import sys

CONTROLS = "src/controls/"
SCENARIO = "examples/gallery/scenarios/keyboard_navigation.luau"

# The raw-keyboard bypass class: naming any of these in CODE is the defect.
FORBIDDEN = ("KeyCode", "UserInputService", "ContextActionService")

# The sanctioned seam, pinned by file and by number of binding SITES.
BINDING_SITES = re.compile(r"keyCode *=")
PINS = {"src/controls/row_actions.luau": 4, "src/controls/text_input.luau": 2}

# The Studio fixture must CREATE no binding — it may only read one for its trace.
FIXTURE_WIRING = re.compile(r"keyCode *=|createAction\(|\.bind\(")

_LONG_OPEN = re.compile(r"\[(=*)\[")


def fail(message: str) -> "NoReturn":  # noqa: F821
    sys.stderr.write(message.rstrip() + "\n")
    raise SystemExit(1)


def _blank(text: str) -> str:
    """The same length, newlines kept, everything else a space — so line numbers
    and column offsets in what comes out still point at the real source."""
    return "".join("\n" if ch == "\n" else " " for ch in text)


def _close_long(source: str, start: int, level: int) -> int:
    """Index just past the `]` + `level` `=` + `]` that closes a long bracket
    opened at `start`, or len(source) if the file ends first (Luau would reject
    that source; we blank to EOF rather than pretend the rest is code)."""
    found = source.find("]" + "=" * level + "]", start)
    return len(source) if found < 0 else found + level + 2


def strip_luau_comments(source: str) -> str:
    """`source` with every COMMENT blanked to spaces and everything else intact.

    Strings are lexed (so a `--` or `]]` inside one cannot be mistaken for a
    comment delimiter) but their contents are left in place on purpose — see the
    module header: `GetService("UserInputService")` is the bypass this guard is
    for, and it lives inside a string.
    """
    out = []
    i, n = 0, len(source)
    while i < n:
        ch = source[i]
        if ch == "-" and source.startswith("--", i):
            opened = _LONG_OPEN.match(source, i + 2)
            if opened:  # --[[ ]] / --[=[ ]=] / --[==[ ]==] …
                end = _close_long(source, opened.end(), len(opened.group(1)))
            else:  # -- to end of line (the newline itself is code's business)
                end = source.find("\n", i)
                end = n if end < 0 else end
            out.append(_blank(source[i:end]))
            i = end
        elif ch == "[":
            opened = _LONG_OPEN.match(source, i)
            if opened:  # long STRING — kept, but skipped over
                end = _close_long(source, opened.end(), len(opened.group(1)))
                out.append(source[i:end])
                i = end
            else:
                out.append(ch)
                i += 1
        elif ch in "\"'`":
            j = i + 1
            while j < n and source[j] != ch:
                if source[j] == "\\":
                    j += 2  # any escape, including \" and a line continuation
                elif source[j] == "\n" and ch != "`":
                    break  # unterminated quote: Luau rejects it; stop here
                else:
                    j += 1
            end = min(j + 1, n)
            out.append(source[i:end])
            i = end
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def luau_files(root: str) -> list:
    found = []
    for base, _, names in os.walk(root):
        found += [os.path.join(base, f) for f in names if f.endswith(".luau")]
    return sorted(found)


def code_of(path: str) -> str:
    with open(path, encoding="utf-8") as handle:
        return strip_luau_comments(handle.read())


def hits(code: str, pattern) -> list:
    """(line number, matched text) for every match, on the stripped source."""
    return [(code.count("\n", 0, m.start()) + 1, m.group(0)) for m in pattern.finditer(code)]


def main() -> None:
    if not os.path.isdir(CONTROLS):
        fail(f"missing {CONTROLS} — run this from the repo root")

    # ---- 1. THE BYPASS CLASS: nothing here names the raw keyboard in code ----
    offences = []
    for path in luau_files(CONTROLS):
        code = code_of(path)
        for token in FORBIDDEN:
            for line, _ in hits(code, re.compile(re.escape(token))):
                offences.append(f"  {path}:{line}: {token}")
    if offences:
        fail(
            "DK-16 VIOLATED — a control names the raw keyboard in CODE (comments are exempt,\n"
            "string literals deliberately are not: `GetService(\"UserInputService\")` is the\n"
            "bypass this guard exists for). Route the key through `bindActionSystem` instead:\n"
            + "\n".join(offences)
        )

    # ---- 2. THE SANCTIONED SEAM, pinned by file and by binding SITE ---------
    binding_files = {p: len(hits(code_of(p), BINDING_SITES)) for p in luau_files(CONTROLS)}
    binding_files = {p: c for p, c in binding_files.items() if c}
    if set(binding_files) != set(PINS):
        fail(
            "the set of controls that bind a key has CHANGED.\n"
            f"  pinned  : {sorted(PINS)}\n"
            f"  on disk : {sorted(binding_files)}\n"
            "Both pinned files ride the SAME director-approved seam (contribution-scoped\n"
            "through bindActionSystem, focus-gated per row). A third file is a new claim on\n"
            "the keyboard and needs the same approval before this pin moves."
        )
    for path, expected in sorted(PINS.items()):
        if binding_files[path] != expected:
            fail(
                f"{path} holds {binding_files[path]} `keyCode =` binding site(s); the row pins {expected}.\n"
                "This counts OCCURRENCES, not lines (2026-08-14: `grep -c` counted lines and so\n"
                "measured formatting — a consolidation into one table reddened a refactor that\n"
                "removed nothing). If a binding was genuinely added or removed, the pin moves\n"
                "with the director approval that sanctioned it, never on its own."
            )

    # ---- 3. THE FIXTURE PROVES THE BEHAVIOUR IS AUTOMATIC ------------------
    if not os.path.isfile(SCENARIO):
        fail(f"missing {SCENARIO}")
    wiring = hits(code_of(SCENARIO), FIXTURE_WIRING)
    if wiring:
        fail(
            f"{SCENARIO} now WIRES input, so it can no longer prove DK-16.\n"
            + "\n".join(f"  line {line}: {text}" for line, text in wiring)
            + "\nThe traversal case has to present with ZERO input opts; reading `binding.keyCode`\n"
            "for the trace is observation and stays legal, creating one is not."
        )


# --------------------------------------------------------------------------
# The lexer's own cases. A stripper is exactly the kind of code that looks right
# and is wrong in one branch, and this check is only worth its gate row if it
# still BITES — so the mutation direction that matters most (a genuine binding
# must redden it) is asserted here by name, beside the one the 2026-08-15 defect
# was about (a block comment must not).
# --------------------------------------------------------------------------
SELFTESTS = (
    ("a line comment is stripped", "x = 1 -- ContextActionService\n", False),
    ("a BLOCK comment is stripped (the 3eb97fb defect)", "--[[\n\tContextActionService priority\n]]\n", False),
    ("a long comment at level 2 is stripped", "--[==[\nUserInputService\n]==]\n", False),
    ("a level-1 close does NOT close a level-2 comment", "--[==[\n]]\nKeyCode\n]==]\n", False),
    ("an unterminated block comment blanks to EOF", "--[[\nContextActionService\n", False),
    ("an inline block comment is stripped, code around it survives", "a --[[ KeyCode ]] b = 1\n", False),
    ("a REAL bind still reddens: GetService in a string", 'local s = game:GetService("UserInputService")\n', True),
    ("a REAL bind still reddens: Enum.KeyCode in code", "ctx.bind({ key = Enum.KeyCode.Tab })\n", True),
    ("a REAL bind after a block comment is still seen", "--[[ prose ]]\nlocal u = UserInputService\n", True),
    ("a REAL bind on the SAME line as a trailing comment is still seen", "local u = UserInputService -- why\n", True),
    ("`--` inside a string does not blank the rest of the line", 'local d = "--" .. UserInputService\n', True),
    # MEASURED with lune 2026-08-15, not recalled: `local x = 1 --[[ [[ ]] print("code
    # after") --[[x]]` PRINTS. Luau long brackets do not nest (Lua 5.1 dropped it), so
    # the FIRST `]]` closes the comment and what follows is code the guard must see.
    ("a long comment does not nest: the first `]]` closes it", "--[[ [[ ]] KeyCode ]]\n", True),
    ("a long STRING's contents stay visible", "local s = [[UserInputService]]\n", True),
    ("an escaped quote does not end the string early", 'local s = "a\\"-- " .. KeyCode\n', True),
    ("an interpolated string does not swallow the line", "local s = `a{b}` .. KeyCode\n", True),
)

SITE_CASES = (
    ("a commented-out binding does not count", "-- keyCode = 'Tab'\n", 0),
    ("a binding inside a block comment does not count", "--[=[\nkeyCode = 'Tab'\n]=]\n", 0),
    ("a real binding counts", "bind({ keyCode = 'Tab' })\n", 1),
    ("two real bindings on one line count twice", "{ { keyCode = 'a' }, { keyCode = 'b' } }\n", 2),
)


def selftest() -> None:
    bad = []
    for name, source, should_see in SELFTESTS:
        code = strip_luau_comments(source)
        seen = any(token in code for token in FORBIDDEN)
        if seen != should_see:
            bad.append(f"  {name}: expected {'a hit' if should_see else 'no hit'}, got the opposite")
        if len(code) != len(source) or code.count("\n") != source.count("\n"):
            bad.append(f"  {name}: offsets moved — line numbers in a report would be wrong")
    for name, source, expected in SITE_CASES:
        found = len(hits(strip_luau_comments(source), BINDING_SITES))
        if found != expected:
            bad.append(f"  {name}: expected {expected} binding site(s), found {found}")
    if bad:
        fail("selftest FAILED:\n" + "\n".join(bad))
    print(f"selftest: {len(SELFTESTS) + len(SITE_CASES)} cases green")


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        selftest()
    else:
        main()
