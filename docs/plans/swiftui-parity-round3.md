# SwiftUI parity round 3 — design

The build plan for the mission stated in
[`swiftui-parity-round3-brief.md`](swiftui-parity-round3-brief.md). **The brief is
binding; this document is the design it asked for** — one section per phase, plus
the Phase 0 map every later section rests on.

Round 2's design document is [`swiftui-parity-round2.md`](swiftui-parity-round2.md);
where this document repeats one of its facts, it is because a round-3 decision
turns on it, not as a summary.

---

## Phase 0 — the map, verified in source

Every claim in this section was produced by a tool result in the session that
wrote it, on **2026-08-13**, against `main` @ `ff0c28a`. A claim taken from a
document rather than from source or a live URL is marked as such.

### The baseline this mission moves from

| | |
|---|---|
| Branch / commit | `main` @ `ff0c28a` |
| LuauUI suite | **4638 passed**, green (`./run-tests.sh`) |
| Rascal Rally suite | **3138 passed**, green (`games/RascalRally/code/run-tests.sh`) |
| LuauUI version | `0.9.0` (`src/init.luau`) |
| Working tree at start | three modified files and three untracked paths, all belonging to the **declarative-3D** decision session (`docs/adr/ADR-0024-declarative-3d.md`, `spikes/`, `artifacts/declarative-3d-architecture/`, plus edits to `artifacts/code-simplicity-cleanup/public-surface.txt`, `docs/plans/distribution-readiness.md`, `docs/plans/luauui-consolidated-roadmap.md`). **Not this mission's work**, and not to be swept into this mission's commits |
| Rascal Rally version control | **`games/RascalRally` is not a git repository.** The git root is `GameStudio/ui/LuauUI`. So "commit as you go" (brief rule 6) covers framework work only, and the game-side rider's evidence is protected by the scratchpad backup rule instead |

### Standing rule 3's premise is wrong, and the true state is more interesting

Standing rule 3 says the MicroProfiler instrument has **"never once"** been read.
It has been read twice. But correcting the sentence is not the point — the point
is that establishing *what* has been read turned up a much sharper problem than
the one the brief set out to fix.

**There are three instruments here, not two, and the middle one is load-bearing.**

| | Instrument | What it measures | Has it run? |
|---|---|---|---|
| **A** | `profile.counters()` — Lua-side open/close **counts** | how many times each scope opened; `balanced`; `maxDepth` | **Yes, routinely** — all 18 capture rows carry it |
| **B** | `profile.setHooks` + `os.clock()` around the same twelve scopes | inclusive/exclusive **ms per scope**, call counts, parent attribution | **Yes** — and this is the instrument behind *every* optimisation number the repo has ever published |
| **C** | **LibMP / the real MicroProfiler** — the engine's own timer table over `debug.profilebegin` | true **engine-side** ms per scope | **Yes, twice — and neither run is usable** |

**What instrument C actually produced**, both in
`artifacts/performance-stress-places/studio/perf-lab.json`:

- **2026-08-04, `attributionBeforeFix` (row PL-17)** — the one and only real
  MicroProfiler timing table in the repo. 65 frames of `scrollSteady=60`, mean
  frame 16.65 ms: `arrange` 147.74 ms total / 2.11 mean, `commit` 111.77 / 1.034,
  `mount` 43.73 / 1.214, `measure` 21.21 / 0.303, `scenario` 18.2, `react` 7.06,
  `resource` 0.21, `mutate` 0.04. **Eight scopes of twelve.** Its own key says
  `beforeFix`; the source stamp and the scenario version (`/1` → `/4`) are both
  since superseded.
- **2026-08-05, `microprofilerScopes` (row PL-8)** — all **twelve** `LuauUI/*`
  timers found by mask in a live capture (frames 18132–18387), with engine timer
  ids, `opens == closes == 313541`, `maxDepth: 4`. **Discovery and balance only.
  Zero milliseconds.**

And no capture file has ever been kept: `find` over the whole repo for `*.gprx`,
`microprofile*` and `*.trace` returns **nothing**, and all 18 rows carry
`capturePath: "not captured in this run"`.

> **The verdict line this mission uses.** The MicroProfiler has been read twice:
> once for **timings**, on 2026-08-04, covering eight of twelve scopes at a source
> stamp and scenario version both since superseded; and once for **timer
> discovery and balance only**, on 2026-08-05. **No capture file has ever been
> preserved**, and **`LuauUI/present`, `LuauUI/focusmap` and `LuauUI/tick` have
> never been MicroProfiler-timed at all** — the three scopes that exist precisely
> because they own the frame nobody was measuring.

### …and the corollary, which is the real finding

Everything the repo *believes* about where a frame goes — L-27's "the focus map
was 20 % of every scroll frame", the 78.4 ms → 7.6 ms `focusmap` win, the
0.124 ms idle frame, L-28's themed-recycling numbers — comes from **instrument
B**, whose own source comment says (`examples/performance/lab/perf_lab.luau:2010-2014`):

