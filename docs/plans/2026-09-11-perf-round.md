# Performance round after the four-task landing (2026-09-11)

Scope: audit the perf lab and the headless benchmark against everything that
landed since the last baseline (radial menus and world anchors, the adaptive
distance and gamepad work, Alert, the Picker styles and menu popover, the split
button, plain row hits, the surface-before-class chrome rule), measure the
current state, and take the meaningful lever. Branch `task3-perf` off
`34c1f4cd`.

## 1. Coverage added

| Instrument | Added |
|---|---|
| `bench/perf_scenes.luau` (headless, `lune` class) | `alert-present-dismiss`, `picker-menu-open-close`, `picker-segmented-textsize`, `radial-menu-open-close`; budgets derived the documented way (worst p95 over five repeats x4, floored) |
| `examples/performance/lab/transient_surfaces.luau` (new lab module) | the three open/close fixtures, shared by the scenes above and the lab |
| perf lab workload `transient-surfaces` (nineteenth) | passes `alertPresent`, `pickerMenu`, `radialOpen`; `implementation = "none"`; `SCENARIO_VERSION` unchanged (adding a workload changes no existing workload's steps) |
| `tools/check_perf_scenes.py` | liveness proofs for the four scenes (the surface really presented, the strip really flipped) |
| `bench/perf_budgets.json` | seven budgets tightened after improvements: `lab-dense-scroll` 19.2 -> 6.2 ms, `lab-collection-churn` 12.3 -> 0.9, `navigation-customization` 26.7 -> 7.5, `virtual-list-scroll` 6.8 -> 4.1, `collection-mutation` 4.2 -> 3.2, plus the two new open/close scenes after the fix below. No budget was loosened. |

Still uncovered on purpose: the split button (its popup is the same
`picker_menu` engine the picker scene prices) and the chrome-slot classify rule
(the theme-swap scenes already walk it per node).

## 2. Regression check across the landings

`tools/perf.sh` at three checkouts, two interleaved rounds each, floorAndroid
p50, minimum of the two runs. `pre-radial` = `157b189b`, `pre-tasks` =
`d3160164`, `current` = the merged main this branch starts from.

| scene | pre-radial | pre-tasks | current | cur/pre1 |
|---|---|---|---|---|
| scroll-focus-traversal | 0.045 | 0.070 | 0.070 | **1.56** |
| screen-lifecycle-churn | 1.746 | 1.706 | 1.487 | 0.85 |
| native-scroll-drag | 0.016 | 0.009 | 0.009 | 0.58 |
| every other scene | | | | 0.92 - 1.10 |

The one move is `scroll-focus-traversal`, bisected to `618b4d95` (the adaptive
commit): `focus_graph.setFocus` now calls `recordFocus`, which scans every
group's order (`groupOf`) on each move to remember the last focus per section.
It is 1.6 us per focus move on the host, 25 us per sixteen moves, and left in
place: the section memory is the feature, and the cost is below the budget
floor. A per-scope `pathToGroup` index is the lever if it ever matters.

FacetBench (headless, facet and `_fixture`, S/M/L, `--retry-drift 2`) reads
flat before and after this branch (0.97x - 1.04x on every row, the `_fixture`
control at 0.98x - 1.02x). No arena workload writes a presentation transform,
so the fix below is invisible there by construction. `tools/check.sh` green.

## 3. The lever: a scale-only transform write re-applies one node

Attribution of the two new open/close scenes with a temporary per-node hook on
the reactive core (memo/observer/effect/settle timed by creation site) and
probes around the renderer's refresh stages:

| scene | total | where |
|---|---|---|
| picker-menu-open-close | 4.0 ms | 1.9 ms in **33 `adapter.setProp("transform")` writes on the popover** (~57 us each), 1.5 ms in the picker's present/dismiss observer (mount + solve + commit of the popover), the rest solve/build/rectPass |
| radial-menu-open-close | 4.4 ms | 0.66 solve + 0.64 `layout_node.build` over five solves (the ring animates its sector geometry through the solver, one solve per tick), 0.56 ms in four transform writes on `Rings`, 0.18 hit lift |

Every frame of a `materialize` transition (and every animated scale) writes a
presentation transform whose offset half (x/y/w/h) is unchanged. The live
adapter's `setTransform` re-walked the subtree for it — `recomputePresentationOffset`
plus `applyRect` (whose hit-expander and float-ring writes are unconditional) on
every descendant — and the headless mirror re-composed every node in the tree. A
descendant's composed position reads only the offset half off its ancestors;
scale and rotation are the node's own paint (UIScale child, `Rotation`). Both
adapters now walk the subtree only when the offset half moved; the node itself
is still re-applied (its anchor flips at the first non-1 scale).

Pinned by `tests/presentation_transform_subtree.spec.luau`: the mirror's
recompose count is 1 for a scale-only write and the subtree size for an offset
write, and the live rule is read off `screen_presentation.luau`'s own source.

Headless ABBA (fake mirror), floorAndroid p50 min-of-5, base = `34c1f4cd` with
the same scenes:

| scene | base A | fix B | base A | fix B |
|---|---|---|---|---|
| picker-menu-open-close | 3.118 | **1.452** | 3.227 | **1.424** |
| radial-menu-open-close | 3.713 | **3.184** | 3.723 | **3.205** |

Live: the Showcase picker menu (Choices and filters, keyboard-driven open)
materializes and settles correctly on the new path — popover edge-aligned to the
trigger, rows in place, `GroupTransparency` 0 and the motion UIScale cleared at
rest. The per-frame saving on a device is the subtree walk of every fading
pop-up, radial ring and animated scale; it is not separately measured on
hardware here.

## 4. Studio rows (studio-emulated, host)

`Facet-PerformanceLab.rbxl` built from this branch, Studio 0.736, 1280x719, flat
theme, clean capture on, `transient-surfaces` at 24 reps, `export:1` admissible.
Numbers in `scratchpad/t3_studio_transient_surfaces.json` of the session and here:

| pass | open p50 | open p95 | close p50 | close p95 |
|---|---|---|---|---|
| alertPresent | 4.25 ms | 4.71 | 0.70 | 0.86 |
| pickerMenu | 5.31 | 8.29 | 0.38 | 0.65 |
| radialOpen | 3.46 | 3.86 | 2.58 | 3.15 |

Host frame: RenderCPU p50 2.65 ms, heartbeat 16.8 ms. These are dev-host numbers
and close no device budget; the three physical classes stay `measured: false`.

## 5. Levers booked, not taken

- **Radial open animates through the solver.** Five solves per open/close on a
  six-sector ring (~0.13 ms solve + ~0.13 ms `layout_node.build` each on the
  host). Moving the sector reveal onto the presentation channel (scale/alpha)
  would make the open paint-only; it changes the control's animation
  architecture and was out of this round's scope.
- **`layout_node.build` is a solve-sized cost** on small trees (0.64 of 1.3 ms
  in the radial scene). Plan D made the solve incremental; the build pass is the
  next place the same treatment applies.
- **`recordFocus`'s group scan** (above), if focus moves ever show on a device.
- Physical-device rows for the three transient passes.
