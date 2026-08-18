# `instance.Parent` is NOT the layout parent — the screen target's tree is FLAT

**Found:** 2026-07-25, first live drive of the rich-skinning-v2 bar assembly (P3).
**Applies to:** anything in `src/client/screen_target.luau` that needs a node's
layout ancestor.

## What bit

The bar's clipped fill has to size its art to the whole TRACK, so the adapter
read the track's extent off `handle.instance.Parent`. It compiled, it passed the
headless suite, and live it produced a 0-wide image on one screen and a
viewport-wide one on another.

`screen_target` renders a **flat instance tree**: every mounted node is a direct
child of its root `ScreenGui` (or its scroll host) with an *absolute* rect
written by the solver, and its `Name` is the full Facet path. So

```
/ValueProbe/Load/Bar/Fill        -- a Frame whose Parent is the ScreenGui
/ValueProbe/Load/Bar             -- a sibling Frame, NOT its parent
```

The DataModel parent says nothing at all about layout containment. Reading
`AbsoluteSize` off it measures the ScreenGui.

## The rule

**The PATH is the containment relation.** Walk up `handle.path` and look the
segments up in `handlesByPath`:

```lua
local cut = string.match(path, "^(.*)/[^/]+$")
```

Stop at whatever you are actually looking for — in the bar's case, the node that
declared the `barTrack` decoration hint, which also means a control may nest its
fill as deep as it likes.

## What still uses real parenting

Adapter-created chrome — decorations, layer ladders, the bar window, the toggle
knob-track — ARE real children of the node they decorate, and they position
relative to it normally. The flatness is about Facet *nodes*, not about the
managed children the adapter hangs off them. Two consequences worth remembering:

- a child combinator in a StyleSheet rule (`.facet-interactive:Press > .facet-chrome-toggleKnob`)
  reaches adapter chrome exactly as written, because that part of the tree is real;
- the same combinator can NEVER reach one Facet node from another, because they
  are siblings — which is why every node-to-node state rule keys on tags instead.

## Related

- `docs/lessons/later-locals-are-not-upvalues.md` — the other shape in this file
  that only a Studio session catches.
- `artifacts/rich-skinning-v2/rs-a5-image-bars.json` → `liveFoundDefectsFixed`.
