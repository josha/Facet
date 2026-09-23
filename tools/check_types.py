#!/usr/bin/env python3
"""Verify the public `app.controls.*` surface with a positive witness and a
negative probe, against the composite registrations in
`src/render/compose_controls.luau`. Dependency-graph diagnostics outside the
target files are reported separately, not silently claimed as clean.

The authoring model this once checked (`local Controls = table.freeze({...})`
in `src/init.luau`, `Facet.Controls`, `Facet.View`, `Facet.newCore`) was
removed when Facet moved onto Compose (`Facet.new()` -> `app.controls`, built
by `controls.new()` in `src/render/compose_controls.luau` from `composite(name,
require(module).build)` registrations plus blueprint primitives). This script
now discovers its namespace from those registrations instead of from a table
literal that no longer exists.

Run: python3 tools/check_types.py [--selftest]
"""

import json
import os
import re
import shutil
import subprocess
import sys

ANALYZER = "luau-lsp"
PLATFORM = "standard"
INIT = "src/init.luau"
CONTROLS_FILE = "src/render/compose_controls.luau"
WITNESS = "tests/types/controls_witness.luau"
LEVEL_TYPES = "src/spec_types/level_picker.luau"
NAVIGATION_TYPES = "src/spec_types/navigation_stack.luau"
BLUEPRINT = "src/blueprint.luau"
TARGETS = [INIT, WITNESS, LEVEL_TYPES]
ARTIFACT = "artifacts/release-candidate-review/perf/types.json"

# The composite() registrations this check knows about. An entry vanishing
# from this set (renamed, de-registered, or rewritten to skip composite()
# entirely) is caught here rather than silently dropping out of the negative
# probe below, which only checks entries it is HANDED. Update this list with
# `namespace_entries()` itself whenever a control is deliberately added or
# retired.
DECLARED_ENTRIES = {
    "Alert", "AsyncImage", "Avatar", "AvatarGroup", "Badge", "Button", "Callout", "Chip", "CollapsibleView", "Dialog",
    "ComboBox", "DisclosureGroup", "Label", "LevelPicker", "Menu",
    "NavigationStack", "NumberInput", "PageView", "Picker", "Popover", "PopupButton", "ProgressView",
    "RadialMenu", "Rating", "RowActions", "Sheet", "ShortcutHint", "Skeleton", "StatusIndicator", "Slider", "SplitButton",
    "Stepper", "TabView", "Table", "TextInput", "Toggle", "VirtualGrid",
    "VirtualList",
}

# Every composite rejects a bare number. Field-specific probes below separately
# check both constructor forms; namespace protection alone cannot prove fields.
DECLARED_UNPROTECTED = set()


def _env():
    env = dict(os.environ)
    extra = [os.path.expanduser("~/.rokit/bin"), "/opt/homebrew/bin", "/usr/local/bin"]
    env["PATH"] = os.pathsep.join([p for p in extra if os.path.isdir(p)] + [env.get("PATH", "")])
    return env


def analyze(paths):
    """-> (list of diagnostic lines attributed to `paths`, whole stdout)."""
    r = subprocess.run(
        [ANALYZER, "analyze", "--platform", PLATFORM, *paths],
        capture_output=True,
        text=True,
        env=_env(),
    )
    out = r.stdout + r.stderr
    wanted = tuple(paths)
    own = [ln for ln in out.splitlines() if ln.startswith(wanted)]
    return own, out


# `api.NAME = composite("NAME", require("../controls/x").build)` or
# `api.NAME = composite("NAME", localVar.build)` where `localVar` was bound by
# a top-of-file `local localVar = require("../controls/x")`.
_COMPOSITE_RE = re.compile(
    r'api\.(\w+) = composite\("\1",\s*(?:require\("([^"]+)"\)|(\w+))\.build\w*\)'
)
_REQUIRE_RE = re.compile(r'local (\w+) = require\("(\.\./controls/[^"]+)"\)')


