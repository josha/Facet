# Parallel Sponsor (Step 6) — DIRECTOR REVIEW PACKET

**Date:** 2026-07-31 (refreshed end of day) · **Stage:** `parallel-sponsor` (LuauUI
roadmap Step 6) · **Contract:**
`GameStudio/ui/LuauUI/docs/plans/agent-execution-contract.md` §8 (one review build,
one packet, no state assembly by the reviewer).

## Status — automation complete, device pass 2 + FEEL evidence pending

> **Automation complete THROUGH designer round 2 + fix round 3, director visual
> rounds 1–6, director device round 1, and the commissioned tuned-values audit.
> Device pass 2 and the FEEL judgment are pending.** Not "complete": the
> physical-device rows, the five device re-checks device round 1 could not close,
> the director's FEEL judgment, and the remaining capture sweep are open by design
> (contract §8: hardware and human review unavailable ⇒ report exactly this, never
> "fully complete").

| Fact | Value (verified in this run) |
|---|---|
| RascalRally suite | **2819 passed**, exit 0 (`games/RascalRally/code/run-tests.sh`) |
| LuauUI suite | **2755 passed**, exit 0 (`GameStudio/ui/LuauUI/run-tests.sh`) |
| Legacy checksums | **11/11 match** the freeze (`baseline/legacy-checksums.txt`, re-run 2026-07-31) |
| Sanctioned changes | 6 files, all additive, stamped in `baseline/sanctioned-changes-post-abc.txt` |
| Selector default | **legacy** — `workspace.UseLuauUISponsor` is unset; nothing LuauUI-Sponsor-related even loads on that path |
| Rollback | clear the attribute |
| Format gate | `stylua --check src tests` clean on both trees |
| Reviews closed | designer round 1 (11 findings, 5 rulings) · designer round 2 (12 findings, 3 rulings) · fix round 3 · **director visual rounds 1–6** (DV-1…DV-8, DV2-1…6, DV3-1…5, DV4-1…3, DV5-1…3, DV6-1…2 — **every item closed**) · **director device round 1** (7 bugs + 1 observation, all fixed with tests and mutations) · **tuned-values audit** (108 rows: 80 matched / 20 better / 3 gap-fixed / 4 gap-queued / 1 N-A) |
| Reviews open | **device pass 2** (§3.1) · the **FEEL sitting** (§3.2) · the outstanding capture sweep (§5.3) |

**The finish screen is already approved.** `docs/DECISIONS.md` 2026-07-31 — *"I do
think the new race finish screen is the best yet"* — ratifies the commissioned
**S16 v2** redesign (declared on `UI.Composition`, three-lane landscape, spanning
recap, role-aware CTAs, coin-earning beat) as the `UI-SPEC` gate outcome for that
surface. Everything in this packet about results (§2.3 S8, §4, §5) describes S16 v2
**as built**, not as proposed. `rows/DV6-results-columns-iphone16-landscape.png` is
the frame that verdict was given against.

---

## 1. ELI5 — what this is, in plain language

**What was built.** Sponsor Mode has a second, complete presentation built on the
studio's own UI framework (LuauUI). It draws the same director table, racer list,
minimap, card hand, chip row, ticker, toasts, world omens and results screens the
shipped Sponsor Mode draws — from declarative blueprints instead of hand-built
Roblox GUI objects.

**What stayed the same.** Everything that decides anything. The server still owns
race rules, card legality, fairness, energy, and results; both presentations read
the same replicated attributes and send the same commands on the same remotes. The
eleven shipped Sponsor modules were not touched — their checksums are byte-identical
to the freeze, re-verified today. Legacy is still what every player gets; the new
presentation only appears when a developer sets one Studio attribute, and clearing
it puts everything back.

**What is being asked of you.** Three things, in this order:

1. **Drive it once** (§2). Fifteen to thirty minutes, one Play session, a scripted
   scenario list. The state is set up for you; nothing to assemble. New this round:
   nine **drive verbs** (§2.4) let a Studio session run the tap and drag flows
   without a phone.
2. **Judge it on the device** (§3). §3.1 is the short list of five re-checks device
   round 1 could not close from here — they are what your last pass was one pass
   away from settling. §3.2 is the standing physical/FEEL list: a real finger, a
   real thumbstick, real eyes at arm's length.
3. **Decide twelve open questions** (§4). Eleven earlier ones are now **resolved**
   and recorded (§4.1) — including the leaderboard, the CTA copy and the finish
   screen. What is left is four tuning questions the audit queued, one governance
   ratification, one legacy edit, and the design rows that only a human can close.
   Everything still provisional is *labelled on screen*, which is the lesson from
   the first visual round.

**What this packet is not.** It is not a cutover proposal. Making LuauUI the
default is a separate decision after this gate, and deleting the legacy code is a
third one after that (`LUAUUI_SPONSOR_PARALLEL.md` § Explicitly later).

---

## 2. The one-sitting drive script

Everything below is copy-pasteable. Two hard traps, stated once:

- **`RascalSponsorScenarioAPI` must be invoked from the SERVER VM.** It is a
  server-side rig; a Client-VM invoke will not find the callback's upvalues.
  **`LuauUISponsorDevReport` and `LuauUISponsorDevDrive` must be invoked from the
  CLIENT VM** — they are the presenter's own exports.
- **Every one of these functions returns a JSON *string*.** `JSONDecode` it before
  reading a field, or you will be indexing a string.

### 2.1 Setup (once, before Play)

