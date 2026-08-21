# ADR-0032 — The nested instance tree: the mechanism already exists, and switching is a registration policy

**Date:** 2026-08-15
**Status:** Accepted — decided here; **BUILT by the nested-instance-tree round,
2026-08-16/17.** This ADR was *decision only; this ADR does not build* — the staged plan
in §Migration was the build brief, and §What the build found records what happened when
it was followed, including the three things this ADR got wrong or did not see.
**Number:** 0032, not 0031. `ADR-0031` is claimed *twice* in live source this week — by
`UI.Foreign` (`src/render/authority.luau:9`, `src/blueprint_schema.luau:2163`) and by the
motion-curve vocabulary (`src/motion/curves.luau:2`, `src/init.luau:259`) — while no
`ADR-0031-*.md` exists on disk. Those two agents own that collision; this ADR steps over
it rather than joining it.
**Commissioned by:** the game director, 2026-08-15. Verbatim: *"from reading the
facet-react comparison, i'm wondering if we should allow for nested instance trees vs.
just the flat hierarchy? it seems like a view of nested views is a good approach and will
allow for things like compositing of animation or traits like opacity"* — followed, the
same day, by the ruling that settles the schedule: ***"switching to nested should come
before release."***
**Amends:** [ADR-0022](ADR-0022-sponsor-framework-gaps.md) Decision 2 (which named the
fade group *"the single documented exception to Facet's flat instance tree"* — there are
three, and after this ADR the exception becomes the rule).
**Companions:** [ADR-0026](ADR-0026-authored-presentation-composition.md) Decisions 2/5/7,
[ADR-0029](ADR-0029-leaf-opacity-refusal.md) Decision 2 (the offerable-term rule, which is
this ADR's closest precedent), [ADR-0009](ADR-0009-billboard-target.md) (verifier F1, why
`ZIndexBehavior.Global` was refused), [ADR-0028](ADR-0028-cross-surface-overlap.md)
(surfaces as the escape hatch), `docs/reference/react-lua-comparison.md` §2.2 and §4.3.
**Evidence:** `artifacts/adr-0032-nested-instance-tree/live-probes.md` — every number
below, with its instrument and its tier.

---

## The headline, stated before anything else

**The arrange win is real and it is large.** Moving a container with 120 descendants
costs, in the shipped flat tree, **123 rect writes and 120 engine `Position` writes**,
with the solver's incremental-layout optimisation skipping **zero** nodes. Nested, it is
**one** write. An engine-level harness puts the Luau-side write cost at **O(N) flat
(0.0145 / 0.0625 / 0.2556 ms at N = 50 / 200 / 800) versus O(1) nested (0.00022 ms at
every N)** — 63× to 1157×, against a widest A/A control spread of 9.88%.

**And the number that argues against, which a future reader must see and not have to dig
for: elision.** On a 20-row list surface, elision removes **61 of 142 GuiObjects — 43%**.
Materialising every container so it can be a real parent costs **+75.3% instances**. That
is *worse* than the −34% previously on record.

**A second cost, found in source and not anticipated by the brief: nesting disables
recycling on the node it is applied to.** `parkEligible` refuses any handle that is a
registered host (`screen_target.luau:3382`), so a hosted node leaves the instance pool.
The virtualised list row is both the best move boundary *and* the case recycling exists
for. That collision is unpriced here and gates the first build step.

**The elision cost is reconcilable, and that is the whole design.** Parenting in Facet does not
walk the node tree — `hostFor(path)` is a **longest-path-prefix match over a registry**,
so a container that is not registered is *invisible to parenting* and elision is
untouched. Nesting is therefore not "mirror the blueprint in Instances". It is **"register
more hosts"**, and the correct policy registers a container **only where nesting pays**.

---

---

## What the build found — added 2026-08-17, after the migration ran

This ADR reasoned from live probes and got the shape right: nesting **is** a
registration policy, the mechanism **did** already exist, and no render-seam change was
needed. Steps 1, 2, 4 and 6 landed as written. What follows is what only building it
could show.

