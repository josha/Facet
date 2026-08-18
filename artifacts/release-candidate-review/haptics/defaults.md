# Facet sensory haptics — the shipped defaults and what proves them

Wave R4, task 11. Framework base `3859fba`; suite at close **6338 passed** (from
6270 at base). Everything below is measured by
`tests/sensory_profile.spec.luau`, `tests/haptics.spec.luau`,
`tests/control_feedback.spec.luau` and `tests/perf_lab.spec.luau` under Lune
against a scripted engine — **nothing here was felt**, and the row that says so
is the last one.

## 1. The profile — `src/client/sensory_profile.luau`

Three phases, three original Facet waveforms. `WaveKey` is plain data
(`{ timeMs, intensity, mode }`); the `FloatCurveKey.new(ms, 0..1,
Enum.KeyInterpolationMode)` construction happens only in the adapter, which is
why these values are pinnable byte-exactly on a host with no engine.

| phase | name | character | keys (`timeMs`, `intensity`, `mode`) |
|---|---|---|---|
| `press` | **contact** | one short, crisp tap when the action goes down | `{0, 0, Linear}` · `{6, 0.9, Cubic}` · `{30, 0, Linear}` |
| `release` | **settle** | a lighter, rounder answer when the action completes | `{0, 0, Linear}` · `{10, 0.5, Cubic}` · `{34, 0, Linear}` |
| `select` | **tick** | the smallest audible-to-the-hand step for a changed choice | `{0, 0, Linear}` · `{4, 0.35, Linear}` · `{16, 0, Linear}` |

Constraints, each a test rather than a comment
(`docs/research/2026-08-12-haptics-engine-facts.md` §7):

* **peaks ≥ 0.3** — the full-release announcement records that "haptic intensity
  below 0.1 may not trigger any haptic effects" on some clients, so an authored
  subtlety under that floor is a silence that reports success. Measured peaks:
  0.9 / 0.5 / 0.35.
* **total duration ≤ 34 ms** — rapid interaction must not overlap two pulses
  perceptibly. Measured: 30 / 34 / 16 ms.
* every key list starts at 0 ms and strictly rises; every `mode` is one of
  `Enum.KeyInterpolationMode`'s three members; every intensity is inside [0, 1].
* the tables are frozen **all the way down**, so a consumer cannot edit the
  product in place.

**Originality.** These are Facet designs, tuned for the semantic role of each
phase. No other UI framework publishes waveform data for its semantic feedback —
Apple's `SensoryFeedback` exposes named kinds and a single `intensity` scalar and
nothing else (verified 2026-08-17) — so there is nothing to copy even in
principle. Whether they *feel* like anything a player has met elsewhere is a
device judgement: see §8.

## 2. Phase-timing ownership — who decides the moment

| phase | the moment | who owns it | how it reaches the phase |
|---|---|---|---|
| `press` | the DOWN edge | **the engine** | `GuiButton.PressHapticEffect` — Facet hands over a reference and never calls `Play()` on it. Reachable only from `decorate`, never from the bus. |
| `release` | the COMPLETED edge | **the bus** | the presenter stamps `reason = "activation"` on the event a control's own activation raises, and that event exists only when the activation completed. Checked **first**. |
| `select` | a VALUE CHANGED | **the bus** | the `select` / `adjust` verbs on an event that is **not** an activation. |

**THE CAUSE OUTRANKS THE VERB** (fix round 1, review F2). A verb says *what*
happened; `reason = "activation"` says *a control was pressed*, and a press
completing is not a choice moving. So a control declaring `activation = "select"`
feels `settle` when pressed and `tick` when its value changes, and
`pressSpecFor` answers `nil` for both of the select phase's verbs — they have no
down edge, because a choice has not moved yet when the finger lands. Before the
fix the property route ignored this entirely and such a control clicked going
down and ticked coming up: two sensations for one choice, and the opposite of
what the module and both reference docs said.

`activationIsFelt(verb)` is the *other* question — is this control felt at all —
and it is a separate function for exactly that reason: the release edge used to
be gated on `pressSpecFor`, so silencing the select verbs' down edge would have
silently cost them their completion too.

The four input classes (pointer, touch, keyboard, gamepad) each resolve their
activation **once**, in the presenter/responder path — including the
`ACTIVATE_ECHO_WINDOW` collapse that makes a keyboard/gamepad Activate and its
engine `Activated` echo one dispatch. This task added **no** input listener:
`ContextActionService` never appears in the adapter, and `UserInputService`
appears exactly twice, both times as `service(options.inputService,
"UserInputService")` for the device probe (a capability question, not an input
one). The only `uis:` method call in the file is `GetConnectedGamepads`, and the
only signals it connects are `GamepadConnected` / `GamepadDisconnected` /
`LastInputTypeChanged`. Pinned by *"no raw-input API is reached for a press, a
release or a select"*.

