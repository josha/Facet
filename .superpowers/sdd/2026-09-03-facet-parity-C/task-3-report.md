# Task 3 (C1 steps 0-11) report — a host is a coordinate space

Base `22897aac` on `facet-parity`. RascalRally step-0 commit `e3bfc45` on `main`.

## What

A container whose placement is REACTIVE (`offsetX`/`offsetY`/`anchor` in
`dynamicProps`) and that has children is now a real engine parent AND the origin
its subtree's rects are STORED against. A 250-plate nameplate tick costs **250
stored rects and 250 engine writes instead of 1,500 of each**; on the shipped
Rascal Rally minimap a dots-only frame costs **8 rect writes instead of 48**.
Every public read — `controller.rectOf`, `controller.screenRectOf`, the engine
position the adapter composes, the focus record, the diagnostics — is unchanged,
which is what the five-arm oracle and the RascalRally literal contract say.

Steps in the brief's order:

- **Step 0 (RR literals, before any `src/` edit)** — RR
  `tests/facet_translate_host_contract.spec.luau`, committed on its own at
  `e3bfc45` (3578/0). The minimap dot / its hit button / its name tag, the compact
  `Ticker` strip and its entry plate, the `StartCountdown` box and its numeral,
  each pinned to the value read off the run at RR `07d1a18` + Facet `a46f84c4`;
  `hostCount()` 0 and the 48-write frame recorded as the before column.
- **Step 0b** — TAKEN, though R-14's trigger said it would not be:
  `src/render/dirty_closure.luau` (`dirty_closure.of(dirty) -> (contains,
  measures)`), a pure function of its argument, with
  `tests/dirty_closure_seam.spec.luau` (9 cases, each source rule with a negative
  control). See "Deviations".
- **Step 1** — the reader-audit table is in the ledger
  (`progress.md`, "### Task 3 — reader audit"): 21 rows, one per reader the plan
  names, with its verdict and its pin. The `contentRect`/viewport grep the brief
  asks for found nothing new (`contentRect.` appears only in `solve`'s own root
  setup; `text_audit`'s `viewports` are the hand-built maps that have no live
  producer).
- **Steps 2-9** — as the brief specifies; the three places where measurement
  contradicted the plan are in "Findings" below.
- **Step 10** — RR acceptance gate: every step-0 literal unchanged, plus the new
  facts (every dot is a host, `hostOf(dotHit).path == dot`, `hostCount()` 8, the
  composed-rect identity, the 8-write frame).

## Reader audit

In the ledger under **### Task 3 — reader audit** (21 rows). Summary: 12 readers
compose automatically because they read through `controller.rectOf` /
`screenRectOf` / the pointer contract (which `renderer.luau` supplies as
`screenRectOf`); 3 are same-space-by-construction and pinned
(`presentation_channel`, `selection_indicator`, `rect_pass.applyOne`); 5 had to
learn to compose and are edited here (`restoreParkedProps`, `hit_lift.refresh`,
`commit_walks.authorPressableRects`, `surface_overlap.coverRect`,
`scroll_into_view`); and the 3 ABSOLUTE readers are served as R-13 says
(`composition_resolve` by the origin carry, `large_text.auditRects` and
`layout/dump.luau` at their producers).

