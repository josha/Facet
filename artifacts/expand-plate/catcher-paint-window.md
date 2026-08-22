# The catcher paint window — what a `GetStyled` reading near a node's birth means

**Measured 2026-08-21 in the connected Studio (`Facet-Showcase.rbxl`, Edit
datamodel), DIR5 fix round.** Commissioned by a review finding: the mechanism DIR5
published for "the popup background is opaque" was refuted by DIR5's own oracle —
a `plain` catcher resolves to `BackgroundTransparency = 1`, so the class-default
rule was never the opaque source. This is what the director's two numbers actually
measure.

## The probe

A `StyleSheet` carrying the two rules Facet's own sheet carries for this node —

```lua
StyleRule "Button default"  Selector = "TextButton"             -> BackgroundTransparency = 1
StyleRule "Scrim backdrop"  Selector = ".facet-surface-scrim"   -> BackgroundTransparency = 0.45
```

— linked to a fresh `ScreenGui` through a `StyleLink` named `FacetStyleLink`, in
the adapter's own order (create root, link, parent, create node, tag it), then read
back after N frames with `GetStyled("BackgroundTransparency")`.

## The numbers

```
plain@0f  styled=0.00  prop=0.00
plain@1f  styled=0.00  prop=0.00
plain@2f  styled=0.00  prop=0.00
plain@3f  styled=1.00  prop=0.00
plain@5f  styled=1.00  prop=0.00
plain@10f styled=1.00  prop=0.00

scrim@0f  styled=0.00  prop=0.00
scrim@1f  styled=0.00  prop=0.00
scrim@3f  styled=0.45  prop=0.00
scrim@10f styled=0.45  prop=0.00
```

A sheet parented OUTSIDE the linked subtree (`ReplicatedStorage`) settles to the
same values, so sheet placement is not a term. A first probe that read back after a
single frame reported `styled = 0` for *both* roles, which is the whole finding.

## What this establishes

1. **`prop` is never written, ever.** In native mode the adapter deliberately writes
   no `BackgroundTransparency` at create — an explicit write permanently defeats
   every surface rule (spike m10) — so the instance property reads the engine
   default (`0`) for the whole life of every Facet node. **The director's
   "`BackgroundTransparency` 0" is expected and carries no information.** DIR5's
   report treated it as corroborating; it does not.

2. **`GetStyled` reports the CLASS DEFAULT until the styling pass has applied**,
   measured at ~3 frames after creation, and it does so for `scrim` exactly as much
   as for `plain`. A catcher root is created at the instant a surface opens, so a
   reading taken then is inside that window. **The director's `GetStyled = 0` is
   consistent with a correctly linked, correctly ruled catcher.**

3. **The settled values are right, and were right before the fix.** `plain` settles
   to 1 (invisible); `scrim` settles to 0.45. The role change did not remove a known
   cause — it replaced an unowned 1 with a theme-owned 0.45, which is the right
   *product* answer for a plate that covers content but is not the mechanism DIR5
   claimed.

## What is still open

The window itself is a real opaque flash of a full-viewport node, and **no
framework-side write can close it**: the one property that would is the one native
mode may not touch. Two live candidates remain for a *persistent* opaque fill, and
each has a fence:

* a root that never received a `StyleLink` (created while `activeSheetFor()` was
  nil, and only ever repaired by a later theme swap) — pinned model-side by
  `tests/popup_catcher_paint.spec.luau` "the synthesized scrim ROOT is linked to the
  same sheet as the screen it covers";
* the window above, which is engine-side and unmeasurable headlessly.

**If the popup is reported opaque a fourth time, the discriminator is duration**: a
reading taken 10+ frames after the plate opened that still says 0 is the unlinked
root; one taken immediately is this window. Take both.