**THE ARRANGE WIN WAS REAL BUT IT WAS NOT WHERE THIS ADR PUT IT.** §The headline prices
a container move at "123 rect writes and 120 engine `Position` writes" and treats
nesting as the thing that removes them. Nesting alone removes none of them. Measured in
Studio on a 120-node list inside a `ScrollView` whose header grew 40px — a shape that
was already fully nested before this round — the move cost **240 descendant `Position`
changes, two per node**, and half of them were the WRONG VALUE:

    1. cell -> y=60    the new window rect against the host's OLD origin
    2. list -> y=60    the host finally moves, and its entry origin updates
    3. cell -> y=20    corrected, when the host re-bases its own children

The cell ends where it started, because a `GuiObject.Position` is parent-relative — the
fact this ADR's whole arrange argument rests on. The old path paid 240 writes to arrive
at no change, and for the moment between (1) and (3) the entire subtree is drawn
displaced. **That is a rendering defect, not a performance one, and this ADR did not
see it** because it measured a synthetic engine harness rather than the framework's own
rect path.

The cause was upstream of nesting entirely: the renderer applied a solve's rects by
iterating a hash — its own comment called it *"the unordered rect hash"* — so a
descendant could be placed before its host, and the adapter compensated with an inline
re-base of every child on the host's `setRect`. Harmless on a flat tree, where every
Position is absolute. The fix is document order in `src/render/rect_pass.luau` plus
deferring that re-base to `adapter.settleRects`, and it needs **both** halves: ordering
alone re-bases against the children's own stale rects, deferring alone still lets the
first write see a stale origin. **241 engine writes become 1.** A/A control spread 0
(discrete event counts, both arms run twice, identical).

A third piece was needed in front of them: `applyRect` now caches the pair it last
wrote and skips an unchanged write. On its own it delivered **nothing** on this
workload — measured, with the skip patched out as a control, both arms at 240 — because
the two writes were two different values. It is what makes the corrected path cost
nothing rather than N.

**A PLAIN `Frame` CARRIES `Rotation` AND `UIScale`, IDENTICALLY TO A `CanvasGroup`.**
Decision 4's measurement used `canvasGroup = true` because a group was the only way to
get nesting at the time, which left the cost of the decision open. Measured: child
80x40 -> **120x60 at `AbsoluteRotation` 30 in both arms**. So Decision 4 costs one
`Frame`, not an offscreen buffer, and — with Decision 3 having already refuted the
ordering story — `Frame` nesting and `CanvasGroup` nesting now differ in exactly one
thing: the buffer, and therefore `GroupTransparency`.

**DECISION 5 IS CONFIRMED LIVE.** In both arms above the descendant's own `Rotation`
stayed `0` and it grew no `UIScale` while visibly rotating and measurably scaling. An
engine-composed descendant effect is not a write to the descendant's property, so the
authority manifest is unchanged — the one question here that could have forced a
manifest change does not.

**`crops` IS NOT `clipChildren`, AND THE HOST RECORD NEEDED A FOURTH FIELD.** The focus
ring is re-parented as a float inside a host because a stroke drawn under a clipping
parent is cut. A `CanvasGroup` cuts it too, despite never setting `ClipsDescendants`,
because it renders its subtree into a buffer its own size. A plain move-boundary host
cuts nothing. Without the distinction, every container that merely moves would grow a
float ring it does not need. Verified live: inside a `ScrollView` the float exists;
inside a rotated container it does not and the ordinary outward ring is used, matching
the host-free case exactly.

**`hostFor` WOULD NOT HAVE SCALED.** It scanned the whole registry on every `create`
and `adopt` — free at three hosts, O(nodes x hosts) exactly as "register more hosts"
proceeds. The cost would have arrived with the feature and been blamed on nesting. It
now walks the candidate path's own separators: 20,000 lookups against 4,001 hosts,
**4.9485 s -> 0.0077 s**.

**STEP 3 WAS NOT TAKEN, AND DID NOT NEED TO BE.** This ADR gates step 3 on the
recycling conflict and asks for a first move boundary to be chosen against it. The
ordering fix delivers the arrange win on hosts that **already ship** — every
`ScrollView` on every list surface — for zero new instances, zero elision cost and no
argument with the pool. The conflict is therefore still unpriced and still real
(`parkEligible` still refuses a registered host, and the fake target now models that
refusal so a headless spec can see it), but nothing in this round had to pay it.

