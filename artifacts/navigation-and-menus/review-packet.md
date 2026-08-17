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

### The six PENDING_PHYSICAL rows need a real device, not Studio

Publish and open on hardware. Studio's emulator cannot synthesize a real touch or gamepad
input class (see the table below), so a Studio pass closes none of Part 1.

### For the four PENDING_HUMAN rows, Studio is fine

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
**Scenario:** any surface with a `newMenu` trigger.
**Do:** press and hold a menu trigger for ~0.5 s, then release.
**Expect:** the menu opens as a **sheet** (touch is live, so presentation resolves to sheet,
not a floating panel). Releasing without moving does not also fire the trigger's primary
action.
**Also check:** long-press on a *truncated label that is not a menu trigger* still shows the
full-value plate. D2 deliberately kept that route — Menu claims long-press only inside its
own trigger subtree — and this is the one place that split is observable.

### P2 · Menu opens on pointer **right-click** — `NM-X2`
**Do:** right-click a menu trigger on a real mouse.
**Expect:** the menu opens as a **floating panel** anchored to the trigger, not a sheet.
**Watch for:** the browser/Studio context menu stealing it, and whether a right-click that
lands on a *child* of the trigger still opens it.

### P3 · Pointer **hover-dwell** shows `help` — `NM-3a.1`, `NM-X2`
**Do:** rest a real pointer over a control carrying `help` and wait.
**Expect:** the plate appears after ~0.45 s; moving away hides it; **clicking the control
hides it and does not leave it stranded.**
**Judgement:** does 0.45 s read as a decision, or as a lag? This is the number to change if
it feels wrong.
**Negative control, and it matters:** on the touch phone, the same control must show
**nothing** — no plate, no long-press. That is the spec, not a gap.

### P4 · Gamepad reaches every menu and every tab — `NM-X3`
**Do:** with a real gamepad (confirm `PreferredInput == Gamepad`), open a menu with the
bound button, walk it, enter and leave a submenu with the stick/d-pad, and cancel with B.
Then page a `TabView` with the shoulder buttons.
**Expect:** B closes **one** submenu level, not all of them. Shoulder paging moves the
selection and the sliding indicator follows it.
**Cannot be faked:** synthetic KeyCodes do not prove input classification or Button A
contention.

### P5 · The playlist's resize divider under a finger — `NM-8.3`
**Scenario:** `ex02` (Playlist table).
**Do:** on the phone, drag the divider between Name and Artist.
**Expect:** you can actually grab it. The divider paints 8 px against a 44 px touch floor
(`grip8x28`); the expander is supposed to make it reachable. This is the row that says
whether it does.

### P6 · The Callout's tail and the segmented chip under a real theme — `NM-D1-12`, `NM-6.5`
**Scenario:** `callout`, then `all-controls` with an ornate theme package installed.
**Expect:** the 45°-rotated tail reads as part of the plate, not as a separate square; the
selection chip keeps enough contrast against the ornate chrome to say which segment is
selected.

---

## Part 2 — PENDING_HUMAN (judgement, not measurement)

### H1 · The sliding indicator reads as **one object moving** — `NM-4.4`, `NM-X4`
**Scenario:** `r3`-shaped — any segmented picker; then a `TabView` strip.
**Do:** tap between segments repeatedly, including interrupting a slide mid-flight.
**Judge:** does the chip read as one thing travelling, or as two things cross-fading? Does an
interrupted slide feel caught or feel snapped?
**Then turn reduced motion on** (`LuauUIShowcaseAPI.motion("reduced")`) and repeat: it must
**snap** with no intermediate frames, and that snap must not feel broken.

### H2 · A Callout reads as **help**, not as an ad — `NM-X5`
**Scenario:** `callout`.
**Judge:** Apple's own warning is the bar — *"Use tips sparingly… Don't use tips to guide
people through your app, or for advertising and promotion purposes."* Does the plate feel
like it is telling you something useful once, or like it is selling you a feature?

### H3 · Icon-only segments are readable and comfortable — `NM-6.1`, `NM-6.5`
**Judge:** on the phone, is the icon-only vertical rail comfortable under a thumb at 44 px?
Does the icon+label → icon-only degrade happen where you would put it, or too early?

### H4 · The HUD's disclosure route is discoverable — `NM-7.4`
**Scenario:** `hud`. Turn the URL bar on in portrait so regions elide and drop.
**Judge:** when the tasks and the weapon rail give way, is it *obvious* where they went? The
gate proves a route exists at every viewport. It cannot prove a player would find it.

---

## What to record

For each row: **pass / fail / changed-my-mind**, the device and build, and — where it failed
— one sentence on what you saw. That is enough; the fixtures are deterministic and the
traces are already stored beside this file.

If a row fails, it is a `FAIL_PRODUCT` against the acceptance ledger, not a note. Bring it
back and it gets fixed.
