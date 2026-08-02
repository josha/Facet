# PS-T rows — layer L2 (table/list/map/poses) live Studio evidence

**Date:** 2026-07-30 · Play Solo, bench, `UseLuauUISponsor=true`, rig held
`racing` during the sweep. Suites at session: game **2591** / LuauUI **2598**;
stylua clean; 11/11 legacy checksums OK. Export:
`workspace.LuauUISponsorDevReport`. Flags/TrackLayout restored after.

**Fix round (same day):** findings 1 and 2 dispositioned below; the ONE real
defect the sweep found was that every semantic `label` on a childless
`UI.Button` was being PAINTED — "Wa t…" beside every map dot, "Show the table"
across the minimap, "…" on the size toggle, "Pre…" / "Ne xt" on the watch
arrows. Fixed screen-side (content buttons + `compactLabel`) and framework-side
(a node pinned on BOTH axes never ran the compact ladder — LuauUI row OWN-D10).
Suites after: game **2601** / LuauUI **2601**. Re-drive (same day): the three
load-bearing frames re-pinned clean and visually verified — compact-portrait
max (map "–" glyph, clean rows, a live NPC play pill rendering), phone-
landscape max, and the follow pose (watched card confirmed BOTTOM-CENTER with
‹ › glyph arrows). Tablet/desktop/TV frames still carry the pre-fix painted
labels; they get re-captured anyway in the owed paired legacy-vs-LuauUI
comparison sweep.

## Five-view sweep, maximized pose (captures in this dir)

| Row | Device | Viewport | sizeClass | splitAxis | Verdict vs spec §6 |
|---|---|---|---|---|---|
| compact-phone-portrait | `iphone_16` portrait | 392×758 | compact | **y** | ✓ map top / list below (matches legacy portrait split) |
| compact-phone-landscape | `iphone_16` landscape | 733×371 | regular | x | ✓ map left / list right (matches legacy landscape baseline) |
| tablet-landscape | `ipad_9th_generation` | 1078×809 | wide | x | ✓ |
| desktop-standard | `hd_1080` | 1920×1078 | wide | x | ✓ |
| console-ten-foot | `android_tv_1080` (44 dpi) | 1728×970 (fit-to-window) | regular | x | ✓ BY DESIGN — `adaptive.luau:63` demotes wide→regular under the ten-foot distance profile (fewer/larger, not denser); type ramp carries the bump |

Follow (minimized) pose captured at raw pane + phone portrait + phone
landscape (`PS-T1-luauui-min-*.png`).

## Interaction/state facts proven live

- **PS-T6:** dot tap → `watch.enter` 0→1, watch key AIKart_1→AIKart_7,
  durable selection follows the watch (Q3 provisional semantics); second tap
  on the same dot did NOT re-fire; `tracePoints=55` (≤100); dot hit target
  44×44 (floor honored).
- **PS-T2:** 12 s of live re-sorts: selection + watch key + mounted count all
  stable; no remount flicker observed.
- **PS-T1 state survival:** selection survived FOUR device/orientation
  changes including a live portrait⇄landscape axis flip (AdaptiveStack
  re-solve, no structural swap) — the load-bearing spec requirement.
- **PS-L4 completion:** SizeToggle click → pose minimized AND responder
  engaged→passive (the resign edge injection couldn't reach before);
  `engagedApplies` stayed 3 across idle frames (no fan-out churn).
- **PS-T5 (partial):** greyscale capture of the finished-state list: finished
  rows read by flag FORM + recede + latched position with zero hue; active
  rows plainly distinct. Blocked/slash/disconnected forms remain
  headless-proven (state-matrix spec) + owed a rig-held live fixture pass.

## Findings for the ui-designer integrated review

1. **Watched-card position — RESOLVED, not a positional defect.** The card IS
   bottom-center: `PS-T1-luauui-min-iphone16-landscape.png` shows it docked
   bottom-centre ("Rhoda Rhino / P3"), and the headless solve at 733×371 puts
   it at x=177 w=380 in a 717-wide anchor (centre 367 vs 366.5) with its bottom
   exactly the 14 px inset above the anchor's. **(505,239) is `CycleNext`, not
   the card** — the flat instance tree makes the two easy to conflate. The
   reading did surface a REAL defect at that exact spot, now fixed: the arrows
   were painting their semantic labels ("Pre…" / "Ne xt") instead of ‹ ›, which
   is what made the card's right end read as a separate block. The fixture spec
   now asserts centre-x, the dock gap and the lower half — the previous check
   only asserted the bottom edge, which a right-middle card also passes.
2. **White "✕ / hammer / Josh" chip — ATTRIBUTED, not ours.** It is the Roblox
   **CoreGui player list**: the ✕ is its close control and the hammer is the
   place-owner badge next to the local player's display name. Proof it cannot
   be a presenter node: it sits in the SAME screen corner in
   `PS-T1-luauui-min-iphone16-landscape.png`, where the racer list does not
   exist at all, and it is outside the table plate in both. Mechanically
   guaranteed too — the gather iterates `KartRoster.scan`'s entries, a parked
   sponsor's kart has no RaceState `Pos` row, so it reaches neither the list nor
   the map (the director's "no white 'you' dot on the sponsor map" ruling). New
   regression specs pin exactly that, plus "exactly one pose region's content is
   mounted". **Product question left open for the designer:** the CoreGui list
   occludes the racer list's top-right corner; legacy has the same overlap and
   the game disables no CoreGui, so a `SetCoreGuiEnabled(PlayerList, false)`
   would be a GAME policy change, not a presenter one.
3. **Split-axis keying at extreme aspects** — options for the ruling:
   - **(a) Key on `sizeClass` (what ships now, and what §6 says).** §6's table is
     written per class, `AdaptiveStack.axis` binds `adaptive.conditions.axis`
     straight through, and the breakpoint is the framework's one implementation.
     Cost: a 907×1044 desktop pane (taller than wide, but ≥600 wide) resolves
     regular/x, so the map sits left of the list in a portrait-shaped window.
   - **(b) Key on the panel's aspect (`panelW >= panelH`, SponsorGui:1053).**
     Reproduces legacy exactly at every window shape. Cost: a second breakpoint
     vocabulary alongside `sizeClass` (§6 keys row height, ticker, chip row and
     CTAs on the class, so the split would key on something else), and the
     number is the SOLVED panel rect, which is a geometry read-back rather than
     a declared condition.
   - **Divergence is desktop-only:** all five real device rows agree, so this is
     about resizable windows, not about any shipping device.
   - **Recommendation: (a), recorded as an intentional difference,** with a
     follow-up only if the director judges a tall desktop window a real
     configuration. (b) is buildable — the map canvas rect is already read back
     for the projection aspect — so this is reversible in one memo either way.
   - Not decided here; the `UI-SPEC` gate rules.

## Instrument notes

- Emulated fit-to-window scales the reported viewport (TV 1920→1728);
  `SetScalingModeAsync(ActualResolution)` did not change the report in this
  session — record viewport as-read per row.
- Renderer-owned instances can be temporarily renamed to address them by
  instance_path for clicks; restore the EXACT name (one dot's name was lost
  to a placeholder this session — renderer reconciliation self-heals on
  rebuild, but save the original name next time).
