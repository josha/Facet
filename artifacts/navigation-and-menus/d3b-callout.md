# D3b — `Callout`: the plate the app pushes, and the state it refuses to keep

**Landed 2026-08-16.** Gate row `d3b-callout`. Brief:
`docs/plans/navigation-and-menus-brief.md` §2 D3; director ruling §6.2; director
call `artifacts/navigation-and-menus/additive-vs-net-new.md` §4.

Reference: `docs/plans/reference-media/2026-08-16-roblox-app-navigation/f1-avatar-editor.jpeg`
— the "Post Avatars to Marketplace" plate with an arrow tail pointing up at a
top-right `+`. **That is a Callout, not a tooltip**, and it is visible unchanged
across the whole of `r3-segmented-control.mov` while the player operates the
controls beneath it.

---

## What shipped

| | |
|---|---|
| `LuauUI.newCallout` | `src/controls/callout.luau` — eligibility, invalidation, the plate, the persistence boundary |
| `src/present/callout_queue.luau` | "at most one on screen, a queue not a pile" — a driver over `toast_schedule`, not a second scheduler |
| `presenter.presentCallout` / `releaseCallout` / `callouts()` | the queue's public seam, schema `luauui-callout-queue-dump/1` |
| `contribution.bindPresent` | gained a fourth and fifth argument, additively (D2's precedent) |
| `callout.plate(UI, opts)` | the plate exported so it has ONE definition — the control mounts it, the large-text matrix sweeps it |
| Specs | `tests/callout.spec.luau` (32 cases), registered in `tests/run.luau` |
| Scenario | `examples/gallery/scenarios/callout.luau`, in the ORDER, in `demo_picker.DEMOS`, in the overflow sweep |
| Consumer rider | `games/RascalRally/code/tests/luauui_help_callout_contract.spec.luau` |

## The public API, verbatim

```
LuauUI.newCallout(LuauUI, core, spec) -> { blueprint, api, dump, dispose }

spec = {
  id?           = "Callout",
  anchor        : Blueprint,   -- REQUIRED: the node the plate points at
  content       : Blueprint,   -- REQUIRED: the plate's body, not a string
  dismissLabel? = "Got it",
  edge?         = "bottom",    -- "top" | "bottom" | "leading" | "trailing"
  align?        = "center",    -- "start" | "center" | "end"
  tail?         = true,
  priority?     = 0,
  -- the CALLER'S state, read and never written
  seen?         : Readable<boolean>,
  sessions?     : Readable<number>,
  afterSessions?: number,
  featureUsed?  : Readable<boolean>,
  onRetire      : (reason) -> (),  -- REQUIRED
  onShow?       : () -> (),
  onHide?       : (reason) -> (),
}

api = { eligible() -> boolean, present() -> boolean, dismiss(reason?),
        invalidate(reason?), state() -> "waiting"|"queued"|"showing"|"retired",
        isShowing: Signal, retired: Signal }
```

`blueprint` is **the caller's own anchor node** carrying an input contribution —
no wrapper, no layout change, the `newMenu` shape. Retirement reasons are
`"dismissed"`, `"featureUsed"`, `"invalidated"` and `"seen"`.

> **Apple's warning, verbatim, because it is the design constraint and not a
> footnote:** *"Use tips sparingly… Don't use tips to guide people through your
> app, or for advertising and promotion purposes."*

## Eligibility, invalidation, and exactly where the persistence boundary sits

Every eligibility rule is a **read** of something the caller owns:

- `seen == true` → never eligible (show once per player);
- `sessions < afterSessions` → not yet (show after N sessions);
- `featureUsed == true` → never (only until the feature is used).

Invalidation is permanent, by contract rather than by state: `retire(reason)`
reports **once**, `retired` latches, and `eligible()` refuses forever after — so
a second `present()` in the same session cannot bring it back. `featureUsed` and
`seen` are *observed*, so a callout dies on the frame the player does the thing
it was pointing at, including while it is on screen.

**The boundary is one function call.** The framework's entire side of persistence
is `pcall(spec.onRetire, reason)`. It writes nothing, anywhere. `onRetire` is
**required** at construction, because a coach mark nobody can persist is one that
comes back every session and the author would find that out from a player. The
spec drives a retirement and asserts the caller's `seen` signal is untouched —
counted through an observer, not eyeballed — and the game rider carries the same
case, because for Rascal Rally a quiet write would land in a live profile.

The gallery scenario puts the boundary on screen as two separate readouts: *what
the framework reported* and *what this app chose to save*.

## Never blocks — driven, not asserted

| Claim | How it is proved |
|---|---|
| Not a modal | it presents through `present`, not `presentModal`; the base screen keeps its own focus order and no `/Callout` path appears in it |
| The ring does not move | `presenter.focus.focused` is identical before and after `present()` |
| The pointed-at control stays operable | a real `adapter.tap` on the `+` **counts an activation** — a swallowed tap looks identical from outside — and the plate is still up afterwards |
| A tap away retires it | driven through the presenter's own catcher path at a real Zone-B coordinate |
| Every class can retire it | pointer/touch tap the `Dismiss` row (44px floor asserted); keyboard/gamepad reach it with **one arrow press** and press Return / ButtonA, and the ring returns |

**The plate stays up when the anchor is pressed, and that is the reference
behaviour** rather than a gap: in `r3-segmented-control.mov` the coach mark is
visible and unchanged while the player works the controls beneath it. What
retires it is the app noticing its feature was used.

## The queue is `toast_schedule`, configured

`maxVisible = 1` is the whole rule. Priority ordering, the queue cap, FIFO within
a priority, the read floor priority may never truncate, and a reason code on
every retirement all arrive with the shipped model. Two configuration choices are
worth stating:

- **A duration no session reaches.** A toast has been read after four seconds; a
  coach mark waits for the player. `toast_schedule` measures duration against an
  injected clock, so "never times out" is spelled as a finite number rather than
  `math.huge` — which the model's own `isFinite` guard would reject and silently
  replace with the four-second toast default.
- **The read floor is left at the model's own**, so a more urgent callout waits
  for the one on screen to have been readable. That is why the queue steps its
  clock from the presenter's tick rather than not at all.

## The f1 fixture

Reproduced at 390×844: the plate hangs **below** a top-right `+`
(`edge = "bottom"`, `flipped = false`), its body is **shifted left**
(`shift < 0`), and the arrow still points **up at the button**
(`tailSuppressed = false`, `tailX` inside the `+`'s own span). All three are D1
placement decisions; what this proves is that the construct asks for the right
ones.

## The gallery scenario

`examples/gallery/scenarios/callout` — "Two plates, and who raised them":

- the **f1 plate** under a top-right `+`, tail and all;
- a **press counter** under it, which is the non-blocking claim on screen rather
  than in a document: the `+` keeps counting while the coach mark points at it;
- a **second coach mark** on a second anchor, so the queue is something a player
  can watch instead of a sentence — ask for both and only one is ever up;
- the **persistence boundary** as two readouts, "what the framework reports" and
  "what THIS app chose to save";
- and both anchors carry **`help`**, so the same screen holds the pulled plate
  and the pushed one — with the help sentences also printed in the body copy,
  which is exactly the rule `helpRoutes` enforces.

Its buttons are ordinary controls with their own callbacks, so a player drives
the whole thing by hand; the scenario runner drives the same four steps by name.
It is swept by `tests/overflow_sweep.spec.luau` at every viewport, preference and
theme package. **The pinned 44px `+` came out** in the first sweep: under the
ornate reference package a 44px square control has to give its own chrome inset
back, and the sweep files that at every viewport. The 44 is a fact about the
*screenshot*, asserted in `tests/callout.spec.luau` where it belongs; the
scenario lets the theme size its own controls.

## Evidence

| ID | Behaviour | Level | Driver | Status |
|---|---|---|---|---|
| NM-D3b-1 | Eligibility: unseen, `seen`, `afterSessions`, `featureUsed` | E1 | `tests/callout.spec.luau`, 4 cases | PASS_AUTOMATED |
| NM-D3b-2 | Invalidation is permanent, reported exactly once | E1 | same file, 2 cases | PASS_AUTOMATED |
| NM-D3b-3 | **The framework writes no player state** | E1 | same file, counted through an observer | PASS_AUTOMATED |
| NM-D3b-4 | Closed spec; a missing `onRetire` is an authoring error | E1 | same file, 2 cases | PASS_AUTOMATED |
| NM-D3b-5 | At most one on screen; a queue ordered by priority | E1 | same file, 3 cases | PASS_AUTOMATED |
| NM-D3b-6 | Never blocks, every half driven | E1 | same file, 4 cases | PASS_AUTOMATED |
| NM-D3b-7 | Four input classes retire it; the 44px floor holds | E1 | same file, 5 cases | PASS_AUTOMATED |
| NM-D3b-8 | The f1 fixture: below, shifted left, arrow up | E1 | same file | PASS_AUTOMATED |
| NM-D3b-9 | Blueprint content; ~1.4x copy wraps rather than clipping | E1 | same file + the `LT8-CTL Callout-plate` sweep | PASS_AUTOMATED |
| NM-D3b-10 | Deterministic dumps, both schemas | E1 | same file, 2 cases | PASS_AUTOMATED |
| NM-D3b-11 | Teardown: dispose, and dying with the surface it points at | E1 | same file, 2 cases | PASS_AUTOMATED |
| NM-D3b-12 | Apple's warning is in the docs, verbatim | E1 | same file, holds `api.md` to it | PASS_AUTOMATED |
| NM-D3b-13 | The scenario is swept clean at every viewport × preference × package | E1 | `tests/overflow_sweep.spec.luau` | PASS_AUTOMATED |
| NM-D3b-14 | The live RascalRally consumer is current | E1 | `luauui_help_callout_contract.spec.luau` | PASS_AUTOMATED |
| NM-D3b-15 | **The tail's paint under a real theme on a real device** — D1's own NM-D1-12, and this is the first construct to put one on screen | E4 | a Studio/device pass | PENDING_PHYSICAL |
| NM-D3b-16 | **Whether a coach mark reads as guidance rather than an obstruction** — the plate under a thumb, and whether a player finds the `Dismiss` row | E5 | a human pass | PENDING_HUMAN |

## Mutation ledger — six that bit, one that did not

| # | Mutation | Reddened |
|---|---|---|
| M3 | the plate presented `modal = true` | 5 cases — the ring moves, the base order is invaded, the tap-through and the arrow-reach both fail |
| M4 | `maxVisible = 2` | `a second callout WAITS…` + `priority orders the queue without ever showing two` |
| M5 | `eligible()` stops consulting `retired` | `a player dismissal retires it once, with a reason, and never twice` — **after the spec was fixed; see below** |
| M6 | `retire()` writes `spec.seen` itself | `THE FRAMEWORK WRITES NO PLAYER STATE…`, and the game rider's `PERSISTENCE IS THIS PACKAGE'S…` |
| M14 | `onRetire` made optional | `a callout with no way to report a retirement is an authoring error` |
| M15 | the queue ignores the surface its plate points at | `dismissing the surface underneath takes the callout with it` |
| **M12** | the tap-away catcher flipped to `consume = true` | **NOTHING — recorded, with the reason** |

**M5 found a hole in this stage's own spec before it found anything in the
source.** The first run of that mutation reddened nothing: the case that covered
"a retired callout never returns" also declared `featureUsed`, which refused for
an entirely different reason, so the `retired` clause was never the thing under
test. A case with neither `seen` nor `featureUsed` now pins it, and the mutation
bites. Recorded because a mutation that fails to bite is information, not a
formality.

**M12 does not bite, and it should not be quietly dropped.** On the catcher path
the two modes are identical by construction: `catchers.onPopupCatcherTap` reads
`consume`, dismisses, and returns either way, because an empty-space tap pressed
no rendered node and there is nothing to forward it to. The mode is load-bearing
on the presenter's **rendered-sibling** path (`onNodeTap`), which iterates the
contributions of the handle owning the *tapped* node — and this contribution
rides the Callout's own surface, not the screen underneath, so a tap on the
pointed-at control never reaches it. That is why the plate stays up when the `+`
is pressed, which is the reference behaviour. The declaration stays because it is
the true statement about what this surface must never swallow; it is documented
in source beside the line, so the next reader finds the reasoning rather than
re-deriving it.

## What this row does NOT claim

- **Everything is E1.** No device pass, no human pass. The wedge's paint under a
  real theme is D1's own `NM-D1-12`, still open, and this is the first construct
  that puts one on screen — so it is the natural first stop for a Studio pass.
- **No shipped Rascal Rally surface adopts it.** The rider is a framework-presence
  check plus a tripwire. That tripwire had to pin a **file set** rather than a
  zero, and finding out why is the useful part: this game already spells `help`
  for the Sponsor **card family** — a hue, a weight, a glyph, a slot — across
  thirteen files, so "no `help =` anywhere" was never going to be true and a
  needle narrow enough to dodge them all would dodge the real thing too.
- **No adaptive presentation.** Unlike `newMenu`, a Callout does not resolve into
  a sheet on touch: it is one plate with one placement on every class, which is
  what the reference does. If a compact-screen form is ever wanted, it is a
  `resolvePresentation` question and not a device branch.
