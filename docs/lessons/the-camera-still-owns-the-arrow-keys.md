# The camera still owns the arrow keys

**Measured live in Studio, 2026-08-14** (LuauUI-Showcase, Play mode, the
`table_columns` fixture, real engine).

`src/controls/table.luau`'s column model puts a selected column's resize on
**Left/Right** (`api.handleGrabNavigate`, `:2855-2862`): a device Activate on a
header selects the column, and while it is selected the stick owns the direction
keys — Left/Right resizes, Up/Down cycles the sort. `tests/paradigm_table.spec.
luau:147` and `tests/table_columns.spec.luau` both prove it, green.

**On the live showcase it does not happen.** Left and Right never reach LuauUI.

## The measurement

Focus on `Head-team/Column`, Return pressed (the fixture's hint line changed to
`Team has the keys…`, so the *selection* landed — the Activate path is fine):

| input | `RbxCameraKeypress` | result |
|---|---|---|
| `Right` ×3 | **bound** | Team width unchanged (`Team auto` — no override committed at all) |
| `.` ×2 | bound | Team **405 → 437px**, the readout followed |
| `Right` ×2 | **unbound** | Team **437 → 469px** |

The third row is the control that makes the first row mean something. Without it,
"Right did nothing" is equally explained by "the selection model is broken" — and
that is the story I would have written, because it is the one the code invites.

## The cause

```
RbxCameraKeypress[Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.I, Enum.KeyCode.O] prio=2000
```

Roblox's own default camera script binds Left/Right through
`ContextActionService` at priority **2000** and **sinks** them. Nothing LuauUI
does is wrong; the key is consumed before any LuauUI handler is offered it.

`,` / `.` — the presenter's dynamically bound Adjust keys, live only while a
resizable header holds focus (`presenter.luau:2599-2639`) — are not contended,
which is why they work and why the fixture's on-screen hint names *them*.

## Why no test could see it

`tests/*.spec.luau` drive `system.deviceKey("Right", true/false)` straight into
`LuauUI.newActionSystem`. There is no camera script in a Lune process, no
ContextActionService, and therefore no contention: **the headless suite is
measuring a keyboard nobody has.** Every arrow-key assertion in this repo is a
proof about LuauUI's routing and says nothing about whether the key arrives.

This is the `an-instrument-nobody-runs` shape one level down: the instrument runs,
and it cannot see the thing.

## What already knew this

`examples/gallery/scenarios/runner.luau:1094-1100` unbinds `RbxCameraKeypress`
for any scenario declaring `keyboardFirst = true` — added during Step 8's desktop
keyboard round, recorded in `luauui-step8-desktop-keyboard`. So the repo has
known since 2026-08-03 that the camera eats arrows, and the knowledge lives in
**one host's opt-in flag**, not in the framework and not in the showcase. Every
surface reached through the demo picker — which is every surface a player can
reach in-experience — runs with the camera binding live.

## The ruling, and the measurement that withdrew it (2026-08-14, same day)

The director ruled the first option, narrowed:

> LuauUI claims the arrows at a priority above the camera's, SCOPED to the moment
> a column is actually selected for resize, and releases them the instant it is
> not — the same shape `row_actions` uses for Delete/Backspace/ButtonX. Verify the
> priority mechanism live rather than assuming a number works.

It was built exactly that way: a sinking `InputContext` named
`TableColumnKeys-<id>` at priority **10000**, created lazily on the first
selection, enabled only while `selectedColumn ~= nil`, with the Direction1D
neutralised on release so a claim let go mid-press could not come back deaf.
Live in the showcase it appeared on cue — `TableColumnKeys-Entrants prio=10000
sink=true enabled=true` the moment Return selected Team, `enabled=false` two Tabs
later.

**And Right still did nothing.**

| who is bound on Left/Right | LuauUI claim | result |
|---|---|---|
| `RbxCameraKeypress`, CAS prio 2000, Sink | `InputContext` 10000, Sink | Team **unchanged** (`auto`) |
| nothing (the camera unbound in-session) | `InputContext` 10000, Sink | Team **352 → 384px** |
| a CAS Sink at priority **100** | `InputContext` 10000, Sink | **the probe fired 2×**; Team unchanged |
| a CAS Sink at priority 2001 | (CAS, not IAS) | the claim fired 2×, camera 0 |

