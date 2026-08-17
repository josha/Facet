# NM-H4a — the HUD paint latch, reproduced and root-caused

**2026-08-17.** Reproduced headlessly on the director's own fixture, and the
mechanism measured on the real Roblox adapter. Fixed at the seam that caused it.

---

## 1. The mechanism

`park` takes a dying node's GuiObject out of the tree; `adopt` gives it to the
next node that wants the same shape. **`adopt` was never told which SURFACE it
was adopting for.** Its signature was
`adopt(handle, newPath, newClass, hint)` — new identity, no root — so
`screen_target` answered the parenting question with a module-scope local:

```
screen_target.luau:987   local lastRootHandle: any = nil
screen_target.luau:1212  lastRootHandle = rootHandle          -- every create
screen_target.luau:3708  handle.instance.Parent = lastRootHandle.gui  -- every adopt
```

`lastRootHandle` holds the root of the **last `create` on this adapter,
whichever surface asked for it**. One `screen_target` serves every surface a
presenter puts on it, and the gallery runs several at once — measured live in a
Play session on the built showcase:

```
LuauUI_ShowcaseBackdrop  enabled=true  order=10100
LuauUI_ShowcaseChrome    enabled=true  order=10200
LuauUI_AdaptiveScreen    enabled=true  order=10300      (+ the demo's own surfaces)
```

So the root of the last create is the right answer only by luck of ordering.
When the luck runs out, a node is re-parented into **another surface's
ScreenGui**.

### Why it presents as "stops painting and never recovers"

Measured on real Instances (`screen_target`, real adapter, Studio):

```
FIXED   rule: adopt(..., rootA) -> Parent is rootA.gui = true,  rootB.gui = false
SHIPPED rule: adopt(..., rootB) -> the /Alpha node's Parent is Workspace…LuauUI_Beta
              ...and it reports Visible=true, IsDescendantOf(Alpha)=false
after Beta's ScreenGui:Destroy() -> Parent = nil ;
              writes to the instance are STILL ACCEPTED (pcall ok = true)
```

Three consequences, and together they are the whole symptom:

1. **It is invisible to every model-side instrument.** Rect, `Visible`, ZIndex,
   solved arrangement, forms, dropped, elided — all correct. Only `Parent` is
   wrong, and nothing measured `Parent`.
2. **It is partial.** Only the nodes that came out of the pool move.
3. **It never recovers.** Nothing re-parents a node that already exists, and once
   the foreign surface is disabled or destroyed the instance is nowhere — while
   the renderer goes on writing rects, visibility and z into it *without
   erroring*. Only a remount clears it.

### Why the sink dismissal, and why two cycles

- The **recycle pool must be non-empty** before an adoption can happen at all.
  The pool is the accumulated state: the first round of churn parks, the second
  adopts. That is "it fires on the second".
- The **sink** is a fourth surface. Presenting it makes its root the last
  creator; **dismissing** it calls `destroyRoot`, which `Destroy()`s that
  ScreenGui — taking any HUD node that landed inside it with it, and stripping
  those paths out of `instancesByPath` on the way. A dismissal is what turns
  "drawn on the wrong layer" into "gone for good".
- Within one structural sync the misparented set is a **contiguous document-order
  prefix**: everything adopted before the walk's first fresh `create` takes the
  foreign root, and that first `create` resets the module local, so everything
  after it is correct. A `Path` node is a natural boundary — nothing of that
  recycle key is ever in the pool.

---

## 2. The reproduction

### Headless, on the director's own fixture

`tests/hud_paint_probe.spec.luau` — "the director's sequence with the gallery's
other surfaces present". The same sequence the existing block drives (sink opened
**and closed**, two orientation-plus-URL-bar cycles), with a second live surface
above the HUD, as the gallery genuinely presents its showcase screen above a
scenario's. Against the shipped code:

```
✗ no HUD node is left parented under another surface's root
    expected /HudScreen/LadderWhen/then/LadderLines under 'Showcase' ;
             /HudScreen/LadderWhen/then/LadderLines/Ladder under 'Showcase'
```

