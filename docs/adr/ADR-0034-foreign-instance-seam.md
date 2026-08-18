# ADR-0034 — The foreign box: a hole in the closed set that claims one property and disclaims the rest

**Date:** 2026-08-15
**Status:** Accepted
**Supersedes:** nothing. **Amends:** `src/render/authority.luau`'s header claim that
`host` is "declared but unused" — closing carry-over **ARCH-F8**, which
dispositioned that authority as dead in the Step 5.5 cleanup ledger, and
satisfying requirement **UI-EXT-001** in a narrower form than it was written.
**Commissioned by:** [`docs/reference/react-lua-comparison.md`](../reference/react-lua-comparison.md)
§5 **rank 1 · BUILD NOW** — *"Facet has 26 classes and a seven-entry class map;
anything else becomes a `Frame`."*
**Companions:** [ADR-0024](ADR-0024-declarative-3d.md) (the 3-D/world-instance
case, decided separately and NOT this), [ADR-0029](ADR-0029-leaf-opacity-refusal.md)
(the refusal-that-names-the-alternative pattern this follows),
[ADR-0028](ADR-0028-cross-surface-overlap.md) (the cover-rect alarm this must not
blind), `fusion-comparison.md` §5 **G-2** (`Ref` — **still deferred**, and this
record does not overturn it), the `UI.Stage` seam
(`docs/research/2026-08-08-viewportframe-engine-facts.md`) which is the working
precedent for every part of this.

## Context — the gap, and why the obvious fix is worse than the gap

Every class Facet renders is one Facet declares. A consumer who needs a
`VideoFrame`, an `EditableImage` surface, a vendored widget, or any first-party
control the framework has not wrapped has **no route at all** — the class map
answers `Frame` and the pixels never arrive. The comparison ranks this first not
because it is the largest missing feature but because it is the only one with no
workaround: a framework with no escape hatch is a bet that its class list covers
everything, and that bet cannot be won.

The obvious fix is React's: `UI.Native{ class = "VideoFrame", props = { … } }`.
It should be refused, and the comparison says why in three lines that are each a
load-bearing property of this framework:

1. **It reopens the closed key set.** The schema cannot validate props it has
   never heard of, so `UI.Native{ props = { Vidoe = … } }` is accepted and
   ignored — the exact failure class constitution §4 exists to remove.
2. **It defeats property authority.** The manifest has no entry for a class it
   does not know, so nothing arbitrates a second writer — and on this engine a
   second writer is **silent**. Measured 2026-08-15 (ADR-0029 probe L1): an
   explicit write defeats a `StyleSheet` rule, fires no signal, and
   `GetStyled(prop)` returns *the write* from then on, so the rule's own value
   stops being readable at all.
3. **It breaks the measure model.** An `AutomaticSize` child measures itself,
   which the solver cannot see, so the box would be reserved at a size nobody
   measured — the `painted-vs-measured` defect family, by construction.

## Decision 1 — `UI.Foreign` takes no engine properties, and the emptiness is the design

`UI.Foreign{ id?, width?, height?, …, surface? }` — the shared box vocabulary the
solver already owns, plus the plate *behind* the content, and **nothing else**.

Every one of the three costs above is a cost of *accepting an engine property*.
Accept none and all three go away at once, without a mitigation, a heuristic or a
gate: the key set stays closed because there is no new key; authority is not
defeated because the framework claims almost nothing to defeat; and the box is
declared rather than inferred, exactly as `UI.Box`'s and `UI.Stage`'s are.

It is a **content leaf** to the solver — no children, no intrinsic size, measures
0×0 without dimensions — and it is **never elidable**. That second property is not
a preference: an elided node has no engine object at all, and this class's whole
purpose is that an object exists for somebody else's content to live in. Both
adapters' elision lists are allow-lists, so the guarantee is structural rather
than asserted, and `tests/foreign.spec.luau` pins both lists against a widening.

**The box is a promise, and `ClipsDescendants` is what makes it one.** The
container clips from birth, so nothing a caller adopts can paint one pixel outside
the rect the solver reserved. This is written once at creation and never again —
`clipChildren` is a `CONTAINER_LAYOUT` prop and `UI.Foreign` does not offer it, so
the renderer can never write this property on this class and there is no second
writer. The clip is also what keeps ADR-0028's cover-rect alarm honest about this
node (Decision 5).

## Decision 2 — the seam hands back nothing: `adopt(instance)`, not `contentRoot()`

