# Row actions — five-view device matrix + perf budget (Task 11)

**Date:** 2026-08-10. **Feature:** `newRowActions` / Table `rowActions`
(`docs/plans/row-actions-implementation.md`). **Fixture:** gallery scenario
`row_actions` (`examples/gallery/scenarios/row_actions.luau`) — a mail-style
list, two surfaces: (1) hand-wrapped `ScrollView > VStack` rows sharing one
`LuauUI.newRowActionsCoordinator()`, (2) a reorderable/editable
`LuauUI.newTable` using the public `rowActions` spec key. Actions on both
surfaces: trailing = Delete (destructive) + Flag, leading = Mark Read,
`fullSwipe = true` on both edges.

**Evidence-class discipline (`docs/guide/11-device-verification.md`):** every
number below states which instrument produced it. Studio rows are
`studio-emulated` (E3) **by env-frozen viewport, not full device-catalog
selection** — see "What this matrix is (and is not)" below. Perf rows are
`lune` (E1), trend-only. Nothing here is a `phone-physical`/`console-physical`
(E4) result; those rows exist with zero entries in the NEEDS_PHYSICAL_DEVICE
section, stated rather than omitted.

## What this matrix is (and is not)

The plan's five-view driver (`tools/studio/device_matrix.luau` +
`src/preview/matrix_rows.luau`) resolves each row against the **live Studio
device catalog** via `StudioDeviceSimulatorService`, which requires a second
Play session per view for touch fidelity
(`docs/guide/11-device-verification.md` "Two sessions, not one"). This
session's known, twice-confirmed constraint is that every screen-driving MCP
tool (`user_mouse_input`, and — newly found this session — `screen_capture`)
times out; `execute_luau`/`get_studio_state`/`start_stop_play`/
`get_console_output` work. Given that, this matrix drives the canonical five
**viewport sizes** through the scenario's own frozen-env seam
(`LuauUIScenarioAPI.freezeEnv` + `.setEnv({viewportRect=...})`) inside **one**
live Studio Play session against the real engine (real solver, real text
metrics, real Instances) — genuine `studio-emulated` evidence for layout,
diagnostics, and the swipe/commit/reorder mechanics, but **not** a
catalog-selected device preset and **not** a proof of `displaySize`/
`PreferredInput` settling behavior the full driver exists to check. That gap
is exactly what a future full run of `tools/studio/device_matrix.luau` against
this scenario would close.

## Session setup (reproducible)

1. `lune run tools/lune/studio_sync` (fresh listener; confirmed `manifest 249
   nodes, stamp 75af9177-4154093` — not a stale server per
   `docs/lessons/sync-server-file-list-is-startup-frozen.md`).
2. Injected via `tools/studio/inject.luau`'s exact algorithm, **with one
   change**: `src/client/screen_target.luau` is 212,886 bytes, and this
   session's `execute_luau` environment refuses a direct `Instance.Source =
   <string>` property write once the string exceeds 200,000 characters
   (`"Provided string length (212886) is greater than or equal to max length
   (200000)"` — a NEW, previously-undocumented tool-level guard; not a Roblox
   engine limit, and not present in any prior session's notes). **Fix, proven
   in-session:** `game:GetService("ScriptEditorService"):UpdateSourceAsync(
   instance, function(_) return src end)` has no such cap and patched all 249
   manifest nodes cleanly (`{"created":0,"patched":134,"unchanged":86,
   "failed":[]}` on the settled run). `ModuleScript:UpdateSourceAsync` (no
   service prefix) does **not** exist and errors loudly — the working call is
   on `ScriptEditorService`, not the instance. **This is a new trap for future
   Studio sessions on this repo — `screen_target.luau` will only grow.**
3. `workspace:SetAttribute("LuauUI_Scenario", "row_actions")`, Play.
   Console: `[LuauUI Scenario] 'row_actions' ready (0.8.0); steps:
   bindScroll,close,commit,editing,keyDeleteList,list,menuList,mode,open`.
4. `LuauUIScenarioAPI.freezeEnv` (`{"frozen":true}`), then per view:
   `setEnv({viewportRect={x=0,y=0,w=W,h=H}, preferredInput=...})`, `reset`,
   drive steps, read geometry via `PlayerGui` traversal and
   `LuauUIScenarioAPI.report({tree=false}).diagnostics`.
