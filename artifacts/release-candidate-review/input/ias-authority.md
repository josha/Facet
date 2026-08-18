# Input Action System authority — the wave R3 close

Evidence for the release-candidate gate row `ias-owns-semantic-input`. The
classification it rests on is
`artifacts/release-candidate-review/input/ias-inventory.md` (116 rows, `INPUT-1`
… `INPUT-116`); the platform authority every "can IAS express it" answer cites is
the 2026-08-17 live fetch recorded in that document's header. This file records
what changed, what deliberately did not, and what is still owed to a live engine.

| | |
|---|---|
| Framework | `GameStudio/ui/Facet` — suite **6412 passed** |
| Consumer | `games/RascalRally/code` — suite **3416 passed** |
| Baselines | 6407 / 3384 before this wave (+5 / +32) |
| Fix round 1 | the band ceiling (below), the guard deleted, a cross-system model added |
| Drift check | `tools/check_input_authority.py` — **8 allowlisted adapters, 6 ledger verbs, 0 new binders**; `--selftest` **8 cases green** |

---

## 1. Classification counts, before and after

The inventory's five classes partition its 116 rows exactly:

| Class | Rows | |
|---|---:|---|
| 1 — semantic action routing | 36 | 23 already on IAS · 9 on a legacy engine surface · 4 on the **deprecated** `InputAction:Fire()` |
| 2 — environment / capability observation | 18 | |
| 3 — raw pointer / keyboard geometry | 21 | + 2 secondary |
| 4 — engine interoperability / diagnosis | 30 | 22 code rows + 8 project-file rows |
| 5 — test-only injection | 11 | + 3 secondary |

Class 1 was the only one with anything owed. Its 13 non-compliant rows split:

| Verdict | Before | **After R3** | Rows |
|---|---:|---:|---|
| **MUST migrate** — IAS expresses it today | 5 | **0** | INPUT-90/91/92/93 (deprecated `Fire`) · INPUT-105 (`UIButton`) |
| **Cannot migrate** — no IAS surface exists | 6 | 6 | INPUT-32, 35, 36, 37, 39, 116 |
| **Partially expressible — keep** (payload loss) | 2 | 2 | INPUT-27, 33 |

Plus the prerequisite every arbitration claim rests on:

| | Before | **After R3** |
|---|---:|---:|
| Place/project files declaring `Workspace.PlayerScriptsUseInputActionSystem` | 3 of 8 | **8 of 8** |

**Nothing in class 1 is now routed through a legacy surface that IAS can
express.** The eight that remain are documented impossibilities or documented
payload losses, each with its citation in §4.

## 2. What migrated

### M-1 · `InputAction:Fire()` → a `Scriptable` `InputBinding` (6 call sites, 2 files)

`InputAction.Fire` is tagged **Deprecated** on the live class reference. The
sanctioned surface is `InputBinding:Fire(state)`, which *"respects the same
deduplication rules as hardware input"* and *"can only be called on bindings with
Type set to Scriptable — calling it on an Automatic binding will throw an error."*

The five `fired` actions (`steerTouch`, `steerAssist`, `brakeStick`,
`throttleStick`, `debugReset`) already carried **no** hardware bindings, so each
now gets exactly one child `InputBinding` with `Type = Scriptable`, created beside
the action in `InputRig.build` on the server, and the client Fires *that*:

- `src/server/InputRig.luau` — `scriptedBinding(action)` on the `fired` branch
- `src/client/InputBridge.luau` — `steerTouchBinding` / `brakeStickBinding` /
  `throttleStickBinding` (3 sites)
- `src/client/AssistPilot.luau` — `steerAssistBinding` (2 sites)

The binding's name is declared once, shared by both ends
(`InputActions.SCRIPTED_BINDING_NAME = "Scripted"`), so the resolve cannot drift
from the create. Zero behavioural change is the claim: identical dedup, identical
`Pressed`/`Released`/`StateChanged`.

**Pinned by** `tests/input_authority.spec.luau` — *"no module Fires anything but a
Scriptable binding"*, which walks every `:Fire(` in `src/client`, `src/server` and
`src/shared`, allows exactly one named non-IAS `BindableEvent`, and carries a
floor so a pattern that stopped matching cannot pass vacuously.

### M-2 · `INPUT-105` manual staging → `InputBinding.UIButton`