Two readers the audit did NOT anticipate turned up as failures and are recorded
as rows in spirit: **`tests/lib/overflow_guard.luau`** (every containment,
overlap and clip rule in the sweep compares a node against an ANCESTOR's box) and
a family of test-side raw `adapter.node(path).rect` reads. Both are served by one
one RULING, recorded in the ledger under "the fake target's `rect` ruling":
**`node.rect` is the WINDOW-space rect on both targets and `node.storedRect` is
exactly what the renderer handed `setRect`** (same split for `hitRect` /
`storedHitRect`). `adapter.composedRect(path)` is the explicit name for the
first. Leaving `node.rect` host-relative would have made the suite's most-used
instrument mean something different depending on whether an ancestor happened to
carry a reactive offset.

## TDD evidence

**RED** (`tests/translate_host.spec.luau` written first, run at the T2 HEAD):

```
$ lune run tests/run_one translate_host
  ✗ a pure tick writes one rect and one engine Position per plate
      expected rectWrites=1500 engineWrites=1500 solves=1 to be rectWrites=250 engineWrites=250 solves=1
  ✗ a caster tick adds exactly the Cast bars' writes
      expected rectWrites=1500 engineWrites=1550 solves=1 to be rectWrites=300 engineWrites=300 solves=1
  ✗ a ScrollView with a reactive offsetX is a host but NOT a coordinate space
  ✗ a clipChildren container with a reactive offsetY is a host but NOT a coordinate space
  ✗ a reactive placement is the fifth trigger on a CONTAINER and never on a leaf
      expected box=false leaf=false to be box=true leaf=false
5 failed, 0 passed
```

**GREEN**, 14 cases: the two counter demonstrators, the three trigger/refusal
cases, and one pin per reader in the audit that had to change —

```
$ lune run tests/run_one translate_host
14 passed
$ lune run tests/run_one host_space_oracle
5 passed
$ lune run tests/run_one host_move_write_cost
10 passed        (6 absolute-scheme controls + 3 coordinate-space fixtures + the double-register OR)
$ lune run tests/run_one dirty_closure_seam
9 passed
```

The four HEAD literals in `translate_host.spec.luau` were read off a throwaway
probe at the T2 HEAD before any `src/` edit (`x=265,y=375,w=61,h=16` for plate 7's
`Name`, both reads) and are unchanged after.

## Findings — three places where measurement contradicted the plan

Full write-ups in the ledger under **### Task 3 — findings that changed the plan's
own mechanism**. In short:

1. **R-13 does not make a Composition exact under a MOVING host.** The origin
   carry is exact only where the composition is re-entered, and under a
   coordinate space a host's move re-bases nothing, so both the arm and the
   ordinary arrange SKIP pass. Measured 7px wrong after one slide. Fixed with
   `Ctx.spaceStack`/`spaceCompositions`/`noSkipDepth`: every space host above a
   composition is marked on the arrange walk and carried in the work record, and
   such a host suspends the skip and the arm for its own body.
2. **The `hostSpace` stamp cannot live only in `ensureTree`** — `layout_node` can
   build first (a re-solve from inside a settle reaches rows whose handles do not
   exist yet). Instrumented directly on a card rail. This was the single cause of
   ~50 of the 88 first-run failures. Fixed by asking the ONE predicate at both
   sites, memoised on the mounted node by `instance_boundary.createOptsFor`.
3. **`adopt` never re-resolved `handle.instanceHost` for the new path**, on both
   adapters (the live one wrote it only when the new path HAS a host). Latent
   before this task; caught by the oracle's `pos == sro` identity, which is
   exactly the instrument that clause exists for.

And one consequence worth naming: **`hitRects` stopped walking a moved subtree**
(1,503 → 253 on the 250-plate fixture). It was the one walk that "never prunes a
move by construction"; under a coordinate space a moved plate's descendants do not
move in their own space, so plain entry identity stops it.

## Files

Facet `src/`:
- `src/render/instance_boundary.luau` — the fifth trigger, the ScrollView /
  `clipChildren` / `translateHosts` refusals, `CreateOpts.hostSpace`, the memo
- `src/render/renderer.luau` — `RendererAttachOpts.translateHosts`; the
  `ensureTree` stamp; `livePaths`' `space` thread filling
  `geometry.hostSpaceOf`/`spaceHosts`; `clearHosts`/`invalidateOrigins`/
  `dropPath` at the writers; the cross-space guard in `restoreParkedProps`; the
  `originOf`/`hostOriginOf` split across the four composers
- `src/render/rect_reads.luau` — `setCommitRects`/`commitOriginOf`; the four
  orphaned review codes reworded (T1 debt, `check_comment_codes` now PASSes)
- `src/render/layout_node.luau` — `hostSpaceOf` through the same predicate;
  `newStore(reuse, attachOpts)`
- `src/render/dirty_closure.luau` (new) — step 0b
- `src/render/rect_pass.luau`, `hit_lift.luau`, `commit_walks.luau`,
  `surface_overlap.luau`, `scroll_into_view.luau` — the composers
- `src/layout/solver.luau` — `Node.hostSpace`; `Ctx.spaceOX/spaceOY`,
  `spaceStack`, `spaceCompositions`, `noSkipDepth`; `arrange` → `arrangeBody` +
  the wrapper; the origin rebind; the arm's empty-run branch; the shifted origin
  numbers at the arrange-time `composition_resolve.resolve`
- `src/layout/dump.luau` — `nodeDump`'s two-number accumulator
- `src/client/screen_presentation.luau` — `registerHost`'s fifth argument and its
  reuse-path OR; the one `hostOriginOf(handle)` local at the three sites; the
  "THE INSTANCE TREE IS FLAT" prose
- `src/client/screen_target.luau` — the fifth `registerHost` argument; the
  five-trigger prose; `setRect`'s `movedHosts` guard; the `elided` note;
  `adopt`'s unconditional `instanceHost`
- `src/controls/selection_indicator.luau` — the cancellation argument extended to
  a coordinate-space host (one paragraph, pinned)
- `docs/reference/api.md` — `translateHosts` documented

Facet tests/tools: `tests/translate_host.spec.luau` (new),
`tests/host_space_oracle.spec.luau` (new), `tests/dirty_closure_seam.spec.luau`
(new), `tests/lib/nameplates_scene.luau` (`Opts.hosts`, the extended
`snapshot()` with the `pos == sro` identity, `publicSnapshot()`),
`tests/lib/fake_target.luau` (`hostSpace` through `registerFakeHost`, the
`_composePresentation` chain, the subtree recompose on a space-host `setRect`,
`adopt`'s host, `composedRect`), `tests/lib/large_text.luau`,
`tests/lib/overflow_guard.luau`, `tests/host_move_write_cost.spec.luau`,
`tests/instance_hosts.spec.luau`, `tests/translate_arm.spec.luau`,
`tests/nameplates_baseline.spec.luau`, `tests/commit_translate.spec.luau`,
`tests/commit_dirt_classes.spec.luau`, `tests/engine_writes.spec.luau`,
`tests/node_reuse.spec.luau`, `tests/commit_walks_seam.spec.luau`,
`tests/scroll_into_view_seam.spec.luau`, `tests/redteam_closing_round.spec.luau`,
`tests/table.spec.luau`, `tests/playlist_columns.spec.luau`,
`tests/anchored_surface.spec.luau`, `tests/run.luau`,
`tools/lune/check_elision_census.luau`,
`tools/lune/verify/data/source-cap-ledger.md`.

RascalRally: `tests/facet_translate_host_contract.spec.luau`, `tests/run.luau`.

## Gates

| gate | result |
|---|---|
| `lune run tests/run` (Facet) | **8328 / 0** (was 8293 at base; +35 net new cases) |
| RascalRally `./run-tests.sh` | **3580 / 0** (was 3575 at base; transcript `task-3-rr-suite.txt`) |
| `stylua --check src tests tools bench examples` | CLEAN |
| `python3 tools/check_source_size.py` | PASS — `solver.luau` 191,195 → **197,445** (2,555 to the cap), `renderer.luau` 194,497 → **196,359** (3,641 to the cap); both ledger rows re-recorded |
| `python3 tools/check_brand_drift.py` | PASS |
| `python3 tools/check_comment_codes.py` | PASS — 0 orphans (was **4** at base: Task 1's `IM-9`/`IM-8`/`BL-5` in `rect_reads.luau`, reworded to plain reasons here) |
| `lune run tools/lune/check_elision_census` | PASS — flat 142/61/81 **unchanged**; new `TRANSLATED` fixture 62 creates / 1 elided / 61 GuiObjects, read off the run: one Frame per moving container |

Numbers the campaign is about, measured on the 250-plate nameplate fixture:

| a pure tick | before | after |
|---|---|---|
| `rectWrites` | 1,500 | **250** |
| `engineWrites` | 1,500 | **250** |
| `hitRects` commit visits | 1,503 | **253** |
| cumulative `rectWrites` over mount + 2 ticks | 4,502 | **2,002** |

...and on the shipped RascalRally minimap: `hostCount()` 0 → 8, a dots-only
frame's `rectWrites` 48 → **8**, `hitRects` commit visits 45 → **29**, with every
public read unchanged.

## Mutation evidence — five, all of which bite

| mutation | reddens |
|---|---|
| delete the origin composition in `rect_reads.rectOf` | `host_space_oracle` 4/5, `translate_host` 1 |
| delete the fake's space-host subtree recompose in `setRect` | `host_space_oracle` 4/5 (`POSMISMATCH`), `translate_host` 4 |
| hand `hit_lift.refresh` + `commit_walks` `hostOriginOf` (last frame) instead of the fresh-map `commitOriginOf` | `translate_host` "a hit expander under a MOVED host is composed on the same solve it moves" |
| revert `paintedRectIn` to `hostOriginOf` | `translate_host` "a path leaving its clip box because its host moved is culled on that solve" |
| delete the solver's origin rebind (`if node.hostSpace then rect = ORIGIN_OF(rect)`) | `host_space_oracle` 4/5 |

## Self-review

- **Completeness.** Every step ran. Step 0 and step 10 are two RascalRally commits
  (`e3bfc45`, `b580702`); step 0b was taken; step 1's audit is in the ledger with
  21 rows, each with a verdict and a pin; every `must compose` site is edited;
  both adapters carry `hostSpace` including the reuse-path OR (pinned in
  `host_move_write_cost` in either order); `pos == sro` is asserted as an identity
  inside `snapshot()` and emits `POSMISMATCH`; arm `e` is compared after every
  step on every public column plus `diagKey`; the four HEAD literals are unchanged.
- **Quality.** One predicate decides a coordinate space
  (`instance_boundary.createOptsFor`, memoised on the mounted node) and one
  function decides what an engine Position is relative to
  (`screen_presentation.hostOriginOf`, read at all three sites). No `R-n`/`IM-n`
  codes in any `src/` comment. The fake target's two rect names (`rect` /
  `storedRect`, `hitRect` / `storedHitRect`) are the change stated rather than
  smuggled.
- **Discipline.** T5's maps (`spaceHostHasPath`, `pathHostOf`) are still empty.
  The three deviations are named above and in the ledger.
- **Tests.** Counters and `solves=N` on both demonstrators; five mutations run by
  hand and recorded; the oracle's non-vacuity has three clauses (the fixture
  paints, arm `a` really has hosts, arm `e` really has none, and the two worlds'
  stored rects really differ).

## Concerns

1. **`solver.luau` is 2,555 characters from the 200,000 cap — the least headroom
   it has ever had, and T5 edits it next.** The ledger row is re-recorded with
   TRIGGER: ARRIVED and two named candidates (the SCROLL arrange branch; a small
   one this round found — `noteContainment` → `arrange_reports`, ~1.7 KB, which
   reads only `ctx.hiddenDepth`/`ctx.diagnostics` plus module-level helpers).
   **T5 should take one before it spends any room there.**
2. **Renderer +1,757 against R-14's +1,400 budget** (under the 197,500 STOP line,
   and after taking step 0b plus moving the commit-span origin closure into
   `rect_reads`). The irreducible code alone is ~950 characters; the budget could
   not accommodate it plus any reasoning at this file's register.
3. **`tests/host_space_oracle.spec.luau` is expensive** — five arms x four
   fixtures x nine views x 24 steps. It should almost certainly join
   `tests/lib/tiers.luau`'s fast-tier exclusions; `lune run tools/lune/time_specs`
   was not run for it, and that is the one measurement this task owes.
4. **The fifth trigger is broader than the plan's examples suggest.** Every
   `VirtualList`/`VirtualGrid` row, every `row_actions` content container, every
   `Callout`, `Menu` and gallery chip strip is now a real Frame and a coordinate
   space. The census prices it at one Frame per moving container and the flat
   count is unchanged, but the INSTANCE cost on a long virtualised list is real
   and was not in the plan's budget — worth a device measurement before T10.
5. `tools/verify.sh affected --jobs 1` was NOT run (the full suite, RR suite and
   every individual gate producer were run directly instead, because the suite
   alone takes ~20 minutes and the harness serialises one lune process at a time).
   The gate rows it would spend are the six above.