**This departs from the shape §5 recommended, and the departure is the point.**
The comparison says the seam should *"hand the caller a container"*, mirroring
`stageHost`'s `contentRoot()`. Building it that way surfaced the problem: a
container handed out is a **framework-owned `GuiObject`** that the renderer writes
a rect, a plate and a visibility onto every solve — a writable handle to an
instance Facet owns and continues to write, which is precisely the hole
`fusion-comparison.md` §5 defers `Ref` for.

So the seam inverts. `controller.foreignHost(path)` answers one verb:

```lua
local host = controller.foreignHost("/Watch/Trailer")
if host ~= nil then host.adopt(myVideoFrame) end
```

The caller passes their instance **in**; nothing Facet owns travels **out**. The
framework's total surface area on the caller's side is one function call, and the
caller's total surface area on the framework's side is zero. `contentRoot()` is
deliberately absent, and `api.md` says so where a reader looking for parity with
`stageHost` will find it.

`stageHost` keeps its `contentRoot()`: a `WorldModel` is a bare container the
renderer never writes, and changing a shipped seam is not this round's business.
The asymmetry is recorded rather than smoothed over.

## Decision 3 — `host` goes live, owning exactly one property, and this is what it was reserved for

`Foreign.Parent = "host"` is now the manifest's only `host` entry.

**Was the reserved authority genuinely this seam? Yes — with one honest
qualification.** The evidence is direct: `host` had been in the `Authority` union
since phase 3 and, per the Step 5.5 cleanup ledger's disposition of ARCH-F8,
*"appears exactly once in the whole repo, its own type-union member"* — no
`MANIFEST` entry carried it and no `assertWrite` call passed it, *"because the
custom-control seam it was reserved for (UI-EXT-001) never shipped a blueprint
class."* And UI-EXT-001 reads, in `requirements.json`: **"Escape hatch: `UI.Custom`
mounts raw Instances under explicit contract (rects, tokens, owned properties,
disposal, diagnostics)."** That is this feature, named, five stages before it was
built.

The qualification is worth stating because it is the interesting part. UI-EXT-001
said **"owned properties"** — plural, a control declaring its own props with its
own authority. The bounded form owns **one**, and it is not an authored prop at
all: `Parent` cannot be written by any consumer, appears in no spec type, and
exists only inside the adapter's `adopt`. So the *name* was waiting and the
*vocabulary* was already wired (the theme linter's rejections and ADR-0019 §4
classify engine properties against this same five-name list, which is why the union
member was retained rather than deleted), but the *shape* is smaller than the
reservation described. The reservation was for a seam that claims; the seam that
shipped mostly **disclaims**, and needed exactly one row to say so.

**Why `host` and not `layout`.** The four live authorities all answer *"which
Facet writer owns this property of a Facet instance"*. This one answers a
different question — *"what does the framework claim over an instance it does not
own"* — and the answer being auditable is the entire safety argument. Putting it in
the manifest means the existing `assertWrite` gate carries it with no new
machinery: `assertWrite("Foreign", "Parent", "style")` is a loud error naming
`host`, exactly as every other second-writer attempt is.

**And "Facet writes nothing else" is structural, not a promise.** The seam
parents and **forgets**: no handle field, no registry, no closure captures the
adopted instance. A framework that holds no reference cannot write a property
later, whatever a future edit intends. `tests/foreign.spec.luau` walks the handle
after an adoption and fails if the content is reachable from it at all.

## Decision 4 — it dies with the box, and it never recycles

**Unmount.** The container is destroyed on `remove`/`destroyRoot`; engine `Destroy`
propagates; adopted content goes with it. This matches `UI.Stage`'s shipped
contract and is stated in `api.md` as a fact a caller must design around: content
that must outlive the node is re-parented out by its owner in `onDisappear`. The
rejected alternative — Facet unparenting the caller's content on the way down —
would be a second write on an instance we have just finished disclaiming, and it
would leak (nobody would then destroy it).

The **handle** goes dead separately from the instances (`markForeignDisposed`),
so a consumer holding a stale handle gets a refusal naming the node rather than a
silent parent-write into a corpse.

**Recycling.** A `Foreign` node is **never parked** into the instance pool.
Recycling hands an existing instance a new identity, and this instance holds
content the *caller* put there — a new node would inherit somebody else's video.
The refusal is keyed on `handle.foreignBox`, a field rather than a class name,
mirroring the Stage refusal for the reason platform review N3 gave (a degraded
Stage *is* parkable, so a class-name refusal made the fake stricter than the
adapter it mirrored). `Foreign` has no degrade case, so the field is always set —
and it is refused whether or not anything has been adopted yet, because a caller
may adopt at any time.