## 3. The double-pulse guard — narrower than it was

Before this task the adapter **dropped every** `reason = "activation"` event,
because the only alternative was replaying the down edge the engine had already
played. Now the two edges are separate sensations with separate owners, so the
rule is simply that the bus never plays the PRESS phase — and that is
*structural*, not a rule somebody has to keep remembering: `phaseEffect("press")`
is reachable only from `decorate`.

Measured: six completed activations across six different verbs leave the button's
own `PressHapticEffect` instance at `played = 0` while `phases.release.plays`
reads 6 (*"the bus NEVER replays the down edge"*). Mutating `phaseEffect("release")`
to `phaseEffect("press")` reddens 10 cases.

### 3a. The same-instant collapse (fix round 1, from review F4)

A **pointer** press has two moments a hand can tell apart. A **keyboard or
gamepad** press does not: the IAS `Activate` action resolves on the key going
down, so the completion event is raised in the same instant the engine would play
the button's own press effect. Two sensations at one instant are one blurred
pulse.

So for an activation the presenter marks non-pointer (`context.source ==
"action"`), the bus contributes exactly **one** sensation — `settle` — and drops
anything else it would have played for that path inside
`SAME_INSTANT_SECONDS = 1/60`. Dropped, never deferred. `diagnostics().collapsed`
counts it, separately from `coalesced`.

Measured: a non-pointer activation followed by a same-instant value change for
the same path → **1 play, 1 collapsed**; the same pair one frame apart → **2
plays, 0 collapsed**; two *different* paths in one frame → **2 plays**; four
echoed activations in one instant → **1 play, 3 collapsed**; and the negative
control, a **pointer** activation followed by a value change → **2 plays, 0
collapsed**, because a pointer gesture's two moments are genuinely apart and
collapsing them would swallow the value change a tap on a picker row causes.

**What this cannot do**, stated rather than implied: the engine's own `contact`
in that instant is the engine's, and whether it fires at all for a non-pointer
press is undocumented. Rows D8/D9 of the device packet are how that gets
answered.

## 4. Cancellation — silent structurally, never special-cased

`GuiButton.Activated` does not fire for a press that was dragged away from, so
the presenter emits no completion and the adapter is never asked. There is **no
cancellation branch in the module**, and the test asserts the absence: a
decorated button, a down edge that the engine owns, `plays = 0`,
`phases.release.plays = 0`, and no new construction. A mutation that
special-cased a cancel would have to invent an event first.

A control whose declared verb the MAP silences (`cancel`, `arrive`, `dismiss`,
`supersede`) or that declared `none` is unfelt on **both** edges —
`activationIsFelt` answers `false` for all five, so neither the press property nor
the completed edge reaches a sensation.

**And that includes the invisible tap band.** A control solved smaller than the
touch floor gets a second `GuiButton` — `FacetHitExpander`, a sibling at
`hostZ - 1` — which a haptics consumer sweeps like any other button. The Roblox
adapter now mirrors the host's declared verb and its `Active` / `Interactable`
onto it at all three seams that can change either (birth, `setActivationFeedback`,
the `enabled` branch). Before the fix the band read as *undeclared and enabled*:
a control declared `none` was silent on its face and buzzed two millimetres
outside it, and a disabled control's band was still felt — on exactly the small
controls where a thumb lands in the band rather than on the face.

## 5. Coalescing — leading edge, and it DROPS

`select` and `adjust` share **one** limiter (default `DEFAULT_SELECT_INTERVAL =
0.06 s`, past the ≥ 50 ms the design asks for and past the 16 ms `tick` waveform,
so two select pulses can never overlap). Two limiters would let a control
alternating the two verbs — which a scrubbed picker does — pass both and fire at
full rate; measured, one limiter turns 20 alternating pairs inside 20 ms into
**1 play, 19 coalesced**.

A suppressed pulse is **dropped**, never deferred: advancing the fake clock by 10
seconds after two suppressed pulses still reads `plays = 1`. A hold-to-repeat
stepper at 20 Hz for a second fires 20 select-phase pulses, **0** press and **0**
release, from **1** constructed Instance. Mutating the limiter to fall through
instead of returning reddens 5 cases.

## 6. Pooling and teardown — Instances are the evidence