**WHAT IS STILL OWED.** The total-frame claim. Everything above counts engine property
writes, not milliseconds; the engine's own C++ descendant walk is untouched and
unmeasured, exactly as §Risks says. A Performance Lab run and a device pass remain the
only things that can turn this into a frame number.

## Decision 1 — Facet adopts a nested instance tree, and it requires no new mechanism

The mechanism is already shipped, already general, and already load-bearing. `clipHosts`
plus `hostFor` produce real engine parents today for **three** triggers:

| trigger | since | source |
|---|---|---|
| `ScrollView` (a clip host *by construction*) | — | `renderer.luau:1481-1487` |
| `clipChildren = true` on any container | — | `screen_target.luau:2708-2718` |
| `canvasGroup = true` / an authored `opacity` | ADR-0022 D2, ADR-0026 D4 | `screen_target.luau:1044-1118` |

and one parenting rule for all of them:

```lua
-- clip-host parenting: descendants of a clip host live INSIDE it so
-- the engine crops them; everything else stays flat under the root
local host = hostFor(path)
if host ~= nil then ... instance.Parent = host.instance
else instance.Parent = rootHandle.gui end
```
(`screen_target.luau:1318-1327`)

**Switching to nested is a change to one predicate: which paths get registered in
`clipHosts`.** It is not a rewrite of the renderer, and it is not a change to the render
seam — `src/render/target_contract.luau` still takes **no parent handle**, and this ADR
adds none. Nesting stays an adapter-internal fact, which is exactly why the headless
suite, the fake target and the solver are not in its blast radius.

**Naming.** `clipHosts` becomes a misnomer the day a host is registered for a reason that
is not clipping. Rename it to `instanceHosts` at the first step of the migration, while it
still has three call sites' worth of meaning rather than three hundred.

## Decision 2 — a container is registered as a host when it is a MOVE BOUNDARY or a COMPOSITE BOUNDARY, never merely because it has children

This is the decision, and it is the one that keeps elision alive.

> **Register a container as a real instance parent when the engine can carry something
> down its subtree that the framework would otherwise compute per descendant:**
> **(a)** its subtree moves as a unit (a *move boundary*), or **(b)** it composites as a
> unit — `opacity`, `scale`, `rotation`, clipping, scrolling (a *composite boundary*).
> **Otherwise leave it unregistered and elidable.**

A `VStack` that exists only to say "these three things are in a column" and never moves
independently is pure layout bookkeeping: the solver already places its children
absolutely, and materialising it buys one instance and saves nothing. That node stays
elided, exactly as today. A row in a virtualised list, a card that slides, a panel that
fades, a tray that flicks — each of those *is* a boundary, and each is where the 120-write
bill is actually paid.

**A host is a plain `Frame` unless a composite reason demands otherwise, and that
distinction is the difference between cheap and expensive.** The three costs people
associate with nesting are not properties of nesting:

| cost | caused by | a move-boundary host pays it? |
|---|---|---|
| an offscreen render buffer | `CanvasGroup` | **no** |
| clipping the subtree | `ClipsDescendants` | **no** |
| an ordering wall | any real parent under `Sibling` | yes (Decision 3) |

A move-boundary host is one extra `Frame` and nothing else. **This matters because the
live consumer already reasons about exactly this trade**: Rascal Rally's Sponsor HUD sets
`canvasGroup = false` explicitly on its whole-screen layer root
(`FacetSponsor/HudScreen.luau:472`) because a group there *"would clip every child's
decoration and cost a render buffer over live gameplay"*. That judgement is correct and
this ADR does not disturb it — a move boundary would give that node engine-carried motion
without a buffer and without clipping.

**Why this is a general mechanism and not a special case** (the standing rule): (a) and
(b) are the same predicate stated twice — *"the engine can compose this for its
descendants"*. `opacity` already reaches only classes whose instance can BE a
`CanvasGroup` (ADR-0029 Decision 2). This decision is that rule's general form: **a
presentation term is deliverable to a subtree exactly when the subtree is real.**

