# Handoff — Facet showcase place, device-fix pass

**Written:** 2026-07-26, end of session. **For:** a fresh context continuing the
device-driven bug fixing on `examples/places/Facet-Showcase.rbxl`.

Read this, then `docs/guide/11-device-verification.md` §"The hands-on place".

---

## 0. The one-paragraph state

The showcase place (one publishable `.rbxl` where the demo AND the theme are
switchable in game) exists and works. A director pass on a **physical iPhone 15
Pro** found nine defects across rounds 1–2 and **six more in round 3**; all are
fixed in the tree and the suite is green at **2058**. Round 3's six turned out to
be **seven framework defects and one missing control** — almost nothing was an
example bug — and every fix is proven headlessly against the real themes. NONE of
round 3 has been seen on a device yet. §3 is rounds 1–2; **§3b is round 3**.

**Gates:** `cross-platform-proof`, `rich-skinning-v2`,
`theme-packages-and-skinning`, `native-stylesheets` all PASS. Step 4's
fresh-context review closed at **READY TO DECLARE** (round 7).

---

## 1. First thing to do

```bash
cd GameStudio/ui/Facet
./tools/test.sh                       # expect 2058
./tools/gate.sh cross-platform-proof  # expect PASS
```

Then **open `examples/places/Facet-Showcase.rbxl` fresh** and press Play.

> ⚠️ If a Studio session from the last run is still open, its scripts hold
> PUSHED sources from mid-session and are **older than the tree**. The `.rbxl`
> on disk is authoritative. Reopen it.

### Prove which build you are looking at — this cost a whole round

On 2026-07-27 a director round reported four defects that had all been fixed the
day before. Every one was a stale Studio session: the `.rbxl` on disk was
current, the session was not. Two sub-agents spent an hour refuting reports
against a tree that was already correct.

**Never reason about a capture until you know which build produced it.** Rojo's
binary `.rbxl` is compressed, so `strings` on it is worthless — it finds a marker
one build and misses the same marker the next. Build the XML form and grep that:

```bash
rojo build examples/showcase.project.json -o /tmp/showcase.rbxlx
grep -c "newRating" /tmp/showcase.rbxlx      # a marker only the new code has
```

That proves what the BUILD contains. To prove what the SESSION is running, ask
the running place, through the MCP bridge (§2):

```lua
-- in the Edit datamodel
return (game:GetService("ReplicatedStorage").Facet.controls :: any):FindFirstChild("rating") ~= nil
```

A `false` there with a `1` from the grep above means: close the place and reopen
it. Do that BEFORE writing down a single finding.

---

## 2. The development loop (this is the useful part)

Rojo's live sync was never connected for this place. What worked instead — and
what makes the loop fast — is pushing sources into the open Studio over HTTP so
**no file content passes through the agent's context**:

```bash
# once
python3 -m http.server 34874 --bind 127.0.0.1     # serve the repo root
```

Then in Studio (**Edit** datamodel, via the MCP `execute_luau`):

```lua
game:GetService("HttpService").HttpEnabled = true  -- needed once per place
local Http, B = game:GetService("HttpService"), "http://127.0.0.1:34874/"
local g  = game:GetService("StarterPlayer").StarterPlayerScripts.Gallery
local rs = game:GetService("ReplicatedStorage")
;(g :: any).Source              = Http:GetAsync(B .. "examples/gallery/client/init.client.luau")
;(g.demo_picker :: any).Source  = Http:GetAsync(B .. "examples/gallery/client/demo_picker.luau")
;(g.theme_picker :: any).Source = Http:GetAsync(B .. "examples/gallery/client/theme_picker.luau")
;(rs.Facet.render.renderer :: any).Source = Http:GetAsync(B .. "src/render/renderer.luau")
return "synced"
```

Push → Play → measure → Stop → push again. **Always re-run
`./tools/build_places.sh` before handing the place back**, or the `.rbxl` and the
tree disagree.

### Driving it without a pointer

Injected input **does not deliver events** in this Studio (the open XP-B3
limitation — `VirtualInput` methods exist and are callable, calls succeed, no
`InputBegan` arrives). So the place publishes `workspace.FacetShowcaseAPI` as
BindableFunctions (the MCP runs in a different Luau VM, so `_G` does not cross
but the DataModel does):

```lua
local api = workspace.FacetShowcaseAPI
api.showNext:Invoke("1")            -- {"current":"ex03","mounted":"ex03","ok":true}
api.current:Invoke()                 -- the same three fields
api.toggleThemes:Invoke()            -- open/close the theme panel
api.themes:Invoke()                  -- {"entries":[...],"current":{...}}
api.pickTheme:Invoke("fantasy-parchment")
```

**`current` is what was ASKED for; `mounted` is what is on the screen.** They
differ whenever a demo's build throws — `mountDemo` runs under a `pcall`, so the
failure is a client-console `warn` no scripted caller sees. `mounted` is `false`
then and `ok` is `false`, and a sweep that reads only `current` measures whatever
surface is still standing (measured 2026-08-15: a sweep took a leftover surface
for the demo it had asked for, 21 times, and reported it clean). **Never take the
id on faith, and destroy anything you mount yourself in the same call.**

**Caveat that matters:** `pickTheme` routes through `theme_picker.dispatch`,
which is *not* the path a tap takes any more (§4.1). Driving it proves the theme
APPLIES; it does **not** prove the button works. Only a real tap does that.

---

## 3. The nine device findings and their verification status

| # | Reported | Fix | Verified |
|---|---|---|---|
| 1 | Settings sync: music toggles on, never off | host flushes the loopback server each frame | **headless only** (2 tests) |
| 2 | Confirm dialog has no visible boundary | dialog is now `scrim` + centred `raised` card | **headless only** |
| 3 | The two chips overlap | both chips in ONE solver-laid-out HStack | **live** (8..107 / 115..235) |
| 4 | Theme list cut off on the right (portrait) | panel is a full-width child of the chrome column | **live** (right edge == viewport) |
| 5a | Theme list mislaid in landscape | panel scrolls inside its own card | **live** (portrait only) |
| 5b | Tapping a theme does nothing | see §4.1 | **headless only** |
| 6a | Table rows cramped | `rowHeight` 34 → 48 | **headless only** |
| 6b | Filter clear button invisible | `surface = "chip"` on the clear button | **not verified** |
| 7 | Panel clipped to a rectangle, scrollbar detached | ONE node is card + scroller | **live** (capture) |