One Instance per **distinct resolved PhaseSpec** (keyed by
`sensory_profile.key`), plus one per mapped verb the phases do not claim. Custom
effects get `SetWaveformKeys` **exactly once, at build**, and the waveform keys
are built *before* the Instance — so a client that cannot make a `FloatCurveKey`
never ends up holding a keyless `Custom`, which would be a guaranteed silence
that reports success.

| measurement | number |
|---|---|
| distinct phase specs (Facet defaults) | 3 — `custom:contact`, `custom:settle`, `custom:tick` |
| verb effects the phases do not claim | 5 — `pickup`, `commit`, `reject`, `land`, `celebrate` |
| live Instances after 40 rounds × 12 verbs × 2 causes + 3 decorated buttons | **8** (`= 3 + 5`), and `diagnostics().pooled` agrees with the instance count |
| platform budget | "fewer than 100 simultaneous haptic effects" — asserted `< 100` |
| 50 completed activations | `constructions = 1`, `plays = 50`, `keyedTimes = 1` — construction is flat across N pulses |
| dispose after press + release + select + one verb | live `4 → 0`, `destroys == constructions`, every effect `Stop()`ped before `Destroy()` |
| 5 enable/disable cycles across all three phases | live `0`, `destroys == constructions`, `pooled = 0` |

The counts are read off the fake engine's own objects, never off
`diagnostics()` — the rule this repository earned when a `pooled` counter
reported 0 while fifteen `HapticEffect`s sat parented in Workspace.

## 7. Fallback — and the limitation it carries

If the `Custom` route will not build on a client, the phase falls back to a real
preset, never to a bare `Custom`:

```
FALLBACK = { press = "UIClick", release = "UIHover", select = "UIHover" }
```

The platform ships exactly **three** UI presets. `UINotification` is documented
as drawing the player's attention *away* from gameplay, which is neither what a
released button nor a changed choice means — so **release and select share
`UIHover` and are distinct only by cause** under fallback, and press keeps
`UIClick`'s crisp character. Measured on a client with no
`Enum.KeyInterpolationMode`: three phases, **two** Instances.

`diagnostics().phases[phase].fallbackActive` is set only once the preset has
actually been built and handed back — a phase whose custom route failed *and*
whose preset route failed is not "on fallback", it is silent, and `support()` /
`lastError` are where that is explained. It is not reset by `setEnabled(false)`:
whether this client can make a `FloatCurveKey` is a fact about the client, not
about the switch. Mutating the flag away reddens 2 cases.

`constructionVerdict == "absent"` now short-circuits **before** the waveform work
as well as inside `construct`, so a client without the class neither re-resolves
the interpolation enum per button per sweep nor overwrites the engine's own words
about why the class could not be made.

## 8. What is NOT proved here

**PENDING_DEVICE — perceived similarity, and perception at all.** Studio cannot
feel. Roblox documents "all game controllers connected to MacOS 15+" as
unsupported and this repository's dev machine is macOS, so a silent run here is
expected and must never be recorded as "haptics do not work". Three rows only a
hand closes:

1. that `contact`, `settle` and `tick` are *distinguishable* from one another on
   a phone and on a gamepad;
2. that they are *appropriate* — that the release is felt as an answer rather
   than as a second tap, and that the select tick is felt at all at 0.35;
3. that they are perceptibly **original** rather than a near-copy of any other
   platform's stock feedback — the comparison is a paired judgement, on one
   device, and it is a judgement, not a measurement.

Also unreadable from game code, in either direction: whether a `HapticEffect`
actually fired, and the player's own haptics strength
(`UserGameSettings.HapticStrength` is `RobloxScriptSecurity` on read).

The procedure for closing all three is
[`device-review-packet.md`](device-review-packet.md).

## 9. Where to press it

`examples/gallery/scenarios/sensory_feedback` grew a **calibration panel**: one
row per phase, a profile selector (Facet defaults | preset fallback | silent) and
a live pulse counter.

* **Press** — an ordinary undeclared button. The engine plays `contact` on the
  way down; the same press answers with `settle` on the way up. Hold it, drag off
  the button and let go to feel the down edge alone — which is also the
  cancellation proof.
* **Release** and **Select** — controls that declare `activation = "none"`, so
  each puts exactly one cause on the bus and nothing else. Judged alone.
* The pulse line prints what the adapter played per phase and says, in words,
  that the press count is the engine's and unreadable — rather than printing a
  `0` that would read as "it never fired".

The performance lab takes `select:haptics=on` and adds a counter line
(`haptics=on built=… pooled=… plays=… coalesced=…`). A whole 30-step dense
scroll with the adapter bound moves **no** haptic counter: it is event-driven,
and a scroll produces no feedback verbs.
