# A fixed box cannot hold a theme's frame

**Found:** 2026-07-26, iPhone 15 Pro, showcase place. **Cost:** two controls
shipped with labels the theme quietly ate.

## The symptom

Two unrelated controls, same shape of failure, only under packages that skin
their slot with real art:

| Control | Box | Under Glossy Touch | Under Pixel Quest |
|---|---|---|---|
| Table's `Edit` toggle | `fixed` 56 × 24 | drew **"E"** | drew an **empty plate** |
| TextInput's clear chip | `fixed` 28 × 28 | ✕ drew **outside** the plate | same |

Studio Neutral and Classic Desktop looked perfect, which is exactly why it
survived so long: the flat themes reserve nothing, so there was nothing to eat.

## The cause

A theme's `contentInsets` are **solver-visible**: `snapshot.resolve` folds them
into `chromeInsets`, and the renderer adds them to the padding of the node that
carries the slot. That is correct — a carved border is room the content must
clear.

But padding is spent **inside** the box, and these boxes could not grow:

```
Edit toggle, Glossy Touch:  56 − 2×6 (own padding) − 2×14 (the art's frame) = 16px
                             ...for the word "Edit" at 17px type.

Clear chip, any flat theme:  28 − 2×12 (a Button's default text inset)       =  4px
                             ...for the × glyph. Before a package says a word.
```

The numbers 56, 24 and 28 were chosen against a theme with no frame. They are
not sizes; they are sizes *plus an assumption*.

## The fix

`minMax` with the token as the **floor**, not `fixed` as a cage:

```lua
-- before                                    -- after
width  = { type = "fixed", px = TOKEN }      width  = { type = "minMax", min = TOKEN }
height = { type = "fixed", px = TOKEN }      height = { type = "minMax", min = TOKEN }
```

Flat themes are unchanged to the pixel (content is smaller than the floor, so the
floor wins); a skinning package grows the box for its own frame instead of
reserving that frame out of the label's room.

And for the clear chip, one more: `padding = 0`. A Button's default text inset
exists to keep a **word** off a plate's edge. A chip whose entire content is one
centred glyph wants none of it.

## The rule

**A control's fixed dimension is a promise it cannot keep under a theme it has
not seen.** Any box a theme may paint a frame on states a floor, not a size. Ask
of every literal in a reusable control: *what does this number assume about the
package?* If the answer is "that it has no border", it is a `minMax` min.

The same reasoning in reverse produced this round's other framework change: a
Table row's painted card and its cell content are **different nodes**, so the
reservation the renderer made on the painted one was inert, and the cells had to
read `chromeInsets.selection.*` as a theme metric to honour it. Reserving room is
only half of it — something has to *spend* the reservation.

## See also

- [`one-word-two-subsystems.md`](one-word-two-subsystems.md) — the other half of
  the same device round.
