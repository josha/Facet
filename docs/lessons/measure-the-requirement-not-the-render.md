# Measure the requirement, not the render

**Found:** 2026-08-05, from a director's glance at the fantasy theme — *"some buttons were
so small the single glyph overflowed onto the border area."*

**Cost:** a themed screen where the `Open` button, the `Ready` toggle and six overlay
chips had no readable label, past a green 3 421-case suite, a green layout audit
reporting **zero** findings, and a gate at 22/22.

## The defect

A 60×46 button. Its own `Text = "Open"`, `TextBounds = 36×18`, `TextFits = true`. The
solver sized the control for that label and was right.

The theme then **lifted the label into `LuauUIChromeText`, sized from the art** — a 36px
decoration minus two 14px corner pieces — leaving a box **8 pixels wide**. The label
rendered as nothing.

```
button          60x46   Text="Open"  TextBounds=36x18  TextFits=true
LuauUIChromeText 8x26   Text="Open"  TextBounds= 0x18   ← rendered nothing
```

## Why every existing instrument missed it

**The lift happens in the adapter, after the solve.** `controller.diagnostics()` — the
instrument that catches every other layout defect in this project — measures the tree the
solver produced. It never sees a box the theme derived from art afterwards.

This is the same family as
[`the-solver-already-told-you.md`](the-solver-already-told-you.md) and the fixed-px-height
lesson: *painted at a size nobody measured for it*. What is new is the seam — the audit is
not blind here, it is **downstream of the thing that went wrong**.

## The trap inside the fix

The first version of the check compared the lifted box against `lifted.TextBounds` and
**flagged nothing at all** on the very screen that was visibly broken.

**`TextBounds` is the RENDERED width, not the required one.** A label truncated to nothing
reports `TextBounds.X = 0`, so `box.X < textBounds.X` is false for exactly the labels that
have vanished. The check was blindest precisely where the defect was worst.

This is the same shape as `TextFits` returning `true` for a truncating label, which this
project had already been caught by once.

**The requirement has to come from somewhere that still knows it.** Here that is the
HOST control's own `TextBounds` — the width the solver measured and sized the control for
— plus an unambiguous `vanished` case: a non-empty `Text` that renders zero width.

Live result after the fix: **8 of 34 lifted labels flagged under `fantasy_ornate`, 0 of 0
under `flat`.** The v1 check reporting 0 on the same screen is the mutation evidence.

## Rules

1. **A number that describes the outcome cannot detect the outcome being wrong.**
   Rendered width, `TextFits`, a truncated bounds — all of them already have the failure
   baked in. Compare against the *requirement*, held somewhere upstream.
2. **Every seam past the solve needs its own audit.** `controller.diagnostics()` covers
   the solve. Anything that derives geometry afterwards — chrome lifts, decoration
   sizing, adapter-owned art — is outside it and needs a check of its own.
3. **A theme selector that silently does nothing is worse than one that errors.** The same
   investigation found `select:theme=X` recording a name it never applied, while capture
   rows wrote that name into their identity. Refuse what you cannot honour.
4. **Ask what you have not measured.** Every performance number in that pass was taken on
   the flat theme. Nobody had asked whether the wins held with a real theme loaded — they
   did, but that was luck rather than evidence until it was checked.
