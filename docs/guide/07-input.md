# 7. The input story

> ## ⚠️ LuauUI requires the Input Action System
>
> LuauUI's input layer is built on Roblox's **Input Action System** (IAS:
> `InputContext` / `InputAction` / `InputBinding`). For a game with an avatar,
> that includes the player scripts: **you must tick
> `Workspace.PlayerScriptsUseInputActionSystem` in Studio's Properties
> panel, by hand.** The flag is not scriptable and not Rojo-syncable — no code
> (including LuauUI) can read it, set it, or verify it for you. It is a
> one-time, human checkbox, and it is the single thing LuauUI cannot do on your
> behalf.
>
> Why it matters: with the flag off, Roblox's *legacy* control scripts grab
> gamepad `ButtonA` outside IAS, and your UI's gamepad Activate goes silently
> dead. With the flag on, avatar input joins the same arbitration as every
> LuauUI action, and everything in this chapter simply works. If A-presses ever
> feel dead, start at [§7.4 Troubleshooting](#74-troubleshooting-and-hard-limits).

Roblox players arrive on four kinds of input: a **mouse**, a **touchscreen**, a
**keyboard**, and a **gamepad**. LuauUI's position (the studio's standing
principle) is that a control which only answers one of them is unfinished — so
the framework doesn't stop at *layouts* that adapt per device. Every control
ships its **interaction** for all four inputs, and the conformance suite fails
any control that would regress to mouse-only. This chapter explains what that
means for you as a consumer. The short version: mount controls, present the
screen, and the input story comes with it.

## 7.1 What you actually have to do

1. **Tick `Workspace.PlayerScriptsUseInputActionSystem`** in the Properties
   panel (the warning above). Once, per place.
2. **Mount controls and present screens.** That's the whole input setup for a
   UI screen — no key bindings, no activation callbacks, no navigation wiring.
