# Haptics device-review packet — PENDING_DEVICE

Wave R4, task 11, **rebuilt at fix round 1** (review finding F4). Companion to
[`defaults.md`](defaults.md), which records everything a headless host *can*
prove. This file is the procedure for the three things it cannot: that the three
Facet waveforms are **distinguishable**, **appropriate**, and **perceptibly
original**.

Nothing in this packet may be filled in from Studio. Studio runs the effects
locally and never fires a motor you can feel, and the full-release announcement
lists "all game controllers connected to MacOS 15+" as unsupported — this
repository's dev machine is macOS, so a silent run there is **expected** and must
never be recorded as "haptics do not work".

---

## A. Read this before pressing anything: which gesture isolates which waveform

**The first version of this packet was confounded and would have burned the
pass.** It asked the reviewer to "press Press, then Release, then Select" and
judge each waveform. But a *completed* press on the Press control fires **two**
sensations — `contact` on the way down (the engine) and `settle` at the
completion (the bus) — so every judgement about `contact` was actually a
judgement about `contact + settle`.

Each phase has exactly one gesture that isolates it. Use the right one:

| waveform | ISOLATING gesture | why it isolates |
|---|---|---|
| **`contact`** (press) | on the **Press** row: press, **hold**, **drag your finger off the button**, then release | dragging away means the activation never completes, so no `settle` is raised. The down edge is the only thing that fired. |
| **`settle`** (release) | tap the **Release** row | that control reports nothing of its own, and puts one completed activation on the bus. Nothing else fires. |
| **`tick`** (select) | tap the **Select** row | same: one value-change cause on the bus, alone. |

And one gesture deliberately fires **both**, in a fixed order:

| gesture | expected | order |
|---|---|---|
| an ordinary completed tap on the **Press** row (press and release **on** the button) | **two** sensations | `contact` first (the moment the finger lands), then `settle` when it lifts |

That two-pulse pair is the round's central design claim — *two moments, two
sensations, two owners* — so it gets its own row (D6) rather than being an
accident inside D1.

**The Release and Select rows put their cause on the bus directly.** That is what
buys the isolation, and it means those two rows say nothing about whether a real
press reaches the release phase. The **Press** row is an ordinary control taking
the real path end to end, and the panel now prints *"Completed presses heard on
the bus: N"* beside the pulse counts — read off the bus, not off the button's
handler. Row D7 uses it.

---

## B. What the reviewer is judging

| row | question | verdict vocabulary |
|---|---|---|
| **D1 distinguishable** | with eyes closed, using each waveform's **isolating** gesture, can the three be told apart? | `distinct` / `two-of-three` / `indistinguishable` |
| **D2 appropriate** | isolated, does `contact` read as a tap going down, `settle` as an *answer* rather than a second tap, `tick` as the smallest step that registers at all? | per phase: `right` / `too strong` / `too weak` / `wrong character` |
| **D3 original** | held next to the platform reference, do Facet's three read as their own thing rather than a near-copy? | `own character` / `similar` / `indistinguishable from the reference` |
| **D4 cancel** | press, hold, drag off, release: is anything felt on the way **up**? | `silent` (expected) / `something fired` |
| **D5 rapid select** | scrubbing fast: does it buzz, or does it tick and stop? | `discrete` / `buzzsaw` / `nothing` |
| **D6 completed press** | an ordinary tap on the Press row: how many pulses, in what order? | `two — contact then settle` (expected) / `one` / `two but wrong order` / `mush` |
| **D7 wiring** | does the on-screen *"Completed presses heard on the bus"* count rise by exactly 1 per tap on the Press row? | `1 per tap` (expected) / other |
| **D8 keyboard** | see §D | see §D |
| **D9 gamepad** | see §D | see §D |

D3 is a **judgement**, never a measurement, and the packet says so in the result
file too. Apple publishes no waveform data for `SensoryFeedback` — only named
kinds and a single `intensity` scalar — so there is nothing to diff numerically;
the only honest comparison is a paired one, by hand, on one device.

---

