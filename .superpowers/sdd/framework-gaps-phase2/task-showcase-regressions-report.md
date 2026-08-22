# Task FIX-SHOW report — three showcase regressions (2026-08-22)

**Status: BUG A + BUG B — one shared root cause, FOUND and PROVEN, fix BLOCKED
(`src/client/screen_target.luau`, an owed extraction the brief forbids me to
precede). BUG C — root cause found, the table's own half FIXED and shipped
(`5b88eb2`); the row-actions half BLOCKED on another lane's file.**

Baseline: place as built at HEAD `a39146b` (the director's own build), Studio
`Facet-Showcase.rbxl`, native StyleSheet paint path (`Facet_NativeStyle`), theme
`studio-neutral`, emulated Samsung Galaxy S22 Ultra, viewport 677x338.

---

## BUG A and BUG B ARE ONE DEFECT

### Root cause

`src/client/screen_target.luau:566`

```lua
if string.sub(tag, 1, 5) == "facet-" and desired[tag] ~= true then
    CollectionService:RemoveTag(instance, tag)
end
```

`string.sub(tag, 1, 5)` is `"facet"` — five characters. `"facet-"` is six. **The
comparison can never be true, so the tag-REMOVAL half of `syncTags` is dead
code.** `syncTags` — the one function that owns every `facet-*` classification
tag on an instance — became purely ADDITIVE: every tag ever applied to a node
stays on it for the node's whole life.

**The commit that introduced it**: `36d1883` (2026-08-18, *"the tags were the
largest surviving old name, and the guard could not see them"*, ADR-0038, the
`luau-*` → `facet-*` tag rename), inside the release-candidate-review window
exactly as the brief predicted. Its diff at this line:

```
-  if string.sub(tag, 1, 5) == "luau-" and desired[tag] ~= true then
+  if string.sub(tag, 1, 5) == "facet-" and desired[tag] ~= true then
```

`"luau-"` is five characters, so the `sub` length was correct before the rename
and wrong after it. The 395-occurrence sweep rewrote the literal and not the
length. `git log -S 'string.sub(tag, 1, 5)'` returns only the initial commit —
the length has never been touched.

### How that produces the two screenshots

In native mode a `Button` takes a class default at CREATE
(`screen_target.luau:1449-1465`): `handle.nativeSurface = "control"`,
`nativeInteractive = true`, `syncTags`. `picker.luau:552` then declares every
segment `surface = "plain"` whenever an indicator slides, *"so nothing paints
over the chip behind them"*, and `screen_paint.applySurfaceNative` correctly sets
`handle.nativeSurface = nil` / `nativeInteractive = false`. The handle is right;
the INSTANCE keeps the stale tags, and the sheet's `.facet-surface-control` rule
paints an opaque `$Control` fill over the indicator that
`selection_indicator.luau` deliberately declares BEHIND the strip.

* **Bug A (underline skin, app bar)** — the 4px accent bar is fully covered
  except where the plate's `::UICorner` rounds away, which paints exactly *"two
  tiny blue triangular slivers at its bottom-left and bottom-right corners"*.
* **Bug B (pill skin, page bar)** — the inset pill is entirely under the opaque
  plate at rest, and crosses the GAPS between plates mid-flight: *"it flashes
  during the move, and at rest there is no indicator at all"*.

### RED evidence

**1. Clean-room adapter probe** (live Client VM, no source edits, the shipped
adapter driving itself):

```lua
local adapter = screen_target.new({})
local h = adapter.create(adapter.createRoot("ProbePlainSurface"), "/Probe/Btn", "Button")
adapter.setProp(h, "surface", "plain", "style")
```
```
class=TextButton
nativeSurface=nil            <- correct
declaredSurface=plain        <- correct
nativeInteractive=false      <- correct
tags=[facet-interactive,facet-surface-control]   <- WRONG: never removed
styledBT=0                   <- GetStyled: the sheet paints an OPAQUE fill
```

**2. Blast radius** (same probe, one Button, `GetStyled`/tags after each write):

```
create:            [facet-interactive,facet-surface-control]
selected=true:     [... ,facet-selected, ...]
selected=false:    [... ,facet-selected, ...]                       <- never removed
surface=plain:     [... ,facet-selected,facet-surface-control]      <- never removed
surface=accent:    [... ,facet-surface-accent,facet-surface-control] <- TWO surface tags
role=destructive:  [... ,facet-role-destructive, ...]
role=default:      [... ,facet-role-destructive, ...]               <- never removed
```

This is framework-wide, not tab-specific: selection, hover-eligibility, button
role, toggle value, error state, shape, typography role and skinned-slot tags are
all sticky today. Two surface tags coexisting means the sheet cascade decides the
fill by rule ORDER rather than by what the node declared.

**3. Causal proof on the director's own screen.** Captures:
`artifacts/framework-gaps-phase2/bugAB-red-tabview.png` (as built, `a39146b`) and
`bugAB-green-tags-removed.png`. Between them the ONLY change was, in the live
Client VM:

```lua
CollectionService:RemoveTag(<each of the 12 strip TextButtons>, "facet-surface-control")
CollectionService:RemoveTag(<each of the 12 strip TextButtons>, "facet-interactive")
```

RED: four dark opaque tab plates; the active tab shows two tiny blue triangular
slivers at its bottom corners; the top page bar shows no resting indicator.
GREEN: the plates are gone, the app bar shows its full blue underline under
"Pages", and the page bar shows its blue pill under "Avatars". Full transcript:
`artifacts/framework-gaps-phase2/bugAB-tag-stickiness-probe.txt`.

### The fix, and why it did not land

**The fix is one character**: `string.sub(tag, 1, 5)` → `string.sub(tag, 1, 6)`
in `src/client/screen_target.luau:566`. It is SIZE-NEUTRAL (one digit for one
digit), so it neither grows the file nor moves its ledger row.

`src/client/screen_target.luau` is one of the four files the brief names:
*"carry owed extractions that must PRECEDE any edit — if your fix lands there,
report BLOCKED with the root cause written up; do not start the extraction
yourself this round."* The ledger row (193,795, 205 from its 194,000 trigger)
says the `screen_vocabulary.luau` extraction is OWED and *"the next change of any
size to this file must be PRECEDED by it rather than accompany it."* **BLOCKED,
as instructed.**

**Recommendation to the controller.** The owed extraction and this fix want the
same seam. `screen_vocabulary.luau` is specified as the module-level vocabulary
tables (`CLASS_TO_INSTANCE`, `TEXT_ALIGN_MAP`, `SCALE_MODE_ENGINE`,
`TINT_REPAINTING_PROPS`, `toColor3`, `fontFaceFor`) — the tag-ownership predicate
belongs in it, as a named fact rather than a magic number at a call site:

```lua
-- screen_vocabulary.luau
local TAG_PREFIX = "facet-"
function screen_vocabulary.ownsTag(tag: string): boolean
    return string.sub(tag, 1, #TAG_PREFIX) == TAG_PREFIX
end
```

with `syncTags`' loop calling it. That makes the defect unrepeatable (the length
can no longer disagree with the literal) and pays down the extraction the row
demands, in one round. **A one-character `5` → `6` is the minimum viable fix if
the extraction cannot be scheduled** — this regression is on the framework's own
demo place today.

