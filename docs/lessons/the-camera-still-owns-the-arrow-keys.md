# The camera still owns the arrow keys

**Measured live in Studio, 2026-08-14** (Facet-Showcase, Play mode, the
`table_columns` fixture (retired 2026-08-16 into the shipped playlist tutorial; the spec is now `tests/playlist_columns.spec.luau`), real engine).

`src/controls/table.luau`'s column model puts a selected column's resize on
**Left/Right** (`api.handleGrabNavigate`, `:2855-2862`): a device Activate on a
header selects the column, and while it is selected the stick owns the direction
keys — Left/Right resizes, Up/Down cycles the sort. `tests/paradigm_table.spec.
luau:147` and `tests/playlist_columns.spec.luau` both prove it, green.

**On the live showcase it does not happen.** Left and Right never reach Facet.

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
`ContextActionService` at priority **2000** and **sinks** them. Nothing Facet
does is wrong; the key is consumed before any Facet handler is offered it.

`,` / `.` — the presenter's dynamically bound Adjust keys, live only while a
resizable header holds focus (`presenter.luau:2599-2639`) — are not contended,
which is why they work and why the fixture's on-screen hint names *them*.

## Why no test could see it

`tests/*.spec.luau` drive `system.deviceKey("Right", true/false)` straight into
`Facet.newActionSystem`. There is no camera script in a Lune process, no
ContextActionService, and therefore no contention: **the headless suite is
measuring a keyboard nobody has.** Every arrow-key assertion in this repo is a
proof about Facet's routing and says nothing about whether the key arrives.

This is the `an-instrument-nobody-runs` shape one level down: the instrument runs,
and it cannot see the thing.

## What already knew this

`examples/gallery/scenarios/runner.luau:1094-1100` unbinds `RbxCameraKeypress`
for any scenario declaring `keyboardFirst = true` — added during Step 8's desktop
keyboard round, recorded in `facet-step8-desktop-keyboard`. So the repo has
known since 2026-08-03 that the camera eats arrows, and the knowledge lives in
**one host's opt-in flag**, not in the framework and not in the showcase. Every
surface reached through the demo picker — which is every surface a player can
reach in-experience — runs with the camera binding live.

## The ruling, and the measurement that withdrew it (2026-08-14, same day)

The director ruled the first option, narrowed:

> Facet claims the arrows at a priority above the camera's, SCOPED to the moment
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

