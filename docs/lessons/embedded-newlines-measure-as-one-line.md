# A `\n` inside `UI.Text` is drawn but not measured

**Found:** 2026-08-04, roadmap Step 9 (performance lab), driving the lab's own
counter block in a live Studio session.

## What happened

The lab overlay published its six counter lines as ONE `UI.Text` whose value was
the lines joined with `\n` — deliberately, to keep a development overlay from
re-solving six nodes per update. In Studio the block rendered as six lines and was
clipped after two: the solved box was `879 x 29`, and the last four lines were
drawn outside it.

The solver's own text facts say why:

```
/S/Multi  text = "one\ntwo\nthree\nfour\nfive\nsix"
          lines = 1   naturalLines = 1   policy = "wrap"   truncated = false
```

The engine honours the newlines when it draws. The measure pass does not: it
counts wrapped lines against the available width and never looks for explicit
line breaks, so a six-line string reserves a one-line box and reports
`truncated = false` while four lines of content are invisible.

This is the painted-vs-measured family again (`docs/lessons/one-word-two-subsystems.md`):
two subsystems answering the same question differently, with the cheaper one
winning the geometry.

## Reproduction (headless, no engine needed)

```lua
local h = pres.present(UI.Screen({ id = "S", children = {
    UI.Text({ id = "Multi", text = "one\ntwo\nthree\nfour\nfive\nsix", textSize = 12 }),
}}))
pres.refresh()
print(h.controller.textAt())   --> naturalLines = 1
```

## What to do until it is fixed

**Author one `UI.Text` per line.** A `VStack` of N text nodes measures correctly,
wraps correctly, and each line participates in the overflow ladder on its own. The
performance argument for joining them is real but small, and it is not worth
paying in invisible content — the lab's own overlay was changed to a per-line
stack the moment this was found.

Do NOT reach for `lineLimit` to "fix" this: that bounds how many lines a WRAPPED
string may occupy and has nothing to say about a string that already contains its
own breaks.

## Why this was not fixed on the spot

The measure path is Step 8.5 territory — exact-once preferred-text offsets, the
premeasure cache and its boot-window corrections, the truncation/disclosure
ladder — and all of it is pinned by a large gated suite. Teaching `naturalLines`
about `\n` is a small change with a wide blast radius (every reserved text box,
both reference themes, four preference values), so it is recorded here and as
decision packet PLN-6 rather than slipped into a performance stage.
