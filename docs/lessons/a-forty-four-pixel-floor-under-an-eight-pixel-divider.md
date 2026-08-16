# A 44px floor under an 8px divider makes a dead zone, not a target

**Measured live in Studio, 2026-08-14** (LuauUI-Showcase, Play mode, the
`table_columns` fixture, real engine).

`src/controls/contract.luau:95-102` gives `Grip` `minHitSize = 44`. The table's
resize divider (`table.luau`'s `gripFor`) is `width = { type = "fixed", px = "s" }`
— **8px** under Studio Neutral, 4px under `classic_desktop` — and `height = fill`
of a 28px header band. So the renderer asks the adapter for a **44×44 hit rect
centred on an 8×28 grip** (`layout_node.luau:182-186` → `renderer.luau:1978-2028`).

`screen_target.luau:2461-2500` realizes that as a real `LuauUIHitExpander`
`TextButton`, parented **beside** the grip at `ZIndex = grip.ZIndex - 1`.

> **Sibling defect, same fixture, same session.** This page is about the
> **pointer** route to a resize. The **keyboard** route was broken in the same
> hour and for an unrelated reason — Roblox's default camera holds `Left`/`Right`
> through ContextActionService and sinks them, so the selected-column arrow
> resize never receives a keypress
> ([`the-camera-still-owns-the-arrow-keys`](the-camera-still-owns-the-arrow-keys.md)).
> That one is **not** a LuauUI defect and has no LuauUI fix: it is closed by the
> embedding experience enabling `Workspace.PlayerScriptsUseInputActionSystem`,
> which puts the camera on the Input Action System where priority arbitration
> works. Read the two together before concluding anything about which resize
> routes exist — the route inventory in point 3 below is the *pointer* one.

## What that actually builds, measured on the live instance tree

Header cell `Head-name` spans x ∈ [12, 277]; the header band is y ∈ [120, 148].

| instance | class | rect | ZIndex |
|---|---|---|---|
| `Head-name/Column` | `TextButton` | (12,120) 265×28 | **10** |
| `Head-name/Title` | `TextLabel` | (20,125) 249×17 | 11 |
| **`LuauUIHitExpander`** (the grip's) | **`TextButton`** | **(251,112) 44×44** | **12** |
| `Head-name/Grip` | `Frame` (Active) | (269,120) 8×28 | 13 |

`12 > 10`: the expander sits **above the header cell's own button**, and a
`GuiButton` sinks `InputBegan`
(`docs/lessons/a-button-eats-the-swipe-underneath-it.md`).

## The consequence, measured, with a control in the same session

| click | inside | what happened |
|---|---|---|
| **(264, 134)** — trailing 26px of the name header, over the expander | the name header cell | **nothing.** No sort, no selection. `SortMark` stayed `''`, 0×0 |
| **(100, 134)** — same cell, clear of the expander | the name header cell | **sort cycled.** `SortMark` = `▲`, 7×14 |

**A 26px-wide dead band runs down the trailing edge of every resizable header
cell.** It is not a small edge case: it is ~10% of a 265px column, it grows
proportionally narrower columns get, and it sits exactly where a player aims when
they are reaching for the divider.

## Three things make it worse than it looks

1. **The floor buys the grip nothing.** The expander is *below* the grip
   (`grip.z - 1`), so it never widens the draggable band. The resize target is
   still 8×28 = 224px² against a required 1936px² — **11.6%**. The mechanism
   costs a dead zone and returns no target.
2. **The expander is inert.** `screen_target.luau:2487-2498` wires it only to
   `handle.activate`, which is assigned for `TAPPABLE` classes only
   (`renderer.luau:250` = Button, Toggle, TextField). A Grip is not tappable, so
   the expander is a `GuiButton` that sinks presses and forwards nothing. The
   `renderer.tapAt` forwarding that `row_actions` uses to solve exactly this
   problem (same lesson, "ruling 6, option A") is **never called from
   `table.luau`** — `grep tapAt src/controls/table.luau` is empty.
3. **On a phone there is no route at all.** The divider is 8px against the same
   theme's own 44px touch floor — the floor `controls.table.rowHeight.touch` is
   itself derived from (`tests/table_columns.spec.luau` pins the measurement:
   `Touch=grip8x28/row36→44`; the ROW grows for touch, the DIVIDER does not).
   Touch has no bumpers, no `,`/`.`, no Tab. **A resizable column is not
   resizable on a phone**, and the only pointer affordance is a `MouseIcon` hint
   no touch device can render.

## Why the headless suite is green

`controller.tapAt` is the **framework's** hit test and arbitrates on solved rects;
it answers `Column` at every point above. The expander exists only on the adapter,
as an instance, and `fake_target.pointerDown(path, x, y)` dispatches to the path
it is *handed* — no rect containment, no z arbitration. So the two "touch grip
drag" cases in `tests/table_input.spec.luau:313,332` prove the handler wiring and
structurally cannot see any of this.

What a headless run *can* hold is the geometry that produces it, and
`tests/table_columns.spec.luau`'s `asks for 44x44 centred on an 8x28 grip` pins
exactly that: the 44×44 request, the 26px band, and `grip.z - 1 > column.z`. If
any of the three moves, the live table above has to be re-measured.

## Ruled and fixed the same day (director, option 1)

> "Give the expander the grip's gesture, forwarding via `tapAt`."

It was the only one of the four that closes both symptoms in one move, and it is
the **general mechanism rather than a new concept**: `row_actions` already
forwards unclaimed presses through `controller.tapAt(x, y, { within, skip })`
(ruling 6, `aa1e271`). Two halves:

1. **The adapter** (`screen_target.luau`). The `InputBegan` body that starts a
   pointer capture was extracted as `beginPointerCapture` and is now connected to
   the expander as well as to the host instance — the expander's whole contract is
   "a press here is a press on the host", and it had been honouring that for
   `handle.activate` only. `dropHitExpander` takes both down in one place.
2. **The control** (`table.luau`'s `gripFor`). A press is not a resize until it
   travels: `interaction_tokens.promoted(dx, dy, pointerType)` — the shared
   press→drag gate, 6px on a mouse and 14px on a finger, which this control
   already reads for its row drag. Under the gate the press was never this zone's
   gesture, so it is handed to whatever the expander was covering:
   `controller.tapAt(pos.x, pos.y, { within = cellPath, skip = gripPath })`.
   No width is committed, and the guide line no longer flashes for a tap.

### Which `tapAt` family, and a correction to the ruling's note

The ruling said "a resize grip is a pointer zone, so [the pointer-zone] family is
the one you need". That reads the direction backwards, and it matters:

- `tapAt` replays a pointer zone's **down/up pair at one point**. A resize is a
  *drag*, so a replay could never produce one — and the grip's solved rect is 8px
  wide, so `tapAt` would not find it at a point 18px to its left anyway.
- What actually lands under the expander is the header cell's own `Column`
  **Button**, so the **tappable** family runs: the same activate dispatch a native
  press reaches. The pointer-zone family still earns its place here — it is what
  makes the Grip a `tapAt` candidate at all, which is precisely why `skip` names
  the Grip so it cannot forward to itself.

The 44px drag target comes from the *adapter* half, not from `tapAt`. Nothing
about the ruling's choice changes; only the note about which family does the work.

### Measured live afterwards, same place, same session (2026-08-14)

| input | where | before | after |
|---|---|---|---|
| click (264,134) | trailing 26px of the name header, over the expander | **nothing** | **sort cycles, `SortMark` = `▲` 7x14; widths still `auto`** |
| click (100,134) | same cell, clear of the expander (the control) | sort cycles | sort cycles, `▼` |
| press (258,134), drag to (200,134) | inside the 44px band, 11px clear of the 8px grip | **nothing** | **Entrant 265 -> 207px**, readout follows |
| press (215,134), drag to (275,134) | the 8px grip itself (the old route) | resizes | resizes, 207 -> 267px |

The 26px dead band is gone and the band is a real resize target. Row 4 is there
because "the band works now" would otherwise be equally explained by "the grip
stopped working and only the band is live".

**And the phone is answered.** Point 3 above — "a resizable column is not
resizable on a phone" — was true because the only pointer target was 8px wide.
The target is now the whole 44x44 the floor always asked for, and the tap/drag
gate reads the touch token (14px) from the pointer type of the event in hand, so
a finger that travels resizes and a finger that does not sorts. Injected Studio
input arrives as `UserInputType.Touch`, so the drags in rows 3 and 4 above were
touch presses; a physical-device confirmation is still the standing rider.

### The open ceiling, inherited

Ruling 6's `ponytail` applies here unchanged: **a forwarded press has no pressed
visual.** The header button under the finger does not light up while held, because
the engine never told it it was pressed. The activation itself is exact. Upgrade
path is the same one — forward the down/up pair rather than the resolved tap.

### What the geometry pin does now

`tests/table_columns.spec.luau`'s 44x44 / 26px / `grip.z - 1 > column.z` pin is
**unchanged at the same numbers**: the repair was to what the rect *does*, not to
where it is. The z relationship in particular is now load-bearing for the opposite
reason — the expander has to be the topmost thing under a finger aiming at the
divider, or there would be no press to promote into a drag.

### The options that were not taken, and why

(Recorded as they stood before the ruling.)

- **Give the expander the grip's gesture** (forward via `tapAt`, as `row_actions`
  does) — makes the 44px band a real resize target and removes the dead zone in
  one move. Probably right; changes what a press near a column edge means.
- **Exempt `Grip` from the floor** — honest ("a splitter is a mouse affordance"),
  and gives up on touch resize entirely.
- **Widen the grip on touch** — paints a fat hairline down every column edge,
  and space steps have no paradigm today (`snapshot.resolve`'s `Facts` never sees
  `preferredInput`), so it is a new theme concept.
- **A separate touch affordance** — a drag handle in edit mode, the way reorder
  already works.

The measurement was the deliverable; the ruling followed the same day.

## The other half, ruled and fixed 2026-08-15: the band the fix could not reach

The 2026-08-14 repair made the expander a real drag target. It did **not** make
the whole 44px band reach the expander, because the OUTER half of that band lies
over the *neighbouring* header cell, whose button is walked later and therefore
paints higher — and Roblox delivers input to the topmost interactive object only.
Re-measured live, per pixel: `EXP 18px + Grip 8px` and then **18px belonging to
`Head-team/Column`**. 26 delivered of 44 across, 38 of 44 down (the bottom 6px
went to row 1's `Hit`).

That is not a Table defect at all — 48 scenarios on a real engine found 86 hit
expanders and 82 such relations (`artifacts/hit-expander-overhang/
corpus-measurement.md`), with `virtual_list_native` and `keyboard_navigation`
carrying it silently. The fix is a paint-order rule, `src/render/hit_lift.luau`:
a host whose expander overhangs is walked, with its expander, **after** the
branches that expander reaches PAST it into. Measured after: **44 of 44 on both
axes**, an outer-half drag resizes, and an outer-half tap sorts nothing.

Two things this lesson got right and one it did not:

- "Raise the expander" is unsatisfiable, and this page's own table shows why: the
  expander needs `< hostZ` (hover lives on the host) and `> neighbourZ`, while
  `neighbourZ > hostZ`. The HOST is what has to move.
- The `grip.z - 1 > column.z` pin is still exactly right, and it now also pins the
  clause that keeps the rule from inverting it: a target the host's own painted
  rect already overlaps is not "past its host" and is never lifted over.
- What no one had noticed: `hostZ - 1` **collides** with whatever node the walk
  visited immediately before the host. A tie, broken by insertion order. The z
  walk now reserves that counter for the expander.