| who is bound on Left/Right | Facet claim | result |
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
Facet's *own* action above the camera's, unbound on release, works and hands the
key straight back — measured: the camera received the very next press. It is not
"unbinding the game's camera": the camera's binding is never touched. But it means
Facet reaching into ContextActionService, which `src/client/roblox_input.luau`
deliberately does not do ("arbitration is the ENGINE's job here — this adapter
never re-implements it", ADR-0004). That is a framework-architecture decision, so
it is reported rather than switched to.

**Unchanged and uncontended:** `,` / `.` and the bumpers, bound while a resizable
header holds focus. The fixture's hint line names them, and that is still the only
honest sentence it can print.

## The resolution (director, 2026-08-15): it is a property, not a number

The open question below was answered, and the answer is not on the list — because
every option on that list assumed the framework had to win the key. It does not.

> Facet must **not** reach into ContextActionService. The Input Action System is
> the whole story, and there is a workspace property that makes Roblox's own
> player scripts use IAS. We can note in our docs we use IAS and this is required.

**`Workspace.PlayerScriptsUseInputActionSystem`.** Roblox documents it as
controlling "whether the built-in player scripts are updated to use the Input
Action System"
([`Workspace` API reference](https://create.roblox.com/docs/reference/engine/classes/Workspace),
`RolloutState`, ReadWrite). With it enabled, the camera is not on
ContextActionService at all — its keys are an `InputContext` like everyone
else's, and the arbitration this whole page is about becomes ordinary priority
arbitration, which Facet already participates in correctly.

So the ruling above was withdrawn for the right reason and the fix was in the
wrong layer. The claim at priority 10000 was inert because **no number can work**;
the repair is to change what the camera is bound *through*, and only the
experience can do that.

**Everything measured on this page stays true, and is now load-bearing for a
different purpose.** The engine truth — CAS priority and `InputContext.Priority`
are not one arbitration space — is exactly *why* the property is a hard
requirement rather than a nicety. If a bigger number worked, an integrator who
forgot the checkbox would merely have degraded input; because no number works,
they have **silently dead input with no in-framework remedy**. That is the
sentence the docs now carry.

### What the property is, precisely — and the misreading to avoid

Re-probed live 2026-08-15 on `0.734.0.7340915`. A plain read errors with
**"PlayerScriptsUseInputActionSystem is not a valid member of Workspace"**, which
reads like *this build does not have the property*. It is not that:

| probe | answer |
|---|---|
| `workspace.PlayerScriptsUseInputActionSystem` | `is not a valid member of Workspace` |
| `workspace:GetPropertyChangedSignal("PlayerScriptsUseInputActionSystem")` | **`is not a scriptable property`** |
| `workspace:GetPropertyChangedSignal("TotallyMadeUpPropertyXyzzy")` (control) | **`is not a valid property name`** |

Rows 2 and 3 are different sentences, and that is the whole finding: the property
**is** in this build's reflection database, with its scriptability off.
`StarterPlayer.CreateDefaultPlayerModule`, `Workspace.NextGenerationReplication`
and `Workspace.SignalBehavior` all answer identically — the capability-gated
Server-Authority setup class (`GameStudio/specialists/ROBLOX.md`).

The consequence is durable rather than a rollout window: scriptability is a
reflection-level flag, so **no Facet version on any Studio build will be able to
read this property**, and a newer build will not change that. Waiting for it is
not a plan. Every detector is behavioural, and the docs can tell an integrator to
tick it but can never assert that they did.

### The probe that was added, and the one that could not answer this

`gamepad_contention.cameraKeysContended()` — does any CAS binding currently hold
`Left`/`Right`/`Up`/`Down`? It reads `GetAllBoundActionInfo()` directly, so a
`true` is a fact rather than an inference.

It is a **separate** probe from `legacyStackActive()` on purpose, and one live
reading is why. In a Play session of the showcase, 2026-08-15:

```
CAS bound (6): RbxCameraKeypress(prio=2000, [Left Right I O]) | RbxCameraGamepadZoom(2000,
[ButtonR3]) | ScrollSelectedElement(2000, [PageUp PageDown Home End]) |
FreecamToggle(1000, [P]) | RbxCameraThumbstick(2000, [Thumbstick2]) |
EnableKeyboardUINavigation(2000, [BackSlash])
```

`jumpAction` **is not in that list** — the showcase is a UI-only place and had
already called `disableLegacyControls()`. So `legacyStackActive()` answered
`false` in the very session the arrows were owned. Jump and camera are separate
bindings from separate CoreScripts; a probe for one says nothing about the other,
and the older module comment claiming the controls-module disable does not free
the camera key now has a measurement under it.

**It does not warn on its own.** In every place that has not ticked the property
it is true, which today is every default Studio session, so a boot-time warning
would fire always and teach people to ignore it. It is asked, not announced —
the same contract `traversalKeyContended()` already had.

## The open question as it was posed — closed by the section above

Kept as it stood, because the shape of the miss is the useful part: all three
options below argue about *how the framework should take the key*, and none of
them asks whether the key had to be contended at all. The answer was the
experience's property, one layer up.

Whether a UI framework may unbind the platform's camera keys is a design call,
not a patch:

- **The framework does it** — Facet would be silently changing camera behaviour
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
measurement above made most attractive while the question stood. It is now a
plain design question about the column model rather than a workaround for a key
that cannot arrive: with the property enabled the arrows *do* arrive, so keeping
them costs nothing.

What must not happen again is a demo whose on-screen instructions name a key that
the platform eats. And now also: a ruling about arbitration that is proved against
a model of the arbiter.