## Decision 5 — outside focus and input, inside the cover-rect alarm

**Outside focus, by construction rather than by policy.** `focusRole = "none"`,
no semantic actions, and inserting a `Foreign` between two `Button`s does not
change the Tab order. The reason is stronger than the one that keeps a `Stage`
unfocusable: the framework has never seen the adopted instance, so it *could not*
route a focus stop to it. The content's own engine input still works — a
`VideoFrame`'s controls, a vendored widget's buttons — Facet's traversal simply
cannot stop on it. A consumer who needs a focus stop composes one **around** the
box (a `Button` overlay, a focusable `Grip` sibling), exactly as they would around
a `Stage`. The control contract says this in full so it is discoverable from the
registry rather than from this record.

**Inside the overlap alarm, and the clip is why that is sound.** ADR-0028's
cover rect is the union of solved rects a surface actually paints; a `Foreign` box
joins it like any other leaf. That would be a *lie* if adopted content could paint
outside the box — a video pane spilling over a HUD would be invisible to the alarm
— which is the second reason `ClipsDescendants` is not optional. Clipped, the
solved rect is the whole truth about this node, and the alarm keeps meaning what
it says.

**Never a decoration surface.** A theme package's whole-art recipe covering the
box would cover content the framework does not know the shape of, so the create
path pins the no-slot hint unconditionally — the same fix the reference-app matrix
forced on `UI.Stage` in 2026-08-08, now a two-member table (`NO_DECORATION_CLASSES`)
so the hot mount path pays one index instead of a chain of compares. A theme still
reaches the box's *edge* through the authored `UI.stroke`/`UI.corners` modifiers.

## Decision 6 — every refusal names the alternative, at construction and at the call

Following ADR-0029: a capability the framework declined should say so where it is
reached for, with the argument and the line that works.

**At construction** (`schema.refusal`, extended with a class-scoped table):
`class`, `className`, `props`, `instance` and `native` on `UI.Foreign` are refused
with the three-part reason above and the `foreignHost(...).adopt(...)` spelling —
never a "did you mean". `tint` is refused separately, because it is a reasonable
thing to want and the answer is specific: a tint multiplies the node's own picture,
and this node's picture is the caller's instance.

**At the call** (`foreign_content.assertAdmissible`, pure and shared by both
adapters, so the words cannot drift): nothing-passed; a `LayerCollector` (a
`ScreenGui` cannot be a child of a `GuiObject`, so it can never render here); a
non-`GuiObject` — where the message points at **`UI.Stage` and ADR-0024**, because
a caller reaching this seam with a `Part` has the 3-D case, not a type error; and
an instance the engine has already destroyed.

That last one is the only rung an adapter cannot judge from pure facts: Roblox
offers no `IsDestroyed`, and a destroyed instance accepts every write **except** a
non-nil `Parent` ("Parent property is locked"). So the probe *is* the write — a
`pcall`'d parent into the container it was heading for anyway, which either
succeeds (the adoption is done) or fails (nothing moved, and the ladder re-runs
with `alive = false` to produce the sentence). This is the same detection the
recycling `adopt` has relied on since architecture review F9.

## Decision 7 — the one thing the framework does not write but still reaches, found live

**Measured in Studio during this round's live verification, 2026-08-15.** The
showcase's `foreign_content` demo mounted with its clip pane **empty**, and the
cause was not the seam:

```
adopted Frame:  raw BackgroundTransparency = 0
                GetStyled("BackgroundTransparency") = 1
```

A native-mode surface links a theme `StyleSheet` at its root, and a `StyleLink` is
**ambient in the DataModel and selects by class**. Facet's sheet carries
class-default transparency rules for the seven GuiObject classes it renders, so a
foreign `Frame` — an instance the framework has never heard of — wears
`BackgroundTransparency = 1` simply for being a descendant.

**And the escape is narrower than "just write the property".** A rule loses to an
explicit write, but the engine decides *explicit* **by value, not by assignment**.
The frame is born at `0`, which is the `Frame` class default, so writing `0`
changes nothing observable and the rule keeps winning. Writing `0.5` gave
`styled = 0.5`; writing `0` again went back to `styled = 1`. **A class-default
value cannot be held against a rule at all.**

