# Review packet — navigation & transient menus

**Automation complete, release evidence pending.** Every automatable row in
`acceptance.md` is closed. What remains cannot be closed by any instrument in this
repository, and this packet exists so it takes one focused pass rather than a discovery
exercise (execution contract §8).

You should not have to find the test cases, assemble game state, read logs, or work out
which result failed.

---

## Step 0 — BUILD THE PLACE, THEN CHECK THE STAMP

**This step exists because skipping it already cost a device session.** On 2026-08-16 the
showcase was tested against a place built **5h41m before** the commit it was meant to prove.
The tester reported "the playlist columns do not resize" — correct, and the playlist in that
build predated the feature. Nothing on screen distinguished a stale place from a fresh one.

```
cd GameStudio/ui/LuauUI
tools/build_places.sh            # rebuilds every place from the CURRENT working tree
git log -1 --format=%h           # the sha you should see on screen
```

Then publish `examples/places/LuauUI-Showcase.rbxl` and open it on the device.

**On the device: open the settings panel and read the `build` line.** It shows the short
sha, a `+dirty` flag when the tree was ahead of HEAD, and the build time — e.g.
`build 3d7c0fc+dirty 2026-08-16 17:01`. **If it does not match the sha above, stop and
rebuild.** Every row below is measured against the wrong software otherwise, and a wrong
result here is worse than no result: it sends someone hunting a defect that does not exist.

### The eight PENDING_PHYSICAL rows need a real device, not Studio

Publish and open on hardware. Studio's emulator cannot synthesize a real touch or gamepad
input class (see the table below), so a Studio pass closes none of Part 1.

### For the six PENDING_HUMAN rows, Studio is fine

```
rojo serve examples/showcase.project.json      # then Connect in Studio's Rojo plugin
```
Press Play and drive the demo picker. In a Rojo-served session the source on disk **is** the
running source, so the staleness question above cannot arise — and the build line is absent,
which is how you can tell the two apart.

`workspace.LuauUIShowcaseAPI` (`list`, `current`, `showNext`) advances the showcase without a
pointer. **Read `mounted`, not `current`** — `current` is what was *asked* for; `mounted` is
what is actually on screen and is `nil` when the last mount failed. A picker that lies turns
a whole device pass into a green run against an empty screen (`b377fe9`).

---

## Why these rows cannot be closed here

| Instrument | What it cannot do |
|---|---|
| Headless suite | No Roblox Instances, no engine layout or paint, no input delivery |
| Studio device emulator | Cannot synthesize a real **touch** or **gamepad** input class. An injected pointer event arrives as `Touch`, not `MouseButton1`/`MouseButton2` — **filtering it wrong manufactures a false positive that agrees with you** |
| Studio, any mode | Cannot summon the real mobile OS keyboard; cannot prove `PreferredInput == Gamepad`, physical forwarding, or Button A contention |
| A screenshot | Cannot show that a resize happened, that a surface did not block a tap, or that motion read as one object moving |

A row below cannot be closed by a different, easier row.

---

## Part 1 — PENDING_PHYSICAL (needs real hardware)

Bring: a touch phone, a pointer machine (real mouse), and a gamepad.

### P1 · Menu opens on touch **long-press** — `NM-X1`
**Open the `Menus and their five triggers` demo** (id `menu`).
**Do:** press and hold **card 4** (the one declaring `{activate, longPress}`) for ~0.5 s.
It opens at `began`, under your finger.
**Expect:** the menu opens as a **sheet** (touch is live, so presentation resolves to sheet,
not a floating panel). Releasing without moving does not also fire the trigger's primary
action.
**Also check:** long-press on a *truncated label that is not a menu trigger* still shows the
full-value plate. D2 deliberately kept that route — Menu claims long-press only inside its
own trigger subtree — and this is the one place that split is observable.

