# UI Designer — integrated review, ROUND 2 (parallel Sponsor on LuauUI, POST-RESTYLE)

**Date** 2026-07-30 · **Scope** round-1 F1–F11 + director DV-1–DV-8 verification; new layers L4/L5/L6.
**Method** every capture named in the dispatch read as pixels, plus 2–6× crops and numeric sampling
(row strokes, plate levels, text max-luminance, scrim factor, dock hues, type extents, foreground-band
scan); where a verdict rests on a number the number is quoted. **Files I could not read:** none.
**Extra files opened:** `PS-B3-legacy-max-iphone16-portrait/landscape.png`, `FIX-max-rawpane-racing.png`,
`legacy-pill-t0-land/-t6-cooldown/-locked`. **Limits not re-litigated:** injected clicks inside the
list's scroll host; live toasts/drag/commit; physical touch + pad.

## 1. Verification table

**Legend** FIXED = proved in post-restyle pixels · FIXED\* = proved only in a PRE-restyle capture
(`FIX-*-rawpane.png`, red/blue hues + smooth dial), post-restyle re-shot owed · NV = not verifiable
from current captures · **BROKEN** = still wrong, evidence given.

| # | Verdict | Evidence |
|---|---|---|
| F1 detached gate ring | **NV** | No gate pill/ring appears in ANY post-restyle capture (no play staged, no shield write, list never scrolled). OWN-D26's framework clip + spec exist; the pixels do not. Needs capture **C1**. |
| F1b faceless armed ghost | **FIXED\*** | `FIX-armed-ghost-face-rawpane.png`: the staged card paints icon + "Headwind" label, source slot emptied. Re-shoot post-restyle (**C4**) — the card faces changed under it. |
| F2 selection overrides recede | **FIXED** | `DV-verify-max-iphone16-landscape` (all-finished fixture): watched Wrenchy name max-lum `(159,165,181)` **=** unwatched Flash `(159,165,181)`; both swatches muted (`64,74,150` / `172,121,76`) vs the racing fixture's `(43,60,192)` / `(240,146,67)`. The recede now composes over watched. |
| F3 locked pill = toggle switch, two hues | **NV** | Same as F1: no pill on screen. Ledger records the legacy anatomy (44/22 px, 0.4 outline, 12-tick ring). Needs **C1**. |
| F3b card faces greyless | **FIXED** | Dock in both `DV-verify-max-*`: Headwind `(145,121,214)` = `HINDER_ICON_COLOR rgb(150,120,220)`, Tailwind `(247,207,110)` = `HELP_ICON_COLOR rgb(255,205,90)`. Help vs hinder is a one-glance read. |
| F4 watched = accent stroke ring | **BROKEN** | See ruling (c). Watched stroke `(57,97,203)` at 2 logical px is **byte-identical** to the dock card's ring in the same frame; the `controlSelected` plate lift is `(25,27,34)` vs `(24,26,32)` = **+1/255** in the racing fixture. The reserved channel still carries the meaning. |
| F5 minimap has no plate | **FIXED\*** | `FIX-min-follow-rawpane.png`: real dark rounded plate, inset top-right, trace + dots inside it. Needs **C3**. |
| F6 evidence integrity | **FIXED** (rider) | Phone pairs carry the dock live; the landscape pair is state-matched (both all-finished). Rider: tablet / desktop / TV were **not** re-shot and the tablet pair is still legacy-racing vs LuauUI-finished (**C9**). |
| F7 watched card 2nd read | **BROKEN** (half) | Centring + name size fixed (`FIX-min-follow-rawpane`, name 52 px tall, centred between the arrows). The **cycle glyphs are 8 px tall** in a ~90 px target box — A2's "resolve at `label`" floor is not met; round 1 measured ~10 px, so this is unchanged. |
| F8 §7 M5 vs §11 D-2 | **FIXED** | Spec A4 landed; OWN-D27 added `armStaging` framework-side. |
| F9 ghost parks on the aim row | **FIXED\*** | Ghost sits above the dock, not on a row. See **N13**: legacy stages above the *source slot*, which is the better spot. |
| F10 dock alignment + emptied radius | **FIXED\*** | Dock centred (cards 673–1075 in a 20–1710 panel); the emptied slot keeps `radii.control`. |
| F11 dev banner occludes SizeToggle | **FIXED** | Banner is bottom-left in all four DV captures; the `–` toggle is clear. |
| DV-1 purple/gold restored | **FIXED** | Exact constants, measured above (F3b). |
| DV-2 card icon quality | **FIXED** (rider) | Silhouettes and hues are legacy's family pair. Rider **N10** (craft) and: the third face visible in the results frames is a gold ring + grey dash and reads as unfinished — the rest of the hand is unjudged (**C4**). |
| DV-3 map name tags | **FIXED** (rider) | Tags are now dark pills with bold white text at both orientations — legacy's form. Rider: every capture is a start-line bunch where the pills pile into a blob (legacy does the same), so *readability at race speed* is still unproven (**C11**). |
| DV-4 race-drama dial | **FIXED** (rider) | Nine tangential dashes + 3 px needle + hub in the zone hues, matching `legacy-dial` geometry. Riders **N9** (no lit zone) and **N3** (placement). |
| DV-5 racer-list row chrome | **FIXED** | Flat plates with a 1 px identity-hue hairline (Flash top edge `(100,74,51)`, Bruno `(63,53,48)`, Toby `(69,76,58)`, Bolt `(103,93,103)`), no `raised` chrome, legacy's proportions. Supersedes round 1's praise of outlined plates: I accept the overrule — the hairline version keeps the tablet/TV separation benefit without the outline look. |
| DV-6 toast composition | **NV** | No toast in any capture (**C5**). |
| DV-7 lap chip type | **FIXED** (rider) | "Lap 1/3" glyph run 53 raster px vs legacy's 58 in the identical portrait frame (~91 %); rider **N11** (weight). |
| DV-8 unreadable icon left of the lap chip | **NV** | Correctly traced to `ShowrunnerPillGui`'s collapsed pill (OWN-D18) — a legacy sibling. The only capture that contains it is the PRE-restyle `FIX-min-follow-rawpane`, where it is still an illegible 40 px blob. Needs **C3**, and see ruling (b). |

