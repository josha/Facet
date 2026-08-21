# Decoration paints to the edges — and a policy string nothing reads is a lie

**Found:** 2026-07-26, a physical phone, showcase place.

## Two facts that belong together

**1. Safe areas are for content.** A scrim, a backdrop, a dim — none of these is
content. Inset one and you get a rectangle drawn *inside* the screen with the 3D
world showing around it, which is exactly what a device capture showed: a black
panel with a hard edge against the sky gradient on two sides.

So a decoration layer is presented with:

```lua
presenter.present(backdrop, { responder = "passive", rootPolicy = "edgeToEdge" })
```

and the renderer zeroes the insets for that root only. Content roots keep
`coreSafeContent` (the default) or `deviceSafeContent`.

**2. `edgeToEdge` had been passed for months and never read.**

`src/present/presenter.luau` has asked for `rootPolicy = "edgeToEdge"` on every
modal scrim since scrims existed, with a comment stating "the dim/barrier covers
the whole viewport (incl. insets)". No branch in `src/render/renderer.luau`
matched that string. It fell through to the default and every scrim was quietly
inset.

Nothing failed. No test caught it. The comment described the intent and the code
did something else, and the two agreed loudly enough that neither was checked —
for as long as nobody looked at a scrim on a device with real insets.

## The rule that generalises

**A policy string that no consumer branches on is indistinguishable from a policy
that works.** When you add a named mode:

- add the branch that reads it *in the same change* as the caller that passes it;
- make the default case assert, or at minimum enumerate the names it accepts, so
  an unrecognised one is a failure rather than a shrug;
- if a comment says what a mode does, that sentence is a test you have not
  written yet.

## Related

- [a-scroll-container-clips-to-itself.md](a-scroll-container-clips-to-itself.md)
  — the same capture produced both lessons.
- `docs/guide/11-device-verification.md` — why the phone found this and the
  emulator did not: over a plain grey baseplate an inset backdrop looks fine.