## C. The paired iPhone procedure (D1–D7)

**One device, both apps, one sitting.** A judgement taken an hour apart on two
devices is a judgement about two devices.

1. **Device**: an iPhone with haptics (the docs say "most iPhone, Pixel and
   Samsung Galaxy devices"). Silent switch OFF; the phone in the hand, not on a
   table — a desk couples the vibration and flattens the difference.
2. **Settings**: iOS *Sounds & Haptics → System Haptics* ON. Roblox's own haptics
   preference is not readable from game code
   (`UserGameSettings.HapticStrength` is `RobloxScriptSecurity`), so record
   whatever the Roblox client's setting is set to, verbatim, in the result file.
3. **Facet side**: open the showcase, `sensory_feedback` demo, scroll to
   **Calibrate the three phases**. Turn *Play haptics on this device* ON. The
   line under the switch should read **Requested** or **Could not determine** —
   a phone has no capability probe on the platform at all, and *Could not
   determine* is a correct answer, not a failure. Record it verbatim either way.
4. **FIRE EACH PHASE ONCE BEFORE READING THE REPORT.** The adapter builds nothing
   until a phase is first needed, so a freshly enabled adapter reports
   `contact/settle/tick` and `fallbackActive = false` regardless of what this
   client can actually do. Tap Press, Release and Select once each, *then* read
   the panel: if any phase now names a preset (`UIClick` / `UIHover`) instead of
   a waveform name, this client fell back and every judgement below is a
   judgement of the **presets**, not of Facet's waveforms. Record which.
5. **Reference side**: any first-party iOS app whose feedback is the system's own
   — e.g. a native picker wheel (selection), a native switch (impact), a Face
   ID / password failure (notification). Do **not** use a third-party app; the
   point of the reference is that it is the platform's stock feedback.
6. **Run the rows, alternating** Facet → reference → Facet for D3, so the hand is
   comparing rather than remembering:

   | # | on the Facet panel | on the reference |
   |---|---|---|
   | D1 | each waveform's **isolating** gesture from §A, three times each | — |
   | D2 | the same three **isolating** gestures, one at a time, eyes closed | — |
   | D3 | `contact` (drag-off gesture) vs a native button press · `settle` (Release row) vs a native confirmation · `tick` (Select row) vs a native picker wheel step | the paired native gesture |
   | D4 | Press row: press, hold, drag off, release | — |
   | D5 | tap **Select** as fast as possible for ~3 s | a native picker wheel spun fast |
   | D6 | Press row: an ordinary tap, ten times | — |
   | D7 | Press row: five taps, watching the on-screen count | — |

7. **Then flip the profile selector** to **Preset fallback** and repeat D1 only.
   Expected: press still crisp, release and select now the *same* sensation
   (both `UIHover`) — this is the documented limitation, and the reviewer is
   confirming it is what a fallback client actually feels, not a defect.
8. **Then flip it to Silent** and press all three rows. Expected: nothing at all,
   and the pulse counter stays where it was.

---

## D. Keyboard and gamepad — the same-instant collapse (D8, D9)

**This is the row the first packet was missing, and it tests the round's central
claim on the input classes where that claim is hardest.**

On keyboard and gamepad the IAS `Activate` action resolves on the key or button
going **down**. There is no separate "lift" moment, so the framework's two edges
land in one instant. The adapter therefore **collapses**: for a non-pointer
activation the bus contributes exactly **one** sensation, `settle`, and drops
anything else it would have played for that control in that instant.

What the framework **cannot** do is silence the engine's own press effect in that
instant. Whether `GuiButton.PressHapticEffect` fires at all for a keyboard or
gamepad activation is **undocumented** — it is an open platform question, and
these two rows are how it gets answered.

| row | device | gesture | what to record |
|---|---|---|---|
| **D8 keyboard** | a desktop client with a physical keyboard | focus the **Press** row (Tab), then Space or Enter, ten times | how many distinct pulses per press |
| **D9 gamepad** | a PlayStation or Xbox pad on a supported host — **not** a controller attached to a phone, and **not** any controller on macOS 15+, both documented unsupported | select the **Press** row, then ButtonA, ten times | how many distinct pulses per press |

**Verdict vocabulary for both**, and every one of the three is a real, useful
answer:

* `one pulse` — the expected outcome of the collapse: the bus played `settle` and
  the engine did not add its own press effect for this input class. The framework
  is doing exactly what it says.
* `two distinct pulses` — the engine **is** firing `PressHapticEffect` for a
  non-pointer press. That is a platform fact this repository does not have and
  cannot get any other way; record it, because it turns an undocumented question
  into a documented one and it is the input to whether the collapse should grow
  to cover it.
* `one blurred/mushy pulse` — both fired and they overlapped. Same platform
  finding as above, and it is also the failure the collapse exists to prevent, so
  it is the row that would send the design back.

Also record, for both rows: whether the sensation felt **appropriate** for a
button press (the same D2 vocabulary), because `settle` is deliberately the
lighter of the two waveforms and on these input classes it may be carrying the
whole press on its own.

---

## E. Android + Quest sampling rows

Smaller samples, because the questions are narrower.

| device class | minimum | what is recorded |
|---|---|---|
| **Android phone** (Pixel or Galaxy, Android 12+; the beta announcement lists Android ≤ 11 as unsupported) | 1 device | D1, D2, D4, D6 — plus whether anything is felt *at all*, which is a platform row rather than a design one |
| **Quest Touch** | optional | D1 and D9 only; record the headset build |

For every row also record the panel's verbatim `support()` value and the
`N buttons holding a press effect` count. A `requested` with a 0 decorated count
is a wiring fault, not a hardware answer.

---

## F. What the reviewer writes down

One entry per device, into
`artifacts/release-candidate-review/haptics/device-results.md` (create it on the
first pass; it is deliberately not created empty here, because an empty results
file reads as a completed pass with nothing in it).

```
## <device> — <OS build> — <Roblox client version> — <date>
panel line (verbatim): ...
support(): ...            decorated: ...
AFTER firing each phase once — press: ...  release: ...  select: ...
    (waveform names = Facet's own; preset names = this client fell back)
profile: Facet defaults

D1 distinguishable (ISOLATING gestures): distinct | two-of-three | indistinguishable
    notes:
D2 appropriate (ISOLATING gestures):  contact=...  settle=...  tick=...
    notes:
D3 original (vs <named reference gesture>): own character | similar | indistinguishable
    notes:  (a JUDGEMENT, not a measurement — Apple publishes no waveform data)
D4 cancel (press, hold, drag off, release): silent | something fired
D5 rapid select: discrete | buzzsaw | nothing
D6 completed press (ordinary tap): two — contact then settle | one | two but wrong order | mush
D7 wiring (bus count per tap): 1 per tap | ...
D8 keyboard (Space/Enter on the Press row): one pulse | two distinct pulses | one blurred pulse
    appropriateness: right | too strong | too weak | wrong character
D9 gamepad (ButtonA on the Press row): one pulse | two distinct pulses | one blurred pulse
    appropriateness: right | too strong | too weak | wrong character

profile: Preset fallback
D1 (release vs select expected IDENTICAL): as documented | differed
profile: Silent
all three rows: nothing felt | something fired
```

A row the reviewer could not run is written as `NOT RUN` with the reason. It is
never left blank and never inferred from another device.

## G. What closes the task

`defaults.md` §8's three rows move from PENDING_DEVICE to a recorded verdict once
**at least** the iPhone pass (§C) and one gamepad row (§D) exist in
`device-results.md`. A `too strong` / `too weak` on D2 is a tuning change to
`src/client/sensory_profile.luau` and a re-pin of
`tests/sensory_profile.spec.luau` — the waveforms are the product, so moving one
is a deliberate edit with a test, never a quiet adjustment. A `two distinct
pulses` or `one blurred pulse` on D8/D9 is a **platform finding** that belongs in
`docs/research/2026-08-12-haptics-engine-facts.md` first, and only then in a
design decision about widening the collapse.
