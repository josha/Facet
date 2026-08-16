# O-31 — the post-`present` call that is now no call at all

**2026-08-15.** O-30's census found that a virtualised collection renders the
WRONG ROWS when the consumer forgets `bindNativeScroll`, and says nothing. The
gallery half was fixed there. This is the API half.

Everything below is a transcript of something run for this file. The live halves
were driven in Studio (`LuauUI-Showcase.rbxl`, Rojo-connected, port 34873) on
2026-08-15; the headless halves in a pristine `git worktree` at HEAD `b377fe9`
carrying exactly the hunks these commits carry.

---

## Part 1 — the seam the ledger proposed does not reach, and that is measured

O-31's own text names the fix:

> `buildFocusGroups(rootNode)` is already the one seam that hands a control its
> own mounted path … delivering the controller through the same call would retire
> `bindNativeScroll` as a requirement.

**It is not the one seam, and it does not reach.** The presenter calls a
contribution's `focusGroups` only from `focus_map.autoGroups`, and `autoGroups`
runs only when the consumer left `opts.navigationGroups` ABSENT
(`presenter.luau`: *an explicit array/function wins; `false` forces the flat
ring*). One control, four presenter configurations, counted:

```
navigationGroups ABSENT     focusGroups=2  syncGeometry=3 (node.path=/S/VG)  bindController=1   bindNativeScroll(no path) -> OK
navigationGroups = false    focusGroups=0  syncGeometry=3 (node.path=/S/VG)  bindController=1   bindNativeScroll(no path) -> REFUSED
navigationGroups = <array>  focusGroups=0  syncGeometry=3 (node.path=/S/VG)  bindController=1   bindNativeScroll(no path) -> REFUSED
navigationGroups = <fn>     focusGroups=0  syncGeometry=3 (node.path=/S/VG)  bindController=1   bindNativeScroll(no path) -> REFUSED
```

The last column is a **second, unrecorded defect this probe found**: with
`focusGroups` never called the control never learns its mounted path at all, so
today — before this fix — a consumer who declares a focus map cannot even call
`bindNativeScroll(controller)`. It refuses outright. The ledger's proposal would
have fixed the default screen and left that consumer exactly as broken.

The two seams that DO reach are unconditional for every discovered contribution:
`bindController(controller)` (once, at present and on a structural sync) and
`syncGeometry(rectOf, node)` (every refresh AND every solve, carrying the
control's own mounted node). Together they are precisely what the post-`present`
call was being asked for by hand.

### The counterfactual, run rather than argued (mutation M8b)

The strongest form of the claim is to build the ledger's fix and watch it fail.
M8b moves the mount notice off `syncGeometry` and onto `buildFocusGroups` in all
three controls — with `mirror` forward-declared so the experiment measures the
SEAM and not the mutation's own declaration order (the first attempt, M8, did
not, and its 659 reds are recorded as an artefact of my mutation, not a finding).

```
M8b — the fix built on buildFocusGroups          2 failed, 5606 passed
  ✗ ...and it still does when the CONSUMER declares navigationGroups
  ✗ ...and when navigationGroups is a FUNCTION, and when it is `false`
```

Two reds, and they are exactly the two discriminator cases. Everything else
passes. That is what "the seam does not reach" looks like when it is run.

## Part 2 — what shipped

`src/controls/native_scroll_binding.luau` (new) holds the arbitration all three
hosts share; `install` — the only part that differs — is passed in. Each control
adds two lines to its contribution bundle: `bindController -> noticeController`
and the mounted node from `syncGeometry -> noticeMount`.

**`src/present/` was NOT touched, and that is the headline.** The presenter
already delivers both facts to every contribution in every configuration; the
mission's named scope assumed a presenter change would be needed and none was.

Three rules the arbitration holds, each mutation-proved below:

- **Identity, not path, is the mount key.** The node table handed to
  `syncGeometry` is stable across plain refreshes and FRESH after a remount —
  measured, including a remount back to the SAME path, which a path comparison
  cannot see. That is what makes the mirror self-healing across a `UI.When` flip;
  RascalRally hand-rolls the path comparison and its own comment says the bind
  "would go stale across a pose flip".
- **An explicit unbind sticks.** `noticeMount` re-asserts only when the mount
  changes, never per frame, so `unbindNativeScroll()` is not a one-frame
  suggestion.
- **`bindNativeScroll` is idempotent.** The (controller, path) already mirroring
  hands back the same stop function. This is the entire compatibility story for
  every existing caller, RascalRally included.

### All three controls, and the unified table path

`newVirtualHGrid` is `newVirtualGrid{ axis = "x" }` on the same arithmetic, so
the brief's "three controls" are two modules plus Table. The horizontal axis is
not a free rider: mutation M7 hard-codes `pos.y` in the grid's mirror and the
`LazyHGrid` case reddens while every vertical case stays green.

### The opt-out: one general mechanism, and it already existed

There is **no new opt-out key**. The only collection whose scrolling is genuinely
owned elsewhere is a `newTable{ scrolls = false }` block table, and it already
publishes that fact as `api.scrollPath() == nil` (ruling 3, O-10). The automatic
path reads the same function a consumer would: it mirrors nothing and still binds
the row-actions tray-close to the real scrolling ancestor. A
`newVirtualList`/`newVirtualGrid` always mounts its own `ScrollView` and has no
such state to be in, so inventing a spec key for them would have been a
mechanism with no state to describe.

## Part 3 — live, on the real engine, with no consumer call