1. Open the debug place in Studio, connect Rojo (`rojo serve` from
   `games/RascalRally/code`, then the plugin's **Connect**), and **verify the sync**
   — `rojo serve` running is not the same as Studio connected
   (`docs/lessons/studio-sync-verify-rojo-connected.md`). Cheap check, Edit mode:

   ```lua
   -- execute_luau / command bar, Edit
   print(game.StarterPlayer.StarterPlayerScripts.Client:FindFirstChild("LuauUISponsor") ~= nil)
   ```

   `false` means the place is stale and every observation afterwards is meaningless.

2. Set the three flags in **Edit** (the selector is read once at client start, so it
   must be set before Play):

   ```lua
   -- execute_luau / command bar, Edit
   workspace:SetAttribute("UseLuauUISponsor", true)   -- mount the LuauUI presenter
   workspace:SetAttribute("SponsorScenarioRig", true) -- arm the deterministic rig
   workspace:SetAttribute("TrackLayout", "debug")     -- the bench track
   ```

3. **Play** (Play Solo).

4. Become the sponsor. Any one of these — the first is the honest path:
   - **the modal**: on boot the role-pick modal is up; press **Cause Chaos**;
   - **Client VM**: `game.ReplicatedStorage.SponsorCmd:FireServer("role", "sponsor")`;
   - **Server VM**: `workspace.RascalSponsorScenarioAPI.step:Invoke("pickSponsor")`
     after selecting `boot-role`.

5. Confirm the labels are on screen. They are how a capture proves which build it is:
   - bottom-left dev chip: **`LuauUI Sponsor [dev] · build 0.7.0 · presenter=luauui`**
   - top-left of the table plate: **`[LEGACY PILL — ruling pending]`** (decision (c),
     §4.2 — still the one item with an on-screen tag)
   - the legacy build carries **neither**.
   - The Roblox player list is **gone on both builds** — that is your own game-wide
     ruling, shipped (§4.1).

### 2.2 The three instruments

```lua
-- SERVER VM — the scenario rig
local HttpService = game:GetService("HttpService")
local api = workspace.RascalSponsorScenarioAPI
return HttpService:JSONDecode(api.list:Invoke())    -- the scenario names
```

```lua
-- CLIENT VM — the presenter's own snapshot (surfaces, focus, poses, list, watch,
-- cards, story, omens, results, core counters, command counters)
return game:GetService("HttpService"):JSONDecode(workspace.LuauUISponsorDevReport:Invoke())
```

```lua
-- CLIENT VM — DRIVE the surface (see §2.4 for the verb table)
local H = game:GetService("HttpService")
return H:JSONDecode(workspace.LuauUISponsorDevDrive:Invoke("tapCard", 1))
```

Rig verbs: `list` · `select "<name>"` (applies the fixture **and** its phase hold) ·
`steps` · `step "<name>"` · `holdPhase "racing|prestart|grace|results|rollcall"` ·
`release` · `reset` · `report`. A held phase does not advance — the live bench
otherwise auto-advances results in ~7 s and destroys the evidence.

**Filing a capture:** save the capture beside `report().stamp` and the dev report.
The stamp is what pairs a LuauUI frame with its legacy twin.

**Device rows:** set the state **first**, then select the emulator preset. Studio's
Device Emulator swallows *all* injected input while active
(`docs/lessons/studio-device-emulator-swallows-injected-input.md`) — your real mouse
still works; the automation does not. Five views only: compact phone portrait, the
same phone landscape, tablet landscape, desktop, console/ten-foot.

### 2.3 The ordered run

Run in this order; it front-loads the surfaces with the least evidence.

| # | Scenario / steps | Expect to see (from the evidence rows) |
|---|---|---|
| **S1** | `select "boot-role"` (holds `prestart`) | Role-pick modal up, scrim real, **two verbs only** — Race Now accent-filled and dominant, Cause Chaos secondary — and **no dismiss affordance anywhere**. Initial focus sits on Race Now. Keyboard Down moves to Cause Chaos; **Backspace does nothing**; Return sends **exactly one** `("role","sponsor")`. `commands.total` is 0 until you pick. *(PS-L1/L2; `rows/PS-L2-rolepick-modal.png`.)* Cards stay disabled and the countdown never elapses under this hold — by design. |
| **S2** | `select "live-normal"` (holds `racing`) — the everyday table | **Landscape:** the Lap and Race Drama chips dock in the platform **topbar band, immediately right of the settings gear** (DV3-1, off the two env facts `topbarInset` / `topbarSafeInsets`). **Portrait:** when that band cannot hold them they take a **reserved band above the table**, and the table begins exactly below it — the chips never paint over the map, the P1 row or the dock (round 2's N3). Portrait = map top / list below; landscape = map left / list right. Rows are **flat dark plates with NO resting outline of any kind** — DV4-1 retired the identity hairline; identity is the **swatch** alone. The **watched** row is a plate *level* and nothing else (DB-3(a) retired the marker bar). No row ever wears a ring. Map name tags are dark pills with bold white text at legacy's transparency. The drama dial is nine tangential dashes + needle + hub, with the segment under the needle lit. Card faces are **purple Headwind / gold Tailwind** — legacy's own constants. |
| **S3** | still `live-normal`: press the `–` toggle (or gamepad **Y**) | Follow pose: minimap on a **real dark plate** inset top-right (it painted on bare sky in round 1), watched-racer card bottom-centre, name **centred** between full-size `‹ ›` chevrons, no racer list. **There is no separate restore button and never was** — the map canvas itself is the restore target. Toggle back. |
| **S4** | `select "legal-illegal-hand"` → `step "blockedSpread"`, `step "blockedShielded"`, `step "helpOnly"` | Rows 1–2 preview as spread-blocked: receded plate, desaturated swatch, **slash form** — never colour alone. A blocked slot is still pressable and **says why**; it never silently no-ops. Each invalid attempt raises **one** correctly-keyed toast on legacy's plate, held past a **2.5 s** read floor. Gate pills appear in `locked` (22 px glyph-only, no ring) and in the **authored `play`/`cooldown` forms — 44×22 pill, **28 px author badge centred on its LEFT cap**, neutral rim, 12-tick countdown ring (DB-1; these forms were structurally unreachable before this round, which is why no earlier capture contains one). |
| **S5** | **the real-pointer check** (S4 state, no device emulator): arm a card, then **click a racer row with your actual mouse** | Injected clicks do not deliver Activate inside the list's scroll host, so this click is the only pointer-native proof available in Studio. Expect the source slot to stay empty until the card lands, the landed row to **wash toward the verdict hue and nothing else** (no outline, no marker, no blue — spec A22), and **exactly one** `play` on the server (`commands.play` in the dev report vs the server receipt). §2.4's verbs prove the same chain downstream of the activation edge. |
| **S6** | `select "celebration-burst"` → `step "burst"`, `step "struck"`, `step "showrunnerComplete"` | A dense pile-up against the single-slot celebration gate: omen → landed → three drama beats → dodge in one call. Toasts stack by priority; ticker entries hold ~3.5 s then age-fade; a host ribbon outranks a caption and the caption **defers** rather than overlapping; the caption band never prints across the chip band (OWN-D57); `struck` reaches the driver-side attribution slot. |
| **S7** | `select "omens"` → `step "omenHelp"`, `step "omenHinder"`, `step "omenBurst"` | A world billboard over the affected kart, dying with the kart and taking no input; the minimap omen agrees with the world. **The billboard ring, the map-dot ring and the gate pill's ring are the same 12-tick drawing** — that is ruling (a) and PSD-3 below. Watch whether the plate slides on banked corners (an open framework row, OWN-D33). |
| **S8** | `select "results-sponsor"` → `step "economy"`, `step "story"`; capture; then `step "storyBlocked"`; then `step "rollcall"` | **S16 v2, as approved.** The table is **gone**, not washed — nothing behind results paints text. Masthead = coin chip · "Next race in" · **Skip as mark + word** at ≥44 px. Under it the **drama recap spans the full width**. Then three lanes in landscape: LEFT = the promo pair (`Rhoda Rhino is on the grid` + `Hot Streak`) with the hero/celebration above them when present; MIDDLE = the **full finishing order** (whole grid, your row plated), scrolling; RIGHT = the two CTAs only. CTA labels name your **last** role — after a sponsored round, "Sponsor Again" (bright) and "Race". Portrait re-resolves the same declaration to one column. Watch the **coin beat**: the "+N" arrives featured, flies to the counter, and the counter counts up. `storyBlocked` shows the block line and no hero. `rollcall` moves the hold to the INTERMISSION reveal. On a **quiet** round the left lane must **collapse entirely** and give its width to the list (DV6-2). |
| **S9** | `select "results-racer"` → `step "economy"` | The racer read: placement slam. **Never captured on either build** — this is capture C2's other half. |
| **S10** | `select "large-roster"` → `step "publish"`, then `step "shrink"` | 16 roll-call rows (8 drivers + 8 sponsors, one carrying the reserved drop-in); scroll it, and check the focus stays visible as you navigate. `shrink` republishes 1+1 and **no ghost rows may survive**. Note: the list and map show only real karts — synthetic identities appear in the roll-call only. |
| **S11** | `select "asset-failure"` → `step "publish"`, `step "ghostOmen"`, `step "ghostStruck"` | Fallback `Racer`/`Sponsor` names with the initial-on-surface placeholder. A badge with **no** name is **hidden**, not a "?" plate. An unknown cast key renders without a silhouette and without breaking. |
| **S12** | `select "reduced-motion-live"` — **and turn reduced motion on in the client settings** | The rig only *stamps* the fixture; the axis is a client/device setting. With it on, information must survive: beats are substituted, never simply deleted (including the coin count-up, which lands instantly at its final value with a static "+N"). Without the client setting the row is unfiled — do not assume it. |
| **S13** | `select "churn"` → `step "flip6"` | Six real role flips. Afterwards the dev report's `core.signals/memos/observers/scopes` return to their pre-churn values, `surfaces.depth` is sane, `commands.dropped` is 0, and no surface lingers. |
| **S14** | `api.reset:Invoke()` then `api.release:Invoke()` | The round machine resumes; the fixture stops being asserted. |
| **S15** | **the paired legacy re-drive** | Stop Play. Clear `UseLuauUISponsor`. Play, arm the rig, run the **same** `select`/`step` sequence, capture at the same `report().stamp`. Both presentations see identical bytes; only one is ever mounted. |

**When you are done:** clear `UseLuauUISponsor`, clear `SponsorScenarioRig`, and set
`TrackLayout` back to `firstSmile`. That is the whole rollback.

### 2.4 The dev DRIVE surface — nine verbs (OWN-D52, your own addition)

`workspace.LuauUISponsorDevDrive` (Client VM; Studio-only, same gate as the report,
destroyed on teardown). Each call returns `{ ok, consumedBy, counters, sessionMode,
verdictKey }` as JSON, where `counters` is the **delta** over the presenter's own
report — so one call proves the whole downstream chain (session → verdict → commit →
flight → land → wash → command) rather than "something happened".

| Verb | Args | What it drives |
|---|---|---|
| `tapCard` | slot index (`> handSize` ⇒ the Showstopper) | the dock slot's own Activate closure |
| `tapRow` | kart key | the racer row's Activate closure — the tap-commit path |
| `watchDot` | kart key | the map dot's floored hit node |
| `togglePose` | — | the minimize dash, or the map canvas when minimized |
| `skip` | — | the results Skip affordance |
| `beginDrag` | slot index | `pointerDown` + a move past the promotion token |
| `dragTo` | kart key, **or** x, y | `pointerMove` on the live session |
| `drop` | — | `pointerUp` at the current pointer position |
| `cancel` | — | `PlayFlow:handleCancel` — the Cancel action's own verb |

**Every verb is a second CALLER of an existing path, never a second path.** The tap
verbs go through `adapter.driveActivate`, which invokes the *exact closure object*
the renderer registered for that node — the one `GuiButton.Activated` calls; the drag
verbs are the drag registry's own `pointerDown/Move/Up`. A verb that reached
`playFlow:onSlotActivate` directly would have passed happily through the whole of DB-4.

> **⚠ Evidence label: DOWNSTREAM-ACTION only.** These verbs prove everything *after*
> the engine's activation edge and **nothing before it** — they say nothing about the
> engine delivering a touch to an instance, which is exactly where DB-4 lived. Native
> routing stays a device question (§3.1 D1).

**Proven live end-to-end this session.** In a live Studio Play session on the LuauUI
build, `tapCard` → `tapRow` ran the full arm → commit → flight → land chain with the
counter deltas to match and **exactly one** `play` server receipt — the director's own
construction order (presenter built as a racer, sponsor seated afterwards), which is
the order that used to dispatch nothing. Session frame filed at
`rows/DEVDRIVE-landed-pill-badge.png`; it also shows the post-DV3/DV4 table live
(chips docked in the topbar, no resting row outlines, no rings, purple/gold faces).
**Read that frame honestly:** the gate pill is *not* resolvable at capture scale, so
it is not the badge evidence its filename promises — C1 and §3.1 D4 both stay open.

---

## 3. The device and FEEL checklist

### 3.1 Device pass 2 — the five re-checks owed from device round 1 (do these first)

All seven of your device-round-1 bugs are **fixed with tests and mutations** (§6b).
Five of them cannot be *closed* from here: native touch routing, the touch input
class, a moving image, and two questions of art at device scale. Each is one action
and one judgment, and each is the last thing standing between its fix and a closed row.

| # | Bug | Action | The one judgment |
|---|---|---|---|
| **D1** | **DB-4** — tap-commit (the crown bug) | On the phone, S4 state: arm a card, then tap a racer row. | Does **exactly one** card fly and land, and does the row's green verdict clear? (The fix is proved from the activation edge inward, in your own construction order; the engine's delivery of that tap is the half no harness here reaches.) |
| **D2** | **DB-3(b)** — no focus ring under touch | Play a whole minute with a finger only. Then plug a pad and press d-pad once. | **No blue outline anywhere** while you are using a finger — and the ring **returns** on that first d-pad press, on the node the finger left focus on. (`preferredInput = Touch` is not producible in the emulator, so this is the only proof.) |
| **D3** | **DB-7** — the drop motion | Watch a drop sequence at speed (record it if you can, as you did with `selection.mov`). | Does it read as **ONE wash** on the plate — no outline, no marker bar, no blue at any point in the transition? |
| **D4** | **DB-1** — the author badge at scale | S4 with a play landed: look at the gate pill on the row. | Does the played pill show the **author chip at its left cap** the way legacy's does — and does a `locked` pill show a lock and **no** chip? This is art at device scale, not geometry (the geometry is measured and pinned). |
| **D5** | **DB-2** — the FTUE dots at scale | Run the FTU flow on the device; scroll Flash out of the list and look again. | Do the dots run **card → Flash**, and do they **clamp to the list's edge** when Flash is scrolled away? |

### 3.2 The standing physical / FEEL rows

The irreducible rows. Each is **one action** and **one judgment** — nothing to set up
beyond §2. No emulator, screenshot, or headless result may close any of these
(contract §3: a row never passes through an easier row).

| # | Action | The one judgment |
|---|---|---|
| **H1** | Scenario S4/S5 on a **real pointer**: arm a card, click a racer row; then press-and-drag a card onto a row and release. | Does the commit feel *direct* — the ghost under the pointer 1:1, the land instant, the row's wash caused by your release? (Press→drag promotion still cannot be injected at all, so the drag half is only ever felt, never driven.) |
| **H2** | **Physical gamepad**, S1: press **B** on the role modal. Then in S2 press **Y** to toggle the pose, and the bumpers to cycle the watched racer. | Does B do **nothing** (the pick is mandatory — that is the intent), and do Y and the bumpers reach their verbs without stealing a driving binding? Studio cannot synthesize these buttons at all, so this is the only proof. |
| **H3** | **Physical touch phone**, S4: tap a card to arm, **swipe the list** while holding it, then tap a row. | Does the swipe scroll (never drop) and the tap place? A held card must not make the list unscrollable. Also: drag a held card to the list's edge — does the **autoscroll** arm after a beat, ramp, and give you a single haptic tick at the moment it starts? |
| **H4** | Same phone, S2, portrait **and** landscape: read the racer list and the map at arm's length while the race is actually running. | Can you name who is leading and who you are watching **at race speed**, without stopping? (Named criterion C9 — the one legacy's map tags fail.) |
| **H5** | S7 on the phone: watch an omen land. | Does the **12-tick ring** read as "about three left" at billboard scale — or does it read as a decoration? This is the pixel evidence for PSD-3 / UI-SPEC Q4. |
| **H6** | S8 then S9, **both roles**, **both orientations**, on the phone. | Does the results screen tell the round's story first and let you leave whenever you want? Is Skip obviously Skip? Does the coin beat feel like *earning* rather than a number changing? And on a **quiet** round, is the left column truly gone rather than an empty band? |
| **H7** | The **weakest supported device** (2 GB-class Android): S2 racing, then S6's burst, then a scroll of S10's roster. | Does it hold frame under the burst, and does the table stay responsive to touch while it does? |
| **H8** | Console / ten-foot, S2 and S8, from ~3 m. | Is the composition right at distance — density, focus ring visibility, hand reachability? (The type bump is measured; the composition is not.) |
| **H9** | **The verdict.** Any scenario, at race speed, both builds back to back (§2.3 S15). | Does this feel like Sponsor Mode — as good or better — or does it feel like a rebuild of Sponsor Mode? This is PS-G7 and it cannot be self-approved. |