> "THE HOOKS COST SOMETHING. Two `os.clock()` calls and a table push per scope is
> not free, and the scope counts here run to six figures — so these numbers are
> for **ATTRIBUTION** (which phase, what share), **never for a capture row**."

Instrument B was **wrong twice before it was right** — a stack shared across
threads, and exclusive time accumulated on entry instead of exit
(`optimization-log.md` L-27) — and **both bugs were invisible on leaf scopes.**
It has **never been cross-checked against instrument C.**

> So the honest headline is not "we never read the MicroProfiler". It is: **the
> repo's entire performance model rests on a hand-rolled wall-clock profiler that
> has been wrong twice and has never been validated against the engine's own.**

**That reframes this round's perf work.** The first capture is not "take a
reading we have never taken" — it is a **differential oracle**: drive the same
scene under both instruments and find out whether B has been telling the truth.
That is the highest-leverage single outcome available here, and it is the shape
`docs/lessons/the-solver-already-told-you.md` keeps teaching — an instrument
shipped, and the question it exists to answer never asked.

### Three checks that cannot bite, found while establishing the above

Each is the "instrument nobody runs" class the brief's orchestration rules name,
and each is cheap:

1. **`capturePath` is unenforced.** It is not in `check_perf_captures.py`'s
   `REQUIRED` list, and nothing checks the named file exists. Every row in the
   repo says `"not captured in this run"` and passes. *This is the check that
   would have made "never captured" visible instead of latent.*
2. **There is no schema and no checker for a MicroProfiler timing summary.**
   `check_perf_gate_evidence.py scopes()` reads timer *names* and balance and
   asserts **nothing about milliseconds**. Without one, round 3's capture lands as
   unvalidated prose exactly as the last one did.
3. **`acceptance.md` PL-8 names an artifact that has never existed** —
   `artifacts/performance-stress-places/studio/scopes.json`. The evidence went
   into `perf-lab.json` instead.

Plus two stale docs: `docs/guide/12-performance-lab.md` §12.4 says "a closed set
of **nine** phase scopes" and tables nine (the module declares twelve — it is
stale by exactly `present`/`focusmap`/`tick`, the three that matter most), and
two files point at `docs/guide/09-performance-lab.md`, which is not the filename.

### Hot paths under no scope at all

The same blind-spot class that created `present` and `focusmap` still exists.
Named here so the first capture is read with them in mind, **not** fixed
speculatively — the module's cardinality bound is raised deliberately or not at
all (`src/core/profile.luau:87-90`):

- **pointer/touch input dispatch** — `screen_target.luau:2993`, `:3037`, `:3102`,
  `:3751`. Per input event, includes a pointer-vs-rect walk. A touch-pan capture
  on a device will attribute all of it to `$Script`.
- **the scroll echo path** — `screen_target.luau:3405`, `CanvasPosition` →
  `observeScroll` → `virtual_list.luau:2727` → a full re-solve. This is the
  *entire* dense-scroll workload's entry point and it is outside every scope
  until it reaches `react`.
- **the resource drain loop** — `roblox_resources.luau:63`, a per-frame Heartbeat
  iteration. `LuauUI/resource` covers only the completion.
- **text measurement** — correctly excluded, because `GetTextBoundsAsync` yields
  and `profile.luau` rule 2 forbids a yield inside a span. A deliberate hole, but
  a capture reader must know the text round is invisible.

*The decision rule: take the capture first, and see whether `$Script` outside the
twelve is large. Only then propose a thirteenth name.*

### The headless harness's noise floor, stated before any delta

Standing rule 3 requires the same-arm spread *before* any number that claims an
improvement. Six consecutive **identical** `tools/perf.sh` runs, no edit between
them, each aggregated the way round 2 aggregated (the sum of `phases.total` over
all 100 scene × profile cells). All six returned `status: PASS`.

| | run 1 | 2 | 3 | 4 | 5 | 6 | spread |
|---|---|---|---|---|---|---|---|
| Σ `total.p50_ms` | 42.960 | 44.478 | 43.736 | 44.121 | 42.829 | 43.429 | **3.78 %** |
| Σ `total.p95_ms` | 75.054 | 79.726 | 77.669 | 78.846 | 77.385 | 76.087 | **6.03 %** |

**Two findings, and the second is the one that changes practice.**

