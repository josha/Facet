# Device-emulator truths (2026-07-20, Studio compact-phone emulator, both orientations)

Probed live with ScreenInsets probe guis (CoreUISafeInsets / DeviceSafeInsets /
None / IgnoreGuiInset). Evidence: artifacts/studio/part2-device-emulator.json.

1. **The camera viewport IS the device-safe canvas.** `Camera.ViewportSize`
   already excludes the notch zones and the home-indicator bar (portrait:
   camera 389×762 of a 389×843 device — notch 47 + home 34 outside; landscape:
   camera 749×368 of 843×389 — 47 on BOTH sides + home 21 outside). An
   `IgnoreGuiInset` ScreenGui spans exactly the camera. Therefore device
   profiles and env bindings must NOT model lateral/bottom safe areas as
   in-canvas insets — the platform pre-excludes them.

2. **`GetGuiInset` reports only the 58px CoreGui topbar** — nothing lateral,
   nothing bottom — and that is the ONLY reserved region inside the canvas.
   `roblox_env`'s binding (viewport from camera + coreSafeInsets from
   GetGuiInset) is therefore CORRECT as-is on notched devices; the old
   preview "phone" preset (in-canvas 44/44/21 insets) was modeling a world
   that doesn't exist and has been replaced with the measured presets.

3. **The flat renderer cannot clip ScrollView overflow.** All instances are
   siblings of the root, so `ClipsDescendants` on a scroll node clips nothing,
   and no scroll offset is implemented. On a short canvas, overflowing rows
   paint past the panel AND past the screen edge (live-caught: the racer
   list's 8×36px rows spilled 24px in phone-landscape). Until real
   scrolling/clipping ships (spec §17 Phase 4 territory, with virtualization),
   CONSUMERS MUST FIT their content to the floor device — pin it with a
   headless spec at the measured canvases (see the racer list's
   `buildDocked` + fit spec pattern).

4. **Rotation is drivable programmatically**: with the game's
   `ScreenOrientation = Sensor`, setting `PlayerGui.ScreenOrientation =
   LandscapeLeft/Portrait` in the client re-orients the emulator live —
   no Studio UI needed. Re-apply after each Play restart.

5. **Injected mouse coordinates do NOT map under the emulator** (the device
   canvas is scaled into the Studio window; MCP/VirtualUser clicks miss and
   VirtualUser doesn't dispatch GuiButton activation at all). Verify emulated
   surfaces with geometry probes and by driving real class APIs
   (`:open()`/`:_activate(path)`); tap SEMANTICS belong to the full-window
   drives (Place1) where injection maps 1:1.
