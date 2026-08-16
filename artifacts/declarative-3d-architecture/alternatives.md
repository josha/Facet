# Declarative 3D — alternatives comparison

Stage `declarative-3d-architecture`. Four alternatives, one criteria set. Plain
language first; the ADR (docs/adr/ADR-0024-declarative-3d.md) carries the decision.

**ELI5 of the whole question.** LuauUI is a machine where you *describe* what a
screen should look like ("a list of these items, this label shows that number")
and the machine keeps the real screen matching the description as values change.
The question: should the studio have the same kind of machine for *world objects*
— Parts and Models in the 3D world — and if so, should it be part of LuauUI, a
sibling that shares LuauUI's engine room, or a separate thing? The engine room
("the kernel") is the part that tracks which values changed and tells exactly the
right listeners, once, in the right order, without leaks.

## The alternatives

- **A. Extend LuauUI** — add world nodes (`UI.Part`, …) to LuauUI's blueprint,
  mount, and renderer; a world render target joins ScreenTarget/BillboardTarget.
- **B. Sibling package, shared kernel** — a new, separate declarative scene
  package with its own vocabulary and adapters, driving the SAME reactive kernel
  LuauUI uses (`src/core/` semantics), plus shared conventions: keyed identity,
  scope ownership, transactions, error quarantine, API constitution style.
- **C. Independent system** — same authoring principles, but its own reactive
  kernel written fresh; zero code sharing with LuauUI.
- **D. No build** — keep imperative construction + native mechanisms; or adopt a
  community framework (Fusion/Vide) where declarative instances are wanted.

A research fact that frames all four (artifacts/declarative-3d-architecture/
research.md §6): **nobody has built the hard part.** Fusion and Vide are
instance-generic but have no streaming, replication, or external-destruction
awareness; the ECS school (jecs/Matter) leaves entity→Instance sync entirely to
the game; Roblox's own new `Roblox/signals` library is a state-only fine-grained
core with no world renderer. So "adopt instead of build" still means building the
topology/streaming/authority layer — the part this stage is actually about —
on someone else's kernel instead of our proven one.

## Criteria and verdicts

### 1. Package boundary and public surface

- **A** drags 3D vocabulary into a production UI framework whose contract is
  rectangle-shaped at the seam: `target_contract.REQUIRED` includes `setRect`,
  and the renderer's dirty queue is measure/arrange/paint — none of which means
  anything for a Part. Every LuauUI public change also pays the standing
  RascalRally consumer-lockstep tax (root CLAUDE.md rider) for zero UI benefit.
- **B** keeps LuauUI's surface untouched; the new package owns its own
  constitution-style rules. The kernel seam already exists as a typed interface
  (`src/core/contract.luau`) — sharing it is a dependency decision, not a rewrite.
- **C** identical boundary cleanliness to B, at the cost of a second kernel.
- **D** no boundary at all; each game keeps ad-hoc patterns.

### 2. Layout vs transforms (the shape mismatch)

LuauUI layout is a global two-pass solve: (tree, viewport) → rectangles. World
placement is local-transform composition onto a platform where parts carry only
world CFrames; the native mechanisms (Model pivots, welds/RigidConstraints,
Attachments) do the real work. There is no viewport, no text measurement, no safe
area, no focus. **A** would bolt a second, unrelated "layout" mode into one
solver pipeline; **B/C** give transforms their own small, correct home. This is
the single strongest structural argument and the spike tests its other half:
that the *kernel* (not the solver) is the part that transfers.

### 3. Server/client topology and double-construction prevention

UI is per-player and client-only by construction; world objects are not: shared
objects are server-owned (Roblox replicates the resulting Instances natively),
decoration/preview/per-player visuals are client-local, and presentation is not
automatically equal on every client. A reactive graph or closure must never be
replicated — only Instances and semantic state cross the network, and behavior is
reconstructed client-side from identity (tags/attributes), never shipped.

- **A** LuauUI has no concept of a server mount; retrofitting one touches
  presenter/env/client layers that are deliberately client-bound.
- **B/C** make root HOME explicit at the API's front door (`mountServer` /
  `mountClient` split at the runner/entry layer), stamp materialized roots, and
  can refuse the wrong endpoint at mount time. The spike proves the stamp-count
  probe on both datamodels.
- **D** leaves the double-construction rule as per-game discipline, which is how
  it is (inconsistently) handled today.

### 4. Identity, keyed diffing, lifecycle

Keyed reconcile preserving survivors, scope-owned resources, reverse-order
idempotent disposal — these transfer from UI conceptually unchanged; the spike
measures them on Parts/Models (survivor identity, counters to baseline). Equal
for A/B/C; **D** (Fusion/Vide) has keyed collection helpers but no scope-owned
connection-to-Instance counter discipline the studio's gates rely on.

### 5. Streaming

A client-side view of server world objects can vanish and return at any time
(StreamingEnabled). No UI concept maps to this. **A** would push streaming
awareness into a framework that never needs it; **B/C** put a check-first,
state-derived reattachment belt (the ROBLOX.md standing lesson) in the world
adapter where it belongs. **D**: every game re-solves streaming reattachment ad
hoc — today's status quo, and a recurring defect source.