All four in one Play session, on source verified live in the datamodel first.

### The engine truth

**`ContextActionService` priority and `InputContext.Priority` are not one
arbitration space.** A sinking CAS binding consumes the key before *any*
`InputContext` is offered it, at *any* priority — row 3 is a CAS binding at 100
beating an InputContext at 10000. So there is **no number a framework can write on
an `InputContext` that takes a key back from a legacy CoreScript CAS binding.**
`RbxCameraKeypress` is un-outrankable from IAS, full stop.

Recorded in `src/client/gamepad_contention.luau` as ENGINE TRUTH 5 — the module
this repo already keeps this exact class of fact in — and checked by
`tests/gamepad_contention.spec.luau`, because there is no headless surface for
ContextActionService at all. That absence is why a whole ruling could be designed,
built and mutation-proved against a *headless model of the camera* (a sinking
context at 2000, which the model dutifully lost to at 1500 and beat at 10000)
while being wrong about the engine. **A model of the contention is not the
contention.** The model was right about everything except the one thing only the
engine knows.

### What shipped, and what did not

**Not shipped: the claim.** It was removed rather than left in. Where it could
fire at all (camera absent, row 2) the presenter's own focus-gated Adjust binding
already resized the column through the identical `stepColumnWidth` — so it had
zero observable effect anywhere, while still sinking Left/Right away from any
lower IAS context. Cost with no benefit is not a fix; it is a mechanism whose
only evidence is a fixture nobody runs in production.

**Shipped: the release.** Building the claim exposed a real, already-shipped bug
beside it. `releaseColumnOnFocusLeave` was driven only from `api.handleFocusMoved`,
and the presenter routes `focusMoved` **only to contributions whose mounted path
prefixes the newly focused one** — so focus leaving the Table entirely never
reached it. A column stayed selected after the ring had gone somewhere else, and a
selected column swallows *every* direction (`handleGrabNavigate` returns true for
all four, deliberately, so the selection cannot be steered off) and answers Cancel.
The ring on another control, the arrows still owned by a table nobody was looking
at. It is now driven from the focus graph (`bindFocusGraph`), the one source that
sees every move wherever it lands. Confirmed live: select Team, Tab twice, hint
line back to idle.

**Carried to the director, not taken:** row 4. A `BindActionAtPriority` claim of
LuauUI's *own* action above the camera's, unbound on release, works and hands the
key straight back — measured: the camera received the very next press. It is not
"unbinding the game's camera": the camera's binding is never touched. But it means
LuauUI reaching into ContextActionService, which `src/client/roblox_input.luau`
deliberately does not do ("arbitration is the ENGINE's job here — this adapter
never re-implements it", ADR-0004). That is a framework-architecture decision, so
it is reported rather than switched to.

**Unchanged and uncontended:** `,` / `.` and the bumpers, bound while a resizable
header holds focus. The fixture's hint line names them, and that is still the only
honest sentence it can print.

## The open question as it was posed

Whether a UI framework may unbind the platform's camera keys is a design call,
not a patch:

- **The framework does it** — LuauUI would be silently changing camera behaviour
  in any experience that embeds it, which is exactly the "never shadow gameplay
  bindings" rule that `api.adjustTargets` exists to honour (it binds Adjust *only*
  while a resizable header holds focus, precisely so a bare Table never steals a
  bumper).
- **The surface does it** — the `keyboardFirst` precedent, one opt-in per screen,
  and every screen has to remember.
- **The model moves off the arrows** — Adjust (`,` `.` / bumpers) already reaches
  every resize with no contention and no selection step at all, which makes the
  select-a-column-then-steer model the redundant half.

The third option — move the model off the arrows entirely, since Adjust already
reaches every resize with no contention and no selection step — is the one the
measurement above makes most attractive, and it is still open.

What must not happen again is a demo whose on-screen instructions name a key that
the platform eats. And now also: a ruling about arbitration that is proved against
a model of the arbiter.
