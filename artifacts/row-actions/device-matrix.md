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

**CAPTURE STALENESS (director device round, 2026-08-12).** The functional-matrix
tray captures below **predate icon-first**: they show tray plates wearing WORDS
("Delete" / "Flag"), and a tray plate now wears its icon at every width when the
action declares one (api.md `ActionSpec.icon`). Tray gutters
(`controls.rowActions.trayGap`) are likewise absent from them. **Re-capture is a
device-pass item**, not a blocker for this matrix's claims: the layout,
diagnostic, swipe/commit and reorder mechanics the functional rows assert are
unchanged, and the **perf numbers are unaffected** (no node was added or removed
by the change — same instance count, same tray structure, one extra solved gap).

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
| Re-capture tray visuals | Re-take the tray captures on any view: they predate icon-first trays + the `trayGap` gutter (2026-08-12 director device round) — the current captures show word plates with no gap; confirm glyph plates with the theme's `space.xs` gutter and update the capture set. |
| Icon-action announcement | Accessibility rider (api.md ActionSpec.icon): an icon-first tray plate carries NO engine `Text`, so the action's semantic name reaches the player only through the Shift+Return/long-press menu row — resurface this when the platform-wide `Button.label` screen-reader question is next opened. |

## Perf budget row — RESTORED (row-actions-hosted-mode-plan Task 7/8, 2026-08-12)

**Status: budget RESTORED.** The `row-actions-hosted-mode-plan` (Tasks 1-7)
replaced the manual per-row `newRowActions` wrap this section originally
measured with a **solver-hosted** integration (`VirtualList`/`Table` take
`spec.rowActions` directly; a closed row mounts no `Hit` grip, no gesture
engine, nothing beyond the tray `When` scaffolding). Task 7 re-measured that
hosted integration with a de-biased harness and found its real cost is small
enough to sit back inside the plan's *original* ≤5%/≤5% budget, so Task 8
restores it as the live ceiling (tightened on the instance side — see below).
The 2026-08-10 numbers below (manual per-row wrap, pre-hosted-mode) are kept
as a **superseded** historical record, not erased, but they are no longer
what ships: every consumer of `newRowActions` today goes through the hosted
path.

**Instrument:** headless Lune (`lune`/E1 — trend-only, not a device claim).
**Reproduce:** `lune run artifacts/row-actions/perf_workload.luau`.
**Workload:** `LuauUI.newVirtualList`, 200 rows, viewport 400×700 (13 rows
windowed at a time, `rowHeight=56 + rowGap=4`), identical row content in
three worlds built from one item set — **baseline** (plain rows, the
budget's denominator), **hosted** (`spec.rowActions = actionsFor`, the
blessed integration, all rows closed the whole run), and **legacy**
(the old manual per-row `newRowActions` wrap, measured against its own
freshly built `baseline2` denominator, kept purely informational — nothing
in the shipped framework builds this shape anymore).

**Methodology — why the numbers below are ≥5-run means, not a single run.**
An A/A control (both worlds built plain, true delta zero by construction) on
the *committed one-pass* harness — build baseline, measure it in full, then
build and measure the other world — showed a systematic **second-world
schedule bias of roughly +1 to +6 percentage points** (3 runs: steady mean
bias +1.31pp, fling +5.63pp, idle +1.98pp; allocator/GC state accumulated by
the first world's 150+30 samples is paid by whichever world goes second).
A ≤5% ceiling read off a one-pass A/B is a coin flip, not a gate.

The fix is **ABBA interleaving**: each world is measured in two blocks of 75
samples run in the order base → other → other → base, so each world takes
one "leader" slot and one "follower" slot and a monotone drift over the four
blocks cancels to first order. An earlier **ABAB** cut (other → base → other
→ base pattern per pair) was tried first and still left one world second in
both pairs; its own 3-run A/A control measured a *one-sided* residual of
+1.15pp fling / +2.57pp steady. That round's hosted fling mean (+1.75%, 3
runs) reading *below* the final ABBA mean (+2.83%, 5 runs) is **not**
evidence the ABAB schedule bias suppressed ("flattered") the hosted delta —
that mechanism runs backwards. The ABAB residual itself was estimated from
only 3 A/A runs and carries substantial sample variance of its own (the
final ABBA per-run sd is 0.96-2.90pp); a 3-run mean landing ~1pp below a
later 5-run mean is ordinary small-sample noise riding on that residual's
own variance, not a directional effect. ABBA's own 6-run A/A control
measured the residual much tighter: steady **-0.01pp**, fling **-0.24pp** —
recorded beside every mean below.

Per-run sd on the ABBA harness is 0.96pp (fling) to 2.90pp (steady), so a
single run is not a result — **the budget is called on ≥5-run means, always**
(single-run swings of ±2-5pp on identical code are expected and are not a
regression signal by themselves).