**Is this an authority leak that should refuse the design? No, and the distinction
is exact.** The authority claim in Decision 3 is that Facet *writes* exactly one
property of the caller's instance, and that is still true — `GetStyled` and the raw
property disagreeing is the proof that nobody wrote it. What reaches the content is
the engine's own cascade, through a sheet the framework installs for its own nodes.
That is a *styling* effect, not a second writer: it is readable (`GetStyled`),
escapable (a non-default value), and absent entirely for the classes this feature
exists to reach — `VideoFrame`, `EditableImage` surfaces, a vendored widget's own
class are not selected by that sheet.

So the disclaimer is narrowed rather than withdrawn, and `api.md` states the
narrowed version where a caller will hit it. The alternative — suppressing the
sheet inside a `Foreign` box — would mean the framework generating a per-node rule
to un-style content it does not own, which is more authority over the caller's
instance, not less.

## Consequences

- **The class list is no longer a bet.** Any `GuiObject` Roblox ships is reachable
  from a Facet layout on the day it ships, with no framework change.
- **Cost, measured against the estimate.** The comparison estimated "one blueprint
  class, one render-target optional method, one solver content-leaf branch". The
  first two are exact. **The solver branch cost zero**: the solver has no `Stage`
  branch either — it already treats a leaf with no intrinsic content as a
  zero-intrinsic content box — so a class that declares its own dimensions needs no
  layout code at all. That is a fact about the solver worth having on the record.
- **Off the path, nothing changes.** A surface using no `Foreign` pays: one
  additional key in a schema table built once at load; one table index in the
  create path where there used to be one string compare (net neutral, and the
  `Stage` compare it replaced is now an index too); and one field test in the park
  eligibility chain. Measured in `artifacts/foreign-instance-seam/`.
- **`Ref` stays deferred.** Nothing here hands out an instance Facet created —
  Decision 2 exists specifically to keep that true — so `fusion-comparison.md`
  §5 G-2's refusal is untouched and should not be read as relaxed.
- **A consumer can now shoot themselves.** A caller may adopt an instance that
  paints badly, animates every frame, or costs more than the surface it sits in.
  The framework's contract stops at the box, and `api.md` says so plainly. This is
  the correct trade for an escape hatch — the alternative is the gap — but it is
  the first place in this framework where "Facet renders this correctly" has a
  stated boundary rather than being a whole-surface claim.

## Assumptions that depend on the tree being FLAT

Recorded deliberately, because [ADR-0032](ADR-0032-nested-instance-tree.md) moves
Facet from a flat instance tree to a **nested** one before first release, and this
seam is about parenting. Each of these is true today and should be re-examined
then; none of them is load-bearing for the *authority* argument, which is what
makes the design likely to survive.

**The one interaction ADR-0032 should not have to discover: recycling.** ADR-0032
notes that nesting *"disables recycling on the node it is applied to"* — 
`parkEligible` refuses any handle where `clipHosts[path] ~= nil`. A `Foreign` node
is **already** refused, unconditionally and for its own reason (Decision 4), so
registering one as an instance host under nesting **costs this class nothing** and
cannot regress a recycling win it never had. If the nesting round wants a rule of
thumb: `Foreign` is the one class where becoming a host is free.

1. **The container is a leaf's own instance, and no Facet node is ever its
   child.** That is why adopted content can be parented directly under the node's
   own `Frame` with no dedicated content child, and why the node is deliberately
   **not** registered as a `clipHost` (a clip host means "Facet nodes are
   re-parented under this instance and re-based against it"). Under a nested tree
   both statements need re-reading: a `Foreign` is still a leaf, so it should still
   have no Facet children — but the *reason* changes from "the tree is flat" to
   "this class takes no children", and the code should be made to say the second
   one.
2. **Adopted content is invisible to the path-naming scheme.** `instancesByPath`
   is keyed by Facet paths and the caller's instance is registered nowhere, keeps
   its own `Name`, and is never enumerated. Under nesting, any walk that recurses
   through *engine children* rather than through handles would start meeting
   foreign instances; every such walk must skip a `Foreign` node's children by
   construction, and `handle.foreignBox` is the flag to skip on.
3. **`ZIndexBehavior = Sibling` gives the caller a local stacking context.**
   Adopted content stacks inside the container above the plate, and Facet never
   writes the caller's `ZIndex` — which would be a second writer. Nesting does not
   obviously change this, but it changes what the container's own `ZIndex` means
   relative to its parent, so the "we never write your `ZIndex`" promise should be
   re-confirmed rather than assumed.
4. **The clip is the containment guarantee.** Under nesting an ancestor may also
   clip. That composes correctly (both clips apply) and no promise weakens, but the
   cover-rect argument in Decision 5 should be re-derived rather than inherited.
