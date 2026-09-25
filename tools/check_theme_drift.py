#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ALLOWLIST = os.path.join("tools", "theme_drift_allowlist.json")
THEME = "src/ui/themes.luau"
EXCLUDED = ("src/vendor/",)
STATUSES = {
    "structural": "derived from the part's own geometry or an invisible structural surface",
    "no-metric": "the theme package defines no metric or role for this sub-part",
    "authored": "the value is the caller's authored override, not default paint",
}
METRICS = {
    "radius": ("radii", re.compile(r"\bradii\s*=\s*\{([^}]*)\}")),
    "stroke": ("strokes", re.compile(r"\bstrokes\s*=\s*\{([^}]*)\}")),
    "type-size": ("typography", re.compile(r"\{\s*(caption\s*=[^}]*)\}")),
}
COLOR = re.compile(r"\b(?:Color3\.(?:new|fromRGB|fromHex|fromHSV)|BrickColor\.\w+)\s*\(")
OPACITY = re.compile(r"\b(\w*Transparency)\s*=\s*(0?\.\d+)\b")
TEXT_SIZE = re.compile(r"\bTextSize\s*=\s*(\d+(?:\.\d+)?)\b")
FONT = re.compile(r"\b(?:FontFace\s*=\s*[\w.]*Font\.(?:new|fromEnum|fromName|fromId)|Font\s*=\s*[\w.]*Enum\.Font\.)")
CORNER_UDIM = re.compile(r"\bCornerRadius\s*=\s*[\w.]*\.new\(\s*[^,()]+,\s*(\d+(?:\.\d+)?)\s*\)")
CORNER_CALL = re.compile(r"\bctx\.corner\(([^()]*(?:\([^()]*\)[^()]*)*)\)")
STROKE = re.compile(r"\bThickness\s*=\s*(\d+(?:\.\d+)?)\b")
REACTIVE = re.compile(r"\b(TextSize|LineHeight|CornerRadius|Thickness)\s*=\s*function\s*\(")
NUMBER = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])")
STRING = re.compile(r"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`")
FAMILY = {"TextSize": "type-size", "LineHeight": "type-size", "CornerRadius": "radius", "Thickness": "stroke"}


def code(line):
    return STRING.sub('""', line)


def literals(text):
    return [value for value in NUMBER.findall(code(text)) if float(value) not in (0.0, 1.0)]


def indent(line):
    return len(line) - len(line.lstrip("\t "))


def metric_values(root):
    with open(os.path.join(root, THEME), encoding="utf-8") as handle:
        theme = handle.read()
    values = {}
    for family, (section, pattern) in METRICS.items():
        found = pattern.search(theme)
        if not found:
            values[family] = None
            continue
        names = {}
        for name, number in re.findall(r"(\w+)\s*=\s*(\d+(?:\.\d+)?)", found.group(1)):
            names.setdefault(float(number), []).append(f"{section}.{name}")
        values[family] = {number: " or ".join(labels) for number, labels in names.items()}
    return values


def scan_file(relative, lines, metrics):
    found = []

    def add(number, rule, text, values=()):
        hints = []
        table = metrics.get(rule) or {}
        for value in values:
            name = table.get(float(value))
            if name:
                hints.append(f"{value} is the neutral {name}")
        found.append({"path": relative, "line": number, "rule": rule, "text": text.strip(), "hint": "; ".join(hints)})

    index = 0
    while index < len(lines):
        raw = lines[index]
        line = code(raw)
        number = index + 1
        if COLOR.search(line):
            add(number, "paint-color", raw)
        for prop, value in OPACITY.findall(line):
            if 0 < float(value) < 1:
                add(number, "paint-opacity", raw)
        for value in TEXT_SIZE.findall(line):
            add(number, "type-size", raw, [value])
        if FONT.search(line):
            add(number, "type-face", raw)
        for value in CORNER_UDIM.findall(line):
            if float(value) != 0:
                add(number, "radius", raw, [value])
        for argument in CORNER_CALL.findall(line):
            values = literals(argument)
            if values:
                add(number, "radius", raw, values)
        for value in STROKE.findall(line):
            add(number, "stroke", raw, [value])
        reactive = REACTIVE.search(line)
        if reactive:
            depth = indent(raw)
            body = index + 1
            while body < len(lines) and not (indent(lines[body]) == depth and lines[body].strip().startswith("end")):
                values = literals(lines[body])
                if values:
                    add(body + 1, FAMILY[reactive.group(1)], lines[body], values)
                body += 1
        index += 1
    return found