The on-screen DRIFT and ITEM buttons were staged by hand: a
`GuiButton.InputBegan` listener wrote a pending `true`, a **global**
`UserInputService.InputEnded` identity-matched the release and wrote `false`, and
`RenderStepped` flushed both through the deprecated `InputAction:Fire()`.

All of it is gone, replaced by one `InputBinding` with `UIButton = <the button>`
per action — the seam the camera toggle already used. The engine bug the staging
worked around ("*the `.Released` event will not fire*" when a finger slides off a
`UIButton` before lifting) was **fixed at the engine level 2026-04-07**, staff
confirmation: *"the Released event will now fire."*

Removed with it: the `pending` table, the per-frame flush loop, the `activePress`
identity match, and the only global `UserInputService.InputEnded` subscription in
the consumer's client tree — which is why `src/client/InputBridge.luau`
disappeared from the drift check's hit list entirely (§5).

**No existing test pinned the old staging semantics** — the mechanism was
uncovered. Pins were added rather than updated: `tests/input_authority.spec.luau`
asserts the `UIButton` bindings exist, that `stageButton` / `activePress` /
`pending[action]` / `UserInputService.InputEnded` are all absent, and that the
whole touch surface still hides behind one `ScreenGui.Enabled` flip while an
overlay is up (the buttons are the binding now, so their visibility *is* the
binding's reach).

**The trap this deliberately avoids:** injected input arrives as `Touch`, never
`MouseButton1`. The old code filtered on both; the new code filters on nothing,
because the engine owns the raise and release. There is no filter left to get
wrong.

### M-3 · the flag, in five project files that never had it

`Workspace.PlayerScriptsUseInputActionSystem = "Enabled"` added to:

| file | place(s) |
|---|---|
| `tools/build_places.sh:71` (generated) | the 8 tutorial example places |
| `tools/build_places.sh:143` (generated) | `examples/places/Facet-Showcase.rbxl` |
| `tools/build_reference_places.sh:45` (generated) | the 5 reference-proof places |
| `games/RascalRally/code/default.project.json` | the production place |
| `games/RascalRally/code/places/debug.project.json` | the debug place |

**All 15 Facet places rebuilt** (`tools/build_places.sh`,
`tools/build_reference_places.sh`) so the built `.rbxl` files carry it; both
Rascal Rally projects verified to build.

Before this, the *served* showcase project declared the flag while the *built*
`.rbxl` a device actually opens did not — the two differed in input topology. And
the production place's flag was an **unversioned, hand-ticked Studio property**.

## 3. The arbitration scheme (DF-1..6)

### The root cause

All four of the consumer's `InputContext`s shipped with `Priority` and `Sink` at
their engine defaults. The class reference is explicit: *"Contexts with the same
priority will receive the input."* Four confirmed double-fires fell out of that
one omission (DF-6), and every mitigation in the tree was a **state assumption**
maintained elsewhere, not arbitration.

### The scheme

Declared once in `src/shared/InputActions.luau` (`CONTEXT_BANDS` x `CONTEXTS`)
and read by every construction site, so the numbers on the live instances and the
numbers the tests arbitrate are the same numbers:

| Band | Priority | Sink | Contexts | Enabled |
|---|---:|---|---|---|
| `overlay` | **1400** | **true** | `SponsorInputs`, `ResultsSkipInputs` | derived from surface visibility |
| `hud` | 1200 | false | `ClientInputs` (camera toggle) | on except while sponsoring |
| `gameplay` | 1000 | false | `DriveInputs` (server-created) | always |

`InputActions.contextBand(name)` **errors** on an unknown name rather than
defaulting - a typo'd context silently landing on the gameplay floor is the exact
class of miss the scheme exists to end.

An overlay band without a visibility source is a permanently deaf game, so
`CONTEXTS` records the visibility rule beside the band and the spec asserts every
overlay entry has one.

### THE CEILING IS FACET'S, NOT THE GAME'S (fix round 1)

**The first cut of this table got the frame of reference wrong**, and the review
caught it. These contexts do not live in the game's own arbitration space; they
live in **one** space with Facet's, which publishes its bands at
`src/present/presenter.luau:570-580`:

| Facet band | | |
|---:|---|---|
| **1500** | `BASE_SCREEN_PRIORITY` | every presented Facet screen |
| **2000** | *deliberately vacated* | Facet's own comment keeps it clear for "a game's gameplay sink", so its engaged band cannot tie one |
| **3000** | `ENGAGED_BASE_PRIORITY` | an engaged/exclusive surface; **sinks** |
| **3500+** | modals | +500 per stack depth |

The first cut chose gameplay 1000 / hud 2000 / modal 3000. Two defects:

- `modal = 3000` landed **exactly** on `ENGAGED_BASE_PRIORITY` - an equal-priority
  tie, and the engine reference is explicit that *"contexts with the same priority
  will receive the input."*
- worse, it put a **sinking** context above every Facet base screen at 1500.
  Measured in Facet's own IAS model: a 3000-band game context takes `Cancel` and
  `Activate` away from a Facet-presented screen. Gamepad A stops confirming on a
  Facet surface. **That is DF-1's failure mode rebuilt one layer up, by the fix
  for DF-1.**
- `hud = 2000` additionally squatted the band Facet's comment keeps clear.

**The rule now, and it is a number a test asserts** -
`InputActions.FACET_BASE_SCREEN_PRIORITY = 1500`:

> **No context in this game may sit at or above 1500.** A game verb must never be
> able to sink a UI surface it does not own. If one ever needs to, it is not a
> game verb - it is a UI action, and it belongs in the Facet screen's own action
> contribution.

Every band is now strictly below it, and the driving floor is the same 1000 the
engine's avatar default and Facet's own `SponsorPose` context already use.

### GROUND TRUTH: which sponsor path these contexts belong to

Load-bearing, because it decides what "route through Facet" can even mean here.

`SponsorInputs` and `ResultsSkipInputs` are created by `SponsorGesture` /
`SponsorResults`, which are required by **`SponsorController` alone** - the branch
`init.client.luau` takes **only** when `FacetFlags.sponsorOn()` is false (the
legacy rollback, kept shipped and frozen by the 2026-08-03 cutover ruling). The
two presentations are mutually exclusive; the bootstrap's own comment says so.

**On the production default those contexts do not exist**, and the Facet Sponsor
presenter already routes both verbs through Facet's action system - which is
exactly where a verb acting on a Facet-presented surface belongs:

| verb | production default (Facet Sponsor) |
|---|---|
| sponsor cancel | the presenter's `Cancel` action (`ButtonB`), reaching the surface through `PlayFlow:handleCancel` (`FacetSponsor/init.luau:2015`) |
| results skip | `SkipCelebration` on the sponsor pose context, bound `Space` / `ButtonX` -> `results.skipAll()` (`FacetSponsor/init.luau:875-882`) |

So no key ever reaches both a Facet action and one of these IAS bindings. The
legacy surfaces are hand-built `ScreenGui`s with no Facet screen contract to ride,
which is why they are IAS bindings at all - and deleting them would remove
pad/keyboard cancel and skip from a shipped rollback path with no replacement.
**No new Facet seam was needed: the seam exists and the production path uses it.**

### The guard is deleted (fix round 1)

`sponsorActivateGuard` claimed `ButtonA` inside the sinking overlay to close DF-4.
It is gone. Two reasons, the second load-bearing:

1. A guard is a **claim on a key somebody else may need**. On the production path
   `Activate` on ButtonA is the framework's, decided by the responder chain; a
   game-side guard would be a second authority over a key the UI owns.
2. Under the ceiling it could only ever reach **down**. Every context in this game
   now sits below Facet's base screen, so a claim on A here cannot protect a Facet
   surface - it can only take A away from the game's own driving.

**DF-4 therefore stands on the legacy path exactly as it always did**: one A press
reaches `drift` and the selected row's native `Activated`, mitigated by the kart
being parked while sponsoring. Recorded as a residual on a frozen path, not
papered over. On the Facet path it was never a defect - the responder chain
decides ButtonA and `dispatchActivate` collapses the cross-source echo.

### The four pairs, each proved single-delivery

Proved headless through Facet's engine-free IAS model (`Facet.newActionSystem`,
`src/input/actions.luau`), built from the shipped schema — the real key sets, the
real bands.

