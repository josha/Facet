# A compensation is only true for the value it was computed from

**Found:** 2026-08-13, Studio, Facet-Showcase, Compact Pointer, the `row-actions`
Table surface. Director: *"the left side of the mark read button is cutoff"*
(`cutoff.png`).

## The shape

`screen_chrome.applyFullBleed` makes a decoration cover its host's **own** box by
cancelling the host's `UIPadding`: `Position = (0, -left)`, `Size = (1, left + right)`.
It reads that padding **once**, when it runs.

`screen_target.create` gives a Button a default `UIPadding` of `style.space.s + 4`
and then calls `syncChrome`. The authored `padding` prop arrives **afterwards**,
through `applyProp`, rewrites the `UIPadding`, and used to re-run nothing.

So the decoration cancelled a number the host no longer carried. And a stale
full-bleed does not shrink the decoration — it **moves and grows** it, because the
decoration is laid out inside the host's *padded* content box and then pushed back
out by the older, larger number.

## The measurement (same instrument, one frame)

| button | `UIPadding` | deco offset | overhang L / R |
|---|---|---|---|
| `ModeBar/ModeList` | 12 | −12 | 0 / 0 |
| `TableToolbar/EditToggle` | 12 | −12 | 0 / 0 |
| `RowActions-m1/Content/Row/Hit` | 12 | −12 | 0 / 0 |
| the swipe tray's `Action:read` plate | **8** | **−12** | **−4 / +4** |

```
plate  [10.0 ..  93.0]
deco   [ 6.0 ..  97.0]      4px outside its own host, every side
Body   [10.0 .. 403.0]      ClipsDescendants = true
```

The tray plate is the one button on that screen with an authored `padding` prop,
and the only one whose decoration is wrong. Its left edge sits **exactly** on the
Table body's clip edge, so the 4px to the left — the border and both corners — is
cut away, while the 4px to the right lands in the 6px `rowGutter` and survives.
"The left side is cut off, the right side is not" is the geometry, not a coincidence.

## Why nothing caught it

Every rect involved is flush. The solver models layout; the padding is an engine
object it never sees, and the overhang is paint. The headless sweep reports zero
overflow on every frame — the same blind spot as
[`decoration-paints-to-the-edges.md`](decoration-paints-to-the-edges.md) and the
close-flight overhang fixed in `6469a8e`.

## The rule

**Whoever writes the value owns every compensation derived from it.** The padding
write is the single authority for a host's `UIPadding`, so it is the only place
that can know a compensation has gone stale — hence
`screen_chrome.refitFullBleed(handle)`, called from both halves of
`elseif prop == "padding"`. Same shape as `refitIconArt`, which exists because a
rect can arrive after the icon it sizes.

Generalise it: when a derived value is cached at one seam and its input is rewritten
at another, either recompute at the write or make the cache impossible. A comment
saying "re-applied on every sync" is not a guarantee that the sync runs after the
write that matters — it did run, and it ran *first*.

## Related

- `tests/chrome_padding_refit.spec.luau` — the checks, with the measured numbers.
- [`measure-the-requirement-not-the-render.md`](measure-the-requirement-not-the-render.md),
  [`a-fixed-box-cannot-hold-a-themes-frame.md`](a-fixed-box-cannot-hold-a-themes-frame.md)
  — the same "painted at a size nobody measured" family.