5. **Instance-name truncation, found live:** this framework names every
   mounted Instance with its full LuauUI path (`"/MailActions/ListWhen/then/
   List/.../Content/Row"`), and Roblox truncates `Instance.Name` at 100
   characters. Any path past that length collides in `Name` with its own
   descendants, so `GetDescendants()` name-matching on deep nodes (the edit
   affordance, the trailing tray) is unreliable past ~100 chars — a
   **framework/tooling interaction**, not a row-actions defect. Shallow
   geometry reads (the row content itself, the Table's `Main` root) are
   reliable; deep reads noted below where affected.

## The matrix

Steps driven at every view: `open` (`_open` seam), `close` (`_close`),
`commit` (`_commitFirst` — the same path a full swipe or keyboard Delete
takes), `editing` (Table's edit-mode signal). Diagnostics = the live solver's
own complaint list (`controller.diagnostics()`); `[]` = clean.

| View | Viewport | `_open` reveals tray | `_close`/`_commitFirst` (Delete fires, row removed) | Table mounts, `editing` toggles | Diagnostics (list + table modes) |
|---|---|---|---|---|---|
| compact-phone-portrait | 320×640 | **PASS** — row content slides to `x=-80` (tray width), `dump.openEdge="trailing"` | **PASS** — `commit m2:trailing` → `fired=true`; `list` step confirms `m2` gone | **PASS** | **PASS** — `[]`, `[]` |
| compact-phone-landscape | 640×320 | **PASS** — `x=-80` | **PASS** — `fired=true` | **PASS** | **PASS** — `[]`, `[]` |
| tablet-landscape | 1024×768 | **PASS** — `x=-80` | **PASS** — `fired=true`, `list` = `[m1,m3,m4,m5,m6]` | **PASS** | **PASS** — `[]`, `[]` |
| desktop-standard | 1280×720 | **PASS** — `x=-79` | **PASS** — `fired=true`, `list` = `[m1,m3,m4,m5,m6]` | **PASS** | **PASS** — `[]`, `[]` |
| console-ten-foot | 1920×1080 | **PASS** — `x=-76` | **PASS** — `fired=true`, `list` = `[m1,m3,m4,m5,m6]` | **PASS** | **PASS** — `[]`, `[]` |

Raw per-view row-content geometry (the swiped row, `Content/Row`, before
`close`):

| View | x | y | w | h |
|---|---|---|---|---|
| 320×640 | -80 | 107 | 288 | 88 |
| 640×320 | -80 | 107 | 608 | 74 |
| 1024×768 | -80 | 107 | 992 | 74 |
| 1280×720 | -79 | 107 | 1248 | 74 |
| 1920×1080 | -76 | 107 | 1888 | 74 |

The row width scales with viewport (288→1888px) and the tray-reveal offset is
consistently the tray's own solved width (76–80px, the two-action trailing
tray's natural width; not a fixed literal — narrows very slightly at 1920px
because the destructive/normal button natural widths are text-measured, not
authored). No sibling overlap, no clipped essential text, no solver complaint
at any of the five views, including the narrowest supported phone (320×640).

### Cells not obtainable this session (native input required)

| Cell | Why NOT_OBTAINED | Evidence that exists instead |
|---|---|---|
| Real touch/mouse **swipe gesture** on the Table surface | `user_mouse_input` timed out (this session, twice, per the standing constraint); `_open`/`_commitFirst` are the internal seams the real gesture calls into, and those ARE proven live above | Headless: `tests/row_actions_input.spec.luau` (axis lock, flick, full-swipe commit — mouse and touch pointerType), `tests/row_actions_scenario.spec.luau`'s reorder-vs-swipe axis-lock cases |
| **Keyboard Delete** / **Shift+Return menu** live in Studio | The live client's `ctx.actionSystem` is `roblox_input.newSystem(core)` (real UserInputService-bound), **not** the pure `LuauUI.newActionSystem(core)` the headless test harness and other scenarios' `deviceKey(...)` calls use — the real system has no scripted key-press seam at all; only genuine `VirtualInput` key injection would drive it, and that tool times out this session (same class of failure as `user_mouse_input`) | Headless, full round trip: `tests/row_actions_scenario.spec.luau` "keyboard Delete on a focused row fires the destructive action end to end" and "Shift+Return opens the action menu on a focused row" both PASS against the identical scenario module; `tests/row_actions_input.spec.luau` Task 8/8b suites (Delete, ButtonX, Shift+Return chord, modifier preemption) |
| Gamepad **reorder** (grab/move/drop) live in Studio | Same `deviceKey` gap as above | Headless: `tests/table.spec.luau`'s GAMEPAD reorder case (via `02_playlist_table`'s own end-to-end test) proves the mechanism generally; row-actions' own axis-lock composition is proven in `tests/row_actions_scenario.spec.luau`'s mouse-drag reorder cases |
| `screen_capture` (edit-mode, sustained open-row state) | Two attempts, both `MCP error -32603: Request timeout` (posed state: list mode, row `m3` open trailing, 320×640 viewport) — matches this session's standing screen-capture-times-out finding, now confirmed in Edit-adjacent (Play, single-shot) mode too | Geometry readbacks above (position/size, not pixels) |

