# A header comment describes the path it was written for — say which one

**Found:** 2026-08-12, by the game director, catching the orchestrator repeating a
stale claim back to him.
**Cost:** an agent told the director that the showcase's two picker chips were
still two unlaid-out surfaces held apart by hard-coded offsets, and proposed an
architecture review on that premise. The defect had already been fixed. The
proposal was aimed at a problem that no longer existed.

## What happened

`examples/gallery/client/theme_picker.luau` opens with a long, well-written
header describing the picker as a floating overlay, and carries constants with
careful reasoning attached:

```lua
theme_picker.BAR_HEIGHT = 62
theme_picker.CHIP_LABEL_CHARS = 14   -- "what fits beside the demo picker's chip
                                     --  on the narrowest phone portrait (320px)"
-- where this chip starts, measured from the strip's left edge … so 154 clears it
```

Every word of that is true — **of the standalone path**, where a picker is used
on its own. The showcase does not use it. `examples/gallery/client/init.client.luau`
(~428-470) composes instead, and says so:

> ONE CHROME SURFACE, LAID OUT BY THE SOLVER. The two chips used to be two
> presented surfaces held apart by a hard-coded offset, because neither could
> measure the other. On a real iPhone 15 Pro the text renders wider than the
> offset assumed and they OVERLAPPED — twice reported from a device.

Both comments are accurate. Read in the wrong order, they describe two different
architectures, and the reader has no way to tell which one ships.

## Why the usual rule did not catch it

"A stale comment is a bug" (`ENGINEERING.md`) is aimed at comments that became
*false*. This one never became false. It became **ambiguous about its scope** —
it describes a path that still exists, still works, and is no longer the one the
product takes. No freshness check finds that, because nothing about it is wrong.

The tell was available and got skipped: the constants carried device-specific
reasoning ("on the narrowest phone portrait Roblox reports") for a problem the
composing site says it solved structurally. When a module explains how it works
around a limitation, and a sibling module says that limitation was removed, one
of them is describing history.

## The rule

**A header that documents a mechanism must name the caller it is written for
whenever more than one path exists**, and point at the other one.

```lua
-- STANDALONE PATH ONLY. These constants hold the chip clear of the demo
-- picker's when each is presented as its OWN surface and no solver lays them
-- out together. The SHOWCASE does not take this path: it composes both chips
-- into one screen (examples/gallery/client/init.client.luau, "ONE CHROME
-- SURFACE"), where the solver owns the row and no offset is needed. Changing
-- these numbers cannot affect the showcase.
```

Three parts, and all three earn their keep: **which path**, **what the other
path does instead**, and **the consequence of getting it wrong** — that last one
is what stops the next reader generalising from the wrong file.

## Where it applies

Anywhere the repo carries a composed form and a standalone form of the same
thing: the pickers, any control with a hosted and a standalone mode
(`row_actions` has exactly this shape — standalone `newRowActions` versus hosted
`Table`/`VirtualList` integration), and any adapter seam with a fake and a live
implementation.

The cheap version of this rule, worth applying even when there is only one path
today: if a comment explains a *workaround*, say what it is working around. A
workaround whose reason is unstated outlives the reason.
