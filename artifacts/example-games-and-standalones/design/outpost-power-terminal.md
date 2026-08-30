# The Outpost Power Terminal — design

Two-dimensional Facet on a `SurfaceGui`, on a part the player walks up to and uses.
Binding scope: `docs/plans/example-games-and-standalones.md`, "World terminal:
two-dimensional UI on a 3D surface".

**What this is not.** It is not the declarative Part/Model layout Step 12 considered,
and it is not VR, ray, hand, or gaze support. It is the flat UI this framework already
renders, materialized somewhere other than a `ScreenGui`.

---

## 1. What the player does

You are standing in a small outpost. A console hums against the wall. Walk up to it and
a prompt appears: **Use the power terminal**.

The terminal has one job. The outpost generator makes **six units** of power, and three
things want it: the **blast door**, the **landing beacon**, and the **workshop**. Each
wants a whole number of units, each has a minimum below which it does nothing, and
together they cannot exceed six. You set the three numbers and press **Apply**.

When a valid allocation applies, the world answers: the door opens, the beacon lights,
the workshop's lamps come on — or they do not, depending on what you gave them. The
terminal says what changed. **Reset** puts the outpost back to its starting
allocation, and **Exit** hands you back to the game.

That is a small piece of a real game. It is deliberately not a render-target
diagnostic with buttons on it.

## 2. The rules

| | Minimum to work | Maximum useful |
|---|---|---|
| Blast door | 2 | 3 |
| Landing beacon | 1 | 2 |
| Workshop | 2 | 4 |

- Total available: **6**.
- Each value is a whole number from 0 to its maximum.
- An allocation is **valid** when the total is at most 6.
- The goal, stated on screen: **get all three running at once.** 2 + 1 + 2 = 5 does it,
  with one unit spare — so there is a right answer, more than one way to reach it, and
  a real trade-off (a fully-lit workshop at 4 leaves the door short).
- The starting allocation is 3 / 0 / 0: the door is open, and nothing else works. So
  the first thing the player sees is a problem with an obvious first move.

## 3. Why steppers and not sliders

Every value control on the terminal is a stepper — a labelled value with decrement and
increment — never a drag.

That is a design decision made *by* the render target, not around it. A slider needs
pointer capture, and pointer capture needs a coordinate space. On a `ScreenGui`,
`InputObject.Position` is inset-subtracted window space and the adapter corrects it by
adding the GUI inset. On a `SurfaceGui` that correction is not merely wrong, it is the
wrong *kind* of correction: the position is screen space and the solver's rectangles
are canvas space, and mapping between them means raycasting the adornee's face.

The plan's rule is "implement a capability correctly or remove it with its named
degradation; never let a screen-capability method appear to work when its coordinate
space is wrong". Whole units are also the better game rule — six units among three
consumers is a decision, not a dial. So the terminal is built from controls that need
only activation, and the adapter is honest about what it does not carry.

**The spike decided it, and the answer is steppers.** It proved that *activation*
reaches a surface control, and did not prove what coordinates a *capture* would carry —
so `setPointerHandlers` and `setTouchGestureHandlers` are deleted after construction,
the sanctioned move `billboard_target.luau` already uses, and the contract reports them
absent by name. A slider on this terminal would be a control whose coordinate space
nobody has measured.

## 4. The topology, and why each part of it

```
Workspace
  Outpost
    Console            (Part, Anchored, CanQuery = true)   ← the Adornee
      PromptAttachment (Attachment)
        UsePrompt      (ProximityPrompt)
    BlastDoor          (Part, server-owned)
    Beacon             (Part + PointLight, server-owned)
    WorkshopLamps      (Model, server-owned)

Players.<me>.PlayerGui
  Facet_Surface_OutpostTerminal   (SurfaceGui, client-owned)
      Adornee  → Workspace.Outpost.Console
      Face     → Front
      SizingMode = FixedSize, CanvasSize = the declared canvas
      AlwaysOnTop = false
      ClipsDescendants = true
      ZIndexBehavior = Sibling
    …the Facet tree the renderer materializes…
```

Four facts hold this together, and three of them are the kind that make a spike measure
nothing if they are wrong:

1. **The `SurfaceGui` lives under `PlayerGui`, with `Adornee` pointing at the part —
   and the reason is OWNERSHIP, not input.** This design originally repeated the
   contract's claim that a surface parented *into* the part is display-only. **The spike
   disproved it**: both topologies take input on Studio 0.736. The rule stands anyway,
   for the better reason — a `SurfaceGui` inside a Workspace part replicates to every
   player and is server-owned, and shared UI is what Facet must never build.