Driven as a **parallel real-engine mount** (`require(RS.LuauUI)` + a real
`screen_target.new({})` + the control's own constructor), never through the demo
picker. A bare `screen_target` carries **no stylesheet**, so nothing here is a
paint claim — every number is geometry or an instance name.

Freshness gated on a marker that DISCRIMINATES: `controls/native_scroll_binding`
does not exist at HEAD, and `mirror.noticeMount` appears in no committed source.

```
native_scroll_binding  present=true  bytes=6783   hasMarker=true
virtual_grid           present=true  bytes=48159  hasMarker=true
virtual_list           present=true  bytes=179348 hasMarker=true
table                  present=true  bytes=190240 hasMarker=true
```

**The A/B, in one call.** B is the shipped tree. A is a CLONE of the whole
`ReplicatedStorage.LuauUI` with ONE line removed from `controls/virtual_grid` —
the mount notice — required as a separate tree (`require` is keyed on the
ModuleScript instance, so the clone is a genuine second load). The window is read
off ENGINE INSTANCE NAMES (`…/[cN]/Cell/Hit`), so nothing in the measurement goes
through the framework's own bookkeeping. **Neither side calls
`bindNativeScroll`.**

```
A (mount notice removed)  window before: c1..c40   CanvasPosition.Y := 2000   window after: c1..c40     moved=FALSE  scrollTop=0
B (shipped)               window before: c1..c40   CanvasPosition.Y := 2000   window after: c201..c240  moved=TRUE   scrollTop=2000
```

The other two hosts, same rules, same session:

```
VirtualList  Players.…PlayerGui.LuauUI_O31L./O31L/List            r1..r10  ->  r51..r60   moved=TRUE  scrollTop=2000
Table        Players.…PlayerGui.LuauUI_O31T./O31T/Tbl/Main/Body   r1..r18  ->  r49..r68   moved=TRUE  scrollTop=2000
```

**Teardown.** Every `ScreenGui` created here was destroyed and verified absent in
the same call (`leftoverOfMine: []`), and the clone was destroyed
(`cloneStillInRS: false`).

**One honest note about the session, since it is the trap of the evening.**
`PlayerGui` did not match my pre-mount snapshot at the end — not because of
anything I left, but because a `ScreenGui` I did not create changed underneath
me between calls (`LuauUI_CardRail`, then `LuauUI_AdaptiveScreen`, then
`LuauUI_HudScreen`, as another agent drove the picker). Reported rather than
worked around: a sweep that identifies "the demo on screen" by scanning
`PlayerGui` in this session would read whichever of those happened to be there.

## Part 4 — mutation evidence

Each mutation is applied to a tree restored to "HEAD + exactly these hunks"
first, so no mutation can leak into the next.

| Mutation | Named cases that reddened |
|---|---|
| **M1** the LIST never learns its mount | 4 — VirtualList follows the engine; …with a declared `navigationGroups`; the explicit-bind case; the gallery host case |
| **M2** the GRID never learns its mount | 4 — LazyVGrid; LazyHGrid; the `navigationGroups` function/false case; the gallery host case |
| **M3** the TABLE never learns its mount | 3 — Table follows the engine; the Table explicit-bind case; the gallery host case |
| **M4** the idempotence guard is dropped | 3 — the two explicit-bind cases and the gallery host case |
| **M5** the mirror re-asserts every frame instead of per mount | 2 — *a refresh after that unbind does NOT resurrect the mirror*, plus a pre-existing hosted-row-actions case |
| **M6** the opt-out is ignored (the block table binds its Body anyway) | 2 — *a BLOCK table auto-binds NOTHING*; the gallery host case |
| **M7** the grid mirror hard-codes `pos.y` | 5 — the LazyHGrid case plus four pre-existing horizontal-grid cases |
| **M8b** the counterfactual (build it on `buildFocusGroups`) | 2 — and ONLY the two discriminator cases |
| **R1** (RascalRally) the LIST never learns its mount | 1 — *this game's sponsor list follows an engine scroll with NO bindNativeScroll call* |
| **R2** (RascalRally) the idempotence guard is dropped | 1 — *…and LuauUISponsor's OWN bind on top of it opens no second engine observer* (`registrations added by this game's bind: 1`) |

**M4 is the one to read carefully, and it exposed a weakness in my own test
first.** As first written, *an explicit bindNativeScroll adds NO second engine
observer* counted only LIVE observers — and an arbitration that tears the mirror
down and reinstalls it on every consumer call leaves that count at exactly 1 and
passes. M4 reddened only the gallery case, which counts REGISTRATIONS. The two
framework cases now count both, and M4 reddens three.

**M8's first run is a published measurement error.** It produced 659 reds and
none of them were about the seam: `mirror` is declared after `buildFocusGroups`
in all three files, so the mutation faulted on a nil upvalue. Recorded because
"the counterfactual over-proved" is exactly the shape that gets mistaken for
evidence. M8b is the repaired run.

## Part 5 — suites

Pristine `git worktree` at HEAD `b377fe9`, carrying exactly the committed hunks
(built from `tools/commit_isolated.py --dry-run`'s own patch, so the tree under
test and the commit cannot disagree):

```
HEAD (b377fe9), untouched                     5596 passed, 0 failed
HEAD + this work                              5608 passed, 0 failed
```

Twelve new cases. The shared working tree showed 3 additional failures during
this work — all twelve stale rows in them name `p5_wardrobe`, whose
`examples/reference/p5_wardrobe/init.luau` another agent modified at 22:40, after
my baseline. They do not appear in the isolated worktree, which is what settles
the attribution.

**RascalRally** (its own repo): `3276 -> 3280 passed, 0 failed`. Four new cases
in `tests/luauui_motion_and_scroll_contract.spec.luau` (block **C-SCROLL**): the
sponsor list follows an engine scroll with no bind; `LuauUISponsor`'s own bind
opens no second engine observer and its unbind still stops the mirror; this
package still declares no `navigationGroups` anywhere (so both framework seams
are live here, and the day a screen declares one the difference between the seams
becomes this game's problem); and the new framework module is reachable on this
package's require path — the same distribution risk the two sibling-module rows
beside it were written for.

`tools/check_source_size.py` PASS with `KNOWN_OVER` empty. `stylua --check`
clean on every touched file.
