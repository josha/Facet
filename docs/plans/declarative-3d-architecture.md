# Declarative 3D architecture decision and spike

**Status:** Planned research. This is not approval to add 3D nodes to LuauUI.

## Initial recommendation

Declarative 3D should be a sibling system, not an extension of LuauUI's two-dimensional
blueprint and layout solver.

The systems can share fine-grained reactivity, keyed identity, ownership scopes,
transactions, error containment, and agent-friendly conventions. They should not
pretend that screen rectangles and Roblox world objects have the same layout,
authority, or lifecycle:

- 2D UI solves pixels, text, safe areas, focus, and per-player presentation;
- 3D composition uses CFrames, pivots, attachments, constraints, physics, streaming,
  replication, and security boundaries;
- shared world state is usually server authoritative, but client-only decoration,
  effects, previews, and per-player visibility are also valid. Presentation is not
  automatically server-side or identical on every client;
- a reactive graph or callback closure must never be replicated as state. Roblox
  replicates the resulting Instances/data under an explicit topology.

The stage must test this recommendation rather than treating it as settled.

## Questions to answer

Inventory concrete use cases: static prop layouts, repeated collections, reactive
visual properties, attachments, authored assemblies, client-only decoration,
server-owned shared objects, streaming in/out, and teardown. Keep physics controllers,
terrain generation, gameplay authority, networking replacement, and a general game
engine out of scope.

Compare at least these architectures:

1. adding world nodes to LuauUI;
2. a sibling declarative scene package using a shared reactive/lifecycle kernel;
3. a separate system with compatible authoring principles but no shared package.

Evaluate package boundaries, server/client topology, property authority, identity,
diffing, streaming, instance ownership, failure recovery, performance, testing, and
how a game prevents two endpoints from constructing the same authoritative object.
Decide whether extracting the reactive core is worth the migration risk; do not do it
merely for conceptual neatness.

## Required spike

Build the smallest isolated experiment that can disprove the chosen design. It must
stay outside LuauUI's public exports and production game code and demonstrate:

- a declarative hierarchy of Parts/Models with local transform composition;
- keyed add, remove, and reorder without recreating surviving objects;
- a reactive property update with bounded Instance writes;
- explicit server-owned and client-local roots so the same tree is never double-made;
- cleanup, reparenting, destruction, and a streaming-like disappearance/reappearance
  case;
- one invalid-authoring and one callback-failure path;
- counters or profiles that expose object, connection, and per-update cost.

Use Roblox-native mechanisms first. Do not drive physics objects every frame when a
constraint, attachment, animation, or ordinary replication mechanism owns the job.
Do not claim production performance from a desktop spike.

## Decision output

Write a plain-language ADR that says:

- whether to build the system at all;
- its name and repository/package boundary if recommended;
- which concepts are shared with LuauUI and which are deliberately different;
- its server/client/replication model and trust boundary;
- the first useful, bounded product milestone;
- non-goals, risks, migration cost, and the evidence needed before production use.

This stage may correctly conclude that no production implementation should follow.
It must not merge the spike into LuauUI, extract the core, or create a public package
without a later approved build step.

## Gate

Register `declarative-3d-architecture`. It passes with a reviewed ADR, alternatives
matrix, isolated runnable spike, topology and lifecycle proof, measured costs, fresh
architecture/runtime/platform reviews, and a clear recommendation. A PASS means the
decision is well supported, not that LuauUI now supports 3D layout.

