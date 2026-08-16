# Declarative 3D — concrete use-case inventory

Stage `declarative-3d-architecture`. Grounded in the active game: a read-only
sweep of RascalRally's runtime world-instance systems (2026-08-13) found ~12–14
distinct systems; each category below cites the real ones. The honest headline:
**most world work is NOT a fit for a reactive graph** — it is one-shot builds,
physics-owned assemblies, or per-frame effect pools. The reactive sweet spot is
the middle band: state-driven, event-rate world composition.

**Out of scope, restated from the plan:** physics controllers, terrain
generation, gameplay authority/networking replacement, a general game engine.
Also out (by evidence below): per-frame effect driving — that stays with pools,
particles, and tweens, whatever this decision concludes.

## 1. Static prop layout (build-once composition)

- **Real:** `WorldBuilder.luau` — track folders, road/walls/boost pads built once
  at server start from deterministic authored data; `DriverStatueBuilder.luau` —
  statue rigs assembled once per kart. Generic: podiums, garages, lobby sets.
- **Fit:** declarative authoring helps CLARITY (a tree of specs beats 200
  imperative lines), but reactivity is irrelevant. A declarative system serves
  this only if mounting a static tree costs no more than the imperative build.
  Track/level geometry itself stays with the deterministic authoring pipeline
  (level design guide) — not this system.

## 2. Repeated keyed collections

- **Real:** `SponsorPlacements.luau` — sponsor pads and zones spawn on card play
  and expire, several times per race: a server-owned keyed collection that
  churns. Generic: pickups/respawns, checkpoint sets, per-player podium slots.
- **Fit:** THE core use case. Keyed reconcile preserving survivors, per-item
  scopes, leak-free teardown — exactly the UI `ForEach` discipline on Models.

## 3. Reactive visual properties

- **Real:** boost-pad active/cooldown color, sponsor-pad availability, race-gate
  state; today mostly attribute writes + ad-hoc scripts. Generic: door
  open/locked looks, objective highlights, team-colored props.
- **Fit:** sweet spot — event-rate value→property binding with bounded writes.
  NOT in this band: `KartStateFx`/`RemoteKart`/`ItemFx` per-frame transparency/
  position pools — those stay pooled/imperative or move to native particles and
  tweens; a signal graph at 60 Hz × 7 karts is the wrong tool and the inventory
  says so explicitly.

## 4. Attachments and authored assemblies

- **Real:** `PhysKart.luau` — compound physics puck (welded spheres, seat,
  constraint actuators). Generic: turrets on bases, sign clusters, prop kits.
- **Fit:** SPLIT by authority. Declarative assembly of a RIGID decorative
  cluster (welds, attachments, one pivot move) is in scope and the spike proves
  it. A physics-simulated assembly is built once and then OWNED BY PHYSICS — the
  declarative layer may construct it but must never drive its transforms after;
  constraint actuators (`KartSim`'s per-frame writes) are gameplay code, out of
  scope by charter.

## 5. Server-owned shared objects

- **Real:** sponsor pads/zones, track state objects — server builds them, Roblox
  replicates the Instances to every client natively.
- **Fit:** in scope with one hard rule: the reactive graph lives on the server
  only; what replicates is Instances + semantic state (attributes/tags), never
  signals or closures. Clients that need richer presentation reconstruct it
  locally from identity (category 6).

## 6. Client-local decoration

- **Real:** the whole statue/silhouette pattern, rival-kart presentation orbs,
  FTUE decals — client-created, never replicated, often attached to
  server-replicated anchors.
- **Fit:** in scope as an explicitly CLIENT-rooted tree; per-player and
  device-scaled presentation is legitimate (presentation is not equal on all
  clients). The binding-to-server-anchor case is category 7's twin.

## 7. Streaming in/out

- **Real:** RascalRally runs StreamingEnabled (Server Authority prerequisite);
  track content streams; karts are Persistent. Client decoration attached to a
  streamed server part must survive the part vanishing and returning.
- **Fit:** in scope and UNIQUELY 3D (no UI analogue). The system's client
  adapter needs a check-first, state-derived reattachment belt (the standing
  ROBLOX.md lesson class); the spike simulates loss/reentry, and a real
  streaming device pass is named future evidence.

## 8. Teardown

- **Real:** race end: sponsor placements cleared, FX pools released; today each
  system hand-rolls cleanup, and leak hygiene is per-author discipline.
- **Fit:** in scope — scope-owned instances/connections with reverse-order,
  idempotent disposal and counters back to baseline is precisely what the UI
  side already proves per-screen and the spike proves per-world-tree.

## What this inventory implies for scope

A worthwhile system covers categories 2, 3 (event-rate band), 5, 6, 7, 8, plus
the rigid half of 4 and the authoring-clarity half of 1 — and REFUSES the rest:
no per-frame driving, no physics-owned transforms, no track-geometry authoring.
That refusal list is as load-bearing as the feature list: the three biggest
runtime churners in the active game today (sponsor placements, kart-state FX,
rival-kart FX) split one-in / two-out, and the two out stay out on performance
grounds no framework can change.