The ladder caption is one of the elements missing from `fishy.jpeg`.

### Headless, minimal

`tests/instance_recycling.spec.luau` — "an adopted node belongs to its OWN
surface". Flat rows (no clip host, as the `hud` zones are flat), killed, a second
surface creates, rows rebuilt out of the pool:

```
✗ /Alpha/Col/Rows/[a4]/RowText under 'Beta' ;
  /Alpha/Col/Rows/[a5]/RowText under 'Beta' ;
  /Alpha/Col/Rows/[a6]/RowText under 'Beta'
```

### Why nothing saw it before

`tests/lib/fake_target.luau` **had no parent model at all**. Every headless
replay — 288 of them, plus 144 ordered viewport pairs — compared paths,
properties, rects and visibility, and there was no question to ask about
parenting. The live Studio runs read properties off `adapter.getInstance(path)`,
which answers out of `instancesByPath`; that map is keyed by path and knows
nothing about where the instance hangs. The paint probe's engine seam reads
`Visible` and `AbsoluteSize`, both of which a misparented node still answers.

The fake target now records `parentRoot` on create and adopt, mirroring the live
rule exactly, and answers `adapter.rootIdOf(path)`.

---

## 3. The fix

The adapter stops guessing. The renderer already holds the surface's root at the
adoption call site and now passes it:

| File | Change |
|---|---|
| `src/render/renderer.luau:1146` | `adapter.adopt(candidate, node.path, node.class, hint, rootHandle)` |
| `src/client/screen_target.luau` | `adopt` takes `rootHandle`; parents under `rootHandle.gui`; `lastRootHandle` deleted (declaration and assignment) |
| `tests/lib/fake_target.luau` | mirrors both halves, and records the parent so a headless spec can ask |

Nothing else in either repository calls `adopt` — `billboard_target` does not
implement the recycling verbs, and RascalRally consumes the adapter without ever
invoking them.

---

## 4. Evidence

### Headless

```
lune run tests/run                     6138 passed / 0 failed
games/RascalRally/code: lune run tests/run   3344 passed / 0 failed
```

### Live (E3), real adapter, built showcase place

Place identity confirmed before use rather than assumed: `screen_target.Source`
is 186 510 chars — the exact on-disk length — with `lastRootHandle` absent, the
`rootHandle` parameter present and `renderer` passing it.

The audit is VM-independent and needs no framework handle: `buildHandle` writes
`instance.Name = path` and `adopt` writes `instance.Name = newPath`, so every
GuiObject carries the node path it believes it is. A node whose path names one
surface while its ancestor ScreenGui is another **is** the defect.

19 audits across every demo in the gallery, plus a chrome surface presented and
dismissed — each switch tears one surface down and builds another while the
backdrop and chrome surfaces stay live on the same adapter:

```
start (all-controls)                120 nodes, 0 misparented
after showNext -> row-actions        75 nodes, 0 misparented
… 14 more demos …
after showNext -> hud                98 nodes, 0 misparented
chrome open                         145 nodes, 0 misparented
chrome closed                        98 nodes, 0 misparented
TOTAL MISPARENTED ACROSS ALL AUDITS: 0
```

**Positive control, same VM, same predicate, same engine** — because an audit
that has never fired proves nothing:

```
FIXED   rule: 2 nodes, 0 misparented
SHIPPED rule: 3 nodes, 1 misparented   /Alpha/Row3 inside LuauUI_Beta
```

Capture: the `hud` demo at 749x380 with the paint probe reading
**`14 of 14 rows wanted / 14 of 14 painting`**.

### Mutation ledger

| Mutation | Result |
|---|---|
| renderer drops the `rootHandle` argument (the shipped state) | 2 red — the minimal case and the director's sequence |
| `fake_target.rootIdOf` answers `nil` (the instrument as it was) | 1 red — the vacuity guard, i.e. the blindness itself is caught |
| `screen_target` parents under `baseRootGui` instead | not caught headlessly, and it cannot be: no Lune suite executes `screen_target`. This is why the live positive control above exists and why the RascalRally consumer spec pins the seam by source |