---

## 4. Decisions — eleven resolved, twelve open

### 4.1 RESOLVED since this packet was first written — no action needed

Recorded here so nothing already ruled is put back in front of you.

| Was | Outcome | Where it is recorded |
|---|---|---|
| **The CoreGui player list** (old decision (b)) — disable it on the legacy side too? | **RULED GAME-WIDE and SHIPPED.** *"we should hide the roblox leaderboard thing in all modes."* One `StarterGui:SetCoreGuiEnabled(PlayerList, false)` at client startup (`src/client/init.client.luau:103`), outside the frozen modules, both presenters, both roles; the LuauUI-scoped seam was retired by the same change. Legacy's own Skip occlusion is fixed as a side effect. | `DECISIONS.md` 2026-07-31 · DV2-6 |
| **The results CTA copy** | **RULED, with two new localized strings** ("Sponsor Again", "Race"). Labels name your **last** role; emphasis still follows the selected one. Built, and the labels read the **server-confirmed** role so a pending pick cannot rewrite them mid-frame (DB-6 / OWN-D56). | `DECISIONS.md` 2026-07-31 · DV5-2 |
| **The redesigned finish screen** | **APPROVED** — *"I do think the new race finish screen is the best yet."* Ratifies S16 v2 (UI.Composition declaration, three-lane landscape, spanning recap, role-aware CTAs, coin-earning beat) as the `UI-SPEC` gate outcome for the surface. | `DECISIONS.md` 2026-07-31 · DV4-2 commissioned it |
| **Q1** — Cancel on the mandatory role modal | **CONFIRMED (a): no-op**, via the framework option `cancelPolicy = "none"` (six framework tests, six live keyboard checks). Rider only: H2 must prove B really does nothing on a physical pad. | round 1 ruling R4 |
| **Q3** — does list selection mean "watched"? | **CONFIRMED (a), paint amended twice.** Watched is now the `controlSelected` plate **level alone** — the accent ring was removed in round 2 and the leading marker bar in device round 1 (spec A22). | round 1 R4 + round 2 ruling (c) + DB-3(a) |
| **Split-axis keying** | **RULED (a): key on `sizeClass`**, recorded as an intentional difference, desktop-window only. Reversible in one memo if you judge a tall desktop window a real configuration. | round 1 ruling R1 |
| **The `disconnected` row state** | **RULED: KEEP**, on three conditions, all met — existing vocabulary with no new hue, at the GENERAL-INACTIVE rung, and it explains itself on attempt. | round 1 ruling R3 |
| **Q6** — full finishing order in the field? | **BUILT as recommended (a)**: the whole grid, capped at `MatchTuning.gridMax`, your row plated. Approved in effect by the finish-screen verdict; recorded as **PSD-5**. | spec §S16.14 · ledger PSD-5 |
| **Q7** — the recap as the field's caption? | **BUILT as recommended (a), then amended by your own DV5-1**: the recap **spans the full width** under the masthead. It still never scrolls and still captions the order beneath it. | spec §S16.14 · §S16.17 |
| **Q8** — RACE SPONSORS + rivalry callout out of the roll-call list? | **BUILT as recommended (a), amended twice by you**: DV5-1 moved RACE SPONSORS into the **field** group under the grid it names; DV6-2 moved the promo `Bait`/`Tease` pair into the **ceremony** (they are the two strings DV5-1 named for the left column). | spec §S16.14 · ledger PSD-5 |
| **Q9** — the `twoLane` gap | **CLOSED by construction.** `twoLane` shipped with the composition mechanism; a 667×375 landscape phone now resolves to it instead of falling back to `column`. | spec §S16.13 |