**A red-first mechanized repro is possible without touching the file** and should
land with the fix: `tests/lib/adapter_source.luau` already exposes the adapter
sources to source-scanning specs, so a case asserting *"every `facet-` prefix
test in the adapter compares as many characters as the literal has"* is red today
and green after. I did not add it, because a red spec in the suite would block
every other lane's gate this round.

### Owed to the director

A live re-test of the `tab-view` demo (app bar underline + page bar pill, at
rest and mid-flight) once the fix lands. My proof removed the tags by hand; it
did not exercise the fixed code path.

---

## BUG C — the heading band could not see edit mode

### Root cause

Two derivations of one number.

* `src/controls/table.luau:1096` `cellsEditPadding` — the ROW's cells — adds
  `HANDLE_GUTTER` (32px, the ≡ reorder handle / ◉ selection mark) to
  `ROW_ART.left` whenever `editingSignal` is true and `canEditMode`.
* `src/controls/table.luau:1815` `bandPadding` — the HEADING band and the
  toolbar — is `{ left = { ROW_ART.left, glow }, right = ..., bottom = ... }`
  and has **no edit-mode term at all.**
* On a row that carries a destructive `rowActions` entry there is a SECOND
  leading gutter: `row_actions.build` wraps the row and `row_actions_root`
  spends `editGutterPx` (28 + 8 = 36px) as the LEFT PADDING of the content it
  was handed. The heading pays that one either.

