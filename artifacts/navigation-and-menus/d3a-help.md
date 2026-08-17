# D3a — `help`: the plate the player pulls, and the check that keeps it honest

**Landed 2026-08-16.** Gate row `d3a-help`. Brief:
`docs/plans/navigation-and-menus-brief.md` §2 D3; director ruling §6.2; director
call `artifacts/navigation-and-menus/additive-vs-net-new.md` §3.

---

## What shipped

| | |
|---|---|
| `help` | a construction-only string prop on `Text`, `Button`, `Toggle` and `TextField` (`src/blueprint_schema.luau`) |
| `src/present/help_plate.luau` | the dwell, the resolver, the presentation and the declaration report |
| `presenter.help()` | the plate's state, schema `luauui-help-dump/1` |
| `presenter.helpDeclarations()` | every live declaration and the routes that actually reach it |
| `text_audit.helpRoutes` | the reachability check — two findings, one of them un-waivable |
| `presentAnchored{ chrome = true }` | a D1 extension: a LAYER, not a surface |
| `focus_graph.pushScope` | a non-trapping `initialFocus = "none"` no longer blanks the ring |
| Specs | `tests/help.spec.luau` (25 cases), registered in `tests/run.luau` |
| Consumer rider | `games/RascalRally/code/tests/luauui_help_callout_contract.spec.luau` |

## The public surface, verbatim

```
UI.Button{ help = "Posts this avatar to the Marketplace" }
-- also legal on UI.Text, UI.Toggle and UI.TextField. Construction-only:
-- binding a Readable is refused, naming the rebuild idiom.

presenter.help() -> {
  schema = "luauui-help-dump/1",
  present, path, labelPath, sourcePath, source, helpText, declarations,
  dwelling, text,
}

presenter.helpDeclarations() -> { [path] = { text, hover, focus } }

text_audit.helpRoutes(declarations, rects, opts?) -> { Finding }
--   opts.convenience  path prefixes or a predicate; waives `helpOnlyRoute`
--                     and NEVER `helpNoRoute`
```

| Input class | Show | Hide |
|---|---|---|
| mouse / pointer | hover, after a 0.45 s dwell | the pointer leaves, or the view is activated |
| keyboard / gamepad | on focus, immediately | on blur |
| **touch** | **nothing** | — |

## How "it binds no gesture" is proved

D2 asked for a claim a spec could fail on. There are three, and they fail from
different directions:

1. **At the adapter seam, in a world with both classes live.** A node declaring
   only `help` gets `discloseZone.hover` and `discloseZone.longPress == nil`,
   while a `disclose` node beside it gets both — *"HELP BINDS NO GESTURE: with
   both classes live it wires hover and never a press"*. The renderer's wiring
   is what would have to change, and the mutation that removes the `discloses`
   guard from the press half reddens this case and the pure-touch one.
2. **In the game's own build**, through the same seam, because ten shipped
   Sponsor surfaces declare `UI.Text{ disclose = true }` and the long press is
   the only touch route those labels have.
3. **D2's source sweep**, untouched: *"exactly two constructs know the word
   long-press, and `help` is not going to be a third"*. Nothing under
   `src/present/help_plate.luau`, `src/present/callout_queue.luau` or
   `src/controls/callout.luau` contains the word, and the gate greps for its
   absence in all three.

## The check, and why it is not `clippedEssential`

`text_audit.clippedEssential` accepts the *declaration* `disclose = true` and
stops; it never asks whether the gesture that reaches the plate still exists.
That is D2's own finding, and it is why deleting the long-press binding would
have been an accessibility regression no check could see. `helpRoutes` does the
same job for `help` and keeps the two questions apart on purpose:

| Finding | What it says | Waivable |
|---|---|---|
| `helpNoRoute` | nothing engages this help on **any** live input class | **No.** A declaration cannot answer whether a gesture exists |
| `helpOnlyRoute` | the screen paints this sentence nowhere else, so a player who never hovers cannot read it | Yes, `opts.convenience` |

**The routes are measured, not declared.** `presenter.helpDeclarations()` walks
the mounted tree; `hover` is the LIVE pointer class as the renderer wired it and
`focus` is `focus_map`'s own `FOCUSABLE` set. The same fixture reports
`hover = true` in a pointer world and `hover = false` in a pure-touch one, and
the spec asserts both.

## The plate is chrome, and that was a discovery rather than a setting

The first implementation presented it as an ordinary surface with
`responder = "passive"` and `initialFocus = "none"` — the shape a HUD overlay
uses. It failed two of its own cases, and the reason is worth writing down:

> **A presented surface pushes a focus scope even when it holds nothing
> focusable, and a scope with no members is still the TOP scope.** Measured: the
> next arrow press after a plate appeared had nowhere to go, and the ring on the
> control being described went `nil`.

So D1's seam gained a **chrome mode**: `presentAnchored(panel, { chrome = true })`
hand-mounts its own controller — no stack, no focus scope, no input context, no
catcher — and keeps everything D1 actually owns (the solver, the tail, the safe
box, the moving-source cadence). The disclosure plate and the toast strip were
already doing exactly this by hand; this writes it down once instead of a
fourth time, and it makes "the help plate cannot take navigation" **structural**
rather than configured. `chrome` and `modal` are refused together.