### 4.2 Still open — twelve, with recommendations

#### (a) The three remaining UI-SPEC §12 questions

| Q | Question | Options + cost | Built today (provisional) | Recommendation |
|---|---|---|---|---|
| **Q2** | The activity ticker's **compact form** on a portrait phone (the landscape rail eats ~⅔ of the width over the live race). | (a) a max-2-entry strip above the watched card; (b) hide the ticker in compact; (c) ship the rail as-is. | **(a)** — `tickerCompactMax = 2`, built and tested, flagged PROVISIONAL in `StoryTokens`. | **(a).** Reflow, never squeeze. Flagged because the ticker's existence is your own live ruling, and cutting it to two entries changes what that ruling is judging. Judge it in S2 minimized. |
| **Q4** | Does a **smooth countdown arc** replace the 12-tick ring everywhere? | (a) smooth arc everywhere; (b) keep the ticks; (c) arcs on large surfaces, ticks on small ones. | **(b)** — one 12-tick construction (`TickRing.luau`) serves the gate pill, the map-dot omen and the world billboard. | **(b).** The designer **withdrew** their own (a) recommendation on the pixels: a sponsor sees the gate ring and the omen ring within a second of each other, and two forms for one clock breaks one-meaning-per-channel; ticks also read as "three left" at ten foot where an arc reads as an unlabelled fraction. Ratify via PSD-3; **H5 is the evidence** and PSD-3 should not be ratified without it. |
| **Q5** | The pose materialize's **origin bias** — should the table grow from the minimap's corner? | (a) carry the shipped deferral (symmetric centre-origin); (b) implement the corner origin now that transitions are a framework mechanism. | **(a)** — symmetric centre-origin, as shipped. | **(a)** for the parity build, judged at the FEEL sitting alongside legacy. It is the one item the ratified motion spec explicitly left owed to you, and it cannot be judged from a screenshot. |

#### (b) The four tuning questions the audit queued

Source: `reviews/tuning-audit.md` §3. The audit swept 108 tuned values and rules
against the presenter's **code** (never against a round report): 80 matched, 20 beat
the baseline, 3 gaps were fixed the same round (the M9 tell's shared home, the
autoscroll coast, the autoscroll haptic — ledger OWN-D59…D61), and these four are the
gaps that need a ruling rather than a patch.