| | key | contenders | result under the scheme |
|---|---|---|---|
| **DF-1** | gamepad `B` | `sponsorCancel` (modal) vs `brake` (gameplay) | `sponsorCancel` alone while the overlay is up; `brake` alone while driving |
| **DF-2** | keyboard `Space` | `resultsSkip` (modal) vs `drift` | `resultsSkip` alone while the skip window is open; `drift` alone once it shuts |
| **DF-3** | gamepad `X` | `resultsSkip` vs `item` | same shape |
| **DF-4** | gamepad `A` | `drift` vs the row's **native `Activated`** | **open by decision** - see "the guard is deleted" above |
| **DF-5** | gamepad `Y` | `cameraToggle` (hud) vs `sponsorMapToggle` (modal) | `sponsorMapToggle` alone — **even with the camera context left enabled** |

**DF-4 is the one pair this wave does NOT close**, and that is the fix-round
decision recorded above: the guard that closed it was itself a defect in the
larger frame. Its other consumer is a native `GuiButton.Activated` off
`GuiService.SelectedObject` - not an `InputContext`, so no priority can reach it -
and it exists only on the frozen legacy path.

**DF-5 was already "mitigated"** by disabling the camera context while sponsoring
— a state flag on one of the two contenders, which reopened on any path that left
it enabled. The regression drives exactly that state and still gets single
delivery. The flag stays because a camera toggle during an overlay is meaningless,
not because the arbitration needs it.