### P2 · Menu opens on pointer **right-click** — `NM-X2`
**Open the `menu` demo.**
**Do:** right-click **card 3** (`{activate, secondary}`) on a real mouse.
**Expect:** the menu opens as a **floating panel** anchored to the trigger, not a sheet.
**Watch for:** the browser/Studio context menu stealing it, and whether a right-click that
lands on a *child* of the trigger still opens it.

**Why the demo is five cards and not one.** No public API reports *which* trigger opened a
menu — `onOpen` takes no argument, `dump().triggers` is the DECLARED set, and keyboard and
gamepad share one `MenuOpen` action, so the control cannot tell them apart internally
either. The fixture therefore partitions the routes across cards so that **which card
opened is the answer**. Card 2 accepts only the chords and **deliberately does not open on
a tap** — that refusal is the test, not a bug. The on-screen readout names the card, the
routes it accepts, the live interaction classes at that instant, and a per-card open count.

### P3 · Pointer **hover-dwell** shows `help` — `NM-3a.1`, `NM-X2`
**Open `Coach marks and help`** (id `callout`) — `help` and `Callout` were built together and
share that fixture.
**Do:** rest a real pointer over a control carrying `help` and wait.
**Expect:** the plate appears after ~0.45 s; moving away hides it; **clicking the control
hides it and does not leave it stranded.**
**Judgement:** does 0.45 s read as a decision, or as a lag? This is the number to change if
it feels wrong.
**Negative control, and it matters:** on the touch phone, the same control must show
**nothing** — no plate, no long-press. That is the spec, not a gap.

### P4 · Gamepad reaches every menu and every tab — `NM-X3`
**Open the `menu` demo, then `Tabs, nested` (id `tab-view`).**
**Do:** with a real gamepad (confirm `PreferredInput == Gamepad`), open **card 2** with
ButtonY, walk it, enter and leave its two-level submenu with the stick/d-pad, and cancel
with B. Then page the `tab-view` strips with the shoulder buttons.
**Expect:** B closes **one** submenu level, not all of them. Shoulder paging moves the
selection and the sliding indicator follows it.
**Cannot be faked:** synthetic KeyCodes do not prove input classification or Button A
contention.

### P5 · The playlist's resize divider under a finger — `NM-8.3`
**Open the `Playlist table` demo** (id `ex02`).
**Do:** on the phone, drag the divider between Name and Artist.
**Expect:** you can actually grab it. The divider paints 8 px against a 44 px touch floor
(`grip8x28`); the expander is supposed to make it reachable. This is the row that says
whether it does.

### P6 · The Callout's tail and the segmented chip under a real theme — `NM-D1-12`, `NM-6.5`
**Open `Coach marks and help`** (id `callout`) for the tail, then `All controls`
(id `all-controls`) for the chip.
**Switch the theme first:** open the chrome panel → **Settings** → pick an ornate package
(Fantasy Ornate or Glossy Touch are the two that add the most chrome inset, so they are the
ones that break things). The flat default hides this class of defect — the playlist header
overflow found in this same review was invisible until a package was installed.
**Expect:** the 45°-rotated tail reads as part of the plate, not as a separate square; the
selection chip keeps enough contrast against the ornate chrome to say which segment is
selected.

### P7 · The level picker's bars under a finger — `NM-LP1`
**Open the `Level pickers` demo** (id `level-picker`).
**Do:** drag across the ten-bar row. Then drag off its leading edge. Then press the `−`/`+`
beside it.
**Expect:** the value tracks your finger; dragging off the leading edge clears it to **zero**
(zero is a real state — the three-block row below it starts there); the stepper and the bars
move together because they **share one Signal** and neither knows about the other.
**Also:** the `glyph` and `image` rows below exercise the other two `segment` modes. All
three must be reachable without a second fixture.

### P8 · Do the haptics actually fire, and does the screen say which? — `NM-G3`
**Open `Sensory feedback`** (id `sensory-feedback`) and scroll to the bottom panel,
`Feel it on this device`.

