# ADR-0030 live evidence — the ring moves in two dimensions, on a real place

**Place:** `LuauUI-Showcase.rbxl`, Rojo-connected (`examples/showcase.project.json`, port 34873).
**Date:** 2026-08-15. **Session:** fresh Play, started *after* the sync (`require` is cached per
datamodel — reading the right source is not proof you ran it).
**Instrument:** the real `InputAction`s the presenter binds (`Nav-VirtualGrid.Navigate` /
`.NavigateH` / `.Traverse`), fired live. Not the fake target: the fake models handler wiring, not the
engine's input arbitration.
**Readout:** the painted focus ring. On these surfaces it is a floating `Frame` named
`FocusRingFloat` inside the grid's scroll host, so the focused cell is the one whose rect it sits on
— i.e. the thing the player actually sees, not a signal read behind the render.

## Preflight

| Fact | Value |
|---|---|
| `SetCoreGuiEnabled(PlayerList, false)` | `true` — Tab is the players-list hotkey and is not deliverable with the list enabled |
| `focus_graph` in the datamodel carries `local function laneCount` | `true` |
| …carries `local function lineStep` | `true` |
| …carries the string `ADR-0030` (written minutes earlier) | `true` — the staleness marker |
| `virtual_grid` carries `local function navigateIntercept` | **`false`** |
| `virtual_grid` carries `navigateIntercept = navigateIntercept` (the bundle entry) | **`false`** |
| `virtual_grid` carries `bindFocusGraph` | **`false`** |
| `virtual_grid` carries `columns = lanesNow()` | `true` |

The deletion is therefore what the running client actually has, not what the working tree says.

## LazyVGrid (`virtual-grid` demo, 4 lanes)

Walked the ring out of the grid with the lane axis, back in from above, then down.

```
after 20x Left : none          (the ring left the group — a grid is not a closed box)
after 4x Up    : none
DOWN  #1 -> c1                 ENTRY into the FIRST line
DOWN  #2 -> c5                 +4 — a whole LINE
DOWN  #3 -> c9                 +4
RIGHT #1 -> c10                +1 — one CELL
RIGHT #2 -> c11                +1
UP    #1 -> c7                 -4
UP    #2 -> c3                 -4
```

**The positive control is in the transcript.** `RIGHT` moves the ring by one cell and the probe
plainly reports it — so a `DOWN` that had moved one cell (the list's answer, the "reachable and wrong
in shape" defect this mechanism exists to prevent) is a change this instrument demonstrably sees. The
±4 readings are not the instrument failing to resolve a smaller step.

## LazyHGrid (`virtual-hgrid` demo, 2 lanes running down)

The transpose, on the same instrument:

```
DOWN  #1 -> h1                 the LANE axis here
DOWN  #2 -> h2                 +1 — one CELL
DOWN  #3 -> h3                 +1
RIGHT #1 -> h5                 +2 — a whole LINE
RIGHT #2 -> h7                 +2
LEFT  #1 -> h5                 -2
LEFT  #2 -> h3                 -2
UP    #1 -> h2                 -1
UP    #2 -> h1                 -1
```

Same field, opposite direction pair, no code in either control.

## Tab is still document order

`Nav-VirtualHGrid.Traverse`, five presses from `h1`: `h2, h3, h4, h5, h6` — lanes then lines, which
is the grid's own order. `columns` adds no ordering opinion, and this is that claim on a live place.

## One thing this place cannot show, and it is not new

The showcase's *demo* host does not call `grid.bindNativeScroll`, so the control's scroll mirror does
not follow the engine's `CanvasPosition` and the mounted window stays on its first lines. Measured
directly: an engine scroll to `CanvasPosition = (0, 2000)` left the window on `c1..c16`. That is a
showcase-host gap, not a focus one — an engine scroll is the pointer path and never touched the
intercept — and the pre-ADR intercept was stuck at the same edge for the same reason (its target
resolved to an unmounted cell and it declined). The scenario runner's `bind` step wires it; the demo
picker's auto-bind did not fire here. **Booked as a follow-up, unrelated to this change.**

## Probe hygiene

Nothing was mounted. The one piece of state this session wrote — `CanvasPosition` on the vgrid, set
by the mirror probe — was reset to `(0, 0)` in the same call that used it, before the walk above.
Play was stopped at the end.
