#!/usr/bin/env python3

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FACET_SOURCES = ("src/ui", "src/init.luau")
SCREEN_SOURCES = ("examples",)
TEACHING_DOCS = ("README.md", "docs/guide", "docs/reference", "docs/extending", "examples", "skills")
HISTORICAL_DOCS = {
    "docs/plans": "dated design records that describe past architectures; they are not teaching material",
    "docs/superpowers": "dated planning records that describe past architectures; they are not teaching material",
}

FACET_FORBIDDEN = (
    ("ContextActionService", re.compile(r"ContextActionService"), "Facet controls bind keys only through native InputContext and InputAction"),
    ("BindAction", re.compile(r":\s*Bind(?:Core)?Action(?:AtPriority)?\s*\("), "ContextActionService binding is a second input system"),
    ("raw input Instance", re.compile(r"Instance\.new\(\s*[\"'`]Input(?:Binding|Action|Context)[\"'`]"), "Compose owns input Instances through the host constructors"),
)

ENUM_ALIASES = {"Enum", "E"}
KEY_READ = re.compile(r"(?<![\w.])([A-Za-z_]\w*)\.KeyCode\b")

SCREEN_FORBIDDEN = FACET_FORBIDDEN + (
    ("key polling", re.compile(r":\s*(?:IsKeyDown|GetKeysPressed|IsGamepadButtonDown|GetGamepadState)\s*\("), "a screen polls the keyboard or gamepad itself"),
    ("key device test", re.compile(r"UserInputType\.(?:Keyboard|Gamepad\w*)\b"), "a screen classifies raw key input itself"),
)

BINDING_SITE = re.compile(r"\bInputBinding\s*[({]")

PINS = {
    "examples/gallery/examples/05_word_game.luau": (
        3,
        "the word game declares letter, Submit and Backspace keys in its own sinking InputContext under ctx.inputTarget, the documented seam for game hotkeys",
    ),
    "examples/gallery/examples/06_tile_game.luau": (
        1,
        "the crossword declares its letter keys in its own sinking InputContext under ctx.inputTarget",
    ),
    "examples/virtual_monitors/screens.luau": (
        1,
        "Discover owns the Slash InputAction that its ShortcutHint describes and that focuses the search field, as docs/reference/api.md documents for the hint's action option",
    ),
    "examples/gallery/scenarios/shortcut_hint.luau": (
        3,
        "the ShortcutHint recipe owns the InputAction that the hint describes, as docs/reference/api.md documents for its action option",
    ),
    "examples/gallery/scenarios/outpost_terminal.luau": (
        2,
        "the world terminal declares LeaveConsole on Escape and ButtonB while engaged, in its own InputContext under ctx.inputTarget",
    ),
}

FENCE = re.compile(r"^```(?:lua|luau)\s*$(.*?)^```\s*$", re.MULTILINE | re.DOTALL)
LONG_OPEN = re.compile(r"\[(=*)\[")


def blank(text):
    return "".join("\n" if ch == "\n" else " " for ch in text)


def close_long(source, start, level):
    found = source.find("]" + "=" * level + "]", start)
    return len(source) if found < 0 else found + level + 2


def strip_luau_comments(source):
    out = []
    i, n = 0, len(source)
    while i < n:
        ch = source[i]
        if ch == "-" and source.startswith("--", i):
            opened = LONG_OPEN.match(source, i + 2)
            if opened:
                end = close_long(source, opened.end(), len(opened.group(1)))
            else:
                end = source.find("\n", i)
                end = n if end < 0 else end
            out.append(blank(source[i:end]))
            i = end
        elif ch == "[":
            opened = LONG_OPEN.match(source, i)
            if opened:
                end = close_long(source, opened.end(), len(opened.group(1)))
                out.append(source[i:end])
                i = end
            else:
                out.append(ch)
                i += 1
        elif ch in "\"'`":
            j = i + 1
            while j < n and source[j] != ch:
                if source[j] == "\\":
                    j += 2
                elif source[j] == "\n" and ch != "`":
                    break
                else:
                    j += 1
            end = min(j + 1, n)
            out.append(source[i:end])
            i = end
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def line_of(code, offset):
    return code.count("\n", 0, offset) + 1


def files_under(root, suffixes):
    base = ROOT / root
    if base.is_file():
        return [base] if base.suffix in suffixes else []
    if not base.is_dir():
        return []
    return sorted(path for path in base.rglob("*") if path.is_file() and path.suffix in suffixes)


def relative(path):
    return path.relative_to(ROOT).as_posix()