None of these are row-actions defects; all are this session's standing
input-tool-timeout constraint (task brief) plus one newly-found platform
difference (real vs. headless action system) recorded here for the next
agent who reaches for `deviceKey` inside a live Studio scenario expecting it
to work as it does in the test harness.

## NEEDS_PHYSICAL_DEVICE — owed riders

Carried from the implementation ledger (Task 5/6/8b reviews) plus this
session's findings. Each is a single physical-device check a human can run in
under a minute with the `row_actions` scenario already selected and Playing.

| Rider | One-line instruction |
|---|---|
| Touch-capture-vs-native-scroll | On a real touch device, swipe a list row mostly-vertically starting ON the row: confirm the list scrolls (not the row) and no residual horizontal offset is left on the row after release. |
| Scroll-steals-pan | Fling the list fast enough to still be decelerating, then touch down on a row and immediately drag horizontally: confirm the row still opens (native momentum scroll doesn't eat the gesture). |
| PrimaryModifier live probe | Hold physical Shift and press Return on a focused row: confirm the action menu opens (not the row's own Activate) — this exercises the real `InputBinding.PrimaryModifier` engine path Task 8b's headless suite can only simulate via `deviceKey`. |
| Shift-release-mid-chord | Press Shift, press Return, **release Shift before releasing Return**: confirm the menu still opens exactly once (no double-fire, no stuck-open state) — the real-hardware release-ordering case a scripted `deviceKey` sequence can't reproduce. |
| Same-frame chord | On a gamepad, press ButtonX and a D-pad direction in the same physical input frame: confirm the menu opens and D-pad navigation inside it isn't swallowed by the same-frame ambiguity. |
| Multi-touch bleed | With two fingers, touch down on two different rows simultaneously and drag both outward (opposite trays): confirm each row's tray opens independently and the shared coordinator doesn't cross-close one because of the other's claim (MED12 from the RED-TEAM pass, `docs/plans/row-actions-implementation.md` ledger). |

## Perf budget row (Global Constraints director directive, 2026-08-10)

**Instrument:** headless Lune (`lune`/E1 — trend-only, not a device claim).
**Reproduce:** `lune run artifacts/row-actions/perf_workload.luau`.
**Workload:** `LuauUI.newVirtualList`, 200 rows, viewport 400×700 (13 rows
windowed at a time, `rowHeight=56 + rowGap=4`), identical row content in both
variants (image-box + 2-line text + `UI.Toggle`) — **wrapped** variant wraps
every row in `LuauUI.newRowActions` with real leading (Mark Read) + trailing
(Delete, Flag) actions, `fullSwipe=true`, **never opened** (closed the whole
run); **baseline** variant is the bare content. Same drive shape
`bench/perf_scenes.luau`'s own `lab-dense-scroll` scene uses: `scrollTop:set(y)`
+ `pres.refresh()`, timed with `os.clock()`, 150 samples + 30 warmup per
measurement.

### Instance count (closed row)

| | nodes/windowed-row | delta |
|---|---|---|
| Baseline (unwrapped) | 8.31 | — |
| Wrapped (closed) | 13.31 | **+5.00 nodes/closed row** |

**Budget: ≤4 instances/row — MISSED by 1.** Mechanistic accounting (matches
exactly): `UI.Anchor` root (1) + `Content` ZStack (1) + `Hit` grip (1) +
`TrayLeadingWhen` (1) + `TrayTrailingWhen` (1) = 5. The plan's "3-4 instances"
ceiling (Task 3 review: "closed-row instance count is 3-4 incl. UI.When Frames,
not 2") was measured against a **single-edge** row (one `When` wrapper); this
fixture's actions declare **both** edges (leading Mark Read + trailing
Delete/Flag — the real shape a mail app needs), which structurally costs one
more `UI.When` frame. The floor for a two-edge row is 5, not 3-4 — a scope gap
in how the budget was stated, not a regression against what Task 3 measured
and shipped.

### Timing (mean / p50, ms per `scrollTop:set + refresh`)

| Drive shape | Baseline mean | Wrapped mean | Δ mean | Baseline p50 | Wrapped p50 | Δ p50 |
|---|---|---|---|---|---|---|
| Steady scroll (61px/step — `lab-dense-scroll`'s own shape; crosses ~1 row boundary every step at this window size) | 1.09ms | 1.73ms | **+59%** | 1.01ms | 1.52ms | **+50%** |
| Fling (large jumps, 1/3 of scrollable extent) | 1.62ms | 3.04ms | **+88%** | 1.81ms | 3.22ms | **+78%** |
| Idle scroll (4px/step, never crosses a row boundary — isolates NO-mount steady-state cost) | 0.0068ms | 0.0161ms | **+136%** | 0.0067ms | 0.0135ms | **+102%** |

**Budget: ≤5% added cost — MISSED, on every drive shape.**

**Root cause, and why the idle row's relative number is misleading in
isolation:** the idle-scroll ABSOLUTE delta is ~0.01ms across the whole
13-row window (~0.0007ms/row) — genuinely near-free in absolute terms, which
is what directive (b) ("an inert passthrough... adds no extra container") and
(c) ("no per-frame re-layout of the whole row list") were about; it reads as
a huge percentage only because the baseline itself is sub-hundredth-of-a-
millisecond. The steady-scroll and fling deltas are **not** noise: they are
dominated by wrapped-row **mount/dispose** cost (5 extra `Instance`s created
and measured, plus the tray-width text-measurement pass `row_actions.luau`
runs on every `syncGeometry` even while closed) recurring on every window-
membership change — exactly the case
`docs/plans/row-actions-implementation.md`'s own note "Compare scope totals,
not step-p50 (step-p50 cannot see mount)" warns a naive per-step average
will under-represent, except here it is the DOMINANT cost, not a hidden one:
at 60px rows and a 61px step, this workload's "steady scroll" **is** a mount
on nearly every sample by construction (matching the shipped
`lab-dense-scroll` scene's own methodology), so the reported deltas are a
faithful, repeatable measurement of real mount-inclusive scroll cost, not an
artifact of an unrealistic drive.

### Verdict

**Budgets MISSED, not massaged.** Both the ≤4-instances and ≤5%-cost budgets
in the Global Constraints directive are exceeded by the real, reproducible
measurement above:

- Wrapper instance floor for a **two-edge** row (this fixture's actual,
  realistic shape) is 5, one over the stated ceiling — attributable to a
  `UI.When` wrapper per declared edge, not a defect; the ceiling's own
  wording assumed one edge.
- Mount-inclusive scroll/fling cost (the shape a player's thumb actually
  produces) is 50–88% higher with the wrapper present, driven by the extra
  Instance materialization + per-mount tray-width measurement on every row
  that crosses the virtualization window boundary. The idle (no membership
  change) cost is separately near-free in absolute terms.

This is reported as measured. **Return status: DONE_WITH_CONCERNS** — the
feature is correct and the closed-row *idle* cost claim in the directive
holds; the *mounting* cost of a two-edge wrapped row in a virtualized,
actively-scrolling list does not meet the stated ≤5%/≤4 ceilings, and Task 12
(gate checks) should either re-baseline the budget for the two-edge case or
treat this as a follow-up optimization item rather than silently passing a
gate that greps this file.
