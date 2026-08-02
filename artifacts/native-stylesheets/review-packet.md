# native-stylesheets review packet — NSS-P1 / NSS-P2 / NSS-P3

**Purpose (contract §8):** one focused pass closing the rows automation cannot.
Everything below is pre-staged; no test discovery, state assembly, or log
spelunking required. Automated evidence for the whole stage lives in
`artifacts/native-stylesheets/` (ledger + a1–a10 + feasibility m1–m10).

## Setup (once)

1. Open the working place (Place1 with the injected gallery) **or**
   `build/LuauUI-Gallery.rbxl` after running `tools/build_places.sh`.
2. If sources changed since the last injection: run
   `lune run tools/lune/studio_sync` in a terminal, then execute
   `tools/studio/inject.luau` in the Studio command bar (Edit mode).
3. The seeded stylesheet is `ReplicatedStorage.LuauUIStyle` (StyleSheet) with
   `Theme Dark` / `Theme Light` child sheets — it persists in the place.
4. Workspace attributes: `LuauUI_Scenario = "native_style"`,
   `LuauUI_NativeStyle = true`, `LuauUI_ForceStyleFallback = false`.

## NSS-P1 — Style Editor discoverability (E5, human judgment) — ✅ CLOSED 2026-07-24 (director pass: sheet/themes/rules found and edited as intended)

The automated proof (a3) edited the SAME DataModel objects the Style Editor
drives; what it cannot prove is that a designer can FIND them. In Studio:

1. Open the **Style Editor** (View → Style Editor) in Edit mode.
2. Without other guidance, locate the LuauUI sheet and answer: does the sheet
   appear with readable structure — themes as radio-button entries, rules named
   `Raised panel`, `Control fill`, `Control — hover`, `Selected row`, tokens
   `Surface`, `Control`, `Accent`?
3. Edit token **`Control`** on `Theme Dark` (pick any loud color). Press Play
   with the attributes above: do Row B / Music / the text field show your color?
4. Edit rule **`Raised panel`**'s `BackgroundColor3`. Replay: does the panel
   show it? (Both edits should persist across Stop/Play — seed-once.)
5. Check the guide table (`docs/guide/05-styling.md` §5.7): does the
   immediate-vs-reference-only labeling match what you experienced? In
   particular, confirm editing the `SpaceM` attribute does nothing to layout.
6. **Q11 residual:** with the Style Editor open on the sheet, run a play
   session that mutates a token at runtime (scenario step `editTokenLive`).
   Confirm the editor's Edit-mode view is NOT corrupted afterwards (play-mode
   mutations must not clobber the edit-time sheet).
7. Record: found/not-found per item, plus any naming that read as machine-ish.

## NSS-P2 — physical device confirmations (E4)

On a physical phone (and the floor device where available), retail client:

1. **Touch hover-flash:** run the `native_style` fixture; tap and hold rows.
   The hover fill must NEVER appear (hover rules are pointer-live-tag-gated);
   pressed feedback should. Record what you see.
2. **Theme-swap cost:** trigger `themeLight`/`themeDark` steps (or a game
   binding) and record any visible hitch. Studio-derated numbers were 0.05 ms
   per swap at 600 nodes — device numbers are the authoritative ones.
3. **Reduced-motion (query direction):** enable the OS/Roblox reduced-motion
   setting on the device (`GuiService.ReducedMotionEnabled` true — not
   script-settable, which is why this is here). Confirm state changes are
   instant, and record whether the built-in `@ReducedMotionEnabled` query
   variant (feasibility m9) matches when the setting is ON.
4. Styled-state paint sanity: hover (where a mouse exists), press, disabled,
   selected on device match the desktop captures
   (`NSS-A2_native_style_desktop_rest`, `NSS-A6_..._themeLight`).

## NSS-P3 — Styling Transitions publish status (E0, at release time)

