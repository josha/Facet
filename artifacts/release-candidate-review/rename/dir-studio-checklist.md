# DIR wave — the Studio confirmation check list

For the controller to run after the implementer's report. Every row names WHAT to
drive, WHAT to read, and the value this wave's fixes predict. Nothing here needs a
new instrument: the showcase's own API and the fixture's debug plate carry it.

**Build first.** These fixes are model-side and every one of them is invisible in
a stale place. Rebuild `examples/places/Facet-Showcase.rbxl` and confirm the build
stamp against `git log -1 --format=%h` before reading a single number — a report
taken against a place built before the commit is the class recorded on 2026-08-16.

**Instrument discipline, from this round's own scar tissue:**

- **Read `GetStyled("FontFace")`, never the plain `FontFace` property.** The plain
  read reports `LegacyArial` while the sheet paints Fondamento. This round fell
  into it once already (`dir-reproductions.md`, DIR-2 addendum).
- **A Facet root is `IgnoreGuiInset = true`**, so `AbsolutePosition.Y` reads
  inset-subtracted and a **negative y means near the top, not off the top**
  (confirmed by Roblox staff — see `screeninsets-probe.md` §2.1).
- **Zoom the captures.** The 28px overlap this wave is about is not legible in a
  full-screen screenshot; it was found in a zoomed one.

---

## 1. The gutter floor (contract 6)

**Drive:** the demo picker's chip strip, at phone portrait (~393px), under **every**
theme in the Settings panel's theme list, one at a time.

**Read:** `AbsolutePosition.X` of `/ShowcaseChrome/Dock/Bar/Chips`, plus a zoomed
capture of the strip's **left border against the glass**.

**Expect:** `X >= 8` under every package. The two that moved:

| package | before | after |
|---|---|---|
| Classic Desktop | 4 | **8** |
| Compact Pointer | 6 | **8** |
| Fantasy Ornate / Parchment / Pixel Quest / Sci-Fi HUD | 8 | 8 (unchanged) |
| Glossy Mobile / Glossy Touch | 10 | 10 (unchanged) |

**And the negative half:** nothing else in Classic Desktop or Compact Pointer may
have moved. Spot-check a Table row height and a compact button's padding under
Classic Desktop against the previous build — the fix is a derived `space.gutter`
step, not a raised `space.s`, precisely so those do not move.

**If the border is still clipped at x = 0** after this: the model is clear and the
remaining suspect is the adapter/device seam. Go to
`artifacts/release-candidate-review/rename/screeninsets-probe.md` §4 and run that
probe instead of guessing.

## 2. The themed HUD under the showcase's own chips (contracts 2, 1, 3)

