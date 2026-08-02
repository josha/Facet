# Parallel Sponsor (Step 6) — frozen baseline

**Date:** 2026-07-30
**Stage:** `parallel-sponsor` (roadmap Step 6), per
`games/RascalRally/docs/LUAUUI_SPONSOR_PARALLEL.md` build sequence step 0.
Nothing in this baseline changes player behavior.

## Suites (both green at freeze)

| Suite | Command | Result |
|---|---|---|
| RascalRally | `games/RascalRally/code/run-tests.sh` | **2425 passed**, exit 0 |
| LuauUI | `GameStudio/ui/LuauUI/run-tests.sh` | **2591 passed**, exit 0 |

Format gate: `stylua --check` clean on `src/client/init.client.luau` at freeze.

## Selector state at freeze

No Sponsor presenter selector exists. The legacy presentation is constructed
unconditionally at `games/RascalRally/code/src/client/init.client.luau:673`
(`sponsor = SponsorController.new({...})`), which builds the full legacy module
graph (`SponsorController.luau:567` → `SponsorGui.new(ctx)` plus celebration /
racer list / results / gesture / widget kit / FTUE modules).

Planned selector (matches the shipped `UseLuauUISettings` /
`UseLuauUIRacerList` reversible-port pattern, `docs/LUAUUI_SETTINGS_PORT.md`):

- one workspace attribute, **`UseLuauUISponsor`**, read once at client startup
  *before* either presentation is constructed;
- unset/false → legacy path, byte-identical behavior;
- `true` → LuauUI presenter only (dev builds/Studio only; never set in
  production);
- the LuauUI path is isolation-wrapped so a failure cannot take down client
  startup;
- rollback = leave the attribute unset.

## Legacy surface frozen (evidence targets, not migration targets)

Modules (all under `games/RascalRally/code/src/client/`), total ≈ 14,191 lines:
SponsorGui (2,269) · SponsorController (1,488) · SponsorCelebration (1,812) ·
SponsorRacerList (1,586) · SponsorResults (2,882) · SponsorGesture (1,859) ·
SponsorWidgetKit (973) · SponsorFtue (692) · SponsorMotion (35) ·
SocialBannerGui (237) · ShowrunnerPillGui (358).

These files must remain unchanged through the stage except the isolated
selector branch in `init.client.luau`. The integrity check is a recorded
checksum, not a promise:

- `baseline/legacy-checksums.txt` — `shasum -a 256` of every module above,
  recorded at freeze; the gate re-runs and diffs it. **11 rows, and only those
  11.** The freeze also stamped `init.client.luau` into this file, which made the
  gate self-contradictory: that file is the ONE sanctioned edit this stage allows
  (the selector branch), so its row went stale the moment the selector landed and
  the gate has been reporting a false failure ever since. It now lives ONLY in
  `sanctioned-changes-post-abc.txt`, whose whole purpose is to carry a moving
  hash for a file the stage is allowed to change (corrected 2026-07-31, director
  visual round 2, when DV2-6 added the game-wide player-list write).

## Shared semantic seams both presenters consume (authority stays here)

- Remotes: `SponsorCmd` (client→server intents), `SponsorMsg` (server beats).
- Player attributes (server-written): `SponsorRole`, `SponsorHand`,
  `SponsorEnergy`, `SponsorDrama`, `SponsorShow`, `SponsorShowCharge`,
  `SponsorHue`, `SponsorHelpOnly`, `SponsorSpreadFull`, `PrefReducedMotion`.
- Shared models (`src/shared/`): SponsorHudModel, RaceHudModel,
  CelebrationModel, SponsorSignature, ShowrunnerPillModel, MinimapModel,
  SponsorListModel, SponsorTuning, SponsorFairness, KartRoster.
- World markers: `World.Track.SponsorPads` / `SponsorZones`.

The LuauUI presenter must consume exactly these seams; no new authority, no
legality inference from visuals.

## Pinned live baselines (captures/traces)

Recorded into `baseline/studio/` in the Phase-0 Studio session (2026-07-30,
bench `TrackLayout=debug`, Play Solo, sponsor via
`SponsorCmd:FireServer("role","sponsor")`; bench attribute restored to
`firstSmile` after):

| File | State |
|---|---|
| `PS-B3-table-max-legacy-iphone16-landscape.png` + `.geometry.json` | Live race, table maximized, emulated iPhone 16 852×393 landscape |
| `PS-B3-table-max-legacy-desktop-pane-portrait.geometry.json` | Maximized portrait split geometry (map over full-width list, hand at bottom), measured live at 907×1044. Its paired PNG turned out to capture the results screen instead (race ended between dump and shutter — bench auto-advance); the maximized-portrait VISUAL is carried by the armed capture below |
| `PS-B3-table-min-legacy-desktop-pane-portrait.png` + `.geometry.json` | Follow pose (minimized): 190×190 corner mini-map, watched-racer card with ‹ › cycle arrows bottom-center, list/hand/toggle hidden — verified visually |
| `PS-B4-card-armed-legacy-desktop-pane-portrait.png` | Card armed via tap, maximized portrait pose: ghost staged above the hand dock, full-width row list — doubles as the maximized-portrait visual evidence |
| `PS-B3-results-sponsor-early-legacy-desktop-pane-portrait.png` | Results early beat, portrait: placement banner, standings, sponsors row, Rally Points band, CTA pair |
| `PS-B3-results-late-legacy-desktop-pane-portrait.png` | Results later beat (streak line, "Race Again"/"Sponsor a Race" CTAs) — originally mislabeled table-max; relabeled after visual verification |
| `PS-B4-input-trace-legacy.md` | Arm→tap→commit trace, exactly one `play` receipt; instrument limits |

New instrument lesson from this session:
`games/RascalRally/docs/lessons/studio-device-emulator-swallows-injected-input.md`
(emulator swallows ALL injection; GUI-path-only delivery without it).

The remaining five-view × pose × results-role baseline sweep intentionally
waits for the shared scenario protocol (deterministic fixtures, holdable
states). Legacy is checksum-frozen, so those later captures are the same
frozen bar.

## Performance baseline

Studio-level regression numbers only (never device evidence): recorded with
the PS-B3 session (frame-time sample + instance counts under the Sponsor
surface). Weakest-device numbers remain `PENDING_PHYSICAL` (PS-P3).
