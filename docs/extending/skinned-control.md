# Playbook: a custom control that ships its own art (rung 3)

Audience: an agent (or developer) with NO prior context on this repository, who
has decided that the look they want is **not a variation of anything Facet
ships**. That is rung 3 of the customization ladder
([`../guide/10-rich-skinning.md`](../guide/10-rich-skinning.md) §10.11); rungs 1
and 2 are a theme package and a per-view override, and you should be sure you
need this one.

> **What this document is, in plain words.** You are writing a control nobody in
> the framework knows about — a boiler-pressure gauge, a rune wheel, a stamina
> orb. It brings its own pictures. It should still get *bigger* when the player's
> theme has bigger controls, and it should still be the *right colour* when they
> switch to the night palette. This playbook is how you wire those two facts
> together, and how a theme author finds out — before pressing Play — that their
> package forgot about you.

Read [`../reference/constitution.md`](../reference/constitution.md) first — the
rules your addition must follow.

The worked example is
[`examples/themes/ornate_gauge.luau`](../../examples/themes/ornate_gauge.luau)
with its art in `assets/themes/ornate-gauge/`. Read it beside this file: it is
one module and it is the whole answer.

## 0. Ground rules

- Work from the library root: `GameStudio/ui/Facet` (use absolute paths in shell
  commands, because a relative path run against the wrong working directory is
  the single most expensive mistake recorded here).
- **Public API only.** A control written outside this repository gets
  `Facet.UI`, `Facet.themes`, the resolved snapshot, and the compiled package's
  own plain data. That is the whole seam. If your control needs
  `src/tokens/chrome_slots` or any other internal require, stop: that is a hole
  in the public API, and the honest move is to file it rather than to reach
  through it.
- A composite control that is *interactive* is also a `new-control.md` job — the
  four-input bar, the affordance matrix and the registration checker all apply.
  This playbook covers only the **theme-contribution and art** half; do
  [`new-control.md`](new-control.md) for the control contract itself.
- Test-first. Never mark done while `./run-tests.sh` is red, and the suite total
  must grow.

## 1. Decide what the THEME owns

This is the whole design decision, and getting it wrong is what makes a
contributed control feel bolted on.

| Belongs to the CONTROL | Belongs to the THEME |
|---|---|
| the pictures | how tall the control is |
| the structure (what is drawn where) | what colour its accent is |
| the behaviour | its corner radius, its spacing |

The rule of thumb: **anything a theme author would reasonably want to change
across their whole game is theirs.** A gauge's needle colour is theirs (it should
match the palette). The gauge's *needle shape* is yours (it is the control).

Declare the theme's half as namespaced needs. There are exactly three kinds, and
each has one legal home:

| `kind` | `section` | what a package writes |
|---|---|---|
| `controlSize` | `metrics.controlSizes` | `["ns:role"] = { height, paddingX, iconSize }` |
| `color` | `style.themes[].extra` | `["ns:role"] = { r, g, b }` — **in every theme** |
| `number` | a plain metric section, e.g. `metrics.radii` | `["ns:role"] = <number>` |

```lua
ornate_gauge.needs = table.freeze({
    { name = "gauge:dial",   kind = "controlSize", section = "metrics.controlSizes",
      fields = { "height", "paddingX", "iconSize" },
      authority = "layout", capability = "none",
      fallback = { height = 44, paddingX = 12, iconSize = 18 } },
    { name = "gauge:needle", kind = "color", section = "style.themes[].extra",
      authority = "paint", capability = "none",
      fallback = { r = 0.75, g = 0.58, b = 0.23 } },
    { name = "gauge:ring",   kind = "number", section = "metrics.radii",
      authority = "paint", capability = "none", fallback = 6 },
})
```

Every field is load-bearing:

- **`name` must be namespaced** (`ns:role`). `checkCoverage` rejects a bare name,
  and `themes.define` only passes a *namespaced* key through unvalidated.
- **`authority`** is `"layout"` or `"paint"` — the same line the whole theme
  system is built on. A `layout` value feeds the solver; a `paint` value may
  never move anything.
- **`fallback` is not optional.** It is what makes an uncovered package *degrade*
  instead of erroring, which is the only acceptable behaviour when somebody
  installs a theme that predates your control.

**Sections that do NOT work, so you do not lose an afternoon finding out:**
`metrics.controls` is a closed family list (`slider`, `table`, `progress`, …) and
rejects `["ns:role"]` by name. A bare number in `metrics.controlSizes` compiles
and then breaks `themes.resolve`, because every entry there is expected to be a
`{ height, … }` table. Put plain numbers in `metrics.radii`, `metrics.space` or
another open scalar section.

## 2. Ask the package, before Play

