# T15 — the Studio capture plan the controller runs

**Status:** ready to run. Nothing below has been captured; the whole of it is the
controller's, because it owns Studio. This file exists so the session is a
sequence of named steps rather than a set of remembered intentions.

**Verified before this plan was written** (wave T15, headless half):

| what | how it was verified |
|---|---|
| the place builds from current source | `python3 tools/check_perf_place.py` — PASS, 17 required instances, 5 version markers, publish-safe |
| every workload boots, resets, and reproduces its seed | all 17 selected, mounted, every declared pass run, reset, re-seeded; digests identical |
| the scope wrapper is balanced on every exit path | `lune run tests/run_one profile_scopes` — 15 cases including a throwing body, a throwing hook, and nested unwinding |
| the capture metadata schema refuses an incomplete row | `capture.problems` cases in `tests/perf_lab.spec.luau` |
| the derived-summary tool decodes a dump | `python3 tools/microprofiler_aggregate.py --selftest` — PASS; and run against two real device dumps |
| the counter block the row carries is today's runtime | `tests/perf_lab.spec.luau` — the live read and the exported row compared by SET |
| the chapter's workload table is the registry's | `tests/perf_lab.spec.luau` — every id, both directions, and the spelled-out count |

---

## 0. Before Play

1. `python3 tools/check_perf_place.py` — rebuilds `examples/places/Facet-PerformanceLab.rbxl`
   from current source and re-verifies it. Never capture from a place you did not
   just rebuild: the checked-in artifact was **five days stale** when this wave
   opened, and a stale place fails nothing.
2. Open that file in Studio. Do not open the repo through Rojo for a capture run —
   a live sync writes `Source` while you measure.
3. Set the viewport to the profile you intend to claim. A capture row records the
   viewport it was taken at, and two rows at different viewports are not comparable.
4. Press Play. Wait for `[Facet PerfLab] <version> ready` in the output.

## 1. Arm the profiler, and prove it is armed

`Ctrl`+`Alt`+`F6` (Studio MCP can deliver it: `user_keyboard_input`, datamodel
`Client`). Then run the staleness assertion from
`docs/guide/12-performance-lab.md` §12.4 — `GetFrameIdMax` must advance across a
one-second wait. **An unarmed capture still returns a buffer**, and it returns a
stale one, so this step is not optional and it is not a formality: it is the one
failure that produces plausible numbers about a session that never happened.

## 2. Read the module-load memory marks — FIRST, and once

New in this wave and the reason the memory question can be answered on a device
at all:

```lua
step("counters")   -- read `moduleLoad`
```

`moduleLoad` carries `beforeRequireKb`, `afterRequireKb`, `requireCostKb` (all
three from the bootstrap, which is the only code that has a "before") and
`afterFirstMountKb` / `firstMountCostKb` once the first workload has mounted.

**Take it before anything else and do not re-take it.** The first-mount mark is
taken once on purpose: a mark re-taken on a warm heap answers a different question
under the same name. If you need a second reading, restart Play.

Record it against the headless numbers in `requalification.md` §7 — the headless
figure for `require(Facet)` is **~2.80 MB of Lua heap, of which the nineteen
composite controls are 831 KB**. Studio's number is the one that decides whether
the lazy-loading question is worth reopening.

## 3. The ordered capture list

Each row: select, warm up, arm, drive, snapshot, export. `cleanCapture:on` for
every row you intend to compare — a hidden overlay is still a mounted tree the
census counts and the frame pays for.

| # | workload | settings | warm-up | capture window | what the row is for |
|---|---|---|---|---|---|
| 1 | `idle-baseline` | `cleanCapture:on` | 60 frames | 60 frames idle | the floor. Every later number is read against it |
| 2 | `dense-scroll` | `rows=2000,seed=1,content=normal,theme=flat,cleanCapture:on` | `pass:scrollSteady=30` | `pass:scrollSteady=60` | the principal workload, flat |
| 3 | `dense-scroll-native` | same dataset, `impl=native` | `pass:scrollSteady=30` | `pass:scrollSteady=60` | the matched raw-Roblox reference. Exactly one implementation mounts |
| 4 | `dense-scroll` | `theme=fantasy_ornate`, everything else identical | `pass:scrollSteady=30` | `pass:scrollSteady=60` | flat vs the most expensive shipped skin, same dataset and sequence |
| 5 | `layout-style-churn` | default | `pass:preferenceSweep=1` | `pass:themeCost` | install / steady / teardown timed apart |
| 6 | `collection-churn` | `rows=2000,seed=1` | `pass:scrollSteady=20` | `pass:insert=20` then `pass:reorder=20` | do updates stay proportional to changed content |
| 7 | `arrange-shapes` | default | `pass:flat=30` | `pass:flat=60`, then `pass:fill=60` | **the top cost in all four 2026-08-15 device captures.** `flat` is the control; every other arm is quoted against it |
| 8 | `edit-locality` | default | `pass:editOffWindow=20` | `pass:editOffWindowIncremental=60` | **re-capture is owed**: the RR-5 fix in this wave took `edit-locality` from 131 solves to 83 headless. The device has never seen the ON arm |
| 9 | `host-move` | default | `pass:hosted=20` | `pass:hosted=60`, then `pass:unhosted=60` | ADR-0032's standing risk: is the write collapse a frame-time win |
| 10 | `variable-extents` | default | `pass:extentArms=6` | `pass:extentArms=60` | **re-capture is owed**: the same fix took this from 294 solves to 246 |
| 11 | `large-text-overflow` | `content=identity` | `pass:preferenceSweep=1` | `pass:revealAudit` | bounded measurement, disclosure and motion |
| 12 | `async-image-churn` | `resourceState` per pass | `pass:imagesWarm` | `pass:imagesReuse=60` | **`imagesReuse` is the only arm a capture can contain** — the other three are one-shot state changes and a dump of them is 29 identical frames |
| 13 | `lifecycle-soak` | default | none | `pass:soak=12` | do Instances, connections, memory or stale work trend upward |

