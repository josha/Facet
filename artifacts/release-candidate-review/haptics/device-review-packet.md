# Haptics device-review packet — PENDING_DEVICE

Wave R4, task 11. Companion to [`defaults.md`](defaults.md), which records
everything a headless host *can* prove. This file is the procedure for the three
things it cannot: that the three Facet waveforms are **distinguishable**,
**appropriate**, and **perceptibly original**.

Nothing in this packet may be filled in from Studio. Studio runs the effects
locally and never fires a motor you can feel, and the full-release announcement
lists "all game controllers connected to MacOS 15+" as unsupported — this
repository's dev machine is macOS, so a silent run there is **expected** and must
never be recorded as "haptics do not work".

---

## A. What the reviewer is judging

| row | question | verdict vocabulary |
|---|---|---|
| **D1 distinguishable** | with eyes closed, can the three be told apart? | `distinct` / `two-of-three` / `indistinguishable` |
| **D2 appropriate** | does `contact` read as a tap going down, `settle` as an *answer* rather than a second tap, `tick` as the smallest step that registers at all? | per phase: `right` / `too strong` / `too weak` / `wrong character` |
| **D3 original** | held next to the platform reference below, do Facet's three read as their own thing rather than a near-copy? | `own character` / `similar` / `indistinguishable from the reference` |
| **D4 cancel** | a press dragged away from: is anything felt on the way up? | `silent` (expected) / `something fired` |
| **D5 rapid select** | scrubbing fast: does it buzz, or does it tick and stop? | `discrete` / `buzzsaw` / `nothing` |

D3 is a **judgement**, never a measurement, and the packet says so in the result
file too. Apple publishes no waveform data for `SensoryFeedback` — only named
kinds and a single `intensity` scalar — so there is nothing to diff numerically;
the only honest comparison is a paired one, by hand, on one device.

---

## B. The paired iPhone procedure (D1–D3, D4, D5)

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
4. **Reference side**: any first-party iOS app whose feedback is the system's own
   — e.g. a native picker wheel (selection), a native switch (impact), a Face
   ID / password failure (notification). Do **not** use a third-party app; the
   point of the reference is that it is the platform's stock feedback.
5. **Run the five rows, alternating** Facet → reference → Facet for each, so the
   hand is comparing rather than remembering:

   | # | on the Facet panel | on the reference |
   |---|---|---|
   | D1 | press **Press**, then **Release**, then **Select**, three times each | — |
   | D2 | same three, one at a time, eyes closed | — |
   | D3 | **Press** vs a native button press · **Release** vs a native confirmation · **Select** vs a native picker wheel step | the paired native gesture |
   | D4 | press **Press**, hold, drag the finger off the button, release | — |
   | D5 | tap **Select** as fast as possible for ~3 s | a native picker wheel spun fast |

6. **Then flip the profile selector** to **Preset fallback** and repeat D1 only.
   Expected: press still crisp, release and select now the *same* sensation
   (both `UIHover`) — this is the documented limitation, and the reviewer is
   confirming it is what a fallback client actually feels, not a defect.
7. **Then flip it to Silent** and press all three rows. Expected: nothing at all,
   and the pulse counter stays where it was.

---

## C. Android + gamepad sampling rows

Smaller samples, because the questions are narrower.

| device class | minimum | what is recorded |
|---|---|---|
| **Android phone** (Pixel or Galaxy, Android 12+; the beta announcement lists Android ≤ 11 as unsupported) | 1 device | D1, D2, D4 — plus whether anything is felt *at all*, which is a platform row rather than a design one |
| **Gamepad** (PlayStation or Xbox pad, on a supported host — **not** a controller attached to a phone, and **not** any controller on macOS 15+, both documented unsupported) | 1 pad | D1, D2, D5, plus the `support()` line the panel prints: a connected pad is the ONE case where the platform's boolean probe means what it says |
| **Quest Touch** | optional | D1 only; record the headset build |

For every row also record the panel's verbatim `support()` value and the
`N buttons holding a press effect` count. A `requested` with a 0 decorated count
is a wiring fault, not a hardware answer.

---

## D. What the reviewer writes down

One entry per device, into
`artifacts/release-candidate-review/haptics/device-results.md` (create it on the
first pass; it is deliberately not created empty here, because an empty results
file reads as a completed pass with nothing in it).

```
## <device> — <OS build> — <Roblox client version> — <date>
panel line (verbatim): ...
support(): ...            decorated: ...
profile: Facet defaults

D1 distinguishable: distinct | two-of-three | indistinguishable
    notes:
D2 appropriate:  contact=...  settle=...  tick=...
    notes:
D3 original (vs <named reference gesture>): own character | similar | indistinguishable
    notes:  (a JUDGEMENT, not a measurement — Apple publishes no waveform data)
D4 cancel (drag off, release): silent | something fired
D5 rapid select: discrete | buzzsaw | nothing

profile: Preset fallback
D1 (release vs select expected IDENTICAL): as documented | differed
profile: Silent
all three rows: nothing felt | something fired
```

A row the reviewer could not run is written as `NOT RUN` with the reason. It is
never left blank and never inferred from another device.

## E. What closes the task

`defaults.md` §8's three rows move from PENDING_DEVICE to a recorded verdict once
**at least** the iPhone pass (§B) and one gamepad row (§C) exist in
`device-results.md`. A `too strong` / `too weak` on D2 is a tuning change to
`src/client/sensory_profile.luau` and a re-pin of
`tests/sensory_profile.spec.luau` — the waveforms are the product, so moving one
is a deliberate edit with a test, never a quiet adjustment.