**The honest cost of the (b) half, and it is not zero:** the move boundary is knowable
from the blueprint (a reactive offset, a transition, a virtualised band), but "does this
subtree move as a unit at runtime" is in general a *prediction*. A container that is
registered and never moves has cost one instance for nothing. §Risks names the fallback.

## Decision 3 — `ZIndexBehavior` stays `Sibling`, and nesting is therefore an ordering boundary — which is correct

Both the brief and the coordinator predicted `Global`. **Measured: it is `Sibling`**, on
all three live ScreenGuis and at `screen_target.luau:909`. The full 2×2 was measured with
a hit-test oracle *and* confirmed in pixels:

| | child escapes its ancestor's z-slot? | child paints above its own parent? |
|---|---|---|
| **`Sibling`** (shipped) | **No** | **Yes, always** |
| `Global` | Yes | **No** — it sinks behind an opaque parent |

**`Global` is refused**, and not on taste: the right-hand column is ADR-0009's *verifier
F1* (*"nested control internals sort behind their opaque parents"*), reconfirmed live this
session — a child at `ZIndex = 20` under a parent at `50` was **invisible**. Facet pins
its icon child at a fixed `ZIndex = 20` on every button in the live tree; under `Global`
every one of those disappears the moment its button's counter passes 20.

**And `Sibling` + nesting needs no new ordering code**, because `syncZOrder` is already a
depth-first walk over the mounted node tree whose own comment reads *"A child's counter is
always higher than its parent's, whatever its `zIndex`"*. DFS document order **is**
`Sibling` order. The framework is currently hand-computing, across a flat set, precisely
the order the engine would give it from the tree.

**What nesting forecloses, and why it does not bite.** A registered host becomes a wall a
descendant's `zIndex` cannot climb over. The framework never used `zIndex` for that: an
overlay escapes by being **its own surface**, on a banded `DisplayOrder` — the presenter
raises eight kinds (`base 10000 / toast 20000 / dragProxy 30000 / modal 40000`) and
`row_actions` raises a ninth straight through `renderer.attach` (ADR-0028). **A separate
`ScreenGui` is unaffected by any host's z-slot.** The sharpest risk in the brief is real,
already solved, and the solution is already the one in production.

**`CanvasGroup` is NOT an ordering boundary — the coordinator's hypothesis, refuted at
pixel level.** Under `Global` a nested child paints over an outside sibling whether its
parent is a `Frame` or a `CanvasGroup`, and it still does with `GroupTransparency = 0.5`
forcing a demonstrably real buffer. Ordering follows `ZIndexBehavior` alone; the group
buffer changes *compositing*, not sort order. **`Frame` nesting and `CanvasGroup` nesting
have identical ordering consequences**, so the design does not need the two-tier story the
brief anticipated — which is a simplification, and one worth having found before building
on the opposite assumption.

## Decision 4 — `scale` and `rotation` become subtree terms wherever a host exists, and ADR-0026 Decision 7 is amended in place

Measured today, through the real framework: two `UI.ZStack`s with identical
`rotation = 30, scale = 1.5` and identical `80×40` children —

- **flat**: children stay **80×40, `Rotation = 0`**. The container scales and rotates; its
  contents do not move. In pixels: a rotated plate with its contents sitting bolt upright
  beside it.
- **`canvasGroup = true`**: children are **120×60** — exactly 1.5× — and ride the parent's
  pivot. **The engine did that. No framework code did.**

So the director's compositing argument is **confirmed**, and it is worse than a missing
feature: the flat result is not "nothing happens", it is a container visibly detaching
from its own contents.

ADR-0026 Decision 7 says authored terms *"do not accumulate down the subtree"*. That
sentence stays true and its meaning improves: the **framework** still never accumulates
them — it writes one term on one node — and at a host the **engine** composes them for the
subtree, which is [SW-141]'s multiply delivered by the renderer of record, exactly as
ADR-0026 Decision 5 already describes for nested fade groups. What changes is only *how
often a host exists*.