3. **In a game with an avatar:** present HUD surfaces with
   `{ responder = "passive" }` and bind the one-line touch-controls effect
   (both in [§7.3](#73-the-responder-chain-ui-in-a-game-with-an-avatar)).
4. **Optionally:** mount input hints (`LuauUI.inputHint`) where you want a
   "Press A / Press Enter" label.

Everything else in this chapter is explanation, not obligation.

## 7.2 The concepts: how input works everywhere by default

**Semantic actions, not keys.** LuauUI controls consume *semantic* actions —
**Navigate**, **Activate**, **Cancel**, **Adjust** — never raw key codes. The
presenter builds an `InputContext` per presented screen and binds each action
across the input classes that carry it: Activate is a tap on touch, a click on
mouse, `Return` on keyboard, `ButtonA` on gamepad (PlayStation **Cross** maps to
`ButtonA`, so one binding covers both console families). You never create a
context or bind a key for a control.

**Controls declare their input story; the presenter composes it.** Every
composite control (Table, VirtualList, TextInput, PopupButton, and anything you
build with the [new-control playbook](../extending/new-control.md)) attaches an
*input contribution* — its focus groups, its activate handling, its
gesture idioms — to the tree it mounts. When you present a screen, the presenter
discovers those contributions and wires them together automatically
([`ADR-0013`](../adr/ADR-0013-input-auto-wiring.md)). That is why the playlist
example mounts a filter field and a table and gets field↔rows D-pad navigation,
row selection on A, and drag-reorder grab mode with **zero** input options
passed. If you do pass a `present()` option (`onActivate`, `navigationGroups`,
…), your version wins for that one concern — consumer overrides are per-option.

**Focus and navigation derive from your layout.** The moving highlight a
keyboard or gamepad drives walks an order the presenter derives from the mounted
tree. An `HStack` row of buttons navigates horizontally; a `Grid` of tiles gets
real 2-D navigation (left/right within a row, up/down across rows, column
preserved); a plain column is a simple ring. Layout adaptation and input
adaptation move together: when a screen's layout switches idioms per device, the
navigation map is re-derived from what is actually mounted, every refresh.

**Input-appropriate idioms per class, chosen by the environment.** The
environment tracks `preferredInput` and device capabilities, and controls adapt
their affordances from it — the same table drag-reorders directly with a mouse,
grows edit-mode ≡ handles on touch (pan scrolls, handles reorder), and offers
grab mode on a gamepad (A grabs the focused row, D-pad moves it, A drops).
Text fields raise a sinking text-entry context while editing so typing is never
navigation, and publish a keep-visible offset when the on-screen keyboard would
occlude them. You choose none of this per consumer; it ships with the control.

### 7.2.1 The desktop keyboard conventions

*What you have to do: nothing. No screen binds a key.*

When a **keyboard is live** and one of your surfaces **owns UI input**, three
conventions a desktop player already has in their fingers come with the surface:

**Tab and Shift+Tab walk the focus chain.** Forward and back through everything
focusable on the active surface, in the order it is mounted — the same order the
arrows walk, read linearly instead of directionally. The difference matters in one
place: a *contained* group (a `Grid` row, a `Table`'s header) exists so the arrows
cannot wander out of it sideways, and Tab's whole job is to leave, so it does.
Everything the arrows skip, Tab skips — a hidden node, a disabled control, a
losing `ViewThatFits` candidate, a row that has just become ineligible — because
it is one focus map, not two. A modal traps Tab and gives focus back on dismiss.
A control that scrolls into view for the arrows scrolls into view for Tab.

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
> game use for its own sink*. The shipped `PlayerModule`'s own contexts, measured
> 2026-08-03, are **Camera 100, Character 150, Vehicle 200, Transformer 300** —
> an earlier version of this guide said 1000, which was simply wrong. Nothing in
> LuauUI's behavior turns on it (a plain screen is 1500 and an engaged one 3000,
> which clear all four regardless), but do not size a context against the old
> number.

So a plain screen only shares Space with things that were not claiming it firmly
in the first place — exactly how its arrows have always behaved. If your screen
sits over gameplay and you want a definite answer, present it `passive` (and
engage it), or pass `sinkNavigation = true` to take the key, or declare
`{ gameplayGuard = false }` to leave it alone — which binds neither Activate nor
the guard. Rascal Rally's results screen does the last of those, because it binds
Space itself for the celebration skip.

**The arrows adjust a focused value control.** Focus a `Slider`, a `Stepper` or a
`Rating` and Left/Right move its value — on any screen, including a grouped one
where Left/Right otherwise navigate. The control declares which axis is *its*
(`adjustAxis`), so the other axis still navigates and focus can always leave.
Comma/period and the shoulder buttons keep working as they did. A control that
declares no axis — `Table`, whose resizable headers are navigation stops and
adjust targets at once — keeps its own model (Activate selects the column, then
the arrows resize it, Cancel releases).

**Typing wins while a field is being edited.** Space types a space and the arrows
move the caret — neither activates anything and neither moves the focus ring.

Tab means *"I'm done here"*: the field commits through its normal validation path
first, and only then does focus move on. **On today's Roblox engine that last
sentence describes the framework, not the observed result.** While a `TextBox`
holds keyboard focus the engine marks keyboard input `gameProcessed` and fires no
developer Input Action binding at all, so Tab inside a focused field currently does
*nothing*: it does not type a tab character, does not bypass validation, and does
not advance — measured live, recorded in
`artifacts/desktop-keyboard-navigation/decisions.md` (DKN-2). Commit with `Return`
and then Tab. The commit-then-advance behavior engages with no code change the day
the engine delivers the key.

None of this appears on a device with no keyboard, and all of it appears when one
becomes available — the framework reads the live capability set
(`interactionClasses.keyboard`), never a device name, so a tablet with a keyboard
case behaves like a desktop while touch keeps working. The bindings are created
and destroyed as that fact changes, so nothing is left sinking behind a keyboard
that went away.

One honest caveat about *when* the fact changes: it is fed by
`UserInputService.KeyboardEnabled`, which describes the device class rather than a
plug event, and Roblox publishes no keyboard-connected signal to observe. The
framework's response to the fact changing is proven; whether a mid-session USB
plug on a real client moves that fact at all is a physical row
(`artifacts/desktop-keyboard-navigation/review-packet.md`, DK-P2).

### The paradigm axis: not just *reachable*, but the right *shape*

*What you have to do: nothing. Read this to understand why the same control
feels native on a mouse, a phone, a keyboard, and a TV at once.*

A control adapts on three independent axes. **Layout** — how the tree arranges
per size class. **Reachability** — that every verb (Activate, Cancel, Navigate,
Adjust) fires on every device. And the **paradigm** axis: the *shape* each
device expects — direct-drag versus grab-mode versus a grip handle; a hover
preview versus a focus ring; a naked pan that scrolls versus a wheel. A control
can be perfectly reachable (A, Return, and a tap all fire) and still feel wrong
(a mouse-only reorder, no hover layer, a hairline focus ring across the room).
Every registered interactive control is required to satisfy all three, and the
conformance suite proves each axis separately. Structural primitives and new
controls do not earn that claim until they are registered with the corresponding
proofs.

**Affordances read the live class set, never one preferred value.** Real
devices are multi-modal: a handheld is touch *and* gamepad at once; a desktop
with a pad connected is a pointer machine *and* a gamepad machine. The
environment exposes `interactionClasses` (ADR-0015) — the **live set**
`{ pointer, touch, gamepad, keyboard }` plus a single `primary`. A class is
*live* when its capability is present; `primary` (the `preferredInput` name) is
forced into the set so it is always live. Controls choose their structural
idioms from the **whole live set** — so a handheld shows the table's Edit/Done
handles *and* answers gamepad grab mode *and* answers grip drags simultaneously.
`primary` chooses **emphasis only**: which hint text leads ("Press A" vs "Press
Enter"), which idiom is foregrounded. It never gates whether an idiom exists.
That is why nothing disappears when a player picks up a controller mid-session.

**The per-class idioms, in one place:**

- **pointer** (mouse/trackpad) — direct manipulation: a row or handle is
  **directly draggable** (scroll is a separate channel: the wheel), a **hover**
  layer previews without committing, and a pressed dip confirms. Nothing
  essential lives only behind hover (it does not exist off pointer).
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
take anything away — the drag finishes on the mouse; grab mode is simply *also*
available for the next reorder. Every in-flight interaction (a drag, a grab, an
open edit, a scroll offset, a focus ring) has a defined outcome for a class flip
(the affordance matrix §C): **CARRY** — the state survives and the newly-live
class's idiom becomes additionally available; or **CANCEL** — the gesture reverts
cleanly to its pre-gesture snapshot, never a wedge and never lost data. A mouse
unplugged mid-drag reverts the row to origin (no stuck ghost); a field being
edited when its on-screen keyboard docks ends through the normal commit-or-revert
path (never silently dropping typed text). You never write any of this — it is
the control's contract.

**Ten-foot (console on a TV).** When the display is large the environment reports
`distanceProfile == "ten-foot"` (keyed on `displaySize == "Large"`, *not* on the
input device — a keyboard on a TV still earns it). The presentation applies
**overscan-safe margins**, **reduced density** (a wide viewport resolves to the
`regular` arrangement — fewer, bigger targets), and a **strengthened focus state**
(a thicker ring plus a slight scale, so focus reads across a room instead of as a
hairline). It also intends to add an authored viewing-distance type floor. The
current 0.4 adapter composes that floor with a custom preferred-text scale, but
Roblox may already apply the player's preferred text size. That behavior is under
the native-text evidence gate: the final rule must apply the Roblox preference once
and the authored distance treatment once, with measured and painted bounds agreeing.
Do not rely on the old “preference × 1.5” formula as a settled contract. (TV-*remote*
input — a D-pad-only constrained gamepad — is a separate, deferred concern; it
reuses this same ten-foot profile and is never a fifth device class.)

**How a control declares its paradigm behavior.** All of the above rides the same
input-contribution bundle a composite attaches to its root (ADR-0013). Alongside
`focusGroups`/`handleActivate`/`syncGeometry`/`keepVisibleOffset`, the bundle
carries the paradigm seams this round added — all optional, each the *uniform*
way to express one idiom:

- **`adjustTargets(rootNode)` + `handleAdjust(path, direction)`** — the Adjust
  verb (a grip resize, a value stepper). The presenter binds the Adjust keys
  **only while focus sits on a declared target**, so a bare screen never shadows
  a game's arrow/bumper bindings when focus is elsewhere. `direction` is −1 or
  +1; longest-path-prefix wins, like Activate.
- **`handleCancel(focusedPath)`** — a transient surface (an open menu) is offered
  gamepad Cancel *before* the modal-dismiss branches; it returns true to consume
  (close) or false to fall through, so a modal that *contains* such a control
  still dismisses on a second ButtonB.
- **`outsideDismiss = { active, dismiss }`** — while `active`, a tap outside the
  control's subtree dismisses it, and the presenter synthesizes a transparent
  full-viewport catcher so a tap on empty space closes it too (the modal
  two-zone model, without making the control a modal).
- **`transientScope = { active, rootPath? }`** — while `active`, focus is trapped
  within the subtree and restored to the trigger on deactivation.

The **PopupButton** is the worked example: it is an ordinary control on a plain
screen, yet outside-tap dismiss, gamepad ButtonB close, and focus trap-and-restore
all work because it declares these three seams. **Hover** is likewise an optional
adapter seam, allocated only when the pointer class is live (a pure-touch device
never pays for it).

**Modals dismiss on every input — through two zones.** Think of the screen as
two regions while a modal is up. **Zone A** is the modal's *painted* panel (plus
a **24 px forgiveness ring** so a near-miss beside the edge does nothing, and
every button's 44 px hit rect): a tap here activates a control or, on empty
panel, does nothing — it **never** dismisses. **Zone B** is everywhere else: a
tap dismisses. The presenter paints Zone B for you as a full-viewport
**scrim/catcher** it synthesizes beneath the top modal, so a tap on empty black
space closes the modal too (not just a tap that happens to land on a button
behind it), the modal is a real barrier (lower surfaces can't be clicked
through), and the dim is the visible "tap here to close" affordance.

"Painted" is deliberate: an *invisible* fullscreen container contributes nothing
to Zone A (so a transparent `fill` modal root can't silently swallow every tap),
while a *visible* fullscreen takeover correctly has no outside. Outside-tap,
gamepad `ButtonB` (PlayStation **Circle**), and a focusable Close/Cancel button
(reachable by the focus ring, `Return`/`ButtonA`) **all resolve to the same
non-destructive outcome** — the safety invariant. A modal where dismissing would
be dangerous or lose data sets `outsideTapCancel = false`, which now **swallows**
the outside tap (a true barrier — no dismiss, no clickthrough). Set
`scrim = "none"` for a transparent-but-still-catching popover. Outside-tap is a
touch/pointer concept only; gamepad and keyboard are unchanged (the scrim is
never focusable). There is deliberately no keyboard `Escape` binding — the engine
reserves it (see §7.4).

**Hints re-label themselves.** `UI.Text{ text = LuauUI.inputHint(core, env,
action) }` reads "Press A" on a gamepad and "Press Enter" on a keyboard, and
re-labels the same node with no remount when the player switches input
mid-session.

All of the above is engine-independent and enforced: the conformance registry
requires every interactive control to cite passing device-true tests for all
four input classes, so a mouse-only control cannot land.

## 7.3 The responder chain: UI in a game with an avatar

In a real game the avatar owns the controls by default, and UI must *take* them
politely and *give them back* — the Roblox analog of Apple's responder chain
([`ADR-0014`](../adr/ADR-0014-first-responder.md)). With the IAS flag on (the
warning at the top), avatar input and UI input arbitrate in the same system, by
`InputContext` priority + Sink, and the presenter manages that for you through
three surface modes:

**Passive (HUDs).** A speedometer or score readout — on screen, not being
navigated — presents as:

```lua
local hud = pres.present(speedoScreen, { responder = "passive" })
```

Its navigation context exists but is **disabled**, and while it is passive the
surface binds no keyboard keys at all: `Tab`, `Space`, `ButtonA`, arrows,
everything reaches the avatar untouched. Having the HUD on screen costs the
player nothing.

**Engaged (first responder).** When the player taps one of the HUD's focusables
— or you call `hud.engage()` — the surface enables its context in the engaged
band (priority 3000, strictly above the doc-sanctioned gameplay band at 2000)
with Sink on. Now the UI answers first: arrows move its focus instead of the
character, `Tab` walks the focus chain, and `ButtonA`/`Return`/`Space` activate
instead of jumping — with a keyboard live `Space` *is* the Activate binding, so the
same binding that fires the focused control sinks the jump; with no keyboard it
falls back to the no-op guard that has always caught it. `hud.responder` reads
`"engaged"`. The surface resigns — restoring avatar input exactly — on Cancel
(`ButtonB`), an outside tap, or `hud.resign()`.

**Exclusive (modals).** `presentModal` is engaged from the moment it opens
(3500+, stacking +500 per depth) and restores avatar input on dismiss. A modal
that genuinely wants the jump key (a word game binding `Space`) passes
`{ gameplayGuard = false }`.

**Touch controls follow along.** While any exclusive surface is up, the mobile
thumbstick + jump button should hide. Bind the client-only effect once in your
bootstrap:

```lua
local responder_effects = require(ReplicatedStorage.LuauUI.client.responder_effects)
responder_effects.bind(core, pres) -- toggles GuiService.TouchControlsEnabled
```

Like `roblox_env`/`roblox_input`, this module is client-only and deliberately
not on the `LuauUI.*` table (that keeps the main library safe to require from
server code — [chapter 2](02-architecture.md)).

### Saying "that mattered": `UI.sensoryFeedback`

Some state changes deserve a physical acknowledgement — a purchase landing, a
selection snapping into place, an error. Attach the declaration to any node and
name what happened:

```lua
UI.sensoryFeedback(button, { trigger = purchaseState, event = "commit" })
```

**In plain terms:** when the `trigger` Readable changes, the framework emits
`{ type = event, path }` on the presenter's feedback bus. The event names are a
**closed** taxonomy of twelve — `activate`, `select`, `adjust`, `pickup`,
`commit`, `reject`, `cancel`, `arrive`, `land`, `dismiss`, `supersede`,
`celebrate` — so a typo is an authoring error that lists the vocabulary rather
than a silent no-op.

One thing to be clear about: **LuauUI plays nothing.** It publishes the verb; a
game decides whether that becomes a haptic pulse, a sound, or nothing at all —
`src/client/haptics.luau` is an opt-in adapter you can bind to the bus. That split
is deliberate: what "success" feels like is a game's identity, not a framework's.

## 7.4 Troubleshooting and hard limits

**Gamepad A does nothing on my buttons.** The place is almost certainly running
the *legacy* control scripts: they bind `ButtonA` to `jumpAction` outside IAS —
even with no character — and consume it before IAS ever sees it (D-pad still
works, which is why only A feels dead). Fix: tick
`Workspace.PlayerScriptsUseInputActionSystem` (the warning at the top). The
flag can't be read from code, so LuauUI ships a behavioral probe you can log or
surface in a doctor check:

```lua
local gamepad_contention = require(ReplicatedStorage.LuauUI.client.gamepad_contention)
if gamepad_contention.legacyStackActive() then
    warn("legacy control scripts detected — gamepad ButtonA may be contended: ",
        gamepad_contention.describeContention())
end
```

**UI-only places (no avatar at all)** — a menu shell, a lobby, LuauUI's own
gallery — may instead just disable the legacy control scripts:
`gamepad_contention.disableLegacyControls()`. This is the *only* situation where
disabling player input is acceptable; a real game keeps its avatar controls and
uses the responder chain (§7.3). Full details:
[`docs/lessons/gamepad-contention-truths.md`](../lessons/gamepad-contention-truths.md).

**Do not script `GuiService.CoreGuiNavigationEnabled`.** The CoreScripts
re-enable it, and it was never the cause of dead A-presses anyway.

**Tab is the players-list shortcut, and the players list wins.** Roblox's own
documentation files `Tab` under inputs that are *"reserved unless you disable the
respective feature"* — the feature being the CoreGui **players list** (the
leaderboard) — and documents exactly one remedy:

```lua
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
```

No `InputContext` priority is documented to outrank CoreGui, so while the players
list is enabled (the default) assume `Tab` does not reach LuauUI's traversal
action. Tab is deliberately *not* in Roblox's hard-reserved set
(`Esc`/`F9`/`F11`/`F12`/`PrintScreen`), which is why LuauUI binds it rather than
refusing to — a UI-only place, a menu shell, or any game that has already turned
its leaderboard off gets the desktop convention for free. Everything else in
§7.2.1 — Space activation, the focused-value arrows, the scroll-into-view, the
modal trap — is unaffected either way, because none of those keys are contended.

LuauUI never disables your leaderboard for you. It gives you the same kind of
probe it gives you for gamepad `ButtonA`, so the loss is visible instead of
silent:

```lua
local gamepad_contention = require(ReplicatedStorage.LuauUI.client.gamepad_contention)
if gamepad_contention.traversalKeyContended() then
    warn("Tab traversal is contended by the CoreGui players list; ",
        gamepad_contention.describeContention())
end
```

Roblox's own keyboard UI navigation is a separate, coexisting feature:
**Backslash** enters UI-selection mode, then the arrows/WASD move and Enter
activates. LuauUI's arrows and Return do the same job inside a LuauUI surface,
and neither disables the other.

**`Escape` is engine-reserved.** It is permanently bound to the Roblox menu and
cannot be rebound, so there is no keyboard Cancel key; the sanctioned keyboard
path out of a modal is its focusable Close button (§7.2). Recorded as a
justified exception in `ADR-0013`.

**A physical gamepad button cannot be proven headlessly.** The suite and
Studio's virtual input prove the handshake around `ButtonA`, but cannot press a
real Cross/A button end-to-end. That remains the standing, non-release-blocking
**`physical-device-confirmation`** rider — confirm on a real controller before
shipping a console-facing UI.

---

That completes the core guide. To review: [chapter 1](01-concepts.md) for the
ideas, [chapter 2](02-architecture.md) for how the modules fit and why, [chapter
3](03-getting-started.md) for a working screen, [chapter
4](04-tutorial-examples.md) for the guided examples, [chapter
5](05-styling.md) for the look, and [chapter 6](06-client-server.md) for the
server.

One appendix follows: [chapter 8](08-without-rojo.md), for installing and working
with LuauUI when you build directly in Studio and do not use Rojo.
