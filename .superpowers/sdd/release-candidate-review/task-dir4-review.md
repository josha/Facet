# Review — DIR4: `68f813e` + `67256d2` (director round 4)

Fresh-context scoped review, 2026-08-21. Reviewed as the union diff of the two commits
against `9de8bfd` (`68f813e~`); `158ba46`, which sits between them, is another wave's
one-character `gate_manifest` fix and is excluded from the breakage scan.

**Verdict — spec ✅.** All three director items are implemented literally, the review's
MAJOR-1 and MAJOR-3 are fixed, MAJOR-2 is reported with its seam named, six of the seven
MINORs are closed, and the round's correction to the brief's premise (a double-fire, not a
loss) reproduces exactly.

**Verdict — quality ⚠️ CHANGES REQUESTED. 2 MAJOR, 7 MINOR.** The two MAJORs are the same
shape as each other and the same shape as the defect this round was commissioned to fix:
**a claim about arbitration written into the source and the report, that measurement
contradicts.** One is the MAJOR-2 mitigation, which bites on no path the application can
take while two documents say it does; the other is §5's rebuilt audit, which re-asserts
"nothing else in the place binds either key" for `ButtonY` — and `src/controls/menu.luau`
binds it, in a demo the catalogue ships.

## Measurement discipline

Every number below was produced in private `git archive` exports under the session
scratchpad (`exports/9de8bfd`, `exports/67256d2`, `exports/130dcae`, `exports/3ad40b0`),
one `lune` process at a time. Nothing was written to the shared tree except this file — it
holds another writer's in-flight edits to `src/init.luau`, `tools/check_types.py`,
`tests/region_expand.spec.luau` and five more, none of them this round's.
`check_input_authority` needs the consumer at `../../../games/RascalRally/code/src`, so it
was run in a private hard-linked multi-repo shape with the real consumer symlinked
read-only, not in the live tree.

## What reproduces

| Claim | Measured | Result |
|---|---|---|
| Suite 6881 at the wave head, baseline 6865 | `./run-tests.sh` in both exports | **6865 → 6881, exit 0 both** ✅ |
| +16 is exactly this round's cases | per-file: `gallery_chrome` 53 → **67** (+14), `transient_over_live` 5 → **7** (+2) | ✅ exact |
| MAJOR-3: the rebuilt guard FAILS at `130dcae` | head's `transient_over_live.spec` copied into the `130dcae` export | **1 failed, 6 passed**, `expected panel 10400 over the live screen 11000: false` — the reported numbers verbatim ✅ |
| M7 `anchored.luau` LAYER paints `surface = "base"` | `transient_over_live` | **3 failed** (was 2 at the parent — finding 1 proved) ✅ |
| M8 `pixel_quest` ships `scrimOpacity = 0` | `transient_over_live` | **1 failed** ✅ |
| M1 `sink = true` → `false` | `gallery_chrome` | **2 failed**, both (14) cases ✅ |
| M2 `offsetX/offsetY` → `offsetY = opts.coreTop` | `gallery_chrome` | **1 failed**, (12) console row ✅ |
| M3 drop the `shoulderHint` children | `gallery_chrome` | **2 failed**, (13) ×2 ✅ |
| M4 `barReservation` ignores `overscanTop` | `gallery_chrome` | **1 failed**, (12) demo body ✅ |
| M5 drop the focus restore | `gallery_chrome` | **1 failed**, (15) ring ✅ |
| M6 drop the already-above guard | `gallery_chrome` | **1 failed**, (15) layer ✅ |
| **extra**: the `When` gate always true (hint renders on keyboard) | `gallery_chrome` | **1 failed**, (13) keyboard/touch ✅ |
| `stylua --check` on all five touched sources | export | clean ✅ |
| `check_library_purity`, `check_source_size`, `check_doc_style`, `check_no_screen_key_bindings` | export | all exit 0 ✅ |
| `check_input_authority` with the consumer scanned | private multi-repo shape | **clean, 0 new binders**, 8 allowlisted adapters, 6 ledger verbs ✅ |
| Public surface unchanged | `tools/lune/_probe_public_surface`, base vs head | **241 lines, byte-identical**; `git diff -- src/` is empty ✅ |
| RascalRally lockstep: nothing owed | grep of the whole RR tree for `showcase_chrome`, `demo_picker`, `barReservation`, `transient_over_live`, `inputHint` | **zero files** ✅ |
| The null result: R1 never lost, both shoulders symmetric | contending demo, all three transitions, both shoulders, base export | base: **both fire** (`adjust 1 → 2 → 3` while the chrome transitions); head: `adjust 0` throughout ✅ |
| The sink is per-KEY | a probe context at priority 900 on `Period`/`Comma`/`DPadDown`/`ButtonA`/`ButtonX`/`Tab`/`ButtonL2`/`ButtonR2`, chrome closed AND open | **identical at base and head** — the sink changed nothing for a key the chrome does not bind ✅ |
| The near rows do not move | full painted-geometry dump (every `adapter.paths()` node with a rect) at 390x844, 844x390, 1232x1067 | **identical, line for line, base vs head** ✅ |
| The console row moves in | 1920x1080 / Large / Gamepad | bar `(12,12)` → **`(102,72)`**, demo body `(90,149)` **both** ✅ |
| CONTESTED-2 is live | a modal demo declaring `onAdjust`, one `ButtonL1` | **`chromeOpen=true adjustHits=1`** — the tie double-fires, at head ✅ |
| CONTESTED-3's lock is real | `SOURCE_CAP_LEDGER.md` row for `presenter.luau` | extraction **OWED**, 195,000 trigger already fired ✅ |
| MINOR-7 honestly reported as not fixed | `presenter.luau:3531` and `:3542` | the 12-line block is still there **twice, verbatim** ✅ |

