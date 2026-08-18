# Inert container elision — the 40% finding

**Status: MEASURED AND SCOPED. Not started.** This is a renderer/adapter change with 47
call sites to make instance-optional; starting it at the end of a long pass is how the
first incremental-layout attempt went wrong.

## The finding that reframes the task

The task was "reduce the performance lab's per-row GuiObject count", on the basis that a
row uses 23.6 objects against 9.2 for the matched raw-Roblox reference — 2.6×.

**Enumerating one row shows there is nothing to cut on the row side:**

| | count |
|---|---|
| CONTENT elements (image, 2 labels, toggle, button, 2 stepper buttons, 2 stepper labels) | **9** |
| layout containers | **11** |
| raw-Roblox reference | 9.2 |

**The row's content is already at parity with the native reference — 9 against 9.2. The
entire 2.6× gap is framework container instances.** There is no row-composition win
available; the objects are the framework's, and so is the fix.

## What those containers are

Across the whole surface (5-row window, 137 GuiObjects):

| | count |
|---|---|
| paints a background | 37 |
| clips | 1 |
| interactive | 30 |
| carries modifier children | 38 |
| **completely inert** | **55 (40%)** |

"Inert" = does not paint, does not clip, is not interactive, has no modifier children, and
carries no text or image. Examples: `/Row/Row`, `/Row/Row/Head`, `/Head/Labels`,
`/Row/Controls`, `/Row/Value`, `/Value/Rate`, `/Rows/Canvas`, `/Rows/Canvas/W`.

**And in Facet's flat tree they are not even the engine parent of their children.**
`adapter.create` parents everything to the root (or to the nearest clip host) and the
solver positions every node absolutely. So an inert container is an invisible, zero-child
`Frame` holding a rect that nothing reads.

At the measured ~12.4 µs of engine work per instance, 55 objects is **~0.68 ms per full
window build** — and `mount` is 67% of a fling frame.

## The design

A node needs an engine instance only if it does one of:

- **paints** — a `surface`, background, tint or gradient;
- **clips** — a ScrollView, `clipChildren`, or a CanvasGroup (a real engine parent);
- **is interactive** — a hit target, drag detector or focusable;
- **carries adapter chrome** — decoration, stroke, corner, padding, chrome text, toggle
  parts, motion/press scale, presentation transform;
- **is a text or image leaf**.

Everything else can be handle-only: the handle keeps its path, class and rect for the
renderer's bookkeeping, and no `Instance` is ever created.

**Lazy rather than never** is the safer shape, and matches the `UIScale` fix already
shipped: create the handle without an instance, and materialise on the first write that
genuinely needs one. `setRect` on an instance-less handle is a no-op — correct, because
an invisible container's rect affects nothing in a flat tree.

## Why it is not a small change

`handle.instance` is dereferenced **47 times** in `screen_target.luau`. Every one has to
tolerate absence or force materialisation, and getting a single one wrong produces a
missing node rather than a slow one. The verification has to be the same three oracles
incremental layout needed:

1. the headless differential (paint, text facts, diagnostics);
2. **`tools/studio/visual_diff.luau`** — engine-resolved geometry for every GuiObject,
   which is the oracle that matters here, since the change is *about* which instances
   exist. Note the node count itself will legitimately change, so the diff must compare
   the surviving nodes and assert the elided ones were inert;
3. the full suite plus RascalRally, and a live Studio canary.

Several existing tests count instances directly (census, teardown-to-zero, the
lifecycle soak) and will need their expectations re-derived from the new rule rather than
adjusted to whatever the code produces.

## Expected result

~55 of 137 GuiObjects on this surface, ~11 of 20 per row. That would take the lab's row
from 23.6 objects to roughly the native reference's 9.2 — closing the entire gap that
started this line of work, and it would apply to every Facet consumer, not just lists.
