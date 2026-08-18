# StyleSheet defeat is ORDER-SENSITIVE — pre-parent writes get stomped

**Found:** 2026-07-24, director live find (native-mode toggle knob/track rendered
transparent despite explicit `BackgroundTransparency = 0` writes).

The 2026-07-19/24 defeat truth ("an explicit instance-property write silently and
permanently defeats a StyleRule") holds **only for writes made while the styling
system already tracks the instance** (it is under a `StyleLink`ed tree). A write
made **before the instance first joins the styled tree** is indistinguishable
from a default: the FIRST style application **stomps it** and the rule wins from
then on.

Both directions verified live:

- `buildToggleVisual` wrote `track.BackgroundTransparency = 0` on a detached
  Frame, then parented it under the linked tree → the `Frame` class rule
  (`BackgroundTransparency = 1`) won visually; plain reads still returned `0`
  (reads are blind), `GetStyled` returned `1` (the rule = actual winner).
- The same write made on an instance already under the linked tree (spike m10
  F2/F3 cases) defeats the rule permanently.

**Consequences:**

1. Constructing chrome off-tree and writing "override" values before parenting
   DOES NOT override rules. Either write **after** the instance is styled, or —
   the honest native answer — give the instance a **tag rule** that owns the
   property (the toggle chrome now carries `.facet-toggle-chrome` →
   `BackgroundTransparency = 0`).
2. Plain property reads can claim a write "took" while the screen disagrees.
   **Never verify paint authority with plain reads** — use `GetStyled(prop)`
   (returns the actual winner) plus a visual capture.
3. Post-styling writes to properties with NO competing rule (e.g. the toggle's
   value-driven track/knob colors — no `Frame` color rule exists) are always
   safe in both modes.

## Addendum (same day): cascade order is NOT serialization-stable — pin it with Priority

The first fix (tag rule `.facet-toggle-chrome`) still lost in the director's
place: the sheet had been MIGRATED in Edit and copied into Play, and
`GetStyleRules()` came back **scrambled** relative to creation order ("Toggle
chrome" index 4, "Frame default" index 12 → the default's transparency won the
tie). Insertion-order cascade holds within the DataModel where rules were
created, but does **not survive the Edit→Play copy** (nor, presumably,
place-file round-trips).

**Rule: never rely on child/creation order for cascade. The generator assigns
explicit `StyleRule.Priority` from model order (index × 10) at build AND
re-enforces it on every apply (`syncPriorities`, generator-owned like the
mirrors).** Priority beats order (spike m6) and serializes with the rule.
Designers slot custom rules between the ×10 steps; priority edits to generated
rules are overwritten on apply — cascade is infrastructure, not paint.

## Addendum (2026-07-25): `GetStyled` is stale in the frame a sheet is installed

Found while diagnosing director round 5. Reading `GetStyled(prop)` in the SAME
`execute_luau` call that installed a theme package returns the **pre-install**
winner, not the new one: the style system applies on a later step, and the read
happens before it.

Concretely, on the Fantasy Parchment slider thumb: the install returned, the read
said `BackgroundTransparency = 0` (the old sheet's `Slot — sliderThumb`), and a
`task.wait(0.5)` later the same read said `1` (the new sheet's
`Skinned — sliderThumb`) — with nothing else touched. Diagnosing from the first
read would have "found" a cascade defect that does not exist.

**Rule: after any `install` / `swapPackage` / rule mutation, `task.wait(0.5)`
(0.8–1.2s for a whole-tree package swap) before any `GetStyled` read, and prefer
a second read after a further wait when the answer decides a fix.** The same
staleness applies to a live `StyleRule.Selector` or `Priority` edit — the value
may not move for a frame or more, so an A/B done by mutating a rule in place is
not evidence until it has settled and been re-read.