**The position channel is the one that gets simpler.** `presentationShift`
(`presentation_channel.luau:162-184`) sums every ancestor's offset **by walking the path
string**, stopping at the nearest real parent. It is Luau hand-computing what an engine
parent gives free, and it already knows it: *"the adapter stops its own accumulation at
the nearest REAL PARENT … because that parent's instance move already carries its
children."* Every host registered shortens that walk. **The mechanism that makes nesting
correct is the same one that already exists to compensate for its absence.**

## Decision 5 — the authority manifest gains one concept: a term may be delivered by the engine, and that is not a second writer

Nesting introduces engine-computed descendant effects (`UIScale.Scale`,
`GuiObject.Rotation`, `GroupTransparency`, `ClipsDescendants`, `Visible`) where the
manifest today models one writer per property per class. On a platform where a second
writer is **silent** (a StyleSheet rule is defeated with no signal), that must be settled
explicitly rather than discovered.

**It is not a second writer, and ADR-0026 Decision 1 already supplies the vocabulary.**
The manifest asks *"how many functions may write this engine property?"* — still one, on
one instance. An engine-composed descendant effect is not a write to the descendant's
property at all: the descendant's `Rotation` stayed `0` and its `UIScale` stayed absent in
the measurement above, while it visibly rotated and measurably scaled. **The manifest is
unchanged; what it needs is a documented statement that inherited composition is a
*rendering* fact, not a property claim** — plus a live pin that a hosted descendant's own
`Rotation` / `UIScale` / transparency remain framework-untouched, so the day someone adds
a per-descendant write the suite says so.

The genuinely ambiguous entry is `common.zIndex`, and Decision 3 settles it: DFS order and
`Sibling` order are the same order, so the counter keeps its single meaning.

## Decision 6 — Roblox's layout objects stay refused, and nesting is not an argument for them

