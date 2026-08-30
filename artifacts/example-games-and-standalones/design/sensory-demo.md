# The sensory-feedback demo — design

Reworks `examples/gallery/scenarios/sensory_feedback.luau`. Binding scope:
`docs/plans/example-games-and-standalones.md`, "Sensory-feedback demo".

---

## 1. What is wrong with it today

The demo is 1,087 lines and eight sections deep, and its own source comment explains
the order as a story: five verbs, then a cascade, then a map of what an adapter would
play, and *only then* the switch that decides whether any of it reaches this device.

It is a good story and a bad demo. The switch is seventh of eight sections, so a player
opening the page scrolls past four panels of explanation before reaching the one
control that makes the feature do anything. And the switch starts **off**
(`playHaptics` initialises to `false`), so the honest experience of opening the demo is:
read four panels, find a switch, turn it on, scroll back up, and only then feel
something.

## 2. What it becomes

**The panel that decides everything goes first**, directly after the title and one
short paragraph, and it starts **on**.

```
  Sensory feedback
  Facet reports what an interaction MEANT. A game decides what that feels like.

  ┌─ Haptics ────────────────────────────────────────────────┐
  │  [●———]  On          Adapter installed · profile: default │
  │  This demo turns haptics on for you so the controls below  │
  │  do something immediately. Facet itself ships them off     │
  │  until a game asks.                                        │
  └────────────────────────────────────────────────────────────┘

  Press · Release · Selection · Custom     ← the four comparisons
  What was requested                       ← the bounded event history
```

Everything above the four comparisons has to fit in the first viewport on compact
portrait, short landscape, desktop, and ten-foot — **including at Largest text** — and
that is proved from rendered order and geometry, not from the order of the source
file.

### On by default is a demo choice, and the copy says so

Facet's contract is unchanged: the library enables no haptics until a game opts in, and
the tests that prove it are untouched. The *example* is a game, and it opts in — it
explicitly requests and installs the adapter so that pressing a sample control
demonstrates the feature immediately.

The status line reports what actually happened, in three honest states:

| State | What it says |
|---|---|
| Installed | "Adapter installed · profile: default" |
| Host refused | "This host declined haptics. The controls below still report what they meant." |
| Undetermined | "Roblox cannot tell us whether this device has a motor. The request is on." |

If the host refuses or support cannot be determined, **the requested toggle stays on**
and the result is reported accurately. What is never said, anywhere, in any state: that
the player felt anything. Roblox exposes no motor confirmation, so a claim of sensation
would be a claim nothing can support.

## 3. The four comparisons

Each is one labelled row with a live control, a state readout, and a note saying
whether it uses a built-in default or the example's own override.

### Press — the built-in contact waveform

An ordinary control with no local override. When the primary action goes **down**, the
built-in press waveform is requested. The row shows `pressed` while the pointer, key,
or button is held.

The point of the row is that nothing in the example asked for this. It is what the
library does.

### Release — the distinct release phase, and the cancel that is silent

The same interaction, watched at the other end. When a valid press **ends**, the
built-in release phase is requested, and it is a different waveform from the press.

The row also carries a **cancelled press**: press, move off the control, release. The
readout shows the documented cancel outcome rather than pretending activation
succeeded, because a demo that fires a release on a cancelled press teaches the
opposite of what the framework does.

### Selection — only on a change

A real discrete choice: a small picker. When its selected value changes, the built-in
selection tick is requested. When the player hovers it, nothing fires. When the player
re-picks the value that is already selected, nothing fires.

Both no-ops are visible in the history as "no request", so the absence is evidence
rather than an unexplained silence.

### Custom — one obviously distinct waveform, through the public seam

One control whose feel is supplied by the example through the documented public
override: a partial profile handed to the adapter, resolved against the shipped
defaults. It is deliberately unmistakable next to the built-ins — longer, and with a
different shape — so a player on a real device can tell it apart without instruments.

The example constructs no `HapticEffect` and reaches into no adapter internal. The row
says "custom (this example's override)" where the others say "built-in default".

## 4. The visible history

A bounded list — the last ten requests, newest first — with one line each:

```
  selection tick   · picker → "Medium"        · built-in
  release settle   · Press sample             · built-in
  press contact    · Press sample             · built-in
  (no request)     · picker → "Medium" again  · value unchanged
  (no request)     · Press sample, cancelled  · press did not complete
```

This is what makes the demo work without a device, and what lets automated Studio proof
observe the phase order without feeling anything. It shows the *requested* phase and
its profile identity — never a claim that a motor moved.

Bounded is not decoration: an unbounded log in a demo that can be hammered by four
input paths is a leak with a nice name.

## 5. Lifecycle

| Event | Required behaviour |
|---|---|
| Fresh mount | The toggle is on; exactly one adapter is installed; the status reports the real result |
| Toggle off | The adapter and its effects are detached and disposed |
| Toggle on again | Exactly one working adapter is installed — never a second |
| Remount / reopen | The on default is restored |
| Scenario change, teardown | No adapter, no effect, no connection, no stale state survives |

The "exactly one" clauses are the ones worth testing hard: a second adapter installed on
the third toggle is invisible until something fires twice, and by then the cause is
several interactions in the past.

## 6. Inputs

Every comparison is exercised through pointer/touch proxy, keyboard, and gamepad, and
each must produce **exactly one** request per interaction. A duplicate pulse is the
classic defect here — one activation path firing both a synthesized and a native
event — so the history is censused per input path rather than merely observed.

## 7. What is kept, and what goes

**Kept:** the existing semantic-feedback examples where they teach a different concept
— the declaration forms, the cascade where one declaration reaches several controls,
and the feedback bus itself. Those are real lessons and they are not duplicated by the
four comparisons.

**Removed:** the redundant map tables and the copy that made the four primary
interactions hard to find. The "Sensations" panel that lists what an adapter *would*
play is superseded by four rows that actually play it.

**Rewritten:** every line of copy that says "the switch below" or implies the default is
off. That sentence is now false in this demo and was always confusing about which
default — the demo's or the library's — it described.

## 8. What stays pending

Physical sensation. Studio can prove the request, the adapter, the effect assignment,
and the reported status; it cannot prove a motor moved. That remains a named
device-verification row with an exact closing procedure, and no capture, emulator run,
or headless assertion is allowed to stand in for it.
