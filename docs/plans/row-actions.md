# Row Actions — SwiftUI-style swipe actions for rows (design)

**Date:** 2026-08-09 · **Status:** Design approved, awaiting implementation plan
**Scope:** New general-purpose `UI.RowActions` composite + Table integration + full refresh of `docs/reference/swiftui-parity.md`.

## Goal

Rows in Table (and any list-like content) get SwiftUI-parity swipe actions:
swipe to reveal leading/trailing action buttons that animate in, full swipe to
commit the first action (delete), with every action reachable on every input
device per the constitution. Closes the audit gap "Generalized swipeActions
containers — Missing" (swiftui-parity.md §0).

## Non-goals

- RTL layouts (leading = left, trailing = right; Roblox has no RTL layout system).
- Swipe actions on arbitrary non-row content (carousels, cards). The composite
  is general, but this mission only wires and verifies Table rows.
- Changing edit-mode reorder behavior.

## Decisions already made (with the director)

1. **Full cross-input model** — not touch-only. Every action reachable on
   touch, mouse, keyboard, and gamepad.
2. **General container** (`UI.RowActions`), Table consumes it — not a
   Table-internal feature.
3. **Input mapping follows SwiftUI**, adapted to Roblox:
   - **Touch:** horizontal pan reveals the tray; full swipe commits the first
     action on that edge (SwiftUI `allowsFullSwipe`).
   - **Mouse:** horizontal drag on the row body stands in for macOS trackpad
     swipe (Roblox cannot observe trackpad two-finger swipes).
   - **Keyboard:** focused row + **Delete/Backspace** fires the first
     `destructive` action (SwiftUI `onDeleteCommand`). One Input Action
     ("rowActionsMenu", default **Shift+Return**, rebindable) opens the full
     action menu — the same action gamepad X binds to.
   - **Gamepad:** focused row + **ButtonX** opens a small menu listing all
     actions (the analog of SwiftUI exposing swipe actions as accessibility
     custom actions).
   - **Edit mode:** rows show a leading delete affordance (minus); tapping it
     opens the trailing tray with Delete emphasized (iOS pattern). Joins the
     existing edit-mode reorder handle.
4. **Full re-audit** of swiftui-parity.md, not a delta patch.

## Public API

```lua
UI.RowActions{
  content  = <Blueprint>,          -- the row content (required)
  leading  = { ActionSpec, ... }?, -- revealed by rightward swipe
  trailing = { ActionSpec, ... }?, -- revealed by leftward swipe
  fullSwipe = true?,               -- default true: full swipe commits the
                                   -- FIRST action of the swiped edge.
                                   -- Per-edge form also accepted:
                                   -- { leading = bool?, trailing = bool? }
                                   -- (SwiftUI allowsFullSwipe is per edge)
}

ActionSpec = {
  id    = string?,                        -- stable id (defaults to label)
  role  = ("normal" | "destructive")?,    -- destructive paints theme danger
  label = string,                         -- localization-safe, may wrap
  icon  = string?,                        -- standard icon set name
  onAction = () -> (),                    -- quarantined, exactly-once per commit
}
```

- Constitution kind: **composite control**; strict spec validation, unknown
  keys are errors. Returns the standard composite shape.
- With neither `leading` nor `trailing`, the wrapper is an inert passthrough
  (valid — lets callers wire it unconditionally).
- Colors/metrics come from the theme (danger token for destructive, action
  tray metrics as new theme entries). No literal colors in the control.

### Table integration

```lua
UI.Table{
  ...,
  rowActions = function(item) -> { leading?, trailing?, fullSwipe? }?,
}
```

- Returning `nil` for an item = no actions on that row.
- Table wraps each row's blueprint in `UI.RowActions` and supplies the shared
  open-state coordinator.
- The keyboard Delete path and edit-mode minus affordance derive from the
  first `destructive` action in that row's `trailing` (or `leading`) list —
  no separate `onDelete` spec key; one source of truth per row.

## Architecture

**Components (each independently testable):**

1. **`src/controls/row_actions.luau`** — the composite. Owns the tray
   blueprints, the reveal spring, commit/collapse animation, per-input entry
   points. Content sits in a ZStack over the tray; the tray buttons slide in
   proportionally to drag distance (SwiftUI stretch feel).