**This is NOT a release-candidate regression.** `git show 6a4b59c:src/controls/table.luau`
(initial commit) and `7f9dc59` both show the header padding as
`{ left = { ROW_ART.left, "chromeBleed" }, ... }` — it has never carried
`HANDLE_GUTTER`. What the RC-era work changed is the SIZE of the gap: the
row-actions ⊖ (stage 1, 2026-08-15) took it from 32px to 68px, which is when it
became the thing a director notices.

### RED evidence

`tests/table.spec.luau`, `Table: layout`, three arms driven through
`tbl.api.editing:set(true)` at 800px with two columns:

```
plain / not editing                header.x=0 header.w=736   cell.x=0  cell.w=736   dx=0
plain / EDITING                    header.x=0 header.w=736   cell.x=32 cell.w=704   dx=32
reorderable / EDITING              header.x=0 header.w=736   cell.x=32 cell.w=704   dx=32
reorderable+rowActions / EDITING   header.x=0 header.w=736   cell.x=68 cell.w=668   dx=68
```

Committed-spec form, run BEFORE the fix:

```
$ lune run tests/<table-only runner>
  ✗ columns stay aligned in edit mode: the ≡ gutter
      tests/table.spec:177: expected 32 to be 0
  ✗ columns stay aligned in edit mode: the ≡ gutter AND the row-actions ⊖
      tests/table.spec:177: expected 68 to be 0
```

### The fix (`5b88eb2`)

Both terms now come from the side that SPENDS them, so they cannot be derived
twice:

* `src/controls/table_header.luau` — `headerPadding` is a memo over
  `bandPadding` that appends `(canEditMode and HANDLE_GUTTER or 0) + rowEditGutter`
  while the mode is open, under exactly the condition `cellsEditPadding` uses.
  Closed, it returns `bandPadding`'s own table unchanged, so nothing outside edit
  mode moves and the toolbar (which shares `bandPadding` and is not a row) keeps
  its edge in both states.
* `src/controls/table_rows.luau` — `noteEditGutter` binds a single, re-pointed
  observation to the wrapped row's own `api.editGutterPx`, so the band spends the
  composite's OWN published reading rather than re-summing
  `editAffordance + rowGutter` from theme metrics.
* `src/controls/table.luau` — one owned signal (`rowEditGutter`) and five
  dependency lines. +369 characters, recorded in the ledger row; 434 below the
  190,000 warning line, so the file did not enter the band.

### GREEN evidence

```
  ✓ columns stay aligned in edit mode: the ≡ gutter
  ✓ columns stay aligned in edit mode: the selection gutter
```

Mutation proof (`lead` forced to 0): **both** arms go red, then green again on
restore. The second arm enters edit mode by the OTHER route (an owner-held
`editing` signal, which is what makes `canEditMode` true) precisely so it is not
a case that cannot fail.

**Live**, Studio, native sheet path, source stamp `efc1794e-7090005`, a Table
with a destructive `rowActions` and `reorderable`:

```
editing = false   HEADER Name title x = 32   row cell x = 32     aligned
editing = true    HEADER Name title x = 64   row cell x = 100    32 of 68 closed
```

Captures: `artifacts/framework-gaps-phase2/bugC-live-closed.png`,
`bugC-live-editing.png`.

### The wrapped-row half — BLOCKED

`headerPadding` is already written to spend the ⊖ gutter; the composite does not
publish it in the mode Table uses:

```
src/controls/row_actions.luau:3499   if isHosted then
src/controls/row_actions.luau:3550       api.editGutterPx = editGutterPx
src/controls/row_actions.luau:3569   end
```

There is no other route: `ROW_GUTTER` (`"controls.rowActions.rowGutter"`) is not
exported from `row_actions_metrics.luau`, and re-deriving the sum in the table
would be a second implementation of a number the composite owns.
`src/controls/row_actions.luau` belongs to lane R1b this round. **The one-line
additive change, the reason, the size arithmetic and the ready-to-land spec case
(with its red output) are in
`artifacts/framework-gaps-phase2/bugC-wrapped-row-blocked.txt`**, and the spec
file carries a comment block at the exact spot that points at it. Residue
measured live: 36px.

### Owed to the director

A live re-test of the playlist demo (`ex02`) in edit mode once the ⊖
publication lands — my live proof used a clean-room Table with the same shape,
because injected input could not reliably press the demo's own Edit toggle (see
Concerns).