def namespace_entries(source):
    """-> {control name: module path relative to src/render/, e.g. "../controls/button"}.

    Discovered from the `composite("Name", ...)` registrations in
    `src/render/compose_controls.luau` -- the actual public constructor table
    `Facet.new().controls` is built from (see that file's `controls.new`).
    Primitive constructors (`Text`, `VStack`, ...) are deliberately out of
    scope: they are served by an open `__index` off `blueprint_schema`, not a
    named registration, so there is no fixed list to diff against here.
    """
    aliases = dict(_REQUIRE_RE.findall(source))
    entries = {}
    for name, required, local in _COMPOSITE_RE.findall(source):
        module = required or aliases.get(local)
        if module is None:
            continue
        entries[name] = module
    return entries


def controlSpecAnnotation(modulePath):
    """-> the `spec` annotation `<module>.build`'s EXPORTED signature declares,
    or None when the parameter carries no type (plain `any`/inferred)."""
    path = os.path.normpath(f"src/render/{modulePath}.luau")
    if not os.path.isfile(path):
        return None
    source = open(path).read()
    m = re.search(
        r"function \w+\.build\(\s*Facet(?::\s*\w+)?\s*,\s*core(?::\s*\w+)?\s*,\s*spec(?::\s*([^,)]+))?\s*\)",
        source,
    )
    if m is None:
        return None
    return m.group(1)


def negative_probe(entries):
    """Hand every composite entry a bare NUMBER. -> {entry: True if the analyzer rejected it}."""
    lines = ['--!strict', 'local Facet = require("../../src")', "local app = Facet.new()"]
    order = sorted(entries)
    for i, name in enumerate(order):
        lines.append(f"local _n{i} = app.controls.{name}(42)")
    path = os.path.join("tests", "types", "_negative_probe.luau")
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    try:
        own, _ = analyze([path])
        rejected = set()
        for ln in own:
            m = re.match(r".*\((\d+),\d+\):", ln)
            if m is None:
                continue
            idx = int(m.group(1)) - 4  # 3 header lines, then one call per entry
            if 0 <= idx < len(order):
                rejected.add(order[idx])
        return {name: (name in rejected) for name in order}
    finally:
        os.unlink(path)


