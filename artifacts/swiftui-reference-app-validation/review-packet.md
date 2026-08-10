# Review packet — swiftui-reference-app-validation (PENDING_PHYSICAL / PENDING_HUMAN)

One prepared pass closes every row below. Nothing here is closable by Studio
emulation, and none of it was relabelled as automated evidence.

## The build

Open any of the five self-contained places in `examples/places/` (rebuilt from
final source at gate close; no network, no purchases, no player-data writes):

`LuauUI-Ref-Glade.rbxl` · `LuauUI-Ref-Cartwheel.rbxl` · `LuauUI-Ref-Sipworks.rbxl`
· `LuauUI-Ref-Foyer.rbxl` · `LuauUI-Ref-Wardrobe.rbxl`

Each boots straight into its proof (workspace attribute `LuauUI_Scenario`).
On-screen state is drivable through the visible controls alone; the scenario API
(`workspace.LuauUIScenarioAPI` BindableFunctions: `report`, `step` with
`"name:payload"`, `reset`) is available for scripted resets between judges.
`LuauUI_ThemePackage = "fantasy_parchment"` before Play swaps the theme.

## RA-X1 — physical touch (incl. the real mobile OS keyboard)

Per proof, on a physical phone (portrait AND landscape):

1. Play the representative loop end to end by touch only (each proof's loop is
   listed in `acceptance.md` RA-P1..P5).
2. Verify every verb is reachable by touch (no hover-only affordance), targets
   feel ≥44px, and the search/watchword fields summon and survive the real OS
   keyboard (Foyer search; Cartwheel sign-up) without occluding the field.
   On a NOTCHED device also confirm the four-edge safe-area derivation: no verb
   under the notch/home indicator and non-zero deviceSafeInsets actually
   engaged (platform review N6 — the emulator's presets are rectangular, so
   nothing archived proves this).
3. Wardrobe: one-finger orbit on the preview pane; try-on from the grid; a
   purchase rejection reads clearly at arm's length.
4. Record device, OS, and any mis-tap or unreachable verb. Expected: none.

## RA-X2 — real gamepad / console delivery

On real gamepad hardware (and console/ten-foot where available):

1. D-pad/stick navigation reaches every control in each proof; the focus ring is
   always visible and never trapped (Tab-equivalent traversal is Studio-proven;
   REAL pad delivery and `PreferredInput == Gamepad` are what this row owns).
2. ButtonA activates, ButtonB dismisses every modal (confirm sheets, detail
   panels, refine sheet).
3. Wardrobe: with the pane focused, D-pad Left/Right (and L1/R1) orbit the
   mannequin; off the pane those keys navigate.
4. The gamepad virtual cursor must not self-summon at modal transitions
   (`ROBLOX.md` known engine behavior — record if seen; it is engine-side).
5. ButtonStart/ButtonSelect and the CoreGui back-button must not collide with
   in-experience bindings at any modal state (platform review N7 — the actual
   "Button A contention" family emulation cannot exercise).

## RA-X3 — human product judgment

One pass per proof, any platform: "does this read as a designed product?"
Specifically: hierarchy at a glance, one focal verb per view, motion feel
(reduced-motion parity honored), Fantasy Parchment coherence (chrome re-themes;
scene/stage content palettes read intentionally), and the stand-in art question —
thumbnails currently use the engine's generic placeholder texture and the
mannequin/scene art is deliberately blocky; judge whether an art pass is wanted
before any external showing (recorded as expected follow-up, not a defect).

## Known-open cosmetic riders for the same pass

- Ten-foot: the one declared truncation ("Sunshower Curls") disclosure plate on
  focus dwell — confirm it reads on a real TV distance.
- Wardrobe compact: wallet chip rides the pane corner — confirm it never
  collides with the mannequin's silhouette at odd aspect ratios.