Research sharpened this criterion into three platform facts any design must obey
(research.md §2, §7): streaming parents instances to nil (not Destroy) and
client-set properties "can be lost" across an out/in cycle, so a client overlay
must re-apply its state on stream-in; the official handle is CollectionService
tags + `GetInstanceAddedSignal`/`GetInstanceRemovedSignal`, whose firings are
indistinguishable from real spawns; and the lifetime of client-created children
of a streamed server part is genuinely undefined (contradictory official/forum
answers), so reattachment must be idempotent and leak-free in either outcome.

### 6. Property authority

One-writer-per-property transfers as a principle; the vocabulary does not.
World authorities are different in kind: the declarative tree may own paint and
STATIC placement, but physics owns a simulated assembly's transforms, animation
owns rigged joints, and native tweens own in-flight interpolation. A world system
must REFUSE to drive what another mechanism owns (the spike's welded-child rule
is the first instance: written once, then physically owned). **A** would overload
LuauUI's four authorities with meanings they were pinned against; **B/C** declare
a fresh authority table; **D** has no authority concept — silent double-writers
are exactly the bug class LuauUI's authority rule exists to kill.

One refusal is now platform-mandated, not just principled (research.md §3):
under Server Authority, `BasePart.CFrame` writes on predicted instances are
gated behind `BindToSimulation`, and the engine stitches predicted instances
across endpoints partly by per-script CREATION ORDER within a frame — so a
reconciler that reorders or conditionally skips creation would break stitching.
Predicted/simulated instances are therefore permanently outside this system's
authority: it builds decorative and anchored state-driven objects only, and the
ADR names that as a non-negotiable boundary rather than a tuning choice.

### 7. Performance posture

UI: coalesced flush → minimal writes → one adapter. World: identical *pattern* at
the kernel (transactions, one write per changed prop), plus native offload —
pivot moves, welds, tweens, particles — so the reactive layer stays out of the
per-frame path entirely. Research (research.md §1, §4) confirms the posture:
official docs name server-side per-frame property writes a mistake ("tween on
the client, not the server"), and `BulkMoveTo` is officially an
anti-recommendation ("setting CFrame of individual parts and welded models is
fast enough in the majority of cases") — so no special batched-write plumbing is
needed, and the win is WRITE AVOIDANCE (event-rate graphs, native interpolation),
which is exactly what a fine-grained kernel provides. The spike's counters are
the evidence; production device numbers are explicitly future proof. B's
advantage is reusing a kernel whose flush behavior is already benchmarked and
profiled (`LuauUI/mutate` + `LuauUI/react` spans).

### 8. Testing

**B** inherits the whole discipline for free: engine-free core, fake adapter
recording calls, headless specs, gate manifests. **C** inherits the *pattern* but
must re-prove kernel semantics (glitch-freedom, quarantine, disposal order) that
took LuauUI multiple verifier rounds to harden. **A** inherits it too but couples
3D regressions into a UI suite consumed by a shipping game. **D**: Fusion/Vide
write Instances directly with no adapter seam — headless testing of world logic
stays hard.

### 9. Maintenance and drift

- **A**: one repo, one suite — but every 3D change risks a UI regression and
  triggers consumer-rider work; the framework's "one framework" feel
  (api-architecture-consistency) erodes with a second domain vocabulary.
- **B**: the kernel becomes shared infrastructure. Honest cost: a kernel bug fix
  or semantic change now has two consumers; the kernel needs a BLESSED public
  seam (today `src/core/*` is internal — games/examples may not require it, and a
  sibling package doing so would institutionalize an internal import unless the
  seam is made deliberate). Options, decided in the ADR: bless the core factory
  as a supported LuauUI entry point (additive, no extraction), or extract a
  shared package (max cleanliness, real migration risk for a production
  framework). Doing nothing and importing internals is the one shape ruled out.
- **C**: no coupling, but two kernels drift — the same semantic ("observers fire
  once per flush, post-flush") maintained twice, verified twice, and eventually
  diverging in exactly the subtle ways that are expensive to find.
- **D**: no new maintenance, but the recurring per-game cost (streaming belts,
  double-construction discipline, leak hygiene) continues indefinitely.

### 10. Failure recovery

Quarantined callbacks, mount-time authoring errors naming the fix, error
boundaries per subtree — kernel-provided in A/B; re-implemented in C; absent in
D (a throwing callback in an ad-hoc builder takes its script down).

## Score summary

| Criterion | A extend | B sibling+kernel | C independent | D no build |
|---|---|---|---|---|
| Package boundary | poor | good | good | n/a |
| Transform/layout fit | poor | good | good | n/a |
| Topology + double-build | poor | good | good | poor |
| Identity/lifecycle | good | good | good | weak |
| Streaming | poor | good | good | poor (ad hoc) |
| Property authority | strained | good | good | absent |
| Performance posture | equal | equal + proven kernel | equal, unproven kernel | equal |
| Testing | coupled | inherited | re-proven | hard |
| Maintenance | UI-coupled | shared-kernel cost | drift cost | recurring per-game cost |
| Failure recovery | good | good | rebuilt | absent |

**B is the recommendation the spike set out to disprove; the spike and Studio
evidence (spike-headless.txt, studio-topology.json, costs.json) are the test of
its riskiest assumptions.** The ADR states the decision, the kernel-sharing
mechanism, and the first bounded milestone — and why D ("wait for a concrete
consumer") is the right answer for SCHEDULING even if B is the right answer for
SHAPE.