### Mutation evidence

The scheme is only worth its spec if the spec **bites**. Six mutations, each on a
private copy, each restored:

| mutation | result |
|---|---|
| control (unmutated) | 32 passed |
| `SponsorInputs` band → `hud` | 5 failed |
| `ResultsSkipInputs` drops its `Sink` write | 1 failed |
| a hardcoded `.Priority = 3000` at a site | 1 failed |
| back to `InputAction:Fire` at one call site | 1 failed |
| `stageButton` reintroduced | 2 failed |
| **`overlay` back to 3000 — the shipped defect** | **6 failed** |
| **`hud` back to 2000 (Facet's reserved slot)** | **5 failed** |
| **`sponsorActivateGuard` re-added** | **3 failed** |
| **`overlay` stops sinking** | **7 failed** |
| restored | 32 passed |

### The cross-system model (fix round 1)

The mutation table above is only worth its name if the model can *see* the whole
client. The original `world()` built the game's four contexts and nothing else,
so the 3000-band collision was invisible to it by construction — it stayed green
through the defect, which is how it shipped.

`tests/input_authority.spec.luau` now also builds a **real** `Facet.newPresenter`
presenting a **real** screen, and the game's contexts, on **one shared action
system**. Facet's priorities are not copied into the test: a thin recorder around
`createContext` reads them back off the contexts the presenter actually made. Six
cases:

| case | asserts |
|---|---|
| the Facet screen outranks every game context | the ceiling, behaviourally, not by hardcoded number |
| `ButtonA` with every game context live | the Facet screen's `Activate` still fires (**the review's blocking measurement**) |
| `ButtonB` with every game context live | the Facet screen's `Cancel` still fires, *and* the overlay still beats the game's own brake |
| `Space` with the results overlay up | `resultsSkip` fires, `drift` does not |
| **MUTATION**: a game context re-banded to 3000 claiming `ButtonA` | the Facet screen is **starved** — the shipped defect, reproduced on demand |
| the same context at the scheme's own 1400 band | it is **not** starved — the control that makes the mutation mean something |

## 4. Kept legacy calls — the allowlist and its impossibility citations

Eight adapter files carry a flagged legacy surface. Every one is named in
`tools/check_input_authority.py`'s `ALLOWLIST` with its inventory class, the
platform text that makes it necessary **now**, and the concrete event that
retires it. Condensed:

| File | Class | Impossibility (cited) | Retired by |
|---|---|---|---|
| `src/client/gamepad_contention.luau` | 4 | The flag is **not scriptable** on any build, so every detector must be behavioural; and CAS priority is not the same arbitration space as `InputContext.Priority` (a CAS Sink at 100 beat an `InputContext` at 10000 with `Sink=true`, measured 2026-08-14), so with the flag off there is no in-framework remedy at all | IAS rollout Phase 3 (mid-2027) removes the property. **Partially retired already** — see DF-9 below |
| `src/client/screen_pointer.luau` | 3 (+1) | §A.4 *"Pointer position/geometry: Not addressed as a general capability… no mention of hit-testing"*; and **no wheel input source is documented anywhere in IAS** — `ViewportPosition` delivers a position, not a delta | IAS documents pointer geometry **and** a wheel source |
| `src/client/screen_target.luau` | 3 + class-1-cannot-migrate | Four gaps: no per-node secondary-pointer source; §A.4 *"Touch gesture recognition (swipe/pinch/etc.): Not mentioned"*; §A.4 *"Text entry: Not mentioned anywhere"*; long-press needs `InputObject` identity IAS never exposes | gestures + text entry + an `InputObject` payload on `Pressed` |
| `examples/gallery/scenarios/runner.luau` | 5 (+4) | IAS exposes no input trace, so the raw `gameProcessed` second opinion has no equivalent; `RbxCameraKeypress` is un-outrankable from IAS, so the keyboard-first arm must unbind it | test-only; the arm is retired or IAS gains a trace |
| RR `src/client/InputIdentity.luau` | 2 | §A.4 *"Device-change observation: Not exposed as its own event"*; even `GetLastInputType()` flaps several times a second on a gamepad+touch handheld | IAS documents a device-change event |
| RR `src/client/SponsorGesture.luau` | 3 | §A.4 pointer-geometry gap — card-drag deltas and press-candidate promotion | IAS documents pointer geometry |
| RR `src/client/SponsorGui.luau` | 3 | same gap, on the legacy Sponsor surface kept as the rollback path | same, or the rollback is retired |
| RR `src/client/SponsorFtue.luau` | 3 | same gap — a per-node press on a specific instance | same |

**The impossibility ledger** (`NO_IAS_SURFACE`) holds the six class-1 verbs with
no IAS surface at all, each with the platform quote and a **witness token** that
must still be present in its owner: mouse-wheel delta (INPUT-32), per-node
secondary-pointer context menu (INPUT-35), the six touch gestures (INPUT-36), text
entry begin/commit/cancel + OSK return (INPUT-37), the disclosure long-press
(INPUT-39), and the consumer's 22 menu/HUD button taps (INPUT-116 — expressible in
principle, knowingly kept: 22 actions and contexts to buy a boolean where the
payload is the point). If a verb genuinely migrates, its witness disappears and
the check says so instead of leaving a stale paragraph behind.

**Two rows are kept for payload, not impossibility** (INPUT-27, INPUT-33 —
`GuiButton.Activated` driving the activate verb). IAS's `Pressed` carries **no
arguments at all**, and `pointerActivateMeta` derives from the `InputObject` the
pointer kind, the window-space tap coordinates and the held modifiers. Losing that
is recorded in this repo as a HIGH defect: a meta-less activate made every finger
landing in a 44px hit-expander overhang read as a *mouse click*. Kept until IAS
delivers an input-object payload on `Pressed`.

### DF-9 — the recheck, answered

`disableLegacyControls()` was built on a `jumpAction` measurement taken
**2026-07-20, before any place declared the flag**. Under the flag the player
scripts are IAS contexts: there is no CAS `jumpAction` and no `PlayerModule`, so
the call spent its full bounded wait and then found nothing. Both example
bootstraps called it while their project files declared the flag, and nothing said
which mechanism was live.

The flag is not script-readable, so the detector is behavioural like every other
probe here. `gamepad_contention.iasPlayerScriptsActive(player?, waitSeconds?)`
reads the **artifact** of the flag: `Player.InputContexts.{Character,Camera,
Vehicle}Context` exist only once the player scripts are on IAS. `disableLegacyControls`
now asks first and returns `(uncontended, status)`:

| status | meaning |
|---|---|
| `"inert: IAS owns PlayerScripts"` | nothing touched, nothing needed touching |
| `"disabled"` | the control module was disabled |
| `"unbound"` | the `jumpAction` fallback ran **and the binding is confirmed gone** |
| `"unavailable"` | neither engine path was reachable |

Where the flag is off — any consumer that has not declared it — the behaviour is
unchanged. The order is pinned too (`tests/platform_adapters_recovery.spec.luau`):
the inert check must run **before** either remedy, or a flag-on place still pays
the bounded wait, which is invisible in a boolean.

**The honest residual:** a false negative. `InputContexts` replicates at
player-add, so a bootstrap asking the instant it runs can miss it. The bounded
1-second retry narrows the window; a miss degrades to the pre-existing legacy
path, which is today's behaviour — slower, not wronger.

### The stale claim, corrected

