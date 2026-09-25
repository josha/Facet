#!/usr/bin/env python3
import os
import re
import shutil
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCANNED = ("examples/gallery/examples", "examples/reference")
SKIPPED = ("examples/gallery/examples/words",)
THEMES = "src/ui/themes.luau"

RULES = (
    ("R1", re.compile(r"\bTextSize\s*=\s*-?\d"), "a literal TextSize; use a textRole or the control size"),
    ("R1", re.compile(r"\b(?:TextColor3|BackgroundColor3|ImageColor3)\s*=\s*(?:ctx\.types\.)?(?:Color3|C3)\.\w+\(\s*-?[\d.]"), "a literal paint colour; use a theme tag or role"),
    ("R1", re.compile(r"\b(?:Font|FontFace)\s*=\s*(?:Enum\.Font|Font\.)"), "a literal font; use a textRole"),
    ("R3", re.compile(r"\b(?:Color3|C3)\.(?:(?:new|fromRGB|fromHSV)\s*\(\s*-?[\d.]|fromHex\s*\()"), "a raw colour; use a theme tag or role"),
    ("R4", re.compile(r"\bInstance\.new\s*\("), "an engine reach-around; use the Host constructors"),
    ("R4", re.compile(r"\bgame:GetService\s*\("), "an engine reach-around; receive the service through the context"),
)
ROLE = re.compile(r'\btextRole\s*=\s*"([^"]*)"')

ALLOWLIST = (
    {
        "file": "examples/gallery/examples/05_word_game.luau",
        "match": "TextSize = 24,",
        "why": "the letter glyph of a fixed 48 px board tile; a theme type step would overflow the tile",
    },
    {
        "file": "examples/gallery/examples/05_word_game.luau",
        "match": "TextSize = 12,",
        "why": "the corner mark of a fixed 48 px board tile, sized with the tile",
    },
    {
        "file": "examples/gallery/examples/06_tile_game.luau",
        "match": "TextSize = 16,",
        "why": "the letter of a fixed 44 to 48 px board cell or rack tile, sized with the cell",
    },
    {
        "file": "examples/gallery/examples/07_match3.luau",
        "match": "TextSize = 16,",
        "why": "the fallback glyph of a fixed board tile, shown only when the tile art is missing",
    },
    {
        "file": "examples/gallery/examples/07_match3.luau",
        "match": "Color = Color3.new(1, 1, 1),",
        "why": "the selection ring over coloured gem art must contrast with every gem, so it does not follow the palette",
    },
    {
        "file": "examples/gallery/examples/07_match3.luau",
        "match": 'game:GetService("RunService")',
        "why": "the engine fallback when the host context supplies no run service",
    },
    {
        "file": "examples/reference/p1_glade/init.luau",
        "match": 'game:GetService("RunService")',
        "why": "the engine fallback when the host context supplies no heartbeat",
    },
    {
        "file": "examples/reference/p2_cartwheel/init.luau",
        "match": 'game:GetService("RunService")',
        "why": "the engine fallback when the host context supplies no heartbeat",
    },
    {
        "file": "examples/reference/p3_sipworks/init.luau",
        "match": 'game:GetService("RunService")',
        "why": "the engine fallback when the host context supplies no heartbeat",
    },
    {
        "file": "examples/reference/p4_foyer/init.luau",
        "match": 'game:GetService("RunService")',
        "why": "the engine fallback when the host context supplies no heartbeat",
    },
    {
        "file": "examples/reference/p2_cartwheel/init.luau",
        "match": "Color3.fromRGB(",
        "why": "illustration content: the cart, wheel and awning art of the cartwheel scene, not interface paint",
    },
)


def type_roles(root):
    text = open(os.path.join(root, THEMES), encoding="utf-8").read()
    match = re.search(r"themes\.TYPE_ROLES\s*=\s*table\.freeze\(\{([^}]*)\}\)", text)
    if not match:
        raise SystemExit(f"check_example_drift: cannot read TYPE_ROLES from {THEMES}")
    return set(re.findall(r'"([^"]+)"', match.group(1)))