**No arrow tail**, deliberately: Apple's help tag has none, and the tail is what
distinguishes the app-pushed coach mark (`newCallout`) from the plate a player
pulled.

> **SUPERSEDED 2026-08-16 (device review, F4).** The plate now carries D1's arrow
> tail. The director asked for *"some sort of pointer... to indicate which control
> the tooltip is attached to"*, and the reasoning above did not survive contact:
> what tells the two constructs apart is who raises them and whether they retire,
> not the stem. What the stem carries is which control the sentence is about, and
> a `align = "start"` plate under a row of same-sized buttons leaves that open.
> Same seam, so D1's suppression rule came with it.

## One shipped behaviour changed: `pushScope`

`initialFocus = "none"` meant "do not invent focus for me" (its own comment says
so) and *implemented* "take the ring off everyone". For a **trap** that is
right: a modal covers the screen underneath and the ring must not stay painted
on something unreachable, and `popScope` restores it from the trap stack. For a
**non-trapping** scope it is a surface with no claim on the ring reaching out to
un-focus the screen it is annotating.

Now: a trap still blanks it; a non-trapping scope leaves it alone. Both
directions are pinned in the Rascal Rally rider, because every Sponsor surface
this game presents goes through that call. The full LuauUI suite was run with
and without the change and the delta is zero.

## Evidence

| ID | Behaviour | Level | Driver | Status |
|---|---|---|---|---|
| NM-D3a-1 | Pointer hover presents after a dwell; leaving and activating retire it | E1 | `tests/help.spec.luau` "pointer hover presents the help plate only after the dwell elapses" + 3 | PASS_AUTOMATED |
| NM-D3a-2 | Focus presents immediately; blur retires | E1 | same file, 2 cases | PASS_AUTOMATED |
| NM-D3a-3 | **Nothing on touch**, and no gesture is bound | E1 | same file, 3 cases, read at the adapter seam | PASS_AUTOMATED |
| NM-D3a-4 | The disclosure plate outranks it; never two plates | E1 | same file, "a truncated DISCLOSED label outranks help…" | PASS_AUTOMATED |
| NM-D3a-5 | Chrome: no focus stop, no scope, dies with its surface | E1 | same file, 2 cases | PASS_AUTOMATED |
| NM-D3a-6 | Player copy wraps at ~1.4x rather than clipping | E1 | same file + `LT8-CTL` sweep of the plate | PASS_AUTOMATED |
| NM-D3a-7 | Closed spec: a bound `help` is refused by name | E1 | same file | PASS_AUTOMATED |
| NM-D3a-8 | `helpRoutes`: both findings, the waiver, and what the waiver cannot touch | E1 | same file, 7 cases | PASS_AUTOMATED |
| NM-D3a-9 | The declarations come off a REAL mount, and change with the live class | E1 | same file, 2 cases | PASS_AUTOMATED |
| NM-D3a-10 | No device branch in any new module | E1 | same file, source sweep | PASS_AUTOMATED |
| NM-D3a-11 | The live RascalRally consumer is current, and its a11y route survives | E1 | `luauui_help_callout_contract.spec.luau` | PASS_AUTOMATED |
| NM-D3a-12 | **Hover dwell as a hand feels it** — 0.45 s on a real mouse, and whether a pad player ever finds the plate | E4 | a physical/pointer pass | PENDING_PHYSICAL |

## Mutation ledger — eight, every one seen to fail

| # | Mutation | Reddened |
|---|---|---|
| M1 | `syncHelpFocus` drops the `focusVisible` gate (help on touch) | `a touch tap moves focus but presents nothing…` + `activating the view takes it away…` |
| M2 | the renderer's press half loses its `discloses` guard (help binds long-press) | `HELP BINDS NO GESTURE…` + `a pure-touch world wires NO engagement zone…`, and the game rider's `A11Y: help BINDS NO GESTURE…` |
| M7 | the disclosure plate no longer outranks help | `a truncated DISCLOSED label outranks help on the same engagement` |
| M8 | the plate presented as a SURFACE instead of chrome | 3 cases — the pointer-leave, the move-between-labels and the focus-blur routes |
| M9 | `opts.convenience` silences `helpNoRoute` too | `BUT NO WAIVER REACHES THE GESTURE…` |
| M10 | truncated text counts as "the screen says it" | `…and neither is TRUNCATED text — an ellipsis is not the sentence` |
| M11 | `HELP_DWELL = 0` | `pointer hover presents the help plate only after the dwell elapses` |
| M13 | the `pushScope` fix reverted | 3 callout cases, and the game rider's `THE FOCUS-GRAPH CHANGE, both directions…` |

## What this row does NOT claim

- **No device evidence.** Studio cannot synthesize a real pointer class, and an
  injected event arrives as `Touch` rather than a mouse move — so whether 0.45 s
  reads as a decision, and whether a pad player discovers the plate at all,
  are physical rows.
- **No accessibility hint.** Apple's `.help(_:)` also sets a VoiceOver hint.
  LuauUI has no such channel, so that half has no analogue here and is not
  claimed as parity.
- **No shipped consumer.** Only the gallery scenario declares `help`; the game
  declares none, and its rider measures that rather than assuming it.