# Every negative changes only its intended field. Navigation's valid twins use
# this exact spec with a real path; missing required fields cannot vouch for path.
_NAVIGATION_SPEC = '{ path = PATH, root = { title = "x", content = function() return app.controls.Text({ text = "Home" }) end }, destinations = {}, backLabel = "Back" }'
_NAVIGATION_GOOD_PATH = 'Facet.Compose.cell({} :: { navigationTypes.Entry })'
_EROSION_PROBES = [
    ("Toggle", 'app.controls.Toggle({ value = Facet.Compose.cell(false), hint = 42 })'),
    ("Toggle", 'app.controls.Toggle("Probe")({ value = Facet.Compose.cell(false), hint = 42 })'),
    ("Toggle", 'app.controls.Toggle({ value = Facet.Compose.cell(false), indicatorPosition = "above" })'),
    ("Toggle", 'app.controls.Toggle("Probe")({ value = Facet.Compose.cell(false), indicatorPosition = "above" })'),
    ("Chip", 'app.controls.Chip({ label = "Tag", onRemove = 42 })'),
    ("Chip", 'app.controls.Chip("Probe")({ label = "Tag", onRemove = 42 })'),
    ("Chip", 'app.controls.Chip({ label = "Tag", onRemove = function() end, removeLabel = 42 })'),
    ("Chip", 'app.controls.Chip("Probe")({ label = "Tag", onRemove = function() end, removeLabel = 42 })'),
    ("DisclosureGroup", 'app.controls.DisclosureGroup({ expanded = Facet.Compose.cell(false), content = function() return nil end, appearance = "loud" })'),
    ("DisclosureGroup", 'app.controls.DisclosureGroup("Probe")({ expanded = Facet.Compose.cell(false), content = function() return nil end, appearance = "loud" })'),
    ("DisclosureGroup", 'app.controls.DisclosureGroup({ expanded = Facet.Compose.cell(false), content = function() return nil end, description = 42 })'),
    ("DisclosureGroup", 'app.controls.DisclosureGroup("Probe")({ expanded = Facet.Compose.cell(false), content = function() return nil end, description = 42 })'),

    # BOTH spellings must check their spec: the anonymous form the README uses,
    # and the named form. A probe that passes in one form and is only rejected in
    # the other is exactly the gap this list exists to catch.
    ("Slider", 'app.controls.Slider({ value = "nope", min = 0, max = 1 })'),
    ("Slider", 'app.controls.Slider("S")({ value = "nope", min = 0, max = 1 })'),
    ("Slider", 'app.controls.Slider({ value = Facet.Compose.cell(0), min = 0, max = 1, axis = "z" })'),
    ("Slider", 'app.controls.Slider("S")({ value = Facet.Compose.cell(0), min = 0, max = 1, thumb = "sometimes" })'),
    ("NavigationStack", 'app.controls.NavigationStack(' + _NAVIGATION_SPEC.replace('PATH', '42') + ')'),
    ("NavigationStack", 'app.controls.NavigationStack("N")(' + _NAVIGATION_SPEC.replace('PATH', '42') + ')'),
    ("Label", 'app.controls.Label({ title = 42 })'),
    ("Label", 'app.controls.Label("L")({ title = 42 })'),
    ("Button", 'app.controls.Button({ animation = { scale = 42 } })'),
    ("Button", 'app.controls.Button("B")({ animation = { scale = 42 } })'),
    ("Chip", 'app.controls.Chip({ selected = Facet.Compose.cell(false), animation = { scale = 42 } })'),
    ("Chip", 'app.controls.Chip("C")({ selected = Facet.Compose.cell(false), animation = { scale = 42 } })'),
    ("Toggle", 'app.controls.Toggle({ value = Facet.Compose.cell(false), width = "wide" })'),
    ("Toggle", 'app.controls.Toggle("T")({ value = Facet.Compose.cell(false), width = "wide" })'),
    ("Toggle", 'app.controls.Toggle({ value = "on" })'),
    ("Toggle", 'app.controls.Toggle("T")({ value = "on" })'),
    ("Button", 'app.controls.Button({ controlSize = "tiny" })'),
    ("Button", 'app.controls.Button("Vocabulary")({ controlSize = "tiny" })'),
    ("Button", 'app.controls.Button({ appearance = "loud" })'),
    ("Button", 'app.controls.Button("Vocabulary")({ appearance = "loud" })'),
    ("Button", 'app.controls.Button({ corners = "round" })'),
    ("Button", 'app.controls.Button("Vocabulary")({ corners = "round" })'),
    ("Button", 'app.controls.Button({ over = "panel" })'),
    ("Button", 'app.controls.Button("Vocabulary")({ over = "panel" })'),
    ("Chip", 'app.controls.Chip({ controlSize = "tiny", selected = Facet.Compose.cell(false) })'),
    ("Chip", 'app.controls.Chip("Vocabulary")({ controlSize = "tiny", selected = Facet.Compose.cell(false) })'),
    ("Chip", 'app.controls.Chip({ appearance = "emphasis", selected = Facet.Compose.cell(false) })'),
    ("Chip", 'app.controls.Chip("Vocabulary")({ appearance = "emphasis", selected = Facet.Compose.cell(false) })'),
    ("AsyncImage", 'app.controls.AsyncImage({ key = "art", provider = { acquire = function(): never error("analyzer only") end }, scaleMode = "repeat" })'),
    ("AsyncImage", 'app.controls.AsyncImage("Art")({ key = "art", provider = { acquire = function(): never error("analyzer only") end }, scaleMode = "repeat" })'),
    ("AsyncImage", 'app.controls.AsyncImage({ key = "art", provider = { acquire = function(): never error("analyzer only") end }, resample = "smooth" })'),
    ("AsyncImage", 'app.controls.AsyncImage("Art")({ key = "art", provider = { acquire = function(): never error("analyzer only") end }, resample = "smooth" })'),
    ("AsyncImage", 'app.controls.AsyncImage({ key = "art", provider = { acquire = function(): never error("analyzer only") end }, tileSize = { width = "24", height = 24 } })'),
    ("AsyncImage", 'app.controls.AsyncImage("Art")({ key = "art", provider = { acquire = function(): never error("analyzer only") end }, tileSize = { width = "24", height = 24 } })'),
    ("AsyncImage", 'app.controls.AsyncImage({ key = "art", provider = { acquire = function(): never error("analyzer only") end }, sliceCenter = { x0 = 0, y0 = 0, x1 = "8", y1 = 8 } })'),
    ("AsyncImage", 'app.controls.AsyncImage("Art")({ key = "art", provider = { acquire = function(): never error("analyzer only") end }, sliceCenter = { x0 = 0, y0 = 0, x1 = "8", y1 = 8 } })'),
    ("AsyncImage", 'app.controls.AsyncImage({ key = "art", provider = { acquire = function(): never error("analyzer only") end }, sliceScale = "2" })'),
    ("AsyncImage", 'app.controls.AsyncImage("Art")({ key = "art", provider = { acquire = function(): never error("analyzer only") end }, sliceScale = "2" })'),
    ("Avatar", 'app.controls.Avatar({ name = 3 })'),
    ("Avatar", 'app.controls.Avatar("Ada")({ name = "Ada", presence = "unknown" })'),
    ("Avatar", 'app.controls.Avatar({ name = "Ada", controlSize = "huge" })'),
    ("AvatarGroup", 'app.controls.AvatarGroup({ items = {{ id = 42, name = "Ada" }} })'),
    ("AvatarGroup", 'app.controls.AvatarGroup("Team")({ items = {}, layout = "grid" })'),
    ("AvatarGroup", 'app.controls.AvatarGroup({ items = {}, onOverflow = "show" })'),
    ("ProgressView", 'app.controls.ProgressView({ endLabel = 2 })'),
    ("ProgressView", 'app.controls.ProgressView("Busy")({ presentation = "spinner", controlSize = "huge" })'),
    ("StatusIndicator", 'app.controls.StatusIndicator({ form = "triangle" })'),
    ("StatusIndicator", 'app.controls.StatusIndicator("Count")({ count = "4" })'),
    ("StatusIndicator", 'app.controls.StatusIndicator({ status = "busy" })'),
    ("Badge", 'app.controls.Badge({ label = 4 })'),
    ("Badge", 'app.controls.Badge("Ready")({ label = "Ready", appearance = "emphasis" })'),
    ("Badge", 'app.controls.Badge({ label = "Ready", iconPosition = "above" })'),
    ("Skeleton", 'app.controls.Skeleton({ form = "square" })'),
    ("Skeleton", 'app.controls.Skeleton("Load")({ form = "line", controlSize = "huge" })'),
    ("ShortcutHint", 'app.controls.ShortcutHint({ action = 12 })'),
    ("ShortcutHint", 'app.controls.ShortcutHint("Hint")({ keys = {{"K"}}, controlSize = "huge" })'),
    ("ShortcutHint", 'app.controls.ShortcutHint({ keys = {{"K"}}, separator = 42 })'),
    ("ShortcutHint", 'app.controls.ShortcutHint("Hint")({ action = "Activate", over = "photo" })'),
    ("Dialog", 'app.controls.Dialog({ isPresented = true, closeButton = false, title = "T", width = "huge" })'),
    ("Dialog", 'app.controls.Dialog("D")({ isPresented = true, closeButton = "no", title = "T" })'),
    ("Dialog", 'app.controls.Dialog({ isPresented = true, closeButton = false, actions = { { id = "A", label = "A", role = "primary", onActivate = function() end } } })'),
    ("Popover", 'app.controls.Popover({ isPresented = true, source = { path = "/S/A" }, content = function() return app.controls.Text({ text = "x" }) end, compact = "drawer" })'),
    ("Popover", 'app.controls.Popover("Info")({ isPresented = true, source = { path = "/S/A" }, content = function() return app.controls.Text({ text = "x" }) end, maxWidth = "wide" })'),
    ("Popover", 'app.controls.Popover({ isPresented = "open", source = { path = "/S/A" }, content = function() return app.controls.Text({ text = "x" }) end })'),
    ("Button", 'app.controls.Button("Tracked")({ label = function(use) return tostring(use(42)) end })'),
    ("TextInput", 'app.controls.TextInput({ value = Facet.Compose.cell(""), appearance = "emphasis" })'),
    ("TextInput", 'app.controls.TextInput("Field")({ value = Facet.Compose.cell(""), requiredMark = "maybe" })'),
    ("TextInput", 'app.controls.TextInput({ value = Facet.Compose.cell(""), readOnly = "yes" })'),
    ("TextInput", 'app.controls.TextInput({ value = Facet.Compose.cell(""), selectOnFocus = "everything" })'),
    ("NumberInput", 'app.controls.NumberInput({ value = Facet.Compose.cell("1"), numericValue = Facet.Compose.cell(1), presentation = "search" })'),
    ("Picker", 'app.controls.Picker({ options = {}, selected = Facet.Compose.cell("a"), maxHeight = "96" })'),
    ("Picker", 'app.controls.Picker("P")({ options = {}, selected = Facet.Compose.cell("a"), requiredMark = "maybe" })'),
    ("NumberInput", 'app.controls.NumberInput("Laps")({ value = Facet.Compose.cell("1"), numericValue = Facet.Compose.cell(1), step = "one" })'),
    ("NumberInput", 'app.controls.NumberInput({ value = Facet.Compose.cell("1"), numericValue = Facet.Compose.cell(1), scrub = "yes" })'),
]