2. **`src/controls/row_actions_state.luau`** — pure decision module: given
   gesture deltas/velocity and thresholds, decides `closed | revealing |
   open | committing`, which edge, and rubber-band overshoot. No Instances,
   no engine — fully headless-testable.
3. **Open-state coordinator** — at most one row open per surface. Opening a
   row closes the previous; scroll motion and outside taps close the open
   row (rides the existing responder/exclusive machinery — same family as
   modal outside-tap; note the round-7 Zone-A lesson: closing must not
   swallow unrelated clicks).
4. **Gesture arbitration** — extend the existing `touch_gestures` arbiter +
   row pointer handlers with an **axis lock**: first ~8 px of movement decide
   winner. Horizontal → RowActions claims, vertical → ScrollView keeps it,
   reorder handle drag always wins on the handle. Losers stand down cleanly
   (no half-revealed trays on scroll).

**Data flow (touch happy path):** pointer down on row → arbiter watches →
axis lock horizontal → RowActions drives reveal spring from drag delta →
release: state module picks snap-open / snap-closed / (past big threshold +
`fullSwipe`) commit → commit: row slides off + height collapses on a spring →
`onAction` fires once → owner mutates data → keyed Table diff removes the row.

**Motion:** springs from `motion.newSpring` with theme motion tokens;
gesture→spring velocity handoff via the existing `drag_velocity` capture.
Reduced motion: reveal/commit **snap** (`"snap"` kind); no slides.
Thresholds: snap-open at ~half tray width; full-swipe commit at ~60% of row
width (tuned live during implementation; encoded in the state module, not
scattered).

## Error handling & edge cases

- `onAction` throws → quarantined per constitution; tray still closes.
- Row unmounts while open/mid-gesture → dispose closes cleanly, no leaked
  subscriptions, coordinator entry cleared.
- Reorder drag starting (handle) while a tray is open → tray closes first.
- Action list empty table (`{}`) → spec error (use `nil` to mean none).
- Commit racing a data refresh (row rebuilt under the gesture) → gesture
  cancels; never fire `onAction` for a row whose key no longer matches.
- Text: labels are localization-safe (wrap/auto-fit, ~1.4x expansion, never
  clip) and respect large-text offsets like other controls.

## Testing

- `tests/row_actions.spec.luau` — state module exhaustively (thresholds,
  rubber-band, both edges, fullSwipe on/off); composite mount/dispose;
  callback exactness; reduced-motion snap; spec validation errors.
- `tests/row_actions_input.spec.luau` — axis-lock arbitration vs scroll and
  vs reorder; keyboard Delete; gamepad menu; edit-mode affordance; one-open
  coordinator incl. scroll-closes and outside-tap (with a
  does-not-swallow-unrelated-clicks pin).
- Table integration cases in `tests/table.spec.luau` (rowActions wiring,
  nil-per-row, destructive-derivation for Delete key).
- Every fixture calls `controller.diagnostics()` and fails on it; device
  sweep includes 320×640.
- Gate: new checks follow the `✓.*` grep rule; Studio five-view matrix drive
  (phone portrait/landscape emphasized) + RascalRally consumer check per the
  LuauUI/RascalRally coupling rule (no current RR Table uses rowActions, so
  expected outcome is a compatibility-evidence row, not game edits).

## Audit refresh (after the feature ships)

Full fresh re-audit of `docs/reference/swiftui-parity.md`:

- Re-validate **every** item against current LuauUI (v0.8+, Steps 7–11:
  API constitution, desktop keyboard, large text, perf lab + incremental
  layout + elision, reference apps) and the June 2026 SwiftUI baseline.
- Performed by fresh-context subagents (the luauui verifier roles) so stale
  judgments don't survive by inertia; claims must cite file/test evidence.
- Structure: keep the doc path; rewrite with a new validation date, per-area
  verdict tables, and an explicit "changed since last audit" section.
- swipeActions row flips to covered, citing `UI.RowActions` + tests.
- Note: the file currently has uncommitted local edits on
  `sponsor/director-round-2026-08-04` — reconcile, don't clobber.

## Sequencing

1. `UI.RowActions` composite + state module + tests (headless).
2. Gesture arbitration + coordinator + input paths (headless + Studio).
3. Table integration + edit-mode affordance + gate + device matrix.
4. Full swiftui-parity re-audit (fresh-context agents).