2. **The part must remain queryable.** `CanQuery = false` makes the surface unhittable
   while looking completely normal. The adapter requires it and says so; the Studio
   proof carries a negative control for both this and for wrong parenting.
3. **Client-owned, never replicated.** One `SurfaceGui` per player, built on that
   player's client. The UI tree is never replicated, and a second player's terminal is
   a second client's business.
4. **`presentationSpace = "world"`.** The environment fact exists today and has no
   consumer; this target writes the first one. Shipping the target without it would
   leave the fact decorative.

**The canvas.** A fixed virtual-pixel canvas, measured invariant to the part: one
`CanvasSize` held while the console was resized 8×5 → 4×2.5 → 16×10 → 8×2 studs
reported the same `400, 250` every time, and descendants read in canvas pixels. The
solver is fed one exact rectangle and a resize costs no re-solve. `face` is an explicit
required option with no default, because `Front` is the −Z face and a surface on the
wrong one renders perfectly and can never be clicked.

`AlwaysOnTop` is **pinned false and is not an option**, and the spike is why: with a
wall between the camera and the console, activation read 0 with it false, **1 with it
true**, and 1 with the wall removed. A player does not merely see the terminal through
geometry — they operate it.

## 5. Walk-up, engagement, and every way out

**Walk up.** A native Roblox `ProximityPrompt` on an `Attachment`. It is the
cross-input invitation the platform already ships, players already recognise it, and it
works on keyboard, gamepad, and touch without the example writing an input branch.
Facet does not wrap it.

**Engage.** Triggering the prompt engages exactly **one** Facet responder and focus
scope. From that moment: direct pointer and touch activate controls on the physical
screen; keyboard and gamepad drive the same semantic Input Action System actions and
the same logical focus as any screen UI. The example binds nothing through
`ContextActionService` or `UserInputService` — the semantic layer is the one input
authority, and a scan enforces it.

**Every way out, and what each must do.** Every one resigns the surface, cancels
in-flight input, restores gameplay control, and leaves nothing behind:

| Exit | Trigger |
|---|---|
| Cancel | The prompt's own cancel, or the platform back action |
| Exit control | The terminal's own **Exit** button |
| Out of range | Walking away past the prompt's `MaxActivationDistance` |
| Out of line of sight | The prompt requires it; losing it ends the session |
| Character removal | Death, or respawn |
| Adornee gone | The console streams out or is destroyed mid-session |
| Scenario switch | The showcase picker moves to another demo |
| Teardown | The place shuts the example down |

Repeated trigger-then-cancel, and hot-switching input device mid-session, are both
safe. Each of the eight is driven once in Studio with a leak census: no orphan
`SurfaceGui`, no orphan connection, no responder still holding input, no focus scope
still owning the graph.

## 6. Authority

The UI is per-player and client-owned. The *outpost* is not: opening the blast door
changes something every player can see.

So **Apply** does not change the world. It sends one domain intent — "set the
allocation to (door, beacon, workshop)" — to the server, which validates:

- the values are whole numbers inside their declared ranges;
- the total is at most six;
- this player is the one who engaged this console;
- the request is not arriving faster than a human could send it; and
- **the player is actually within range of the console right now**, measured on the
  server.

A client-side proximity check is a suggestion, not a fact. The server refuses an
invalid, stale, or distant command and says which, and the terminal shows the refusal
rather than pretending it worked. Three refusal drives — a value out of range, a stale
session, and a player who walked away between pressing and arriving — are part of the
Studio proof.

## 7. What has to be proved about the target itself

The plan requires evidence for each; the adapter ships nothing on faith.

| Property | What the evidence has to show |
|---|---|
| Canvas mapping | A solved rectangle lands where the canvas says, at more than one part size |
| Topology | The positive `PlayerGui + Adornee + CanQuery` case works; wrong parenting and a non-queryable adornee are negative controls that must fail |
| StyleSheets and theme | A `StyleLink` under a `SurfaceGui` resolves the same rules with the same cascade, and a theme swap repaints |
| Clipping | `ClipsDescendants` and the scroll host behave as they do on a `ScreenGui` |
| Text measurement | The engine's text bounds are the same numbers off a `ScreenGui` |
| Focus visuals | A focus ring is legible at the distance and angle the console is used from |
| Legibility | Normal and Largest text, at the working distance and obliquely |
| Occlusion | Behind geometry, edge-on, and off-screen: the controls do the documented thing |
| Pointer coordinates | A tap at a known point on the surface activates the control whose rectangle contains it |
| Every optional capability | Implemented correctly, or deleted with its degradation named |
| Lifecycle | Each of the eight exits in §5, with a leak census |
| Cost | Bounded against the same showcase at idle |