def field_erosion_check(entries):
    """-> (eroded: bool, detail: str). Only meaningful if the probed entries
    are still registered composites; skipped otherwise."""
    if not all(name in entries for name, _ in _EROSION_PROBES):
        return None, "probed entries no longer registered; erosion check skipped"
    lines = ['--!strict', 'local Facet = require("../../src")', "local app = Facet.new()"]
    for _, call in _EROSION_PROBES:
        lines.append(f"local _p = {call}")
    lines.append('local navigationTypes = require("../../src/spec_types/navigation_stack")')
    valid_lines = []
    for constructor in ('app.controls.NavigationStack', 'app.controls.NavigationStack("N")'):
        valid_lines.append(len(lines) + 1)
        lines.append(f"local _valid = {constructor}({_NAVIGATION_SPEC.replace('PATH', _NAVIGATION_GOOD_PATH)})")
    path = os.path.join("tests", "types", "_erosion_probe.luau")
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    try:
        own, _ = analyze([path])
        # EVERY probe must draw its own diagnostic: one rejection must not vouch
        # for the rest. Line 4 is the first probe (three header lines precede).
        missed = []
        for offset, (name, _call) in enumerate(_EROSION_PROBES):
            line = 4 + offset
            diagnostics = [ln for ln in own if f"({line}," in ln and "TypeError" in ln]
            if not diagnostics or (name == "NavigationStack" and not any("path" in ln for ln in diagnostics)):
                missed.append(f"{name} ({_call.split(chr(40))[0]}, probe {offset + 1})")
        invalid_twins = [ln for ln in own if any(f"({line}," in ln for line in valid_lines)]
        if invalid_twins:
            return True, "valid NavigationStack twins rejected: " + "; ".join(invalid_twins)
        return (len(missed) > 0), (
            "no diagnostic for a wrongly-typed field on: " + ", ".join(missed)
            if missed
            else f"{len(_EROSION_PROBES)} invalid field/read probes rejected; both valid NavigationStack twins accepted"
        )
    finally:
        os.unlink(path)