`src/client/gamepad_contention.luau` stated the flag is *"NOT script- **or
rojo**-reflectable"* and that a human must tick it in Studio. **The rojo half is
false** with the pinned toolchain, and that wrong half is exactly why five shipped
project files went without the declaration for months. Corrected in the module
header, in the `describeContention()` string a doctor check prints, and in
`docs/reference/api.md`; the correction is pinned by the suite so it cannot fall
back out.

Re-proved this session, with a negative control:

```
$ rojo build flagprobe.project.json -o flagprobe.rbxlx     # PlayerScriptsUseInputActionSystem: "Enabled"
Built project to flagprobe.rbxlx
$ grep -o 'PlayerScriptsUseInputActionSystem[^<]*<[^>]*>[^<]*' flagprobe.rbxlx
PlayerScriptsUseInputActionSystem">2</token>

$ rojo build flagprobe_neg.project.json -o flagprobe_neg.rbxlx   # TotallyMadeUpPropertyXyzzy
        Caused by:
            Unknown property Workspace.TotallyMadeUpPropertyXyzzy
```

The negative control is what makes the positive mean anything: rojo **does** fail
on a property it does not know, and it does not fail on this one. All 15 places
then rebuilt clean. The **script-read** half stands unchanged.

## 5. The drift check

`tools/check_input_authority.py` refuses a NEW direct `ContextActionService` use
and a NEW `InputBegan`/`InputEnded`/`InputChanged` subscription outside the
allowlisted adapters, across `src/`, `examples/`, and the consumer's `src/`. It
reads comment-stripped Luau through the real lexer already shipped in
`tools/check_no_screen_key_bindings.py` — string **contents** stay visible on
purpose, because `game:GetService("ContextActionService")` is the bypass being
hunted and it lives inside a string.

It is deliberately not narrowed to a receiver named `UserInputService`: an alias
would walk straight through that, and the per-node `GuiObject.InputBegan` form is
the same class — it is what the consumer's hand-staged touch buttons used.

**Three rules, all of which bite:**

1. a flagged site in a file that is **not** allowlisted → fail (new drift);
2. an allowlisted file with **no** flagged site → fail (**stale exemption**: its
   removal trigger fired, so the entry must go rather than linger as a standing
   permit);
3. a ledger verb whose **witness** has vanished → fail (the impossibility record
   is fiction until someone re-reads it).

Rule 2 is what makes this age well, and it earned its keep immediately:
`InputBridge.luau` carried two flagged sites until this wave, the `UIButton`
migration removed them, and an allowlist that still excused it would have handed
the next author a free pass on a file that no longer needs one.

```
$ python3 tools/check_input_authority.py
input authority: clean. trees src, examples scanned; consumer scanned. 8 allowlisted adapters, 6 ledger verbs, 0 new binders.

$ python3 tools/check_input_authority.py --selftest
selftest: 8 cases green (planted CAS, planted InputBegan, restore, comment, string, non-zero exit, stale entry, real tree)
```

**The selftest plants into a scratch COPY of the real `src/` tree, not the working
tree.** The rule is the identical `scan()` function over the identical allowlist
and the identical file contents, so the proof is the same one — and a concurrent
reader of the working tree never sees a planted file, nor is one left behind by a
crash mid-run. The eight cases: a planted CAS bind reddens; a planted
`UserInputService.InputBegan` bind reddens; removing the plant restores green; a
**block comment** naming the service does **not** redden; a service name inside a
**string** does; `main()` exits **non-zero** over a plant (the half a gate `run`
string actually reads); a stale allowlist entry is reported; and the real trees —
consumer included — are clean in every dimension.

**What it cannot see**, stated so the next agent does not assume otherwise: a
computed service name (`GetService(NAMES[i])`, concatenation, `loadstring`); a
helper outside the scanned trees binding on a module's behalf (the require graph
in `tools/lune/check_boundary.luau` is the instrument for that class); and whether
an allowlisted file's use is still the one the inventory excused — the entry pins
the file and the reason, not the line.

## 6. No old and new path fires together

The row requires it, so here is the accounting rather than an assertion:

- **The five deprecated `Fire` sites** were *replaced*, not duplicated: the
  `:Fire(` scan finds exactly the migrated binding handles plus one named
  `BindableEvent`, and no `InputAction` handle is Fired anywhere.