**Tallies — round 1 (13 labels): 9 FIXED · 2 NV · 2 BROKEN. Director DV (8): 6 FIXED · 2 NV · 0 BROKEN.**

## 2. New-layer findings (ranked)

**N1 — BLOCKER · game-composition · `DV-verify-results-sponsor-iphone16-{landscape,portrait}`**
The results overlay leaves the **whole table mounted and legible** under a ~50 % wash (sky
`157,197,218`→`74,96,111`; row name `159`→`82`). The hero line lands on the map's name pills (portrait
reads "0 a̶recoveries" where a tag overprints the recap) and the rows, chip row, dial and dock all
compete. Legacy's bar is not a stronger wash — legacy **tears the table down** (`PS-R1-legacy-*`:
scrim over the live scene, nothing else). The weak wash is the symptom; the defect is a surface with no
verb left still on screen. **Fix:** hide the table layer for the results phase (legacy-faithful) or
make the results backdrop opaque — either way nothing behind results may paint text.

**N2 — BLOCKER · game-composition · both results captures**
The **StandingsBand renders nothing.** Foreground scan (lum > 190) finds bands only at the header
(bank chip + "Next race in"), hero, recap and the CTA row — **zero foreground pixels between the recap
and the CTAs** in either orientation. §S16's 2nd read is absent; what looks like standings is the table
bleeding through N1. PS-R1/R3 pass headless, so this is a live-path gap. **Fix:** the standings are the
results surface's own content — and it is exactly where we beat the bar, since legacy shows a sponsor
no standings at all.

**N3 — MAJOR · game-composition · `DV-verify-max-*` (both)**
**The L4 chip row paints over L2.** Portrait: the Lap and Drama chips sit *on* the map, over the track
loop. Landscape: the Drama chip covers the P1 row's swatch **and name** — only the flag and "P1"
survive, so the leader is unidentifiable. §S8's contract is "centred in the band right of the platform
cluster, sharing one midline with it"; legacy puts both chips in the band **above** the panel
(`PS-B3-legacy-max-iphone16-portrait`) and shows no chip row at all in landscape. Note the irony:
OWN-D29 freed that corner by disabling the CoreGui list and the drama chip moved into it. **Fix:** the
chip row is a top-band layer with reserved space; when the band cannot hold it take §S8's own
`ViewThatFits` fallback (a second row *below* the top bar) — never over the table.