Rows 8 and 10 are the two this wave changed. They are the only two where a
before/after comparison against a stored capture is meaningful, and the stored
"before" is `artifacts/performance-stress-places/device-capture-2026-08-15.md`.

## 4. Expected counters, per row

Read `step("counters")` at every row and put it beside the dump. What must hold:

- `mountedRows` <= `windowBound`, always. A virtualized workload that mounts the
  whole collection fails the lab's own assertion at mount, so if you got this far
  it held — record it anyway, because the number is what makes the claim readable.
- `render.solves` — **the counter this wave moved.** Rows 6, 8 and 10 should show
  fewer solves than the 2026-08-15 captures for the same arm at the same n.
- `render.textMeasureBatches` — the text-measure batch count. Should be flat during
  a steady scroll.
- `haptics` — `built`, `pooled`, `plays`, `coalesced`. **`built` must be flat across
  a whole scroll**: the adapter is event-driven and pools one Instance per distinct
  sensation, and a rising `built` is the per-frame allocation defect the counter
  exists to catch. Drive `select:haptics=on` for at least one row.
- `text.pending` — false at the moment of the snapshot. A capture taken while a
  premeasure round is in flight is measuring a surface still deciding its type sizes.
- `moduleLoad` — §2 above, once.
- `core` — signals/memos/observers/effects/scopes. Compare the soak's first and last
  cycle; a monotone climb is the finding.

## 5. Deriving the summary

```bash
python3 tools/microprofiler_aggregate.py <dump.html>
python3 tools/microprofiler_aggregate.py --layout <dump.html>
```

Two things to know, both fixed or found in this wave:

- **Scope times are INCLUSIVE and they nest.** A solve driven from inside an
  observer runs `measure`/`arrange`/`commit` within `Facet/react`, so summing the
  bars double-counts. Compare one phase against itself across two captures.
- **Dumps taken before 2026-08 carry `LuauUI/*` scope names**, which is the whole
  existing corpus. The tool now reads both prefixes and says which it found; before
  this wave it printed an empty table for every one of them, which reads exactly
  like "the framework did no work".

`--layout` is the half no `Facet/*` scope can answer: the engine's own
`Relayouts`/`Updates`/`Resizes` accounting. It is what showed on 2026-08-17 that a
nested host RE-ATTRIBUTES descendant relayout rather than removing it, and it is
how row 9 gets judged.

## 6. Where results go

- the raw dump: keep it. It is the primary artifact and it is irreproducible.
- the derived summary: `artifacts/performance-stress-places/device-capture-<date>.md`,
  in the shape of the two that exist.
- the capture ROW: `step("export:1")` refuses a row missing any condition —
  `"unknown"` counts as missing. Land it in
  `artifacts/performance-stress-places/studio/` through the `studio_sync` bridge
  (§12.3) rather than transcribing it, then `python3 tools/check_perf_captures.py`.
- the requalification artifact's Studio and device rows:
  `artifacts/release-candidate-review/perf/requalification.md` §5 and §6, which are
  written as explicitly open and name this file.

## 7. The one thing that is not in this plan

**The low-end Android capture.** It is a different instrument (a web UI served by
the phone, `Save to file`, no `.gprx`), it is the only measurement that can close
the device budget, and its procedure is `docs/guide/12-performance-lab.md` §12.5 —
verified current in this wave and unchanged. Until that row exists the honest
statement is *automation complete, low-end performance not proven*, which is what
`bench/perf_budgets.json` already declares by carrying `measured: false` on all
three device budgets.