---

## 5. What this does NOT claim

- **The phone was not re-tested.** The mechanism is reproduced on the director's
  own fixture and measured on the real adapter, and the fix is proved live in the
  built showcase — but NM-H4a's own row stays `PENDING_PHYSICAL` until the
  sequence is driven on hardware and the plate still reads 14 of 14.
- **It does not claim to be the only cause of every pixel in `h.jpeg`.** It
  explains the class — a partial, permanent, model-invisible loss of paint that a
  remount clears — and the two elements named in the photographs that this
  reproduction reproduces by name are the ladder caption and its plate.
- The `+93px` shift visible between the healthy and failing landscape frames of
  `hud-latch-repro.mp4` is **unexplained by this fix** and is recorded here as an
  open observation rather than folded into the story.

---

# ROUND 3, 2026-08-17 — THE ACTUAL CAUSE, from the plate the instrument now prints

The instrument shipped in round 2 answered it in one photograph (`a.jpeg`):

```
Paint probe · 734x393 · solve 15
13 of 14 rows wanted
skipped: Objective
NOT RIDING · no platform band · coreTop=120
```

**`coreTop = 120`, not 0.** So `bandH = min(120, 393)` passed and the height gate
was never the problem — it was the INTERSECTION that collapsed.

## The mechanism

`topbarSafeInsets` is stored as **edge insets**, and an edge inset only means
anything against the viewport it was measured on: `platformChrome` turns it back
into a rect with `W - right` and `H - bottom` (`src/env/environment.luau:305-343`).

An orientation change updates `Camera.ViewportSize` and
`GuiService:GetInsetArea(TopbarSafeInsets)` on **different frames**, so one
`pushViewportFacts` can capture a new viewport beside an inset measured against
the old one. `env:batch` makes the *write* atomic; it cannot make the two engine
*reads* agree.

Measured, headless, against the phone's own numbers:

```
landscape 393 tall, safe insets measured AT 393   band=164,0 570x58
landscape 393 tall, safe insets measured AT 852   band=NIL
   H - safeI.bottom = 393 - 794 = -401            <- the clamp goes NEGATIVE
```

`band = nil` → `riding = false` → `Objective` leaves the denominator and the HUD
moves onto the no-band rung, which spends a different top inset and different
column reserves. That is the ··· and the hamburger disappearing.

**And nothing republishes until the next platform event** — which is exactly why
rotating away and back repaired it, and why no scripted resize in Studio ever
reproduced it: `setEnv` writes a consistent pair, and the emulator updates both
together.

## The fix

The header above already states the rule: the two encodings are intersected
because that is *"an identity on a healthy platform and a belt when one of them is
missing or LYING"*. The belt was turning a lie into a total loss. An inset that
cannot describe the current viewport — `top + bottom >= H`, or `left + right >= W`
— is now discarded in favour of the other encoding, which is already window-space
(the DV3-1 correction), instead of being intersected with until nothing is left.

A **truthful** narrowing still narrows: `right = 300` on a 734 window still cuts
the band to `270x58`. The belt is not switched off, only stopped from believing an
impossible number.

## Evidence

| | |
|---|---|
| Guard | `tests/adaptive.spec.luau` — 5 cases, including the truthful-narrowing control and "no topbar rect is still NO BAND, the discard is not a manufacture" |
| Mutations | reverting the discard reddens 2; discarding unconditionally reddens the narrowing control. Both directions bite |
| Consumer | RascalRally reads `platformChrome.band` directly (`LuauUISponsor/init.luau:1312`); rider added to `luauui_composition_collision_contract.spec.luau` |
| Suites | LuauUI 6148 / 0 · RascalRally 3345 / 0 |

## What rounds 1 and 2 were

Round 1's parenting defect (`adopt` re-parenting under a module-scope root) was
real, is proved live, and is fixed — but it was **not this**. Round 2's plate is
what made round 3 possible: `coreTop=120` is the whole diagnosis, and no
photograph before it carried an input.