**Why this row exists.** You reported on 2026-08-16 that *"none of the haptics in sensory
feedback work"*, and you were right. The cause was **not** the engine choice — the adapter
has always used `HapticEffect`, not the superseded `HapticService:SetMotor`. The demo simply
never constructed it: it printed the adapter's map and captioned it *"what an opt-in adapter
would play"*. There was nothing to feel because nothing was installed.

**Do:**
1. Turn **`Play haptics on this device`** on. It constructs the real client adapter
   (`haptics.new({ enabled = true })`) and hands it the two seams a game hands it —
   `bind(presenter)` and `attachButtons`. The library itself stays default-off; the panel
   says so on screen, because the demo opting in is a different decision from the library
   opting in.
2. Press **Buy**, **Delete**, **Pick** and the three cascade buttons. `Delete` is a
   `reject` → `UINotification`; the others are `UIClick`. **`Mute` declares `none` and must
   feel like nothing** — that is the negative control, and a `Mute` you can feel is a defect.
3. Read the two lines under the switch. **Every press re-reads the adapter**, so plugging a
   pad in mid-pass and pressing again updates the verdict without toggling.

**The line says exactly one of three things, and they are three on purpose**
(`docs/lessons/capability-probes-must-be-tri-state.md` — this repository has now shipped two
instruments that collapsed "no" with "could not tell"; do not accept a third):

| On screen | What it means | What to record |
|---|---|---|
| **Requested** | A pad is connected, it reports vibration support, and *N* buttons are holding a press effect. It does **not** say "played" — whether a motor fired is not readable from game code | **Did you feel it?** This row is the only instrument that can answer |
| **This platform says no** | A connected pad answered `false`, or this client cannot construct `HapticEffect` at all. The engine's own error text is printed in the line | Feeling nothing is the **expected** result. Type the line back |
| **Could not determine** | Everything else — and it is not a failure. A phone has no haptics probe on the platform at all, and an absent gamepad answers the same `false` as a motorless one | Type the line back, **and still say whether you felt anything**. The line tells you whether the effects went out; only your hand can say whether they arrived |

**A phone with no controller landing on `Could not determine` is a correct result**, not a
bug report. What would be a bug is the screen saying "no" when it means "cannot tell".

**Also on screen, under `What no game code can read`:** whether an effect actually fired,
and the player's own haptics strength (`UserGameSettings.HapticStrength` is
`RobloxScriptSecurity` on read). The docs also never say which input devices trigger
`GuiButton.PressHapticEffect`. If you feel nothing on a phone, that combination — not a
defect in this adapter — is the first suspect.

**Turn the switch off before you leave the demo.** While it is on, every button on the
client carries its declared press effect, chrome included (that is deliberate: press
anything and find out whether this hardware does haptics at all). Switching off, or leaving
the demo, releases every one of them and destroys the effects.

---

## Part 2 — PENDING_HUMAN (judgement, not measurement)

### H1 · The sliding indicator reads as **one object moving** — `NM-4.4`, `NM-X4`
**Open `Tabs, nested`** (id `tab-view`) — it carries **both** skins: the app-level strip is
`underline`, the page-level strip inside the Pages tab is `pill`. For the segmented-picker
form of the same mechanism, open `All controls` (id `all-controls`).
**Do:** tap between segments repeatedly, including interrupting a slide mid-flight.
Judge the `underline` and the `pill` separately — they are one mechanism and two skins, and
either can read wrong on its own.
**Judge:** does the chip read as one thing travelling, or as two things cross-fading? Does an
interrupted slide feel caught or feel snapped?
**Then turn reduced motion on** (`LuauUIShowcaseAPI.motion("reduced")`) and repeat: it must
**snap** with no intermediate frames, and that snap must not feel broken.

