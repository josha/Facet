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

## Not fixed here, and why

The repair is a design decision with at least four shapes, and picking one from a
desk is how the original comment got written:

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

Recorded for a ruling. The measurement is the deliverable.