def sources(root):
    paths = []
    for path in sorted(glob.glob(os.path.join(root, "src", "**", "*.luau"), recursive=True)):
        relative = os.path.relpath(path, root).replace(os.sep, "/")
        if relative == THEME or relative.startswith(EXCLUDED):
            continue
        paths.append(relative)
    return paths


def check(root=REPO):
    problems = []
    metrics = metric_values(root)
    for family, values in metrics.items():
        if not values:
            problems.append(f"[rule] {THEME} no longer declares the {METRICS[family][0]} metrics the '{family}' rule protects")
    metrics = {family: values or {} for family, values in metrics.items()}
    try:
        with open(os.path.join(root, ALLOWLIST), encoding="utf-8") as handle:
            allowlist = json.load(handle)
    except (OSError, ValueError) as error:
        return [f"[allowlist] cannot read {ALLOWLIST}: {error}"], [], {}
    entries = allowlist.get("entries") if isinstance(allowlist, dict) else None
    if not isinstance(entries, list):
        return [f"[allowlist] {ALLOWLIST} must hold an 'entries' list"], [], {}
    for position, entry in enumerate(entries):
        where = f"{ALLOWLIST} entries[{position}]"
        if not isinstance(entry, dict):
            problems.append(f"[allowlist] {where} is not an object")
            continue
        for field in ("path", "rule", "match", "reason", "status"):
            if not isinstance(entry.get(field), str) or not entry[field].strip():
                problems.append(f"[allowlist] {where} needs a non-empty '{field}'")
        if entry.get("status") not in STATUSES:
            problems.append(f"[allowlist] {where} status must be one of {sorted(STATUSES)}")
        if isinstance(entry.get("reason"), str) and len(entry["reason"].split()) < 6:
            problems.append(f"[allowlist] {where} reason is too short to justify an exception")
    entries = [entry for entry in entries if isinstance(entry, dict)]
    used = [0] * len(entries)
    scanned = 0
    allowed = []
    for relative in sources(root):
        with open(os.path.join(root, relative), encoding="utf-8") as handle:
            lines = handle.read().split("\n")
        scanned += 1
        for finding in scan_file(relative, lines, metrics):
            covering = [
                position
                for position, entry in enumerate(entries)
                if entry.get("path") == relative and entry.get("rule") == finding["rule"] and isinstance(entry.get("match"), str) and entry["match"] in finding["text"]
            ]
            if covering:
                for position in covering:
                    used[position] += 1
                allowed.append((finding, entries[covering[0]]))
                continue
            hint = f" ({finding['hint']}; read it from the theme)" if finding["hint"] else ""
            problems.append(f"[{finding['rule']}] {finding['path']}:{finding['line']}: {finding['text']}{hint}")
    for position, entry in enumerate(entries):
        if not used[position]:
            problems.append(f"[allowlist] stale entry {entry.get('path')} {entry.get('rule')} '{entry.get('match')}' matches nothing")
    return problems, allowed, {"files": scanned}