def run():
    problems = []
    notes = []

    if shutil.which(ANALYZER, path=_env()["PATH"]) is None:
        print(
            f"check_types: FAIL — `{ANALYZER}` is not on PATH. It is pinned in rokit.toml; "
            "run `rokit install` from the repository root."
        )
        return 1, {"status": "FAIL", "problems": ["analyzer missing"]}

    for t in TARGETS + [CONTROLS_FILE]:
        if not os.path.isfile(t):
            problems.append(f"missing target {t}")
    if problems:
        return 1, {"status": "FAIL", "problems": problems}

    # ---- half 1: the targets themselves are clean --------------------------
    own, whole = analyze(TARGETS)
    for ln in own:
        problems.append(f"type error in a target file: {ln}")
    graph = len([ln for ln in whole.splitlines() if "TypeError" in ln or "SyntaxError" in ln])
    notes.append(
        f"{graph} diagnostic(s) in the require graph, IGNORED by design — this check gates "
        f"the {len(TARGETS)} target files only, never the tree"
    )

    # ---- half 2: the namespace is what compose_controls.luau registers -----
    entries = namespace_entries(open(CONTROLS_FILE).read())
    if not entries:
        problems.append(f"discovered 0 composite entries from {CONTROLS_FILE} — the registration pattern moved")

    witness = open(WITNESS).read()
    named_literals = set(re.findall(r'app\.controls\.(\w+)\("[^"\n]+"\)\(\s*\{', witness))
    missing_witnesses = set(entries) - named_literals
    if missing_witnesses:
        problems.append("missing named literal witness: " + ", ".join(sorted(missing_witnesses)))

    discovered = set(entries)
    if discovered != DECLARED_ENTRIES:
        grew = discovered - DECLARED_ENTRIES
        shrank = DECLARED_ENTRIES - discovered
        if grew:
            problems.append(
                "these composite entries are new — add them to DECLARED_ENTRIES if intended: "
                + ", ".join(sorted(grew))
            )
        if shrank:
            problems.append(
                "these composite entries DROPPED OUT of composite() registration (renamed, "
                "de-registered, or rewritten to skip composite() — a real change to the public "
                "surface, not something this check can wave through): " + ", ".join(sorted(shrank))
            )

    observed = negative_probe(entries)
    for name in sorted(entries):
        rejected = observed.get(name, False)
        expectProtected = name not in DECLARED_UNPROTECTED
        if expectProtected and not rejected:
            problems.append(
                f"`app.controls.{name}` used to reject a bare number and no longer does — "
                "composite() stopped requiring a table, or the entry's build function was "
                "swapped for something that accepts `any` (if intended, add it to "
                "DECLARED_UNPROTECTED with a reason)"
            )
        if not expectProtected and rejected:
            problems.append(
                f"`app.controls.{name}` is declared DECLARED_UNPROTECTED but the analyzer "
                "rejected a number for it — remove it from DECLARED_UNPROTECTED, it is fine"
            )

    eroded, erosionDetail = field_erosion_check(entries)
    if eroded is None:
        notes.append(f"field-erosion check: {erosionDetail}")
    elif eroded:
        problems.append(
            "field-level type checking is ERODED at the app.controls boundary: "
            + erosionDetail
            + ". A wrongly-typed spec field must fail here. The constructor types live in "
            "src/control_types.luau (`Controls`, `Constructor<S>`) and reach authors through "
            "`Facet.new(): App`; a control missing from `Controls`, or a spec widened to `any`, "
            "is the usual cause."
        )
    else:
        notes.append(
            "field-erosion check: explicit Constructor<S> contracts check the probed fields "
            "in named and anonymous forms; " + erosionDetail
        )
        notes.append(
            "limits: primitives and returned nodes remain any; VirtualList/Grid constructor "
            "item parameters remain any. Explicit generic specs can check item shape; these "
            "probes do not establish generic item inference or every anonymous literal's inference"
        )

    specAnnotations = {name: controlSpecAnnotation(entries[name]) for name in entries}
    typedInSource = sorted(n for n, ann in specAnnotations.items() if ann and ann.strip() != "any")
    untypedInSource = sorted(n for n in entries if n not in typedInSource)

    report = {
        "schema": "facet-type-check/2",
        "status": "FAIL" if problems else "PASS",
        "analyzer": ANALYZER,
        "platform": PLATFORM,
        "targets": TARGETS,
        "controlsFile": CONTROLS_FILE,
        "entries": len(entries),
        "rejectsNumber": sorted(n for n, v in observed.items() if v),
        "acceptsNumber": sorted(n for n, v in observed.items() if not v),
        "specTypedInSource": typedInSource,
        "specUntypedInSource": untypedInSource,
        "fieldErosionConfirmed": eroded,
        "graphDiagnosticsIgnored": graph,
        "problems": problems,
        "notes": notes,
    }
    return (1 if problems else 0), report