Also fixed, unprompted but found on the way:

- the backdrop drew a rectangle inside the safe area with the world showing
  around it → `rootPolicy = "edgeToEdge"` (**live**, 677x338 == viewport);
- **"Fantasy Parchment (stub)"** — a deliberately-broken test fixture — was
  showing in the player-facing theme list; it now declares `testOnly = true`
  (**live**, 9 entries).

### What is NOT verified anywhere

- **every fix, on the actual phone.** Studio-emulated is not a device.
- the confirm dialog's scrim/card, the playlist rows and the clear button on any
  screen at all;
- **landscape and notched safe areas** — `reserveBar` now carries the adapter's
  other three edges through instead of zeroing them, but that row was never
  re-driven (ledger XP-S4 says so explicitly).

---

## 3b. Round 3 (2026-07-26): six reports, seven framework fixes

Reported against six phone captures. The example was barely at fault — six of the
seven fixes are in `src/`, and the seventh is a new control.

| # | Reported | Root cause | Fixed in |
|---|---|---|---|
| 1 | Theme card far bigger than its list (portrait, Studio Neutral); too wide in Fantasy Ornate | the algebra had no "hug, capped by the offer" — `content` never caps, `fill` never hugs | **new `hug` dim**, `src/layout/solver.luau` |
| 2 | Theme list cut off at the bottom in Fantasy Ornate and would not scroll | a `fill` anchor child took the WHOLE box and was THEN displaced by `offsetY`, so the chrome column hung off the phone by the topbar inset | `src/layout/solver.luau` anchor arrange |
| 1b | ...and the card was still full-width with a narrow column of chips inside | a `uniform` Grid measured the COLUMN width and drew the CELL width | `src/layout/solver.luau` grid `contentSize` |
| 3 | Ugly blur behind the stars (Glossy Mobile) | `surface = "plain"` was honoured by native paint and IGNORED by the chrome classifier, so every star still got the package's `control` recipe — art in one theme, a drop shadow in another | `src/tokens/chrome_slots.luau` `classify` |
| 4a | Row text overflows the row card (Glossy Touch, Pixel Quest, Compact) | a row's painted card and its cells are DIFFERENT nodes, so the renderer's inset reservation landed on a childless hit button and nothing spent it | `src/controls/table.luau` + `chromeInsets` as a readable metric |
| 4b | Edit button clipped to "E" / empty | `fixed` 56×24 could not grow for the theme's own frame | `src/controls/table.luau` |
| 4c | "the rating shouldn't render individual buttons" | it shouldn't — five Buttons is wrong on paint, input AND semantics | **new `Facet.newRating`** |
| 5 | Filter field has no background while focused; ✕ overflows its button | the editing yield hid the ART while slot suppression had already hidden the NODE's own fill — nothing painted; and a 28px box minus a 12px-a-side text inset leaves 4px for a glyph | `src/tokens/sheet_model.luau`, `src/client/screen_chrome.luau`, `src/controls/text_input.luau` |
| 6 | Compact: both sides of the rows overflow | same as 4a | see 4a |

**Two lessons were written and they are the durable part:**
`docs/lessons/one-word-two-subsystems.md` (a public word two subsystems read has
ONE meaning, and something must assert that) and
`docs/lessons/a-fixed-box-cannot-hold-a-themes-frame.md` (a literal size in a
reusable control is a size *plus an assumption about the package*).

### What round 3 proved, and how

Everything is headless and reproducible — no capture was needed to find any of
it, once the right question was asked:

- flat geometry is **byte-identical** (`check_flat_baseline` PASS; the rating
  cell's reshape is characterized as a subtree, a new mechanism in that tool);
- themed row insets are asserted against the REAL packages
  (`tests/table.spec.luau`, "table rows sit inside the theme's own selection
  card"): neutral 16, Glossy Touch 26, Pixel Quest 32, Compact 20, header
  tracking cells exactly;
- the theme panel hugs at 1200px, hugs narrower than the phone, and SCROLLS at
  240px (`tests/gallery_theme_picker.spec.luau`);
- `newRating` carries the full four-input conformance row it is now registered
  for (`tests/rating.spec.luau`, `tests/conformance/controls_registry.luau`).

### What round 3 has NOT proved

**Any of it, on a device.** In particular these three deserve eyes first, because
they are the ones a headless test can be right about while the screen is wrong:

1. the **field background while editing** — the fix restores the node's own fill
   under a new sheet rule; it needs a real keyboard-up capture on Glossy Touch
   and Pixel Quest;
2. the **theme panel** in Fantasy Ornate portrait — it should now hug, and scroll
   when it cannot;
3. the **rating strip** on touch — one Grip now owns the whole cell, so a drag
   that used to pan the table may now scrub a rating. Watch for that interaction
   specifically.

---

## 3c. Round 4 (2026-07-27): four reports, two real, two stale

**Two of the four were a stale Studio session** — the fixes had landed the day
before. See §1's "Prove which build you are looking at". Refuted with numbers,
not opinion: the rating's stars are `Text`/`Grip` nodes that `chrome_slots.classify`
returns `nil` for in all three theme states, and no adapter path gives a
non-Button class a surface, a shadow or a gradient; and under Glossy Touch the
row's text sits **18px inside** the card's own painted edge (sampled from the
card PNG's alpha, whose real border is ~2px, not the 18px slice cap).

The other two were real, and both were framework defects:

| # | Reported | Root cause | Fixed in |
|---|---|---|---|
| 1 | Theme card runs past its content AND off the bottom of the phone | in a stack's ARRANGE pass, EVERY child was measured against the stack's full inner extent — right for the dims that ignore the limit, wrong for `hug`, which clamps to it. A `hug` card under a row of chips was handed the whole column as its ceiling, so it never discovered it should be scrolling | `src/layout/solver.luau` (a second measure pass for `hug` children, in document order) |
| 4 | Landscape, Sci-Fi HUD: the bottom of the controls is past where scrolling can reach | a scroll canvas is built from RECTS and stops exactly at the last child's rect (measured to the pixel in seven configurations). A `shadow` recipe paints OUTSIDE that rect — Sci-Fi declares a centred **24px** glow on `panel` — so the last element's bottom was unreachable | `src/themes/snapshot.luau` publishes `chromeBleed`; `src/render/renderer.luau` spends it on the canvas |

Two judgement calls worth keeping:

- **The glow is a canvas allowance, not layout margin.** Reserving it as margin
  would also have fixed it, and would have been wrong: a glow is *meant* to
  overlap its neighbours, and reserving 24px in every direction would space every
  themed screen out. This is the iOS `contentInset` shape — the layout does not
  move, the paint becomes reachable.
- **`hug` resolves before `fill`.** "What I need" is answered first; "whatever is
  over" gets the remainder. That is the order the fill distribution already
  assumed.

Also this round: `clearButtonMode` (UIKit's four modes) on `newTextInput`; the
clear chip capped at the field height (Pixel Quest grew it to 52 inside a 44px
field); the Rating's star moved from `iconSizes.medium` to `small` after
measuring all nine packages (at `medium` the strip was 164–176px inside a 132px
column and ran off the end of its cell); and a latent canvas bug where the
renderer re-derived a scroll's padding from the AUTHORED prop instead of the one
the solver spent.

**Open, chosen but NOT built:** a general "shrink the label when it will not
fit" mechanism for `UI.Button` (director picked "build it generally" on
2026-07-27). The agreed shape is a `compactLabel` — shorter TEXT, not an icon,
because there is no ASCII-safe pencil and a package shipping no icon art would
draw nothing — selected through the existing `ViewThatFits` primitive. Nothing is
clipped today (the Edit toggle now grows 56 → 108 under Glossy Touch), so this is
a capability, not a fix.

## 3d. Round 5 (2026-07-27): three reports, all real

| # | Reported | Root cause | Fixed in |
|---|---|---|---|
| 1 | The Edit button overlaps the table in ALL themes | it was an ANCHOR child of the table root, pinned top-right and consuming NO height. Invisible as an overlay only while it was 24px tall and the header band it covered was 28 — once round 10 let it grow for a theme's own frame it became 34–68px and sat on the header AND the first row | `src/controls/table.luau`: it is a **toolbar row** inside `/Main` now, so the table lays out beneath it |
| 2 | Glossy Touch: star spacing so wide it overflows the row. Pixel Quest: extra space on the right | ONE cause. A fixed box per star makes the strip's width the THEME's arithmetic (`count` icons + gaps) while the cell is the CALLER's fixed number; they agree only by luck. The same 132px column overran by 12px under Glossy Touch and left 28px empty under Pixel Quest | `src/controls/rating.luau`: the glyph is sized (`starSize`), the BOX is a share of whatever the rating is given |
| 3 | The place should set `ScreenOrientation = Sensor` | it set nothing, so the engine default applied | `tools/build_places.sh` + both `.project.json`s now declare `StarterGui.ScreenOrientation = "Sensor"` (enum 4) on every place |

**A trap this round set off:** moving the toggle changed its PATH, and
`table.luau` routes its activation and its focus group by a `$`-anchored path
suffix. Both matchers silently stopped matching — the button rendered, focused,
and did nothing. Nine tests caught it. **If you move a node in a control, grep
that control for its own path patterns before running anything.**

Also: `tests/table.spec.luau`'s harness now passes an `env` by DEFAULT. Without
one a table cannot know the input class, so it shows the touch-only Edit toggle
unconditionally — meaning every hard-coded mouse-drag coordinate in that spec was
exercising a configuration that does not exist on a pointer device.

## 3e. Round 6 (2026-07-27): the Edit/Done toggle wrapped to "Don" / "e"

Fantasy Parchment only, and the cause is the one this repo keeps meeting from a
new angle: **a content-sized button is measured to EXACTLY its label.** Under
fantasy-parchment, fantasy-ornate and glossy-touch the reserved label column and
the drawn text came out equal to the pixel — zero slack for the engine's own
measurement to differ by one. With `TextWrapped` on, a one-pixel shortfall does
not clip a pixel: **it breaks the word.**

The Toggle already had this exact fix (director finding 13) and its own comment
says *"single-line with an end ellipsis is the same floor a Button's label
gets"* — it was not. The Button instance kept the shared `TextWrapped = true`.

**The ruling, and why it is not simply "buttons never wrap":** blanket
single-line broke the theme picker. Its chips carry two-word names and grow to
two lines on a narrow phone ON PURPOSE (round 9's "Classic Desktop" defect), and
single-line would have clipped them to "Classic Deskt…". So the rule is the
distinction the engine does not make:

> A **word** has no legal break point, so breaking it is always damage and an
> ellipsis is the honest degradation. A **phrase** has one, and wrapping it is
> right.

Both seams re-decide from the same string, and the adapter's half rides the
**label write** rather than creation — the label is a reactive binding and the
table's own toggle flips Edit ↔ Done (`renderer.luau` `isSingleWord`,
`screen_target.luau` at the `text`/`label` write site).

---

## 3f. `compactLabel` + the framework's first icon set (2026-07-27)

Not a device round — a capability, built on §3e. A Button may declare what it says
when its full label does not fit, and **if it declares one the framework never
ellipsizes**. Ladder: fits → full label; does not fit → the compact form; none
declared → §3e's word/phrase rule, untouched.

```lua
compactLabel = "Ed" | { text = "Ed" } | { icon = "edit" } | { image = "rbxassetid://…" }
```

Exactly one key from a closed set, validated at construction; `{ glyph = … }` can
join later without a break. **Not reactive** — a reactive value skips
`schema.checkValue` entirely, and a brand-new closed grammar cannot afford an
unvalidated door.

**The mechanism, and why it is not `ViewThatFits`.** The sanctioned primitive was
measured and rejected on two counts. Cost, on 50 buttons: **52 → 152 live nodes
(+192%)** and **0.40 → 1.06 ms per re-solve (2.64×)**. And identity — a wrapper
means two Button nodes with two paths, and `table.luau` matches its own toggle by
`$`-anchored path suffix in *two* places. Instead the **solver** decides, on the
node itself, and the verdict rides out on the same `rects` channel as the rect it
produced (`out[id].compact` → `applyCompactLabel`, a per-solve paint seam shaped
like `applyTextScale`). One node, one instance, no path change, one decision read
by both seams.

Two things that only measurement would have caught, both fixed:
* the fit test first read `innerMaxW` — the **parent's offer**, so a 400px button
  in a 600px screen was told it had 600. It reads the width the node will *occupy*,
  the same rule `contentSize` and `fits` each had to be fixed for;
* "fits" is measured on the **natural one-line width**. A word overflows when it
  does not fit, but a phrase *wraps* — so comparing wrapped widths would have made
  a compact form unreachable for every multi-word label.

**The icon set.** The framework ships art for the first time: `assets/icons/`, 11
names (the 10 it already knew plus **`edit`**, ASCII floor **`/`**), generated by a
committed script — not by a model, which is wrong for a 16–24px glyph — and
uploaded **fully headlessly** through Open Cloud with `assetType = "Image"`. It
resolves **package art → framework art → ASCII glyph**, with
`identity.standardIcons = false` as the per-package opt-out; `pixel_quest`,
`glossy_touch` and `compact_pointer` take it, and `fantasy_ornate` deliberately
does not, so it now shows every rung at once.

One near-white silhouette, not a light/dark pair, and that was **verified rather
than assumed**: `ImageColor3` multiplies, and `tintRole = "content"` contrasts
**3.31:1 – 15.62:1** against the `control` plate across all **11 theme variants**.
A black source could only ever get darker.

**A claim I made and then withdrew:** the fallback paint path looked like it tinted
from the framework's dark default style regardless of package, which would have put
five light variants at ~1.05:1. It does not — `ICON_TINT_COLOR` and the plate fill
are both built from the target's own `style`, so they always agree. The probe that
suggested otherwise compared two palettes that never co-occur. What *is* real, and
is now pinned, is that the two paint paths must answer for the same tint-role
vocabulary: the native one hard-asserts on an unknown role while the fallback one
silently paints white, so a role in one table and not the other is a crash on one
device and an invisible icon on another.

---

## 3g. Round 7 (2026-07-27): three reports off the built showcase

| # | Reported | Root cause | Fixed in |
|---|---|---|---|
| 1 | Pixel Quest: the demo list runs off the screen and will not scroll | the picker's list was a plain `VStack` — no cap, no scroller. Nine demos at a pixel package's row height came to **720px inside the 689px** the overlay gets on a notched phone; landscape was **700px in 235px**. The THEME picker met this in round 10 and got `ScrollView` + `hug`; this was the sibling nobody went back for | `examples/gallery/client/demo_picker.luau`, 3 tests |
| 2 | Compact Pointer: the rating's stars are spread really far apart | round 12 made each star an even SHARE of the cell, which fixed the strip's OUTER width and left its INNER spacing to chance — the box became the caller's arithmetic while the glyph stayed the theme's. Measured in the playlist's 132px column, gap ÷ glyph reached **0.67** under Compact Pointer (a 15px star in a 25px box) against ~0 elsewhere | `src/controls/rating.luau` |
| 3 | Compact Pointer: the name text overflows the row | **NOT REPRODUCED as geometry** — see below | — |

**The rating ruling changed, and it supersedes round 12.** Director, 2026-07-27:
*"let's have stars group, but knowing that, we should be cognizant of how big the
cell is… if we make the cell with the rating control wider, we need to respect
alignment (e.g. center it in the column)."* So the strip now **hugs** its glyphs
and is **centred** by the root ZStack; gap ÷ glyph is −0.17…+0.05 in every
package. Round 12's *"it FILLS that cell"* assertion is gone, replaced by the
invariant that actually matters — the spacing follows the glyph, not the cell.

Two things that cost a cycle each and are worth knowing:

* **`hug` cannot measure `fill` children.** The first attempt put `hug` on the
  strip and left the stars `fill`; a `fill` child reports no content of its own,
  so the strip collapsed to just its gaps (8–24px). The stars had to become
  glyph-sized first.
* **`alignH` is honoured for ZSTACK CHILDREN and grid cells only — an HStack
  ignores it.** Putting it on the star row to move its own children was
  accepted-and-ignored, the family `enum-props-accept-any-string` warns about. It
  works on the strip because the strip is a child of the rating's ZStack root.

**The no-overrun guarantee narrowed, deliberately.** An even share could never
exceed its cell whatever the glyph was; grouping gives that up, so `medium` /
`large` glyphs in a 132px column now genuinely do not fit. That is the director's
own point about sizing the cell for the control, and the default rung (`small`,
which is what a table row uses) is pinned across all nine packages.

**A follow-up this opened, reported not fixed.** Now that a rating hugs, a fixed
132px column strands **64px under Compact Pointer**, 36 under Pixel Quest and 20
under Glossy Touch — space the `fill` name column could have. `width = { type =
"hug" }` on the column was tried and is **wrong**: a table resolves column widths
per SECTION, so the header hugged the word "Rating" while the body hugged the star
run and the two disagreed by 21px, putting the name column out of line with its
own heading. A content-sized table column has to be measured across header AND
body together, which the control cannot do today.

**On report 3, honestly: I could not reproduce it.** The name text is contained
horizontally (255px of text in a 658px cell at 900px; 176 in 188 at 430px) and
vertically (33px in a 48px row) in all eight packages at every width tried, and
the solver reports no overflow diagnostic on any cell. What IS true and may be
what the capture shows: a plain `UI.Text` gets `TextWrapped = true` at creation
and **no `TextTruncate` at all** — both the word/phrase rule and the end-ellipsis
floor are gated on `handle.class == "Button"` (`screen_target.luau`). So when a
Text's box is too small the framework has no opinion about how it degrades, and
the engine is free to break a word or clip mid-character with no ellipsis. That
is the round-6 gap, un-generalised.

---

## 3h. Round 8 (2026-07-27): the Studio round, and the defect only Studio could show

Rounds 3f/3g were proven headlessly and **not** in an engine. The director's note —
*"you don't seem to be testing this in studio"* — was correct, and driving the real
place found a blocker no headless probe could have.

**FRAMEWORK ICON ART PAINTED PURE WHITE IN NATIVE MODE.** `sheet_model.buildPackage`
emitted one `Icon — <name>` rule per **declared** icon, iterating `package.icons`.
That was right while a package's own map was the only source of art; the
compact-label stage added a rung below it, so a package declaring nothing now
draws pictures — and `ImageColor3` is `NATIVE_SHEET_OWNED`, so the adapter may not
write it. Measured in the running showcase:

```
studio-neutral   sheet rules = 70   ICON rules = 0
resolveIcon(neutral, "edit") -> source=asset  tintRole=content
```

Art resolved, drew, and had **no rule to tint it**. On the five light theme
variants that is a white mark on a near-white plate. Fixed by making the emitter
ask `resolveIcon` — the one resolution ruling every other consumer asks — over the
union of the package's names and the framework's vocabulary, instead of reading
the authored map. Verified in-engine after the fix, with fantasy-ornate as the
known-good control:

| package | icon rules | tinted |
|---|---|---|
| studio-neutral | 0 → **11** | 11 |
| fantasy-ornate (declares 7; KNOWN-GOOD) | 7 → **12** | 12 |
| glossy-mobile (LIGHT) | 0 → **11** | 11 |
| compact-pointer, glossy-touch (opted out) | **0** | 0 |
| pixel-quest (opted out, declares 6) | **6** | 2 |

glossy-mobile's `content` is `0.09,0.11,0.16` against a `0.89,0.93,0.98` plate — a
dark mark on a light plate, which is the whole point of the tint role.

**Cost:** a flat package is no longer free. Six specs asserted "zero chrome rules /
zero image rules" for a flat package; that invariant genuinely changed the day the
framework started shipping art, and they now assert the icon floor instead
(`tests/lib/framework_icons.luau` derives the count so it cannot rot).

### Two instrument traps this round, one of which I fell into

* **`GetStyled("ImageColor3")` is NOT proof a rule exists.** After the fix it
  returned the content colour on every icon and I nearly wrote that down as the
  verification — but enumerating the live sheet showed **0 rules setting
  `ImageColor3`** at all. The live PlayerGui sheet is the built-in
  `sheet_model.build` model (studio-neutral is not an installed *package*), so
  `buildPackage` never ran for it. The real evidence is the emitter's own output,
  taken in-engine, against a package whose rules are known to paint.
* **The session was STALE**, exactly as §1 warns. The library tree was current
  while `StarterPlayerScripts.Gallery.demo_picker` still held the pre-fix plain
  `VStack`. Every finding below the push is worthless without the marker check
  first; the push loop in §2 is what fixed it (14 modules).

### Found, NOT fixed

* **`workspace.FacetShowcaseAPI.pickTheme` is dead.** It calls
  `showcasePicker.dispatch(...)`, and the theme picker stopped exposing `dispatch`
  when behaviour moved onto the nodes (§4.1). It errors with *"attempt to call a
  nil value"* at `Gallery:526`. §2 already warns that driving it does not prove a
  tap works — it now does not prove anything, and switching theme from an agent
  has no working route.

---

## 3i. The glow gutter, and the metric-arithmetic gap it forced open

**Reported 2026-07-27** (Glossy Mobile, phone): *"the way these controls are
cutoff horizontally looks wrong given there's no horizontal scrolling. the view
should narrow to accommodate them (and the glow underneath)."* **Fixed.**

`chromeBleed` is how far a package's shadow paints outside the box it belongs to.
It was spent in exactly one place — an allowance added to a ScrollView's CANVAS —
so a glow past the last row becomes reachable by scrolling to it. That holds on
the scroll axis and **collapses on the other one**: a y-axis scroller cannot be
scrolled sideways, so canvas width buys nothing and the glow is cut by
`ClipsDescendants`. Measured on a 390px phone, every reference package's widest
child sat FLUSH with the scroller's right edge and lost its entire glow — 17px
under Glossy Mobile, Glossy Touch and Fantasy Ornate, 24px under Sci-Fi HUD. The
solver reported nothing, correctly: **the bleed is paint, not layout**, which is
why only a device showed it.

**The fix.** The outermost clipping ScrollView reserves the bleed on its CROSS
axis, as `math.max(padding, bleed)` — the gutter must be at LEAST the glow's
reach, so a container already insetting by 16 owes only the missing 8 under
Sci-Fi HUD and nothing under Glossy Mobile. Adding would have charged twice.

**Nesting does not accumulate** (director's question). A glowing view inside a
glowing view inside a scroller, all flush, overshoots by `bleed` and **not twice
it** — measured 24px, not 72, under Sci-Fi HUD. Reach is measured from each
node's OWN box and an inner box can never lie outside its parent's, so the
deepest flush descendant has the same reach as the outermost; `chromeBleed` is
the package-wide MAXIMUM, so one reservation covers every slot at every depth.
Ordinary containers do not clip in Roblox, so they never entered the question.
Nested CLIPPERS each reserve once (390 -> 342 -> 294 under Sci-Fi HUD), which the
`max` semantics makes near-free wherever the container already has padding.

### What it forced: a side may name SEVERAL metrics, and they ADD

Reserving on the clipper desynchronised a Table from its own header — the rows
live in the scroller and the header does not, so the columns came apart by
exactly the bleed. The header has to inset by *the viewport's glow gutter plus
the row card's carved border*: two gutters at two nesting levels. That is
`chromeBleed + chromeInsets.selection.left`, which no single metric name could
express and which a control cannot pre-compute, because metrics resolve per solve
and a control builds its blueprint once. It is the same wall `table.luau`'s own
edit-mode comment names — *"a metric name and a number cannot be added here"* —
and it had blocked three separate things.

So `sides` now accepts a LIST per side, resolved to the SUM on every solve:

```lua
padding = { left = { "chromeInsets.selection.left", "chromeBleed" } }
```

Every entry is still a number or a real metric name, so a typo inside a list is
rejected at construction exactly as it is outside one. `isMetricPath` also learned
that a TOP-LEVEL numeric snapshot fact is a metric — the dot was a proxy for
"names a section entry", and whole-package scalars like `chromeBleed` are exactly
what a layout needs to name here. Still closed: a name passes only if it resolves
on the neutral snapshot AND resolves to a number.

**Two invariants moved, both honestly.** A skinned table's cells are now inset by
the card's reserve PLUS the glow gutter (a package with no shadow has bleed 0, so
the old assertion is the same assertion). Pinned by three new tests in
`theme_layers.spec` — including the nesting claim — and the flat baseline does not
move, because `chromeBleed` is 0 for every package that declares no shadow.

**Residual, unfixed and deliberate:** an INNER viewport still clips its own
content's glow (a Table's rows against the table's own edge). Only the outermost
clipper reserves, because that is the edge a control can actually sit flush
against, and reserving at every level is what broke the header. If a device ever
shows a row's glow cut at a table's edge, the fix is to give that control the same
multi-metric gutter its header now uses.

---

## 3j. The row text "overflowing" — it was the PLATE that was wrong

**Reported three times** (Compact Pointer, playlist table) and twice I could not
reproduce it: the framework's own geometry said the text was comfortably inside
its cell, horizontally and vertically, in all eight packages at every width. It
was — the text was never the problem. **Driving the real place found it in
minutes.**

A decoration is created at `Size = fromScale(1, 1)` under the comment *"full
bleed: the skin IS the node"*. A scale size resolves against the parent's
**content** box, and a `UIPadding` shrinks that. So every skinned host carrying
one drew its plate INSIDE the padding, while the solver laid the node's content
out against the node's own rect. Measured live on a playlist row:

```
host  x=16  w=357   (UIPadding 12 a side)
PLATE x=28  w=333   <- inset by the padding
TEXT  x=26          <- 2px OUTSIDE its own plate
```

That is the whole defect, and it is invisible to every headless probe because the
displacement is applied by an engine object the solver cannot see. After the fix
the plate is `x=16 w=357` and the text sits 10px inside it.

`chrome_slots.fullBleedBox(l, r, t, b)` is the compensation — pure, in the tokens
layer, so it has a spec with real numbers; `screen_chrome` calls it on EVERY sync
because `applyPadding` re-derives a host's inset from the live theme, so a swap
changes the number being compensated for. Identity when there is no padding, so
nothing unpadded moves.

### Getting there: three broken instruments in a row

Worth writing down, because each one nearly produced a false finding.

1. **Writing `BackgroundColor3` to mark a node does nothing** — it is
   `NATIVE_SHEET_OWNED`, so the sheet defeats it silently. Marker instances have
   to be NEW, untagged objects the cascade cannot reach.
2. **A 2px marker is invisible in a `screen_capture`.** The first markers were
   drawn, present and correct, and simply could not be seen — which read exactly
   like "the capture is stale". Proving the capture was live took a
   quarter-screen red banner; after that, 4px markers were legible.
3. **Pixel-measuring a capture is not measurement.** The capture is not a 1:1
   scale of the viewport and eyeballing it produced two contradictory conclusions
   about where the plate started. What settled it was asking the ENGINE for
   `AbsolutePosition` of the host, the decoration and the text — three numbers,
   no interpretation.

**Also fixed on the way:** `FacetShowcaseAPI.pickTheme` had been dead. The
composed theme picker returned `dispatch = dispatch`, and `dispatch` had not
existed since behaviour moved onto the nodes — a deleted local whose reference
survived, which Luau reads as a nil GLOBAL rather than failing. So the composed
picker shipped `dispatch = nil` and every caller got "attempt to call a nil
value": there was no working route to switch theme from a script at all. It now
exposes `pickPackage`, which routes through the same `apply` the chips'
`onActivate` calls.

---

## 3k. The star run is spaced for the INPUT PARADIGM

**Director, 2026-07-27:** *"it's a little too tight on compact pointer… if we're
on a touch input, part of the paradigm should be slightly wider spacing for touch
targets vs. what we can do with a pointer."*

**Why a space step was the wrong lever.** The run had `gap = "xs"`, and the
packages' spacing ladders disagree wildly with their icon ladders:

| package | `xs` | star | gap as % of glyph |
|---|---|---|---|
| compact-pointer | **2** | 12 | **17%** |
| classic-desktop | 2 | 16 | 13% |
| glossy-mobile | 6 | 16 | 37% |
| glossy-touch | 6 | 20 | 30% |

A run of glyphs is spaced against the GLYPH, not against the page's rhythm, so no
single step is right for both — which is exactly what "too tight on compact
pointer" was.

**The fix.** `snapshot.iconRunGap` is DERIVED from each package's own `iconSizes`,
per rung and per paradigm — 30% of the glyph for a pointer, 45% for touch. Derived,
not authored, for the same reason `chromeBleed` is: a new `metrics.*` section
would move every derived package's content stamp and invalidate stored capture
evidence, which is why `rating.luau` declined to add `controls.rating.*` in the
first place. A package that resizes its icon ladder moves its icon gaps with it
and authors nothing.

Touch buys the wider gap because **the run is one drag target** — the gap is what
makes an individual star reachable with a fingertip, while a cursor lands where it
is aimed and can afford the tighter, better-looking run. It is a metric NAME and
`gap` is reactive, so switching input class is a **re-solve, never a rebuild**: the
strip re-spaces under a live hot-switch with the value and any scrub intact. A
Rating built without an `env` takes the pointer spacing, which is the tighter of
the two and therefore the one that cannot overrun a cell sized for the other.

Measured live under Compact Pointer: the gap went **2px → 5px** and the pitch
**11 → 14** on a 9px drawn glyph. Widest touch run across all packages is 136px
(Glossy Touch and Fantasy Ornate, 20px glyphs), so the playlist's rating column
moved 132 → **144** to clear every package with slack rather than by luck — a
characterized rect drift, since the `fill` Name column absorbs the 12px and every
column right of it shifts by exactly that.

---

## 3l. The PAGE scrolls, not just the rows — `Table.scrolls`

**Director, 2026-07-27, the playlist example in landscape:** *"just the table
scrolls. really the whole view should scroll, as it's unusable having just the
table scroll."*

A Table's body has always been an unconditional `ScrollView` at `height = fill`,
so the table owns a viewport and the page around it cannot move. That is right
when the table IS the screen and wrong when it is one block on a page. Measured
on this example:

| viewport | row window | share of screen |
|---|---|---|
| 390x844 portrait | 651px | 77% |
| 844x390 landscape | 214px | **55%** |
| 660x320 landscape | 144px | **45%** |

The title, filter and hint are a fixed block above the table, so on a short
viewport they took nearly half the screen and the ONLY thing that could move was
the rows inside what was left.

**`Table.scrolls`** (default `true`, so nothing existing moves) makes this a
choice rather than an inference, because both are legitimate — a mail app's list
owns its viewport, a settings page's small table does not. With `scrolls = false`
the body is a plain stack: no `ScrollingFrame`, no clip, `height = content`, and
the root defaults to content too, so every row lays out and whatever the host
scrolls carries them. The example wraps its content in a page `ScrollView` and
takes that mode.

**It also avoids nesting scrollers**, which is the real trap: a vertical drag over
the rows inside a scrolling page is ambiguous and the inner one always wins.
Verified live in a 749x368 landscape session — **one** `ScrollingFrame` in the
whole screen, box 216 with a 479 canvas, so 263px of the page (header included) is
reachable by scrolling. Before, the page had none and the table had one.

**The cost, and it is the trap this repo keeps meeting:** the page wrapper adds one
`/Page` path segment, and 15 example tests hard-coded the old paths. They are
updated, and the flat render carries a characterized reshaped-subtree entry. The
table's own `$`-anchored matchers are unaffected because they anchor on the table
id, not on the screen root — which is exactly why they anchor that way.

---

## 3m. Round 9 (2026-07-27): two overflows with one cause — a pixel count nobody could re-measure

Two reports off a real iPhone, plus one standing ask, and all three are the same
mistake in three places: **a height fixed once, in pixels, against content that
is not fixed.**

| # | Report | Root cause |
|---|---|---|
| 1 | Glossy Touch, playlist: "Drift City Nights" overflows the cell vertically | `rowHeight = 48` with an **uncapped** `UI.Text` cell |
| 2 | Pixel Quest: same, plus the demo chip overlapping the "Playlist" heading | as above, and `BAR_HEIGHT = 62` reserved less than the chip it holds |
| 3 | *"we likely want taller table cells on mobile for touch targeting — that seems like the paradigm adaptation facet should handle"* | `rowHeight` was the consumer's number to guess at all |

**Why the emulator was clean and the device was not.** It takes only a few
pixels of extra text width to turn a two-line wrap into a three-line one. A fixed
row with no line cap has *zero* slack, so any difference at all between emulator
and device — a raised `PreferredTextSize`, a slightly narrower viewport — is
visible damage rather than a rounding difference. The device was not showing a
different bug; it was showing that there was no margin for one.

**The row fix (framework).** A row's height is now a **description**, not a
number. `themes/snapshot` derives `controls.table.rowLines` / `.rowHeight` /
`.rowPadding` per input paradigm — derived, not authored, for `iconRunGap`'s
reasons — and `Table` turns that into pixels using the live typography scale and
accessibility text offset, which the snapshot cannot see. Pointer gets the dense
one-line row every desktop table has; touch gets two lines clearing the 44px
floor; raising the text preference makes rows **taller** instead of making their
contents spill. `Spec.rowHeight` is now optional and `02_playlist_table` no
longer sets it.

**And cells can no longer outgrow their row, at all.** New public prop
`Text.lineLimit` (SwiftUI's name) caps the *reserved* box at N lines — which is
what finally gives the adapter's long-standing `TextTruncate.AtEnd` something to
truncate against. `Table` derives the cap from whichever height won, so a pinned
`rowHeight` is capped to *its* row too. One honest limit: a pin below one line of
its own cell text is raised to it, because a row cannot be shorter than the
single line it must draw.

**The strip fix (showcase).** `BAR_HEIGHT = 62` was "the taller chip's measured
46px plus padding" — measured once, under Studio Neutral. Measured headlessly at
`coreTop = 58`, the chip row actually ends at **131 (Glossy Touch)**, **142
(Pixel Quest)** and **129 (Fantasy Parchment)** against the 120 that literal
reserved; Studio Neutral ends at 112 and fits, which is precisely why nobody
caught it. The strip measures now — `demo_picker.barReservation`, fed by the
chrome surface's `onGeometry` — and the literal survives only as a floor. It
cannot chase its own tail: the chip row is placed at the live topbar inset, not
at the reservation.

**A footgun removed on the way.** `opts.onGeometry` used to WIN OUTRIGHT and skip
every contribution's `syncGeometry` — so asking where your own node landed
silently disabled a composed Table's scroll-into-view and any TextInput's
keep-visible. The parity reference had it written down as exactly that. Geometry
is a notification, not a routing decision (unlike `onActivate`, §4.1); both are
fed now, and every `syncGeometry` in the framework is idempotent.

**Verified.** Suite 2058 → 2073. Live in the built showcase at a 389×762
viewport, four packages, zero row overflow and the chips clearing the page title
in all four — and the derived row is visibly per-theme (Studio Neutral 44,
Pixel Quest 48, Fantasy Parchment 50, Glossy Touch 52, against the one hardcoded
48 before):

| package | row h | tallest cell text | overflow | chips end | title top |
|---|---|---|---|---|---|
| studio-neutral | 44 | 18 | none (−26) | 54 | 78 |
| glossy-touch | 52 | 39 | none (−13) | 73 | 99 |
| pixel-quest | 48 | 40 | none (−8) | 84 | 108 |
| fantasy-parchment | 50 | 21 | none (−29) | 71 | 95 |

**NOT verified:** the accessibility path on hardware. `GuiService.PreferredTextSize`
is **read-only to scripts**, so Studio cannot be driven to Large/Larger/Largest —
that path is proved headlessly only (offsets 0/6/10/14, both paradigms,
`tests/paradigm_table.spec.luau`). Since a raised text preference is the most
likely reason the device diverged from the emulator in the first place, **this is
the row the next device pass should drive**: set the phone's Roblox text size to
Largest and re-open the playlist.

---

## 4. Root causes worth carrying forward

### 4.1 A surface-level `onActivate` OVERRIDES every node on that surface

`src/present/presenter.luau:489` — *"when opts.onActivate IS present it wins
outright (override)"*. It runs and **returns**; no node reaches its own
`props.onActivate`.

The theme picker used to route its rows by matching `P_`/`T_` out of the path in
a surface handler. That is fine while it owns the surface. Composed into a shared
chrome surface, the router answered for its neighbours too — by doing nothing —
and **both chips went dead**. Earlier, a `raise()` that DROPPED the override had
the mirror-image effect: chips alive, rows dead. **One cause, two bugs, and they
trade places.**

Fix: behaviour lives on the NODES. No surface-level `onActivate` anywhere in the
showcase. Pinned by three tests in `tests/gallery_theme_picker.spec.luau`
("composed pieces carry their own handlers").

**Carry this forward:** prefer node handlers. Reach for a surface handler only
when you own the whole surface, and never after composing.

### 4.2 A policy string nothing reads is indistinguishable from one that works

`rootPolicy = "edgeToEdge"` had been passed by **every modal scrim since scrims
existed**, with a comment saying it covers the whole viewport. No branch in the
renderer matched it. Every scrim was silently inset for months.

Now: `edgeToEdge` is implemented, and an **unknown `rootPolicy` errors** instead
of falling through. `docs/lessons/decoration-paints-to-the-edges.md`.

### 4.3 A scroll container clips to ITSELF

Three shapes were tried; only the third is right, and the framework's schema had
it all along — `ScrollView` takes `surface`/`padding` like any container, so one
node is both card and scroller. `docs/lessons/a-scroll-container-clips-to-itself.md`.

### 4.4 Two surfaces cannot measure each other

The chips were held apart by a hard-coded `offsetX`. Real iPhone text is wider
than the guess. **An offset between two things that cannot see each other is a
guess about every font on every device.** Compose them into one solver instead.

---

## 5. Architecture of the showcase (what to read)

- `examples/gallery/client/init.client.luau`, branch
  `if workspace:GetAttribute("Facet_Showcase")` — the host. Owns: the backdrop,
  the reserved strip (`reserveBar`), the ONE chrome surface, per-demo scopes,
  the loopback-server flush, and `FacetShowcaseAPI`.
- `examples/gallery/client/demo_picker.luau` / `theme_picker.luau` — each has a
  pure MODEL half (tested) and a `mount()`. Pass `composed = true` to get
  `{ chip, panel/list, open, ... }` back instead of a presented overlay.
- `tools/build_places.sh` — the `Facet-Showcase` target.
- `examples/showcase.project.json` — extracted for `rojo serve` if you want live
  sync instead of the HTTP push.

**Per-demo scopes:** the host hands each demo a proxy `core` whose
`signal/memo/observe/effect/scope` own into a per-demo scope, disposed on swap.
Ownership in this core is explicit, and the tutorial examples allocate straight
on the core they are given and return no `dispose` — without the proxy, eight
swaps leaked eight demos' worth of signals. Do not "simplify" this away.

---

## 6. Open riders

- **XP-P1..P4** (`artifacts/cross-platform-proof/review-packet.md`) — the
  physical/human rows. Publishing this place is how they close. The packet has
  the exact procedure and the five refusals a fabricated capture has to get past.
- **XP-B3** — `VirtualInput` calls succeed but deliver no events. Instance
  caching was tested and eliminated; the cause is not established.
- **XP-S4** — the four-edge `coreSafeInsets` fix is a code-shape claim, not a
  pixel claim. Re-drive a landscape/notched row against it.
- Round-7 verifier INFO items (non-blocking) in
  `artifacts/cross-platform-proof/verifier-phase-gate.json`: two perf-output
  presentation nits, `xp-s-showcase.json` still labelled `XP-S1..XP-S6` against a
  section that runs to S7, and — out of this stage's scope — the
  `theme-packages-and-skinning` and `rich-skinning-v2` gates still grep their
  verifier files for an accept token instead of reading the `verdict` field. The
  agreed disposition was a rider in
  `docs/plans/agent-execution-contract.md`, **not** editing closed evidence.

---

## 7. Things that will bite you

- **`tools/test.sh <floor>`** is pinned in `tools/lune/gate_manifest.luau` and
  echoed in the ledger and review packet. Change the suite size → update all
  three or the gate fails.
- **`lune run tools/lune/check_flat_baseline`** pins the unthemed render.
  Deliberate geometry changes need an entry in `ALLOWED_RECT_DRIFT` with a
  reason; anything else is a regression. Regenerate the *current* dump with
  `lune run tools/lune/_theme_baseline -- artifacts/rich-skinning-v2/rows/neutral-render-dump.json`.
  *(Updated 2026-07-28, Step 5.5: the generator no longer defaults its target, so
  running it bare can no longer clobber a stored comparison input — it exits 2 and
  says so. `artifacts/theme-packages-and-skinning/baseline-neutral-dump.json` is no
  longer read by any check; the Step 3.5 gate now runs `check_flat_baseline`, which
  regenerates from live source instead of comparing two stored files.)*
- **`later locals are not upvalues`** — this repo's own lesson, and it caught a
  test in this session. A `local function` declared after a closure that calls it
  is a nil global read.
- Studio's render surface can collapse to a **1×1 viewport** after a
  `screen_capture` crash. Every solve then produces 1px-wide roots. It looks like
  a layout bug and is not; restart Studio.