| Q | The gap | Options + cost | Recommendation |
|---|---|---|---|
| **TUNE-Q1** | **The M9 in-flight tell's rising RATE (blink) is not ported.** `CommitBeatModel` ramps a blink 1.15 → 2.4 Hz alongside the swell; the port ships the **swell** on both surfaces (row stroke + map ring, now from one home) and the rate on neither. `UI.Path` has no per-path transparency, so the map ring *cannot* carry it. | (a) accept as an intentional difference and log it; (b) blink the row only — a blinking row beside a steady ring, i.e. two readings of one clock; (c) build a per-path transparency channel in the framework so both can blink. | **(a), as PSD-7.** The port runs at frame rate where legacy sampled the blink on a 250 ms tier at ~2 Hz — one flip per tick — so the channel dropped is the coarsest one legacy had, and the smooth swell it keeps is the one the tuning notes call dominant. (c) is a real framework gap, but not this beat's to pay for. |
| **TUNE-Q2** | **The autoscroll CHEVRON affordance is not built.** §6 ratifies a neutral ▲/▼ pinned to the active edge (hidden at the canvas end, 40 % dwelling, 100 % + a 0.8 Hz pulse scrolling, 120 ms fade). It needs two things the framework lacks: an `atEnd` fact on the autoscroll signal (the honesty rule — no affordance for a scroll that cannot happen) and a looped-oscillation primitive (springs, chases, timers and timelines all settle). | (a) build both framework halves, then the chevron; (b) ship it without the pulse (state by opacity only); (c) drop it — §6's own first line allows "the moving list is itself the primary signal". | **(a)**, sized as one framework row: `atEnd` is five lines, and a bounded decorative oscillation is a primitive M21 will need anyway. Not done this round because it is a build item with a visible design surface, and it wants a device look. |
| **TUNE-Q3** | **M10, the gate-slot form-entry pop, is not built.** Spec §7 M10 ratifies a `reward` pop (0.2 s Back-out) as a gate slot's form appears, re-targeting from the current scale, with `play ⇄ cooldown` explicitly one identity that does not re-pop. The port's slots appear and disappear instantly. | (a) build it **record-driven**, exactly as M16's finish flag already is; (b) build it mount-driven on the region's enter transition; (c) leave it. | **(a)** — and (b) is a trap worth naming: this list is **virtual**, so a mount-driven pop fires on every row that scrolls into the window, which is a pop nobody caused. (a) also gets "does not re-pop across play→cooldown" for free. It needs a firing seam on the roster's gate-form edges that does not exist yet. |
| **TUNE-Q4** | **The race-view toast's ×1.4 scale is not expressed.** Your own ruling (`DECISIONS.md:588`, "bigger overlay text") scaled the toast layer ×1.4 in the race view. Half that ruling's cause is gone — legacy scaled it partly because the toast clipped inside the 110 px minimap, and the port's toasts are framework-scheduled at screen level in every pose. The other half — *too small to read over a live race* — is a readability judgment that never depended on the clipping. | (a) a compact/minimized-pose multiplier so the plate and its type grow in the follow pose; (b) grow it everywhere and drop the pose branch; (c) leave it — the plate is already legacy's 30/36 px box at a fixed 16 px type, the size you approved for the maximized pose. | **(b)** if the device round finds it small, else **(c)**. Flagged rather than built because "which pose deserves a bigger toast" is exactly the kind of call the last six visual rounds were made of, and it should be judged on a phone (**H4/H7**), not from arithmetic. |

#### (c) The legacy `ShowrunnerPillGui` objective pill — one legacy edit