```lua
function ornate_gauge.check(themes: any, package: any): any
    return themes.checkCoverage(package, ornate_gauge.needs)
end
```

That is the whole implementation, and it should stay that way. `checkCoverage`
returns `{ ok, covered, missing = { { name, message, fix } } }` and owns the
message, so your control and the framework can never disagree about what
"covered" means. (The Step 3.5 predecessor,
[`custom_control.luau`](../../examples/themes/custom_control.luau), hand-wrote
this check because the gate did not exist yet, and its own comment promised it
would become a thin call once it did. It has.)

What an uncovering package produces — this is the bar for a useful error, and it
is worth reading once:

```
gauge:dial — package 'classic-desktop' declares no 'gauge:dial' control size; the
contributed control falls back to its built-in metrics and stops following the theme
  fix: add metrics.controlSizes["gauge:dial"] = { height = .., paddingX = .., iconSize = .. }

gauge:needle — theme(s) Day, Night of package 'classic-desktop' declare no
'gauge:needle', so the contributed control paints its built-in colour and ignores the palette
  fix: add extra["gauge:needle"] = { r = .., g = .., b = .. } to every theme

gauge:ring — package 'classic-desktop' declares no 'gauge:ring' in metrics.radii
  fix: add metrics.radii["gauge:ring"] = <number>
```

The name, the consequence *the player would see*, and the exact line to add.
Wire the call into your build or your test suite so nobody has to remember it.

## 3. Resolve from the SNAPSHOT, not from the package

```lua
function ornate_gauge.resolve(snapshot, package, themeName)
    local size = (snapshot.controlSizes or {})["gauge:dial"]
    local ring = (snapshot.radii or {})["gauge:ring"]
    -- …fall back per need when either is absent…
end
```

The **snapshot** is the metric authority: it is what the solver reads, it carries
derivation, floors and pixel-mode snapping, and it is what a live Style-Editor
metric edit moves. Reading `package.metrics` directly gets you a number the
solver may not be using.

The **package** is consulted only for the per-theme paint role, because palettes
are per theme and a snapshot is one resolved theme's worth of metrics.

Return the `usedFallback` flags too. A control that silently used its fallback
looks identical to one that was covered, and that is the state you most want
visible in a dump.

## 4. Ship your art like a package ships art

Your art goes in `assets/themes/<your-control>/` and owes the **same** provenance
obligations a theme package's art does
([`new-theme.md`](new-theme.md) §5) — with one difference recorded at the top of
the folder: it belongs to a control, so `upload-manifest.json` carries
`"package": null` and names the control module instead.

1. **Original, repository-owned art only.** No external imagery, no third-party
   asset, no trade dress.
2. **A generator, a seed, and a byte-for-byte regeneration command** in
   `provenance.md`, plus the library versions it was produced with.
3. **`upload-manifest.json`** mapping each file to the content ID the control
   references. The IDs in the manifest and the IDs in the module must agree;
   `check_docs_cli` fails when they drift.
4. **A contact sheet** under `source/preview/` so a lead can judge the art on
   disk without opening Studio.

**THE MANIFEST IS THE REGISTRATION — there is no list to edit.** A manifest that
declares `"control": "<YourControl>"` with `"package": null` registers the whole
directory: `tools/lune/skinned_controls.luau` enumerates every such root, and
`check_docs_cli` then requires each file the manifest's own `assets` table names,
plus `provenance.md`, plus every generator under `source/`. Until 2026-08-17 that
enforcement was hardcoded to `assets/themes/ornate-gauge`, so this section
promised a contributor a check that only ever ran on the worked example
(MAINT-8d). Get the manifest right and your art is protected; get it wrong — a
missing `control`, a non-null `package` — and the directory is silently
unenforced, which is why the field values above are not decoration.

### Design the art for the authority you actually have

A control paints through the public `UI.Image`, which has **no `sliceCenter` and
no tint** — nine-slice geometry and `ImageColor3` are theme-recipe authority
(`new-theme.md` §1), and a control may not reach them. Do not fight that; author
around it:

- **Anything that must stretch should be invariant along the stretch axis.** The
  gauge's channel art is authored as a column of 64 colours repeated across the
  width, so every column is byte-identical and a horizontal stretch is lossless.
  The generator **asserts** that property after writing the file, so "stretching
  this is fine" is checked rather than claimed.
- **Anything that must not stretch gets a fixed px box.** The needle and the end
  caps are drawn at their authored size and never scaled.
- **You cannot mirror an image** (`Rotation` and `ImageRect*` are presentation
  and theme authority), so a piece used at both ends must read correctly
  unflipped — light it from above, not from a side.

### Where a theme colour can actually land