**N4 — MAJOR · results landscape** — "Next race in: 0" and the "Race Drama:" chip **overprint each
other**, glyph on glyph. Same root as N1+N3. **Fix:** the results header owns its band exclusively and
the race chip row is absent in results (§S9's absent-in-grace/results rule applies to all race chrome).

**N5 — MAJOR · content · both results captures**
The hero line is **not derived from the numbers under it**: "You turned Furry Flash's race around"
sits above "0 passes created · 0 recoveries sparked · Drama Score 0". The acceptance ledger's own PS-R1
rule is "a sponsor with no signature moment gets **no** hero band". Either the fixture injects a
roundStory the counters contradict (then this is not evidence of the shipping path) or the predicate is
wrong. **Fix:** hero condition *and* copy read the same facts as the recap; all-zero ⇒ no hero band and
the recap becomes the 1st read.

**N6 — MAJOR · C1 · both results captures** — **CTA emphasis is inverted for the sponsor role.** LuauUI
paints "Race Again" as the accent-filled primary `(57,97,203)` and "Sponsor a Race" grey; legacy paints
**"Sponsor a Race"** bright with "Race Again" muted. The mode's own verb should carry the primary. The
CTA row also overlaps the still-mounted dock and the dev banner (N1).

**N7 — MAJOR · C7/C3 · results top-right** — the **Skip control is an unlabelled two-square glyph** (6×
crop: two skewed diamonds). It reads as nothing; legacy shows the word "Skip" and §4.5 says skip is
never condensed. **Fix:** icon **plus** word at every size, or a self-evident ⏭ mark at target size.

**N8 — MAJOR** — carried, not new: F4 (ruling (c)).
**N9 — MINOR · portrait chip vs `legacy-dial`** — legacy lights **the zone the needle sits in** at full
saturation `(216,96,72)` and mutes the rest; LuauUI spends that value on the **hub** and leaves the
needle's own dash the darkest element in the arc, so "where is it pointing" rests on the needle alone.
**Fix:** apply `SponsorGui:1307`'s lit/unlit split to the segment under the needle.

**N10 — MINOR** — the Headwind mark is a notched polygonal blob where legacy's is two clean crossed
round-capped strokes with four knobs (equal-scale crops). Hue and family read are right, craft is
coarser; Tailwind's graded bars match.

**N11 — MINOR** — the lap read is ~9 % shorter than legacy's and a **lighter weight** (legacy's is
bold): DV-7's size half is met, the weight half is not.

**N12 — MINOR** — the minimize glyph is a thin low-contrast dash in a large plate; legacy's is a heavy
white bar. Same class as DV-8, on our own control.

**N13 — MINOR** — the armed ghost stages above the **dock centre**; legacy stages it directly above
**its own slot** (`PS-C1-armed-hand-legacy-iphone16-landscape`), keeping the source↔ghost read and
giving the fly-home an obvious origin. Recommend amending A4 to "above the source slot".

**Unjudgeable from the current set** (each maps to a capture in §4): gate pill in every form incl. the
12-tick ring and F1's clipping → **C1**; toasts → **C5**; omen billboard + ring and map agreement →
**C6**; ticker / captions / host ribbon priority → **C7**; grace chip form, start countdown, S9 chip →
**C8**; minimized pose post-restyle → **C3**; held-card row matrix → **C4**; racer-role results →
**C2**; tablet / desktop / TV → **C9**.

## 3. Rulings

**(a) ONE TIMER FORM — the segmented ring wins everywhere a duration depletes; the dial keeps its own
form because it is not a timer.** The pixels settle it: legacy's gate countdown *is* the 12-tick radial
ring (`SponsorWidgetKit:886-892` — visible as the gold "spark" eroding from many rays at t2 to a
two-tick fragment at t6, `legacy-pill-t2-ring-pillband` vs `-t6-cooldown-pillband`), while the drama
dial is nine **tangential** dashes on a half-arc with a needle and hub. Legacy already separates the
two by meaning. **Ruling:** *time remaining* is ALWAYS ticks around a full circle — gate pill, omen
ring, and S9's collapsed pill when it ports. *A zoned scalar* is dashes along a half-arc **with a
needle and hub**, never anything else; needle+hub is the discriminator that stops a third widget
drifting between them. I therefore **withdraw my Q4 smooth-arc ruling**: a sponsor sees the gate ring
and the omen ring within a second of each other on the same play, and two forms for one clock is the
split brain invariant 4 forbids. Ticks also read as "three left" at billboard scale and at ten foot
where a smooth arc reads as an unlabelled fraction. **Amendment A7:** §S14's `UI.Path OmenRing` becomes
the tick recipe; §4.2 states the discriminator.