### Current numbers (hosted, ABBA, 5-run means — 2026-08-12, this machine)

| Drive shape | Baseline (avg) | sd (hosted) | Hosted (5-run mean) | min / max | A/A residual (6 runs) | Budget |
|---|---|---|---|---|---|---|
| Steady scroll (61px, ABBA) | ~1.10ms | 2.90 | 1.10ms (-0.28%) | -4.07 / +3.86 | -0.01pp | ≤5% — **PASS** |
| Fling (1/3 scrollable extent, ABBA) | ~1.60ms | 0.96 | 1.64ms (+2.83%) | +1.60 / +4.06 | -0.24pp | ≤5% — **PASS** |
| Idle scroll (4px, no boundary churn) | — | 17.26 | +23.04% (informational) | +3.76 / +43.90 | -6.15pp | not budgeted — noise-dominated, see below |
| Wrapper instances/closed row | — | 0 | 0.08 | 0.08 / 0.08 | — | ≤1 — **PASS** |
| Legacy steady (informational, own baseline2) | — | 6.98 | +46.28% | +39.47 / +57.85 | — | not budgeted |
| Legacy fling (informational, own baseline2) | — | 14.42 | +91.46% | +69.37 / +104.67 | — | not budgeted |
| Legacy instances/closed row (informational) | — | 0 | +5.00 | 5.00 / 5.00 | — | not budgeted |

**Reading it plainly:** hosted steady is indistinguishable from zero (-0.28%
mean, sd 2.90, against a -0.01pp A/A residual — well inside the ≤5% ceiling
with no measurable regression). Hosted fling is a small but real positive
cost — all 5 hosted fling runs landed positive (+1.60..+4.06) while the 6-run
A/A control straddles zero (-2.87..+2.72, mean -0.24) — attributable to
per-mount work on the row `Hit` (the `rowActions(item)` call plus the four
handler props wired on each newly-mounted row, since a fling remounts the
whole virtualization window). Net of the A/A residual the true fling cost is
~+3.1%, i.e. **headroom against the ≤5% ceiling is ~2pp (~2 standard
deviations)** — real margin, not a coin flip, but not a wide one either.
Idle-scroll is per-step noise on top of a sub-hundredth-of-a-millisecond
baseline (A/A control alone swings -41.80..+23.25pp on identical worlds) and
is deliberately **not a budget line** for that reason, though hosted idle
was positive in 5/5 runs where the A/A mean was negative, so there may be a
genuine ~1us/step cost (a shared overlay `When` re-evaluated per refresh)
worth a targeted look someday — not gate material.

**Instance ceiling tightened to ≤1, not restored to the plan's original ≤4.**
The hosted design's own closed-row cost is integer-deterministic at
**+0.08 nodes/windowed-row** (200 rows / 13-row window; a fractional per-row
average because the overlay adds exactly one `RowActionsOverlay` instance to
the whole list, not one per row — see the identity differential in
`.superpowers/sdd/row-actions-hosted-mode-plan/task-5-report.md`). A design
that should never need more than a small fixed number of extra instances for
a whole list gets a far sharper regression detector at ≤1 than at ≤4 — any
future change that starts materializing per-row wrapper instances again
(regressing toward the legacy shape) trips this ceiling immediately instead
of getting 12x of slack to hide in. Two independent review rounds on this
task both specified ≤1 over the plan's ≤4 for exactly this reason.

**Full raw data (all 5 ABBA runs + the 6-run A/A control + the superseded
one-pass and ABAB rounds):**
`.superpowers/sdd/row-actions-hosted-mode-plan/task-7-report.md` §§0, 2, 6-8.

---

## SUPERSEDED — 2026-08-10 numbers (manual per-row `newRowActions` wrap, pre-hosted-mode)

