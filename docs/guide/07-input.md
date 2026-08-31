# 7. The input story

> ## ⚠️ Facet requires the Input Action System
>
> Facet's input layer is built on Roblox's **Input Action System** (IAS)
> — `InputContext`, `InputAction` and `InputBinding` — and nothing else. It never
> reaches into `ContextActionService`. That is a deliberate architecture choice.
> Arbitration is the engine's job. A UI framework that quietly outbid a game's
> own bindings would be worse than the symptom it fixed.
>
> **So the experience has to put Roblox's own player scripts on IAS too:
> `Workspace.PlayerScriptsUseInputActionSystem` must be `Enabled` in every
> place.** Roblox describes it as controlling "whether the built-in player
> scripts are updated to use the Input Action System"
> ([`Workspace` API reference](https://create.roblox.com/docs/reference/engine/classes/Workspace)).
>
> **Declare it in your Rojo project** — that is the versioned way, and it works:
>
> ```json
> "Workspace": { "$properties": { "PlayerScriptsUseInputActionSystem": "Enabled" } }
> ```
>
> Every Facet place project does this, and so do both of Rascal Rally's. The
> older wording here said the flag was "not Rojo-syncable." That was wrong.
> Because of that error, five shipped place projects went without the
> declaration for months, and a human had to re-tick the property by hand after
> every rebuild. It needs the rokit-pinned toolchain: a stale `rojo` fails the
> build with `Unknown property` (see `tools/build_places.sh`).
>
> The flag is still **not scriptable**: no code (including Facet) can read it,
> set it, or verify it for you, on any build. Every detector Facet ships is
> therefore behavioral — it observes a symptom, never the setting. The closest
> reading available is `gamepad_contention.iasPlayerScriptsActive()`, which
> looks for the default contexts the IAS player scripts create
> (`Player.InputContexts.CharacterContext` and friends) rather than for the flag.
>
> **Why it matters — two measured symptoms, one cause.** With the flag off,
> Roblox's own scripts hold keys through `ContextActionService`, *outside* IAS:
>
> - **Gamepad `ButtonA` is eaten** by the legacy control scripts' `jumpAction`,
>   so your UI's gamepad Activate goes silently dead (D-pad still works, which
>   is what makes it confusing).
> - **The arrow keys `Left` and `Right` never arrive**, because the default
>   camera binds them as `RbxCameraKeypress` at ContextActionService (CAS)
>   priority 2000 and sinks
>   them. Any Facet surface that navigates or adjusts on the horizontal arrows
>   simply does nothing.
>
> **No priority number fixes either one.** A sinking CAS binding consumes a key
> before any `InputContext` is offered it, at any priority. Measured: a CAS
> sink at priority **100** beat an `InputContext` at **10000**
> (`the-camera-still-owns-the-arrow-keys`).
> CAS priority and `InputContext.Priority` are not one arbitration space. The
> property is the fix: it moves those bindings *into* the space where priority
> means something. With the flag on, player input joins the same arbitration as
> every Facet action, and everything in this chapter works. If A-presses or
> arrows ever feel dead, start at
> [§7.4 Troubleshooting](#74-troubleshooting-and-hard-limits).

Roblox players arrive on four kinds of input: a **mouse**, a **touchscreen**, a
**keyboard**, and a **gamepad**. Facet's position (the studio's standing
principle) is that a control which only answers one of them is unfinished — so
the framework doesn't stop at *layouts* that adapt per device. Every control
ships its **interaction** for all four inputs, and the conformance suite fails
any control that would regress to mouse-only. This chapter explains what that
means for you as a consumer. The short version: mount controls, present the
screen, and the input story comes with it.

## 7.1 What you actually have to do

1. **Declare `Workspace.PlayerScriptsUseInputActionSystem = "Enabled"`** in your
   Rojo project (the warning above). Once, per place — versioned, not hand-ticked.
2. **Mount controls and present screens.** That's the whole input setup for a
   UI screen — no key bindings, no activation callbacks, no navigation wiring.
3. **In a game with an avatar:** present HUD surfaces with
   `{ responder = "passive" }` and bind the one-line touch-controls effect
   (both in [§7.3](#73-the-responder-chain-ui-in-a-game-with-an-avatar)).
4. **Optionally:** mount input hints (`Facet.inputHint`) where you want a
   "Press A / Press Enter" label.

Everything else in this chapter is explanation, not obligation.

## 7.2 The concepts: how input works everywhere by default

**Semantic actions, not keys.** Facet controls consume *semantic* actions —
**Navigate**, **Activate**, **Cancel**, **Adjust** — never raw key codes. The
presenter builds an `InputContext` per presented screen and binds each action
across the input classes that carry it: Activate is a tap on touch, a click on
mouse, `Return` on keyboard, `ButtonA` on gamepad (PlayStation **Cross** maps to
`ButtonA`, so one binding covers both console families). You never create a
context or bind a key for a control.

**Controls declare their input story; the presenter composes it.** Every
composite control — Table, VirtualList, TextInput, PopupButton, and anything
you build with the [new-control playbook](../extending/new-control.md) —
attaches an *input contribution* to the tree it mounts. An input contribution
is its focus groups, its activate handling, and its gesture idioms. When you
present a screen, the presenter discovers those contributions and wires them
together automatically. That is why the playlist example mounts a filter field
and a table and gets three things for free: field↔rows D-pad navigation, row
selection on A, and drag-reorder grab mode. It passes **zero** input options.
If you do pass a `present()` option (`onActivate`, `navigationGroups`, …), your
version wins for that one concern — consumer overrides are per-option.

**Focus and navigation derive from your layout.** The moving highlight a
keyboard or gamepad drives walks an order the presenter derives from the mounted
tree:

- An `HStack` row of buttons navigates horizontally.
- A `Grid` of tiles gets real 2-D navigation: left/right within a row, up/down
  across rows, column preserved.
- A plain column is a simple ring.

Layout adaptation and input adaptation move together. When a screen's layout
switches idioms per device, the presenter re-derives the navigation map from
what is actually mounted, every refresh.

**Input-appropriate idioms per class, chosen by the environment.** The
environment tracks `preferredInput` and device capabilities, and controls adapt
their affordances from it. The same table, for example:

- drag-reorders directly with a mouse.
- grows edit-mode ≡ handles on touch (pan scrolls, handles reorder).
- offers grab mode on a gamepad (A grabs the focused row, D-pad moves it, A
  drops).

Text fields raise a sinking text-entry context while editing, so typing is
never navigation. They also publish a keep-visible offset for when the
on-screen keyboard would occlude them. You choose none of this per consumer;
it ships with the control.

### 7.2.1 The desktop keyboard conventions

*What you have to do: nothing. No screen binds a key.*

When a **keyboard is live** and one of your surfaces **owns UI input**, three
conventions a desktop player already has in their fingers come with the surface:

**Tab and Shift+Tab walk the focus chain.** They move forward and back through
everything focusable on the active surface, in the order it is mounted. That is
the same order the arrows walk, but read linearly instead of directionally.

The difference matters in one place: a *contained* group (a `Grid` row, a
`Table`'s header) stops the arrows from wandering out of it sideways. Tab's
whole job is to leave, so it does.

Tab skips everything the arrows skip: a hidden node, a disabled control, a
losing `ViewThatFits` candidate, a row that has just become ineligible. That is
because it is one focus map, not two.

A modal traps Tab and gives focus back on dismiss. A control that scrolls into
view for the arrows scrolls into view for Tab.

Whether Tab **wraps** at the ends is the surface's call, not a control's:
`present(screen, { traversalWrap = false })` makes the end of the chain feel like
an end. The default wraps.

**Space activates, like Return.** Same verb, same once-per-press guarantee, same
disabled-control gate. In a game with an avatar this is exactly where the
responder chain earns its keep — and *which* surface mode you chose decides what
Space does:

| Surface | Space |
|---|---|
| `responder = "passive"` HUD, not engaged | **not bound at all** — the jump key is the player's |
| engaged-from-passive, or a modal | bound inside a **sinking** context above the gameplay band: the focused control activates and the avatar does **not** jump |
| a plain `present()` screen (engaged-open, **non-sinking**, priority 1500) | bound, and it does not sink — so what happens depends on what is underneath (below) |

That last row is the one to plan for, and it is better behaved than it looks.
Measured live against a real gameplay stack:

- with the **doc-sanctioned gameplay band** underneath — a game `InputContext` at
  priority **2000 with `Sink`**, which is what a real game uses — the game wins
  outright: Space reaches the game action and the UI **does not** activate. A
  plain screen sits at 1500, so anything above it that sinks takes the key first.
- with only the **non-sinking** default character contexts underneath, **both**
  fire: the focused control activates *and* the avatar jumps.

> **The avatar does not sit at 2000.** 2000 is the priority Roblox *recommends a
> game use for its own sink*. The shipped `PlayerModule`'s own measured contexts
> are **Camera 100, Character 150, Vehicle 200, Transformer 300** —
> an earlier version of this guide said 1000, which was simply wrong. Facet's
> behavior does not depend on that number: a plain screen is 1500 and an
> engaged one is 3000, and both clear all four regardless. Even so, do not
> size a context against the old number.

So a plain screen only shares Space with things that were not claiming it firmly
in the first place — exactly how its arrows have always behaved. If your screen
sits over gameplay and you want a definite answer, choose one:

- present it `passive` (and engage it),
- pass `sinkNavigation = true` to take the key, or
- declare `{ gameplayGuard = false }` to leave it alone, which binds neither
  Activate nor the guard.

Rascal Rally's results screen does the last of those, because it binds Space
itself for the celebration skip.

**The arrows adjust a focused value control.** Focus a `Slider`, a `Stepper` or a
`Rating` and Left/Right move its value — on any screen, including a grouped one
where Left/Right otherwise navigate. The control declares which axis is *its*
(`adjustAxis`), so the other axis still navigates and focus can always leave.
Comma/period and the shoulder buttons keep working as they did. A control that
declares no axis keeps its own model. `Table` is the example: its resizable
headers are navigation stops and adjust targets at once. Activate selects the
column, the arrows resize it, and Cancel releases it.

**Typing wins while a field is being edited.** Space types a space and the arrows
move the caret — neither activates anything and neither moves the focus ring.

Tab means *"I'm done here"*: the field commits through its normal validation path
first, and only then does focus move on. **On today's Roblox engine that last
sentence describes the framework, not the observed result.** While a `TextBox`
holds keyboard focus, the engine marks keyboard input `gameProcessed` and fires
no developer Input Action binding at all. So Tab inside a focused field
currently does *nothing*: it does not type a tab character, does not bypass
validation, and does not advance. This was measured live, and recorded with
the decision that followed it. Commit with `Return`
and then Tab. The commit-then-advance behavior engages with no code change the day
the engine delivers the key.

None of this appears on a device with no keyboard. All of it appears the
moment one becomes available. The framework reads the live capability set
(`interactionClasses.keyboard`), never a device name, so a tablet with a
keyboard case behaves like a desktop while touch keeps working. The bindings
are created and destroyed as that fact changes, so nothing is left sinking
behind a keyboard that went away.

One honest caveat: `UserInputService.KeyboardEnabled` feeds the *when*. It
describes the device class rather than a plug event, and Roblox publishes no
keyboard-connected signal to observe. The framework's response to the fact
changing is proven. Whether a mid-session USB plug on a real client moves that
fact at all is a physical-device row, and it is still open.

### The paradigm axis: not just *reachable*, but the right *shape*

*What you have to do: nothing. Read this to understand why the same control
feels native on a mouse, a phone, a keyboard, and a TV at once.*

A control adapts on three independent axes:

- **Layout** — how the tree arranges per size class.
- **Reachability** — every verb (Activate, Cancel, Navigate, Adjust) fires on
  every device.
- **Paradigm** — the *shape* each device expects: direct-drag versus grab-mode
  versus a grip handle, a hover preview versus a focus ring, a naked pan that
  scrolls versus a wheel.

A control can be perfectly reachable (A, Return, and a tap all fire) and still
feel wrong: a mouse-only reorder, no hover layer, a hairline focus ring across
the room. Every registered interactive control must satisfy all three axes,
and the conformance suite proves each one separately. Structural primitives
and new controls do not earn that claim until they are registered with the
corresponding proofs.

**Affordances read the live class set, never one preferred value.** Real
devices are multi-modal: a handheld is touch *and* gamepad at once; a desktop
with a pad connected is a pointer machine *and* a gamepad machine. The
environment exposes `interactionClasses` — the **live set**
`{ pointer, touch, gamepad, keyboard }` plus a single `primary`. A class is
*live* when its capability is present; `primary` (the `preferredInput` name) is
forced into the set so it is always live. Controls choose their structural
idioms from the **whole live set** — so a handheld shows the table's Edit/Done
handles *and* answers gamepad grab mode *and* answers grip drags simultaneously.
`primary` chooses **emphasis only**: which hint text leads ("Press A" vs "Press
Enter"), which idiom is foregrounded. It never gates whether an idiom exists.
That is why nothing disappears when a player picks up a controller mid-session.

**The per-class idioms, in one place:**

- **pointer** (mouse/trackpad) — direct manipulation. A row or handle is
  **directly draggable** (scroll is a separate channel: the wheel). A
  **hover** layer previews without committing, and a pressed dip confirms.
  Nothing essential lives only behind hover — it does not exist off pointer.
- **touch** — fingers, no hover, a **44 px hit floor**. A bare one-finger pan
  **scrolls**, so any reorder/drag appears behind an **edit-mode ≡ grip** or a
  long-press — never a naked pan. Text focus summons the on-screen keyboard and
  the field publishes a keep-visible offset so it is never occluded.
- **keyboard** — a visible **focus ring**; **Navigate** (arrows) moves it,
  **Tab**/**Shift+Tab** walk the whole focus chain, **Activate** (Return *or*
  Space) fires, **Adjust** (the focused control's own arrows, or comma/period)
  increments a focused value. (`Escape` is engine-reserved — never a Cancel key;
  see §7.4.) The desktop conventions are §7.2.1 below.
- **gamepad** — focus + select: **Activate → ButtonA** (PlayStation Cross),
  **Cancel → ButtonB** (Circle); reorder is **grab mode**; **Adjust** is
  focus-then-directional (D-pad L/R or L1/R1). Directional moves derive from
  on-screen geometry, not tree order. On some console stacks the D-pad arrives
  as **`Thumbstick1`**; Navigate binds that axis too, so it is never dead.

**Hybrid and hot-switch: a device can arrive mid-gesture.** Because every live
class gets its idiom at once, connecting a pad while dragging a row does not
take anything away. The drag finishes on the mouse; grab mode is simply *also*
available for the next reorder.

Every in-flight interaction — a drag, a grab, an open edit, a scroll offset, a
focus ring — has a defined outcome for a class flip (the affordance matrix
§C):

- **CARRY** — the state survives, and the newly-live class's idiom becomes
  additionally available.
- **CANCEL** — the gesture reverts cleanly to its pre-gesture snapshot. Never
  a wedge, never lost data.

A mouse unplugged mid-drag reverts the row to origin (no stuck ghost). A field
being edited when its on-screen keyboard docks ends through the normal
commit-or-revert path — it never silently drops typed text. You never write
any of this; it is the control's contract.

**Ten-foot (a screen across the room).** When the display class is large the
environment reports `distanceProfile == "ten-foot"` (keyed on
`effectiveDisplaySize == "Large"`, *not* on the input device — a keyboard on a
TV still earns it). `effectiveDisplaySize` is `displaySize` — the engine's own
`GuiService.ViewportDisplaySize` — corrected for one case the raw fact gets
wrong. A touch-capable device the engine still reports as `"Large"` (a PC
handheld's misdetection, not a television) reads `"Medium"` instead. That is
because a real ten-foot session never has a touchscreen. Every other device,
touch or not, sees no difference between the two facts. Four things change,
and they compose rather than multiply:

- **The whole size ladder scales by 1.5.** Type comes first: body text must
  clear roughly 29 pt at three metres. The same factor also drives control
  heights, paddings and gaps, icon sizes, corner radii, and the minimum
  focus-target size. The 44 px target floor becomes 66 px at distance. The
  factor is deliberately one number for both ladders. So **every
  text-to-control proportion at ten-foot equals its near proportion**: a 16 px
  label in a 44 px control becomes a 24 px label in a 66 px control. Nothing
  outgrows the chrome around it.
- **Overscan-safe margins** are inset on all four sides (a television clips its
  own edges). These are a *display* fact, not a size-ladder metric, so they are
  applied once and are **not** scaled by the factor above.
- **Reduced density.** A wide viewport resolves to the `regular` arrangement.
  A `minColumnWidth` grid takes its lane count against the `wide` breakpoint
  rather than the raw extent. The result is fewer, larger targets — never
  more of them than a desktop gets.
- **A strengthened focus state** (a thicker ring plus a slight scale, so focus
  reads across a room instead of as a hairline).

None of this needs an opt-in. The display facts flow through the environment, so
a surface presented with no theme package installed still measures capped lanes
and scaled metrics. What the *player's* own text preference does is unchanged
and independent. The engine applies it as an additive offset at draw time, and
the framework reserves for it at measure time. So the preference and the
distance treatment are each applied exactly once.

**A theme may state its own ten-foot ladder.** The 1.5 is *derived* — it fills in
wherever a package is silent. A package that means something specific about a
television declares `metrics.tenFoot` — dotted metric paths to absolute pixel
values at distance — and owns those numbers outright. This works exactly as an
authored `space.gutter` beats the derived one. Art geometry is never scaled: a nine-slice
border is painted at the size its recipe declares, so the reservation for it stays
the number the paint will be.

(TV-*remote* input — a D-pad-only constrained gamepad — is a separate, deferred
concern; it reuses this same ten-foot profile and is never a fifth device class.)

**How a control declares its paradigm behavior.** All of the above rides the same
input-contribution bundle a composite attaches to its root. Alongside
`focusGroups`/`handleActivate`/`syncGeometry`/`keepVisibleOffset`, the bundle
carries the paradigm seams this round added — all optional, each the *uniform*
way to express one idiom:

- **`adjustTargets(rootNode)` + `handleAdjust(path, direction)`** — the Adjust
  verb (a grip resize, a value stepper). The presenter binds the Adjust keys
  **only while focus sits on a declared target**, so a bare screen never shadows
  a game's arrow/bumper bindings when focus is elsewhere. `direction` is −1 or
  +1; longest-path-prefix wins, like Activate.
- **`handleCancel(focusedPath)`** — a transient surface (an open menu) is offered
  gamepad Cancel *before* the modal-dismiss branches. It returns true to
  consume (close) or false to fall through. A modal that *contains* such a
  control still dismisses on a second ButtonB.
- **`outsideDismiss = { active, dismiss }`** — while `active`, a tap outside the
  control's subtree dismisses it. The presenter synthesizes a transparent
  full-viewport catcher, so a tap on empty space closes it too — the modal
  two-zone model, without making the control a modal.
- **`transientScope = { active, rootPath? }`** — while `active`, focus is trapped
  within the subtree and restored to the trigger on deactivation.

The **PopupButton** is the worked example. It is an ordinary control on a plain
screen. Yet outside-tap dismiss, gamepad ButtonB close, and focus
trap-and-restore all work, because it declares these three seams. **Hover** is likewise an optional
adapter seam, allocated only when the pointer class is live (a pure-touch device
never pays for it).

**Modals dismiss on every input — through two zones.** Think of the screen as
two regions while a modal is up.

- **Zone A** is the modal's *painted* panel, plus a **24 px forgiveness ring**
  (so a near-miss beside the edge does nothing) and every button's 44 px hit
  rect. A tap here activates a control, or does nothing on empty panel. It
  **never** dismisses.
- **Zone B** is everywhere else. A tap here dismisses.

The presenter paints Zone B for you as a full-viewport **scrim/catcher** it
synthesizes beneath the top modal. A tap on empty black space closes the modal
too, not just a tap that lands on a button behind it. The modal becomes a real
barrier: lower surfaces can't be clicked through. And the dim is the visible
"tap here to close" affordance.

"Painted" is deliberate. An *invisible* fullscreen container contributes
nothing to Zone A, so a transparent `fill` modal root can't silently swallow
every tap. A *visible* fullscreen takeover correctly has no outside. Outside-tap,
gamepad `ButtonB` (PlayStation **Circle**), and a focusable Close/Cancel button
(reachable by the focus ring, `Return`/`ButtonA`) **all resolve to the same
non-destructive outcome** — the safety invariant. A modal where dismissing would
be dangerous or lose data sets `outsideTapCancel = false`, which now **swallows**
the outside tap (a true barrier — no dismiss, no clickthrough). Set
`scrim = "none"` for a transparent-but-still-catching popover. Outside-tap is a
touch/pointer concept only; gamepad and keyboard are unchanged (the scrim is
never focusable). There is deliberately no keyboard `Escape` binding — the engine
reserves it (see §7.4).

**Hints re-label themselves.** `UI.Text{ text = Facet.inputHint(core, env,
action) }` reads "Press A" on a gamepad and "Press Enter" on a keyboard, and
re-labels the same node with no remount when the player switches input
mid-session.

All of the above is engine-independent and enforced. The conformance registry
requires every interactive control to cite passing device-true tests for all
four input classes, so a mouse-only control cannot land.

## 7.3 The responder chain: UI in a game with an avatar

In a real game the avatar owns the controls by default, and UI must *take* them
politely and *give them back*. Facet calls this the responder chain. With the
IAS flag on (the warning at the top), avatar input and UI input arbitrate in
the same system. Arbitration runs on `InputContext` priority plus Sink, and
the presenter manages that for you through three surface modes:

**Passive (HUDs).** A speedometer or score readout — on screen, not being
navigated — presents as:

```lua
local hud = pres.present(speedoScreen, { responder = "passive" })
```

Its navigation context exists but is **disabled**, and while it is passive the
surface binds no keyboard keys at all: `Tab`, `Space`, `ButtonA`, arrows,
everything reaches the avatar untouched. Having the HUD on screen costs the
player nothing.

**Engaged (first responder).** When the player taps one of the HUD's
focusables, or you call `hud.engage()`, the surface enables its context. This
puts it in the engaged band (priority 3000, strictly above the doc-sanctioned
gameplay band at 2000) with Sink on.

Now the UI answers first. Arrows move its focus instead of the character,
`Tab` walks the focus chain, and `ButtonA`/`Return`/`Space` activate instead
of jumping. With a keyboard live, `Space` *is* the Activate binding, so the
same binding that fires the focused control also sinks the jump. With no
keyboard, it falls back to the no-op guard that has always caught it.
`hud.responder` reads `"engaged"`. The surface resigns — restoring avatar
input exactly — on Cancel (`ButtonB`), an outside tap, or `hud.resign()`.

**Exclusive (modals).** `presentModal` is engaged from the moment it opens
(3500+, stacking +500 per depth) and restores avatar input on dismiss. A modal
that genuinely wants the jump key (a word game binding `Space`) passes
`{ gameplayGuard = false }`.

**Touch controls follow along.** While any exclusive surface is up, the mobile
thumbstick + jump button should hide. Bind the client-only effect once in your
bootstrap:

```lua
local responder_effects = require(ReplicatedStorage.Facet.client.responder_effects)
responder_effects.bind(core, pres) -- toggles GuiService.TouchControlsEnabled
```

Like `roblox_env`/`roblox_input`, this module is client-only and deliberately
not on the `Facet.*` table (that keeps the main library safe to require from
server code — [chapter 2](02-architecture.md)).

### Saying "that mattered": `UI.sensoryFeedback`

Some moments deserve a physical acknowledgement — a purchase landing, a selection
snapping into place, an error. There are two of them, and they are different
kinds of moment, so the modifier has two forms.

**A value changed.** Give it the Readable whose change is the cause:

```lua
UI.sensoryFeedback(button, { trigger = purchaseState, event = "commit" })
```

**A control was pressed.** Give it the verb that press means:

```lua
UI.sensoryFeedback(UI.Button({ id = "Buy", label = "Buy" }), { activation = "commit" })
```

**In plain terms:** the framework emits `{ type, path }` on the presenter's
feedback bus. The names are a **closed** taxonomy of twelve: `activate`,
`select`, `adjust`, `pickup`, `commit`, `reject`, `cancel`, `arrive`, `land`,
`dismiss`, `supersede`, `celebrate`. A typo is an authoring error that lists
the vocabulary, not a silent no-op. The press form takes one extra word,
`"none"`, for a control you want felt as nothing.

**You almost never need to write it per button.** The press form cascades: put it
on a container and every control inside inherits it — including the ones a Chip,
a Stepper or a Table row build for themselves.

```lua
-- every chip in this row is a `select`, and none of them mention it
UI.sensoryFeedback(UI.HStack({ id = "Filters", children = chips }), { activation = "select" })
```

A control that declares nothing keeps the default it always had: pressing it
emits `activate`.

One thing to be clear about: **Facet plays nothing.** It publishes the verb.
A game decides whether that becomes a haptic pulse, a sound, or nothing at
all. `src/client/haptics.luau` is an opt-in, **default-off** adapter you bind
to the bus. What "success" feels like is a game's identity, not a framework's.
Whether a player wants to feel it at all is a setting your game owns, because
Roblox does not let game code read the player's own haptics preference.

### Turning verbs into something you can feel

Two lines, and your game is the one that wrote them:

```lua
local haptics = require(ReplicatedStorage.Facet.client.haptics)
local hap = haptics.new({ enabled = playerSettings.haptics })
hap.bind(presenter)          -- what a completed press and a changed choice feel like
hap.attachButtons(screenGui) -- what a press going DOWN feels like
```

**Three phases, and each one has a different owner of the moment.**

| phase | the moment | who fires it |
|---|---|---|
| `press` | the press goes **down** | the **engine**, through the button's own `PressHapticEffect`. Facet hands over a reference and never plays it. |
| `release` | the press **completes** | the bus — a press that was dragged away from never completes, so it is silent without a line of code saying so. |
| `select` | a **value changed** (`select` / `adjust`) | the bus, rate-limited: pulses closer together than the floor are **dropped**, not queued behind each other. |

**The cause decides the phase, not the verb alone.** A verb says *what*
happened; a completed press says *a control was pressed*. So a control that
declares `activation = "select"` feels the **release** phase when you press
it. A press completing is not a choice moving. The **select** phase fires
only when its value actually changes. Such a control is handed no press
effect at all: a choice has not moved yet when the finger lands.

**A keyboard or gamepad press is one moment, not two.** The `Activate` action
resolves on the key going *down*, so the completion arrives in the same instant
the engine would play the press effect. For those input classes the bus
contributes exactly **one** sensation — `release` — and anything else it would
have played for that control in that instant is dropped. (What the engine does
with its own press effect in that instant is the engine's, and undocumented; a
device pass is the only thing that can answer it.)

**The three default waveforms, by name.** They are Facet's own, tuned for the
role each phase plays, and they live in `src/client/sensory_profile.luau` where
you can read the exact numbers:

* **`contact`** — one short, crisp tap when the action goes down.
* **`settle`** — a lighter, rounder answer when the action completes.
  Deliberately weaker and slower than `contact`. The down edge is the event
  the hand expects; an equal answer on the way up would read as a double tap
  rather than a reply.
* **`tick`** — the smallest audible-to-the-hand step for a changed choice.

Every peak stays at or above `0.3`. Roblox records that intensities below
`0.1` may not trigger anything at all on some clients. An authored subtlety
under that floor is a silence that reports success. Every waveform is over
inside 34 ms, so rapid interaction cannot overlap two pulses perceptibly.

**Change one phase without touching a control.** Pass a partial profile; anything
you do not name keeps Facet's default:

```lua
haptics.new({
    enabled = true,
    profile = {
        -- your own waveform for the down edge
        press = { kind = "custom", name = "thud", keys = {
            { timeMs = 0, intensity = 0, mode = "Linear" },
            { timeMs = 8, intensity = 1, mode = "Cubic" },
            { timeMs = 40, intensity = 0, mode = "Linear" },
        } },
        -- a stock Roblox preset for the completed edge
        release = { kind = "preset", effect = "UIHover" },
        -- and nothing at all for a changed choice
        select = { kind = "silent" },
    },
})
```

A phase is one of exactly three shapes: `custom`, `preset`, `silent`. The
profile is validated when you construct the adapter. So a misspelled phase,
or a `custom` with no keys, is an error you read at the call site — not a
silence you discover on a phone. `{ kind = "preset", effect = "Custom" }` is refused
outright: a `Custom` effect with no waveform plays nothing while reporting
success.

**If a client cannot build a custom waveform**, the phase falls back to a stock
preset — never to a bare `Custom`:

| phase | fallback |
|---|---|
| `press` | `UIClick` |
| `release` | `UIHover` |
| `select` | `UIHover` |

**The limitation is worth knowing before you rely on it:** Roblox ships exactly
three UI presets, and `UINotification` means "draw attention away from
gameplay" — which is neither a released button nor a changed choice. So under
fallback **`release` and `select` are the same sensation**, distinct only by what
caused them. `hap.diagnostics().phases[phase].fallbackActive` tells you when a
phase is in that state.

**Declared controls are unchanged.** A button that declared its own verb still
gets that verb's preset for its press. A Buy button and a Delete button still
feel different. A control declared `"none"` — or one whose verb the adapter
deliberately silences — is unfelt on **both** edges.

That includes the invisible 44px activation band a control smaller than the
touch floor gets. The band carries the same declared verb and the same
disabled state as the face, so a control you silenced does not buzz two
millimetres outside itself.

**If you declare both forms on one control, you get two sensations.** That is
the honest answer, because two things happened:

```lua
-- a picker row that both changes a value AND is a control being pressed:
-- `tick` when the value moves, `settle` when the press completes
UI.sensoryFeedback(UI.sensoryFeedback(row, { trigger = choice, event = "select" }), { activation = "commit" })
```

To feel only the change, say that the control's own press means nothing — a
sentence the vocabulary already has:

```lua
UI.sensoryFeedback(UI.sensoryFeedback(row, { trigger = choice, event = "select" }), { activation = "none" })
```

**How you find out whether any of it worked.** You do not, from code. Roblox
has no capability API for haptics. `HapticEffect` cannot be asked whether it
fired. And the player's own haptics strength is unreadable from game code.

`hap.support()` answers with a five-state lattice: `supported` /
`unsupported` / `unknown` / `blocked` / `absent`. `unknown` means "attempt it,
expect nothing, publish no platform claim." A phone is permanently `unknown`,
because there is no probe for one. **Studio cannot feel anything either.**
The effects run locally there, and no motor is involved, so a silent Studio
session is not evidence of a problem. The one honest test is a hand on a
device. The showcase's `sensory_feedback` demo carries a calibration panel
with one row per phase and a live pulse counter, built for exactly that pass.

## 7.4 Troubleshooting and hard limits

**Gamepad A does nothing on my buttons.** The place is almost certainly
running the *legacy* control scripts. They bind `ButtonA` to `jumpAction`
outside IAS, even with no character, and consume it before IAS ever sees it.
(D-pad still works, which is why only A feels dead.) Fix: declare
`Workspace.PlayerScriptsUseInputActionSystem` (the warning at the top). The
flag can't be READ from code, so Facet ships a behavioral probe you can log or
surface in a doctor check:

```lua
local gamepad_contention = require(ReplicatedStorage.Facet.client.gamepad_contention)
if gamepad_contention.legacyStackActive() then
    warn("legacy control scripts detected — gamepad ButtonA may be contended: ",
        gamepad_contention.describeContention())
end
```

**Left and Right arrow do nothing.** Same cause, different binding: Roblox's
default camera holds `Left`/`Right`/`I`/`O` as `RbxCameraKeypress` through
ContextActionService at priority 2000 and sinks them, so horizontal focus
navigation and a Table's selected-column resize never see a keypress. Fix: the
same declaration of `Workspace.PlayerScriptsUseInputActionSystem`. There is no
alternative involving a bigger priority number — see the warning at the top of
this chapter for the measurement, and
`the-camera-still-owns-the-arrow-keys`
for the full session.

The probe for this one is separate from the gamepad probe, and it has to be.
Measured live, `RbxCameraKeypress` held the arrows in a session where
`jumpAction` was not bound at all, so `legacyStackActive()` answered `false`
while the arrows were owned:

```lua
local gamepad_contention = require(ReplicatedStorage.Facet.client.gamepad_contention)
if gamepad_contention.cameraKeysContended() then
    warn("an arrow key is held by a ContextActionService binding; Facet will "
        .. "not receive it: ", gamepad_contention.describeContention())
end
```

It reads the binding table directly, so `true` is a fact about this client right
now. `false` is narrower than it looks: CAS exposes no sink flag through
`GetAllBoundActionInfo`, so it means "no CAS action claims an arrow", not
"arrows are guaranteed to arrive".

**Ask these probes; Facet does not announce them.** None of them is wired to a
boot-time warning. In any place that has not declared the property they are
all true — which today is every default Studio session. A warning that
always fires is noise that teaches people to skip it. They exist so that when
something *is* dead you get an answer in one line instead of a session.

**UI-only places (no avatar at all)** — a menu shell, a lobby, Facet's own
gallery — may instead just disable the legacy control scripts:
`gamepad_contention.disableLegacyControls()`. This is the *only* situation where
disabling player input is acceptable; a real game keeps its avatar controls and
uses the responder chain (§7.3).

It returns `(uncontended, status)`, and the status is the part worth logging.
Where the flag is on there is no legacy stack to disable. The call touches
nothing and answers `true, "inert: IAS owns PlayerScripts"`, rather than
spending a bounded `PlayerModule` wait discovering the same thing. `"disabled"`,
`"unbound"` and `"unavailable"` are the three legacy-stack outcomes. A boolean
alone could not tell "I disabled the control module" from "there was nothing to
disable", which is how a place could carry both remedies with neither one live.

**Do not script `GuiService.CoreGuiNavigationEnabled`.** The CoreScripts
re-enable it, and it was never the cause of dead A-presses anyway.

**Tab is the players-list shortcut, and the players list wins.** Roblox's own
documentation files `Tab` under inputs that are *"reserved unless you disable
the respective feature."* The feature is the CoreGui **players list** (the
leaderboard). Roblox documents exactly one remedy:

```lua
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
```

No `InputContext` priority is documented to outrank CoreGui, so while the players
list is enabled (the default) assume `Tab` does not reach Facet's traversal
action. Tab is deliberately *not* in Roblox's hard-reserved set
(`Esc`/`F9`/`F11`/`F12`/`PrintScreen`). That is why Facet binds it rather than
refusing to. A UI-only place, a menu shell, or any game that has already
turned its leaderboard off gets the desktop convention for free. Everything else in
§7.2.1 — Space activation, the focused-value arrows, the scroll-into-view, the
modal trap — is unaffected either way, because none of those keys are contended.

Facet never disables your leaderboard for you. It gives you the same kind of
probe it gives you for gamepad `ButtonA`, so the loss is visible instead of
silent:

```lua
local gamepad_contention = require(ReplicatedStorage.Facet.client.gamepad_contention)
if gamepad_contention.traversalKeyContended() then
    warn("Tab traversal is contended by the CoreGui players list; ",
        gamepad_contention.describeContention())
end
```

Roblox's own keyboard UI navigation is a separate, coexisting feature:
**Backslash** enters UI-selection mode, then the arrows/WASD move and Enter
activates. Facet's arrows and Return do the same job inside a Facet surface,
and neither disables the other.

**`Escape` is engine-reserved.** It is permanently bound to the Roblox menu
and cannot be rebound. So there is no keyboard Cancel key. The sanctioned
keyboard path out of a modal is its focusable Close button (§7.2). It is a
justified exception to the four-input rule, recorded as one.

**A physical gamepad button cannot be proven headlessly.** The suite and
Studio's virtual input prove the handshake around `ButtonA`, but cannot press a
real Cross/A button end-to-end. That remains the standing, non-release-blocking
**`physical-device-confirmation`** rider — confirm on a real controller before
shipping a console-facing UI.

---

That completes the core guide. To review:

- [chapter 1](01-concepts.md) for the ideas.
- [chapter 2](02-architecture.md) for how the modules fit, and why.
- [chapter 3](03-getting-started.md) for a working screen.
- [chapter 4](04-tutorial-examples.md) for the guided examples.
- [chapter 5](05-styling.md) for the look.
- [chapter 6](06-client-server.md) for the server.

One appendix follows: [chapter 8](08-without-rojo.md), for installing and working
with Facet when you build directly in Studio and do not use Rojo.