---

## Files changed

| file | why |
|---|---|
| `src/controls/table.luau` | +369: `rowEditGutter` signal + 5 dep lines |
| `src/controls/table_header.luau` | the `headerPadding` derivation |
| `src/controls/table_rows.luau` | `noteEditGutter` — publishes the composite's own gutter |
| `tests/table.spec.luau` | two red-first cases + the blocked case's pointer |
| `docs/handoff/SOURCE_CAP_LEDGER.md` | table.luau row re-recorded 189,197 → 189,566 |
| `artifacts/framework-gaps-phase2/*` | captures + probe transcripts + the blocked packet |

Commit: `5b88eb2` *"the heading band could not see edit mode, and the row had
been paying for two"*.

Nothing was written to `src/client/screen_target.luau`, `src/controls/row_actions*.luau`,
`src/controls/virtual_list*.luau`, `src/controls/virtual_grid.luau`,
`src/controls/card_rail.luau`, `src/themes/*` or `src/tokens/*`.

## Suite and gates

Measured in a content-pinned pair, as the brief requires:
`tools/mkpair.sh <scratch>/pair_fixshow HEAD HEAD` →
`PIN_FACET aec4888e5ba9dcae4e747cec48ce8f19c888a552` (my `5b88eb2` is an ancestor;
the tip is another lane's commit landed while I was verifying),
`PIN_RR 829b382ee242a87dbea2b4642e5ee6d303ee2478`.

* Facet `./run-tests.sh` in the pair → **7097 passed, 0 failed.**
* RascalRally `./run-tests.sh` in the pair → **3470 passed, 0 failed.**
* For the record: the LIVE working tree read 7093 passed / 3 failed while I
  worked, and an earlier run of the same tree read 7 failed. Every one of those
  was another lane's in-flight `src/controls/gap_metric.luau` (created 11:30
  today, no row in `tests/conformance/controls_registry.luau` at the time) —
  *"the live repository passes every registration rule"* and the two
  input/paradigm rows beside it. They are green in the pinned pair, which is
  exactly why the brief forbids measuring a suite from a live tree.
* `python3 tools/check_source_size.py` → PASS (3 in band, each with a row).
* `python3 tools/check_gate_pins.py` → PASS (260 file pins, 487 run strings).
* `python3 tools/check_manifest_integrity.py` → 1518 suite greps, all anchored.
* `lune run tools/lune/check_theme_drift_cli` → clean.
* `python3 tools/check_types.py` → PASS (0 diagnostics on the target files).
* `stylua --check` on all four edited sources → clean.
* `tools/build_places.sh` → 15 place files rebuilt, exit 0, so the director can
  re-test Bug C by reopening `examples/places/Facet-Showcase.rbxl`.

## RascalRally lockstep

**Bug C's surface is consumed, and the change is inert on it — measured, not
assumed.** RR's only `Controls.Table` consumer is
`games/RascalRally/code/src/client/FacetRacerListScreen.luau:159`, and it
declares `header = false` (line 182). `table_header.band` returns `nil` before
the new `headerPadding` memo is ever constructed for a headerless table, and the
screen passes no `editing`, no `rowActions` and no `reorderable`, so
`canEditMode` is false and `rowEditGutter` is never bound. RR's suite in the
pinned pair is **3470 passed, 0 failed** — unchanged, which is the evidence a
compatible internal change owes rather than a manufactured migration.

**Bug A/B's surfaces ARE consumed and carry RR-side contract tests already** —
`tests/facet_selection_indicator_contract.spec.luau`,
`tests/facet_segmented_picker_contract.spec.luau`,
`tests/facet_menu_contract.spec.luau`,
`tests/facet_hit_expander_overhang_contract.spec.luau`. Nothing in this round
touched the indicator or the picker, so no migration is owed today — but the
blocked `screen_target.luau` fix is a change to the NATIVE PAINT PATH of every
Button in the framework, and RR runs Facet with `UseFacetNativeStyle` (R21). It
must land with an RR-side canary in the same session, per the constitution; that
belongs to whoever the controller sequences it to, and it is called out here so
it is not discovered late.

## Self-review