def key_reads(code):
    return [(line_of(code, m.start()), m.group(0)) for m in KEY_READ.finditer(code) if m.group(1) not in ENUM_ALIASES]


def offences_in(label, code, rules, screen):
    found = []
    for name, pattern, reason in rules:
        for match in pattern.finditer(code):
            found.append(f"  {label}:{line_of(code, match.start())}: {name} `{match.group(0)}` ({reason})")
    if screen:
        for line, text in key_reads(code):
            found.append(f"  {label}:{line}: key read `{text}` (a screen inspects raw key codes itself)")
    return found


def snippets(path):
    text = path.read_text(encoding="utf-8")
    for match in FENCE.finditer(text):
        yield line_of(text, match.start(1)) - 1, match.group(1)


def historical(path):
    name = relative(path)
    return any(name == prefix or name.startswith(prefix + "/") for prefix in HISTORICAL_DOCS)


def scan():
    offences, sites = [], {}
    for root in FACET_SOURCES:
        for path in files_under(root, {".luau"}):
            offences += offences_in(relative(path), strip_luau_comments(path.read_text(encoding="utf-8")), FACET_FORBIDDEN, False)
    for root in SCREEN_SOURCES:
        for path in files_under(root, {".luau", ".lua"}):
            code = strip_luau_comments(path.read_text(encoding="utf-8"))
            offences += offences_in(relative(path), code, SCREEN_FORBIDDEN, True)
            count = len(BINDING_SITE.findall(code))
            if count:
                sites[relative(path)] = count
    seen_docs = set()
    for root in TEACHING_DOCS:
        for path in files_under(root, {".md"}):
            if historical(path) or path in seen_docs:
                continue
            seen_docs.add(path)
            for start, block in snippets(path):
                code = strip_luau_comments(block)
                label = f"{relative(path)}+{start}"
                offences += offences_in(label, code, SCREEN_FORBIDDEN, True)
                count = len(BINDING_SITE.findall(code))
                if count:
                    sites[relative(path)] = sites.get(relative(path), 0) + count
    for path, count in sorted(sites.items()):
        pinned = PINS.get(path)
        if pinned is None:
            offences.append(f"  {path}: {count} unpinned InputBinding declaration site(s); a screen claims keys without an approved pin")
        elif pinned[0] != count:
            offences.append(f"  {path}: {count} InputBinding declaration site(s); the pin records {pinned[0]}")
    for path in sorted(set(PINS) - set(sites)):
        offences.append(f"  {path}: pinned InputBinding sites are gone; remove the stale pin")
    for path, (count, reason) in PINS.items():
        if not reason.strip() or count <= 0:
            offences.append(f"  {path}: every pin needs a positive count and a reason")
    return offences


def report(offences):
    if offences:
        sys.stderr.write(
            "screen key bindings: FAILED. Screens reach keys only through Facet controls or a pinned native\n"
            "InputContext declaration; Facet controls bind keys only through native InputAction.\n" + "\n".join(offences) + "\n"
        )
        return 1
    print("screen key bindings: clean")
    return 0


LEXER_CASES = (
    ("a line comment is stripped", "x = 1 -- ContextActionService\n", False),
    ("a block comment is stripped", "--[[\n\tContextActionService priority\n]]\n", False),
    ("a level-2 long comment is stripped", "--[==[\nContextActionService\n]==]\n", False),
    ("a level-1 close does not close a level-2 comment", "--[==[\n]]\nContextActionService\n]==]\n", False),
    ("an unterminated block comment blanks to the end", "--[[\nContextActionService\n", False),
    ("an inline block comment is stripped", "a --[[ ContextActionService ]] b = 1\n", False),
    ("a service name in a string is seen", 'local s = game:GetService("ContextActionService")\n', True),
    ("code after a block comment is seen", "--[[ prose ]]\nlocal u = ContextActionService\n", True),
    ("code before a trailing comment is seen", "local u = ContextActionService -- why\n", True),
    ("a dash pair inside a string does not open a comment", 'local d = "--" .. ContextActionService\n', True),
    ("long comments do not nest", "--[[ [[ ]] ContextActionService ]]\n", True),
    ("long string contents stay visible", "local s = [[ContextActionService]]\n", True),
    ("an escaped quote does not end the string", 'local s = "a\\"-- " .. ContextActionService\n', True),
    ("an interpolated string does not swallow the line", "local s = `a{b}` .. ContextActionService\n", True),
)