**Drive:** demo = **hud**, theme = **Fantasy Ornate (Grand Hall)**, topbar strip
**ON** (the fixture's own `Topbar strip` switch), URL bar closed. Both orientations.

**Read, at compact-phone-portrait (~360x691):**

- the **weapon rail** (`/HudScreen/Hud/Rail`) and the **FPS readout**
  (`/HudScreen/Hud/Readout`) against the **Settings chip**.

**Expect:** the whole right column now starts **below** the chip row. The
reproduction measured `rail x=262..352 y=0..119` against `chip x=196..290 y=8..75`
— a 28px x-overlap. After the fix the rail's `y` is at or below the chip row's
bottom edge, and **no HUD node's rect intersects the chip row's rect at all**.

The headless twin of this exact shape (chips 282px wide at a 360 viewport) is
pinned in `tests/hud_chrome_rotation.spec.luau`, *"DIR-2: the beside-chrome band
gives way at the measured collision shape"* — 0 painted nodes inside the row,
where the pre-fix rule put 3 there.

**And the half that must NOT have changed:** at landscape, a column the chips do
**not** reach must still sit **level** with them. The clock is the one to look at:
if the chips end well left of the clock's own box, `clock.y` stays at the platform
band's bottom (58) and only `Rounds` drops below the row. A HUD that pushed
everything down again would be the round-2 regression the director already
refused.

**Zoomed capture to take:** the top-right corner, portrait, ornate — the rail
plate's top edge against the Settings chip's bottom edge.

**Also read (contracts 1 and 3), on the same screen:**

- **no zone paints at 0x0.** The reproduction's `"Tasks 1/3"` in a 48x0 box is the
  shape; every visible plate must have real extent.
- **no plate is smaller than the line it holds.** Under ornate the pill plates
  legitimately paint *outside* their own rect — `chromeOutsets.panel = 20/0/0/0`,
  i.e. the layered art's declared 20px top overhang — so read the **painted**
  plate, not `AbsoluteSize`, and expect the glass to sit behind the whole line.

## 3. The rotation, and the give-way latch (contract 4)

**Drive:** the emulator's driver row, `compact-phone-portrait` → pinned
`compact-phone-landscape` (samsung_galaxy_s22_ultra, 678x339), hud + ornate.

**Read:** the **Feed** zone (`/HudScreen/Hud/Feed`, "Ravi eliminated Mo") and the
fixture's own debug plate line, which reads `N of 14 rows wanted · skipped: …`.

**Expect:**

- Feed is **on screen after the rotation** — the reproduction had it at
  `y=-58..-58 x=8..8`, a 0x0 corpse at the inset corner;
- the plate does **not** list `Feed` under `skipped`;
- and then **swap the theme** (Studio Neutral and back). The layout must be
  identical to a fresh mount under that theme — a decision that survives a swap is
  the latch the director photographed.

The model half of this is a **null result and is already pinned**: with the six
platform facts published one per tick in the adapter's device order, the settled
composition equals the single-batch one, zone for zone, both directions
(`tests/hud_chrome_rotation.spec.luau`, "DIR-5"). So **a divergence here is a
platform-adapter finding, not a composition one** — capture the six facts
(`viewportRect`, the three inset areas, `topbarInset`, `displaySize`) before and
after the rotation and attach them.

## 4. The objective chip's width swap (contract 7)

**Drive:** hud + ornate, topbar strip ON, portrait. Then raise the system text
size to **Larger** and to **Largest**.

**Read:** the chip in the free strip beside Roblox's own buttons, and its
`GetStyled` text bounds against the plate.

**Expect:** at the raised preferences the chip shows **`R3`**, not a cut
`Round 3 · Capt…`. The ladder swaps to the short rung now, because a candidate
whose one line has to be CLAMPED to its box no longer counts as fitting.

At the default preference and in landscape the full `Round 3 · Capture` still
shows — the fix must not have made the chip permanently short.

## 5. Value text vs label text — the R9 classification (controller ruling, 2026-08-18)

The standing localization rule is *"wrap or auto-fit, never clip"*. On a HUD that
forces a distinction the rule does not itself make, and this is the ruling:

- **VALUE text is a reading** — a timer, a score, an ammo count, a health figure,
  a reward, a frame readout. Cutting one does not shorten it, it **changes** it:
  `2:1…` is not a shortened round timer and `24/9…` is not a shortened magazine.
  A value therefore **never truncates**. It gets its box (the zone gives way and
  it wraps below), or it **reformats through an authored degrade** (`2:14` →
  `2m`), or the whole plate elides and the ··· sink carries it.
- **LABEL text is a name or a sentence** — a weapon, a task, a kill-feed line.
  Truncation loses detail a player can infer or reach, and it stays the rank
  ladder's ordinary degrade.

The classification lives in the fixture (`examples/gallery/scenarios/hud.luau`,
`VALUE_TEXT`, exported as `hud.valueText`) and
`tests/overflow_sweep.spec.luau` reads it — so a new readout joins the check by
being declared once, and the check and the screen cannot drift.

### The census it was made from

9 viewports x 9 packages x 4 text preferences x both strip states, chip row
declared. **Eleven** nodes truncated; **one** of them was a value.

| node | string | class | before | after |
|---|---|---|---|---|
| `Clock/TimerOnlyPod/…/TimerOnlyText` | `2:14` | **VALUE** | 114 cells cut | **0** — reformats to `2m` |
| `Feed/FeedLine` | `Ravi eliminated Mo` | label | 138 | 138 (ladder degrade) |
| `Tasks/TasksOne/…/TasksOneName` | `Win a round` | label | 178 | 178 |
| `Tasks/TasksFull/…/TaskName1..3` | `Win a round` / `Land 25 hits` / `Open a crate` | label | 52 / 92 / 92 | unchanged |
| `Rail/RailTall/W1..W3/…/WnName` | `Rifle` / `Pistol` / `Knife` | label | 48 / 48 / 28 | unchanged |
| `Rail/W1c/…/W1cT` | `Rifle` | label | 83 | 83 |
| `Weapon/WeaponText` | `Ranger rifle` | label | 73 | 73 |
| `Strip/…/ObjectiveT` | `Round 3 · Capture` | label | cut at +10/+14 | **0** — swaps to `R3` (contract 7) |

**Value nodes that never truncated and must not start**: `TimerText`,
`ScoreHomeT`, `ScoreAwayT`, `HealthNum`, `HealthOnlyT`, `W1Ammo`, `W2Ammo`,
`W3Ammo`, `Reward1`, `Reward2`, `Reward3`, `ReadoutText`. They are on the list so
the rule is a rule rather than a record of what happened to break.

**Total: 946 → 832 truncations, and every one that remains is label class.**

### What to check in Studio

Drive hud + ornate, portrait, strip ON, and raise the system text size to
**Larger** and then **Largest**:

- the round timer reads **`2m`**, never `2:1…`. At the default preference and in
  landscape it reads the full `2:14`;
- the ammo counts, the two scores, the health figure and the three `+50/+120/+300`
  rewards are whole or absent — never ellipsized;
- weapon and task names may still show an ellipsis. **That is the ruling working**,
  not a defect: report them only if a name is unreadable rather than merely cut.

## 6. What is knowingly NOT fixed, and should be read as-is

Under ornate at 360x691 these text nodes still truncate — all **label** class, so
under R9 they are the rank ladder degrading a 114px lane rather than defects:

| node | string | preference |
|---|---|---|
| `Feed/FeedLine` | "Ravi eliminated Mo" | +0 (with the chip row declared) |
| `Tasks/TasksOne/…/TasksOneName` | "Win a round" | +0, +4 |
| `Rail/W1c/…/W1cT` | "Rifle" | +10 |
| `Weapon/WeaponText` | "Ranger rifle" | +10 |

None is below a floor and none paints in a degenerate box.

**The two rows that used to be here and are gone**: `Clock/…/TimerOnlyText`
("2:14" at +10/+14) is fixed — the timer reformats to `2m` (§5) — and
`Strip/…/ObjectiveT` swaps to `R3` (§4). The `2:1…` timer this section previously
asked for a ruling on **got one**: R9, and it is implemented.

`Feed/FeedLine`'s preference column is corrected from `+0, +4` to `+0`: with the
chip row declared it fires at the default preference only (reviewer INFO, and
re-measured here).
