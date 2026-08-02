# sponsor-framework-gaps — physical & human review packet

**Date:** 2026-07-27, revised 2026-07-28 after the director's first SFH pass · **Stage:** roadmap Step 5 · **Status of everything automatable:** complete (see `acceptance-ledger.md`; suite 2542, gate `tools/gate.sh sponsor-framework-gaps`).

**2026-07-28 fix round (director findings):** drag ghost now CENTERED under the
pointer with a center-pivot pickup scale (RR parity; was top-left-pivot at a grab
offset); legal drops land instantly with a row wash (Card B alone demonstrates the
commit flight, now aimed at the row's center); Toss rallies the ball A↔B; the
reward pop and every motion scale pivot on their center; the energy-wash strip is
labeled; toasts sit on raised plates inset from the edges with body-size detail
text and a 2.5 s read floor; SFH-4/SFH-5 rewritten to be runnable as written.

**2026-07-28 virtual-controller round (director's second pass, suite → 2542):**
every finding fixed and the WHOLE pad flow re-driven synthetically through the
live InputAction objects (the same instances the virtual pad feeds — engine
delivery itself was proven by the director's own presses reaching the action
layer). Fixed: Card B unreachable (auto-derived focus groups labeled every
ungrouped run VERTICAL, so "right" across the hand's HStack was dead — groups
are now layout-aware, HStack rows navigate horizontally and Grids as grids);
B-cancel dead on drop-target lists (the cancel handler only attached to
REORDERABLE lists); A-commit landing at the stale aim ("returned to the hand" —
the list now aims at the pressed row first, and the arm's opening hit-test no
longer stomps the arm presentation's aim); the ring frozen while the aim
stepped (armed aim and focus are now ONE truth — the ring rides every step);
the ghost never leaving the hand (armTo spring-hops the ghost to the aim, RR's
ghost-follows-focus); the first row's focus ring clipped by the scroll edge
(rings under a clip host draw INSET, inside the row's own bounds); and
"why row 02 first" (rows that refuse the armed card now DIM — the eligible rows
are the lit ones). Live matrix log: arm → ring+aim+ghost row-02 → down → row-03
→ down → row-04 → A → "A landed on row-04" → re-arm clean → B → cancel + home.

**2026-07-28 round three (director's screenshots):** the inset focus ring drew
UNDER the row's plate (flat tree paints plates as siblings above the hit — only
the top arc showed) → the ring holder now paints topmost within its surface
(z 9999; other surfaces are separate ScreenGuis); entering a group ALONG its
axis lands at the NEAR END (right into the hand = Card A from every row —
ordinal "nearest" had mapped row 3 to card 3; perpendicular entry keeps ordinal
nearest so grids still preserve the column); and the cards declare a `proxy` —
the ghost is a labeled mini-card ("Card C" on a raised plate), not the default
anonymous ghost that read as "a drop target appeared". All three re-driven live
through the action layer: boot ring full on row-01, right-from-row-03 = CardA,
armed CardC shows a "Card C" ghost on row-01, B cancels home.

**2026-07-28 round four (director's ring/plate screenshots):** the ROOT CAUSE of
the ring at last — the instance tree is flat with Sibling z, so on stacked rows
an outward Border ring survives only as its top arc (the next row covers the
bottom, the canvas clips the sides) and any ring parented under the hit is
covered by every higher-z sibling regardless of its own ZIndex. The ring is now
a FLOAT: a topmost-z sibling frame inside the clip host, inset within the
focused rect, re-aimed by applyRect when the row moves — verified as a full
four-sided rounded ring in cropped pixels, not just instance numbers. The
"text on a darker band" artifact was the drop cell painting a SECOND control
plate (margin-inset) over the full-row hit Button's plate — the cell is now
content-only (one plate per row) and the wash mounts ONLY while it has
something to say (a blend-0 tint had been covering the native selected state).
And the hand slot EMPTIES while its card is held (RR: "the slot sits empty
until it lands or returns") — the ghost carries the card's face, the slot keeps
its armed highlight. Pixel-verified: empty slot C + "Card C" ghost + full ring
in one capture. Suite 2565 (includes the concurrent Step 5.5 session's work).

**2026-07-28 round five (director: "the slot should empty for POINTER drags too
— and how do we guarantee things like this are universal?"):** the held-slot
behaviour is now a FRAMEWORK GUARANTEE, not fixture code. The registry publishes
`heldSource` (set at acquisition, cleared when the drop LANDS or the return
flight ARRIVES — the arrival, not the release frame); the renderer stamps the
node with the `dragHeld` presentation state; `sheet_model` emits a
`.luau-drag-held` rule in EVERY package's sheet (TextTransparency 1 — the exact
iconArt channel), with a direct-write fallback in bespoke mode; the return
flight's arrival is announced as feedback `arrive` with `context.returned=true`
(new — RR refills slots on arrival, so the moment had to be a real event).
`dragHeld` cannot be authored (presentation authority), which is what makes the
guarantee universal. The fixture's hand-rolled version was DELETED as proof.
Pinned end to end (pickup→held, release→still held, arrival→cleared) and
pixel-verified on the pointer path: mouse-drag live, slot A blank, B/C intact.
Documented in api.md (draggable spec: `grabAnchor` + the held-source guarantee).
Suite 2566.

**2026-07-28 round six (director: tap-to-pickup / tap-to-drop on mobile):**
`armOnTap` on `UI.draggable` — a tap on a declaring source ARMS an armed-mode
session instead of activating (the touch paradigm's pickup; the commit half
already existed — the list commits any armed session on row activation). The
finger is FREE while a card is held, so the list scrolls with a normal swipe
(past the tap threshold = can never read as a drop) — the exact
scroll-vs-drop separation the drag path cannot offer on mobile. A tap while
held flows to the consumer (put-back / row commit unchanged); press-and-slide
still promotes to a real drag; action-source activates (gamepad A) keep their
path. One renderer choke point covers native taps and detector-synthesized
taps. Fixture cards opt in; pinned end to end (tap arms + held stamps, no
activation eaten, second tap flows, travel still promotes). Suite 2567.
LIVE-PROVEN WITH REAL CLICKS (MCP user_mouse_input, instance-targeted): click
Card A → armed, ghost up, no drag; click row-04 → "A landed on row-04"; armed
Card B survived scroll input over the list without dropping; click the held
card → put back. Real-input truth: the injector's instance_path targeting
delivers; raw x/y coordinates do not.

Every row below is IRREDUCIBLE — no instrument in this build can close it. Each has one exact procedure. The reviewer never assembles state: every fixture is a named gallery scenario selected by one workspace attribute.

## Setup (once)

1. Open the dev place (or any place), run `lune run tools/lune/studio_sync.luau` from `GameStudio/ui/LuauUI`, then run `tools/studio/inject.luau` (via the Studio command bar or MCP `execute_luau`, Edit mode). Confirm `workspace.LuauUI_SourceStamp` matches the server's printed stamp **and the served file count matches** (lesson: `sync-server-file-list-is-startup-frozen.md`).
2. Select a scenario: `workspace:SetAttribute("LuauUI_Scenario", "<name>")` in Edit, then Play. On-screen labels identify the fixture; `workspace.LuauUI_ScenarioState` reads `ready`.
3. Reset between checks: `workspace.LuauUIScenarioAPI.reset:Invoke()`.

## PENDING_PHYSICAL rows

| ID | Device | Scenario | Procedure | Expected |
|---|---|---|---|---|
| SFP-1 touch drag feel | Weakest supported phone (2 GB-class Android), retail client or Studio device streaming | `sponsor_drop` | Finger-drag Card A: press, hold, drag over rows, release on a row; repeat with a flick; drag into the top/bottom edge bands and dwell | Ghost rides CENTERED under the finger, 1:1, no lag (the RascalRally-ratified default; `grabAnchor = "preserve"` is the opt-out for large surfaces); a legal Card A drop lands INSTANTLY — no flight — and the landed row washes accent and decays; Card B is the one card that flies on commit, and its ghost now aims the ROW'S CENTER; a flick's release velocity visibly carries into the fly-home; edge dwell ≈0.3 s then smooth ramping autoscroll; band feels reachable with a thumb (44 px portrait band) |
| SFP-2 tap-vs-drag on touch | Same phone | `sponsor_drop` | Tap a card (should PICK UP — `armOnTap`); swipe the list (should SCROLL, never drop); tap a row (should place); tap the held card (should put back); then 10 deliberate small nudges under ~14 px on a card | Tap = pickup, tap again = put back, swipe = scroll, tap-row = place; no accidental drags from nudges; taps on rows/buttons are never eaten |
| SFP-3 real gamepad drag | Physical gamepad (console or desktop pad) | `sponsor_drop` | Focus a card, Activate to arm, D-pad across rows (ineligible rows must be skipped), Activate to commit; then arm and press B | Arm→navigate→commit works end-to-end on real pad delivery; B cancels with the zero-velocity fly-home; focus ring always visible; NOTE: `UIDragDetector` gamepad motion remains unverified platform-wide (NS-P1 rider) |
| SFP-4 weakest-device perf | 2 GB-class Android | `sponsor_motion` → `stress`, then `sponsor_drop` autoscroll while dragging | MicroProfiler / frame-time overlay during: 20-clone stress, a full-speed autoscroll drag over the 12-row list | Frame time within the game's device budget; no GC hitching from motion (headless says zero-alloc at rest; only a device shows real frame cost) |
| SFP-5 OS keyboard keep-visible | Physical phone | any text-input scenario (`authoring` gallery) | Focus the bottom text field with the real OS keyboard | The field visibly shifts above the keyboard (the SF-M9 channel under a REAL `keyboardOcclusionRect`) |

## PENDING_HUMAN rows

| ID | Judgment | Scenario(s) | What to look at | Question being asked |
|---|---|---|---|---|
| SFH-1 motion feel | `sponsor_motion` | Mash **Panel** (interrupt mid-slide), mash **Toss** (each press is a visible flight — the ball rallies SlotA ↔ SlotB with a mirrored velocity seed), **Pop** (grows from the CENTER — the one earned overshoot), **Hit** twice fast and watch the labeled "energy wash — press Hit" strip under the stage flash and decay | Does interruption feel continuous (no restart pop)? Does the rally read as one ball with momentum? Does the pop read as earned, everything else calm? |
| SFH-2 celebration | `sponsor_celebration` | run, then interrupt mid-beat 2; replay | Does an interrupt land on a clean, believable end state on that frame? (Pops now pivot on their center — fixed after your first pass) |
| SFH-3 toast readability | `sponsor_toast` | burst; priorityMidFloor. Toasts now sit on a raised PLATE with corners and a shadow, inset from the edges; the detail line is body-size; the lab's own title moved below the stage | Are 3 toasts + queue readable at race-glance speed? Does the read floor feel right (now **2.5 s** after your "too fast" call — say if it now feels slow)? |
| SFH-4 ten-foot composition | `sponsor_drop`, then `sponsor_list` — TWO separate checks, never both at once | **Check 1:** Stop Play. In Edit: `workspace:SetAttribute("LuauUI_Scenario", "sponsor_drop")`. Play. In the command bar: `local run = require(workspace.LuauUIMatrixDriver) print(run({ mode = "select", row = "console-ten-foot" }))` — the emulator switches to the console profile with the 1.5× type floor. Look at the screen from ~3 m (or lean back ~3× normal distance). **Check 2:** Stop Play, set the attribute to `"sponsor_list"`, Play, run the same `select` line, look again | Type floor is applied (the machine verified 1.5×) — but is the COMPOSITION right at distance: density, focus ring visibility, hand reachability? Only eyes can pass this |
| SFH-5 capture review | none — this is a picture check, no Studio needed | Open `artifacts/sponsor-framework-gaps/captures/` and compare each PNG against the checklist below (§SFH-5 checklist) | The machine verified the geometry numbers; a human confirms the pictures tell the same story |

### SFH-5 checklist — what each capture should show

| File | You should see |
|---|---|
| `sf_motion_initial.png` | The motion lab at rest: stage with two slots, the ball parked in SlotA, the labeled energy-wash strip, the control grid |
| `sf_motion_stress.png` | The 20-clone stress scene mid-motion (clones fanned out, no layout wreckage) |
| `sf_celebration_terminal.png` | The celebration's clean END state (no half-finished beat frozen mid-air) |
| `sf_toast_stack.png` | Three toast rows stacked top-left ON PLATES, glyph + title + detail readable; queue copy on the overflow rows |
| `sf_drop_ghost_over_everything.png` | A drag ghost floating ABOVE both the list and a live toast (layering proof) |
| `sf_list_churn.png` | The racer list mid-churn with selection visible and no torn rows |
| `sf_list_preferred_text_largest.png` | The same list at the largest preferred-text step: taller rows, nothing clipped |
| `sf_avatars_states.png` | The avatar grid showing all states at once: ready, loading placeholder, dimmed, failed-silent |
| `sf_markers_corners.png` | Minimap markers with corner markers sitting EXACTLY on the map's corners |
| `sf_billboard_world.png` | The world-anchored omen billboard over the kart with its depleting ring |
| `matrix_phone_portrait_drop.png` | The drop lab reflowed for phone portrait: hand at bottom, bands reachable |
| `matrix_console_tenfoot_drop.png` | The drop lab at console scale: 1.5× type, focus ring plainly visible |
| `matrix_avatars_largest_text_portrait.png` | Avatars at phone portrait + largest text: labels wrap, grid stays aligned |

## Rollback / exit

Stop Play; delete `workspace.LuauUIMatrixDriver` and the `ReplicatedStorage.LuauUI*` folders if the place should be returned to empty (the dev place carries no other content). Nothing in this stage ships to players; the gallery is development-only.

## Standing riders carried forward (not this stage's scope)

- NS-P1/NS-P2 physical gamepad/touch substrate rows; XP-P1..P4 (cross-platform-proof stage).
- `preferredTextOffset` real-value sweep; `topbarInset` + `env.locale` consumers (flagged to director).
- VirtualInput non-delivery (re-probed and still dead this session; injected input remains the honest fallback, labeled per row).