RULE_CASES = (
    ("a key comparison is red", "if input.KeyCode == Enum.KeyCode.Q then end\n", True),
    ("a reversed key comparison is red", "if Enum.KeyCode.Q == event.KeyCode then end\n", True),
    ("a key table lookup is red", "local f = handlers[input.KeyCode]\n", True),
    ("IsKeyDown polling is red", "local down = service:IsKeyDown(Enum.KeyCode.W)\n", True),
    ("a keyboard device test is red", "if input.UserInputType == Enum.UserInputType.Keyboard then end\n", True),
    ("a ContextActionService bind is red", "cas:BindAction('Jump', jump, false, Enum.KeyCode.Space)\n", True),
    ("a raw InputBinding Instance is red", 'local b = Instance.new("InputBinding")\n', True),
    ("an enum value in a declaration is clean", "Host.InputBinding({ KeyCode = Enum.KeyCode.Return })\n", False),
    ("an aliased enum value is clean", "local k = E.KeyCode.Return\n", False),
    ("a field-path enum is clean", "local k = types.Enum.KeyCode.Return\n", False),
    ("a pointer device test is clean", "if input.UserInputType == E.UserInputType.Touch then end\n", False),
    ("a commented key comparison is clean", "-- if input.KeyCode == Enum.KeyCode.Q then end\n", False),
)

SITE_CASES = (
    ("a commented declaration does not count", "-- Host.InputBinding({ KeyCode = Enum.KeyCode.Tab })\n", 0),
    ("a class name string does not count", 'action:FindFirstChildWhichIsA("InputBinding")\n', 0),
    ("a call declaration counts", "Host.InputBinding({ KeyCode = Enum.KeyCode.Tab })\n", 1),
    ("a table-call declaration counts", "Host.InputBinding { KeyCode = Enum.KeyCode.Tab }\n", 1),
    ("two declarations on one line count twice", "{ Host.InputBinding({}), Host.InputBinding({}) }\n", 2),
)

PLANTS = (
    ("a raw key handler", "examples/gallery/scenarios/{name}.luau", "--!strict\nlocal uis = game:GetService(\"UserInputService\")\nuis.InputBegan:Connect(function(input)\n\tif input.KeyCode == Enum.KeyCode.Q then\n\t\tprint(\"q\")\n\tend\nend)\n"),
    ("an unpinned native binding", "examples/consumer/src/{name}.luau", "--!strict\nreturn function(Host)\n\treturn Host.InputBinding({ KeyCode = Enum.KeyCode.Q })\nend\n"),
    ("a ContextActionService bind in Facet", "src/ui/{name}.luau", "--!strict\nlocal cas = game:GetService(\"ContextActionService\")\nreturn cas\n"),
    ("a key comparison in a teaching snippet", "docs/guide/{name}.md", "# Planted\n\n```luau\nif input.KeyCode == Enum.KeyCode.Q then\nend\n```\n"),
)


def selftest():
    bad = []
    for name, source, expected in LEXER_CASES:
        code = strip_luau_comments(source)
        if ("ContextActionService" in code) != expected:
            bad.append(f"  lexer: {name}")
        if len(code) != len(source) or code.count("\n") != source.count("\n"):
            bad.append(f"  lexer offsets moved: {name}")
    for name, source, expected in RULE_CASES:
        red = bool(offences_in("case", strip_luau_comments(source), SCREEN_FORBIDDEN, True))
        if red != expected:
            bad.append(f"  rule: {name}")
    for name, source, expected in SITE_CASES:
        found = len(BINDING_SITE.findall(strip_luau_comments(source)))
        if found != expected:
            bad.append(f"  site: {name}: expected {expected}, found {found}")
    baseline = scan()
    if baseline:
        bad.append("  the tree is not clean before planting:\n" + "\n".join(baseline))
    for name, template, content in PLANTS:
        path = ROOT / template.format(name=f"zz_key_binding_selftest_{os.getpid()}")
        if path.exists():
            bad.append(f"  plant path already exists: {relative(path)}")
            continue
        try:
            path.write_text(content, encoding="utf-8")
            planted = scan()
            if not any(relative(path) in line for line in planted):
                bad.append(f"  plant stayed green: {name} at {relative(path)}")
        finally:
            path.unlink(missing_ok=True)
    if scan() != baseline:
        bad.append("  the scan did not return to its baseline after the plants were removed")
    if bad:
        sys.stderr.write("selftest FAILED:\n" + "\n".join(bad) + "\n")
        return 1
    print(f"selftest: {len(LEXER_CASES) + len(RULE_CASES) + len(SITE_CASES)} cases and {len(PLANTS)} planted violations green")
    return 0


if __name__ == "__main__":
    raise SystemExit(selftest() if "--selftest" in sys.argv[1:] else report(scan()))