Before ANY release enables sheet transitions by default: re-check the
transitions beta thread / release notes for publishability
(`corrections §7: a Studio beta must not be required by a publishable build`).
Until confirmed, keep the instant-change default (`setNativeTransitionsEnabled`
initial state honors reduced motion; declared transitions are polish-only).

## Export

Record results per row (PASS/FAIL + notes) back into
`artifacts/native-stylesheets/acceptance-ledger.md` (rows NSS-P1..P3) and flip
the gate's `designer-and-device-confirmation` check when all three close.

## Rollback

Native paint is opt-in per target: set `LuauUI_ForceStyleFallback = true`
(gallery) or omit `nativeStyle` (games) — the explicit-write path is proven
byte-equal (a10). Deleting `ReplicatedStorage.LuauUIStyle` reseeds defaults on
the next native-mode mount.

---

# Promotion to default — the flip packet (added 2026-07-24 after NSS-P1 closed)

Automated promotion checks are DONE (`promotion-readiness.json`): multi-root
modal+scrim, StyleLink-under-BillboardGui, Edit-DataModel styling, custom
game-style model, and NSS-P1 (director pass; your magenta `$Control` edit
persisting into the example-04 modal is itself the round-trip proof). What
remains before flipping the default is exactly the four eyes-on rows below.

## F1 — Published retail client (the biggest unknown)

All stylesheet evidence so far is Studio Play Solo. Steps:
1. Open `build/LuauUI-Gallery.rbxl` (rebuilt 2026-07-24 with the promotion
   sources) in Studio.
2. Set workspace attributes `LuauUI_Scenario = "native_style"`,
   `LuauUI_NativeStyle = true`.
3. File → Publish to Roblox (any private test place on your account), then
   join it from the retail app (desktop first; phone doubles as NSS-P2).
4. Confirm against the desktop captures: dark base + raised panel with rounded
   corners/hairline (phantom chrome), selected row tint, accent primary,
   hover/press on desktop, disabled dim (the scenario steps aren't drivable
   in retail — the REST state + pointer states are the check).
5. Anything missing/flat = the styling system differs in retail → report back
   and the default flip stops until diagnosed.

## F2 — Team Test theme independence (2 clients)

1. Same place, Studio: Test tab → Clients and Servers → 2 players → Start.
2. In one client's console (or a temp keybind): 
   `workspace.LuauUIScenarioAPI.step:Invoke("themeLight")`.
3. Confirm the OTHER client stays Dark (per-client `SetDerives` on a
   replicated sheet must be client-local under FilteringEnabled).

## F3 — RascalRally screens on device (flag staged, one toggle)

Wiring is in the game (uncommitted): attribute **`UseLuauUINativeStyle = true`**
routes all three LuauUI screens (settings via `UseLuauUISettings`, racer list,
garage pilot) through the sheet; absent = library default. Pass:
1. In the RR place set `UseLuauUISettings = true` + `UseLuauUINativeStyle = true`.
2. Phone + desktop: open the gear/settings modal — parity eyeball vs bespoke
   (fills, corners, hairlines, toggle rows, focus ring), scrim dim, no hover
   flash on touch, theme untouched (RR uses the Dark default).
3. Racer list (`UseLuauUIRacerList = true`): row selection tint, scroll, text.

## F4 — Device floor performance (NSS-P2 remainder)

The perf scenes with native paint on the floor Android device (tag churn +
StyleLink cost vs bespoke was only Studio-derated).

## The flip itself (after F1–F4)

One line: `native_style.DEFAULT_ENABLED = true`
(`src/client/native_style.luau`). Escape hatch per target:
`nativeStyle = false`. Billboards stay explicitly bespoke-paint until a full
billboard drive (pinned in `billboard_target.luau`); the edit preview follows
the library default automatically. Then: bump the suite/gate greps if the
default changes any golden output (none expected — fallback stays byte-equal),
re-run both suites + all gates, and record the flip in ADR-0018.
