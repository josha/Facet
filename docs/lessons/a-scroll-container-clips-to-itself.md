# A scroll container clips to itself — so the surface goes ON it, not around it

**Found:** 2026-07-26, a physical phone, showcase place. **Cost:** three wrong shapes
before the right one, two of them shipped to a device and photographed.

## The symptom

A themed picker panel opened as a rounded card. A hard rectangle sliced a row of
theme chips in half; the card's own rounded corner continued *past* the cut; and
the scrollbar floated at the far right of the screen with no visible relationship
to the card. The director's words were "a professional UI designer would not approve of
this", and they were right.

## The three shapes, in the order they were written

```lua
-- 1. WRONG — the scroller is OUTSIDE the card, so it clips the card.
UI.ScrollView({ children = { UI.VStack({ surface = "raised", padding = "s", … }) } })

-- 2. STILL WRONG — the clip is right, but now there are two raised surfaces:
--    a rounded panel inside a rounded panel, with a gutter and no meaning to it.
UI.VStack({ surface = "raised", padding = "s", children = {
  UI.ScrollView({ children = { UI.VStack({ … }) } }) } })

-- 3. RIGHT — one node is both.
UI.ScrollView({ surface = "raised", padding = "s", gap = …, children = sections })
```

## Why (3) is the framework's own answer

`ScrollView`'s schema is `merge(BOX, CONTAINER_LAYOUT, …)` — it already accepts
`surface`, `padding`, `gap` and the rest, exactly like `VStack`. There was never
a reason to wrap it in a container to give it a look.

And the result is not merely tidier, it is *unbreakable*: the clip rect and the
painted card are the same box, so the scroller cannot clip its own rounded
corners, the scrollbar is inside the card by construction, and the padding
applies once.

## The rule

**A container that clips is a container. Give it the surface.**

If you find yourself wrapping a `ScrollView` to make it look like something, or
wrapping something in a `ScrollView` to make it scroll, stop: one node does both.
The same holds for any future clipping container.

## The related trap, one layer up

A decoration layer — a scrim, a backdrop — must be presented
`rootPolicy = "edgeToEdge"`, or it paints a rectangle *inside* the safe area with
the world showing around it. Safe areas exist so that **content** is readable and
reachable; a background is neither. See
[decoration-paints-to-the-edges.md](decoration-paints-to-the-edges.md).