**What you saw** (DV-8: *"i can't tell what the icon to the left of the lap indicator
is when watching"*) is the **legacy** objective pill's collapsed form — a 40 px square
with a countdown ring and a 7 px dot. It is a sibling ScreenGui that mounts for **both**
presenters, so it renders identically on both builds. **Correction, so you are not asked
to re-litigate a phantom control:** the new presenter has no restore button and never
had one; the map canvas is the restore target.

The proposal, in order:

1. **One legacy edit serving both presenters** — the collapsed form wears a
   self-evident objective mark and expands to a labelled chip whenever the chip row
   has room, so it never reads as an anonymous ring beside the lap chip.
   *Cost:* touching a frozen legacy module mid-stage (one sanctioned-change entry,
   and `ShowrunnerPillGui.luau` leaves the 11/11 freeze).
2. **Until then it is flagged on screen** in the dev build — `[LEGACY PILL — ruling
   pending]` — rather than suppressed under LuauUI only, which would make the
   comparison dishonest and leave the objective unrendered. **Already done** (PSD-4);
   it is the only on-screen provisional tag left in the build.
3. **At cutover** the full port retires the legacy pill and its countdown adopts the
   12-tick form from Q4/PSD-3.

**Decision requested:** approve step 1 now, or defer it to cutover and keep the tag.

#### (d) Governance — ratify three specs the shipped build contradicts (TUNE-Q5)

Not a code gap. Three ratified specs still say things the build deliberately does not
do, and in every case the port built the **code** behaviour, as spec §11 recommends.
What is owed is a retroactive ratification plus four dated amendments.

| Doc | What it still says | What ships | Amendment owed |
|---|---|---|---|
| `M12_UI_FIX_SPEC.md` | its status line reads **"UI-SPEC gate pending (director)"** | every item in it ships, and has for a mission | **Ratify as of its build date** (D-6) |
| `UI_SPEC_avatar_badges` §1.3 | promises a **fallback badge** where a nameless one appears | a badge with no name is **hidden**, not a "?" plate | **D-8** |
| `UI_SPEC_avatar_badges` §1.1 | enumerates **six** badge surfaces | **seven** ship (the activity-ticker entry badge) | **D-14** |
| `UI_SPEC_chaos_row_states` §5 | a fixed **2 Hz** pulse | M12 §5's rising ramp superseded it | **D-5** |
| `UI_SPEC_chaos_row_states` §1.1 | a **0.35** recede | `M12_UI_FIX_SPEC` Item 5a superseded it | **D-4** |

**Recommendation.** Ratify `M12_UI_FIX_SPEC` as of its build date, and let the tuning
audit's rows stand as the amendment text for D-4, D-5, D-8 and D-14. A spec that
contradicts a shipped build is a trap for the next reader, and this one has already
cost one round of "is this a defect or a difference?".

#### (e) Ratify the intentional-differences log

Places where the LuauUI build deliberately differs from legacy. Each has evidence and
a test; none is a defect.

**PSD-1…PSD-6 are recorded in `acceptance-ledger.md`** with their approval source:

| ID | The difference | Approved by |
|---|---|---|
| PSD-1 | **A sponsor's results show the final standings** under the drama recap (legacy shows a sponsor none at all). | designer round 2, N2 |
| PSD-2 | **The chip row takes the platform TOPBAR band when it fits, and a reserved band above the table when it does not** — legacy's negative-inset placement and its second-row reflow are not ported. | designer round 2 N3 + your DV3-1 |
| PSD-3 | **The omen ring is the 12-tick segmented ring**, not the smooth arc the spec originally ratified — one drawing shared with the gate pill and the map dot. | designer round 2, ruling (a) (explicit withdrawal of Q4) — **your ratification still owed, on H5** |
| PSD-4 | **The legacy objective pill is tagged on screen** in the dev build rather than suppressed. | designer round 2, ruling (b) step 2 — retires when you rule (c) |
| PSD-5 | **The results field lists the FULL finishing order**, and RACE SPONSORS / the promo pair are their own regions rather than rows inside the roll-call. | S16 v2 Q6+Q8, amended by DV5-1 and DV6-2 — approved in effect by the finish-screen verdict |
| PSD-6 | **A gate pill wears the §1.2 fallback badge** (the author's initial on a neutral-rimmed chip), not a Roblox headshot — identity *resolution* is an engine seam this port deliberately does not hold. | ui engineer, device round 1 — recorded for your D4 look |

**Proposed, and they land in the ledger on your word:**

| ID | The difference | Why it is better or equal |
|---|---|---|
| PSD-7 | **The M9 tell ships the swell and not the blink** (TUNE-Q1). | The port runs at frame rate where legacy sampled the blink at ~2 Hz; the dropped channel is the coarsest legacy had, and the map ring cannot carry it at all without a new framework channel. |
| PSD-8 | **The map/list split axis keys on `sizeClass`**, not on the panel's own aspect. | All five real device rows agree; the divergence is desktop-window-only. The alternative reads a *solved* rect back into a condition — the exact class that produced the detached-ring defect. Reversible in one memo. |
| PSD-9 | **A sponsor's hero line is a round-story line, and is absent when there is no story** — where legacy tells a parked sponsor "8th!". | The placement slam is the driver's read; a sponsor did not place. The hero condition and its copy read the same numbers as the recap under it, so the line can never contradict its own tally. |
| PSD-10 | **A ten-foot type bump**, with the plate inset well inside the frame. | Legacy's TV type is byte-identical to its desktop type — no ten-foot treatment at all — and legacy runs near-full-bleed where a TV overscans. This one *beats* the baseline. |
| PSD-11 | **A `disconnected` row state**, which legacy has no expression for. | Closes a real "no silent states" hole: a dropped racer's row otherwise reads ACTIVE and eats a card. Rendered in the existing vocabulary with **no new hue**, at the GENERAL-INACTIVE rung, and it explains itself on attempt. |

> **ID note.** The packet's earlier proposed PSD-5…PSD-8 were re-issued: the
> acceptance ledger took PSD-5 and PSD-6 for the S16 v2 field and the fallback badge
> on 2026-07-31, and the tuning audit named PSD-7 for the blink. The *content* of the
> four carried proposals is unchanged; only their numbers moved, to the ledger's next
> free ones.

#### (f) Two carried craft items

| Item | The gap | Options + cost | Recommendation |
|---|---|---|---|
| **OWN-D43** — no per-node font **weight** | The lap read is the right size now (pinned) but a lighter weight than legacy's bold. LuauUI's typography puts weight in a theme package's type roles, and RascalRally has no compiled package yet. | (1) carry it to the RascalRally theme package, which is already the named owner of these metric names; (2) add a per-node weight property to LuauUI now — a typography-system change with blast radius across every shipped screen and every package's contrast/pairing rules; (3) accept the lighter weight permanently. | **(1).** It is one label, and (2) mid-stage is how a type system rots. |
| **N10** — the Headwind mark's craft | Hue and family read are legacy's exactly; the silhouette is a notched polygon where legacy draws two clean crossed round-capped strokes with four knobs. Tailwind's graded bars already match. | (1) one art pass against the legacy style reference; (2) accept as-is. | **(1)** — it is craft against a reference, not a rule to decide. Cheap, and it is the last visible remnant of DV-2. |

*Carried but needing no decision unless you want otherwise:* the world billboard's
camera-relative offset (may slide on banked corners — H5/H7 will tell, fix is an
additive framework option, never a game-side property write); a proposed
per-node safe-area opt-out; and five cutover-scope deferrals where a legacy sibling
still serves both presenters.

---

## 5. Evidence index

### 5.1 Paired captures (legacy ↔ LuauUI), all under `artifacts/parallel-sponsor/`

| Surface / state | Legacy | LuauUI |
|---|---|---|
| Table max, phone portrait | `rows/PS-B3-legacy-max-iphone16-portrait.png` | `rows/DV3-verify-rows-no-rings-portrait.png` *(current)*; `rows/PS-T1-luauui-max-iphone16-portrait.png` *(round 1)* |
| Table max, phone landscape | `rows/PS-B3-legacy-max-iphone16-landscape.png` | `rows/DEVDRIVE-landed-pill-badge.png` *(current — post-DV3/DV4 live)*; `rows/DV3-verify-chips-topbar-iphone16-landscape.png` |
| Table max, tablet | `rows/PS-B3-legacy-max-ipad9-landscape.png` | `rows/PS-T1-luauui-max-ipad9-landscape.png` **— pre-restyle, C9 owed** |
| Table max, desktop 1080 | `rows/PS-B3-legacy-max-desktop1080.png` | `rows/PS-T1-luauui-max-desktop1080.png` **— pre-restyle, C9 owed** |
| Table max, TV 1080 | `rows/PS-B3-legacy-max-androidtv1080.png` | `rows/PS-T1-luauui-max-androidtv1080.png` **— pre-restyle, C9 owed** |
| Follow/min, phone portrait | `rows/PS-B3-legacy-min-iphone16-portrait.png` | `rows/PS-T1-luauui-min-iphone16-portrait.png` **— pre-restyle, C3 owed** |
| Follow/min, phone landscape | `rows/PS-B3-legacy-min-iphone16-landscape.png` | `rows/FIX-min-follow-rawpane.png` **— pre-restyle, C3 owed** |
| Armed card + aim | `rows/PS-C1-armed-hand-legacy-iphone16-landscape.png` | `rows/C4-armed-ghost-own-slot.png` *(restyled pose; no staged ghost, and predates DV4-1/DB-7 row chrome — C4 owed)* |
| Sponsor results, portrait | `rows/PS-R1-legacy-results-sponsor-iphone16-portrait.png` | `rows/S16v2-results-sponsor-iphone16-portrait.png`, `rows/DV5-results-sponsor-iphone16-portrait.png` |
| Sponsor results, landscape | `rows/PS-R1-legacy-results-sponsor-iphone16-landscape.png` | **`rows/DV6-results-columns-iphone16-landscape.png`** — the frame the finish-screen approval was given against; also `S16v2-*`, `DV5-*`, `DV3-verify-results-finishers-*` |
| Racer results, either orientation | **never captured** | **never captured** — capture C2 |
| Grace / start countdown | — | `rows/DV6-grace-chip-iphone16-landscape.png`, `rows/DV3-verify-countdown-iphone16-portrait.png` |
| Legacy styling authority (director-requested) | `reviews/legacy-style-reference/` (pill lifecycle t0/t2/t6, row band, map tag, finished row) | — |

Geometry/state companions: `baseline/studio/*.geometry.json` (legacy) and the
`LuauUISponsorDevReport` snapshots quoted in the row files below. Pictures are always
paired with facts; neither alone closes a row.

### 5.2 Evidence rows by ledger section

| Ledger section | Live evidence file |
|---|---|
| PS-B (baseline freeze) | `baseline/baseline.md`, `baseline/legacy-checksums.txt`, `baseline/studio/PS-B4-input-trace-legacy.md` |
| PS-L (entry, role, lifecycle) | `rows/PS-L1-L6-entry-lifecycle-live.md`, `rows/PS-L6-selector-live-proof.md` |
| PS-T (table, list, map, poses) | `rows/PS-T-table-list-live.md`; current chrome in `rows/DV3-verify-*` + `rows/DEVDRIVE-landed-pill-badge.png` |
| PS-C (cards and input) | `rows/PS-C-cards-live.md`; the drive-verb chain (§2.4) and its counter deltas |
| PS-H / PS-W / PS-R (story, omens, results) | `reviews/round2.md` §1–2, the fix-round-3 dispositions and the DV/device dispositions in `responsibility-ledger.md`; captures `rows/DV*-*`, `rows/S16v2-*`, `rows/C2-*` |
| Tuned values (108 rows vs FEEL / DECISIONS / lessons / M11–M12 / the four UI specs) | `reviews/tuning-audit.md` |
| Ownership (framework vs game) | `responsibility-ledger.md` — 10 standing rows + 61 discovered rows (**OWN-D1…OWN-D61**), each naming the public API, tests, and disposition that closed it |
| Reviews | `reviews/round1.md`, `round2.md`, `director-visual-round-{1..6}.md`, `director-device-round-1.md`, `tuning-audit.md`, `results-ground-truth.md` |
| Index | `rows/REVIEW-PAIRS.md` |

### 5.3 OUTSTANDING captures — **collected during the sitting, or on the next automated pass**

Stated plainly rather than hidden: these are the frames still missing. None of them is
a claim; each is a gap.

| # | Capture | Closes | State today |
|---|---|---|---|
| **C1** | **Gate pill close-up**, live, both phone orientations, list scrolled | F1 (ring clipping), F3 (pill anatomy), A6, PSD-3's pill-side evidence, and D4's geometry half | **Outstanding.** DB-1 made the `play`/`cooldown` forms *reachable* (they could not occur at all before), and the anatomy is measured and pinned — but no capture **resolves** a pill. `rows/DEVDRIVE-landed-pill-badge.png` was filed for this and does not deliver it at capture scale. Drive S4 and crop. |
| **C2** | **Results, both roles × both orientations**, non-zero recap, real round story | PS-R1/R3 Studio rows; N1/N2/N5/N6/N7 verification; the S16 v2 device matrix | **Sponsor role COLLECTED, both orientations, on S16 v2** (`rows/S16v2-*`, `rows/DV5-*`, `rows/DV6-results-columns-*`). **Racer-role results have never been captured on either build.** Drive S9. |
| **C3** | **Minimized pose post-restyle**, portrait + landscape | A1/A2/F5, the chevron floor, and DV-8's context for decision (c) | **Outstanding.** Both existing follow-pose frames predate the restyle. Drive S3. |
| **C4** | **Armed hand post-restyle** — ghost with a face at the staging spot above its own slot, source slot emptied, plus a held-blocked slash on ≥2 rows and a finished+watched row in one frame | F1b/F9/F10/N13, the held-row matrix, the rest of DV-2's faces | **Partly collected, with a caveat worth reading:** `rows/C4-armed-ghost-own-slot.png` carries a **full dock and no staged ghost**, so the ghost half is not proven by it — and it now also predates DV4-1 (resting hairline retired) and DB-7/DB-3(a) (verdict ring and marker bar retired), so its row chrome is stale too. Drive S4/S5. |
| **C5** | **Toast burst** — help / hinder / blocked plates, held past the 2.5 s floor | DV-6 (the only director visual finding with zero pixel evidence) | **Outstanding.** Drive S4 + S6. |
| **C6** | **Omen billboard + minimap omen in one frame** | PS-W1/W2 and PSD-3's world-side proof that all three rings are one drawing | **Outstanding.** Drive S7. |
| **C7** | Ticker + caption + host ribbon co-resident | S10/S11 priority, Q2's compact strip, and OWN-D57's caption/chip-band separation in pixels | **Outstanding.** Drive S6. |
| **C8** | Grace phase: the chip row's flag+countdown form, and the start countdown, both poses | PS-H1/H2, DV6-1, DV3-5 | **Partly collected.** `rows/DV6-grace-chip-iphone16-landscape.png` (grace chip on legacy's own metrics, landscape) and `rows/DV3-verify-countdown-iphone16-portrait.png` (the start countdown back inside the viewport). **Owed:** the grace chip in **portrait**, a **two-digit** countdown (t ≥ 10 s), and both poses. |
| **C9** | Tablet / desktop / TV post-restyle, state-matched with their legacy twins | The remaining half of the evidence-integrity finding; the only way to judge the row chrome and the chip row at ten foot | **Outstanding.** The three existing LuauUI frames predate every restyle round. |
| **C10** | A rejected play on one frame: origin-slot flash + refill + one keyed toast | The server-rejection revert ruling's two conditions (R5) | **Outstanding.** Drive S4. |
| **C11** | Mid-race map with the field **spread**, not the start-line bunch | DV-3's readability-at-speed proof | **Outstanding.** Capture mid-race under `racing`. |
| **C12** | Greyscale re-shot of the restyled row matrix | Proof that identity survives without hue | **Outstanding — and its premise changed.** DV4-1 removed the resting identity hairline entirely, so identity now rests on the **swatch** alone. The greyscale shot must prove *that*, not the hairline. |
| **C13** | The results **collapse** cases: a quiet sponsor round in landscape with **no left column at all**; and a skip mid-tail that leaves the slot up | DV6-2's own confirmation list (items 2 and 5); OWN-D48's empty-lane release in pixels | **Outstanding.** `rows/DV6-results-columns-*` proves the *populated* left column (item 3); the collapsed case has not been shot. |

---

## 6. Pending rows — every `PENDING_PHYSICAL` / `PENDING_HUMAN`, with its closing procedure

**Seventeen rows: five device re-checks from round 1, twelve standing.**

### 6.1 The device round-1 re-checks (the §3.1 list, as rows)

| Row | Kind | Why it cannot close here | Exact closing procedure |
|---|---|---|---|
| **DB-4** | PENDING_PHYSICAL | Native touch routing is the half no harness here reaches. The fix is proved from the activation edge inward (framework `presenter.refresh()`, 5 LuauUI cases + the game's own construction-order case, 7 mutation failures) and by the live drive chain — neither is the engine delivering a touch to an instance | §3.1 **D1** on the phone: with a card armed, tap a racer — exactly ONE card flies and lands, and the row's green clears. Record device, OS, build. |
| **DB-3(b)** | PENDING_PHYSICAL | `preferredInput = Touch` is not producible in the Studio emulator | §3.1 **D2**: no blue outline anywhere during a finger-only minute; the ring returns on the first d-pad press. |
| **DB-7** | PENDING_PHYSICAL | The whole complaint is a moving image | §3.1 **D3**: the drop sequence reads as ONE wash — no outline, no marker, no blue, at any point. A recording closes it as well as an eye. |
| **DB-1** | PENDING_PHYSICAL | Badge **art** at device scale (the geometry is measured and pinned) | §3.1 **D4**, and capture **C1** files the frame. |
| **DB-2** | PENDING_PHYSICAL | The FTU flow on a real device, including the scrolled-away target | §3.1 **D5**: dots run card → Flash and clamp to the list's edge when Flash is windowed out. |

### 6.2 The standing rows

| Row | Kind | Why it cannot close here | Exact closing procedure |
|---|---|---|---|
| **PS-G4** | PENDING_PHYSICAL | Real touch feel and OS delivery; the emulator produces neither | Retail/Studio-streamed build on a physical phone, portrait **and** landscape: run §2.3 S2–S5, checklist **H3** + **H4**. Record device, OS, and build. |
| **PS-G5** | PENDING_PHYSICAL | Studio cannot synthesize a gamepad input class; `VirtualInput` refuses `ButtonB` and drops `ButtonY` | Physical pad, §2.3 S1 → checklist **H2**: B on the modal (must no-op), Y (pose), bumpers (watch cycle), A to arm and commit across rows with blocked rows skipped. |
| **PS-G6 + PS-P3** | PENDING_PHYSICAL | Studio frame numbers are regression evidence, never device evidence | Weakest supported device (2 GB-class Android): checklist **H7** with the frame-time overlay/MicroProfiler during S2, S6's burst and an S10 scroll. Record the numbers against the game's device budget. |
| **PS-G7** | PENDING_HUMAN | "Feels like Sponsor Mode" cannot be self-approved by the implementing agent | Checklist **H9**: both builds back to back on the same scenario via §2.3 S15, at race speed. Verdict recorded here. |
| **PS-L2** (gamepad half) | PENDING_PHYSICAL | The mandatory-modal Cancel no-op is proven headlessly (6 tests) and cannot be driven in Studio | Folded into **H2**. Also confirm an outside-tap does not resign the modal (arbitrary-point taps are not injectable either). |
| **PS-L4** (touch/gamepad half) | PENDING_PHYSICAL | Responder ownership under real touch and pad; engine selection stays nil on this presentation by rule | On the phone and the pad: with the table engaged, confirm gameplay input is not stolen, and with it passive, confirm the HUD eats no taps. |
| **PS-C1/C2/C3, PS-T4** | PENDING_PHYSICAL (in part) | Press→drag promotion cannot be injected at all; injected clicks do not reach buttons inside the list's scroll host | **H1** settles the pointer tap-commit with one real click in Studio, and §2.4's verbs prove the same chain downstream of the activation edge. Drag feel, fly-home, velocity handoff, the rejection toast and drag-edge autoscroll (incl. its one haptic tick, OWN-D61) need the phone (**H3**) — capture C10 files the rejection frame. |
| **PS-C4/C5** | PENDING_PHYSICAL | Per-scheme verb coverage and hybrid mid-session switches | On the phone and the pad: exercise every verb (arm, aim, commit, cancel, pose, watch-cycle, skip) on each scheme, then switch input class mid-session and confirm no verb is duplicated or orphaned. |
| **PS-I3** (occlusion/preferred-text half) | PENDING_PHYSICAL | The device emulator never summons the real mobile OS keyboard, and preferred text size is read-only in Studio | On the phone with the OS text-size setting raised: confirm nothing clips and the layout reflows rather than squeezes; confirm no field is left under the keyboard. |
| **PS-W1** (plate stability) | PENDING_PHYSICAL | The world billboard's offset is camera-relative where legacy's is world-space | During **H5/H7**, watch the omen plate through a banked corner. If it slides, the fix is an additive framework option — never a game-side property write. |
| **UI-SPEC Q5** | PENDING_HUMAN | A motion origin cannot be judged from a screenshot | During **H9**: toggle the pose repeatedly on both builds and say whether the table should grow from the minimap's corner or stay centre-origin. |
| **PSD-3 readability** | PENDING_HUMAN | Tick legibility at billboard scale and at ten foot | Checklist **H5** (phone) and **H8** (ten foot). Ratifying PSD-3 / Q4 without this is ratifying a drawing you have not read at size. |

**Also still OPEN, but not yours:** `PS-G3` (fresh-context phase-gate verification of
the acceptance ledger against the raw artifacts) and `PS-B5` (shared-model
characterization pins). Both are agent-closable and are scheduled before cutover, not
before your sitting.

---

## 6b. Director DEVICE round 1 (2026-07-31) — disposition

Source: `reviews/director-device-round-1.md`. All seven bugs and the observation are
**FIXED, with tests and mutations** (ledger rows OWN-D49…OWN-D58; suites at that
round's close: game 2801 → 2818, LuauUI 2743 → 2752, both green, stylua clean, 11/11
legacy checksums unchanged). **Five need your device to close — they are §3.1.**

| # | Cause (one line) | Where the fix lives |
|---|---|---|
| DB-4 | The presenter's input auto-wiring was a **one-shot walk at `present()`**, and the whole Sponsor HUD is inside a `When` that is CLOSED at construction (the presenter is built at client startup, as a racer) — so the racer list never contributed `handleActivate` at all. Focus still moved on a tap (hence the green verdict); nothing dispatched | FRAMEWORK — `presenter.refresh()` re-discovers contributions; `focus_graph.replaceGroups` accepts a flat→grouped upgrade |
| DB-5 | The session outlived the round, and the hand's DIFF carry + the optimistic gap crossed the boundary with it | GAME — `PlayFlow:endRound()` on the racing edge; the model drops its carry on `RoundGen` |
| DB-6 | The CTAs read the LIVE role while every other band read the latched one | GAME — `ResultsScreen.latchedRole` |
| DB-1 | The `play`/`cooldown` FORMS were unreachable (`gateSlots(..., nil)`), so no pill could ever have an author | GAME — the model retains + reaps play records; the list renders legacy's badge anatomy |
| DB-2 | OWN-D22's owed target fact, plus the port's own edge case (a virtual list unmounts an off-window target entirely) | GAME — `Roster.ftueRole` → `Row.ftueRole` → `StoryFlow._armPullLine` + the band clamp |
| DB-3(a) | Amendment A3's leading marker bar read as a stray stripe | GAME — retired; watched is the plate level alone (spec A22) |
| DB-3(b) | There was no input-class ring suppression to fail | FRAMEWORK — `focus_graph.focusVisible` + `setFocusPath(path, visible)` |
| DB-3(c) | The refill gauge wore the THEME accent and sat in the face's flow | GAME — legacy's gold bottom-edge bar |
| DB-7 | The verdict owned a 5 px ring as well as the wash; with the focus ring and the marker beside it, three rings meant three things | GAME + the DB-3(b) half — the wash is the whole verdict (spec A22) |
| (obs) | The caption band never took the chip band's reserve | GAME — the same `poseTopInset` margin the poses use |

**The headless-driver honesty fix (OWN-D51).** `adapter.tap` was one call with invented
meta; `adapter.touchTap(path, pos?, meta?)` now drives the REAL order — `InputBegan`,
`InputEnded`, then `Activated` with `{ source = "pointer", pointer = "touch", x, y }` —
and the DB-3(b)/DB-4 rows are driven through it. A node with no pointer handlers gets
nothing from the first two, which is the truth for a plain Button and is the point: the
order is modelled, not assumed away.

**The dev DRIVE surface (OWN-D52, your addition)** is documented in **§2.4**, with its
verb table and its evidence label.

---

## 7. Rollback / exit

Stop Play. Clear `workspace.UseLuauUISponsor` and `workspace.SponsorScenarioRig`; set
`workspace.TrackLayout` back to `firstSmile`. The legacy presenter is the default in
every production configuration, the eleven legacy modules are byte-identical to the
freeze, and with the flag unset the LuauUI namespace is never even required. Nothing
in this stage ships to players.

The one exception, deliberately shipped to **both** builds on your explicit ruling: the
Roblox player list is hidden game-wide (§4.1).

**This packet is a recommendation and an evidence bundle. It is not a default flip.**
