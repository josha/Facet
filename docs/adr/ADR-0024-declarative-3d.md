# ADR-0024 — Declarative 3D: build a sibling scene system on LuauUI's kernel, when a consumer arrives

**Status:** Accepted at stage PASS (2026-08-13), after four fresh-context
reviews (architecture, reactive-runtime, Roblox-platform, phase-gate) whose
verdicts and resolutions are recorded in
`artifacts/declarative-3d-architecture/reviews.md`.
**This ADR decides; it does not build.** Any build is a separately approved
mission. Evidence: `artifacts/declarative-3d-architecture/` (research, use-case
inventory, alternatives matrix, Studio topology traces with verbatim raw runner
output, measured costs) and `spikes/declarative-3d/` (the runnable disproof
spike, 18 headless cases + 19 live Studio probes, all green after the review
round's corrections).

## The system, explained like you're five

LuauUI is a machine for screens. You hand it a *description* — "a list of these
rows, this label shows that number" — and the machine keeps the real screen
matching the description while the numbers change, without ever redrawing more
than it must, and it cleans up perfectly when a screen closes.

The question here: should the studio have the same kind of machine for *things
in the 3D world* — Parts and Models, like pickup pads that appear when a card is
played and vanish when it expires? Today every system like that is hand-written:
create the parts, remember to recolor them, remember to destroy them, remember
what happens when the world streams out from under you on a phone. Each game
re-solves those chores, and each re-solve is a fresh chance for leaks and
double-builds.

## Decision, in one paragraph

**Build it as a SIBLING system — a new, separate package (working name
`LuauScene`, proposed home `GameStudio/world/LuauScene/`) that reuses LuauUI's
reactive kernel and conventions but none of its screen machinery — and do not
start building until a concrete consumer mission exists.** Do not add world
nodes to LuauUI (wrong shape: its solver, render contract, and presenter are
rectangle-and-focus machinery, and every public change taxes the shipping game).
Do not write a second independent kernel (two subtly different "engine rooms"
maintained forever). Do not extract LuauUI's core into a shared package today
(real migration churn for a production framework, zero present benefit) —
instead, when the build mission starts, LuauUI **blesses its core as a public
entry point**. Said precisely, because "blessing" is cheap but not free: the
semantic interface already exists as `src/core/contract.luau` (types only); the
runtime entry is `src/core/custom.luau`, and blessing it means one additive
export added to LuauUI's boundary-check allowlist, `api.md`, and the surface
ledger, shipped through LuauUI's own gate with the RascalRally consumer rider —
zero migration, one gated public-surface addition. Extraction is reconsidered
only if a third consumer of the kernel ever appears.

## What the spike proved (and what it disproved)

The spike set out to disprove the sibling-with-shared-kernel shape. It failed to
— every riskiest assumption held, measured live:

- **Kernel fit.** LuauUI's actual core (required as-is, not copied) drove
  Part/Model materialization with the same discipline it drives screens: one
  reactive change → exactly one adapter write (a per-signal guarantee — the
  order signals notify within one flush is unspecified, so multi-signal claims
  are bounds, not sequences); N writes in a transaction → one flush; a throwing
  callback quarantined without wedging anything; counters back to baseline on
  dispose, proven through the leak-capable shape (a churned keyed collection
  whose builds own per-item signals and memos). (18 headless cases,
  mutation-proven; 19 Studio probes.)
- **Identity fit.** Keyed collections preserve surviving Instances across
  add/remove/reorder — 100-item live collection: remove 10 = exactly 10
  destroys, survivors keep the same Instance refs. Reorder: identity-keyed
  placement makes a full reversal zero-churn live; order-derived placement
  writes only the transforms that actually changed (proven headless). The
  corollary a builder must know: a SURVIVOR's item content is ignored — builds
  run once per key, so live per-item facts are Readables the build wires up,
  owned by its scope.
- **Native mechanisms carry the motion.** One Luau CFrame write moved a 20-part
  welded assembly (the engine moved the other 19 parts); one `PivotTo` moved a
  Model's whole subtree. The reactive layer never writes per frame — matching
  official guidance that names server-side per-frame writes a mistake.
- **Topology fit.** Explicit server-owned and client-local roots, each stamped
  and check-first: the same declared root was never built twice, a client
  re-declaration of a server root was refused, and client-created roots were
  confirmed invisible to the server.
- **Streaming-shaped lifecycle.** A client decoration bound to a
  server-replicated anchor unmounted on loss and remounted exactly once on
  return, twice in a row, leak-free — using the official CollectionService
  added/removed signals.

Four findings the next builder must inherit (the first two from the live run,
the last two measured by the fresh reactive-runtime review and fixed in the
spike before this ADR closed):

1. **Under Immediate signal mode, removal signals fire before the removal is
   observable.** Inside `GetInstanceRemovedSignal`, the instance still read as
   in-game (`Parent` unchanged, `IsDescendantOf(game)` true). That is
   documented Immediate-mode semantics, not a universal engine fact: under
   `SignalBehavior=Deferred` (which Server Authority auto-sets and RascalRally
   hardcodes) handlers resume after the change, and an out-then-in pair inside
   one resumption cycle collapses to a single state read. The rule that is
   correct under BOTH modes: a state-derived belt re-reads state one scheduler
   step after the signal (`task.defer`), never inside it — and a Deferred-mode
   replay of the lifecycle probes is owed evidence, not assumed.
2. **Anchored root + WeldConstraint + unanchored children rides correctly** on a
   single root CFrame write — the cheap native idiom for rigid decorative
   assemblies (verified by engine-truth position deltas, not assumed). Its
   budget truth: every weld is a real Instance (~2x instance count for a fully
   welded assembly), and the rigid subtree must be welded ALL the way down —
   a non-welded descendant is refused at mount, because the headless model
   would call it riding while the engine leaves it behind.
3. **Read-then-subscribe loses writes made by user build code.** A build that
   writes a reactive source during mount runs in the window between the
   mount's initial read and its subscription; the write flushes before the
   observer exists and vanishes silently. The fix is a bounded convergence
   re-check after subscribing — now in the spike, pinned by a mutation-proven
   headless case.
4. **Per-item reactive resources need an owner.** A keyed collection whose
   builds create signals/memos leaks them into the core and the source's
   subscriber set on every churn cycle unless the build owns them into its item
   scope — measured unbounded before the fix (200 cycles: 6.9x slower updates).
   Builds therefore RECEIVE their item scope, and "counters at baseline on
   teardown" is proven against exactly this shape.

## Shared with LuauUI vs deliberately different

**Shared (the kernel and its conventions):** fine-grained reactivity (signals,
memos, observers, effects, transactions, glitch-free flush), scope ownership
with reverse-order idempotent disposal, quarantined user callbacks with sticky
diagnostics, keyed identity for collections, frozen-spec authoring,
adapter-seam testing with counters, plain-language API constitution style.

**Deliberately different (nothing below is shared):** no layout solver, no text,
no focus, no styling/theme system, no presenter. In their place: local-transform
composition materialized through native mechanisms (Model pivots, welds,
attachments), a world property-authority table (the declarative tree owns paint
and static placement; physics, animation, and in-flight tweens own their own;
predicted/simulated instances are entirely out of bounds), explicit
server/client root homes, and a streaming reattachment belt.

Authority specifics the reviews sharpened, carried as rules for the build:

- The authority table must be MECHANIZED, not asserted — a world authority
  manifest asserted at the adapter's write site, refusing declared props another
  mechanism owns (LuauUI's `assertWrite` precedent). The spike already enforces
  the first instances at mount: a welded child may not declare `anchored` (the
  weld owns anchoring) or a reactive transform (the parent's motion owns it).
- **Anchored→unanchored is an authority TRANSFER, not a tuning change.** Anchor
  a welded child and the assembly splits (its weld deactivates, it stops riding
  forever); unanchor the declared root and the engine re-elects the assembly
  root by mass, physics takes the transforms, and network ownership can move to
  a client. The declarative layer refuses to drive anything past that line.
- **PivotTo is a Luau-call-count win, not a free move**: the engine writes every
  descendant CFrame, and a server-side pivot of an N-part model replicates N
  CFrame changes. Choose it for call economy, budget it as N writes.
- **Semantic state rides attributes and tags within platform constraints**: the
  documented replication criteria (attribute count and name/value size limits),
  the 1KB total-payload trap, and the rule that a client must never stamp a
  tag on a server-replicated instance (untagged on the client when the server
  next writes its own tag list).

## Server/client/replication model and trust boundary

- A reactive graph or closure is NEVER replicated. The graph lives only on the
  endpoint that mounted it. What crosses the network is what Roblox replicates
  natively: the server-built Instances and semantic state (attributes, tags).
- **Server-owned roots** materialize on the server; clients receive the
  Instances. **Client-local roots** (decoration, previews, per-player
  presentation) materialize on the client and never replicate. Presentation is
  not assumed server-side or identical across clients.
- Double-construction is prevented by TWO layers, and naming them separately is
  the honesty the reviews demanded. The structural rule is HOME-PARTITIONED ID
  NAMESPACES: server code owns server-homed root ids, client code owns
  client-homed ones, and neither ever mounts the other's — enforced at the
  entry points, because under streaming an endpoint's view is incomplete
  ("not found" means unknown, never absent). On top of that rides the BELT:
  every materialized root is stamped (tag + root-id attribute) while still
  detached and parented last, so it replicates once already carrying its
  identity, and mounting is check-first — a client re-declaration of a
  replicated server root was refused live. What Play Solo proved is the
  in-view refusal; arrival-order races and the streamed-out-owner case are
  future evidence, listed below.
- Trust: nothing in this system moves gameplay authority. Server state remains
  authoritative; clients reconstruct presentation from replicated identity.
  Under Server Authority, predicted instances are matched partly by per-frame
  creation order, so the reconciler permanently refuses them (a platform
  mandate, not a preference).

## First bounded milestone (when a consumer mission is approved)

**`LuauScene` v0.1 — "server keyed collections + client decoration binder":**
the two proven probe scenarios productized, nothing more. Part/Model/ForEach/
When nodes, transforms + welds + pivots, topology stamps with home-partitioned
id namespaces, the streaming belt keyed on PER-INSTANCE identity (the signal's
instance argument, N anchors, and the official Spawned-attribute pattern to
tell a re-stream from a destroy+recreate), a world authority manifest asserted
at the adapter write site, counters and diagnostics, a fake adapter and
headless suite, one Studio scenario place. Its natural first consumer is
RascalRally's sponsor placements (the one true keyed world-collection churner
in the active game) as a SHADOW adoption proposal — its own mission,
game-director approval, no product change without separate authorization.
Categories it must refuse at v0.1, verbatim from the use-case inventory:
per-frame effect driving, physics-owned transforms, track/level geometry
authoring.

## Non-goals

Physics controllers; terrain generation; networking or replication replacement;
a general game engine; per-frame update loops; VR/spatial input; replacing the
art/level pipelines; any LuauUI public-surface change from THIS stage.

## Risks and costs

- **Shared-kernel coupling:** a kernel bug or semantic change now has two
  consumers. Mitigation: the kernel is contract-pinned with its own conformance
  suite; blessing (not extracting) keeps LuauUI's tree authoritative.
- **Streaming semantics are shakier than UI ever faces:** client-set properties
  can be lost on stream-out/in; client-children lifetime on streamed parts is
  officially undefined. The belt must re-apply state idempotently — designed in,
  but real-streaming proof is still owed (below).
- **Scheduling risk:** building without a consumer produces shelfware. That is
  why the build waits for a mission; the decision here settles SHAPE, not
  schedule.
- **Migration cost of the rejected extraction:** zero today — that is the point
  of blessing instead of extracting.

## Evidence still required before any production use

1. A real StreamingEnabled pass on a device (loss/reentry driven by actual
   streaming, not simulation), including client-decoration reattachment — and,
   for a characterless session, the server-set `Player.ReplicationFocus`
   prerequisite without which nothing streams.
2. A multi-client Team Test run (Play Solo cannot prove cross-client
   replication timing or the attribute/tag arrival-order trap), including the
   double-build races: a client mount racing the server mount, and a client
   mounting while the server's root is streamed out of its view.
3. A `SignalBehavior=Deferred` replay of every lifecycle probe (the spike place
   is Immediate-only; the property is not scriptable there, so this needs a
   place built with it set) — asserting handler-time state and that a
   collapsed out/in cycle neither duplicates nor leaks.
4. A Server Authority place probe (`AuthorityMode=Server` + next-gen
   replication): what SA changes for non-predicted decorative instances is
   undocumented, and the named first consumer runs SA.
5. A performance pass on the weakest target device with MicroProfiler evidence
   (desktop wall-clock here is context, not proof), including instance-count
   budgets that count welds (~2x for welded assemblies) and REPLICATION
   BANDWIDTH for runtime mounts — the docs single out runtime instance-tree
   creation as network-intensive, and call counts alone do not bound it.
6. The anchor destroy+recreate identity case (same tag, new instance) through
   the Spawned-attribute pattern, alongside real streaming.
7. A template-clone probe: Model placement on a cloned model WITH a PrimaryPart
   (the spike's models had none; the adapter now uses PivotTo, which is correct
   in both cases, and the probe proves it).
8. The LuauUI core-blessing change through LuauUI's own gate with the
   RascalRally consumer rider satisfied.

## Alternatives considered

`artifacts/declarative-3d-architecture/alternatives.md` scores all four shapes
(extend LuauUI / sibling with shared kernel / independent kernel / no build)
against ten criteria with the research citations. Extension fails on package
boundary, topology, and the solver shape mismatch; independence fails on kernel
drift; no-build fails on the recurring per-game cost of exactly the hard parts
the spike just proved once — and the ecosystem survey shows nobody else has
built those hard parts either.