1. **The floor has drifted, badly, since round 2.** Round 2's §2.1 recorded a
   same-arm A/A spread of **1.16 %** on this exact aggregate. It is **3.78 %**
   today — 3.3×. Round 2 also recorded a *false signal* produced by exactly this
   drift ("+1.46 %/+2.36 % taken when the same-arm floor had drifted from 0.31 %
   to 1.88 % across a session"). A remembered floor is not a floor. **Re-measure
   the floor in the same session as any delta, or do not report the delta.**

2. **The per-cell floor is far worse than the aggregate, and nobody had looked.**
   Across the 100 cells the **median** same-arm p95 spread is **27.4 %**, and the
   worst cells are wild: `native-scroll-drag` spreads **162–268 %** on every one of
   the five device profiles, `theme-swap-flat` **131–169 %**. The aggregate is
   quiet only because 100 noisy cells average out.

   > **The rule this buys:** a *whole-suite* aggregate can resolve a few percent.
   > A *single scene* cannot resolve anything under roughly 27 %, and
   > `native-scroll-drag` and the `theme-swap-*` family cannot resolve a
   > **doubling**. Round 2 quoted per-scene deltas of +14.3 % / +18.9 % / +22.8 %
   > against stated per-scene floors of 2.9 / 8.1 / 11.2 % — those floors were
   > measured, and they are *scene-specific*, which is the right practice; this
   > table is the reason it is not optional.

**One honest confound, stated rather than buried.** These six runs were taken
while five Opus reconnaissance agents were running on the same machine. That is
real CPU contention, so this is the floor *under load*, not the floor of a quiet
machine — it is an upper bound on the noise, which is the safe direction for a
budget but the wrong number to compare a quiet-machine delta against. **The floor
is re-measured on a quiet machine, in-session, before this mission reports any
delta**, and both numbers are published.

### The environment available to this mission

A Roblox Studio instance named **`Place1`** is connected and empty, offered by the
game director for testing (2026-08-13). It reports `Current Studio Mode: Edit`,
`Available DataModels: Edit`. The standing trap applies and is repeated here
because round 2's evidence was invalidated by it once already: **the Edit
datamodel caches `require()` results**, so anything that must exercise current
source runs under **Play (Client datamodel)**, never Edit
(`docs/plans/device-bug-round-2026-08-12.md`, the re-record procedure, step 1).

---

## Phase 0 verdict — item B decides item A: **flow-wrap is a native arrange branch**

The brief required B (the custom `Layout` protocol) to be *evaluated before* A
(flow-wrap) is built, because B might make A consumer code. It was, and it does
not.

### The decision, and the one reason that carries it

**Build flow-wrap as a native arrange branch in the solver. Record the public
`Layout` protocol as a conditionally-refused future mission, with a named
trigger.**

The reason is not cost, it is that **a public `Layout` would be the first
consumer-authored code ever executed inside the solve**, and the solver's three
newest correctness mechanisms are each sound *only because every input a layout
branch reads is enumerable by reading one file*:

| Mechanism | Where | Why it is an enumeration argument |
|---|---|---|
| the measure memo's cache key | `solver.luau:1647-1666`, `:1019-1063` | the key carries the inputs the computation actually reads, "and no more" — the file says so in those words |
| the incremental-arrange reuse skip | `solver.luau:2500-2539` | sound because "every dimension resolves against the parent's **offer**, which the rect carries" |
| the placement-prop audit | `solver.luau:2084-2087` | returns `nil` — polices *nothing* — for any parent kind not in its fixed table |

A consumer function makes all three unenumerable at once. And each has **already
shipped one real defect from being merely *narrowly* wrong** — the memo's
verdict-replay blocker, the container-key widening, and RED-TEAM HIGH 3. The
third is the sharpest: `auditPlacement` silently polices nothing for an unknown
kind, so every placement prop on a custom layout's children would be
**accepted-and-ignored** — the exact defect class round 2's §2.1 was written to
end, and a direct constitution §4 violation.

Three supporting facts, each verified rather than assumed:

- **SwiftUI ships no flow layout at all.** Apple's live symbol index was searched
  on 2026-08-13 for every node whose title contains "flow" or "wrap": every hit
  is `wrappedValue` / `FileWrapper` / `toolbarOverflowMenu`. SwiftUI's answer to
  flow-wrap *is* "write a custom `Layout`". That is the strongest case for the
  other option, and it loses here because **the gap being closed is a
  Roblox-native gap, not a SwiftUI one** — §4.1's scorecard is against
  `UIListLayout`, and answering a native-parity gap with "write your own layout"
  leaves that row red.
- **Apple built the containers first.** `Layout` is iOS 16 / macOS 13 — three-plus
  years and four major versions after `HStack`. The generalisation *followed* a
  large body of native containers; it did not substitute for them.
- **LuauUI already has the better-shaped answer in this space.** `UI.Composition`
  / `UI.Region` is "closer to a full `Layout` protocol plus `layoutPriority`
  combined than SwiftUI ships in any single construct"
  (`swiftui-parity.md:221`) — and it does it with **frozen, validated data**
  rather than consumer code. Data cannot yield, cannot go stale in the memo, and
  cannot break the reuse skip. If consumer-authored layout power is ever really
  wanted, *extending the declarative surface* is the shape that matches this
  codebase, and that is where the `Layout` mission should start.

**How `Layout` is recorded** — as a conditional refusal with a trigger, matching
the precedent §4.2 and §4.3 already set, never as an open TODO. Trigger: *a real
consumer, outside the repo, wanting a layout the framework does not want to own.*
The seven solver invariants above become that mission's acceptance criteria, to
be satisfied **before it writes a line**.

**One execution note that keeps the door open at zero cost.** The line partition
is written as a **pure function** — `(childMainExtents, innerMain, gap) -> lines`
— cached on `ctx` keyed by node+box exactly as `gridColumnPlan` is
(`solver.luau:664-667`). That is the right shape regardless (it is what makes the
partition headlessly fuzzable, and it is the file's four-times-applied answer to
the "measure and arrange must not disagree" defect class), and it happens to be
the exact internal seam a future `Layout` would need proven anyway.

### Roblox's undefined rule turned out to be defined — measured, not read

Both the brief and `swiftui-parity.md` §4.3 say flow-wrap "needs a cross-axis
line-distribution rule that the Roblox documentation does not define — so LuauUI
would have to define it, and own the divergence". The documentation half is
confirmed: the string `AlignContent` appears **zero** times in the engine API
dump (client `0.734.0.7340915`, 2026-08-10), and neither the `UIListLayout`
reference nor the `list-flex-layouts` guide discusses how wrapped *lines* are
positioned along the cross axis.

**But undocumented is not undefined, and nobody had asked the engine.** Probed
live in Studio on 2026-08-13 — a 300×400 container, six 100×40 items, so three
per line, two lines, 80 px of line extent inside 400 px of container and
therefore 320 px of cross-axis slack:

| `VerticalAlignment` | item `y` offsets | reading |
|---|---|---|
| `Top` (default) | `0,0,0, 40,40,40` | block of lines packed at the start |
| `Center` | `160,160,160, 200,200,200` | block centred — `(400−80)/2 = 160` exactly |
| `Bottom` | `320,320,320, 360,360,360` | block at the end — `400−80 = 320` exactly |

and, with a ragged line (item 2 is 90 tall rather than 40):

| | item `y` offsets |
|---|---|
| ragged | `0,0,0, 90,90,90` |

**Two rules, both now measured facts rather than choices we have to make:**

1. **Lines are packed with no extra space between them, and the whole *block* of
   lines is aligned by the container's existing cross-axis alignment property.**
   There is no separate `align-content`; the property that already exists does
   the job. CSS's `space-between` / `space-around` *between lines* has no native
   counterpart.
2. **A line's cross extent is its tallest item** — the second line starts at 90,
   not at 40. Same rule as CSS, and the same rule LuauUI's flow-`grid` branch
   already uses (`solver.luau:3160`).

**This deletes a design decision instead of adding one.** The reconnaissance
recommended a new cross-axis distribution prop reusing `distribute`'s six-word
vocabulary, defaulting to `start`. The measurement says **no new prop is needed
at all**: LuauUI's existing `align` on an `HStack`/`VStack` *is* the container's
cross-axis alignment, and `lineAlign` (shipped in round 2) *is* per-child
alignment within a line. The engine's three-level structure and LuauUI's map
one-to-one, already:

| Level | Roblox | LuauUI, today |
|---|---|---|
| where the block of lines sits on the cross axis | `VerticalAlignment` / `HorizontalAlignment` | **`align`** |
| where an item sits within its line | `ItemLineAlignment` | **`lineAlign`** |
| where items sit along the main axis | `HorizontalFlex` / `VerticalFlex` | **`distribute`** |

So flow-wrap adds **one prop** — the switch that turns wrapping on — and inherits
its whole alignment story from vocabulary that already ships. That is rung 1 of
the simplicity ladder answering "does it need to exist at all?" with *no*, and it
is byte-identical native parity rather than a divergence LuauUI has to own and
document.

*(A note for the record, since it will otherwise be re-hunted: `FlexAlgorithm` is
**not** a Roblox property — zero hits in the 0.734.0 API dump and zero in this
repo. It entered this mission through a reconnaissance prompt of mine, not through
the brief, and there is nothing to look for.)*

### What flow-wrap must still decide

Two sub-rules the probe does not answer, both to be decided explicitly in the
build and written down:

- **an item wider than the line.** Recommendation: it gets its own line, clamped
  to the line width, and files an overflow diagnostic — the natural sibling of
  the existing message, under the same `hiddenDepth` gate and reuse replay.
- **`stretch` is refused, not silently absent.** `align = "stretch"` already means
  "a child fills its line on the cross axis" (`solver.luau:3463-3465`). Letting it
  *also* mean "lines grow to fill the container" is one word meaning two things —
  the exact ambiguity `lineAlign` was created to end.

And one deliberate **non-goal, stated so it is refused rather than discovered**:
**flow-wrap does not compose with `newVirtualList`.** The virtualizer windows by
`index × pitch` and requires a uniform item extent; a wrapped line has ragged main
extents and a variable items-per-line, so `index × pitch` cannot window it. This
is the same running-offset-index problem §4.2 already declines to solve without a
consumer asking. The combination is refused at construction, naming the conflict.

---

## Phase 0 verdict — item C: the containers do **not** unify, and §13's row is false

### `swiftui-parity.md` §13 says a thing that is not true

The row reads *"No container unifying virtualization + reorder + selection —
**Missing**"*, and the per-row opt-out family is deferred behind it. But
`virtual_list.luau:66-72` says the opposite **in its own header**:

> "THE UNIFIED COLLECTION (ADR-0022 Decision 5). One construct windows, selects,
> reorders and accepts drops at the same time, because the racer-list shape needs
> all four AT ONCE."

All four verified independently: windowing `:1061`, selection `:490-493` / `:726`,
reorder `:547` / `:1090-1106`, drops `:196-198` / `:705-712`. **The blocker that
deferred item C does not exist.** §13's row is rewritten (below), and the family
is unblocked.

### Why the two controls should not merge anyway

Not taste — a recorded, already-deferred gap stands in the way:

- `Table` ships **variable row heights**: `rowHeight` may be
  `number | (item) -> number` (`table.luau:129`, resolved `:371-391`), with a
  whole cumulative-sum `rowTops` model built for it (`:441-452`).
- `VirtualList` **cannot express that.** Its window is `index × pitch`, "O(1) and
  exact precisely BECAUSE the pitch is one number" (`virtual_list.luau:59-65`).
  §4.2 records variable extents as unbuilt, with two candidate designs that each
  give something up, and declines to choose *because no screen wants it*.

So a merged container must either drop `Table`'s variable rows — a behaviour
regression on the shipped playlist example — or solve §4.2 first. Neither is in
round 3's mandate. The second blocker is measured: unifying on `Table`'s
row-actions shape costs **+41–59 % steady / +82–90 % fling / 5.00 nodes per row**
(`row-actions-hosted-mode-design.md:74`) against hosted mode's 0.08.

**Verdict: do not unify.** The duplication that *is* real and worth booking is
**reorder** — two implementations with **contradictory public contracts**:
`Table.onReorder(keys: {string}, toIndex)` is a multi-key block at a **0-based
post-removal** slot (`table.luau:174-179`, `:1148-1169`), while
`VirtualList.onReorder(key, to)` is one key at a **1-based resulting** index
(`virtual_list.luau:1090-1106`). That is a defect a consumer will hit, it is an
API break with its own migration, and **it is booked, not taken here** — taking
it inside item C would repeat the sequencing mistake §13 made in the other
direction.

### §13's row, rewritten to four true ones

| Gap | Verdict | Evidence |
|---|---|---|
| `newVirtualList` refuses `rowActions` + `reorderable` on one list | **Missing**, v1 refusal, scoped | `virtual_list.luau:240-244` |
| `newVirtualList` selection is single-only; no multi-select, no modifier keys | **Partial** | `:490-493` vs `table.luau:2049-2074`, `:2397-2402` |
| `newTable` does not virtualize | **Missing**, blocked behind variable item extents (§4.2) *because* `Table` ships `rowHeight(item)` | `table.luau:1796-1798`, `:371-391` |
| The two `onReorder` contracts disagree in shape | **Confirmed defect**, booked | `table.luau:174-179`; `virtual_list.luau:1090-1106` |

### The edit-mode ⊖ — not a defect, a product decision, and the director took it

The device report was *"in edit mode, tapping delete slides the trailing tray out
instead of deleting the row."* **Traced, not guessed**, to
`row_actions.luau:3343-3375`: the first branch of `handleActivate` matches the
edit-affordance path, finds the first destructive entry, and calls `open(edge)`.
**Nothing on that path ever calls the action's `onAction`.** It is deliberate —
`:3343` says *"the minus never deletes directly — it opens the tray holding the
destructive action"* — and three green tests pin it
(`tests/row_actions.spec.luau:988-990`, `:1023-1030`,
`tests/examples_gallery.spec.luau:1105-1114`, the last one on the very showcase
table the director was using).

**Two things made this a real report rather than a misunderstanding:**

1. **The ⊖ announces itself as "Delete".** Its accessible label is deliberately
   borrowed from the destructive action (`row_actions.luau:3057`,
   *"typically 'Delete'"*). A control that says Delete and does not delete
   manufactures exactly the expectation that was formed.
2. **The design's own justification is uncited.** `:2978` calls the reveal *"the
   iOS pattern"*. Apple documents the ⊖'s **appearance**
   (`UITableViewCell.EditingStyle.delete` — "a red circle enclosing a minus
   sign") and documents that edit mode *"provides controls to delete or move list
   items"*, but **documents no behaviour for tapping it**. Under this repo's own
   §16 convention that is an uncited claim in a source comment — and standing rule
   7 exists because three such recollections were wrong last round.

> **DIRECTOR RULING, 2026-08-13: the ⊖ deletes directly.** Tapping it in edit
> mode removes the row. The three tests above are **re-decided, not
> re-baselined** — each currently asserts the reveal *as correct*, so each is
> rewritten to assert the new contract with the reason on the record. The commit
> machinery is reused rather than rebuilt: `fireTrayAction` (`:3330-3339`) and
> `doCommitAction` (`:1491`) already carry the full slide-off + height-collapse
> sequence, including round 2's C8a fix (nothing painted once the row is carried
> clear). The label stops being a lie by becoming true.

Scope, established rather than assumed: **`Table` and standalone rows only.** A
hosted `VirtualList` row has no ⊖ at all — the whole branch is gated
`if not isHosted then` (`row_actions.luau:2971`), and `hasEditAffordance` requires
a wired `editing` (`:733`) that `VirtualList` never passes, because `"editing"` is
not a legal key in `VIRTUAL_LIST_KEYS` (`virtual_list.luau:343-380`).

### Deletable vs reorderable — already separable, and the odd member is `reorderable`

The director asked whether "deletable" should be a property separate from
`reorderable`. **They are already fully separable and neither implies the
other** — verified by reading every `spec.reorderable` read in both controls and
every `hasDestructive` read in `row_actions.luau`:

- reorder is declared by `reorderable` + `onReorder` (`table.luau:536`, `:991`,
  `:1424`, `:2251`, `:2784`; `virtual_list.luau:547`);
- delete is declared by **attaching a destructive row action**
  (`row_actions.luau:706-716` scans both edges per row; `:733` gates the ⊖);
- **no line couples them** — no `reorderable` read anywhere in `row_actions.luau`,
  no `rowActions` read in any `reorderable` branch of `table.luau`. Both shapes
  ship today: reorderable-without-actions and destructive-without-reorder.

So no per-table `deletable` boolean is added, and **the general mechanism points
at `reorderable` as the odd member**, not at delete: `reorderable` + `onReorder`
is a boolean-plus-handler pair where `onReorder ~= nil` already carries the whole
meaning. Apple's own model, re-verified this round, is *"capabilities are declared
by attaching a handler, never by one boolean"*. Regularising `reorderable` is an
API break; **booked with the `onReorder` contract divergence above, so the two
land together or not at all.**

One consequence the director should know, and it is very likely what prompted the
question: **a table that is deletable but not reorderable and declares no
`onPrimaryAction` grows no auto Edit/Done toggle**, so its ⊖ is unreachable on
touch unless the consumer owns `spec.editing`. That is correct under round 2's
stated principle — the ⊖ is *an affordance, not a capability*, because the swipe
tray, the Delete key and the action menu all reach the same action in normal mode
(`table.luau:488-492`) — but "make it deletable" never implies "give it an Edit
button".

### The opt-out family — the director took the wider option

SwiftUI's family, verified live 2026-08-13 (all three live on `View`, not on
`DynamicViewContent` — the `DynamicViewContent` paths 404):

