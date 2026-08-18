# Wave ADAPT-AUDIT — the default-paradigm matrix

**Anchor:** commit `d6c5b3c4`, measured from a private `git archive` export.
**Suite at the anchor:** `6467 passed` — re-run in the export, matching the briefed
baseline exactly, so the export is faithful and every probe below ran against the
same tree the controller is adjudicating.
**Seat:** fresh-context audit. Findings only; the controller adjudicates and routes
fixes. Read-only on tracked files except this artifact.

**The director's question**, restated so every verdict below answers it: *by default,
does Facet give the right expected controls, views and interactions on every
screen-size × input combo?* Not "is every control reachable" — prior gates own that —
but "is the PARADIGM right".

**The governing bar is already on the record** and is not this seat's invention.
`artifacts/input-adaptation-audit/matrix.md:12-22` quotes `ui_todo.md` §0, director
2026-07-20:

> Each control/tool must ship with the right interaction for ALL supported inputs …
> **verified per input in tests, with NO CONSUMER WIRING**.

That prior audit's vocabulary (AUTO / CONSUMER-WIRED / MISSING) maps one-to-one onto
this one's (RIGHT / AUTHORED-ONLY / MISSING), and its 2026-07-21 baseline was AUTO 12,
CW 39, MISSING 13 across 64 control cells. **AUTHORED-ONLY is therefore a failure of a
standing director ruling, not a neutral state.** That is the single most important
calibration in this document, and it is why the counts below read the way they do.

## The columns

Framework vocabulary throughout, never device names. Facts as set on `tests/lib/world.luau`:

| Combo | viewport | capabilities | preferredInput | displaySize | resolves to |
|---|---|---|---|---|---|
| compact touch (portrait) | 390×844 | touch | Touch | Small | `compact` / `medium` / primary `touch` |
| compact touch (landscape) | 844×390 | touch | Touch | Small | `regular` / `short` / primary `touch` |
| regular touch (tablet) | 1024×768 | touch | Touch | Small | `wide` / `medium` / primary `touch` |
| desktop pointer + keyboard | 1600×900 | mouse, keyboard | KeyboardAndMouse | Medium | `wide` / `medium` / primary `pointer` |
| ten-foot gamepad | 1920×1080 | gamepad | Gamepad | Large | `regular` (capped) / `medium` / primary `gamepad` |
| hybrid (pointer+touch) | 1280×800 | mouse, touch, keyboard | either | Medium | primary flips `pointer`↔`touch` live |

---

# Part 1 — The spine finding

## ADAPT-1 · Adaptation is a fact the AUTHOR must hand to the control, and it fails silently

**Severity: high. Confidence: high.**

`grep 'env:get(' src/controls/*.luau` — only **6 of 33** control modules read the
environment at all (`level_picker`, `row_actions`, `row_actions_metrics`,
`selection_indicator`, `table`, `text_input`). `picker`, `popup_button`, `menu`,
`callout`, `tab_view`, `slider`, `stepper`, `virtual_grid`, `virtual_list` read
nothing. This is stated as design in `docs/reference/swiftui-parity.md:482-485`:

> Two controls (`popup_button`, `picker`) take a size class in as a spec parameter
> rather than reading the key.

Two adjacent adaptive controls then have **opposite default failure modes**:

- `tab_view.luau:337-352` — `placement = "automatic"` with no `conditions`/`env`
  **hard-errors**, with a message naming the fix. Adaptation cannot silently not
  happen. **This is the correct pattern.**
- `picker.luau:426-433` — `sizeClass` nil ⇒ `readSizeClass` returns nil ⇒ the compact
  branch of `resolvePresentation` is unreachable. **Silently** takes the large-screen
  answer, forever.
- `popup_button.luau:238-242` — the same, twice over: nil `sizeClass` **and** nil
  `interactionClasses`.

Probe (pure functions, at the anchor):

```
picker.resolvePresentation(4, nil,       14) -> "segmented"   four long labels crammed on a phone
picker.resolvePresentation(4, "compact", 14) -> "inline"      the correct answer, when fed
menu_recipe.resolvePresentation(3, nil,     nil)   -> "inline"
menu_recipe.resolvePresentation(3,"compact",false) -> "menu"
menu_recipe.resolvePresentation(3,"compact",true ) -> "sheet"  the correct answer, when fed
```

### The census that makes this concrete