Nesting makes `UIListLayout` newly *possible*, which is exactly why this is written down.
It stays refused. Facet solves layout itself to get what the engine's layout objects
cannot give: headless layout in tests with no Roblox present, a solver that can be
*diagnosed*, incremental re-solve of the affected subtree, and a vocabulary the engine
does not have — priority tiers, ranked region degradation, `ViewThatFits`. An
`AutomaticSize` child measures itself, and **the solver cannot see that**. Zero
`UIListLayout` / `UIGridLayout` / `UITableLayout` instances exist in `src/` today and none
are added. `UIPadding` keeps its two existing uses (a control's own text inset).

---

## Before release — the director ruled it, and the ruling is independently correct

The director ruled *"switching to nested should come before release"* before this
investigation reported. The ruling is not merely accepted here; it is **confirmed on the
evidence**, because the underlying question has a checkable answer: *is nesting additive,
or does it change what existing views render?*

**It is not additive. Three things change for callers who write nothing new:**

1. **`scale` and `rotation` on a container start affecting its contents** (Decision 4).
   Today a container at `rotation = 30` rotates alone and leaves its contents upright;
   after, the subtree rides its pivot. Any surface that reached today's behaviour — or
   worked *around* it by rotating leaves individually — renders differently.
2. **A `zIndex` lift stops escaping across a registered host.** Today's flat set makes
   every lift globally effective; a host is a wall (Decision 3). Default document order is
   unchanged, so this affects only deliberate lifts, but it is a render change.
3. **Instance identity and parenting change** under any consumer that reads the tree, plus
   every render dump and flat baseline gets re-based.

Each is a behaviour change to already-shipped views. Doing this after 1.0 would mean
either a MAJOR bump with a migration for every consumer, or shipping the wrong
`rotation`/`scale` semantics permanently and adding a second, correct spelling beside
them. **Before release is the cheap door, and it closes at 1.0.**

The opt-in-group alternative *would* have been purely additive and could have waited —
which is precisely why it was the tempting answer and why §The alternative that lost
records what it does not buy.

## Migration — staged so each step ships green, with five agents live in shared files

Ordered by dependency. Each step is independently landable and independently provable;
none requires the renderer to be rewritten.

1. **Rename `clipHosts` → `instanceHosts`; extract `registerHost(path)`** as the one
   registration site the three existing triggers call. Pure refactor, zero behaviour
   change, byte-identical dumps. *Proof: the flat baseline is unchanged.*
2. **Pin what must not drift.** Add the live-engine assertions Decision 5 asks for (a
   hosted descendant's own `Rotation`/`UIScale`/transparency stay framework-untouched) and
   a `syncZOrder`-vs-`Sibling` order equivalence test, **while the tree is still flat**.
   These are the instruments the rest of the migration is measured against; they are worth
   nothing if written after the change they are meant to catch.
3. **Register one move boundary, and it must be chosen against the recycling conflict
   below — not automatically the virtualised row.** Highest write-count payoff for the
   smallest surface, proven with the §3a instrument (a container move drops from N writes
   to 1) plus an instance-count and recycle-pool census.

   > **The conflict, found in source and load-bearing enough to gate the step.**
   > `parkEligible` refuses to park a handle when `clipHosts[path] ~= nil`
   > (`screen_target.luau:3382`) — a host cannot be recycled. **The virtualised list row is
   > simultaneously the best move boundary and the single most important recycling case**
   > (instance recycling is ON by default; themed recycling is L-28). Registering rows as
   > hosts would trade the framework's biggest churn optimisation for its biggest
   > move optimisation, and this ADR does **not** have the measurement that says which
   > wins. Step 3 must therefore either (a) pick a boundary that is not pooled — a card, a
   > panel, a tray — or (b) first teach `park` to carry a host's children, which is real
   > work and belongs in its own step. **Measure both arms before choosing; a wrong
   > choice here is a regression on a shipped, measured win.**
4. **Register authored `scale` / `rotation` containers**, closing Decision 4's capability
   hole for the case the director named. Additive: a container with neither prop is
   untouched. *Proof: the §2a probe re-run — children scale and rotate with the container.*
5. **Register transition and `withAnimation` move boundaries** — the sliding card, the
   presented panel — where the record's `{x,y}` delta currently repaints a whole subtree.
6. **Extend elision rather than retreat from it.** A registered host must materialise, so
   the elidable set shrinks by exactly the hosts registered. Re-measure §4's 43% at each
   step and publish it; if a step's instance cost exceeds its write saving on the
   Performance Lab, **that step is reverted**, which is what makes the staging real.
7. **The Performance Lab and device pass** — the total-frame claim this session could not
   make (§Risks).

**What must not be attempted:** a big-bang "every container is a parent" change. §4 prices
it at +75.3% instances for a benefit concentrated in a small minority of containers.

**A stale constraint, corrected here because it would otherwise have shaped this plan
wrongly.** ADR-0025 and ADR-0028 both recorded that their mechanism *could not be
canaried live* because `renderer.luau` exceeded Studio's 200 000-character `Source` limit
(ADR-0028 cites 238 000). **That is no longer true**: `renderer.luau` is **185 633
characters** today and `solver.luau` is **178 598** — the extraction that was in flight
when ADR-0026 was written has since landed. Verified the strongest possible way this
session: the renderer's full `Source` was read *out of the live datamodel* and
successfully re-required. **Every step of this migration can be canaried live**, and the
canary ADR-0028 recorded as owed is now takeable. The renderer-split flag stands on
maintainability grounds, not on this limit.

---

## Consequences

- **Public surface: none added by this ADR.** No new blueprint prop, no new controller
  method, no render-seam change. `scale`/`rotation` gain reach on containers that become
  hosts — a behaviour change for a prop combination that today produces a visibly wrong
  result, which is why it ships before release rather than after.
- **`api.md`, the comparison document and ADR-0029's refusal message describe a narrower world
  than will be true.** ADR-0029's message tells an author that a subtree fade needs a
  `UI.ZStack` wrap. That stays correct for `opacity` (it is still the only class that can
  BE a `CanvasGroup`), but the `scale`/`rotation` half of the same message — *"need no
  wrap"* — becomes true in a stronger sense than it was written.
- **Recycling and nesting are in direct conflict, and this is the second number that
  argues against.** `adapter.park` parks by setting `Parent = nil`, and `parkEligible`
  returns **false** for any handle where `clipHosts[path] ~= nil`
  (`screen_target.luau:3382`). **Every host registered is one node removed from the
  recycle pool.** The nodes with the most to gain from nesting — virtualised rows — are
  the same nodes recycling was built for. Either `park` learns to carry a subtree, or the
  boundary set avoids pooled nodes. Neither is free and this ADR does not price them;
  step 3 must.
- **The Explorer becomes readable**, which the comparison doc names as a real ergonomic
  loss of flatness: *"the Roblox Explorer shows you a flat pile of Frames with no
  structure to read."* Not a reason to do this; a genuine consequence of it.
- **The flat baseline check keeps working, and keeps its name honestly.**
  `tools/lune/check_flat_baseline.luau` compares by `{fixture}|{viewport}|{which}|{path}`
  — **path strings, not parents** — and `Instance.Name` stays the full path verbatim. It
  is gate-enforced (`tools/lune/gate_manifest.luau`) and does not need redesigning; it does
  need re-baselining at each step that changes materialisation.
- **~24 test files reason about parenting/children directly**, three plus three tooling
  files are gated on the flat baseline, and `tests/lib/fake_target.luau` — consumed
  transitively by ~200 specs — encodes the flat presentation-accumulation model as its
  core mechanism (*"there is no parenting here, so every ancestor counts"*). **The fake
  target is the single largest test-side item** and it must learn hosts in step 1, before
  any behaviour moves.
- **`surface_overlap` is unaffected**: it unions a flat `path -> Rect` map and never
  consults the engine tree.
- **`focus_graph` and `focus_map` are unaffected**: both are engine-free and walk the
  logical mount tree, not instances.
- **`controller.tapAt` needs re-reading.** Its correctness rests on the comment *"last
  match wins: document order IS paint order"* — which Decision 3 says stays true under
  `Sibling`, but it is asserted in a comment rather than pinned, and step 2 should pin it.

---

## The Rascal Rally consumer rider — investigated, and the answer is smaller than expected

Per the root constitution, Facet and Rascal Rally move together. The game side was
audited in full (its own repo, `code/`, 203 spec files; its suite live-run this session at
**3248 passed / 0 failed**).

**The blast radius is close to zero, and the reason is structural rather than lucky:**

- **Zero game code reaches into the rendered instance tree.** Every Facet consumer — the
  Sponsor package (34 files), the racer list, the garage pilot screen, the settings modal
  — goes through the framework's API only. The single raw-instance touch in the whole game
  is `FacetSettingsGui.luau:96-98`, which resolves `adapter.getInstance(path)` and checks
  `IsA("GuiObject")` before assigning `GuiService.SelectedObject`. It is **path-keyed with
  no depth or sibling assumption — it survives unchanged.**
- **Zero tests depend on Roblox parenting.** Seven files matched a parenting-shaped grep;
  all seven are false positives (data folders, fake haptics roots, prose in comments). No
  real `Instance` is constructed in a headless Lune run at all, and Facet-touching specs
  run against `fake_target.luau` — whose own source says *"there is no parenting here"*.
- **Zero snapshot or baseline files** in the game repo encode Facet instance names or tree
  shape.
- **The legacy hand-rolled Sponsor UI** (the `UseFacetSponsor = false` rollback path) has
  no Facet dependency and is untouched, as its authorization requires.

**What the game side does owe, in order:**

1. **A contract test, required by the rider even though nothing breaks** — the standing
   rule is that a compatible change still needs game-side evidence the live consumer is
   current. Smallest useful shape: one headless test that the Sponsor presenter mounts and
   tears down cleanly, plus a spot-check that the `getInstance(path)` selection path still
   resolves.
2. **A Studio canary on the surfaces most exposed to the ordering change.** Sponsor mounts
   **four concurrent top-level surfaces** (HUD root `coreSafeContent`, chip band
   `edgeToEdge`, results screen, role-pick modal) — which is Decision 3's escape hatch
   already in production use, and the best available evidence that surfaces are how this
   framework layers. Focus on input routing (a `GuiButton` sinks input; nesting changes
   what "behind" means) and the one real `ScrollView` (`ResultsScreen.luau:2458`).
3. **A visual check on `canvasGroup` fades.** Sponsor is the framework's heaviest
   `canvasGroup` consumer — 13+ call sites — so it is the surface most likely to shift
   visibly, and it should only get *more* correct.

**Features Sponsor does not use at all**, which usefully bounds the risk: `opacity`,
`clipChildren`, the `zIndex` prop, `rotation`, `withAnimation`, `UI.Table`, and row
actions. The `rotation`/`scale` semantic change in Decision 4 therefore reaches the live
game through only two `setPresentationTransform` call sites (`StoryFlow.luau:755`,
`OmenState.luau:456-458`), both `scale`-only.

## The alternative that lost, and it lost narrowly

**An opt-in compositing group on a permanently flat default** — a `CanvasGroup`-backed
`UI.Group` that a caller reaches for when they want grouped opacity, with every other
container staying flat forever. This was the hypothesis this investigation was
commissioned to test, and it is *nearly* right: it is additive, it is purely a
before-or-after-release non-question, and it leaves every measured flat-tree win intact.

It lost on one measurement. **It answers the compositing half of the director's question
and none of the arrange half.** A caller reaches for a compositing group when they want a
*fade*; nobody reaches for one to make a list row cheaper to move. The 120-writes-per-
container-move bill (§3a) is paid by ordinary containers that no author would ever
annotate, and an opt-in group leaves every one of them flat. Decision 2's boundary
predicate subsumes it: a compositing group **is** a composite boundary, so the opt-in
group is the (b) half of a rule that also has an (a) half.

It also lost for a reason that only turned up in the pixels: it was premised on
`CanvasGroup` being an ordering boundary that plain nesting would avoid, and Decision 3
measured that both nest identically. **The distinction the alternative was built on does
not exist**, so its main claimed advantage — "pay ordering costs only where opacity was
asked for" — is empty. There are no ordering costs specific to `CanvasGroup` to avoid.

Also considered and rejected:

- **Switch to `ZIndexBehavior.Global` so nesting costs no ordering freedom.** Refused on
  ADR-0009's F1, reconfirmed live: a child sinks behind its opaque parent, which silently
  deletes the icon on every button in the framework.
- **Mirror the blueprint tree in Instances (the React-Lua shape).** Priced at +75.3%
  instances (§4) and it deletes elision outright. The comparison doc's own §5 rank-1 entry
  reaches the same conclusion from the other direction, sanctioning a *bounded* real-parent
  escape hatch rather than general hierarchy.
- **Do nothing.** Overtaken by the director's ruling, and the ruling is well-founded: the
  flat-tree `rotation` result is a visible defect, not merely an absence.

---

## Risks, and what this decision is NOT backed by

- **The total-frame win is unmeasured.** The 63–1157× is **Luau-side write cost only**.
  The engine still recomputes every descendant's `AbsolutePosition` in the nested arm —
  that work moves from Luau into C++, it does not vanish. The frame-time instrument in
  this session was **saturated at 66.7 ms in every arm** (Studio background throttle) and
  could see nothing. **A Performance Lab run and a device pass are owed, and step 3 is the
  first place they can be taken.** If the engine's descendant walk turns out to cost what
  Luau's did, this ADR's headline shrinks to the compositing half — and that is the single
  most important thing a future reader could learn.
- **The move-boundary predicate is partly a prediction** (Decision 2). If it proves
  unreliable in step 3, the fallback is the narrow, honest one: register only where the
  blueprint *declares* a boundary (a reactive offset, a transition, `opacity`/`scale`/
  `rotation`, clip, scroll) and accept a smaller win rather than guess.
- **The `Source`-limit constraint no longer applies** — `renderer.luau` is 185 633 chars
  against Studio's 200 000, proven loadable live this session. The risk it leaves behind
  is the opposite one: ADR-0025 and ADR-0028 each recorded an owed live canary on that
  basis, and both are now takeable and still untaken.
- **No `PerformanceLab` session was connected this round** — checked, not assumed. And the
  connected Showcase session was carrying a **broken** synced renderer from concurrent
  in-flight work (a `NO_DECORATION_CLASSES` use with its declaration missing), so every
  Facet measurement here ran against a clone-and-require patch. Recorded in the evidence
  file; it means these numbers should be re-taken on a clean tree before step 3 lands.