| Symbol | Apple's sentence | Availability |
|---|---|---|
| `selectionDisabled(_:)` | "Adds a condition that controls whether users can select this view." | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ |
| `deleteDisabled(_:)` | "Adds a condition for whether the view's view hierarchy is deletable." | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ |
| `moveDisabled(_:)` | "Adds a condition for whether the view's view hierarchy is movable." | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ |

Apple attaches them to the **row view** with an ordinary boolean over the item.
LuauUI has no per-row-view modifier vocabulary, so the faithful translation is a
**spec-level per-row closure** — which is already this codebase's idiom for
exactly this shape, five times over: `rowFocusable`, `rowDropTarget`,
`rowActions`, `rowHeight`, `dragLabel`.

**The recommendation was to build two of three**, on the grounds that
`deleteDisabled` is already expressible — `spec.rowActions(item)` is itself
per-item, so returning no destructive action for a row makes that row
undeletable, and the ⊖ then does not mount because `hasDestructive` is evaluated
per row instance.

> **DIRECTOR RULING, 2026-08-13: build all three, including the delete member.**
> The concern was raised and the wider option was chosen; it is taken as decided.
> The cost is one redundant spelling of something already expressible, bought for
> discoverability under SwiftUI's own name. The design obligation that comes with
> it, and it is real: `row_actions.luau` has **no notion of an item** — it
> receives already-resolved `ActionSpec` lists — so the delete predicate has to be
> threaded across `spec.rowActions`'s own callback boundary. It must not become a
> second, disagreeing source of truth against "this row returned no destructive
> action": **both routes gate the same funnel**, and a row that is undeletable by
> either is undeletable, with one predicate evaluated in one place.