def selftest():
    """Break the checks on purpose and require the check to notice."""
    backups = {p: open(p).read() for p in (CONTROLS_FILE, WITNESS, NAVIGATION_TYPES, BLUEPRINT)}
    results = []
    try:
        code, _ = run()
        results.append(("unmutated", code == 0, "PASS expected"))

        # M1 — a composite entry's build target swapped for one that accepts a
        # bare number (i.e. stops going through `construct`'s table shape).
        s = backups[CONTROLS_FILE].replace(
            'api.Toggle = composite("Toggle", toggle.build)',
            "api.Toggle = function(_spec: any) end",
            1,
        )
        assert s != backups[CONTROLS_FILE], "M1 anchor missing"
        open(CONTROLS_FILE, "w").write(s)
        code, rep = run()
        bit = code != 0 and any("Toggle" in p for p in rep["problems"])
        results.append(("M1 Toggle stops going through composite()", bit, "FAIL expected"))
        open(CONTROLS_FILE, "w").write(backups[CONTROLS_FILE])

        # M2 — losing a real named literal must fail even if an any placeholder
        # would pass the analyzer. This is coverage, not a field-type claim.
        s, count = re.subn(
            r'local _rowactions = app.controls.RowActions\("RowActions"\)\(\{.*?\n\}\)',
            "local _rowactions = app.controls.RowActions(nil :: any)",
            backups[WITNESS], count=1, flags=re.S,
        )
        assert count == 1, "M2 anchor missing"
        open(WITNESS, "w").write(s)
        code, rep = run()
        bit = code != 0 and any("missing named literal witness: RowActions" in p for p in rep["problems"])
        results.append(("M2 witness loses named literal", bit, "FAIL expected"))
        open(WITNESS, "w").write(backups[WITNESS])

        # M3 — missing unrelated required fields used to hide erased path types.
        s = backups[NAVIGATION_TYPES].replace("path: Compose.Cell<{ Entry }>", "path: any", 1)
        assert s != backups[NAVIGATION_TYPES], "M3 anchor missing"
        open(NAVIGATION_TYPES, "w").write(s)
        code, rep = run()
        bit = code != 0 and any("no diagnostic" in p and "NavigationStack" in p for p in rep["problems"])
        results.append(("M3 NavigationStack path loses type", bit, "FAIL expected"))
        open(NAVIGATION_TYPES, "w").write(backups[NAVIGATION_TYPES])

        # M4 — Bound's tracked callback must receive the real Compose Use.
        s = backups[BLUEPRINT].replace("((use: coreContract.Use) -> T)", "((use: any?) -> T)", 1)
        assert s != backups[BLUEPRINT], "M4 anchor missing"
        open(BLUEPRINT, "w").write(s)
        code, rep = run()
        bit = code != 0 and any(WITNESS in p and "ButtonSpec" in p for p in rep["problems"])
        results.append(("M4 Bound rejects the valid tracked label", bit, "FAIL expected"))
        open(BLUEPRINT, "w").write(backups[BLUEPRINT])
    finally:
        for p, text in backups.items():
            open(p, "w").write(text)

    ok = all(bit for _label, bit, _want in results)
    print("check_types --selftest:", "PASS" if ok else "FAIL")
    for label, bit, want in results:
        print(f"  [{'ok' if bit else 'MISS'}] {label} ({want})")
    return 0 if ok else 1


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    code, report = run()
    os.makedirs(os.path.dirname(ARTIFACT), exist_ok=True)
    with open(ARTIFACT, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    if code == 0:
        print(
            f"check_types: PASS — {report['entries']} app.controls entries discovered from "
            f"{CONTROLS_FILE}; {len(TARGETS)} target files carry 0 diagnostics; "
            f"{report['graphDiagnosticsIgnored']} graph diagnostics ignored by design -> {ARTIFACT}"
        )
        for n in report["notes"]:
            print(f"  note: {n}")
    else:
        print("check_types: FAIL")
        for p in report["problems"]:
            print(f"  - {p}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
