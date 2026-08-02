# Studio instrument log (contract §4)

## Session 2026-07-24 — healthy

| Time | Viewport | Stamp | Result |
|---|---|---|---|
| preflight | 1233×1067 | b8ba37d9-691341 | PASS — scenario `probe` ready, canary capture `M0_preflight_canary` succeeded |
| M0-A1 drive | 1233×1067 | 1a7550a0-696035 | PASS — 9/9 invalid screens rejected, capture `M0-A1_authoring_desktop_rejected` |
| A-LV1 re-drive | 1233×1067 | cf27d826-697733 | PASS — grid cells 0→96px, capture `A-LV1_authoring_desktop_gridFilled` |

## Session 2026-07-24 — FAIL_ENVIRONMENT (viewport collapsed to 1×1)

Reproduced the recorded trap in `docs/lessons/studio-viewport-1x1-instrument-trap.md`
while driving the `scroll_host` scenario for A-SV1:

- `workspace.CurrentCamera.ViewportSize == 1, 1`
- `screen_capture` hung past 120 s and had to be stopped
- every solved width collapsed (a `width = fixed 280` ScrollView reported
  `AbsoluteSize.X == 0`) because the root content rect was ~1 px wide

**This is instrument blindness, not a product defect** (contract §4: "Do not infer a
framework defect from a blind instrument"). The A-SV1 geometry read in that state is
discarded, not recorded as evidence.

Recovery attempted and failed in-session:
1. `osascript` activate / set-frontmost on `RobloxStudio` — process came to the front,
   viewport stayed 1×1;
2. stop Play → start Play — viewport stayed 1×1.

Root cause identified, and it is outside the agent's reach:

- the **Edit** datamodel still reports `1233, 1067` (a cached value), while the
  **Client** datamodel reports `1, 1` — so the play session is genuinely not
  rendering;
- `System Events` reports that the `RobloxStudio` process has **no windows**
  (`Can't get window 1 ... Invalid index`), i.e. the Studio window is minimized or on
  another macOS Space. `activate` / `set frontmost` cannot restore a window that the
  window server does not list.

This matches the lesson exactly: a hidden game view makes the play-session camera
`1, 1`, kills injected input, and hangs capture. Nothing about the framework changed
between the healthy runs earlier in this session and this one.

### Exact recovery procedure (for the review pass)

1. In Studio, click the **game view** tab so the 3D viewport is visible and not
   occluded by a Script editor or docked panel.
2. Run the preflight probe: `workspace.CurrentCamera.ViewportSize` must be larger
   than `1, 1`.
3. Re-run the affected rows; they are listed as `FAIL_ENVIRONMENT` in the ledger with
   their driver steps.

Rows blocked by this: A-SV1's live geometry/capture half (its headless half and the
step-level action results are complete), and everything downstream in the D-* device
matrix.


## Session 2026-07-24 (late) — RECOVERED, matrix completed

`open -a "RobloxStudio"` restored the window immediately, where `activate` and
`set frontmost` had not. Viewport returned to 1233×1067 in both datamodels and
`screen_capture` worked again. The recovery command is now recorded in
`docs/lessons/studio-viewport-1x1-instrument-trap.md` so the next session does not
lose a matrix run to it.

With the instrument healthy, the five-view matrix, the live orientation change and
the native-input chain all ran — see `matrix/`. Three further instrument facts were
established and recorded in `matrix/five-view-matrix.json`:

1. `StudioDeviceSimulatorService` exposes only `GetDeviceListAsync`,
   `GetDeviceInfoAsync` and `ConfigurationChanged` from `execute_luau`. Every setter
   (device selection, orientation, resolution/DPI override) is absent — a
   plugin-security boundary. Presets are therefore RESOLVED through the API and their
   facts driven through the verification surface's declared `setEnv` seam.
2. `UserInputService:CreateVirtualInput()` succeeds but the returned object exposes
   none of `SendKeyEvent` / `SendMouseButtonEvent` / `SendMouseMoveEvent` /
   `SendPointerEvent` at this security level. `VirtualInput` is unusable from
   `execute_luau`; the MCP's own `user_mouse_input` delivered a real `MouseButton1`
   instead.
3. Because device selection is unavailable, the engine window stays at its own size
   while the framework's layout facts are the resolved preset's. The console row's
   capture is therefore cropped by the window; its geometry trace is the evidence.


## Session 2026-07-24 (final) — the instrument is UNSTABLE on this machine

After the matrix completed, the Studio window vanished from the window server again
(`System Events` → 0 windows) and the play camera returned to `1, 1`. `open -a` had
restored it once and did not the second time.

So the recovery command is necessary but not sufficient here: the window does not stay.
Everything that needed a viewport was captured during the one healthy window —
the five-view matrix, the live orientation change, the native-input chain and three
captures. The single live row still open is `A-SV1`'s absolute geometry plus its
wheel-injection row; its step results reproduced identically and its canvas extents
(which do not depend on the viewport) are recorded.

**For the next session:** run `open -a "RobloxStudio"`, confirm
`workspace.CurrentCamera.ViewportSize > 1,1`, and do the Studio work in one pass
without switching away — this window did not survive being backgrounded.
