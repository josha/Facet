# The leaf fade, measured — Studio probes L1–L4, W1, T1

**Date:** 2026-08-15. **Place:** `LuauUI-Showcase.rbxl`, Rojo-connected on
`examples/showcase.project.json` (port 34873).

**Sync proof, taken before any result was trusted.** `script_grep`'s line numbers
were 2–14 lines off the file on disk, which looks exactly like a stale place and
is not — the tool normalizes something before numbering. The check that works is
a byte count plus a string committed minutes earlier:

| module | disk bytes | DataModel bytes | carries `is REFUSED on UI.` | carries `GetStyled returns the ` |
|---|---|---|---|---|
| `src/blueprint.luau` | 70,915 | 70,915 | **yes** | no |
| `src/blueprint_schema.luau` | 103,853 | 103,853 | no | **yes** |

The two "no" cells are the negative control: each string lives in exactly one of
the two files, so the greps are reading real content rather than always
answering true. Both files match `cf275b3`, committed ~1 minute before the read.

---

## The question

ADR-0026 refused an authored `opacity` on a leaf because the write would land on
`TextTransparency` / `BackgroundTransparency`, which the native stylesheet owns.
The director asked whether the leaf could instead **compose** against the sheet's
value at the one write site, the way the group case composes against the
framework's channel value — nested opacity multiplies ([SW-141]).

A composition needs a **base term**. So the question is entirely: *can the
framework read what the sheet would have painted?*

## L1 — the base term is destroyed by the act of composing

A `TextButton` under a `StyleLink`, with two rules: `TextButton` →
`TextTransparency = 0`, and `TextButton:NonInteractable` → `0.6`.

```
1 enabled untouched      GetStyled=0    raw=0
2 DISABLED untouched     GetStyled=0.6  raw=0     <- the sheet's dimming, working
3 enabled again          GetStyled=0
   -- now the leaf fade: authored opacity 0.5 composed against the base the rule
   -- states.  T = 1 - (1 - 0) * 0.5 = 0.5
4 after composed write   GetStyled=0.5  raw=0.5   <- the base is GONE
5 DISABLED after write   GetStyled=0.5  raw=0.5   <- the dimming is GONE
6 unparent+reparent      GetStyled=0.5  raw=0.5   <- and it does not come back
7 GetStyledPropertyChangedSignal exists: function
```

Row 2 vs row 5 is the whole finding. `GetStyled` is the only way to read the
sheet's resolved value, and after one explicit write it returns **the write**.
The composition's base term does not merely go stale — it stops existing.

Row 6 matters because `docs/lessons/stylesheet-defeat-order-sensitive.md` records
that a write made *before* an instance first joins the styled tree is stomped by
the first style application. That escape hatch does not apply here: an instance
that has been tracked keeps its defeat across leaving and re-joining the tree.

## L2 — the two remaining designs, closed

```
a1 state flip, no write yet   fired=1  GetStyled=0.6    <- the signal works…
a2 state flip AFTER the write fired=1  GetStyled=0.5    <- …and now reports our own write
b  a StyleRule edit reached GetStyled after 3 frames
c  phantom ::UIStroke child instances on the leaf: []  count=0
```

* **a** — "subscribe to `GetStyledPropertyChangedSignal` and re-compose" fails,
  and fails *loudly rather than silently*: the signal still fires, so the naive
  implementation looks alive while reading its own output.
* **b** — "don't write the instance, animate the RULE" fails on latency alone: a
  rule edit takes **3 frames** to reach `GetStyled`. A 60 Hz fade needs the value
  in the frame. (It is also per-selector, not per-node, and the generator owns
  rule priorities — "cascade is infrastructure, not paint".)
* **c** — a `::UIStroke` rule renders a 3px ring with **zero child instances** on
  the leaf. Part of a leaf's painted output has no instance to write a
  transparency on *at all*, at any price. This one is independent of the defeat
  argument and cannot be engineered around.

## L4 — the honest attempt, built and watched

L3 established that our own write does *not* re-fire the signal (one write, one
sample), so the runaway is not per-frame. L4 flips `Interactable` four times with
the recompose connected — i.e. a button being used:

```
mount     base=0.000 -> wrote 0.500
signal#1  base=0.500 -> wrote 0.750
signal#2  base=0.750 -> wrote 0.875
signal#3  base=0.875 -> wrote 0.938
signal#4  base=0.938 -> wrote 0.969
signal#5  base=0.969 -> wrote 0.984
signal#6  base=0.984 -> wrote 0.992
signal#7  base=0.992 -> wrote 0.996
signal#8  base=0.996 -> wrote 0.998
FINAL raw=0.998046875   (1.0 = the label is gone)
```

A label declared at `opacity = 0.5` is **invisible after four disable/enable
cycles**, because the composition multiplies its own output back in every time
the control changes state. This is what "the base term is destroyed" costs when
someone builds it anyway.

## W1 — the wrap the refusal names, on a real native-styled surface

`UI.ZStack{ opacity = 0.5, children = { UI.Button{ label = "Buy", enabled } } }`,
mounted on `screen_target` with `nativeStyle` active (`nativeStyleInfo().active
= true`). Instances: the wrap is a real `CanvasGroup`, the button a `TextButton`.

```
1 DISABLED  GroupTransparency=0.5000  btn GetStyled(TextTransparency)=0.4000  raw=0.0000  Interactable=false
2 ENABLED   GroupTransparency=0.5000  btn GetStyled(TextTransparency)=0.0000  raw=0.0000  Interactable=true
3 DISABLED  GroupTransparency=0.5000  btn GetStyled(TextTransparency)=0.4000  raw=0.0000  Interactable=false
```

The fade is one property no rule owns, and the control's `raw` transparency is
**0 throughout** — LuauUI never wrote it, so the sheet's `:NonInteractable` rule
is still its only writer and the dimming moves with the state underneath the
group fade. This is ADR-0026 Decision 6 confirmed from the other end.

## T1 — an authored presentation term and a theme commit

The standing hazard (`docs/lessons/a-re-solve-does-not-repaint.md`): a theme
commit re-derives everything the **solver** reads and nothing the **adapter**
paints, so every adapter-owned paint that resolves a palette had to join
`screen_paint.refreshThemedPaint` or go stale. Does an authored `opacity` have to
join it?

`UI.ZStack{ opacity = 0.4, scale = 0.75, rotation = 20 }` under Studio Neutral,
then `theme_controller.install(adapter, fantasy_parchment.build(themes), { env })`:

```
1 studio-neutral GroupTransparency=0.6000  UIScale=0.7500  Rotation=20.0000  capTextColor=0.925,0.937,0.961
2 AFTER swap     GroupTransparency=0.6000  UIScale=0.7500  Rotation=20.0000  capTextColor=0.204,0.157,0.102
3 a sec later    GroupTransparency=0.6000  UIScale=0.7500  Rotation=20.0000  capTextColor=0.204,0.157,0.102
```

**The caption colour is the positive control** — it moves from Studio Neutral's
near-white to Fantasy Parchment's dark brown, so the commit demonstrably landed.
All three authored terms are unchanged across it.

**No sweep is needed, and the reason is a rule rather than luck.**
`refreshThemedPaint` exists for adapter-owned paint that **resolves a palette** —
a `tint`'s blend, a `Path`'s stroke role, the focus ring's accent. The
presentation composition resolves none: its terms are the framework's channel
value and the author's number, and neither is theme-derived. A theme commit
cannot make stale a value that never read the theme. (Stated as the entry
condition, so the *next* authored paint knows which side it is on: **if the
composition contains a palette term, it joins the sweep; if it contains none, it
cannot go stale.**)

## Probe hygiene

Every probe destroyed what it mounted and verified absence in the same call:
`L1Probe`/`L1Sheet`, `L2Probe`/`L2Sheet`, `L3Probe`/`L3Sheet`,
`L4Probe`/`L4Sheet` all read back `nil`. Two LuauUI roots (`LuauUI_W1`,
`LuauUI_Probe0`) survived `presenter.dismiss` — dismiss detaches the surface but
leaves the root `ScreenGui` — and were destroyed by name in a follow-up call that
confirmed `remaining=[]`, `stylesheets in PlayerGui = 2` (the showcase's own two)
and `showcaseStillUp = true`. `LuauUI_T1` likewise verified gone.