Everything the report offered as measured, measured. The two things it offered as *reasoned*
are where this review parts company with it.

---

## MAJOR-1 — the MAJOR-2 mitigation bites on no path the application can take, and two documents say it does

The report's "What I did do" for MAJOR-2:

> It bites on the failed-mount path, where `mounted` is nil, nothing climbed, and the old
> code re-presented anyway.

and the shipped hazard note (`showcase_chrome.luau`, `raisePanel`'s header):

> the failed-mount path raises without presenting anything, and that raise is now free.

**Both are false, and the code says so on its own face.** The guard is

```lua
if
    type(demoHandle) == "table"
    and type(demoHandle.displayOrder) == "number"
    ...
    and panelHandle.displayOrder > demoHandle.displayOrder
then
    return
end
```

and `demo_picker.luau:824` hands it `local handle = if mounted ~= nil then mounted.handle else nil`.
On the failed-mount path `mounted` is nil, so `type(demoHandle) == "table"` is false, the
guard does **not** return, and the panel re-presents. The spec's own comment in case (15)
states the opposite of the source comment three files away — *"the listener is handed nil
and the panel re-presents (it cannot prove it is above a surface it was never told
about)"* — so the same commit contains both readings.

There are exactly **two** production call sites (`demo_picker.luau:640` and `:645`, both
inside `show()`, reaching `raisePanel` through the single `watchRaise(raisePanel)`
registration at `showcase_chrome.luau:825`), and the guard skips on neither:

* **successful swap** — the demo has just been presented, so `demo.displayOrder >
  panel.displayOrder` by construction. The report itself proves this when it rejects the
  review's suggested fix ("never skips, because a demo swap re-presents the demo and it
  therefore climbs above the panel *every time*") — which is the same sentence as "the
  guard I shipped never skips here";
* **failed mount** — `nil`, so the guard cannot fire at all.

Measured, both exports, same probe:

```
[open]   demo 10300 -> 11500   panel 10400 -> 11600      6 swaps   (both revisions)
[closed] demo 10300 -> 10900                              6 swaps   (both revisions)
100 swaps, panel open:  demo 30300  panel 30400          (both revisions)
100 swaps, panel closed: demo 20300                      (both revisions)
FAILED MOUNT, panel open: panel 10400 -> 10500           (both revisions)
```

+200 per swap at head, exactly as at base; the toast band still arrives at ~48 swaps; and
the failed-mount raise still spends a slot it does not need. The only thing case (15)
exercises is `w.chrome.raise({ displayOrder = panelHandle.displayOrder - 100 })` — a
hand-built table no call site in the example can produce. **A spec case that pins an
unreachable branch is the "check that proves nothing" class**, and it is what makes this
worth MAJOR rather than a wording nit: the round reports a mitigation, ships dead code,
and pins it with a fixture.

**The one-line fix that makes both sentences true.** Skip when the handle is `nil`:
nothing was presented (a dismissal does not move `displayLayer`), so nothing climbed, so
the panel is provably still above and the re-present is provably waste. That is the only
real saving available to the app, it is the case the report says it took, and it is
currently the one case the guard refuses. Then either delete the `> demoHandle
.displayOrder` comparison as unreachable or keep it with a comment that says so, and give
case (15) a driven failed mount instead of a fabricated handle.

Nothing here contradicts the report's honest headline that the round **does not make the
rate worse** — it does not. The defect is the claimed improvement, its dead branch, and
the fixture that certifies it.

## MAJOR-2 — §5 rebuilds the audit and re-asserts the same false claim about the OTHER pair of keys

The old header said "no other context in the place binds either key". The new §5 says:

> The first version of §4 said "no other context in the place binds either key", and for
> `Backquote`/`ButtonY` **that is still true**.

It is not true for `ButtonY`. `src/controls/menu.luau:70-76` declares
`TRIGGER_KEYS.gamepad = { { keyCode = "ButtonY" } }` at `TRIGGER_KEY_PRIORITY = 1200`, and
`menu.luau:884-899` creates a **sinking** context and binds it whenever a `Menu` control
has an action system — and the catalogue ships `demo_picker.DEMOS` entry `menu`, whose
scenario mounts real `Facet.Controls.Menu` controls.

Measured with the **real** `examples/gallery/scenarios/menu` fixture mounted as the demo
inside the chrome harness, one `ButtonY` press:

```
base 9de8bfd : pres.depth 3 -> 5   chromeOpen false -> true    (the menu opened AND the chrome opened)
head 67256d2 : pres.depth 3 -> 4   chromeOpen false -> true    (the chrome sank the menu's trigger)
```

and with a stand-in context that copies `menu.luau`'s own registration (priority 1200,
`sink = true`, `ButtonY`):