**Three design rules this family is held to**, each from a rule this repo already
paid for:

1. **Positive polarity — `rowSelectable` / `rowMovable` / `rowDeletable`**, not
   SwiftUI's negative `*Disabled`. `rowFocusable` already sits on the same spec
   table; `rowFocusable` and `moveDisabled` two lines apart is a bug factory. The
   parity doc states the inverse mapping explicitly.
2. **Gate the funnel, not the affordance.** `table.luau:1015-1030` already records
   being bitten by *"a third, wholly separate way to start the identical
   reorder"* that missed a guard. `rowMovable` is therefore checked at
   `api.moveRow` / `commitReorderAt` — the one place a row actually moves — as
   well as at each affordance. `Table` has **five** reorder entry points.
3. **A predicate may only ever subtract.** It answers "may *this row*
   participate?", never "can this container do X at all?". So declaring
   `rowMovable` on a control with no `onReorder`, or `rowSelectable` with
   `selection = "none"`, is a **construction-time refusal** naming the missing
   capability — constitution §4, and `table.luau:679-695` is the existing
   precedent.

**Consumer blast radius: near zero.** Rascal Rally's two call sites —
`LuauUIRacerListScreen.luau:159` (`newTable`) and
`LuauUISponsor/RacerList.luau:917` (`newVirtualList`) — declare no `reorderable =
true`, no `rowActions`, and the Sponsor list already carries a per-row predicate
of exactly the proposed shape (`rowFocusable`). Both compile untouched; the rider
is an added contract test, not a migration.