def selftest():
    plants = [
        ("a hardcoded paint color in a control", "src/ui/inputs.luau", "BackgroundColor3 = Color3.fromRGB(40, 40, 40),", "paint-color"),
        ("a fractional opacity literal", "src/ui/inputs.luau", "BackgroundTransparency = 0.35,", "paint-opacity"),
        ("a literal text size", "src/ui/nav_menu.luau", "TextSize = 18,", "type-size"),
        ("a hardcoded font face", "src/ui/nav_menu.luau", 'FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json"),', "type-face"),
        ("a literal control corner radius", "src/ui/collections.luau", "Host.UICorner({ CornerRadius = D.new(0, 8) }),", "radius"),
        ("a literal radius through the corner helper", "src/ui/collections.luau", "ctx.corner(8),", "radius"),
        ("a named corner table inside a reactive radius", "src/ui/media.luau", "CornerRadius = function(use)\n\t\t\t\treturn D.new(0, ({ square = 0, rounded = 8 }).rounded)\n\t\t\tend,", "radius"),
        ("a literal stroke thickness", "src/ui/media.luau", "Thickness = 2,", "stroke"),
        ("a literal inside a reactive text size", "src/ui/media.luau", "TextSize = function(use)\n\t\t\t\treturn 18\n\t\t\tend,", "type-size"),
    ]
    control, _, _ = check()
    ok = True
    if control:
        print("  control: the unplanted tree is red")
        for problem in control:
            print(f"      -> {problem}")
        ok = False
    else:
        print("  control: the unplanted tree passes")
    for label, relative, planted, rule in plants:
        work = tempfile.mkdtemp(prefix="facet-theme-drift-")
        try:
            shutil.copytree(os.path.join(REPO, "src"), os.path.join(work, "src"))
            os.makedirs(os.path.join(work, "tools"))
            shutil.copy2(os.path.join(REPO, ALLOWLIST), os.path.join(work, ALLOWLIST))
            target = os.path.join(work, relative)
            with open(target, encoding="utf-8") as handle:
                text = handle.read()
            with open(target, "w", encoding="utf-8") as handle:
                handle.write(text + "\nlocal planted = {\n\t\t\t" + planted + "\n}\n")
            problems, _, _ = check(work)
        finally:
            shutil.rmtree(work, ignore_errors=True)
        bitten = [problem for problem in problems if problem.startswith(f"[{rule}] {relative}")]
        print(f"  [{'BITES' if bitten else 'MISSED'}] {label}")
        for problem in (bitten or problems)[:1]:
            print(f"      -> {problem}")
        ok = ok and bool(bitten)
    work = tempfile.mkdtemp(prefix="facet-theme-drift-")
    try:
        shutil.copytree(os.path.join(REPO, "src"), os.path.join(work, "src"))
        os.makedirs(os.path.join(work, "tools"))
        with open(os.path.join(REPO, ALLOWLIST), encoding="utf-8") as handle:
            data = json.load(handle)
        data["entries"].append({"path": "src/ui/inputs.luau", "rule": "radius", "match": "ctx.corner(77)", "reason": "short", "status": "maybe"})
        with open(os.path.join(work, ALLOWLIST), "w", encoding="utf-8") as handle:
            json.dump(data, handle)
        problems, _, _ = check(work)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    for label, expect in (("a stale allowlist entry", "stale entry"), ("an allowlist entry without a real reason", "reason is too short"), ("an allowlist entry with an unknown status", "status must be")):
        bitten = [problem for problem in problems if expect in problem]
        print(f"  [{'BITES' if bitten else 'MISSED'}] {label}")
        ok = ok and bool(bitten)
    return ok


def main():
    parser = argparse.ArgumentParser(description="Refuse theme-owned paint and metric literals in framework control code.")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        print("check_theme_drift --selftest")
        passed = selftest()
        print("check_theme_drift --selftest: " + ("every rule bites" if passed else "a rule did not bite"))
        raise SystemExit(0 if passed else 1)
    problems, allowed, counts = check()
    if problems:
        print(f"check_theme_drift: {len(problems)} problem(s)")
        for problem in problems:
            print(f"  - {problem}")
        raise SystemExit(1)
    tally = {}
    for _, entry in allowed:
        tally[entry["status"]] = tally.get(entry["status"], 0) + 1
    detail = ", ".join(f"{count} {status}" for status, count in sorted(tally.items()))
    print(f"check_theme_drift: clean ({counts['files']} framework files outside {THEME}; {len(allowed)} allowlisted literal(s): {detail})")
    raise SystemExit(0)


if __name__ == "__main__":
    main()
