# Review packet — `traversal-document-order`

Two rows no instrument in this build can close. Everything else is automated and
stored; these need a person and a real device.

**Why this packet is not a formality.** The stage this one fixes passed its gate and
**three** independent fresh-context reviews. The director then found two real defects
in a ten-minute playtest, this one among them, because every instrument measured the
order it had been told to expect. So: TD-P1 is not "sanity-check the screenshots". It
is the row that has historically caught what the machines did not.

---

## TD-P1 — a person tabs through the fixture (`PENDING_HUMAN`)

**Time:** about two minutes.

### Setup

```bash
cd GameStudio/ui/LuauUI
lune run tools/lune/studio_sync          # leave it running
```

In the open gallery place (`Place1`), in the **Edit** datamodel, run
`tools/studio/inject.luau` via the Studio MCP, then:

```lua
workspace:SetAttribute("LuauUI_Scenario", "keyboard_navigation")
```

Press **Play**. (Injecting is not enough on its own — `require` caches module
results in Edit, so only a Play session sees fresh source. The gallery client
disables the CoreGui players list for you, which is what frees `Tab` at all.)

### What to do

Click once on the **name field** at the top, then press **Tab** repeatedly and watch
where the focus ring goes.

### Expected

```
Name field → Save → Reset → the SLIDER → − → + → Row 1 … Row 12 → (wraps)
```

The slider sits on screen between the Save/Reset row and the stepper. **Tab should
reach it there** — fourth — not after all twelve list rows.

Then press **Down** a few times from the stepper. It should walk into the list
(Row 1, Row 2, …) and should **not** land on the slider. That difference is
deliberate: Tab means document order, arrows mean "content before grab handles".

### The judgment being requested

Not "is the order correct" — the machines have that covered, and the exact trace is
in `studio/traversal.json`. The question is:

> **Does tabbing through this form feel like reading the form?**

Specifically worth an opinion:

1. ~~Can you tell when Tab lands on the slider?~~ **Reported and fixed** (round 2,
   TD-17): the ring was there and invisible — an accent *hairline* at 92%
   transparency, because `strokeData{ color = "accent" }` defaults its weight and
   alpha to the theme's hairline. It is now a 2px opaque accent ring on the thumb,
   the same weight the adapter draws on every other control. **Please confirm it
   reads at a glance now** — the measurement says visible, but visible and
   *legible* are different claims and only you can make the second one.
2. Is an accent ring on the **thumb** the right affordance for a value control at
   all, or would a glow / thickened rail / highlighted readout read better? The fix
   made the existing design visible; it did not revisit the design.
3. Is landing on the slider between the buttons and the stepper what you expected,
   or would you rather Tab skipped value controls entirely?
4. Anything else that reads wrong.

### If something is off

`artifacts/traversal-document-order/studio/traversal.json` has the full forward and
reverse traces, the raw key log, and the live `handle.focusOrder()` dump. A new
control can be moved without touching the framework:

```lua
UI.Button{ id = "Submit", label = "Submit", traversalPriority = 1 }   -- traverses late
```

---

## TD-P2 — physical keyboard (`PENDING_PHYSICAL`)

Everything above is Studio-synthesized input. A real client on real hardware is a
separate row and cannot be closed by it.

This row **inherits Step 8's open items unchanged** — it does not reopen or re-derive
them:

| Inherited | What it is |
|---|---|
| **DK-P1** | A real operating-system keyboard on a phone/tablet. The emulator cannot produce a keyboard-capable touch profile and never summons the mobile OS keyboard. |
| **DK-P2** | Physical keyboard hot-plug against a real avatar control stack. |
| **DKN-1** | `Tab` is the CoreGui players-list shortcut. With the leaderboard **enabled** — the default — the engine will not deliver it at all. This stage changed the *order* Tab walks, not whether Tab arrives. Unchanged and still true. |
| **DKN-2** | Keyboard IAS bindings are dead while a `TextBox` holds engine capture. |

**One observation from this session, offered as a lead and not as a result.** The
first Tab did move from the focused name field to Save, with `gameProcessed=false`.
That is *not* a contradiction of DKN-2 — the field held LuauUI focus but was never
put into an editing state, which is the condition DKN-2 describes. Worth ten seconds
on real hardware: click **into** the field so the caret is live, then press Tab.

---

## What is already closed, so nobody re-runs it

| | |
|---|---|
| Library suite | **3114 passed** (stage start 3079; 35 new tests) |
| Rascal Rally suite | **3026 passed, 0 failed** (was 3019 passed / **1 failed**) |
| Mutation-proved | traverse-ignores-rank → 5 red; presenter-stops-ranking → 8 red; the naive fix that breaks the arrows → 2 red; the game tripwire with a Slider added → 1 red |
| Studio, live | forward Tab, reverse Shift+Tab, arrows-unchanged, dump-matches-behavior, slider focus ring before/after, captures — `studio/traversal.json` |
| Still open besides these two | the Rascal Rally **game-place** canary (`TD15-consumer-canary`), recorded PENDING rather than closed by the library place |