**(b) The legacy `ShowrunnerPillGui` collapsed objective pill (OWN-D18 / DV-8) — take ONE thing to the
director, and do not hide it under LuauUI only.** Suppressing it for the new presenter would make the
comparison dishonest and leave the objective unrendered. Packet recommendation, in order: **(1)** ask
for one legacy edit serving both presenters — the collapsed form wears a self-evident glyph (a
target/objective mark) and expands to a labelled chip whenever the chip row has room, so it never reads
as an anonymous ring beside the lap chip; **(2)** until then flag it **on screen** in the dev build
(the DV-1 process lesson); **(3)** at cutover the S9 port retires it and its countdown adopts (a)'s
tick form. Carry the DV-8 correction verbatim — the presenter has no restore button and never had one,
the map canvas is the restore target — so the director is not asked to re-litigate a phantom control.

**(c) The restyled watched row DOES recreate F4, and the numbers say why.** The treatment should be
`controlSelected` plate + leading marker; measured, the plate lift is **+1/255** in the racing fixture
(`25,27,34` vs `24,26,32`) — invisible — while the row wears a **2 px accent stroke `(57,97,203)`,
byte-identical to the dock card's ring in the same frame** (`DV-verify-max-iphone16-landscape` shows
both at once). The channel that should carry "watched" does nothing; the channel reserved for focus and
the drop verdict does all the work. It only reads in the all-finished fixture because the receded plate
drops to `(16,17,23)` and the lift becomes +9. **Required:** (i) the plate lift is a real level — that
+9 is the floor, measured against the resting plate **in the same fixture**; (ii) the watched row drops
to the same 1 px identity-hue hairline every other row wears; (iii) the leading marker stays and
becomes the primary cue — a *form*, greyscale-safe, unconfusable with a ring; (iv) the accent stroke is
reserved for focus and the drop verdict, nothing else. With every row stroked at rest the verdict
stroke must also separate by weight: legacy's 5 px @ α0 against a 1 px @ 0.7–0.85 resting hairline
(OWN-D40) is 5:1 and acceptable — assert it.

## 4. Remaining work before the director's formal sitting (ranked)

1. **C1 — gate pill live, both phone orientations, list scrolled.** Closes F1, F3, A6 and gives ruling
   (a) its evidence: two open findings and a ruling on one capture.
2. **C2 — results re-shot after N1/N2/N5/N6/N7 land**, sponsor **and racer** roles × both orientations,
   non-zero recap and a real roundStory. Racer-role results have never been captured on either build.
3. **C3 — minimized pose post-restyle**, portrait + landscape. Closes A1/A2/F5, the F7 chevron floor,
   and puts DV-8 in context for ruling (b).
4. **C4 — armed hand post-restyle**: ghost with face at the staging spot, emptied slot, plus
   RELATIVE-INACTIVE + held-blocked slash on ≥2 rows and a finished+watched row in the same frame.
   Re-proves F1b/F9/F10 on the shipping build; closes the §4.1 held matrix and the rest of DV-2's faces.
5. **C5 — toast burst** (help / hinder / blocked plates, held past the 2.5 s floor). DV-6 is the only
   director finding with zero evidence.
6. **C6 — omen billboard + minimap omen in one frame** (PS-W1/W2); also ruling (a)'s world-side proof.
7. **C7 — ticker + caption + host ribbon co-resident** (S10/S11 priority, Q2 compact strip).
8. **C8 — grace phase**: the chip row's flag+countdown form and the start countdown, both poses.
9. **C9 — tablet / desktop / TV post-restyle, state-matched with their legacy twins.** Closes F6's
   remaining half; the only way to judge DV-5 and the chip-row reflow at ten foot.
10. **C10 — rejected play frame**: origin-slot flash + refill + one keyed toast on one frame (R5).
11. **C11 — mid-race map** (field spread, not the start-line bunch): DV-3's readability-at-speed proof.
12. **C12 — greyscale re-shot of the restyled row matrix**: the new identity hairlines must not have
    become a colour-only channel; round 1's greyscale win has to survive DV-5.