---

## Phase 0 verdict — item D2: no native radial primitive; build on `Path2D`

### Searched and found none

Checked live 2026-08-13 against `create.roblox.com` and the engine API dump
(client `0.734.0.7340915`). Recorded as a *searched result*, not an assumption:

| Checked | Verdict |
|---|---|
| `UIGradient` | **No angular/conic/radial mode.** Four properties only; `Rotation` turns a *linear* gradient on its side. Conic gradients are a standing open feature request on the DevForum, not a shipped feature |
| `ImageLabel` | **No fractional/radial fill.** `ScaleType` is Stretch/Tile/Slice; there is no Unity-style `fillAmount` |
| `EditableImage` | `DrawCircle`/`DrawLine`/`DrawRectangle` — **no arc primitive**, one image updatable per frame, and client authoring is age/ID-gated |
| `GuiObject.Rotation` | Exists, degrees — but **the pivot is not settable** ("relative to the centre… you cannot change the point of rotation") and it is documented **incompatible with `ClipsDescendants`** |
| a first-party spinner/loading widget | **None** in the class list or the UI docs |

So: build both forms on **`Path2D`**, which LuauUI already ships as `UI.Path`.

### The enabling fact, and why nothing new is invented

`Path.points` is declared `reactive = true, dirty = { "paint" },
channel = "binding"` (`blueprint_schema.luau:1888-1896`), and
`authority.luau:150` gives the control binding authority over it. So a
phase-driven `points` memo animates the ring for **zero re-solves** — the same
trick the dot spinner's `tint` already uses, and pinned today by
`tests/path.spec.luau:86-127` (a points change is one prop op and no solves).

