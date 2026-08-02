# native-substrate physical/assisted review packet

**Date prepared:** 2026-07-23 · **Ledger:** `acceptance-ledger.md` rows NS-P1..NS-P3 +
two assisted sub-checks. One focused pass closes every remaining row; everything
automatable is already PASS_AUTOMATED with stored artifacts.

## Setup (once)

1. Open the Studio place used this session (Place1 with the injected gallery) or
   re-inject: `cd GameStudio/ui/LuauUI && lune run tools/lune/studio_sync` then run
   `tools/studio/inject.luau` via the command bar / MCP in Edit mode.
2. Scenario selection: set workspace attribute `LuauUI_Scenario` (string) BEFORE
   Play. Reset any scenario with `workspace.LuauUIScenarioAPI.reset:Invoke()`.
   Every scenario prints readiness and exposes `report`/`step` BindableFunctions.
3. On-screen identity: workspace attributes `LuauUI_SourceStamp` + `LuauUI_Version`
   must match the manifest stamp printed by studio_sync.

## NS-P1 — physical gamepad: selection bridge (scenario `selection_bridge`)

Connect a physical pad to Studio (or a retail client on a published copy).

1. Play; the base screen shows "Selection bridge (base stays nil)".
   **Expect:** no engine selection outline anywhere; pad d-pad moves nothing
   engine-owned (LuauUI logical focus only, driven through IAS).
2. Click "Open modal" (or step `openModal`).
   **Expect:** engine outline on the first row; d-pad Up/Down moves LuauUI focus
   AND the outline follows with NO double-step (one press = one row), no fighting,
   no jump-back. Record whether selection sound/haptics occur (observations).
3. Hold Down until an off-view row focuses. **Expect:** the modal's list
   autoscrolls (native) and never scrolls a surface outside the modal.
4. Press ButtonA on a focused row. **Expect:** exactly ONE activation (no IAS
   double-dispatch). Press ButtonB. **Expect:** modal dismisses, outline clears,
   `GuiService.SelectedObject == nil` (report:Invoke() shows selectedObject null),
   gameplay controls unaffected.
5. **TextField hazard (platform verifier F3/F4):** repeat steps 2–4 on a modal
   containing a TextField beside buttons (TextFields are intrinsically
   `Selectable` for native A-press capture, giving the engine's navigator a
   second target). Watch specifically for the pad moving the engine outline onto
   the TextField without LuauUI's focus moving (self-navigation/desync) and for
   duplicate select sounds. The bridge re-asserts on every logical focus change,
   so a transient divergence that self-heals on the next move is acceptable; a
   sticky divergence fails the row.
6. FAIL any step → the bridge stays experimental: record in the ledger and leave
   `engineSelectionBridge` unset in consumers (LuauUI focus visuals remain).

## NS-P2 — physical touch (phone) + emulator-assisted checks

Device emulator half (assisted, no hardware): pick a notched phone preset.

- Scenario `safe_area`: **expect** content clear of the notch on all four edges in
  both orientations (the emulator camera pre-excludes the notch; confirm no double
  inset — content must NOT be inset twice).
- Scenario `scroll_host`: drag-scroll the list with the emulator's touch pointer.
  **Expect:** native momentum + elastic bounce + scrollbar; below-list marker never
  moves. (This closes the touch-scroll sub-row the MCP cannot inject.)
- Accessibility → Preferred Text Size (if the Studio emulation is available): set
  Large/Larger/Largest and run scenario `preferred_text`. **Expect:** painted text
  grows INTO the reserved boxes (no clipping anywhere, TextFits true in report).
  The engine applies the preference as a FIXED PIXEL OFFSET (official
  announcement; magnitude undisclosed) — MEASURE the actual per-level offset in px
  (painted TextBounds height delta at a known TextSize) and compare against the
  reservation offsets in `roblox_env.luau` (`Large=6, Larger=10, Largest=14`).
  If any measured offset exceeds its reservation, raise the table (never lower it
  below measured + margin).
- Scrollbar overlay (platform verifier F6): in scenario `scroll_host` verify a
  right-edge control inside a scrollable list is still tappable under the 8px
  scrollbar band; if not, the Step-3 ScrollView completion reserves the width.

Physical phone half: real touch on scenario `scroll_host` (fling feel, overscroll),
`path_ring` (stroke rendering on device), and any Table surface (pan-scroll vs
edit-reorder). OS keyboard rows stay with the existing textinput riders.

## NS-P3 — device-performance floor (deferred to roadmap Step 7)

The performance lab (Step 7) owns real budgets. For this stage only a smoke note is
wanted: scenario `scroll_host` + `table-native-scroll` on the weakest available
Android: scrolling stays smooth and memory stable over 2 minutes. Record device,
build, and subjective result; numbers wait for the lab.

## Export

After each pass: `workspace.LuauUIScenarioAPI.report:Invoke()` returns the JSON
report — paste it (or save via the MCP) next to the matching
`artifacts/native-substrate/*.json` with a `_physical` suffix, and flip the ledger
row to `PASS_PHYSICAL` with the device + build noted.