Kept for the historical record. These numbers measured the **old** consumer
shape — every row manually wrapped in `LuauUI.newRowActions`, a 5-instance
composite whether or not the row was ever touched — which the
`row-actions-hosted-mode-plan` replaced. They are **not** read by
`tools/check_row_actions_matrix.py` (the check's regexes match the "Current
numbers" table above, which appears first in this file); they no longer
describe what ships. The `legacy` world in the current workload measures
this same manual-wrap shape as an informational reference (see the table
above), so this history is also independently reproducible today.

### Perf budget row (Global Constraints director directive, 2026-08-10)

**Workload (as it existed then):** `LuauUI.newVirtualList`, 200 rows,
viewport 400×700 — **wrapped** variant wraps every row in
`LuauUI.newRowActions` with real leading (Mark Read) + trailing (Delete,
Flag) actions, `fullSwipe=true`, never opened; **baseline** variant is the
bare content. One-pass drive shape (not yet ABBA-interleaved).

#### Instance count (closed row)

| | nodes/windowed-row | delta |
|---|---|---|
| Baseline (unwrapped) | 8.31 | — |
| Wrapped (closed) | 13.31 | **+5.00 nodes/closed row** |

Mechanistic accounting: `UI.Anchor` root (1) + `Content` ZStack (1) + `Hit`
grip (1) + `TrayLeadingWhen` (1) + `TrayTrailingWhen` (1) = 5 — the per-row
composite the hosted design's `+0.08`/list replaces.

#### Timing (mean / p50, ms per `scrollTop:set + refresh`, one-pass)

| Drive shape | Baseline mean | Wrapped mean | Δ mean | Baseline p50 | Wrapped p50 | Δ p50 |
|---|---|---|---|---|---|---|
| Steady scroll (61px/step) | 1.09ms | 1.73ms | **+59%** | 1.01ms | 1.52ms | **+50%** |
| Fling (1/3 scrollable extent) | 1.62ms | 3.04ms | **+88%** | 1.81ms | 3.22ms | **+78%** |
| Idle scroll (4px/step) | 0.0068ms | 0.0161ms | **+136%** | 0.0067ms | 0.0135ms | **+102%** |

At the time this was measured against the plan's original ≤5%/≤4-instance
budget it MISSED on every shape (per-row manual wrap, one-pass harness, no
ABBA de-biasing). Full narrative kept from the original write-up:

**Root cause (as understood then):** the idle-scroll absolute delta was
~0.01ms across the whole 13-row window — near-free in absolute terms — but
read as a huge percentage because the baseline was sub-hundredth-of-a-
millisecond. Steady-scroll and fling were dominated by wrapped-row
mount/dispose cost (5 extra `Instance`s created and measured per row that
crosses the virtualization window boundary, plus a per-`syncGeometry`
tray-width measurement pass even while closed).

### Task 11b (director-mandated perf follow-on, 2026-08-10) — investigation + one fix shipped

Full writeup: `.superpowers/sdd/row-actions-implementation/task-11b-report.md`.

**Finding:** `row_actions.luau`'s own reactive-graph construction was NOT
the dominant cost (~2% of the measured delta); ~98% was the shared
renderer/solver's cost of creating, measuring, and destroying the wrapper's
5 extra `Instance`s on every virtualization window-membership change — the
Instance count was the lever, not the reactive graph.

**What shipped then:** `ensureKeysContext()` used to build a real
action-system context unconditionally at MOUNT for every windowed row, only
to `setEnabled(false)` immediately after. `syncKeysEnabled` was changed to
build the context only once real focus actually enters the row. Zero
behavior change; the scroll-only workload's numbers moved within noise
(this benchmark never focuses a row, so it couldn't exercise the win).

**Numbers as they stood then (mean, ms/refresh, one-pass, `17719bc`):**

| Drive shape | Baseline | Task 11 (before) | Task 11b (after) | Budget (then) |
|---|---|---|---|---|
| Steady scroll (61px) | ~1.10ms | 1.73ms (+59%) | 1.75ms (+57%) | ≤5% — FAIL |
| Fling | ~1.60ms | 3.04ms (+88%) | 3.01ms (+81%) | ≤5% — FAIL |
| Idle (no boundary churn) | ~0.008ms | 0.016ms (+136%) | 0.018ms (+102%) | informational |
| Wrapper instances/closed row | — | 5.00 | 5.00 (unchanged) | ≤4 — FAIL |

**Return status then: DONE_WITH_CONCERNS, floor reached.** Closing the gap
was judged to need either a `VirtualList`-level gesture-composition hook (so
a hosted `newVirtualList` + `rowActions` pairing could skip the `Hit` grip
the way a `reorderable` Table row already does) or generic cell recycling —
both out of that task's scope, chartered as `docs/plans/row-actions-perf-mission.md`.
**That is exactly the shape the `row-actions-hosted-mode-plan` then built**:
the current numbers above are that gesture-composition-hook mission's
result, measured and shipped.

### Task 12 resolution (director ruling 2026-08-11) — interim re-baseline, now superseded

Between the MISSED 2026-08-10 numbers above and the hosted-mode fix, the gate
(`tools/check_row_actions_matrix.py`) was re-baselined to the numbers Task
11b actually shipped (steady ≤57%, fling ≤81%, ≤5 wrapper instances) as an
**interim** ceiling — a real future regression above the then-shipped shape
would still fail, but the plan's original ≤5%/≤4 budget was tracked
separately rather than left permanently red. That interim ceiling is what
Task 8 (2026-08-12) replaces with the restored ≤5%/≤5%/≤1 budget above, now
that the hosted-mode plan has landed the fix this section's own
recommendation called for.
