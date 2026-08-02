# Engine input truths found during Table Phase B live drives (2026-07-19)

All three probed live in Place1 with `workspace:SetAttribute` probes on real
`InputAction.StateChanged` (evidence: artifacts/studio/part2-table-phaseb.json).

1. **`InputObject.Position` excludes the topbar inset; IgnoreGuiInset rects do
   not.** Any adapter comparing pointer positions against solver rects must add
   `GuiService:GetGuiInset()` (ScreenTarget `toWindowSpace`). Symptom before the
   fix: the drop indicator computed its slot ~58px (one row) high while clicks
   (which the engine hit-tests itself) worked fine — a nasty half-working state.

2. **Direction1D composite slots are axis signs, not key names.** `Up` slot
   emits +1, `Down` slot emits −1, whatever key you put there. Map
   `direction > 0 → Up`. Wrong mapping is INVISIBLE headless and invisible to
   scriptable-Fire drives (they bypass bindings) — it only shows up under real
   or injected key events. Live symptom: focus navigation ran backward, which
   at list position 1 looks like "keyboard is dead" (clamped at the top).

3. **Under Studio injected input, key bindings do not fire while Shift is
   held** — composite AND Bool both (probed both). Modifier+mouse works
   (Activated + `IsKeyDown`), so ctrl/shift-click semantics verify live, but
   shift+key chords cannot be driven by `user_keyboard_input`. Do not burn time
   "debugging" a chord feature via injected keys; it needs a manual pass.

4. **Injected Left/Right ARROW keys never reach IAS either** (2026-07-20:
   probed with a fresh priority-3000 Bool binding on Left — zero StateChanged
   while injected Down/Up/Return/letters deliver fine). Keyboard horizontal
   bindings (the Adjust action) are therefore un-drivable by injection, same
   class as the shift-chord limitation — hand/physical testing only. Do not
   diagnose "Left does nothing" from injection results.

5. **Injected keyboard needs the game viewport re-focused (synthetic click)
   after ANY other Studio interaction** — every `execute_luau` steals focus, so
   the drive pattern is: click viewport → the ENTIRE key sequence in ONE
   `user_keyboard_input` call → only then read state. Interleaving reads
   between key calls silently kills delivery (looks like the same "keyboard is
   dead" symptom as #2 — check ProbeNav-style attributes to distinguish).