Scripted brace-matched scan of every adaptive-control call site in `examples/`
(each control's whole spec table parsed, not a line grep):

| control | call sites | wire the fact | FORCE a presentation (opt out of adaptation) | rely on the adaptive default |
|---|---|---|---|---|
| `Picker` | 17 | 8 (`sizeClass`) | 10 (`presentation = "segmented"`) | **0** |
| `PopupButton` | 5 | 5 (`sizeClass`) | 0 | 0 |
| `Menu` | 1 | 1 (+ `interactionClasses`) | 0 | 0 |
| `Callout` | 2 | 0 | 0 | **2** — and `Callout` has no adaptive surface to wire: its closed spec (`callout.luau:69-85`) has no `sizeClass`, no `presentation`, and the file contains zero occurrences of `compact`/`sheet`. See the transient-surface family. |

**Not one of 17 picker call sites uses the automatic presentation.** Ten explicitly
disable it. The adaptive ladder that exists, is exported, is pure and is unit-tested
is chosen by zero shipped surfaces — so it has never been exercised in situ, which is
exactly why the nil-fact path was never caught.

The ladder's *first* rule is dead everywhere too: `interactionClasses` is wired at
exactly one place in all of `examples/` — `gallery/scenarios/menu.luau:265`. All five
`PopupButton` sites wire `sizeClass` and omit `interactionClasses`
(`reference/p2_cartwheel/screens/workbench.luau:326-331`), so `touchLive` is false and
`if touchLive then return "sheet"` never fires in any reference app. Every ingredient
picker in the reference app presents as a floating plate on a phone where the
reference platform's own default is a sheet.

**Smallest fix.** Do not add a new mechanism — adopt the one `tab_view` already uses.
Let `picker`/`popup_button` accept `conditions` or `env` and derive the facts
themselves, and make the fact-less construction of an `automatic` presentation a
construction **error** naming the fix, exactly as `tab_view.luau:344-350` does. A
control whose adaptation is optional and silent is a control whose adaptation does not
ship.

---

# Part 2 — Per-family matrices

## Family A · Navigation (navPlacement)

Measured by probe over `adaptive.navPlacement` at every combo and at every canonical
row of `tests/lib/device_views.luau`.

| combo | measured today | expected | verdict |
|---|---|---|---|
| compact touch portrait | `bottomBar` | full-width bar in the thumb zone | **RIGHT** |
| compact touch landscape | `bottomBarCompact` | the reduced inline bar | **RIGHT** |
| **regular touch (tablet)** | **`bottomBar`** | `topBar` — the tablet shape the policy itself documents | **WRONG** (ADAPT-2) |
| desktop pointer | `sidebar` | sidebar | **RIGHT** |
| ten-foot gamepad | `topBar` | centered top bar that hugs | **RIGHT** |
| hybrid | `sidebar`, flipping to `topBar` on first touch | exactly that | **RIGHT** (ADAPT-3) |

`TabView` genuinely consumes this by default (`tab_view.luau:332-352`) and refuses to
guess — a real strength, and more adaptive than the reference platform, whose tab bar
stays a bottom bar everywhere unless the author opts into `.sidebarAdaptable`.
Probed: `dump().placementSource == "policy"` on all six combos, and the strip really
re-homes (`BottomHome/` · `CompactHome/` · `TopHome/` · `RailHome/` with matching solved
rects). `newTabView` is the *only* consumer — `screen_chrome.luau` and `chrome_slots.luau`
carry zero `navPlacement` references, correctly, as they are paint subsystems.

### ADAPT-4 · The three placements documented as CENTERED are left-aligned

**Severity: high. Confidence: high.** The policy module states the contract twice
(`adaptive.luau:114-122`): `bottomBarCompact` is "the SAME bottom bar in its reduced,
inline, **centered** form", and `topBar` is "a **center-aligned** top tab bar that HUGS
its content (never full width)". `api.md:3756` and `api.md:6019` repeat it.

`tab_view.luau:493-529` declares **no main-axis alignment at all** — independently
confirmed: the only `align` in the file is `align = "stretch"` at line 461, which is
the *cross* axis. Measured:

| combo | band | strip | leftGap | rightGap |
|---|---|---|---|---|
| ten-foot 1920×1080 | 1740×46 @x90 | 193×46 @x90 | **0** | **1547** |
| tablet | 1024 | 193 | 0 | 831 |
| compact touch landscape | 844 | 193 | 0 | 651 |
| ten-foot, 8 tabs | 1740 | 1028 | 0 | 712 |

On a TV a three-tab bar is a 193px cluster in the top-left corner with 1547px of empty
band beside it. Three of six combos are affected; `bottomBar` (fill) and `sidebar` are
unaffected.

**Smallest fix, with the trap named.** The in-repo precedent is exact —
`level_picker.luau:459-465`, director ruling 2026-07-27: *"a strip pinned to the leading
edge of a wide column reads as misaligned with its own header"*. **But that same comment
carries the warning that makes the naive fix wrong:** `alignH` "is honoured for zstack
children — an **HStack ignores it**, so putting it there would have been
accepted-and-ignored." So the fix must place the centering on a ZStack root (or use the
stack's own distribution), and must be proven by a measured `leftGap == rightGap`, not
by the property appearing in a dump.

### ADAPT-2 · The tablet column of every gate has been measuring a phone

**Severity: high. Confidence: high.**

`adaptive.luau:118-131` documents its own intent — "touch + Medium/Large disp →
`topBar` (tablet shape)", "touch/gamepad + Small → `bottomBar`". The engine disagrees
with that mapping. `displaySize` comes from `GuiService.ViewportDisplaySize`
(`src/client/roblox_env.luau:151-155`), and Roblox documents **`Enum.DisplaySize.Small`
= "Most tablet/mobile/handheld devices"**, `Medium` = "most laptops and monitors",
`Large` = "TVs or larger". So:

- a real tablet reports `Small` → takes the **phone bottom bar**;
- `Medium` is a pointer device, which `primary == "pointer" → sidebar` catches first.

The `topBar` tablet branch is therefore reachable only by a touchscreen laptop whose
player last touched the glass. **No tablet can ever reach the tablet paradigm.**

The framework's own canonical matrix already recorded this and nobody read it —
`tests/lib/device_views.luau:27` declares `tablet-landscape … displaySize = "Small"`.
Probe over that exact table:

| canonical row | w×h | displaySize | sizeClass | navPlacement |
|---|---|---|---|---|
| compact-phone-portrait | 359×718 | Small | compact | bottomBar |
| compact-phone-landscape | 705×338 | Small | regular | bottomBarCompact |
| **tablet-landscape** | **1079×809** | **Small** | **wide** | **bottomBar** ← phone paradigm |
| desktop-standard | 1232×1067 | Medium | wide | sidebar |
| console-ten-foot | 1920×1078 | Large | regular | topBar |

Flip that one declared value to `Medium` and the same viewport yields `topBar`
(probe confirmed both ways). So the regular-touch column of every prior five-view gate
has been a second phone row — and `device_views.luau` is *right about the engine*,
which is what made this invisible.

Platform-side confirmation that the fact simply is not available: an open Roblox
feature request asks for a `DeviceFormFactor` enum precisely because "None of these
tell me whether the device is a phone or tablet".

**Smallest fix — needs no new fact, but the obvious version of it is wrong.** I tested two
candidates rather than assuming:

| case | w×h | `sizeClass == "wide"` | **`min(w,h) >= 600`** |
|---|---|---|---|
| phone portrait | 390×844 | phone ✓ | phone ✓ |
| phone landscape | 844×390 | phone ✓ | phone ✓ |
| big phone landscape | 932×430 | phone ✓ | phone ✓ |
| **tablet portrait** | 810×1080 | **phone ✗** | **tablet ✓** |
| small tablet portrait | 768×1024 | **phone ✗** | **tablet ✓** |
| tablet landscape | 1079×809 | tablet ✓ | tablet ✓ |

The intuitive fix — "a tablet is `sizeClass == "wide"`" — **still gets portrait tablets
wrong**, because a portrait tablet is 768–810 wide and lands in `regular`, the same class
as a landscape phone. The discriminator that holds in both orientations is the **short
side**: every phone has `min(w,h) < 600` whichever way it is held, every tablet has
`min(w,h) >= 600`, and it reuses the existing `BREAKPOINTS.regular` constant rather than
introducing a number. Desktop and console are `wide`/ten-foot but are caught by the
earlier pointer and distance branches, so they never reach this test.

So: replace the `displaySize` test inside the touch branch with a short-side test, and
correct `device_views.luau`'s row so the matrix stops asserting a value the engine will
never deliver.

### ADAPT-3 · Hybrid is the column that is right (recorded as a positive)

**Confidence: high.** Probe: pointer+touch+keyboard at 1280×800 → `primary=pointer`,
`nav=sidebar`; the same device with `preferredInput="Touch"` → `primary=touch`,
`nav=topBar`. The flip is live and deliberate, and the reasoning is written down at
`environment.luau:508-527` — a preference the player has not expressed cannot outvote
what the device physically is. **RIGHT**, and the pattern the other columns should copy.

## Family N · Ten-foot specifics

| row | measured today | expected (tvOS-convention tie-breaker) | verdict |
|---|---|---|---|
| focus visibility | ring 2px → **4px** plus **1.05 scale** on the Large display class, glow derived (`default_style.luau:52-59`, `chrome_slots.luau:2172-2179`); `focusVisible` is suppressed only for pointer-origin focus (`focus_graph.luau:210-232`) | focus must be unmistakable across a room; scaling ~1.05–1.1x, never colour alone | **RIGHT** |
| size decisions vs. the real screen | `contentWidth` is the **raw** viewport (`adaptive.luau:300-306`, verifier finding V16): "In the console matrix row it reads 1920 while overscan removes 106px per side" | decisions should respect the TV-safe area | **WRONG** (ADAPT-5) |
| size class at ten foot | 1920 caps to `regular` — the same class an 844px landscape phone gets | deliberate density cap | **RIGHT**, with the caveat that anything keyed on `sizeClass` alone cannot tell a TV from a landscape phone |

### ADAPT-5 · Ten-foot decisions run against a width the screen does not have

**Severity: medium. Confidence: high.** `grep -i overscan src/` finds only virtual-list
windowing overscan (`virtual_extents.luau`) — there is **no TV-safe content width
anywhere in the framework**. Every ten-foot decision keyed on `contentWidth` is made
against 1920 when roughly 1708 is real. The hazard is self-documented and the fix was
declined ("belongs in `ViewThatFits`, which measures") — but nothing in the ten-foot
column actually routes through `ViewThatFits` by default, so the decline left a hole
rather than a route. **Smallest fix:** derive an inset-aware `safeContentWidth` beside
the raw one from the `coreSafeInsets` fact the environment already carries, and point
the ten-foot rows at it.

## Family C · Pickers and value controls

| # | combo | measured today | expected | verdict | sev | conf |
|---|---|---|---|---|---|---|
| C-1 | all six | With default authoring (`sizeClass` omitted) `dump().presentation` is **byte-identical on all six combos**: n=2 → `segmented`, n=5 → `inline`, n=3 @14-char labels → `segmented`. Only OPTION COUNT bites (`picker.luau:249`) | the ladder is driven by width AND count | **AUTHORED-ONLY** (width axis; the count axis is a real default) | high | high |
| C-2 | compact touch portrait | With `sizeClass` wired, only this combo changes, and only the long-label case (`segmented → inline`, `picker.luau:252`) | width-driven collapse | RIGHT once wired | — | high |
| C-3 | 2,3,4,5,6 | With `sizeClass` wired the answer is **unchanged from unwired** on every non-compact combo. Input class is never consulted | a ten-foot pad and a desktop mouse should not get identical option rows | **MISSING** (no input-class rung) | med | high |
| C-4 | all six | `presentation = "menu"` / `"stepper"` are **rejected at build** — confirmed: `PRESENTATIONS = { automatic, segmented, inline }` (`picker.luau:207,301`). A phone with 8 options collapses to a full-width stacked list, **never a menu** | many options on a small screen → menu/sheet | **MISSING on `newPicker`** (the rung lives on `newPopupButton`, unreachable from `automatic`) | med | high |
| C-5 | all six | `menu_recipe.resolvePresentation` **does** have a touch rung, but both facts are author-passed. Unwired: n≤3 → `inline`, n>3 → `menu` on **every** combo — a touch phone gets the desktop floating-panel idiom | touch → sheet by default (the reference platform's own default) | **AUTHORED-ONLY** | high | high |
| C-6 | ten-foot gamepad | **The prior HStack-alone focus defect is FIXED at this anchor.** `focus_map.isHorizontalRun` (`focus_map.luau:639-670`) matches an `AdaptiveStack` whose live `axis == "x"`; `DPadRight` really moves `Opt1 → Opt2` on all six | segmented picker traverses its own axis | **RIGHT** | — | high |
| C-7 | all six | Slider keyboard/gamepad stepper is a **default**: 50 → 51 on `Period`, `ButtonR1`, `DPadRight` on every combo (`value_model.luau:117`, `slider.luau:596-620`) | focus-gated Adjust, not a mandatory stick | **RIGHT** | — | high |
| C-8 | touch combos | Slider has **zero input-class awareness**; touch gets the same continuous drag. Track height 44 on all six | touch may want detents | **MISSING**, possibly deliberate — no ruling found | low | high |
| C-9 | all six | `newLevelPicker` Adjust works everywhere, but its **touch density is env-gated**: mark gap **7px** with `env`, **5px** without, on the same touch phone (`level_picker.luau:313-318`) | a finger gets the wider run automatically | **AUTHORED-ONLY**, and silent | med | high |

## Family D · Text entry

| # | combo | measured today | expected | verdict | sev | conf |
|---|---|---|---|---|---|---|
| D-1 | all six | `clearButtonMode` resolves to **`"never"` on all six**; no clear node is mounted even with a value (`text_input.luau:203,211-229`) | touch/search fields offer a clear affordance | **AUTHORED-ONLY** — matches the reference platform's `.never` default, but Facet claims an adaptivity the reference does not | med | high |
| D-2 | all six | Occlusion response **works by default when `env` is passed**: field bottom lands at 456.2 vs keyboard top 464.2 — exactly `KEEP_VISIBLE_MARGIN = 8` (`text_input.luau:101,234-251`) | layout responds to the occluded area | **RIGHT** (given env) | — | high |
| D-3 | compact touch | With **no `env`**, `occlusionOffset` stays **0** — the field sits under the keyboard, silently | — | **AUTHORED-ONLY** | med | high |
| D-4 | ten-foot gamepad | The pad **entry** route is a complete default: field focusable, `ButtonA` → `editing=true`, D-pad swallowed while editing, `ButtonB` → revert. Typing is delegated to the engine via `TextBox.Selectable` + `CaptureFocus` (`screen_target.luau:1480,3453-3470`) | a ten-foot surface has a way to type | route **RIGHT**; the keyboard itself not measurable headlessly | — | high |
| D-5 | all six | `submitLabel` carried as data and never applied — `TextBox.ReturnKeyType` is `[Hidden, NotScriptable]` (`text_input.luau:56-61`) | — | documented engine-absent exception, no action | low | high |

## Family E · Transient-surface dismissal (measured with navigation)

| combo | measured today | verdict |
|---|---|---|
| all six | **`ButtonB` dismisses a default modal on every combo** (`presenter.luau:2421`); **outside-tap dismisses on every combo** (`outsideTapCancel` defaults true) | **RIGHT** |
| desktop/hybrid keyboard | **`Escape` does nothing** — deliberately unbound, engine-reserved, ruling inline at `presenter.luau:2417-2420` and `target_contract.luau:78` | **MISSING but justified**; the escape hatch is a screen-provided close control |
| desktop/hybrid sidebar | Rail traverses correctly (`DPadDown` moves `Opt2 → Opt3`), but is **not collapsible** — `collapsed`/`collapsible`/`sidebarCollapsed` are all rejected by the closed spec | reachable RIGHT; **collapse MISSING** (med) |
| compact touch landscape | `bottomBarCompact` band is **46px — identical to `bottomBar`** — with the same full labels, though `api.md:3756` promises "short labels, tighter band" | **MISSING** (only the fill→hug flip shipped); low — either ship the compact metric + `compactLabel` pass, or correct the doc |

**A precision note on the recommended fix.** Several rows above want the facts to arrive
without the author passing them. The contribution seams that already exist are
`bindController`, `bindMotion`, `bindFocusGraph`, `bindNativeScroll`, `bindActionSystem`,
`bindPresent`, `bindScroll`, `bindAxis`, `bindAdjustKeys`, `bindCamera`
(`src/input/contribution.luau`). There is **no environment contribution seam**. A
`bindEnv` does exist but it is a *host-level* test seam for swapping the engine binder
(`src/client/host.luau:78`, under "seams (headless, Edit mode, or a consumer that owns a
piece)"), not a per-control channel — so the fix is a new sibling seam, not the adoption
of an existing one.

## Family K · Editable collections

**A combo-invariance result worth stating first.** Across editable collections, selection
and drag, *nothing measured varies with viewport or `displaySize`*. Every divergence is
driven by `interactionClasses` or by **which other spec keys the author happened to
declare** — never by the combo. The framework's edit/selection/drag paradigms are gated on
**declaration shape, not device shape**.

| # | cell | measured today | verdict | sev |
|---|---|---|---|---|
| K-1 | `newTable` + `rowActions`, swipe tray | tray opens on both a **touch** and a **mouse** drag, identically, at all six combos (24/24 rows). No `interactionClasses` read anywhere in `row_actions*.luau` | **RIGHT** | — |
| K-2 | `newTable` + `rowActions` **alone**, keyboard/gamepad route | **The table has ZERO focus stops.** Initial focus `nil`; twelve `Down` presses reach `nil`; `Delete fired: 0`; `ButtonX menu: false` on combos 4 and 5 | **MISSING** (ADAPT-13) | **high** |
| K-3 | `newVirtualList` + `rowActions` (hosted) | **all four routes DEFAULT** on all six combos: touch swipe, mouse swipe, focus on row 1, `Delete → fired=1`, `ButtonX → menu=true` | **RIGHT** — the reference implementation | — |
| K-4 | edit-mode ⊖ auto-toggle | shows when `reorderable` or (`selection ≠ none` and `onPrimaryAction`), gated on `classes.touch or classes.gamepad`. Absent on desktop pointer by explicit ruling ("a mouse user reaches both capabilities without it") | **RIGHT** (by ruling) | low |
| K-5 | virtualized Table + `rowActions` | a **construction refusal** with a named alternative ("Use newVirtualList"). `newVirtualGrid` offers no selection/reorder/rowActions at all | **RIGHT** — a loud, named refusal, not a silent gap | — |

### ADAPT-13 · A Table that declares only `rowActions` is unreachable on keyboard and gamepad

**Severity: high. Confidence: high.** Confirmed verbatim at `table.luau:1926`:

```luau
focusable = selectionMode ~= "none" or spec.reorderable == true,
```

`rowActions` is not in that disjunction, and `newTable` has no `rowFocusable` key at all.
With no focus stop, the engine's key context is never even built. Proof that the focus stop
is the whole mechanism: the *same* table with `selection = "single"` focuses row 1
immediately and `Delete fired: 1` / `ButtonX menu: true` on both combos.

Second-order confirmation of the shape: after a **mouse** swipe opens a tray on the
no-selection table, the tray button becomes the only focus stop on the screen — so the
non-pointer route exists but must be **bootstrapped by a pointer**.

**Three things make this the cleanest fix in the audit.** (1) `api.md:4445` claims the
opposite in as many words — "Keyboard and gamepad Delete/menu bind per row through the
wrapper itself … with no separate Table wiring." (2) `virtual_list.luau:1780-1792` has
**already diagnosed and closed this exact defect** for lists, in prose that describes
Table's current state precisely: "a row a keyboard-only or pad-only player had merely
focused had no engine and therefore no binding at all … Row actions were reachable by
pointer only." (3) The fix is one clause — add `or spec.rowActions ~= nil` — in the same
shape as the `reorderable` clause already there. `rowDeletable` already asserts `rowActions`
is present, so it cannot widen anything else.

## Family L · Selection

| # | cell | measured today | verdict | sev |
|---|---|---|---|---|
| L-1 | single selection | works from every paradigm, identical on all six combos | **RIGHT** | — |
| L-2 | multi on **pointer** | plain click replaces; Ctrl-click toggles `[r1,r3]`; Shift-click ranges `[r1..r4]` — identical all six | **RIGHT** | — |
| L-3 | multi on **touch**, no `onPrimaryAction` | two taps → `[r1,r3]` additive | **RIGHT** | — |
| L-4 | multi on **touch**, with `onPrimaryAction` | normal-mode tap selects nothing; after the auto Edit toggle, two taps → `[r1,r3]` — the reference platform's documented rule, cited in-file | **RIGHT** | — |
| L-5 | edit mode's **visible** selection affordance | on a selectable, non-reorderable table the row mounts exactly `Row/Hit` + `Row/Cells` — **no leading circle, no checkbox, no gutter**; the only change is the invisible `selected` prop. The sole cue that the mode changed is the toolbar label flipping Edit→Done | **WRONG** | med |
| L-6 | multi on **keyboard** | **a single arrow press destroys any multi-selection**: ctrl-clicks build `[r1,r3]`, one `Down` → `[r4]`. `Ctrl+Down` does not move without selecting. `Shift+Down ×2` does not extend | **MISSING** (ADAPT-14) | **high** |
| L-7 | multi on **gamepad** | **a pad can never hold two rows selected**: `A`→`[r1]`, `DPadDown`→`[r2]`, `A`→`[r2]` | **MISSING** (ADAPT-15) | **high** |
| L-8 | `newVirtualList` multi-selection | a hard construction error — "must be \"none\" or \"single\"" — and named as a known hole in the parity doc | **MISSING but declared** — a loud refusal | med |
| L-9 | `selection_indicator` | an internal seam, never a focus stop, by director ruling 2026-08-16; combo-invariant | **RIGHT** | low |

### ADAPT-14 · Keyboard multi/range selection is destroyed by focus movement

**Severity: high. Confidence: high.** `table.luau:3678` — `api.handleFocusMoved` calls
`api.select(rowKey, { mode = "replace" })` on **every** focus move, with no modifier
awareness and no focus-cursor/selection split. A selection built by ctrl-click dies on the
first arrow press. **Fix:** read `actionSystem.modifiers()` in `handleFocusMoved` — the
presenter already publishes shift/toggle on Activate — and branch: `toggle` → move focus and
select nothing; `shift` → `mode = "range"`; neither → today's `replace`.

### ADAPT-15 · Multi-selection is structurally unreachable on a gamepad

**Severity: high. Confidence: high.** A pad Activate carries `meta.source = "action"` with
`shift`/`toggle` read from `system.modifiers()` — a **keyboard-only** modifier table
(`actions.luau:260-268` lists LeftShift/RightShift/Control/Meta) — so a pad always lands in
the `else` branch and replaces. This violates the control's own four-input rule as written
at `table.luau:865`: "our four-input rule makes every declared verb reachable on every
input." An author can declare `selection = "multi"` and a pad player can never produce a
multi-selection.

**Fix — the cheaper of the two options is already pad-reachable.** Rather than inventing a
bumper-as-modifier chord, reuse edit mode: while `editingSignal` is true, make a device
Activate `mode = "toggle"` rather than `replace`. One clause in `handleActivate`, and the
auto Edit toggle already shows for `classes.gamepad` (K-4), so the mode is reachable today.

## Family M · Drag interactions

| # | cell | measured today | verdict | sev |
|---|---|---|---|---|
| M-1 | Table **column resize** | **all four routes work on every combo**: mouse grip 160→200, touch grip 160→200, keyboard `Period` 160→176, gamepad `ButtonR1` 160→176 | **RIGHT — the model cell of this audit** | — |
| M-2 | Table row reorder, touch | body drag correctly declines (it would fight the scroll); the auto Edit toggle appears and a drag on the edit-mode ≡ reorders | **RIGHT** | — |
| M-3 | Table row reorder, gamepad | `A` → edit mode, `DPadDown` to a row, `A` grabs, `DPadDown ×2` moves one slot per press, `A` drops. `reorders = 2` | **RIGHT** | — |
| M-4 | Table row reorder, keyboard-only | no Edit toggle is mounted (the auto-toggle union is touch ∨ gamepad) and the grab branch requires edit mode, so `Down×3 + Return` → `reorders = 0`. Forcing `api.editing:set(true)` makes the identical journey work | **AUTHORED-ONLY**, degrading to MISSING in a keyboard-only session | med |
| M-5 | `newVirtualList` row reorder, **touch** | **no touch route at all**: touch drag is declined and there is no `armOnTap`, no edit mode and no ≡ handle. The in-file comment claims touch "reaches reorder through the grab verbs — Table's precedent", but Table's grab verb is a *mounted* handle a finger can press; VirtualList's `toggleGrab` is a Luau function bound to no touch gesture | **MISSING** | **high** |
| M-6 | `newVirtualList` reorder, pad/keyboard | `A` arms → `DPadDown ×3` steps the predicted slot → `A` commits; keyboard identical | **RIGHT** | — |
| M-7 | …but when the list also declares `onActivate` | `grabOnActivate` flips to false; `A` fires `onActivate` and arms nothing. Reorder then requires the author to bind `toggleGrab` to a key | **AUTHORED-ONLY** | med |
| M-8 | public `UI.draggable` / `UI.dropTarget`, pointer + touch | mouse drag and touch drag both commit a drop at every combo | **RIGHT** | — |
| M-9 | public `UI.draggable`, **gamepad / keyboard** | **no default non-pointer route.** With the card focused, `ButtonA` → arms nothing; `Return` → arms nothing; a tap → arms nothing. The machinery is entirely present and works when called: `reg.arm()`, `reg.armTo()`, `reg.commit()` → `kind=dropped`. It is simply never bound — `grep` finds no caller of `registry.arm` anywhere in `src/present/` | **AUTHORED-ONLY** | **high** |

### ADAPT-16 · The public drag verb is built, tested, and bound to nothing on pad or keyboard

**Severity: high. Confidence: high.** `drag_registry.luau:12` states the intent — "the
non-pointer arm→navigate→commit verbs all funnel into `beginSession`" — and every piece of
that path is proven working when invoked directly. The presenter only ever calls `armTo`,
to follow focus for an **already-armed** session, and nothing arms. `renderer.luau:471-475`
excludes action-source activates on purpose, reasoning that they "belong to the consumer's
`onActivate` — the armed paradigm already owns them". **But nothing else owns them, so
today they own nothing.** `virtual_list.luau:2555` already implements the right default rule
for its own rows (`grabOnActivate = reorderable and onActivate == nil` — "a source with no
consumer Activate arms on Activate"); hoisting that same rule to the public verb is the fix.

## Family B · Card sets — the director's own example

What the framework ships for "a set of cards": `UI.Grid`, `UI.GridRow`,
`Controls.VirtualGrid`, `Controls.VirtualList{axis="x"}`, `UI.ScrollView{axis}`,
`UI.containerRelativeFrame`, `UI.AdaptiveStack`, `UI.ViewThatFits`, `UI.Composition`, and
the pure helpers. **There is no `Card`, `Rail` or `Carousel` primitive** — defensibly, since
a card is composition rather than a control.

| # | cell | measured today | expected | verdict | sev |
|---|---|---|---|---|---|
| B-1 | `UI.Grid` default lanes | 6 cards → **6 lines of 1 at every one of the six combos**, 390 through 1920. Confirmed verbatim at `grid.luau:173-181`: `gridLaneCount` returns `1` when neither `columns` nor `minColumnWidth` is declared | 1-up on compact, multi-up on regular/wide | **WRONG** — a 1600px screen paints one 60px card per row | high |
| B-2 | `UI.Grid{ minColumnWidth = 160 }` | 1→2 cols · 2→5 · 3→6 · 4→6 · 5→6 · 6→6, matching `adaptive.columnsFor` exactly | adapts with width | **RIGHT but AUTHORED-ONLY** | — |
| B-3 | `columnsFor` at ten-foot | `columnsFor(1920,160,8) = 11` vs desktop `= 9` — **the TV gets MORE columns than the desktop**, while `sizeClass` and `heightClass` both cap ten-foot density (`adaptive.luau:84-110`) | a TV at 3m must be the *least* dense arrangement — the module's own stated rule | **WRONG** — density capped on the two functions that describe, uncapped on the one that decides | high |
| B-4 | `VirtualGrid` lanes | `columns` is **required** (construction error); `minColumnWidth` refused *with a route* | a lazy grid adapts its lanes | **AUTHORED-ONLY** (documented, routed, deliberate) | med |
| B-5 | rail, recommended shape `VirtualList{axis="x"}` | scroll region `axis=x` at every combo; **DPadRight steps c1→c4, DPadDown does nothing**; keep-visible scrolls (sx 0→834→2066→3298) | scrolls by touch, steps by pad | **RIGHT** | — |
| B-6 | rail, naive shape `ScrollView{axis="x"}` | **DPadRight moves nothing; DPadDown steps the cards** — a horizontal rail navigates vertically on a pad. `focus_map.luau:640-668` `isHorizontalRun` matches `HStack` and `AdaptiveStack{axis="x"}` only; `ScrollView{axis="x"}` is not in the predicate | scroll axis and focus axis agree | **WRONG** — the exact defect class the D5 round fixed, one predicate short | high |
| B-7 | **paging / snapping** | park the rail mid-card (x=77, pitch 140), settle 30 frames → **x stays 77**. No `snap`/`paging`/`scrollTarget` symbol anywhere in `src/` | a compact card set pages one view at a time | **MISSING** — no route at all, not even authored | **highest** |
| B-8 | page sizing | `containerRelativeFrame` gives card width == host width at every combo; arithmetic matches the reference verbatim | one-view-at-a-time sizing | **RIGHT, AUTHORED-ONLY** — and inert for a carousel without B-7 | — |
| B-9 | page-dot indicators | no symbol anywhere. The only carousel affordance shipped is the negative one: `indicators = "none"` for "a peeking carousel whose affordance IS the half-visible next tile" | — | **MISSING**, follows B-7 | med |
| B-10 | scroll-indicator policy | pointer → `"always"`, else `"auto"`, derived from the live interaction class with no author involvement | desktop persistent bar, touch/pad flash | **RIGHT** | — |
| B-11 | ten-foot overscan margin | cards land at x=90,y=60 on ten-foot and x=0,y=0 elsewhere — applied by default | a TV never renders edge-flush | **RIGHT** | — |
| B-12 | keyboard **Tab** across a rail | Tab moves nothing by default; arrows do work. Off until asked for, by director playtest ruling 2026-08-03 — "the keys it claims are the ones an avatar is already using" | Tab traverses on desktop | **AUTHORED-ONLY, deliberate** — a ruled trade-off for a game framework | low |

**The director's question, answered directly.** *Do cards present as a swipeable single-view
carousel on a phone but a multi-up grid/rail on medium and large screens?* **No, on both
halves.** By default a card set is **one column at every one of the six combos** (B-1); the
compact carousel does not exist even as an authored route, because nothing snaps (B-7); and
every size-responsive lane count is something the author must write (B-2/B-4) — with the
documented route producing a *denser* grid on a television than on a desktop (B-3).

**Reference-platform calibration, stated honestly.** The reference platform does not
auto-adapt card sets either: `GridItem(.adaptive(minimum:))` is an authored declaration, and
carousel paging needs an authored `.scrollTargetBehavior(.paging)` / `PageTabViewStyle`. So
"carousel on phone, grid on tablet" is authored *there* too, and B-2/B-4 are not a parity
gap. Two things are still genuinely worse here: **B-1**, where the reference's default flow
is not one-column-forever, and **B-7**, where the reference ships the landing behaviour and
Facet has no route at all. B-7 is the one that fails the director's example outright.

## Family J · Tables

**Locating DIR-4:** it is *not* a priority-collapse. `task-dir-brief.md:3` — "DIR-4 (table
clamp) … already landed in the previous wave" — is the clamp of user-committed **resize
overrides** (`table_columns.luau`, `table.luau:1184-1232`). Measured in J-8 below.

| # | cell | measured today | expected | verdict | sev |
|---|---|---|---|---|---|
| J-1 | column collapse by priority at compact | **Does not exist.** The column boundary's closed key set (`table.luau:257-269`) has no `priority`, no `visibility`, no `collapse`. At 390px **all five columns stay mounted** and divide the width. (`disclose` is a *text* disclosure, not a column verb — do not conflate them.) | at compact, low-priority columns drop and their values move to a secondary line — the reference platform "hides headers and collapses all columns after the first" **by default** | **MISSING** (no API at all) | **highest** |
| J-2 | does a `fill` column honour `minWidth`? | **No.** At 390px a `minWidth = 120` column resolves to **73px** and a `minWidth = 100` column to **37px**, and the cell text is `truncated = true`. Confirmed verbatim: `resolveDim` (`table.luau:1203-1216`) applies `minWidth` only to an *override* and to a *percent* dim; a `fill` dim is `return dim`, untouched | a declared column floor is a floor | **WRONG** — silently dropped on the one dim kind a responsive table uses most | **highest** |
| J-3 | wide all-fixed (720px) table at compact | body rect 390, scroll region **`axis=y` only**, `rating` cell right edge at **720** against a 390 window — it clips. The framework files the right diagnostic twice ("content overflows this hstack by 330px … wrap it in a ScrollView") — advice the control cannot take about its own header | collapse by priority, or a horizontal scroller as the honest fallback | **WRONG** | high |
| J-4 | truncation recovery per input | hover on 4,6 · long-press on 1,2,3 · **pad/keyboard: none**. The focus route is structurally dead for a Table: `disclosureTargetIn` walks the subtree of the *focused* node, but Table's focusable is `Row/Hit` while the disclosed text is `Row/Cells/Cell-name/Value` — a **sibling**. Positive control passes (a `disclose` Text inside a focused Button raises the plate); the identical declaration in a table row raises nothing. Same for the header title | the framework's own stated debt: "when it ellipsizes the framework owes the reader the whole value" | **WRONG** — and it is the **only** recovery route at the ten-foot combo | **highest** |
| J-5 | row activation per input | with `onPrimaryAction`: touch-tap ✓ · mouse-1click ✗ (correct) · mouse-2click ✓ · Return ✓ · pad-A ✓ — at **every one of the six combos** | tap / double-click / Return / A, no invented gesture | **RIGHT — the strongest result in this audit** | — |
| J-6 | per-row detail route on compact | the verb is bound on every input, but there is no list-detail primitive (`NavigationSplitView` recorded Missing). A screen wanting list-on-compact / list+detail-on-wide hand-writes the branch | compact pushes a detail; regular/wide is two-column | **AUTHORED-ONLY** for the verb (RIGHT), **MISSING** for the arrangement | high |
| J-7 | default row height per input | 44 on touch/hybrid, 36 on pointer, **36 on ten-foot** (no gamepad rung — see ADAPT-10) | taller under touch, floor honoured | **RIGHT** for touch/pointer; ten-foot covered by ADAPT-10 | — |
| J-8 | DIR-4 override clamp | commit 297/168 at 844 → rotate to 390 → clamps to 182/111/96 (sum 389 ≤ 390), proportional above each floor → rotate back → **exactly 297/168**. The model never moves; only the resolution clamps | a commitment is not a guarantee of space | **RIGHT** | — |
| J-9 | can focus reach a clipped column? | `Header` has **no scroll region**, and 4× DPadRight lands focus on a column at **x=640…720 on a 390px viewport** — 250px off-screen, `focusVisible = true`, with nothing able to scroll it into view | focus never lands where the player cannot see | **WRONG** — falls out of J-1/J-3, no separate fix wanted | high |

## Family G · Transient surfaces (menu / callout / sheet / tooltip)

Probed with the same `newMenu`, 3 items, twice per combo — once default-authored, once
with env facts wired:

| combo | sizeClass | primary | DEFAULT (no facts) | WIRED (env facts) |
|---|---|---|---|---|
| compact touch portrait | compact | touch | `menu` | `sheet` |
| compact touch landscape | regular | touch | `menu` | `sheet` |
| regular touch tablet | wide | touch | `menu` | `sheet` |
| desktop pointer | wide | pointer | `menu` | `menu` |
| ten-foot gamepad | regular | gamepad | `menu` | `menu` |
| hybrid pointer+touch | wide | pointer | `menu` | **`sheet`** ← wrong (see ADAPT-9) |

Measured cost on a 390×844 touch phone:

```
wire=false  presentation=menu    panel x8 y52 125x110    row 125x36
wire=true   presentation=sheet   panel x0 y658 390x186   row 374x56
```

…and the default plate's rows have **overlapping engine hit rects** — rows at y=52/89/126
with h=36 get 44px expanders at y=48/85/122, a 7px overlap between adjacent rows.

| cell | measured | expected | verdict | sev |
|---|---|---|---|---|
| menu on compact touch | 125×110 floating plate, 36px rows | full-width bottom sheet, 56px rows | **AUTHORED-ONLY** | critical |
| menu on desktop pointer | anchored plate | anchored plate | **RIGHT** | — |
| menu on ten-foot | anchored plate, focus lands on row 1 | acceptable placement; rows should ride the ten-foot ladder | RIGHT (placement); see density | — |
| a general modal becoming a sheet on compact | **no such thing** — `presentModal` has no size-driven form and there is no `UI.Sheet`/`newSheet` in the public API. (`presentation_channel.luau`'s "sheet" is the Roblox StyleSheet, a different noun.) | the reference platform adapts a popover to a sheet on compact **by default** | **MISSING** | high |
| Callout on every combo | universal anchored plate + tail; no size/input branch exists in `callout.luau` at all | the reference platform's coach-mark is a plate on every platform | **RIGHT** | low |
| Callout on gamepad | pad B does **not** retire it; one `DPadDown` lands the ring on its Dismiss, A retires it | non-modal chrome must not steal Cancel from the screen beneath | **RIGHT** — matches `callout.luau:47-51` verbatim | — |
| menu focus trap on gamepad | 6 `DPadDown` presses never escape to a sibling; `escaped=false` on all 12 rows | trapped | **RIGHT** | — |
| pad B dismiss + focus restore | `open=false`, focus restored to the trigger on all 12 rows | B closes, focus returns | **RIGHT** | — |
| tooltip (`help`) on pointer | hover dwell 0.45s → plate | hover after dwell | **RIGHT** | — |
| tooltip on gamepad/keyboard | focus route, no dwell | focus route | **RIGHT** | — |
| tooltip on touch | nothing appears | nothing, by parity with the reference | **MISSING BY EXPLICIT RULING** — documented at `help_plate.luau:11-32`, and `text_audit.helpRoutes` mechanically refuses a `help` string that is the only route | low |

### ADAPT-9 · The hybrid rule contradicts the environment's own ruling

**Severity: medium (latent — bites only once the sheet path is wired). Confidence: high.**
`menu_recipe.luau:90` gates on `classes.touch`, not `classes.primary`. So a pointer-primary
hybrid — a touchscreen laptop with a mouse — resolves to a **sheet**, directly contradicting
`environment.luau:515-521`: "A mouse still wins outright, which keeps every desktop and every
hybrid (touchscreen laptop) exactly where it was." **Fix with ADAPT-1, not separately:** gate
on `primary == "touch"`.

## Family H · Hover-dependent affordances — the exhaustive list

The hover surface is genuinely small and this is **the strongest area of the framework**.
`HOVERABLE` is exactly two classes (`renderer.luau:123`: `{ Button, Toggle }`), and all
wiring is gated on `interactionClasses.pointer`, with a hot-switch re-wire at
`renderer.luau:3060-3074`.

| # | hover affordance | touch route by default | gamepad route by default | verdict |
|---|---|---|---|---|
| 1 | Button hover fill | n/a — decoration only; activation is class-agnostic | n/a — the focus ring is the pad's equivalent | RIGHT |
| 2 | Toggle hover fill | same | same | RIGHT |
| 3 | Primary/accent button hover | decoration | decoration | RIGHT |
| 4 | Destructive button hover | decoration | decoration | RIGHT |
| 5 | Theme-package chrome art `hover` variant | decoration; the validator forbids a differing reservation so it can never relayout | decoration | RIGHT |
| 6 | Icon art `hover` variant | decoration | decoration | RIGHT |
| 7 | Toggle knob hover | decoration | decoration | RIGHT |
| 8 | **Full-value disclosure plate** (truncated `disclose` text) | **YES — long-press**, deliberately kept: "the ONLY touch route to a truncated label's full value … deleting the binding would have been an accessibility regression" | **YES — focus enter** | **RIGHT — all three classes** |
| 9 | `help` tooltip plate | **NO — by ruling** | YES — focus | MISSING BY RULING |
| 10 | `UI.Text{ reveal = "auto" }` marquee | automatic; its static alternative is #8, reachable by long-press | automatic + #8 by focus | RIGHT |
| 11 | Semantic cursor hint (`colResize` on the Table resize grip) | n/a (no cursor on touch); the grip is still a draggable zone | **YES** — Adjust on the focused header; the grip is deliberately `focusable = false` | RIGHT for reachability — but `CURSOR_ART` is **empty by default** ("No first-party cursor set exists"), so the resize edge has no visual affordance on any input class |
| 12 | Drag/drop hover (drop target, enter/leave, predicted verdict) | **YES** — tap-to-pick-up ("a TAP on this source IS the pickup … works one-thumbed on mobile") | **YES** — activate / keyboard-pad pickup, promotion gate 0 | RIGHT |
| 13 | Reorder hover (armed landing slot in VirtualList) | rides #12 | rides #12 (grab-mode intercept) | RIGHT |

**Net: no hover-only affordance without a touch/pad route exists**, other than `help`,
which is a documented ruling with a mechanical guard rather than an oversight.

## Family I · Density, spacing and hit targets

Every metric is identical on all six combos **except the four marked** `*`.

| metric | compact touch ptr | compact touch lsc | regular touch tablet | desktop pointer | ten-foot gamepad | hybrid |
|---|---|---|---|---|---|---|
| `targetSizes.minimum` | 44 | 44 | 44 | 44 | **44** | 44 |
| controlSizes compact/regular/large | 36/44/56 | = | = | = | **= (unchanged)** | = |
| `*` Table row (paradigm) | 44 touch | 44 | 44 | 36 pointer | **36 pointer** | 44 touch |
| space xs/s/m/l/xl/gutter | 4/8/16/24/40/8 | = | = | = | **= (unchanged)** | = |
| `*` typographyScale / paintScale | 1 / 1 | = | = | = | **1.5 / 1.5** | = |
| icons small/med/large | 16/20/24 | = | = | = | **= (unchanged)** | = |
| `*` overscan insets | 0 | 0 | 0 | 0 | **t60 b60 l90 r90** | 0 |
| `*` scrollIndicatorPolicy | auto | auto | auto | **always** | auto | **always** |

Hit-rect enforcement, measured on a deliberately 20×20 Button and a 28px Toggle:
`Tiny rect=20x20 hit=44x44 | Tog rect=Wx28 hit=Wx44` — identical on every combo, via
`class_contract.luau:128-167` × `layout_node.luau:183-186`.

### ADAPT-7 · The ten-foot type floor does not reach unauthored text · **TOP FINDING**

**Severity: critical. Confidence: high.** Measured at `displaySize = Large`, 1920×1080:

| declaration | painted size |
|---|---|
| `UI.Text{ text }` (no `textSize`) | **16px** |
| `UI.Text{ textSize = "body" }` | 24px |
| `UI.Button{ label }` | **18px**, h=46 |
| `UI.Button{ textSize = "control" }` | 27px, h=57 |
| `UI.Toggle{ label }` | **16px**, h=28 |

Cause, confirmed verbatim at `renderer.luau:1472`:

```luau
local scaled = if authored then raw * scale else raw
```

matched at measure by `layout_node.luau:222-226`, whose comment states the asymmetry as
intentional: *"an INTRINSIC size never reaches paint scaled, so it is reserved at scale 1."*

**The honest framing matters here.** This is not a sloppy bug — the seam is deliberate,
self-documented, and internally consistent: measure and paint agree, so nothing overflows
and nothing clips. **That consistency is precisely why it is invisible**, and why it
survived. But the consequence appears unintended: the framework's own ten-foot acceptance
row D.1 ("body text must clear ~29pt at 3m", `snapshot.luau:267-271`) is unmet for every
screen written the natural way, and the shipped ten-foot spec only ever asserts an
*explicitly sized* node (`paradigm_tenfoot.spec.luau:61-73` uses `textSize = 16`), so the
suite cannot see it. A game that writes `UI.Button{ label = "Play" }` — the way the
tutorials write it — ships near-distance type to a television.

**Why the suite cannot see it, verified.** `tests/paradigm_tenfoot.spec.luau`
UI-PARADIGM-003 is the ten-foot type row, and both of its cases declare
`UI.Text({ id = "T", text = "Race", textSize = 16 })` — an **authored** size, asserting
16 → 24. There is no case anywhere that omits `textSize`. The spec tests the one branch
that works.

**The smallest proof, red-first.** Add one case to that describe block with no `textSize`
at `displaySize = "Large"` and assert the scaled size. It reddens at the anchor. That
single case is a better gate than any amount of prose, and it is the mutation that proves
any fix actually bites.

**Smallest fix:** scale the intrinsic size at **both** seams together (`renderer.luau:1472`
and `layout_node.luau:222-226`), never one alone — measure/paint agreement is the property
that must survive the fix, and it is the reason the current asymmetry is silent rather than
merely wrong.

### ADAPT-8 · The ten-foot ladder is only type, overscan and the focus ring — a scope question, not a defect

**Severity: medium. Confidence: high. Deliberately downgraded from the measurement seat's
"high" after reading the design intent, and flagged as a DIRECTOR CALL rather than a fix.**

The measurement is not in doubt: `snapshot.resolve:726` sets
`out.density = if displaySize == "Large" then "ten-foot" else "near"` and the value is, in
its own words, *"recorded, never re-applied"*. Control heights, spacing, icon sizes and the
44px hit floor on a television are byte-identical to a phone's.

**But this is a scoped policy, not an oversight, and the audit should say so.** The
framework's ten-foot policy is four named rows and metric spacing was never one of them:
D.1 the **type** floor (`tenFootFloor = 1.5`, "body text must clear ~29pt at 3m",
`snapshot.luau:265-271`), D.3 the **sizeClass density cap** (`adaptive.luau:82-110`), D.4
**focus strengthening** (ring 2→4px + 1.05 scale), plus the overscan insets. There is no
acceptance row claiming spacing, control heights or hit targets scale at distance, so
measuring their absence as a defect would be inventing a requirement.

What is genuinely open is whether four rows are *enough* at 3 metres — and that is a
human-factors judgement a headless probe cannot make. It belongs on the batched device
pass, not in a fix queue.

One real compounding hazard worth fixing regardless: the env default
`themeMetrics = themeSnapshot.neutral()` (`environment.luau:136`) resolves with
`facts = {}`, so `density` reads `"near"` **even on the Large combo** unless the caller
re-resolves with the live fact — the same author-must-wire-it shape as ADAPT-1.

### ADAPT-10 · Gamepad has no rung in the density ladder — the TV gets the densest row

**Severity: high. Confidence: high.** `table.luau:470` asks `if classes.touch then "touch"
else "pointer"`, and a gamepad is neither — so the ten-foot combo resolves `paradigm =
pointer` and gets the **36px** row, the densest one, at 3 metres. `snapshot.luau:686-692`
publishes exactly two keys, `pointer` and `touch`. **Fix:** add a gamepad/ten-foot rung and
select on `distanceProfile`, not on `classes.touch` alone.

### ADAPT-11 · Table density is caller-wired, and the default is below the touch floor

**Severity: high. Confidence: high.** Probed: Table row height **defaults to 36px on every
combo, including compact touch portrait**, because `table.luau:499-503` returns
`rowBoxFor(nil, …)` when `spec.env` is absent, which makes `classes` nil and the paradigm
`pointer`. The engine hit rect is still expanded to 44, so the tap survives — but adjacent
44px expanders then **overlap on a 38px pitch**, the same class of defect measured in the
menu plate above. Wired, it is correct: 44 on touch combos, 36 on pointer/pad.

### ADAPT-12 · The universal 44px floor is right for touch and unexamined elsewhere

**Severity: low. Confidence: high.** `targetSizes.minimum` is a theme constant
(`default_style.luau:104`, floored at `package.MIN_TARGET_SIZE = 44`) and is never keyed on
input class or distance. That is **RIGHT and well-enforced for touch** — the strongest
single guarantee in this family. It is, however, the same 44 for a precise mouse (where a
denser ladder is legitimate) and the same 44 on a television (where it is too small).
Both are consequences of the metric ladder having no per-class dimension at all — the same
root as ADAPT-8. Not worth a separate fix; fix it with ADAPT-8.

## Family F · Disclosure / reveal

Per the brief this row **cites the approved spec as the expected contract rather than
measuring it**: `.superpowers/sdd/release-candidate-review/task-reveal-brief.md`
(director-approved 2026-08-18, Option A with two constraints), landing after this anchor.

**Measured at the anchor:** no `activeForm`, no `richestForm`, no `formInteractive`, no
region-level `reveal` anywhere in `src` (grep: zero hits). What exists is the D7.1
**recovery contract** (`composition.luau:487-517`): a multi-form region *must* declare
`recover = "none" | "self" | "overflow"`, and construction fails without it
(`composition.luau:836-841`) because "silence is not consent". That is a correctly
*refusing* authored declaration — good hygiene — but it is not a default.

Measured corpus: **22** `recover` declarations in `examples/` — 13 `overflow`, 6
`none`, and exactly **1** real `self` (`hud.luau:2529`; the other two grep hits are
comments). So the shipped answer to "adaptation hid something" is overwhelmingly *go
open the sheet*, which is precisely what the REVEAL wave replaces with in-place
expansion at the region's own anchor.

The framework has already measured its own dead ends: `composition.luau:490-493`
records **39 elided-or-dropped occurrences across nine viewports** on its own HUD
showcase, "every one of them a dead end"
(`artifacts/navigation-and-menus/d7-hud-baseline.md`).

The substrate the reveal needs is already there: losing forms are hidden, "which is
what takes them out of focus order" (`composition.luau:100-102`), so the brief's "stop
appears/disappears with form changes" rides existing machinery.

**Verdict at the anchor: AUTHORED-ONLY across all five combos**; the approved spec
makes it automatic. The per-combo rows to hold the wave to are the brief's own §3
(passive form = exactly one focus stop; interactive form = a chevron with its own 44px
band and its own stop *after* the form's stops), §2 (tap-away / Esc / pad B / focus
loss, plus clean dismissal on an epoch change), and §2's sizing fallback to the
full-width sheet when form 1 cannot meet its floor.

### ADAPT-6 · `reveal` is about to mean two different things

**Severity: medium (API hygiene). Confidence: high. Timely — the wave is landing now.**
At the anchor `reveal = "auto"` **already exists** as a `UI.Text` prop meaning "marquee
the truncated string" (`blueprint_schema.luau:1082-1098`, director ruling 2026-08-04).
The REVEAL wave introduces `reveal = "auto" | "none" | function` on a composition
*region*, meaning "present form 1 in an anchored overlay". Same key, same `"auto"`
literal, different construct, different mechanism — and both are described as
disclosure. `docs/reference/swiftui-parity.md` already has to disambiguate them in
prose. **Smallest fix:** rename one before the wave lands rather than after; the region
one is unshipped, so it is the cheap side to move.

---

# Part 3 — Verdict counts, findings, and what is not measurable headlessly

## Verdict counts

**Counting rule, stated so the number can be audited:** one *cell* is one default-paradigm
decision as tabulated in Part 2 — a row-family question resolved either across all six
combos (where the answer is combo-invariant, which it very often is) or per combo-group
(where it is not). Cells are the rows of the Part 2 tables plus the per-combo rows of the
navigation and disclosure families. Where a finding spans several combos it is counted once
per affected combo-group, not once per combo.

| verdict | cells | share |
|---|---|---|
| **RIGHT** | **58** | 51% |
| **MISSING** | **23** | 20% |
| **AUTHORED-ONLY** | **19** | 17% |
| **WRONG** | **14** | 12% |
| total | **114** | |

Per family:

| family | cells | RIGHT | WRONG | MISSING | AUTHORED-ONLY |
|---|---|---|---|---|---|
| Navigation (navPlacement) | 6 | 5 | 1 | — | — |
| Centered-placement alignment | 3 | — | 3 | — | — |
| Ten-foot specifics | 3 | 2 | 1 | — | — |
| Pickers & value controls | 9 | 3 | — | 3 | 3 |
| Text entry | 5 | 2 | — | 1 | 2 |
| Transient-surface dismissal | 4 | 1 | — | 3 | — |
| Editable collections | 5 | 4 | — | 1 | — |
| Selection | 9 | 5 | 1 | 3 | — |
| Drag interactions | 9 | 5 | — | 1 | 3 |
| Card sets | 12 | 3 | 3 | 2 | 4 |
| Tables | 9 | 3 | 4 | 2 | — |
| Transient surfaces | 11 | 8 | — | 2 | 1 |
| Hover-dependent affordances | 13 | 12 | — | 1 | — |
| Density / spacing / hit targets | 11 | 5 | 1 | 4 | 1 |
| Disclosure / reveal (at anchor) | 5 | — | — | — | 5 |
| **total** | **114** | **58** | **14** | **23** | **19** |

**How to read this.** A bare 51% RIGHT understates the framework in one direction and
overstates it in another. Understates: the *hardest* input problems are solved — the hover
family is 12/13 with the one gap being a documented ruling; row activation is bound
correctly on all four inputs at all six combos; column resize works on all four inputs at
all six combos; the swipe tray, the focus trap, pad-B dismissal and focus restoration are
all correct everywhere. Overstates: **32 of the 36 non-RIGHT cells are the same two shapes**
— either a correct adaptive rule that the author must hand facts to (AUTHORED-ONLY, 19), or
a paradigm with no route at all on some input class (MISSING, 23). Very little is *wrongly*
implemented; a great deal is implemented and not connected.

## Findings, ranked by severity

| id | finding | severity | confidence |
|---|---|---|---|
| **ADAPT-7** | The ten-foot type floor does not reach unauthored text: `UI.Text{text}` paints 16px on a TV where `UI.Text{textSize="body"}` paints 24px. Measure and paint agree, so it is silent, and the ten-foot spec only ever asserts an authored size | **critical** | high |
| **ADAPT-1** | Adaptation is a fact the author must hand to the control, and it fails silently. 0 of 17 picker call sites use the adaptive default; the touch→sheet rung never fires in any shipped app | **critical** | high |
| **ADAPT-17** | No scroll snapping exists anywhere in `src/` — the director's own carousel example cannot be built, even by an author | **critical** | high |
| **ADAPT-18** | No column collapse by priority exists; the column boundary has no `priority` key, and a wide table clips at compact with a `y`-only scroller | **critical** | high |
| **ADAPT-19** | A `fill` column's `minWidth` is silently dropped — a 120px floor resolves to 73px at 390 — which is what makes ADAPT-18 invisible rather than merely unhandled | **critical** | high |
| **ADAPT-13** | A Table declaring only `rowActions` has zero focus stops, so Delete and the action menu are dead on keyboard and gamepad — contradicting `api.md:4445`, and already fixed for VirtualList | high | high |
| **ADAPT-2** | The tablet column of every five-view gate has been measuring a phone: `DisplaySize.Small` covers tablets, so the documented tablet placement is unreachable on tablets | high | high |
| **ADAPT-4** | The three placements documented as *centered* are left-aligned; on a TV a 3-tab bar is a 193px cluster with 1547px of empty band beside it | high | high |
| **ADAPT-20** | Table truncation recovery is structurally unreachable on keyboard and gamepad: the focus walk starts at `Row/Hit` and the truncated text is a sibling. It is the only recovery route at ten-foot | high | high |
| **ADAPT-15** | Multi-selection is structurally unreachable on a gamepad — pad Activates carry keyboard-only modifiers, so every press replaces | high | high |
| **ADAPT-14** | Keyboard multi/range selection is destroyed by focus movement: `handleFocusMoved` replaces on every arrow press | high | high |
| **ADAPT-16** | The public drag verb has no default gamepad or keyboard pickup; the whole arm→navigate→commit path is built, proven, and bound to nothing | high | high |
| **ADAPT-21** | `newVirtualList` reorder has no touch route at all: touch drag is declined and no tap-arm or handle is mounted | high | high |
| **ADAPT-22** | `UI.Grid` defaults to one lane at every combo, 390 through 1920 — the most-reached-for card container has no size-responsive default | high | high |
| **ADAPT-23** | Ten-foot density is capped on `sizeClass`/`heightClass` but **not** on `columnsFor`, so the documented adaptive-grid route yields 11 columns on a TV against 9 on a desktop | high | high |
| **ADAPT-24** | `ScrollView{axis="x"}` navigates *vertically* on a pad — the exact defect class the D5 round fixed, one predicate short | high | high |
| **ADAPT-25** | No general sheet presentation exists: `presentModal` has no size-driven form and there is no `UI.Sheet` | high | high |
| **ADAPT-10** | Gamepad has no rung in the density ladder, so the ten-foot combo gets the *densest* 36px table row | high | high |
| **ADAPT-11** | Table density is caller-wired; the default is 36px on a touch phone, producing overlapping 44px hit expanders on a 38px pitch | high | high |
| **ADAPT-26** | No list-detail arrangement primitive, so compact-push / wide-two-column must be hand-branched | high | med |
| **ADAPT-5** | Ten-foot decisions run against the raw 1920 width; no TV-safe content width exists anywhere | medium | high |
| **ADAPT-6** | `reveal` is about to mean two different things — the `UI.Text` marquee prop and the new region reveal share the key and the `"auto"` literal | medium | high |
| **ADAPT-8** | The ten-foot ladder is only type, overscan and the focus ring — a scoped design decision, flagged as a **director call**, not a defect | medium | high |
| **ADAPT-9** | The hybrid rule gates on `classes.touch` not `classes.primary`, contradicting the environment's own mouse-wins ruling. Latent until ADAPT-1 is fixed | medium | high |
| **ADAPT-27** | Edit mode paints no selection affordance — no circle, no checkbox, only an invisible prop change | medium | high |
| **ADAPT-28** | Table reorder on keyboard-only, and VirtualList reorder on any list declaring `onActivate`, degrade from default to authored-only | medium | high |
| **ADAPT-29** | Sidebar has no collapse; every collapse key is rejected by the closed spec | medium | high |
| **ADAPT-12** | The universal 44px floor is right and well-enforced for touch, and unexamined for pointer and distance. Fix with ADAPT-8 | low | high |
| **ADAPT-30** | `bottomBarCompact` is byte-identical to `bottomBar` (46px, full labels) though the docs promise a tighter band — ship the metric or correct the doc | low | high |
| **ADAPT-3** | *Positive:* hybrid is fully correct and live-flipping — the pattern the other columns should copy | — | high |

**Where each finding's evidence lives in Part 2.** ADAPT-1 → Part 1 · ADAPT-2, 3, 4 →
Family A · ADAPT-5 → Family N · ADAPT-6 → Family F · ADAPT-7, 8, 10, 11, 12 →
Family I · ADAPT-9, 25 → Family G · ADAPT-13 → Family K (K-2) · ADAPT-14, 15, 27 → Family L
(L-6, L-7, L-5) · ADAPT-16, 21, 28 → Family M (M-9, M-5, M-4/M-7) · ADAPT-17, 22, 23, 24 →
Family B cards (B-7, B-1, B-3, B-6) · ADAPT-18, 19, 20, 26 → Family J (J-1, J-2, J-4, J-6) ·
ADAPT-29, 30 → Family E.

## The one systemic recommendation

Nineteen AUTHORED-ONLY cells and several MISSING ones share a single root, and the framework
already contains its own fix. `tab_view.luau:345-351` **refuses to construct** when its
adaptive fact is absent, with an error naming the remedy. `picker`, `popup_button`, `menu`,
`level_picker`, `text_input` and `table` all silently substitute the large-screen /
pointer answer instead. Making those six match TabView — either by defaulting the facts from
the presenter's env, or by refusing loudly — converts a large block of this matrix in one
change, and would have caught ADAPT-1, ADAPT-11, ADAPT-9 and the picker/menu rows at
construction time rather than in an audit. There is no environment *contribution* seam today
(`bindEnv` in `client/host.luau:78` is a host-level test seam, not a per-control channel), so
this is a new sibling seam alongside the ten that already exist.

## Not measurable headlessly — for the batched Studio/device pass

| # | claim | the exact step that settles it |
|---|---|---|
| 1 | Whether 24px body text and 36px rows are legible at 3m, and whether four ten-foot rows (type, overscan, focus, density-cap) are *enough* — the ADAPT-8 director call | Console/TV or `ViewportDisplaySize = Large` session, `screen_capture` viewed at equivalent angular size, director sign-off |
| 2 | Whether the left-aligned bars (ADAPT-4) read as broken to the eye at ten-foot distance | Ten-foot matrix row at 1920×1080, gamepad preferredInput, **zoomed** capture of the top band |
| 3 | Whether the `:Hover` sheet rules actually match on a real device | Studio Play, hover a Button, `GetStyled("BackgroundColor3")` vs `$ControlHover` — a plain property read reports the *unstyled* value, so `GetStyled` is the only valid instrument |
| 4 | Whether touch long-press actually reaches the disclosure plate through the engine gesture path | Touch-emulated viewport, hold ≥0.5s on a truncated `disclose` label, confirm the plate mounts |
| 5 | Whether the console virtual keyboard appears when `editing` drives `CaptureFocus` on a pad | Physical console/handheld capture, or `execute_luau` on `UserInputService.OnScreenKeyboardVisible` — `screen_capture` cannot see CoreGui |
| 6 | Whether `keyboardOcclusionRect` is populated on a real device (its writer's guard was only fixed 2026-08-17) | Live mobile session: focus a field, read the engine keyboard rect and the env fact, confirm the surface transform |
| 7 | Whether ten-foot overscan (x=90, y=60) matches a real TV's title-safe area | Console/TV run, capture the top band, measure against the physical bezel |
| 8 | Whether a real `UIDragDetector` honours `declineTouch` as the fake target does | Touch-emulated viewport, drag a VirtualList row body vertically; confirm the scroll pans and no reorder starts |
| 9 | Whether gamepad `ButtonX` survives CoreGui / legacy CAS arbitration (CAS priority and `InputContext.Priority` are *not one arbitration space*) | Physical pad in a published place, or Studio Play with the camera script live |
| 10 | Touch-target size of the edit-mode ≡ (`HANDLE_GUTTER = 32`) and the row-actions ⊖ (28px) — both under 44 before expansion | `inspect_instance` the mounted handle in Play, reading the **expanded hit rect**, not the solved rect |
| 11 | Whether a fling on a real rail settles as paging anyway (engine momentum may mask ADAPT-17) | Device: `card_rail.luau` on a phone, fling and release, record settle position across 10 trials |
| 12 | Whether a truncated cell shows an ellipsis or a hard clip at 57–84px, and whether clipped columns are genuinely invisible | Studio at 390: capture the compact table, zoom the name column; `inspect_instance` the row `Cells` `AbsoluteSize` vs the body window |
| 13 | Whether `Shift+Return` preempts the base Activate context on a real client (two `InputBinding`s with `PrimaryModifier`) | Studio Play, hold LeftShift then Return on a focused row; assert the menu opens and plain Return still activates |
| 14 | Whether a real desktop client ever emits the keyboard-only capability shape ADAPT-28 depends on | `execute_luau` read of `UserInputService.KeyboardEnabled/MouseEnabled/TouchEnabled` vs `env:get("interactionClasses")` |
| 15 | Whether selection paint is legible at ten-foot under each theme package (I measured the `selected` prop, not paint) | Five-view matrix with `selection = "multi"`, two rows selected, per package |
| 16 | Whether the auto Edit/Done toggle and the ⊖ read as discoverable to players, and whether Tab-less desktop rails confuse them | Director playtest — the same instrument as the 2026-08-03 ruling that set the Tab default |

## Method and provenance

Measured from a private `git archive` export of `d6c5b3c4`; suite re-run there at **6467
passed**. Instruments: `tests/lib/world.luau` headless mounts at the six combos,
`tests/lib/device_views.luau` for the canonical viewport set, the pure `adaptive.*`
functions, the gallery and reference fixtures, and a scripted brace-matched scan of every
adaptive-control call site in `examples/`. Four measurement seats ran in parallel on
independent exports; every finding ranked high or above in this document was
**re-verified by this seat against source** before being recorded, and two were corrected in
the process — one seat's "no env seam exists anywhere" (a host-level `bindEnv` does exist,
though it is not a control channel) and one seat's severity on ADAPT-8 (a scoped design
decision reported as a defect). Reference-platform comparisons are cited inside this
artifact only; every recommendation above is expressed in Facet/Roblox terms.