### H2 · A Callout reads as **help**, not as an ad — `NM-X5`
**Open `Coach marks and help`** (id `callout`).
**Judge:** Apple's own warning is the bar — *"Use tips sparingly… Don't use tips to guide
people through your app, or for advertising and promotion purposes."* Does the plate feel
like it is telling you something useful once, or like it is selling you a feature?

### H3 · Icon-only segments are readable and comfortable — `NM-6.1`, `NM-6.5`
**Open `All controls`** (id `all-controls`) — the icon-only segmented picker and the vertical
pill rail live there.
**Judge:** on the phone, is the icon-only vertical rail comfortable under a thumb at 44 px?
Does the icon+label → icon-only degrade happen where you would put it, or too early?

*Honest note:* D6 shipped icons and the vertical rail with **spec consumers only** — no
example used them, which is why this row had nowhere to look on the first pass. The demo
was added afterwards, for exactly that reason.

### H4 · The HUD's disclosure route is discoverable — `NM-7.4`
**Open `Screen-anchored HUD`** (id `hud`). Turn the URL bar on in portrait so regions
elide and drop.
**Judge:** when the tasks and the weapon rail give way, is it *obvious* where they went? The
gate proves a route exists at every viewport. It cannot prove a player would find it.

### H4a · Reproduce the HUD paint failure and READ IT OFF THE SCREEN — `NM-H4a`
**Open `Screen-anchored HUD`** (id `hud`) on the phone. A small plate is already on the
right edge, vertically centred, reading `Paint probe · <viewport> · solve <n>`. That is a
**separate surface** with its own render controller, so it keeps painting when the HUD does
not — which is the whole reason it exists.

**Do, exactly, in this order** (the director's own sequence, 2026-08-16):
1. Portrait. Tap the **···** disc in the top-left round strip, then **Close** the panel.
2. Rotate to **landscape**. Turn **URL bar** on, then off again.
3. Rotate to **portrait**. Turn **URL bar** on, then off again.
4. Rotate to **landscape**. This is where it went wrong.

**Then read the plate and photograph it.** It says one of two things:

- `14 of 14 painting` — nothing diverged. Say so; that is a real result.
- `7 of 14 NOT PAINTED`, then the **names in document order**, then `first painted: …`,
  then `hidden under: …`. **Those three lines are the report.** Type them back verbatim —
  the names are node identifiers, not prose, and `hidden under` is the one that decides
  whether seven regions were lost under a single node or seven times over.

**The plate freezes itself.** It latches on the frame the disagreement appears and stops
updating, so you do not have to catch it — by the time you look, it is already holding the
failing frame. `Freeze` / `Live again` on the plate releases and re-arms it. Do not press
anything before you have read the plate.

**Why it needs a human at all:** the exact sequence above has been driven 288 times
headlessly and twice against the real Roblox adapter in live Studio — with the ··· panel
opened and closed, with per-orientation insets, with the insets arriving a frame after the
viewport — and diverged from a fresh mount by **zero** every time. Studio cannot perform an
operating-system orientation change and neither can its emulator. Full record:
`artifacts/navigation-and-menus/h4a-paint-probe.md`.

**If it says `no engine read — model only`,** the build is wrong: publish a place built by
`tools/build_places.sh` from the current tree and start again at Step 0.

---

### H5 · Do the three `segment` modes read as the same control? — `NM-LP2`
**Open the `level-picker` demo.**
**Judge:** the bar, glyph and image rows are one control with one argument. Do they read
that way, or do they read as three different widgets? Is the filled/unfilled contrast strong
enough on a phone in daylight — particularly for `bar`, which is a tinted box and has no
shape cue the way ★/☆ does?

---

## What to record

For each row: **pass / fail / changed-my-mind**, the device and build, and — where it failed
— one sentence on what you saw. That is enough; the fixtures are deterministic and the
traces are already stored beside this file.

If a row fails, it is a `FAIL_PRODUCT` against the acceptance ledger, not a note. Bring it
back and it gets fixed.