* **Bug A/B**: the root cause is proved three ways (a source read that shows the
  comparison is unsatisfiable, a clean-room probe that shows the tags surviving,
  and a live A/B that shows removing exactly those tags restores exactly the two
  reported pictures). The regression window and the commit are named from `git
  show`, not inferred. I did not fix it, and I say so in the first line.
* **Bug C**: the fix is at the derivation, not at the symptom — I did not add a
  hand-applied inset to the header. The closed state is a pass-through, so the
  blast radius outside edit mode is provably zero (the existing "the header
  tracks the rows, so the columns never come apart" and "a flat package does not
  move a single pixel" cases are still green). Both new cases were proved to bite.
* **What a staff engineer would push back on**: `noteEditGutter` watches ONE
  wrapped row (re-pointed to the most recently built one) rather than all of
  them. Every row that can show the minus publishes the same number — it is two
  theme metrics and the mode — so which row is watched cannot change the reading;
  and the whole term is gated on `editingSignal`, so a stale reading cannot leak
  into the closed state. The residual edge (edit mode open, and every row that
  could show a minus filtered away, while the last-built one is gone) leaves the
  band over-inset by 36px — strictly less wrong than today, and it disappears the
  moment the blocked publication lands. Recorded here rather than smuggled.

## Concerns

1. **Bug A/B is worse than three screenshots.** The dead removal loop makes
   EVERY `facet-*` classification tag sticky for an instance's whole life —
   selection, interactive, button role, toggle value, error state, shape,
   typography role, skinned slots. Two surface tags can coexist on one node. Any
   other paint oddity reported from a native-path build should be re-examined
   against this before it is investigated as its own defect. It should be
   sequenced ahead of the rest of this campaign.
2. **The showcase place the director tested still has all three defects**, minus
   the 32px Bug C half I just fixed. The rebuilt places carry the Bug C fix; A
   and B are unchanged.
3. **A stale `studio_sync` on port 8642 silently served OLD sources.** A previous
   session's server (started 6:53PM) held the port; mine logged
   `Address already in use` to a file I was not watching, and the inject reported
   a clean `staleModules: 0` while pushing pre-fix code into the place. The
   verification looked correct and was evidence about older code — the exact
   false-evidence shape `inject.luau`'s own header exists to prevent, arriving
   through the server rather than the injector. Caught by reading the live
   `Source` length back. **Always read a changed module's live `#Source` back
   after an inject**, and check the sync log actually says `serving on`.
4. **Injected mouse input could not press the showcase's own Edit toggle.**
   `user_mouse_input` with x/y landed the cursor at a translated position
   (requested 625,317 → `GetMouseLocation` 578,375) and with `instance_path` it
   updated only y; repeated attempts left `GetMouseLocation` frozen. I fell back
   to a clean-room mount driven by a `BindableFunction`, which is stronger
   evidence for geometry but does NOT exercise the demo's own toggle path — hence
   the director re-test owed above.
5. **`row_actions.luau` publishes `api.editGutterPx` only in hosted mode.** That
   asymmetry is itself worth a look by whoever owns that file: the number is a
   fact about the row in both modes, and the WRAP-mode host (Table) is precisely
   the one with chrome outside the composite that has to match it.

## What still owes a live re-test by the director

* **Bug A** — the app bar's underline indicator, at rest, on the `tab-view` demo.
* **Bug B** — the page bar's pill indicator, mid-flight and at rest, on the
  `tab-view` demo. Both after the `screen_target.luau` fix lands.
* **Bug C** — the playlist demo (`ex02`) in edit mode. The rebuilt place shows
  the heading tracking the ≡ gutter today; it will not sit over the columns until
  the row-actions ⊖ publication lands.

---

## Postscript — what the rebuilt places actually contain

`tools/build_places.sh` ran at 2026-08-22 after `5b88eb2`, stamping
`Facet_Build = "5b88eb2+dirty <time>"` into every place (the settings panel shows
it). The `+dirty` is honest and load-bearing: the working tree at build time also
carried two other lanes' in-flight edits (`src/controls/virtual_list.luau`,
`src/controls/virtual_grid.luau`, `src/controls/gap_metric.luau`). So the
rebuilt `examples/places/Facet-Showcase.rbxl` is Bug C's fix PLUS whatever those
lanes had on disk at that instant — not a clean checkout of any commit. If the
director's re-test is meant to certify Bug C alone, rebuild from a clean tree
first; if it is a general re-test, read the stamp and take the `+dirty` at face
value.