def files(root):
    for base in SCANNED:
        for folder, _, names in os.walk(os.path.join(root, base)):
            relative_folder = os.path.relpath(folder, root)
            if any(relative_folder == skip or relative_folder.startswith(skip + os.sep) for skip in SKIPPED):
                continue
            for name in sorted(names):
                if name.endswith(".luau") and not name.endswith(".spec.luau"):
                    yield os.path.relpath(os.path.join(folder, name), root).replace(os.sep, "/")


def allowed(file, line, allowlist):
    for entry in allowlist:
        if entry["file"] == file and entry["match"] in line:
            return entry
    return None


def check(root, allowlist=ALLOWLIST):
    roles = type_roles(root)
    violations, used, scanned = [], set(), 0
    for file in files(root):
        scanned += 1
        for number, line in enumerate(open(os.path.join(root, file), encoding="utf-8"), 1):
            hits = [(rule, what) for rule, pattern, what in RULES if pattern.search(line)]
            for role in ROLE.findall(line):
                if role not in roles:
                    hits.append(("R2", f"an unknown textRole '{role}'; the roles are {', '.join(sorted(roles))}"))
            if not hits:
                continue
            entry = allowed(file, line, allowlist)
            if entry and all(rule != "R2" for rule, _ in hits):
                used.add((entry["file"], entry["match"]))
                continue
            for rule, what in hits:
                violations.append(f"{file}:{number}: [{rule}] {what}: {line.strip()}")
    stale = [f"{entry['file']}: allowlist entry '{entry['match']}' matches nothing" for entry in allowlist if (entry["file"], entry["match"]) not in used]
    return violations, stale, scanned


def selftest():
    temp = tempfile.mkdtemp()
    try:
        os.makedirs(os.path.join(temp, "src/ui"))
        shutil.copy(os.path.join(REPO, THEMES), os.path.join(temp, THEMES))
        folder = os.path.join(temp, "examples/gallery/examples")
        os.makedirs(folder)
        os.makedirs(os.path.join(temp, "examples/reference"))
        planted = {
            "R1": "local a = { TextSize = 18 }\n",
            "R2": 'local b = UI.Label { textRole = "banner" }\n',
            "R3": "local c = Color3.fromRGB(1, 2, 3)\n",
            "R4": 'local d = Instance.new("Frame")\n',
        }
        for rule, line in planted.items():
            path = os.path.join(folder, f"plant_{rule}.luau")
            open(path, "w").write(line)
            found, _, _ = check(temp, ())
            if not any(f"[{rule}]" in item for item in found):
                return f"selftest: rule {rule} did not fire"
            os.remove(path)
        path = os.path.join(folder, "plant_allow.luau")
        open(path, "w").write("local e = Color3.new(1, 1, 1)\n")
        allow = ({"file": "examples/gallery/examples/plant_allow.luau", "match": "Color3.new(1, 1, 1)", "why": "test"},)
        found, stale, _ = check(temp, allow)
        if found or stale:
            return "selftest: an allowlisted line was reported"
        os.remove(path)
        found, stale, _ = check(temp, allow)
        if not stale:
            return "selftest: a stale allowlist entry was not reported"
        open(os.path.join(folder, "plant_role.luau"), "w").write('local f = UI.Label { textRole = "title" }\n')
        found, _, _ = check(temp, ())
        if found:
            return "selftest: a known textRole was reported"
        return None
    finally:
        shutil.rmtree(temp)


def main():
    if "--selftest" in sys.argv:
        problem = selftest()
        if problem:
            print(f"check_example_drift: FAIL - {problem}")
            return 1
        print("check_example_drift: selftest PASS (R1, R2, R3, R4, allowlist and stale entries)")
        return 0
    violations, stale, scanned = check(REPO)
    for item in violations + stale:
        print("  " + item)
    if violations or stale:
        print(f"check_example_drift: FAIL - {len(violations)} violation(s), {len(stale)} stale allowlist entr(ies) in {scanned} files")
        return 1
    print(f"check_example_drift: PASS - {scanned} example files, {len(ALLOWLIST)} allowlisted literals with reasons")
    return 0


if __name__ == "__main__":
    sys.exit(main())
