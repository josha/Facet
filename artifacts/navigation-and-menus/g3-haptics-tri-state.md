# NM-G3 — the sensory-feedback demo can play haptics, and reports a tri-state

**Finding, director's physical pass 2026-08-16:** *"none of the haptics in sensory
feedback work."*

## 1. Why nothing played, and what it was not

It was **not** the engine choice. `src/client/haptics.luau` has used `HapticEffect`
since it shipped, never the superseded `HapticService:SetMotor`, and its header
quotes Roblox's own supersession notice. That file was not changed by this repair.

Two causes, and the second is the one that would have survived an obvious fix:

1. **The fixture never constructed the adapter.** `examples/gallery/scenarios/sensory_feedback.luau`
   subscribed `presenter.onFeedback` for a **log**, and printed `haptics.MAP` beside
   it under the caption *"What an opt-in haptics adapter **would** play"*. Everything on
   that screen was true; nothing on it was installed. A reader can reasonably read a
   published map as a demonstration, and the director did.

2. **`bind(presenter)` alone would still have played nothing here.** The adapter drops
   every event carrying `reason = "activation"` (`haptics.luau:685`), on purpose:
   a control's press belongs to the **engine**, through `GuiButton.PressHapticEffect`,
   and playing it on the bus as well would be two pulses for one press. Every event this
   surface produces is an activation. So "wire the adapter to the bus" — the obvious
   repair — produces a screen that installs an adapter and still feels like nothing.

   The route that makes a press felt is `attachButtons(root)`, and it needs a real
   `Instance`. That is the thing an engine-free fixture had no way to reach, and it is
   why this gap survived a shipped adapter, 43 passing adapter specs and a showcase demo.

## 2. What shipped

`examples/gallery/scenarios/sensory_feedback.luau` only. No `src/` change.

- **The switch.** `Play haptics on this device`, a `UI.Toggle`, **default off**.
  Flipping it constructs `haptics.new({ enabled = true })` and hands it the two seams a
  game hands it: `bind(presenter)` and `attachButtons(PlayerGui)`. Flipping it back
  `dispose()`s — which stops every effect, destroys the Instance, and clears every
  `PressHapticEffect` this adapter assigned.
- **The library's default does not move**, and the panel says so on screen: *"LuauUI stays
  default-OFF, and this switch does not change that: it is the DEMO opting in, which is a
  different decision from the library opting in."*
- **The adapter is found by two routes**, because the two hosts have different instance
  trees: `ReplicatedStorage.LuauUI.client.haptics` in the built place (where `src` and this
  directory are **sibling** mounts, so no relative path between them exists), and the
  relative require under Lune (where there is a filesystem and no `game`). Both
  `pcall`-guarded; a failure keeps the engine's words and is reported as a fact about the
  host, never about the hardware.

## 3. The tri-state, and why it is three

`docs/lessons/capability-probes-must-be-tri-state.md`. This repository has now shipped
**two** instruments that collapsed "no" with "could not tell" — the boolean capability
probe that lesson is about, and a paint probe that printed "13 of 13 painting" over a
broken screen. This is the third instrument in that family and it does not collapse.

| Screen | Condition | Sentence |
|---|---|---|
| **Requested** | `support() == "supported"` **and** at least one button holds a press effect | "the press effects are with the engine, and a connected pad reports vibration support. Whether a motor actually fired is not readable from game code, so a human has to feel it and say." |
| **This platform says no** | `support() == "unsupported"` (a pad IS connected and answers `false`) or `"absent"` (this client cannot construct the class) | "…that is an answer rather than a fault" / "…no route to a motor exists", plus the engine's own error text |
| **Could not determine** | `"unknown"` (touch has no probe at all; an absent gamepad answers the same `false` as a motorless one), `"blocked"`, no root reached, nothing decorated, or the module never loaded | five distinct sentences, each naming which of those it was |

It says **Requested**, never *played*: whether a `HapticEffect` fired is unreadable from
game code. `support()` is printed verbatim beside the headline — all five lattice values —
so the conclusion can be argued with rather than only believed.

**A phone with no controller lands on `Could not determine` and that is correct**, not a
defect. The line still says whether the effects went out; only a hand can say whether they
arrived.

## 4. What is genuinely unknowable from game code

On screen, under `What no game code can read`:

- **Whether the effect fired.** `HapticEffect` has no "did it play" readback. `Ended` does
  not fire when `Looped`, does not fire on `Stop()`, and one community report says it only
  fires with a gamepad connected — so it is not an oracle either.
- **The player's own haptics strength.** `UserGameSettings.HapticStrength` is
  `Hidden, NotReplicated, RobloxScriptSecurity` on read **and** write. Whether
  `HapticEffect` is scaled by it is undocumented.
- **Which input devices trigger `GuiButton.PressHapticEffect`.** The docs never say
  (`docs/research/2026-08-12-haptics-engine-facts.md` §3). If a phone feels nothing, that
  combination is the first suspect, not this adapter.
- And the fact that started the lattice: `HapticService:IsVibrationSupported(Gamepad1)`
  read `false` live in Studio on a machine with **zero** gamepads attached.

## 5. Guard

`tests/control_feedback.spec.luau` §"the sensory-feedback demo installs the real adapter and
reports a TRI-STATE" — 12 cases. A headless target cannot fire a motor and cannot read
whether one fired, so nothing there asserts a sensation: what is asserted is the
**decision** and the **reported state**.

The last case, `with NOTHING injected it still installs, and names what it could not reach`,
runs the **shipped default** seam — the adapter module really resolves under Lune, the UI
root really does not — so the path both hosts take is exercised rather than described.

## 6. Mutation ledger — 10 of 10 bite

Run against `examples/gallery/scenarios/sensory_feedback.luau`, one at a time, restoring
between each. Four of them are the collapse this row exists to prevent.

| # | Mutation | Cases reddened |
|---|---|---|
| M1 | `blocked` collapses into `refused` | 1 — `a refusal for some OTHER reason is \`blocked\`` |
| M2 | `unknown` (no pad / touch) collapses into `refused` | 1 — `NO PAD is NOT a refusal` |
| M3 | a missing root reads as a hardware refusal | 1 — `with NOTHING injected it still installs` |
| M4 | a module that never loaded reads as a platform NO | 1 — `an adapter that could not be LOADED is undetermined` |
| M5 | `unknown` is optimistically reported as REQUESTED | 1 — `NO PAD is NOT a refusal` |
| M6 | **the whole lattice becomes ONE BOOLEAN** (`supported and decorated > 0` ? requested : refused) | **6**, including `the three answers stay THREE` |
| M7 | the demo binds the bus only, never `attachButtons` | 6, including `a supported pad … says REQUESTED` |
| M8 | the switch installs an adapter left DEFAULT-OFF | 7 |
| M9 | `release` drops the reference instead of `dispose()`ing | 2 — both instance-leak cases |
| M10 | the demo installs itself at build (default ON) | 10, including `DEFAULT OFF` |

M6 is the load-bearing one: a boolean satisfies five of the twelve cases on its own, and
only `the three answers stay THREE` — which walks seven fact-sets and asserts three
distinct states with no headline shared across two of them — makes it impossible.

## 7. What this does not claim

That anything was felt. That is review-packet row **P8**, and it is
`PENDING_PHYSICAL` for a reason no instrument in this repository can remove: this
machine is darwin, and Roblox documents "all game controllers connected to MacOS 15+"
as unsupported, so a silent run here is not evidence either way.