**Both forms are one function of one scalar** — `path_shapes.arc(start, sweep)`,
which already ships (`path_shapes.luau:29-64`) and whose header already
anticipated this mission: *"NOT the full-circle kappa shortcut, so partial arcs
(**progress rings**) keep stroke quality at any sweep."*

| Form | Binding |
|---|---|
| determinate ring | `arc(0, 360 × fraction)` |
| indeterminate | `arc(360 × phase, FIXED_SWEEP)` — a fixed head whose **start angle** advances |

One call, two bindings, no second `if`. **The presentation-channel `rotation` is
deliberately not used**: it is presenter-owned and keyed by node path
(`screen_target.luau:1979-1982`, fed only by `controller.setPresentationTransform`),
so a control cannot reach it — the same boundary round 2 recorded for
`withAnimation`. The arc rotates by recomputing its own start angle, which also
sidesteps the documented `Rotation` ⊥ `ClipsDescendants` incompatibility. **No
channel is invented and no authority is contended.**

### The brief's premise about the spike is half true, and the missing half is the half D2 needs

The brief says *"The spike has happened."* It happened; **it did not clear
investment 7's bar**, which required *"authored curves, clipping, layering, and
device cost"*. Against `artifacts/native-substrate/feasibility/m5-path2d.json`
and `a7-path.json`:

| Requirement | Verdict |
|---|---|
| authored curves | ✅ proved — control points, tangents, kappa convention, 100-point ceiling, a 0.65 arc rendered |
| layering | ✅ proved for the ZStack case — three strokes composited and captured |
| **clipping** | ❌ **never checked.** The word "clip" appears in neither artifact |
| **device cost** | ❌ **never checked.** Desktop Studio only, and the arc was only ever stepped discretely — **never updated at frame rate** |

And the repo already says so in its own words —
`swiftui-parity-next.md:349`: *"`Gauge` remains unbuilt (the `Path2D` spike bar
was never met)."* **The two unmet halves are exactly the two D2 depends on.**

### So the clipping half was closed before writing any code

Probed live in Studio, 2026-08-13, because building first would have been
`the-solver-already-told-you` a third time:

| Probe | Result |
|---|---|
| `Path2D.Transparency` read / write | **`false` / `false`** — still absent, re-confirming the 2026-07-23 measurement. **The ring cannot fade** |
| `Path2D.ZIndex` readable | `true` |
| under `ClipsDescendants = true`, points spanning −0.5…1.5 | constructs; `GetBoundingRect` returns `min=(-54,96) max=(354,104)` against a 200×100 host — i.e. **the bounding rect is pure geometry and knows nothing about the host's clip** |
| inside a `ScrollingFrame`, node scrolled out of the window | constructs; rect `min=(196,376) max=(604,384)` while the frame is 200×100 and its **window is 191×91** |
| `UpdateControlPoint(i, pt)` | **`false` — "Attempting to use Path2D with invalid parent"** |
| `GetMaxControlPoints()` | `100` |

**Three findings that change the design:**

1. **`GetBoundingRect` is not a clip oracle.** It reports geometry, not paint, so
   it cannot answer "did the host crop this" — the question needs a *rendered*
   capture under Play, not an Edit-mode geometry read. **Booked as a Play-mode
   canary before the control ships**, not hand-waved.
2. **`UpdateControlPoint` is not the cheap escape hatch it looked like.** It
   refuses on a Path2D whose parent is not a live GUI ancestor, so the "pin the
   segment count and update in place instead of re-uploading" mitigation cannot be
   assumed to work — it has to be re-probed under Play, parented for real. If it
   does not, every frame of the indeterminate arc is a full `SetControlPoints`.
3. **The ring cannot fade, confirmed.** `sheet_model.luau:1416-1430` already
   refuses `tint.transparency` on a Path and names the working idiom (fade a
   `canvasGroup` container). Since `canvasGroup` decides the node's engine class
   **at creation** and cannot be added later, whether the circular indicator
   declares its own `canvasGroup` holder is a decision to take **now**, not after.

### The shape of the change

**No new blueprint prop, no new class, no new decoration slot** — strictly less
new styling surface than the dot spinner cost, which added a `spinner` slot.
`presentation` gains one value, `"circular"`, accepting **both** modes.

But standing rule 2 bites the *existing* code first. Today the shape/mode
relationship is three hand-written refusals (`progress_view.luau:187-193`,
`:195-202`, `:203-211`). Adding a shape that accepts both modes and has no track
means writing a fourth and fifth `if` for a sibling case — **so the first ones
were the bug.** They are replaced by one capability table:

```luau
-- presentation = the SHAPE. value nil/not-nil = the MODE. They are orthogonal,
-- and this table is where that orthogonality is declared instead of being
-- re-litigated per shape in a chain of ifs.
local PRESENTATIONS = {
    bar      = { indeterminate = true, determinate = true,  hasTrack = true  },
    circular = { indeterminate = true, determinate = true,  hasTrack = false },
    spinner  = { indeterminate = true, determinate = false, hasTrack = false },
}
```

All three refusals become *generated* from it, and `circular` joins by adding a
row rather than a branch. A registry rather than a two-member union, and the
reason is stated as the rule requires: **there are now two independent axes**
(three shapes × two modes) and both existing refusals are already functions of
the pair, so a union of `if`s would grow multiplicatively.

**Size comes from theme metrics, never a per-call number** — two new optional
metrics taking the identical route `spinnerDotSize` takes (`package.luau:216`
plus a fill in `snapshot.luau` from the theme's own space scale), so **no
package's authored metrics and therefore no package's content stamp move**.
`height` stays refused, generated now from `hasTrack = false`, because it is the
bar's track and silently becoming the ring's diameter is the same silent
reinterpretation the existing refusal exists to prevent.

**Reduced motion is inherited, not re-decided.** The circular indeterminate form
reads the **same** `phaseValue` the dots read, from the **same** single
`clock:glide(…, kind = "informational")` call at `:294`. So it acquires **no new
clock entry**, `motionClock` stays a plain spec key rather than an input
contribution (which would have obliged a four-input proof for a control that
accepts no input), and the existing `scope`-required refusal and
release-owned-first ordering apply verbatim. **The leak stays unrepresentable
with no new machinery.** Apple, checked live, documents nothing about reduced
motion here — but does say *"Keep progress indicators moving so people know
something is continuing to happen"*, which independently supports the policy
already written down.

**The five-dot `spinner` is kept, unchanged, and demoted in the docs** — because
it is the fallback if the arc's per-frame cost fails on device, and deleting the
fallback before taking the measurement would be backwards. Its refusal message is
rewritten though: the current text says *"there is no rotation or trim channel to
draw one with"*, which is **now false and must not survive into shipped code**.
It will name the working alternative instead.

**Rascal Rally exposure: one call site, untouched.**
`ResultsScreen.luau:1471` is determinate `bar` with a `height`, no `presentation`,
no `scope`; both round-2 riders keep passing unchanged, and one of them is already
written to redden *with a message naming the cause* if a framework round makes
`scope` unconditional — which this one does not.

---

*(Phases 1–6 follow once Phase 0's remaining reconnaissance track reports. This
document is written as they land; a section that is not here yet has not been
decided yet, and that is deliberate — round 2's lesson is that a plausible story
ahead of the data is worse than no story.)*
