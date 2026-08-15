# A composition needs a base term, and writing is how you lose it

**Found:** 2026-08-15, closing ADR-0026's deferred question — *can an authored
`opacity` compose against the stylesheet's own value on a leaf, the way it
composes against the framework's channel value on a group?*

**Answer:** no, and the reason generalizes well past opacity.

## The shape

A composition is `f(base, mine)`. Owning a property means writing `mine`.
Composing means writing `f(base, mine)` — which is only possible if you can
**read `base` after you have written**. The whole design rests on a read nobody
thinks to check, because in every ordinary case reading is free.

Roblox's styling system is a case where it is not. `Instance:GetStyled(prop)` is
the only way to read a sheet-resolved value, and it reports **the actual winner**
— so after one explicit write it returns your own write, forever:

```
disabled, untouched      GetStyled=0.6   raw=0     <- the rule is the winner
after the composed write GetStyled=0.5   raw=0.5   <- you are the winner
disabled again           GetStyled=0.5   raw=0.5   <- the rule is gone
unparent + reparent      GetStyled=0.5   raw=0.5   <- and it does not come back
```

The base term is not stale. It has stopped existing.

## What makes it dangerous is that the loop still looks alive

The natural fix is "subscribe and re-compose".
`GetStyledPropertyChangedSignal` exists, and it still fires after the defeat — so
the implementation looks connected and healthy while reading its own tail. Built
and watched, a label at `opacity = 0.5` re-composing on every state transition:

```
0.500 -> 0.750 -> 0.875 -> 0.938 -> 0.969 -> 0.984 -> 0.992 -> 0.996 -> 0.998
```

Four disable/enable cycles and the label is gone. A silent failure would have
been kinder; this one produces a plausible-looking mechanism that converges on
invisible, and it converges *at the speed the player uses the control*, so it
would have shipped looking fine and rotted in the field.

## Rules

1. **Before designing a composition, ask how the base is read — and read it
   again after a write.** "The framework composes at the one write site" is only
   a design if `base` survives the write. One probe answers it.
2. **A signal that still fires is not evidence that a value is still true.** The
   defeat took the value; it left the notification. Check what the callback
   *reads*, not whether it runs.
3. **"Permanently defeats the rule" undersells this class.** That phrasing
   invites workarounds — cache it, watch it, re-assert it — and every one of them
   needs the read that is gone. Say *the base becomes unreadable* and the whole
   family closes at once.
4. **Count the properties before calling it "one write site".** A leaf's alpha is
   `TextTransparency` plus a background plus an icon plus chrome slots plus a
   stroke — an **open** set a theme package extends. And a rule-created phantom
   modifier (`::UIStroke`) renders with **no instance at all**, so part of the
   paint has nothing to write to at any price.
5. **A rule edit is not an animation channel.** A `StyleRule` property change
   took **3 frames** to reach `GetStyled`. Anything that must land in the frame it
   paints cannot go through the cascade.
6. **The offerable-term rule that fell out of it** (ADR-0029): a term is
   offerable on a class when ONE engine property that no rule owns expresses it
   for that class's whole painted output. `UIScale.Scale` and `GuiObject.Rotation`
   pass everywhere; alpha passes only where the instance can be a `CanvasGroup`.
   That is the whole reason `scale`/`rotation` are on 21 classes and `opacity` on
   two.

## And the corollary for the repaint sweep

`docs/lessons/a-re-solve-does-not-repaint.md` says every adapter-owned paint that
resolves a palette must join `screen_paint.refreshThemedPaint`. The entry
condition is worth stating positively, because this round had to answer it:
**a paint joins the sweep iff its value resolves a palette.** The presentation
composition resolves none — its terms are a framework number and an author number
— so a theme commit cannot make it stale, measured with the caption colour as the
positive control. A future term that reads a role, a token or `paletteTheme()`
joins the sweep the day it is written.