## 8. Where the code lives

| Module | Owns |
|---|---|
| `src/client/surface_target.luau` | **Facet.** The render target: canvas policy, root factory, topology requirements, capability declarations. A thirteenth blessed client entry point, built on the same root-factory seam `billboard_target.luau` uses, so it inherits the whole property chain, the recycling seams, and the parity pin rather than copying them. |
| `examples/…/outpost_terminal/` (content module) | **Example.** The declarative terminal screen, shared verbatim by the showcase scenario and the standalone place. |
| `examples/…/outpost_terminal/rules.luau` | **Example.** The pure power rules: ranges, validity, what "running" means, what a refusal says. |
| `examples/gallery/scenarios/runner.luau` | The engine seam that builds the world fixture, exactly as it already does for the billboard. Scenario modules stay engine-free; the runner touches Instances on their behalf. |

Six places currently assert that this target does not exist —
`tests/spatial.spec.luau` (four assertions, one of which fails the moment the file
lands), `artifacts/cross-platform-proof/rows/xp-d3-future-target.json`, the
`cross-platform-proof` gate row that reads it, `docs/adr/ADR-0021-spatial-seam.md` §4,
`docs/reference/api.md`'s "eleven unanswered questions and not implemented", and
`docs/extending/new-platform-mode.md`'s gate row. They are replaced together, in the
same change, or the repository contradicts itself.

## 9. The spike comes first

No adapter is published before a Studio spike answers
`target_contract.FUTURE.surface`'s open questions. The spike is a scenario, driven
through the existing `studio_sync` / `inject` / `_G.FacetScenario` path, and its rows
are recorded in a `check_spike.py`-readable artifact so a truncated file cannot pass as
evidence.

What the spike must answer before a line of adapter ships: the canvas mapping at more
than one part size; whether a `StyleLink` cascades identically; whether clipping and
the native scroll host behave; whether `GetTextBoundsAsync` answers the same numbers;
what a tap's coordinates actually are; and what happens when the adornee streams out
mid-session. Every one of those is a question whose wrong guess produces an adapter
that looks correct and is not.

---

## 10. Two facts about the showcase place that shape this, found before building

`examples/gallery.project.json` is the showcase's whole world, and it has two
properties this terminal collides with. Both are recorded here rather than
discovered halfway through.

### There is no server at all

The project maps `ReplicatedStorage`, `StarterPlayer.StarterPlayerScripts` and
`Lighting`. **It maps no `ServerScriptService` and no `ServerStorage`.** Every example
in this repository is client-only, which has been correct until now — none of them
changes anything another player could see.

This one does. "Applying power changes shared world state, so send domain intent to the
server" is not satisfiable in a place with no server, and faking it client-side would
teach exactly the lesson the plan forbids.

**So the showcase gains a server side**: `examples/gallery/server/`, mapped to
`ServerScriptService`, holding the outpost's authority and nothing else. It is small
and it is the point — a reader should be able to see, in one file, what the server
checks and why. It validates:

- each value is a whole number inside its declared range;
- the total is at most six;
- the sender is the player who engaged *this* console;
- the request is not arriving faster than a human could send it;
- and **the player's distance to the console, measured on the server**.

A `RemoteEvent` carries the intent one way and the outcome back. The UI tree is never
replicated; only the allocation is.

### `CharacterAutoLoads` is `false`, and a walk-up needs something to walk

`Players.CharacterAutoLoads = false` in the showcase, and that is deliberate: forty-odd
UI demos do not want an avatar standing in front of them.

A `ProximityPrompt` needs a character — it measures distance from one, and its own
`RequiresLineOfSight` is about one. So:

- **The showcase scenario loads a character when it is selected and removes it when it
  is switched away from.** That is scenario setup, exactly like the world fixture
  itself, and it belongs in the runner's engine seam beside `ctx.billboard` rather than
  in the scenario module — scenario modules stay engine-free.
- **The standalone place sets `CharacterAutoLoads = true`** in its own project, because
  a place whose entire content is a walk-up terminal has nothing to protect from an
  avatar.

This also makes character removal a *real* exit path rather than a hypothetical one:
the scenario's own teardown removes the character, so the "character removed" row in
§5 is exercised by the same control that switches demos.

### What this adds to the manifest's job

The place manifest now has to carry, per place: whether it needs a server side, whether
it auto-loads a character, and which world fixture it builds. That is the
"presentation target and world-fixture metadata" the plan already asks the manifest to
drive — this is simply the first place that needs it to be more than a name.