```
base: ButtonY -> chromeOpen=true  menuTriggerFired=1
head: ButtonY -> chromeOpen=true  menuTriggerFired=0
```

Three consequences, in ascending order of importance:

1. **The audit sentence is false where it is load-bearing** — this is the identical
   failure the round diagnosed for the bumpers, in the paragraph written to correct it.
2. **The round's "pinned by its own case" is not pinned.** Case (14)'s fourth `it` —
   *"the toggle key still reaches the chrome through a demo that sinks the keyboard"* —
   presses `Backquote`/`ButtonY` against `contending()`, a demo that declares `onAdjust`
   and binds neither key. That is the same harness blindness the round names as the reason
   the suite never saw the L1/R1 defect ("the stand-in demo that never bound a key is why
   the suite never saw it"), reproduced one key over. The case that would bite is ten
   lines: register a 1200-priority sinking `ButtonY` context, press, assert it fired.
3. **Nothing has ruled on this one.** R19 is explicitly about the bumpers ("the bumpers
   belong to chrome sections"). The chrome now also consumes the pad's **Menu** trigger
   for every surface in the place, so the `menu` demo — whose entire subject is "one list
   of verbs, five ways in" — can no longer demonstrate its gamepad route while the chrome
   is mounted. It was already broken at base (it opened *under* a chrome panel that opened
   on the same press), so head is more deterministic, not more broken; but the disposition
   should be a stated ruling like R19's, not a sentence asserting the contention does not
   exist.

---

## MINOR findings

1. **`showcase_chrome.BAR_ID` is dead the day it lands.** Declared at `:183` with the
   comment *"the two surface ids, named once … a literal in two places is a rename waiting
   to go half-done"*, and never read anywhere in `src/`, `examples/` or `tests/` — while
   `:446` still spells `id = "ShowcaseChrome"` as a literal. `PANEL_ID` is used four times
   and earns its keep; `BAR_ID` is precisely the `sectionActions` defect (MINOR-3) that
   this commit removes, re-created in the same file.
2. **The `api.md` insertion splits `presenter.present`'s own documentation.** The new
   `### The standing rule…` heading is placed between the presenter's method list ("Handle
   fields: `.root`, `.controller`, … `.focusOrder()`") and the paragraph that begins
   *"Options — the key set is closed, and an unknown one is refused at present time"* — so
   the closed option key set now reads as belonging to the standing-rule section. The
   content of the new section is accurate (`SURFACE_LAYER.toast` really is +10000 above
   base; `.displayOrder` really is documented at `:2814`); its placement is wrong. Move it
   after the options block.
3. **R19's stated consolation is not true on a pad for the controls it costs the most.**
   §5 and the commit message both say the framework's Adjust "keeps DPad / Comma /
   Period". For a control that declares `adjustAxis` (Slider, LevelPicker) that holds — the
   DPad pair is bound to `AdjustAxis`. For a **legacy**-state control on a screen with
   horizontal navigation (`presenter.luau:2398-2402`: `if navigateH ~= nil then return
   bound end`), the bound set is **Comma, Period, ButtonL1, ButtonR1 and nothing else** —
   the first two are keyboard keys, so a pad player keeps *nothing*. That is TabView and
   Table, i.e. the `tab-view` and `table-virtualized` demos, and `tests/tab_view.spec
   .luau:945-965` is the framework asserting the shoulders as the pad's paging affordance
   ("THE SHOULDERS PAGE"). The behaviour is authorised by R19; the sentence explaining why
   it is affordable is not accurate, and the director's ruling was taken against it.
4. **The MINOR-2 fix is unpinned.** `(opts.warn or print)` now reports what the `pcall`
   catches — verified working: with a capturing `warn` supplied, one throwing listener
   produces exactly one `[Facet Showcase] a raise listener failed: …` line and the rest of
   the chrome survives. But the `gallery_chrome` harness passes `warn = function() end` at
   `:155`, so the suite would not notice if the report line were deleted tomorrow. One
   case with a capturing warn closes it.
5. **The ten-foot fix insets two edges of four.** Measured at 1920x1080 / Large:
   `/ShowcaseChrome/Dock/Bar` is `x102 y72 w1806`, i.e. its right edge is at **1908** on a
   set that crops 90 — the strip's box still runs 78px into the right bezel. Nothing is
   right-aligned in it today so nothing is hidden, but the `ViewThatFits` ladder is
   choosing its rung against an offer ~90px wider than the visible width, and any future
   right-hand chrome lands behind the bezel. Identical at base, so this is an incomplete
   fix rather than a regression. The `Dock`'s width (or a matching `overscanRight`) is
   where it belongs.
6. **CONTESTED-2's "not an example's call" is overstated.** `TOGGLE_PRIORITY` is the
   example's own constant. Setting it to 3501 breaks the first-modal tie deterministically
   in the chrome's favour — which is the outcome R19 asks for — without touching a
   framework band, and leaves the second modal (4000) winning and sinking, which is also
   one action per press. It may still be the wrong call (a magic +1 wedged into a
   framework band is its own smell), but it is an app-side option that was not evaluated,
   and the item is filed as though none exists.
7. **`isPanelPath` is a loose prefix test.** `string.sub(path, 1, #PANEL_ID + 1) ==
   "/ShowcasePanel"` also matches `/ShowcasePanelX/...`, unlike the spec file's own
   `isPrefix` helper which checks for the separator. Harmless with one such surface;
   wrong as written, in a function whose whole job is "is this path mine".

---

## Per-item verdicts

### 1. The chrome respects overscan — **ADDRESSED**, with MINOR-5

Root cause confirmed by reading: `rootPolicy = "edgeToEdge"` takes the whole viewport and
reads no insets, so the renderer's ten-foot margin reached every content surface except the
one nearest the glass. The fix is gated on `distanceProfile`, the same gate the renderer
uses, through one pure predicate shared by the memo and the host heartbeat — the right
shape, and the reason the near rows are arithmetic with zero in them.

**The double-count is real and the subtraction is right.** Reproduced end to end at
1920x1080: `barTop = 0 + 60`, chips bottom 141, `barReservation(0, 141, 8, 60) = 89`, the
renderer adds 60, demo body at **149** with an 8px gap under the chips — and `demo.rect.x
== 90`, so the content keeps its own margin.

**On "byte-identical".** The shipped case proves two numbers per row (`chips.rect.x ==
screen.rect.x + 8`), which is weaker than the claim. I ran the stronger version: a full
sorted dump of every painted node's path and rect at all three near viewports, base vs
head — **identical, line for line**. The claim holds; the proof in the file does not
carry it alone.

### 2. Shoulder discoverability — **ADDRESSED**

The glyph is the binding's own `displayName` read back through `Facet.inputHint`, so there
is one spelling of "LB" in the tree; the gate is `effectiveInput` through a `UI.When`, and
the "first chip starts at the row's own edge" assertion is the right instrument for
proving it is a `When` and not a blank string (mutating the gate to a constant `true`
reddens exactly that case). Both rungs build fresh nodes from a function rather than
sharing one table. Nothing in `src/` moved, and the focus map is untouched.

### 3. Both shoulders, one action — **ADDRESSED** (see MAJOR-2 for the key it did not audit)

`deviceKey` is per-key by construction (`actions.luau:365-412`: candidates are gathered
only for bindings whose `keyCode` matches, and `consumedPriority` cuts only *strictly*
lower contexts), so the sink is correctly scoped, and I measured it: eight keys the chrome
does not bind fire identically at base and head, with the chrome closed and open. The
harness change (`demoPresent`) is the right fix for the blindness that hid the defect, and
the negative control (`Period`/`Comma` first, proving the demo's Adjust is live) is the
case that makes `adjustHits 0` mean something.

### MAJOR-2 (display-layer climb) — **CONTESTED, correctly diagnosed, mitigation inert**

The seam citations check out (`presenter.luau:2635-2637` for `displayLayer += 100` inside
`makeHandle`, `:3553` for the `#stack == 0` reset), the lock is real (`SOURCE_CAP_LEDGER`
row: extraction OWED, trigger fired), and the rejection of `presentModal` and of
`handle.controller.setDisplayOrder` is reasoned rather than convenient. The hazard note
and `api.md` are honest about the halved horizon and my 100-swap numbers match theirs. What
fails is the "and here is what I did do" — see MAJOR-1.

### MAJOR-3 (the guard was green on its own defect) — **ADDRESSED, and proved**

This is the round's strongest work. The rebuilt spec fails at `130dcae` with the reported
numbers, the viewport-derived threshold makes the third construct live (M7 goes from
reddening two cases to three), the base roots are a set, all eight packages' scrim rules
are read (M8 bites), and the fifth construct drives the real `demo_picker` +
`settings_panel` + `showcase_chrome` with a negative control proving the predicate can see
an app-declared opaque fill. Every mutation reproduced.

### MINOR spot-checks

* **MINOR-3** (`sectionActions` dead) — gone; the actions are keyed by section because the
  glyphs read them. Verified by reading and by M3's bite. *(But see MINOR-1: a new dead
  constant arrived in the same diff.)*
* **MINOR-2** (`pcall` swallows) — the fix works; verified by supplying a real `warn` seam
  and catching exactly one report line. Unpinned by the suite (MINOR-4 above).
* **MINOR-4** (focus reset) — the restore works and M5 reddens its case; the two traps the
  report describes (reading `focused` inside the raise reads the *new* demo; a `focusOn`
  on the line after `present` is a no-op behind a `When`) are both real in the code as
  written.
* **MINOR-7** — correctly reported as NOT FIXED: the duplicate 12-line block is still at
  `presenter.luau:3531` and `:3542`, verbatim, in a locked file.

---

## Measured and cleared (recorded so it is not re-litigated)

* **The null result is genuine.** Both shoulders performed all three transitions at base,
  symmetrically, and both double-fired an `onAdjust` surface (`adjust 1 → 2 → 3`). Nothing
  headless makes R1 lose. The live "R1 does nothing" is still owed a device pass, and the
  report says so in Concern 1.
* **The dynamic-Adjust path does not double-fire the way the static one does.** With a
  focused adjust target, the value does not move at base either — the chrome's present
  moves focus off the target before the Adjust dispatch resolves. The measured double-fire
  is the `opts.onAdjust` (consumer opt-in) path, which is what case (14) drives. The
  round's framing is right; the mechanism is worth knowing before someone re-measures.
* **CONTESTED-2 is live at head**: a modal demo with `onAdjust`, one `ButtonL1`,
  `chromeOpen=true adjustHits=1`. Accurately recorded (see MINOR-6 for the one untried
  app-side option).
* **RascalRally**: `src/` untouched, public surface byte-identical, zero references in the
  consumer tree, `check_input_authority` clean with the consumer scanned. Nothing owed,
  and the evidence is reproducible.
* `check_comment_codes` (needs `git ls-files`) is genuinely unrunnable in an archive
  export; the report's disclosure of that is accurate, and the checks that *can* run in an
  export all pass.

## Recommended before merge

1. **MAJOR-1** — make the guard skip on `demoHandle == nil` (the failed-mount path: nothing
   was presented, so nothing climbed), and correct the two sentences that describe the
   guard biting on a path where the code passes `nil`. Replace case (15)'s fabricated
   handle with a driven failed mount so the case pins a branch the app can reach.
2. **MAJOR-2** — replace §5's "for `Backquote`/`ButtonY` that is still true" with the
   measurement (`menu.luau:70-76`, priority 1200, sinking; the `menu` demo ships it), add
   the ten-line case that presses `ButtonY` against a context that actually binds it, and
   get a ruling on the pad's Menu trigger the way R19 ruled on the bumpers.
3. **MINOR-1, MINOR-2, MINOR-7** are one-line cleanups (delete or use `BAR_ID`; move the
   `api.md` heading below the options block; tighten `isPanelPath`).
4. **MINOR-3** is a correction the director should see, because it changes the price of
   R19: on a pad, a legacy-state adjust control keeps *no* Adjust route once the chrome
   takes the bumpers, not "DPad / Comma / Period".
5. **MINOR-4, MINOR-5, MINOR-6** are follow-ups, not blockers: pin the warn, inset the
   strip's right edge (or its width) on a ten-foot display, and record the 3501 option
   inside CONTESTED-2 so the next reader knows it was considered.