- **The staging mechanism** was *deleted*, not left beside the `UIButton` binding:
  `stageButton`, `activePress`, `pending[action]` and the global
  `UserInputService.InputEnded` are each asserted absent.
- **DF-1..5** are the "two paths fire together" class itself, and each is proved
  single-delivery in both states (overlay up, overlay down).
- **DF-8** (Facet `Activate` vs a native `Activated`) was already mitigated
  in-framework by `dispatchActivate`'s cross-source echo collapse and is unchanged
  by this wave. Its residual was DF-4 — a *consumer* mirroring `SelectedObject`
  outside a Facet surface — which is what the guard closes.
- **DF-7 is the one pair not closed**, deliberately: §7.

## 7. Explicitly pending — engine measurements this wave cannot make

Everything here is booked in
`artifacts/release-candidate-review/input/studio-checklist.md`, which names what
to drive, what to read, and the value predicted.

| # | Question | Why headless cannot answer it | Row |
|---|---|---|---|
| **DF-7** | Does `PrimaryModifier` narrow what a sinking context **sinks**? | `Sink` is documented **by KeyCode**; `PrimaryModifier` gates whether a *binding triggers*. The two sentences do not compose, and both failure modes are silent. **No binding was changed.** | gate `df7-modifier-sink-measured` (**bare PENDING**), evidence `input/df7-measurement.md` |
| DF-1..3, DF-5 | Does the engine's `Sink` behave as its own reference states? | The model mirrors the measured spike, but arbitration is re-verified with real injected input at engine gates (ADR-0004) | checklist §1, §2, §4 — **legacy rollback build** |
| DF-4 | *(nothing new to confirm — the guard is deleted)* | The pair is unchanged from the pre-wave build, on a frozen path | checklist §3, now a "still looks like before" reading |
| **N2** | Does the engine release a `UIButton`-bound action when the **`ScreenGui` is disabled mid-press**? | The 2026-04-07 staff fix covers the pointer leaving the *bounds*, not a teardown. `setSponsoring` disables the touch GUI while a finger may hold DRIFT; a latched `true` in a server-created action drifts forever | checklist §7c — **new in fix round 1** |
| DF-9 | Is `disableLegacyControls()` inert in a flag-on place, and what does `cameraKeysContended()` answer there? | Requires a live client in each half of the place matrix | checklist §6 |
| M-1 / M-2 relay | Does `InputBinding:Fire` / `InputBinding.UIButton` on a **server-created** action relay to the server under Server Authority? | The docs do not walk through a server-authoritative IAS pattern at all (staff acknowledged the gap, June 2026). `InputAction:Fire` was *proven* on this path; the replacements are documented but unproven **for SA** | checklist §7a, §7b — including the drag-off release the deleted staging existed for |

DF-7's file records the three possible readings and the fallback for two of them
(rebind the menu to a chord sharing no KeyCode with `Activate`; `ButtonX` already
covers the pad, so only the keyboard side moves).

## 8. Not done, and why

- **INPUT-113** — `ItemFx.luau:44`, a dead `UserInputService` import with zero
  uses. Inventory follow-up 7, outside this wave's scope, and harmless: it carries
  no flagged site, so the drift check neither excuses nor reports it.
- **Consolidations** — the duplicated modifier read (INPUT-11 / INPUT-26), the
  duplicated `InputContexts` silencer (INPUT-97 / INPUT-98), the two
  `GetImageForKeyCode` sites. Inventory follow-up 7; each is a reuse finding, not
  an authority one, and belongs to the reuse ledger.
- **INPUT-48** — `Facet.newActionSystem` exported with no guard against a *client*
  wiring it instead of `roblox_input.newSystem` (a UI that binds nothing to
  hardware, failing silently). Inventory follow-up 8. Recorded here because it is
  the one remaining way a consumer can end up with no IAS at all and no
  diagnostic.
- **`src/controls/table.luau`** is 1,236 characters from the Source write cap and
  was off-limits this wave. It carries no flagged site; its `ContextActionService`
  mentions are all inside a block comment recording the 2026-08-14 measurement,
  which the lexer strips.
- **ADR-0014, `docs/lessons/gamepad-contention-truths.md` and the 2026-07-21
  research note** still repeat the "not rojo-reflectable" wording. They are dated
  decision/evidence records rather than live guidance; the module, its printed
  diagnostic, and the API reference — the three a reader acts on — are corrected.