Today the one public per-view paint channel that takes an explicit colour is
**`UI.shadow`**. Everything else public is semantic (a `surface` name), by design:
a control may not invent fills. So a namespaced `color` role typically becomes a
glow behind your art:

```lua
local needle = UI.shadow(UI.Image({ id = "Needle", image = ART.needle, … }), {
    blurRadius = { scale = 0, offset = 18 },
    color = resolved.needle,          -- the THEME's colour
    transparency = 0.35,
    zIndex = -1,                      -- MUST be negative
})
```

You can also let the theme paint *around* your art: a `UI.Box` with
`surface = "raised"` gets the package's whole panel recipe, layers and all. In
the shipped capture the gauge sits inside Fantasy Ornate's carved gold frame for
exactly that reason, and inside Pixel Quest's wooden one under the other package
— with no change to the control.

## 5. Re-theme live, and be honest about what does not

A framework control re-solves on a package swap because it reads the snapshot.
Yours can too — bind the values you resolved to **reactive props**:

```lua
-- `height` is reactive, so writing the new resolved height into this signal
-- re-sizes the control in the same frame, with no rebuild and no remount
local dialHeight = core:memo(function(use) return { type = "fixed", px = use(heightPx) } end)
```

Then, from your `controller.onChange` handler, re-run `resolve(...)` and write
the signal.

**What does NOT update that way, and why:** `UI.shadow` and `UI.corners` are
functions that normalize eagerly and return a new blueprint — they are not
reactive props you can hand a `Readable`. A shadow colour or a corner radius
therefore changes only when you rebuild the blueprint. Do not route around this
with hand-built "normalized" tables; state it in your control's documentation the
way `ornate_gauge.luau` does. A control that hides when its paint updates is
lying about its own contract.

Measured live at stamp `4d7e87c7-1615388`, `fantasy-ornate` → `pixel-quest`: the
dial moved 56 px → 48 px and its radius 8 → 4, all 12 of the gauge's
mount-identity entries stayed byte-identical, `rebuilt = false` — and the needle
glow kept the colour it was built with, exactly as the paragraph above predicts.

## 6. Required tests

Add cases to the existing specs rather than a new file:

| Spec | What to add |
|---|---|
| `tests/theme_reference_packages.spec.luau` | the declaration is complete and namespaced; `check` agrees with `themes.checkCoverage` on every package; TWO covering packages resolve DIFFERENTLY; an uncovering package produces the error AND a control that still runs; no theme names your art |
| `tests/theme_authoring_scenario.spec.luau` | the fixture mounts, the control's own art is on its own nodes, a package swap re-sizes it with the SAME node object, and coverage answers both directions |

One covering package proves nothing about re-theming. Use two.

## 7. Studio evidence

Headless conformance proves the decisions. It does not prove Roblox drew
anything. Drive
[`examples/gallery/scenarios/theme_authoring.luau`](../../examples/gallery/scenarios/theme_authoring.luau)
— steps `presentGaugeFixture`, `gaugeProbe`, `gaugeCoverage`,
`dismissGaugeFixture` are the rung-3 fixture — and pair every capture with the
geometry, the resolved values, the `isLoaded` state of each picture and the mount
identity across a swap. The scenario returns all of them in one object.

Keep physical-device, human-judgment and low-end-performance rows explicitly
pending. A Studio run closes none of them.

## 8. Gate obligations

```sh
./run-tests.sh                                   # suite green, count grew
lune run tools/lune/check_docs_cli               # docs match the shipped surface
lune run tools/lune/check_registration_cli       # every public export documented
lune run tools/lune/check_prop_parity_cli        # property views agree
```

`check_docs_cli` enforces that this playbook exists, that the guide links it,
that the rung-3 example still builds through `themes.checkCoverage`, and that
**every** skinned control's art, provenance and manifest exist and agree — yours
included, derived from your manifest (§4). Never edit the acceptance ledger or
the gate manifest; name them in your report instead.

## Common traps

- **Reaching for a decoration slot.** Decoration slots are a closed framework
  vocabulary; `chrome.myThing` is a compile error, and adding a slot is a schema
  change (`new-theme.md` §3–§4). Reach the existing slots through the public
  `surface` prop instead.
- **Resolving at build time and calling it themed.** If nothing is bound to a
  reactive prop, your control follows the theme only until the first swap.
- **A `number` need in the wrong section.** See §1 — `metrics.controls` rejects
  it and `metrics.controlSizes` breaks the snapshot.
- **Naming your art from the theme.** A package should never have to know your
  content IDs. If it does, you have put the control's identity in the theme's
  hands and a package that forgets it will paint nothing.
- **A picture that stretches badly.** Whole art has no slice geometry. Author for
  the stretch or do not stretch it (§4).
