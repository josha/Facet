# SwiftUI parity round 3 — design

The build plan for the mission stated in
[`parity-round3-brief.md`](parity-round3-brief.md). **The brief is
binding; this document is the design it asked for** — one section per phase, plus
the Phase 0 map every later section rests on.

Round 2's design document is [`parity-round2.md`](parity-round2.md);
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
| Facet suite | **4638 passed**, green (`./run-tests.sh`) |
| Rascal Rally suite | **3138 passed**, green (`games/RascalRally/code/run-tests.sh`) |
| Facet version | `0.9.0` (`src/init.luau`) |
| Working tree at start | three modified files and three untracked paths, all belonging to the **declarative-3D** decision session (`docs/adr/ADR-0024-declarative-3d.md`, `spikes/`, `artifacts/declarative-3d-architecture/`, plus edits to `artifacts/code-simplicity-cleanup/public-surface.txt`, `docs/plans/distribution-readiness.md`, `docs/plans/facet-consolidated-roadmap.md`). **Not this mission's work**, and not to be swept into this mission's commits |
| Rascal Rally version control | **`games/RascalRally` is not a git repository.** The git root is `GameStudio/ui/Facet`. So "commit as you go" (brief rule 6) covers framework work only, and the game-side rider's evidence is protected by the scratchpad backup rule instead |

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
- **2026-08-05, `microprofilerScopes` (row PL-8)** — all **twelve** `Facet/*`
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
> preserved**, and **`Facet/present`, `Facet/focusmap` and `Facet/tick` have
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
  iteration. `Facet/resource` covers only the completion.
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
- **Facet already has the better-shaped answer in this space.** `UI.Composition`
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
line-distribution rule that the Roblox documentation does not define — so Facet
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
   not at 40. Same rule as CSS, and the same rule Facet's flow-`grid` branch
   already uses (`solver.luau:3160`).

**This deletes a design decision instead of adding one.** The reconnaissance
recommended a new cross-axis distribution prop reusing `distribute`'s six-word
vocabulary, defaulting to `start`. The measurement says **no new prop is needed
at all**: Facet's existing `align` on an `HStack`/`VStack` *is* the container's
cross-axis alignment, and `lineAlign` (shipped in round 2) *is* per-child
alignment within a line. The engine's three-level structure and Facet's map
one-to-one, already:

| Level | Roblox | Facet, today |
|---|---|---|
| where the block of lines sits on the cross axis | `VerticalAlignment` / `HorizontalAlignment` | **`align`** |
| where an item sits within its line | `ItemLineAlignment` | **`lineAlign`** |
| where items sit along the main axis | `HorizontalFlex` / `VerticalFlex` | **`distribute`** |

So flow-wrap adds **one prop** — the switch that turns wrapping on — and inherits
its whole alignment story from vocabulary that already ships. That is rung 1 of
the simplicity ladder answering "does it need to exist at all?" with *no*, and it
is byte-identical native parity rather than a divergence Facet has to own and
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
| `newTable` does not virtualize | **Missing** — was blocked behind variable item extents (§4.2) *because* `Table` ships `rowHeight(item)`; that substrate shipped 2026-08-14 (`src/virtual_extents.luau`), so this is now UNBLOCKED and is its own mission | `table.luau:1796-1798`, `:371-391` |
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
Facet has no per-row-view modifier vocabulary, so the faithful translation is a
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
`FacetRacerListScreen.luau:159` (`newTable`) and
`FacetSponsor/RacerList.luau:917` (`newVirtualList`) — declare no `reorderable =
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

So: build both forms on **`Path2D`**, which Facet already ships as `UI.Path`.

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
`parity-next.md:349`: *"`Gauge` remains unbuilt (the `Path2D` spike bar
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

## Phase 0 verdict — item E: the owed ledger, verified rather than inherited

The brief names six owed items. Verifying each against the tree found that **four
of the named six are still owed, one is stale as written, and five things the
brief does not name are owed too** — plus five items already closed that a
mission would otherwise have re-opened.

### Already closed — do not re-open these

The most valuable half of the audit, each with its evidence:

| Brief/round-2 claim | Actual state |
|---|---|
| `check_flat_baseline` red, 382 uncharacterized deltas (§6.6) | **GREEN, exit 0**, 1461 nodes. And it was not papered over: a re-pin was *declined*, two narrower waiver kinds were added, disappearance still has **no** waiver, and the real regression it caught — `06_tile_game`'s readouts leaving their published paths — was fixed by `732a520` |
| "an instrument nobody runs" | **Both instruments now run.** `tests/overflow_sweep.spec.luau` is required at `tests/run.luau:205`; the disappearance question got its own twin, `tests/example_readouts.spec.luau`, at `:212`. Correct as retrospective, stale as an owed item |
| The hit expander drops the pointer kind (round 2 §3.4.1, "owed, not fixed here") | **CLOSED** in `79649d6` — `screen_target.luau:3341-3350` now passes `pointerActivateMeta(inputObject)`, and the lesson file exists |
| The `api.md` revert incident's damage | **REPAIRED** — all three checkers exit 0 and every reverted surface is back on disk. What survives is the *prose* skim, a smaller and different job |
| The floating row-actions `Menu` placement defect | **CLOSED and re-verified** 2026-08-13. (The separate viewport-*clamp* question is still open — do not conflate them) |

### Still owed, ranked — the ones this round takes

| # | Item | State, verified | Blocked on |
|---|---|---|---|
| 1 | **`traversal-document-order` re-record** | `check_traversal_evidence.py` → **exit 1, "STALE EVIDENCE"**. The `Body` ScrollView is still at `keyboard_navigation.luau:84-85`; the artifact still holds 18 pre-`Body` paths. The six recorded steps are still accurate | Studio |
| 2 | **Places were stale** | **DONE this round** — all fifteen rebuilt; see the commit. The underlying defect (no build stamp, nothing compares a `.rbxl` to its sources) is booked | — |
| 3 | **Studio device canary on the rebuilt showcase** | **Not run.** No canary artifact exists for round 2 at all. Now unblocked by the rebuild | Studio |
| 4 | **Chrome is unreachable by keyboard and gamepad** | **CONFIRMED IN SOURCE, and it is worse than "without a pointer".** Both pickers present `responder = "passive"` (`demo_picker.luau:464`, `theme_picker.luau:797`); a passive surface's nav context is created **disabled** (`presenter.luau:2595-2603`) and Tab/Space bind **only while the responder is engaged** (`:2839-2842`); the **only** `engage()` call in `src/` is inside the *tap* handler (`:2248`). So mouse ✓, touch ✓, **keyboard ✗, gamepad ✗**. `demo_picker.luau:225` carries a comment promising "the gamepad/keyboard path" above a `showNext()` whose only callers are the test driver. **No key and no pad button is bound to it.** A standing-rule-7 violation inside the artifact the showcase rule exists to protect | headless, then Studio |
| 5 | **`api.md` round-2 prose skim** | **CLOSED 2026-08-13** (`c265015`, `fa03dcc`, `46a9cd5`, `023b0fe`, `5aaa79e`). **The "12 concrete defects, listed below" this row promised DO NOT EXIST**: nothing below it is that list, no match for "prose skim"/"12 concrete" exists anywhere in `docs/`, `artifacts/` or `tools/`, and the commit that wrote this row (`9518d8a`) added the row and no list. The Phase-0 agent counted 12 and never wrote them down — this document's own "reviews must land as artifacts" finding, committed by the document. The skim was therefore redone from scratch (all 5,610 lines, against a live schema dump) and found **15**, all fixed: four wrong class counts, `Stage` missing from three inventories and from `tint`, three drifted ledgers (DEPRECATIONS 2→5, Controller 28→35, SURFACE_LAYER "five"→four bands), a paragraph cut in half mid-sentence by an earlier insert, `newVirtualList`'s `axis` and `selectionPaint` undocumented while the prose referred to `axis`, and **`recycleInstances` / `incrementalLayout` documented NOWHERE despite being ON BY DEFAULT**. The mechanical half was already closed; `check_prop_parity` is a bare substring test, so one mention anywhere satisfies it | headless |
| 6 | **Shrink gap (a): a shrinkable label lands outside its box** | **TRUE, measured.** Three `shrinkWeight=1` texts in a 120px box solve to `x0 w120 / x120 w120 / x240 w100` — two land wholly outside. `absorbTier` absorbs at most `Σ(basis−floor)`; residual deficit is simply not absorbed and nothing clips. The shrink pass is **best-effort and its own diagnostic says so** | headless + a ruling |
| 7 | **Shrink gap (b): `shrinkWeight` flips the `ViewThatFits` winner** | **TRUE, measured — and round 2's §2.4 claim is FALSE.** That doc says `ViewThatFits` "picks its candidate before any of this and is therefore unaffected"; PASS 1.5 (the measure-side shrink, landed a day later) invalidated it. Swept 150→420px, adding `shrinkWeight=1` to a candidate's children flips the winner at **10 of 28 widths (290–380px)**, because the candidate now *reports* a shrunk extent and `fitsW` becomes true | headless + a ruling |
| 8 | **Table tray-focus: trays are in no focus group** | **DONE 2026-08-13** (`e54d671`) — the walk anchors on the wrapper, so a row is its whole mounted subtree. See "Rows 8 and 9 shipped" below | — |
| 9 | **Keyboard/pad Delete on an unswiped hosted row** | **DONE 2026-08-13** (`e725c68`) — the LIST holds the focused row's key surface and builds the engine on the press. The gap was wider than Delete: the action menu was in it too | — |
| 10 | **A BLOCK table publishes a scroll path it has no host for** | **OPEN, not named by the brief.** `table.luau:2869-2871` returns `…/Main/Body` unconditionally with no `scrolls` check. The crash half is fixed; the design half is live in the shipped playlist example — open a tray, scroll the page, and the tray rides along still open, because "any scroll closes the tray" binds to a node that never scrolls | headless + a ruling |
| 11 | **Reduced-motion settings surface** | **NOT BUILT.** `with_animation` writes the real env fact but restores it on dispose (`:159`, `:486`), so the reduced-motion axis is reachable only while that one demo is on screen. **Hard-blocked behind #4** — a settings surface only a finger can open cannot run the keyboard or gamepad axis of a canary | headless |
| 12 | **Row-actions menu not clamped to the viewport** | **OPEN**, comment unchanged. Trigger at y=508 on a 600px viewport → menu at y=556..629 | a ruling |
| 13 | **The "Edit item" wrap rule** | **OPEN.** `renderer.luau:452` unchanged. The honest rule, per the doc's own root-cause: wrapping is right only when the phrase's **longest word** fits the drawable width | a ruling |
| 14 | **The overflow sweep cannot see cross-axis findings** | **DONE 2026-08-13** — the message filter is deleted, not widened, and all five recorded findings are re-verified. See "The overflow sweep asks about every finding" below | headless |

### Deferred, with the reason

`presenter.animator()` (build it when a composite asks, not before) · size animation in `withAnimation` (its own mission; the five blocking mechanisms stand) · variable item extents — **NO LONGER DEFERRED**: the consumer arrived (the widened sweep's 249px-in-an-84px-slot at `preferredTextOffset = 14`), the director ruled option A on 2026-08-13, and Stage 1 shipped 2026-08-14 (`docs/plans/variable-item-extents.md`); measured extents are Stage 2 · §6.4's perf follow-ups (**worse than reported** — `perf_lab.spec` is now 16,494 ms, **37 %** of the suite, against round 2's 13.7 s/32 % — but it is runtime, not correctness) · the five unfulfilled placement intents and the rendered-canary-set proposal (**both are director decisions, surfaced not built**) · every `PENDING_PHYSICAL` row, including brief item **E2**, which the brief itself says not to block on and is right: its fix rests on an unverified engine premise that only a device can settle.

### Two process findings worth more than any single item

1. **No round-2 review artifact exists in the tree.** `artifacts/swiftui-parity-round2/` holds three files and none is a review; `[SHOWCASE-CHROME]: CONCERNS 16` survives only as prose citations, and `gate.json` cites a `prior-gates-rerun.txt` that **does not exist**. Every round-2 review finding is unrecoverable except as summary. *Reviews must land as artifacts.*
2. **The tree was not exclusively this mission's, and checking is what proved it.** A concurrent session's `tools/gate.sh swiftui-parity-round2` had been hung for 2 h 37 m holding `/tmp/facet_prior_gates.lock`, which is why round 2's `prior-gates-unregressed` reads `FAIL_RECOVERABLE`. The reconnaissance recommended clearing the lock as "the cheapest unblock in the ledger"; **`pgrep` showed a live process holding it, and clearing it blind would have broken that run.** It also explains the perf place changing mid-session. Killed with director authorisation, 2026-08-13, along with three further orphans. *`ListAgents` is not enough — check the process table.*

---

*(Phases 1–6 follow. This document is written as they land; a section that is not
here yet has not been decided yet, and that is deliberate — round 2's lesson is
that a plausible story ahead of the data is worse than no story.)*

---

## D2 shipped — the circular progress indicator, both forms

`presentation = "circular"` ships. Everything below is what was decided while
building, what was measured, and the one question that is still open.

### 1. The capability registry replaced the three hand-written refusals

Standing rule 2 bit the existing code first. `presentation` is the **shape**;
`value` nil-or-not is the **mode**; they are two independent axes (three shapes ×
two modes), and every refusal is a function of the *pair*. That was three
hand-written `if`s, and adding a shape that takes both modes and has no track
would have meant a fourth and fifth branch for a sibling case — so the chain was
the bug. It is now one table (`progress_view.luau`), with a fourth column the
mission's design added:

```luau
bar      = { indeterminate = true, determinate = true,  hasTrack = true,  valueLabel = true  }
circular = { indeterminate = true, determinate = true,  hasTrack = false, valueLabel = false }
spinner  = { indeterminate = true, determinate = false, hasTrack = false, valueLabel = false }
```

**Four refusals are now generated from it** — unknown presentation (which lists
the rows), illegal mode, `height` without a track, `showValue` without a label
host — and each row carries the *sentence* its refusal borrows, so the reason
lives beside the fact. `circular` joined by adding a row. The rendering side is a
dispatch table keyed by the same name rather than a chain, so a shape is added in
one place at both ends; the three builders are genuinely different geometry (a
track, five dots, a stroked arc), which is what separates a dispatch from the
`if` chain the refusals used to be.

**The spinner's old refusal message is gone.** It said *"the blueprint has no
rotation or trim channel to draw one with"*, which stopped being true the moment
`circular` shipped. It now names `presentation = "circular"`, and
`display_controls.spec` fails if the old sentence ever comes back.

### 2. The `canvasGroup` decision: NO holder, and the caller owns the fade

`Path2D` has no `Transparency` — re-confirmed by the Phase 0 probe (both the read
and the write pcall returned false). `canvasGroup` fixes a node's engine class at
creation and cannot be added later, so this had to be decided now.

**Decided: the control declares no `canvasGroup`.** Declaring one would force a
CanvasGroup instance — an off-screen render target and a permanent opt-out of
container elision — on *every* caller, to buy a fade nobody asked for and whose
effect on a `Path2D` child is itself unverified. A caller who needs the ring to
fade wraps `blueprint` in their own `UI.ZStack({ canvasGroup = true })`, which is
exactly the idiom `sheet_model.tintTransparency`'s existing refusal already names.
Recorded in the control's header and in `docs/guide/10-rich-skinning.md` so a
theme author looking for a "ring slot" finds the answer instead.

### 3. The `showValue` decision: REFUSED, with both alternatives named

Apple's centred readout is real and was verified from the JSON twin
(`accessoryCircularCapacity`: *"This style displays the gauge's
`currentValueLabel` value at the center of the gauge"* — SW-131). It is also a
**`Gauge`** on a complication-sized dial. This indicator is small by construction:
its diameter is a theme metric off the `space` scale and there is **no per-call
diameter**, so a centred readout has no size it is guaranteed to fit inside — and
putting it *beside* the ring, where the bar puts it, would ship a different design
under Apple's description. So `showValue` is refused on `circular` (in both
polarities — `showValue = false` is refused too, because the field has no meaning
here either way), and the message names the two things that do work: compose your
own `UI.Text` beside the control, or use the bar. The gallery fixture does exactly
the former, so the documented alternative is one a reader can see working.

**The parity claim is split accordingly.** On iOS/tvOS `ProgressView(.circular)`
is not guaranteed to be determinate — Apple's own words, now cited: *"In cases
where no determinate circular progress view style is available, circular progress
views use an indeterminate style"* (SW-130). So `swiftui-parity.md` claims
`ProgressView` parity for the **indeterminate** ring only; the determinate ring is
cited against `Gauge(.accessoryCircularCapacity)` (SW-131), which is also the one
`Gauge` shape Facet now has.

### 4. Sizing: two optional metrics, and the arithmetic lives where the numbers do

`controls.progress.circularSize` and `circularThickness` join
`spinnerDotSize` in `package.CONTROL_FAMILY_OPTIONAL.progress`, filled by
`snapshot.resolve` from the theme's own `space` scale (`space.l`, and `space.xs`
for the stroke). **No shipped package's authored metrics move, so no package's
content stamp moves.**

The non-obvious half: a Path2D stroke is **centred on its curve**, so a ring at
radius fraction `R` in a box of `D` paints out to `R·D/2 + thickness/2`. The
control only ever sees metric *names* — it never resolves a snapshot — so the
relationship can only be guaranteed inside `snapshot.resolve`, where both numbers
exist. `CIRCULAR_RADIUS = 0.8` leaves a fifth of the diameter as the stroke's
budget and the fill clamps to it (pre-snapped **down** onto a pixel theme's grid,
because §4b snaps every published length **up**). `progress_circular.spec` asserts
`R·D/2 + t/2 ≤ D/2` for the neutral snapshot and all eight shipped packages —
this is the "painted at a size nobody measured" family, which no headless
diagnostic can see, so the invariant is checked as arithmetic instead.

### 5. Performance — tier 1 (headless Lune), and the prediction held exactly

Falsifiable prediction, stated before measuring: `commit` rises, `react` rises
slightly, **`measure`/`arrange` stay FLAT** — any movement there means the arc
leaked into geometry. Measured over 600 frames of live cycle at 400×600:

| shape (indeterminate) | instances | ops/frame | solves | propWrites | rectWrites | arranged | measured | ms/frame |
|---|---|---|---|---|---|---|---|---|
| `bar` | 6 | 1.98 | **+600** | 0 | 1188 | 6 → 6 | 27 → 27 | 0.044 |
| `spinner` (dots) | 8 | 5.00 | 0 | 3000 | 0 | 8 → 8 | 26 → 26 | 0.021 |
| **`circular`** | **4** | **1.00** | **0** | 600 | 0 | 4 → 4 | 8 → 8 | **0.004** |

And 100 determinate value changes:

| shape | ops | solves | propWrites | rectWrites |
|---|---|---|---|---|
| `bar` | 100 | **+100** | 0 | 100 |
| **`circular`** | 100 | **0** | 100 | 0 |

`measure`/`arrange` are flat in every row, `solves` is zero for both circular
forms, and the rotating ring is the **cheapest** indicator in the family — one
prop write per frame against the dot spinner's five, on half the instances, and
0.004 ms/frame against the indeterminate bar's 0.044 ms with its 600 re-solves.
The five-dot spinner is kept anyway, unchanged and demoted in the docs, because
the number that matters is a **device** number and nobody has taken it.

**Off-path cost is exactly zero**, asserted rather than asserted-about: a surface
with a bar and a dot spinner, driven 120 clock steps, materialises no `Path`
instance (instance delta 0) and emits no `.points` op (op delta 0). Mutation
M14 (a stray `UI.Path` added to the bar's builder) reddens that case.

Everything above is **tier 1 (headless Lune)**. Nothing here is a phone number:
the arc's per-frame `SetControlPoints` cost on device is **`PENDING_PHYSICAL`**,
and `Path2D:UpdateControlPoint` — the cheap in-place mitigation if it is needed —
**refuses on an unparented Path2D** (Phase 0 probe) and has not been re-probed
under Play.

### 6. The risk this mission could NOT close: clipping

Phase 0 booked "does the ring clip inside a ScrollView" as a Play-mode canary.
It is **still open**, and the honest statement is in two halves:

* **The framework half is closed, and it was already closed before D2 started.**
  `renderer` culls a `UI.Path` that is not *fully* inside every clip host above
  it — all-or-nothing, because a stroke has no half-crop — and
  `tests/path.spec.luau`'s RS-PATHCLIP block pins it over a real `ScrollView`
  host, including the partial-overlap case and the no-clip-host case. So a
  circular indicator in a scrolling list **winks out at the edge**; it does not
  paint outside the window. That is a behaviour a caller must know (it is now in
  `api.md`), not a defect.
* **The engine half is untested.** Whether the engine *itself* would have cropped
  the stroke is unanswered, and `GetBoundingRect` cannot answer it: it reports
  geometry that knows nothing about a host's crop. Answering it needs a rendered
  capture under Play, which this mission did not take. It does not block the
  control — the framework's cull runs first and is deterministic — but the
  D2 row in any device-canary ledger should read **PENDING_PHYSICAL**, and the
  `progress_ring` fixture is the surface to drive when someone takes it.

### 7. What shipped, and where it is proved

`src/controls/progress_view.luau` (registry + both forms) ·
`src/themes/package.luau` + `src/themes/snapshot.luau` (two optional metrics) ·
`tests/progress_circular.spec.luau` (11 cases) · six new cases in
`tests/display_controls.spec.luau` · five in `tests/examples_gallery.spec.luau` ·
`examples/gallery/scenarios/progress_ring.luau`, registered in the scenario
`ORDER`, `demo_picker.DEMOS` and the always-on `overflow_sweep` list ·
`docs/reference/api.md`, `docs/reference/swiftui-parity.md` (rows + citations
SW-130/SW-131), `docs/guide/10-rich-skinning.md` · and one extended framework
rider in Rascal Rally's `tests/facet_sponsor_results.spec.luau`, which asserts
the bar's three registry cells directly (mutating `bar.valueLabel` to `false`
reddens that one case and nothing else; mutating `bar.hasTrack` reddens 388,
because the rally bar stops presenting).

---

## Item A shipped — flow-wrap, as one prop and no new alignment words

Built 2026-08-13 against the Phase 0 verdict above, which is not re-litigated here:
flow-wrap is a **native arrange branch**, the public `Layout` protocol stays a
conditional refusal with a trigger, and the engine's cross-axis rule is a measured
fact rather than a divergence Facet has to own. This section records the five
decisions the verdict left open, the two things it got wrong, and the evidence.

### A.1 The prop, and why it is a prop

**`wrap` is a boolean prop on `UI.HStack` and `UI.VStack`.** Not a class, and not
on any other container.

The kind ladder (`docs/reference/constitution.md` §1) asks whether the thing
"needs its own layout/paint/input semantics an existing class cannot compose". A
wrapping stack has the same children, the same paint (none), the same input
(none), the same `gap`, the same `align`, the same `lineAlign` and the same
`distribute` as the stack it is a mode of. **One boolean is the entire
difference**, which is standing rule 2's "a two-member union with a comment beats
a registry" at the smallest possible scale.

The decisive argument is not economy, it is the remount. `AdaptiveStack` exists
because swapping `UI.VStack` for `UI.HStack` through a `When` "would remount every
child and lose their state on a viewport flip" (`blueprint_schema.luau:1196-1199`).
A `UI.FlowStack` class would have made *"wrap this row on a phone, keep it on one
line on a desktop"* — the single most likely use of the feature — exactly that
remount. `wrap` is reactive (`dirty = { "measure" }`), so the flip is a re-solve
of the same nodes; `tests/flow_wrap.spec.luau` and the gallery case both assert
node identity across a flip rather than only the geometry.

**But the SOLVER kind is distinct: `hwrap` / `vwrap`.** One public class, two
internal kinds — the same prop-decides-kind seam `AdaptiveStack.axis` already
uses. This is forced, not stylistic: `solver.auditPlacement` is keyed on the
layout kind, and a wrapping stack reads a **different placement set** from the
stack it is a mode of (below). There is no way to express "an hstack that wraps
reads a different set" in a table keyed by kind without a distinct kind.

`Screen` and `AdaptiveStack` deliberately do **not** get `wrap`. A prop only two
arrange branches read is a prop every other class must refuse (§4), and the schema
is what refuses it — `UI.ZStack{ wrap = true }` is a construction error. If a
consumer wants a wrapping `AdaptiveStack`, that is a one-line addition plus its
own test row, and it should wait for the consumer.

### A.2 The four sub-rules, decided and written down

| Rule | Decision | Where it is enforced |
|---|---|---|
| an item wider than its line | it gets a line of its own, is **clamped** to the line, and files a **main-axis** diagnostic naming the child and the pixel count | `arrange`'s wrap branch, under the same `hiddenDepth` gate and reuse replay as the existing overflow message (it files under the STACK's id, so `filedBy` falls back to `d.node` exactly as that one does) |
| `align = "stretch"` | **refused**, and treated as `start`. It already means "a child fills its line on the cross axis"; letting it also mean "the lines grow to fill the container" is one word meaning two things — the ambiguity `lineAlign` was created to end | **two seams, one rule**: a *literal* stretch is a construction error in `blueprint.luau` (the loudest answer, and `props.align == "stretch"` can only be true of a literal); a *bound* one — `align` is reactive, so this is the only other way it can arrive — is a solver diagnostic with the same wording |
| composition with `newVirtualList` | **refused.** The virtualizer windows by `index × pitch` and needs a uniform item extent; a wrapped line has ragged extents and a variable items-per-line | already refused, by the closed spec: `newVirtualList{ wrap = … }` is an unknown-field construction error. **Pinned but not perfect — see A.6** |
| a `fill` child on the main axis | it **takes a whole line to itself**, and is named rather than silently swallowed | found while building, not in the brief. `resolveAxis` can only report CONTENT for a `fill` axis, so a `fill`-width Box would otherwise have entered the partition at **zero** — three of them sharing one line at zero pixels each, invisible and silent |

Two further rules that fell out of the measurement rather than a choice: **one
`gap` spaces both the items and the lines** (`UIListLayout` has a single
`Padding`; a `rowGap` on `HStack`/`VStack` would be accepted-and-ignored on every
stack that does not wrap, which is the §4 violation the placement audit exists to
end), and **an aspect-ratio child keeps the pair `measure` resolved** rather than
re-deriving a main extent at arrange time — the partition is a function of the
measured main extents, so an arrange-time re-derivation would make the two passes
disagree about the lines.

### A.3 The one new thing this ships that native does not: a cross-axis overflow

**A wrapping stack cannot overflow its main axis — that is what wrapping means.**
The direction it runs out of room is the **cross** axis, as the lines pile up, and
**nothing in this repo had ever looked there.** Every overflow message in
`solver.luau` was a main-axis message, and `tests/overflow_sweep.spec.luau` —
the always-on sweep over every showcase surface at every viewport — greps for the
literal string `"on the main axis"`. A wrapping stack on any screen would have
been structurally invisible to it: the "instrument that cannot bite" class that
sweep was written to end.

So `arrange` files `"the wrapped lines overflow this <kind> by Npx on the cross
axis"`, and the sweep now matches **either** axis. That broadening is
mutation-proved in both directions (A.5): with a swept surface made to overflow on
the cross axis, the old main-axis-only grep passes it **green** and the new one
fails it.

It found a real defect immediately. The gallery fixture's alignment panel was a
200px box reasoned from Studio Neutral's ~36px chip; the nine-package sweep
reported it overflowing on the cross axis under **four** packages at 320px wide —
glossy_touch by 33px, fantasy_parchment by 33, fantasy_ornate by 49, pixel_quest
by 88. That is `docs/lessons/facet-fixed-px-heights` arriving on schedule, caught
by an instrument that did not exist an hour earlier.

### A.4 The cache key and the reuse skip: no widening, and here is the sentence

**Verdict: neither the measure memo's key nor the incremental-arrange reuse skip
needs widening**, because the line partition reads nothing that is not already a
function of `(node identity, maxW, maxH, hiddenDepth)` — the child main extents
come from `measure` at the box being partitioned (so they are keyed by that box
already), `gap` and `align` are fields of the node itself, and the partition
function reads no ctx, no clock and no ancestor.

The reuse skip's own enumeration argument (`solver.luau:2500-2539`) survives for
the same reason: "every dimension resolves against the parent's **offer**, which
the rect carries", and a wrapping stack's lines are a function of its own inner
box, which its rect carries.

**What *did* need a key is the plan cache itself**, and this is where the mutation
discipline paid. `flowPlan` is cached on `ctx` keyed by `{innerMain}|{innerCross}|
{gap}`, exactly as `gridColumnPlan` is. Dropping the box from that key —
`local key = "constant"` — reddened **nothing** on the first attempt: every
fixture in the file measured a wrapping stack at the box it was then arranged in,
so the key was an assertion no test could see. The case that makes it load-bearing
is a wrapping stack that opts into `shrinkWeight` under a short parent: measured
at the full offer, squeezed, re-measured at the reduced offer, arranged at the
reduced offer — three questions, two boxes, one node. With the box in the key it
reports `100x160` and four lines; without it, it answers the first question three
times and paints four items side by side out of a box a quarter as wide. That
case is now `"the plan is keyed by the BOX: a SHRUNK wrapping stack re-breaks its
lines"`, and the same mutation now reddens it.

### A.5 Every check, mutation-proved

Each mutation asserts its anchor matched **exactly one site** before running —
the orchestrator's "0 reddened" trap this session was a text surgery that silently
matched nothing, which is indistinguishable from an uncovered check.

| # | Mutation | Reddened |
|---|---|---|
| M1 | the partition never breaks a line (`elseif true`) | **14** cases incl. the fuzz, the measure report, all four probe cases |
| M2 | a line's cross extent is its FIRST item, not its tallest | **6** incl. "ragged: line 2 starts at 90" |
| M3 | the block of lines is not aligned (`+ 0`) | **3**: Center, End, and the gallery `align` case |
| M4 | `flowPlan`'s cache key drops the box | **0 at first** → 1 after A.4's case was added |
| M5 | an over-wide item is not clamped | 1 |
| M6 | the over-wide diagnostic is deleted | 1 |
| M7 | the cross-axis overflow diagnostic is deleted | 1 |
| M8 | `PLACEMENT_READS` forgets `hwrap`/`vwrap` | 2 (and 1 in Rascal Rally) |
| M9 | the solver's `stretch` refusal is deleted | 1 |
| M10 | a `fill` main child no longer takes the line | 1 |
| M11 | `distribute` is not applied per line | 1 |
| M12 | the `lineAlign` ladder collapses to the block's word | 2 |
| M13 | the renderer never produces a wrapping kind | **10**, incl. the sweep and every gallery case |
| M14 | the construction refusal of a literal `stretch` is deleted | 1 |
| M15 | schema `wrap` dirties `paint` instead of `measure` | 3, incl. the repo-wide property-parity check |
| M16 | `wrap` is also declared on `ZStack` | 2 |
| M17a | a swept surface is made to overflow on the cross axis | **6**, incl. `scenario 'flow_wrap'` in the always-on sweep |
| M17b | …the same overflow, with the sweep's OLD main-axis-only grep | **0 — green.** The negative control for A.3 |
| R1 | (Rascal Rally) the framework renderer never wraps | 1 |
| R2 | (Rascal Rally) a game file starts declaring a layout `wrap` | 1 |
| R3 | (Rascal Rally) `PLACEMENT_READS` forgets the wrapping kinds | 1 |

### A.6 Performance — `tier 1 (headless Lune, regression signal only)`

**The noise floor, re-measured in this session on a quiet machine** (0 other
`lune` processes), three identical `tools/perf.sh` runs with no edit between them,
aggregated as round 2 aggregated (the sum of `phases.total` over all 100
scene × profile cells; every run `status: PASS`):

| | run 1 | 2 | 3 | spread |
|---|---|---|---|---|
| Σ `total.p50_ms` | 39.016 | 38.680 | 39.722 | **2.69 %** |
| Σ `total.p95_ms` | 64.410 | 64.704 | 67.623 | **4.99 %** |

That is well under Phase 0's 3.78 %/6.03 %, which is consistent with Phase 0's own
caveat that its floor was taken under five-agent CPU contention. **Phase 0's
per-scene finding stands and is not re-measured: the median per-cell same-arm p95
spread is 27.4 %, so no single-scene number is quoted below.**

**The delta**, interleaved B A B A B in one session, against the same-arm floor
above (medians; A = 5 samples including the floor runs, B = 3):

| | BEFORE | AFTER | delta | floor |
|---|---|---|---|---|
| Σ `total.p50_ms` | 39.372 | 39.721 | **+0.89 %** | 2.69 % |
| Σ `total.p95_ms` | 65.220 | 66.038 | **+1.25 %** | 4.99 % |

**Inside the noise on both aggregates**, and every one of the 100 cells passed its
budget in all eight runs. The B arm is the four source files at `fba3158^`
(solver, renderer, schema, blueprint), swapped in and out around each run.

The claim this supports is the narrow one: **not one perf scene contains a
wrapping stack**, so this measures purely the *off-path* cost — the two string
comparisons the wrap branch adds to `contentSize` and to `arrange`, on the stack
fall-through only. It is a regression signal, not a device claim (§14.3), and it
says the off-path cost is not resolvable by this harness rather than that it is
zero.

### A.7 What shipped, and what I found and did not fix

`src/layout/solver.luau` (`flowPartition` — pure and exported, `flowPlan` —
ctx-cached, the `hwrap`/`vwrap` measure and arrange branches, the three new
diagnostics, and the `PLACEMENT_READS`/`PLACEMENT_BY`/`PLACEMENT_INSTEAD` rows) ·
`src/blueprint_schema.luau` (`WRAP`) · `src/blueprint.luau` (the typed spec plus
the literal-`stretch` refusal) · `src/render/renderer.luau` (`toLayoutNode`'s kind
and the child axis) · `tests/flow_wrap.spec.luau` (**40 cases**) ·
`examples/gallery/scenarios/flow_wrap.luau`, registered in the scenario `ORDER`,
`demo_picker.DEMOS` and the always-on `overflow_sweep` list · six new cases in
`tests/examples_gallery.spec.luau` · `tests/overflow_sweep.spec.luau` taught the
cross axis · `docs/reference/api.md`, `docs/guide/01-concepts.md` (§1.9, the ELI5
paragraph), and the three now-false flow-wrap rows in
`docs/reference/swiftui-parity.md` (§4.1's scorecard, the `Wraps` row, §4.3) ·
plus `games/RascalRally/code/tests/facet_flow_wrap_contract.spec.luau` (8 cases).

**Found and NOT fixed, in descending order of how much it would bother me:**

1. **The `newVirtualList` refusal does not name the conflict.** `wrap` there is
   caught by the closed-spec guard, so the message is the generic *"unknown
   field"* rather than *"a wrapped line has ragged extents and a variable
   items-per-line, so `index × pitch` cannot window it"*. Naming it means editing
   `src/controls/virtual_list.luau`, which this task does not own. The refusal is
   real and pinned by a test; only the message is generic. **Owed to whoever owns
   that file.**
2. **`AdaptiveStack` cannot wrap.** Its `axis` resolves to `hstack`/`vstack` in
   the same `toLayoutNode` branch, so supporting it is one line plus a schema
   entry — deliberately not taken, because a prop with no consumer is a prop with
   no test that means anything. It is refused loudly (schema), not silently.
3. **The word `wrap` was already taken in this codebase, twice.** A focus
   NAVIGATION GROUP has had a `wrap` field for as long as groups have existed
   (`wrap = true` = arrow past the last row and land on the first), and Rascal
   Rally sets it in two files. The two live in disjoint tables and cannot be
   confused by the framework — but they can be confused by a reader, and by a
   naive `grep`. The Rascal Rally contract spec therefore pins the exact set of
   existing occurrences by path rather than asserting there are none. Renaming
   either was not considered worth it: both are the universal word for their own
   idea, and CSS, Roblox and the focus literature all agree with both readings.
4. **No live Studio canary was taken for this item.** The scenario is registered
   and driven headlessly at every swept viewport under all nine themes, and the
   cross-axis rule it reproduces came from a live Studio probe on 2026-08-13 — but
   the *fixture itself* has not been mounted in Studio under Play. The gate row
   for A should read **PENDING_PHYSICAL** on the device ledger; `flow_wrap` is the
   surface to drive.
5. **Two perf-lab specs were red mid-session and are not mine.**
   `tests/perf_lab.spec` "refuses a pass the workload does not declare" and "loops
   ONE pass" failed against an in-flight working-tree edit to
   `examples/performance/lab/perf_lab.luau` (the orchestrator's file). Both were
   green again by the final run. Named here so the transcript is not mistaken for
   a flow-wrap regression.

---

# Item D3 — the five clean-room reference apps, re-proved

**Closed 2026-08-13.** `examples/reference/p1_glade`, `p2_cartwheel`,
`p3_sipworks`, `p4_foyer`, `p5_wardrobe`. Suites **4725 → 4734** (Facet) and
**3149 → 3149** (Rascal Rally, untouched by this item). Nine new cases, every one
mutation-proved. Five places rebuilt.

## The headline, before the diff

**Round 2's vocabulary had a zero-percent adoption rate in these five apps.** A
grep across all five trees before this session found no `withAnimation`, no
`distribute`, no `containerRelativeFrame`, no `layoutPriority`, no
`shrinkWeight`, no `sensoryFeedback`, no `GridRow`/`gridSpan`, no `Table`
`onPrimaryAction`, no `newVirtualList`, and no swipe actions. Round 2's commit
`a42ef97` did touch these apps — but only to *delete* no-op alignment props in
the §2.1 placement audit. Not one round-2 API was ever adopted here.

That is not a failure of round 2's APIs; it is what "the apps are only re-proved
when someone re-proves them" looks like. It is also why D3 was worth doing: three
of this session's strongest findings were sitting in prose comments the original
authors wrote, describing intents the framework had since grown a word for.

## Adoption ledger

Legend: **U** = found unaided from `docs/guide/**` + `docs/reference/api.md`;
**T** = found only after being told (a documentation defect); **A** = wanted and
absent.

### p2_cartwheel — 4 adoptions, all `wrap`

| Capability | Verdict | Site | Evidence |
|---|---|---|---|
| `HStack{ wrap = true }` | **U** | `screens/dashboard.luau` tag cloud | **This spends bounded gap #3.** The capability ledger nominated "stack `wrap`/flow" as a candidate bounded gap in round 1, scoped precisely — *"only if P2's tag cloud reads wrong as a uniform grid"* — and the source comment recorded it as unspent. It read wrong: `Grid{ minColumnWidth = "intrinsic", itemSizing = "uniform" }` measured **all sixteen tags at an identical 135x23** on a 3-column pitch. Now 83/68/135/105/113 … ragged, on 3 lines. |
| `HStack{ wrap = true }` | **U** | `screens/ledger.luau` chart legend | Three plaza-name chips, all forced to 135x23 across **two** rows with a dead third cell. Now 113/135/113 on **one** line. |
| `HStack{ wrap = true }` | **U** | `screens/chatter.luau` post tags | Every post's two tags came out the same width as each other (105/105, 113/113, 83/83, 135/135, 90/90, 105/105 across the six seeded posts). Now ragged in 5 of 6. |
| `HStack{ wrap = true }` | **U** | `screens/plaza.luau` summary — **a `ViewThatFits` ladder deleted** | See "the trap, found live" below. |

### p4_foyer — 3 adoptions

| Capability | Verdict | Site | Evidence |
|---|---|---|---|
| `HStack{ wrap = true }` | **U** | `MetaFits`, the tile meta row | **The strongest single proof in the set.** The ladder's own comment read *"reflow, never squeeze"* — which is the definition of a flow wrap, written in prose by an author who had no word for it and built a two-rung `ViewThatFits` instead. Verified at `preferredTextSize` +14: `Approval` @ y1872, `Chip` @ y1934 — a genuine second line, from one node set. |
| `distribute = "spaceBetween"` | **U** | `MetaFits` (per line), section `Header`, detail `Footer` | Replaces three hand-placed `UI.Spacer({})`. It also *had* to replace the one inside `MetaFits`: a `fill` main-axis child takes a whole line to itself in a wrapping stack, which api.md states and the framework reports. |
| `layoutPriority` × `shrinkWeight` | **A** | `TopBar` | Tried and **reverted**. See "the gap this session actually hit". |

### p5_wardrobe — 2 adoptions

| Capability | Verdict | Site | Evidence |
|---|---|---|---|
| `HStack{ wrap = true }` | **U** | `WornRow`, the stage-fallback worn chips | A bare `ForEach` under a `VStack` gave **every worn piece its own line**: five equipped categories measured at y = 93, 116, 139, 162, 185 — a 115px column of short words on a plate already competing with the preview pane for height. Now all five at y = 93, one line, 15px. |
| `distribute = "center"` | **U** | same | And this is the case that *could not be hand-built*: a `ForEach` row returns exactly one blueprint, so no `Spacer` could ever be interleaved, and the chip count follows what the player is wearing. api.md says this explicitly under `distribute`, and it is why the prop exists. |

### p1_glade, p3_sipworks — deliberately unchanged

Surveyed in full; **no change shipped, with reasons**. This is a legitimate
outcome and the reasons are the finding:

- **Neither app contains a chip/tag/badge cloud at all.** Every `parts.chip` call
  site in p1 is a lone child of a `VStack`; p3's three `surface = "chip"` nodes
  are full-width or toast chips. There is nothing for `wrap` to claim.
- **Both apps' `Grid` sites are legitimately uniform.** `p3_sipworks` `Tiles`
  (`views/detail.luau:225`) is a grid of 96px *art plates* under centred labels —
  `intrinsic` + `uniform` is exactly the contract that keeps the plates aligned
  across rows, and the existing comment explains why a px literal was worse. Same
  for `rewards.luau` `Seals` (a 2×5 stamp card, `columns = 5`), and for p1's
  `Cards`/`WispCards`/`FloraCards`, all of which use a numeric `minColumnWidth`.
  A ragged wrap would **break** all five.
- **`percent` is justified in p3 and `containerRelativeFrame` would be wrong.**
  Two of the uses *are* the flip animation (`views/parts.luau`), one is
  necessarily parent-relative against a collapsing face, and every capped card box
  uses `percentMax` — for which `containerRelativeFrame` has no equivalent (see
  the gap list). Only `views/shell.luau:417` is a clean crf candidate, and it is
  low value.

## The trap, found live — and it was worse than the precedent

The brief warned about `06_tile_game`: a `ViewThatFits` ladder wrote its readouts
twice, moving them off their published paths past a green suite, because a losing
candidate satisfies a presence assertion **at a deliberate zero rect**.

`p2_cartwheel`'s plaza summary was the same defect, and measurably worse:

- `Charge` existed at **three** published paths (`Summary/Full/Charge`,
  `Summary/Two/Charge`, `Summary/One/Charge`);
- the two losers measured **8x0 at 733x313, 1024x768 and 1440x900** — *every*
  viewport this section is reachable on. **The ladder never once chose them.**
  They were pure dead weight for the whole life of the app;
- and the ladder's purpose was to **drop facts**: narrowing the card deleted
  "Trending", then "Popular". A summary chip is a fact about the plaza. The honest
  narrow form is the same three chips on two lines.

`p4_foyer` carried the identical shape at a higher price: the losing `MetaColumn`
rung needed its **own `newLabel` control** (`ApprovalB`, a second disposable per
tile) plus its own `When`/`ChipB`.

**Every case added here reads `screenRectOf` and insists on a non-zero rect at a
named path.** A presence assertion would have passed with either ladder intact.

Node count, p4_foyer, 1400x900: **601 → 454 (−24.5%)**, and **24 mounted
`Spacer` instances → 0**.

## The `align` double-read (a real trap when a ladder comes out)

Promoting a ladder's inner `align = "center"` onto the wrapping container that
replaces it **moves pixels**. On a wrapping stack `align` places the *block of
lines* on the cross axis, and the parent *also* reads a child's own `align` as
that child's cross placement. Keeping it slid the plaza summary 80px right, off
the card's leading edge (x 270 → 350, measured 1440x900). It was a no-op on the
ladder's inner row (chips are one height) and load-bearing twice once promoted.

api.md's wrap table does document both readings; it does not warn that migrating
a ladder is where they collide. Suggested one-line addition under the table —
**for agent A, whose file this is**:

> When a `ViewThatFits` ladder is replaced by `wrap = true`, do not carry the
> losing rung's `align` up onto the container: on the inner row it was cross-axis
> only, but on the container the PARENT reads it too.

## The gap this session actually hit

**A text node cannot be told to yield below its longest word**, so
`layoutPriority`/`shrinkWeight` cannot rescue a row whose deficit sits in a
single-word label.

`p4_foyer`'s `TopBar` reports *"content overflows this hstack by 46px on the main
axis"* at 390x844 with `preferredTextSize` at **+4 and +14** — the phone, at two
of the four shipping text offsets. It is a **pre-existing defect**, not a
regression (verified by stashing every edit; the diagnostics are byte-identical),
and it was invisible because the proof's five-view sweep raises `displaySize` and
**never `preferredTextSize`**.

The round-2 shrink pair looks like the answer and is not. Applied
(`Brand` tier 0 weight 1, `SearchSlot` tier 1) the overflow stayed at **exactly
46px**, and the framework said why — a genuinely excellent diagnostic:

> every shrinkable child is already at its floor (layoutPriority order tried: 0)

A text node's shrink floor is its longest word; the brand is the single word
"Foyer", which measures **224px at title+4**. There is nothing for a weight to
give. The props were **deleted rather than left in place looking like a fix**, and
the measurement is recorded in the source at the site.

The lever that would close it does not exist in any round: something like a
`truncatesBelowFloor` / explicit shrink floor on `Text`. Today the only tool is a
hand-chosen `minMax` cap — exactly the kind of magic number the shrink pair was
introduced to retire. **Cross-checked against
`parity-completeness-audit-2026-08-13.md`: this is not among its 39.**

## Documentation defects found

1. **`rowSelectable` / `rowMovable` / `rowDeletable` — shipped this round, and
   `docs/reference/api.md` has ZERO occurrences of all three.** Nothing in
   `docs/guide/**` either. Undiscoverable by any means short of reading `src`.
   *(agent A's file — reported, not edited.)*
2. **Seven round-2/3 APIs appear in `api.md` but in no guide file at all**:
   `containerRelativeFrame`, `shrinkWeight`, `layoutPriority`, `sensoryFeedback`,
   `withAnimation`, `GridRow`, `gridSpan`. `distribute` reaches the guide only in
   `01-concepts.md`. An author working the way these apps were authored reads the
   guide first; every one of these is reachable only by already knowing its name.
3. The `align` migration note above.

`wrap` itself is the counter-example and the reason all seven adoptions here are
**U**: its api.md entry is the second paragraph of the `VStack`/`HStack` section,
states the four rules worth knowing before you reach them, and includes the table
that resolves `align` vs `lineAlign` vs `distribute`.

## Findings recorded but NOT acted on

Surfaced by full reads of all five apps; each is a real shape, none was shipped
because none could be proved as cleanly as the seven above inside this item.

1. **The duplicated-readout ladder is systemic.** Seven further `ViewThatFits`
   ladders re-emit the same ids in more than one candidate:
   `p1_glade/init.luau:865`, `:895`, `p1_glade/ui/overview.luau:303`,
   `p3_sipworks/views/detail.luau:140`, `views/shell.luau:139`, `:162`, `:191`.
   Both apps' scenario runners address nodes by id-path tail, so the drift is
   load-bearing. **Recommend a dedicated follow-on**; it is bigger than D3.
2. **Three of those seven are not content step-downs at all** —
   `p1_glade/init.luau:895` and `p3_sipworks/views/shell.luau:139`, `:162` pass
   `short = true` on *both* rungs: identical labels, identical ids, differing only
   in `hug` vs `fill`. That is a distribution choice spelled as a remount.
   **Deliberately left alone**: these are the HIG tab-bar ladders and the
   hug-caps-the-offer construction was hard-won. Any change needs its own round.
3. **Indeterminate circular progress has ~10 genuine sites and zero adoptions.**
   Every "working" state in all five apps is a text swap — "Visiting…",
   "Confirming…", "Placing…", "Unlocking…", "Working…" — usually paired with a
   disabled control. Two are stronger still: `p4_foyer`'s `Refresh` and
   `p5_wardrobe`'s per-card pending render an observable pending window as *pure
   absence of interactivity*, with no visible token at all. Not shipped here
   because adding a spinner to a proof is a **design** decision (where it sits
   relative to the label, whether every card gets one), not an API swap — and the
   `xa` label-swap width jump it would remove deserves its own measurement.
4. **`p5_wardrobe:257` is a false positive for `distribute`** and is worth
   recording as such: the modal footer is `Confirm`, `Cancel`, `Spacer`, `Close` —
   a 2-and-1 split. `spaceBetween` would push `Confirm` and `Cancel` apart from
   each other too. The existing `Spacer` is the simpler correct code.
5. **`p1_glade/ui/detail.luau:87` and `p3_sipworks/views/book.luau:317`** carry
   their own diagnosis in comments (*"none of them yields — so the gaps are the
   only slack there is"*) and are the clearest remaining
   `layoutPriority`+`shrinkWeight` sites. Unlike p4's `TopBar` these have real
   multi-word children with somewhere to go.

## Method note, stated honestly

Each app was worked from `docs/guide/**` and `docs/reference/api.md`, never from
`src/`. The two full-app *surveys* were delegated, and those subagents did read
`src/blueprint_schema.luau` and `src/blueprint.luau` to check spellings. They
located and judged shapes; every adoption decision, measurement and doc verdict
above is from the public docs. The **U** verdicts were additionally probed
mechanically: for each capability, the term an author would search for was run
against `docs/guide/**` and `api.md`, and the results are what defect (2) reports.

## What shipped

- `examples/reference/p2_cartwheel/screens/{dashboard,ledger,chatter,plaza}.luau`
- `examples/reference/p4_foyer/init.luau`
- `examples/reference/p5_wardrobe/init.luau`
- `tests/reference/{cartwheel,foyer,wardrobe}_spec.luau` — 9 cases, 11 mutations
- `artifacts/swiftui-reference-app-validation/capability-ledger.md` — gap #3 spent
- all five `examples/places/Facet-Ref-*.rbxl` rebuilt

---

## E shipped — the chrome is reachable on four inputs, and the settings surface exists

Item **E** rows 4 and 11: *"chrome is unreachable by keyboard and gamepad"* and
*"reduced-motion settings surface — NOT BUILT, hard-blocked behind #4"*.

### 1. The defect was bigger than the row said, and the extra half was measured

Row 4's claim held exactly: both pickers presented `responder = "passive"`, a
passive surface's nav context is created **disabled** (`presenter.luau:2595-2603`),
Tab and Space bind only while the responder is **engaged** (`:2839-2842`), and the
only `engage()` call in `src/` is inside the presenter's **tap** handler
(`:2248`). No key and no pad button was bound to `demo_picker.showNext` anywhere,
despite the comment at `demo_picker.luau:225` promising "the gamepad/keyboard
path".

**What nothing had reported is that the demo was unreachable too.** A presented
surface pushes a focus **scope**; `focus_graph` navigates the **top** scope only
(`navigate`, `traverse` and `focusOn` all read `top()`); and the old chrome
re-presented itself after every demo mount, because z-order is present order. So
the chrome's scope was permanently on top. Driven headlessly on the shipped
assembly before any change:

| press | result |
|---|---|
| `Tab` | focus → `/ShowcaseChrome/Chips/DemoToggle` (a chip on a **passive** surface, so no ring paints) |
| `Return` / `ButtonA` | **nothing** — `dispatchActivate` ran against the **demo's** handle with a chrome path, found no node, and no-opped |
| `Down` | focus stayed on the chip; no key reached a single control of the demo on screen |

Keyboard and gamepad were dead in **both** directions. That is why the fix is a
restructure rather than one `engage()` call.

### 2. The chrome shape chosen: one strip that never moves, one panel that comes and goes

Present order is z-order **and** focus-scope order, and a closed chrome needs
opposite answers for the two: the strip must be visible (it is, and it can never
be covered, because `coreSafeInsets.top` is reserved from the chips' own measured
bottom edge) while the **demo** must own the focus scope. One surface cannot do
both; two can.

- **`ShowcaseChrome`** — the two chips. Presented **once**, before the first demo,
  and never re-presented. Passive, `edgeToEdge`, and it feeds `chipsBottom`
  through `onGeometry` exactly as before. Its scope stays buried, so Tab and the
  d-pad belong to the demo.
- **`ShowcasePanel`** — presented when a target opens, dismissed when it closes.
  Presented last, so it draws over the demo and owns the top scope;
  `initialFocus = "first"` and `engage()` on every open, so Tab/Space/arrows/A/B
  are bound and sunk while it is up; **dismissed on resign**, so pad `Cancel`, an
  outside tap and the toggle key all put the demo back — `removeScope` restores
  focus to the surface beneath.

The bar **never** engages. A tap on a focusable inside a passive surface engages
it, so opening resigns the bar in the same breath: two engaged surfaces both sit
at the engaged band's 3000, both receive `Traverse`, and one Tab press would step
the ring twice. That is now an assertion (`one Tab press moves the ring one step,
not two`), and mutation **M3** proves it bites.

The structural half moved out of `init.client.luau` into
**`examples/gallery/client/showcase_chrome.luau`**. `init.client.luau` is a
LocalScript that reaches engine globals at load, so anything built inline there
can only be checked by reading its source text — which is the shape of check the
brief singled out (`gallery_theme_picker.spec.luau:194` asserting a file
*contains* `responder = "passive"`). The chrome is now mounted and driven for
real by `tests/gallery_chrome.spec.luau`.

### 3. Two targets forever, and the ladder that replaces the character clip

`[SHOWCASE-CHROME]: CONCERNS 16` stands as written. The strip carries **which
demo** and **settings**, and the chips step down a `UI.ViewThatFits` ladder to
**icon-only** (`menu` and `more`, both already in `src/themes/standard_icons`;
the standard set ships no gear and inventing one is art plus an upload, not a
chrome restructure) rather than clipping labels by character count.

`p4_foyer` is the reference, including its trap: both rungs are sized
`{ type = "content" }`, not `hug`, because **`hug` caps at the offer and a capped
row can never tell a `ViewThatFits` that it does not fit** — the ladder silently
pins its first candidate and the labels truncate anyway. Mutation **M10** flips
exactly that word and reddens the 320 px case and the sweep.

`CHIP_LABEL_CHARS = 14` survives on the **standalone** picker path only (the
eight single-example places assert geometry against it); the composed chip now
carries the demo's real title and lets the ladder decide. `Temperature converter`
+ `Settings` is what forces the icon rung at 320×640 — mutation **M22** puts the
clip back and the case reddens, which is the arithmetic CONCERNS 16 did, executed.

### 4. The bindings, and why these two

The vocabulary is closed (`constitution.md` §9), so no new verb was invented: the
chrome's own context declares **`Activate`** — "activate the chrome" — and
nothing else. Everything after that press is the framework's own: `Navigate`
walks the panel, `Traverse` walks it linearly, `Activate` presses a row, `Cancel`
leaves.

| class | key | why |
|---|---|---|
| keyboard | **`Backquote`** | `Escape` is engine-reserved, so there is no keyboard Cancel and the same key must toggle. `Tab` is `Traverse` (and CoreGui-contended), `Space`/`Return` are `Activate`, the arrows are `Navigate`, and a letter is contended by `05_word_game`, which reads the whole alphabet. Backquote is in none of those sets and is not in Roblox's hard-reserved set (`Esc`/`F9`/`F11`/`F12`/`PrintScreen`) |
| gamepad | **`ButtonY`** | `ButtonA` is `Activate` and is eaten unconditionally by the legacy `jumpAction` (`gamepad-contention-truths.md` truth 1); `ButtonB` is `Cancel`; `ButtonX` is the row-actions menu; `ButtonStart`/`ButtonSelect` are the platform's own menu buttons, and claiming those is the trade that lesson refuses. ButtonY is the one face button no verb in this framework claims |

The context sits at **priority 3500**, strictly above the engaged band's 3000, so
the toggle key still works while the panel it opened is engaged and sinking.
Sinking is per-**key** (`actions.luau`'s `deviceKey` only cuts candidates for the
same key code) and nothing else in the place binds either key, so this steals
nothing — asserted by pressing all twelve contended keys and requiring that none
of them toggles the chrome.

**One toggle key, two targets** is resolved inside the panel: its first control is
a segmented `newPicker` (`Demos | Settings`). The strip's chips say *open this*;
the segment says *which section am I in*. That is what makes both targets
reachable from one key, and it switches sections in one press on touch as well.

### 5. The settings surface, and what `with_animation` now composes to

`examples/gallery/client/settings_panel.luau` ships. It owns a **`Full | Reduced`**
segmented control — never "on/off": the env fact is binary but the effect is not
(`motion.luau:31-42`), and a caption under the control says so in words that must
survive pseudo-localization. A check enumerates every string in its exported
`COPY` and refuses `on`, `off`, `disable`. The theme picker's two sections are
composed into the **same card** (`theme_picker` now returns `sections` beside its
`panel`), so there is one raised scroller rather than a raised card inside a
raised card.

**The composition rule, decided and now asserted — one fact, two editors:**

- the settings control holds two signals: `setting` (the player's **preference**,
  written only by a press on it, via `newPicker`'s `onChange`, which fires only
  from `picker.choose`) and `mode` (**what is live**, mirrored from
  `reducedMotion`, and what the picker shows);
- `with_animation`'s inline control **stays** — it is the demo teaching its own
  subject — and now also **reads the fact back**. Open Settings over that demo,
  flip Motion, and the demo's own segmented control moves in the same frame.
  Before this it would have read "Full" over a screen that had stopped travelling;
- the demo's documented **restore-on-dispose is unchanged**: a change made from
  inside the demo is a **local override** scoped to that demo, which is the trap
  that rule exists for;
- the showcase host calls `settings.apply()` after **every demo mount**, so
  leaving a demo returns the place to the **preference** whichever control was
  touched last. That is what makes it a setting rather than a demo's side effect,
  and it is the exact sequence the case *"the host's re-apply is what makes the
  SETTING win over that restore"* drives.

Round 2's reason 3 is proved rather than restated: flipping the setting re-solves
**without rebuilding** — `handle.root.counters().factoryRuns` and the adapter's
instance count are both unchanged across the flip while `motionClock:isReduced()`
goes true. Mutation **M15** makes the write a no-op and the case reddens, so it is
not vacuous.

The reduced-motion axis of a device canary is now reachable without a pointer and
without that one demo on screen: `FacetShowcaseAPI.motion("reduced")`, plus
`chrome("demos"|"settings"|nil)` and a `toggleThemes` that routes through the same
`chrome.request` a chip press and the toggle key take.

### 6. What is asserted, and how

`tests/gallery_chrome.spec.luau` — 38 cases, **27 mutations, every one proved to
bite** (and one anchor that matched zero times was reported as BROKEN rather than
as "0 reddened"). Nothing in it reads source text; everything drives
`system.deviceKey(keyCode, isDown)` through the real `InputBinding` table or
`adapter.tap(path)` through the real hit path, against the real chrome on a real
presenter.

Groups: (0) a closed chrome leaves the demo's own input alone — the regression
above; (1) keyboard alone changes demo **and** theme; (2) gamepad alone changes
demo, theme **and** motion, with `capabilities.keyboard = false` so no keyboard
binding can be helping; (3) mouse/touch unchanged; (4) exactly one engaged
surface, one ring step per Tab, and no stolen keys; (5) the two-chip ladder;
(6)–(8) the settings model, its persistence across demo swaps, and its
composition with `with_animation`; (9) the sweep.

**The showcase rule in full.** The chrome is not reachable by
`tests/overflow_sweep.spec.luau` (that file sweeps demo surfaces under the
chrome's reservation, not the chrome itself), so group (9) sweeps it directly:
both surfaces, both sections, at all eight `device_views.VIEWS` viewports, under
**all eight shipped reference packages**, failing on either overflow axis — 128
mounts. Plus the 320×640 non-overlap case (the panel's top edge against the
chips' bottom, and the strip against the right screen edge) under every package,
and a ~1.4× pseudo-localization pass on the settings copy at three viewports
through a `copy` override the surface itself accepts.

### 7. What shipped

- `examples/gallery/client/showcase_chrome.luau` — new
- `examples/gallery/client/settings_panel.luau` — new
- `examples/gallery/client/init.client.luau` — the chrome block replaced by the module; `settings.apply()` on every demo mount; `motion` / `chrome` added to `FacetShowcaseAPI`
- `examples/gallery/client/demo_picker.luau` — `rows` (a plain stack for the panel's own card), `iconChip`, `onChip`/`onChose`, and the composed chip's label off the character clip
- `examples/gallery/client/theme_picker.luau` — `sections` beside `panel`
- `examples/gallery/scenarios/with_animation.luau` — reads the fact back; header updated
- `tests/gallery_chrome.spec.luau` — new, 38 cases, 27 mutations
- `tests/gallery_demo_picker.spec.luau` — the `pres.present` census follows the chrome out of the bootstrap
- `examples/places/Facet-Showcase.rbxl` rebuilt

### 8. Not closed

- **No Studio canary was run.** Row 3 of the ledger stays open; everything above
  is headless. The live questions this raises and does not answer: does a real
  `Backquote` reach IAS (injected keys are known-unreliable for some classes —
  `engine-input-truths-phaseb.md` items 3–5), and does a physical `ButtonY` fire
  `Activate` end-to-end (the standing `physical-device-confirmation` rider —
  a real pad button cannot be pressed headlessly or by injection).
- The panel's **section switch** is a second rendering of the same two targets
  that the strip's chips name. It reads as *which section* against the chips'
  *open this*, and it is what makes one toggle key serve two targets, but it is a
  judgement call a director may want to revisit on a device.

---

# Item D — the completeness audit's ranked gaps

`parity-completeness-audit-2026-08-13.md` ranked 39 unexamined SwiftUI
capabilities by "how likely a real Roblox game screen is to want it", and named
four more that already ship and had never been rowed. This section says what was
taken, what was deliberately left, and why — the audit is the record for
everything below the line, and the parity document's §13 now points at it.

## 1. The free parity, first — five rows, no library code

The audit's §4 was a **document defect, not a roadmap gap**, and it turned out to
be more interesting than "four missing rows". Verified in source, then rowed with
citations:

| Capability | Verdict it actually earned |
|---|---|
| `AsyncImage` → `Facet.newAsyncImage` | **Covered.** Its silent-failure rule is Apple's own, arrived at independently ([SW-132]) |
| `compositingGroup()`/`drawingGroup()` → `canvasGroup` | **Partial.** A `CanvasGroup` is grouped alpha and re-renders its children every frame; it is never `drawingGroup`'s cached bitmap |
| `.keyboardType` → `TextField.keyboardType` | **Partial.** Declared, validated, enum-closed, adapter-mapped — and **inert**, because `TextBox.TextInputType` is not writable from a LocalScript today. Capability-detected, so the day the engine opens it every declaration already in the tree starts working |
| `accessibilityReduceTransparency` → `effectiveTransparency` | **Partial.** The signal is first-class and fault-tested; **no shipped paint path reads it**. The one accessibility preference Facet reads and does not honour |
| `.onSubmit` → `onFocusLost(reason == "enter")` | **Composable**, scored so it stops looking like a gap. What is genuinely absent is the hierarchy-level submit channel |

**Two of the four were Partial, not Covered**, which is the useful half. The
audit's own column said "already ships"; reading the source said "ships and does
nothing yet" for two of them. A row that had said Covered would have been a new
false claim in a document whose whole rewrite was about removing those.

## 2. What was built — #12 and #16, and the judgement behind that pair

The brief said take the top of the ranked list and prefer finishing three
completely over starting six. **Two capabilities shipped complete; a third was
examined and refused.** The pair was chosen for one reason: both are cheap
*because a mechanism already existed and nobody had exposed it*, which is the
`the-solver-already-told-you` shape, and it is the only shape where a "prop"
cost estimate is trustworthy.

- **#12 `onAppear`/`onDisappear`** — mount scopes have owned this lifetime since
  phase one. Only the hook was missing.
- **#16's hide** — the renderer already had a per-node paint hold, a solver-side
  hidden set, a `hiddenRoots` the focus map filters on, and a hit-rect
  retraction. `hidden` is **one merge line into that set**.

### The two ordering decisions, made explicitly

Apple declines to specify these: *"The exact moment that SwiftUI calls this
method depends on the specific view type that you apply it to"* ([SW-138],
[SW-139]). So they are Facet's to define, and they are defined:

- **`onAppear` drains after that frame's layout solve.** The callback can read
  its own rect. It is still before anything reaches the screen, because a refresh
  is one synchronous call — so Apple's weaker guarantee ("completes before the
  first rendered frame appears") is met either way, and the earlier placement
  would have handed every hook a `nil` rect, which is the useless half of the
  capability.
- **`onDisappear` drains after the removal sweep.** Handle released, caches
  cleared, so `rectOf(path)` is `nil` *inside* the callback — asserted from in
  there, because that is the only place the ordering is observable.
- **Teardown fires every still-mounted hook.** A panel usually goes away by being
  dismissed, so a cleanup that only ran on re-keying would be a leak with a
  green suite. A pending appear is dropped there and the disappear still runs:
  a missed cleanup is the dangerous direction, an extra one is not.

### Why `hidden` dirties `arrange` and not `paint`

`paint` was the obvious answer and it was wrong. A paint-only channel would have
repainted the node and reached **none** of: the focus-order filter, the hit-rect
retraction, or the structure epoch the focus map is cached on. The result would
have been an invisible control that still takes Tab and still activates — which
is precisely half of what Apple's `hidden()` promises, shipped as if it were all
of it. Merging into the solver's own hidden set instead makes the prop inherit
every one of those for one line, and it means there is one hidden verdict in the
renderer rather than two that could disagree.

### The finding that came out of it, and cost a game-suite bisect

Apple's second clause — *"can't receive or respond to interactions"* ([SW-140]) —
needed a gate the framework did not have, because an authored `hidden` keeps a
**full-size box** on purpose, so no geometry stops an `Activated` reaching it.
The gate reads `solverHidden`, the merged verdict, so it also covers a losing
`ViewThatFits` candidate.

That turned out to be a live behaviour change, and the Rascal Rally suite caught
it within the hour. **Root-caused by instrumenting the gate**, not by reading the
diff: the sponsor results spec was driving `adapter.tap` into a CTA at
`.../CtaFit/CtaRow/CauseChaosRow` — rect **170×0**, its candidate root in
`hiddenRoots`, while the sibling `CtaColumn` was the pair actually on screen. The
same spec file already asserts three hundred lines later that `/CtaFit/` is
unreachable to a gamepad walk. The screen knew which form had lost; only the tap
did not.

No player could produce that tap — `Visible = false`, zero painted height — so
**no game behaviour changed**. What changed is that a synthetic drive can no
longer reach content nobody can see. It is the round-2 orchestration note ("a
test can be satisfied by a hidden copy") one step worse: this one *drove* the
hidden copy. Pinned framework-side with a clean-room `ViewThatFits`, and
game-side as `A37b`, which is the contract test for Facet's largest
`ViewThatFits` consumer.

## 3. What was deliberately left, and why each

### `opacity` — refused, and the refusal is the finding

The brief anticipated this: *"if that decision is bigger than a prop, say so and
stop rather than forcing it."* It is bigger than a prop, for a structural reason
rather than an effort one:

- `transparency` is owned by the **presentation** channel
  (`render/authority.luau:59`);
- the manifest's entire job is one authority per engine property per class, and
  it is asserted at the single write site;
- the schema has **no presentation channel** for an authored prop to declare —
  the five are layout / style / binding / handler / structural / semantic, and
  none of them fits.

So an authored `opacity` is either a second writer for the property the manifest
exists to keep single, or a **composition rule** — effective transparency as a
function of the authored value and the live presentation alpha — resolved at that
one site. Apple states the rule such a composition would have to honour: applying
`opacity` to an already-transformed view *"multiplies the effect of the underlying
opacity transformation"* ([SW-141]). And it would then need reconciling with
`withAnimation`'s fade records and with the native sheet's ownership of
`BackgroundTransparency`/`TextTransparency`. That is an ADR with a design round,
and forcing it into a prop round is exactly how a second silent authority ships.

**What already works and is easy to miss:** a whole subtree *can* be faded today,
through `controller.setPresentationTransparency` on a declared `canvasGroup` node.
The gap is authoring, not capability.

### `.disabled()` subtree cascade — examined, not taken

Taken only "if the first two land cleanly", per the brief. They did; this one
still should not have been, and the reason is worth recording because it is the
opposite of `hidden`'s:

**There is no existing set to merge into.** `props.enabled` has three independent
readers (`focus_map.luau:30`, the renderer's drag-source gate, the renderer's tap
gate) and no inherited channel. Worse, it needs a *paint* answer for the classes
that have no disabled look at all — a `Box`, a `Text`, an `Image` inside a locked
panel — which is a theme vocabulary, not a prop. Shipping the channel without the
paint would hand consumers a subtree that is **inert and looks live**, which is a
worse screen than no cascade.

### The other 36

Untouched and now enumerated rather than silent. §13 of the parity document
carries one row pointing at the audit's §5, so a reader who looks up rich text,
scroll snapping, `Section` headers, `Form`, pull-to-refresh or scroll observation
finds a ranked entry with a cost estimate instead of a silence they would
reasonably read as "considered and rejected". The six subsystems the brief ruled
out (#3, #7, #18, #19, #23, #39) stay ruled out.

## 4. Evidence

- **Suites.** Facet **4725 → 4803**. Rascal Rally **3149 → 3150** (A37b added;
  A37 fixed). Both green.
- **Mutations, 18 in total**, every anchor asserted to match exactly once before
  the run because a mutation that silently matches nothing reports "0 reddened"
  and is indistinguishable from an uncovered check. Eleven on the framework
  (drain removed; drain moved before the solve; departure never queued; the
  departing path keeps its rect; the authored hides never joining the solver's
  verdict; the hide not registered at mount; the tap gate removed; teardown not
  fanning out; `paint` instead of `arrange`; the live value never re-read; the
  hide surviving its own node's removal), six on the showcase, one on the game.
  Two of them **found real gaps on the first pass** — the remount case and the
  panel-order case exist because the mutation did not bite.
- **Performance, tier 1 (headless Lune, regression signal only).** Two ABBA
  rounds, `A B B A` then `B A A B`, arm B being the three touched `src/` files
  at `fba3158`. Same-arm spread measured in-session: **0.43 %–3.52 % Σp50** and
  **0.57 %–5.86 % Σp95**. Pooled delta **+1.08 % Σp50, +1.75 % Σp95** — inside
  the harness's own noise both by the declared whole-suite figures (2.69 % /
  4.99 %) and by the spreads measured beside it, **and the sign flipped between
  rounds** (+2.66 %/+4.90 % then −0.43 %/−1.23 %), which is the strongest
  available evidence that there is no effect to measure. `tools/perf.sh` PASS,
  20 scenes × 5 profiles, no budget moved.
- **Showcase.** `lifecycle_hidden` in `scenarios/init.luau` ORDER, swept by
  `overflow_sweep` on **both** axes at every viewport and every shipped theme,
  six headless cases in `examples_gallery.spec.luau` including the ~1.4×
  pseudo-localized run.

## 5. Owed

- **`demo_picker.DEMOS` registration for `lifecycle_hidden`.**
  `examples/gallery/client/**` belongs to a concurrently running agent this
  round and had uncommitted work in it; round 2 lost ~114 lines to exactly this
  situation. The entry to add:
  `{ id = "lifecycle-hidden", title = "Lifecycle & hidden", blurb = "One switch, two badges: the slot that stays and the events you cannot see", kind = "fixture", module = "lifecycle_hidden" }`.
- **No Studio canary and no device run** for either capability. Both are
  headless-provable in full — `hidden` is a `setVisible` write plus set
  membership, the hooks are queue drains — but "headless green is necessary,
  never sufficient" stands, and the one thing a device would answer that nothing
  here does is whether Roblox itself already refuses input to an invisible
  `GuiButton`. Roblox documents no behaviour there (checked 2026-08-13:
  `GuiObject.Visible` describes rendering and `UIListLayout` participation and
  says nothing about input), which is why the framework holds the rule itself
  rather than relying on the engine.
- **The place is not rebuilt.** `tools/build_places.sh` was not run for the
  showcase after `lifecycle_hidden` landed, because the registration above is
  outstanding and a place built without it would have to be rebuilt again.

---

## The accessibility-text-size axis on the always-on sweeps (2026-08-13)

Game-director approved the same day. The always-on overflow sweep varied display
SIZE and never varied TEXT SIZE, and that blind spot bit twice in one sitting,
found independently by two agents: the perf lab's virtualized rows overflowed
their fixed slot by 11/39/59px at `preferredTextOffset` 4/10/14 (clean at 0, so a
headless run and a default Studio session both saw nothing), and
`examples/reference/p4_foyer`'s `TopBar` was found overflowing its hstack —
**pre-existing**, verified byte-identical with every edit stashed, invisible for
exactly the same reason. This section records what was built, what it costs, what
it found, and what it still does not ask.

### What landed

- **`tests/overflow_sweep.spec.luau`** now sweeps 42 surfaces × 8 viewports ×
  **4 accessibility preferences** — the whole cross product, nothing dropped.
- **`tests/example_readouts.spec.luau`** gained the same axis. Its blind spot was
  sharper: the defect it exists for is a readout that lost a `ViewThatFits`
  candidate ladder, and which candidate wins is a function of the text preference.
- The offsets are **read from `tests/lib/large_text.PREFERENCES`**, not written in
  either spec, so `{ Medium 0, Large 4, Larger 10, Largest 14 }` (decision LTN-1,
  measured live 2026-08-03) has exactly one home and a fifth preference would
  arrive in both sweeps without an edit.

### The cost, and why the full cross product is affordable

A 4× multiplier on an always-on instrument had to be measured before it was
chosen. Both shapes were built and timed on the same tree, back to back:

| shape | overflow-sweep case time | delta |
|---|---|---|
| pre-axis (offset 0 only) | 845 / 849 ms | — |
| **re-mount** each surface once per preference | 3339 ms | +2.5 s |
| **mount once, swing the preference live** | 2177 / 2113 ms | **+1.30 s (~+2.7 % of a ~48 s suite)** |

The swing is what shipped. It is the seam a player actually uses —
`PreferredTextSize` changes while the experience is running — and the suite
already pins it as equivalent to a fresh mount (`tests/large_text_hot_swap.spec`,
LTSWAP-BORN: "a screen BORN at Largest matches one swung there live"). It was also
verified directly for this corpus rather than assumed: **both modes produced the
same 304 findings, byte for byte**, across all 42 × 8 × 4 cells. The readout sweep
paid +152 ms (98 ms → 250 ms) for the same axis.

### Why nothing was narrowed

Two narrowings looked defensible; the measurement says both are wrong, which is
why the sweep runs the full product instead:

- **"Just the extremes, 0 and 14"** misses `03_settings_sync` `/Settings/Page/State`,
  which overflows by **24px at +4 and is clean at +10 and +14**. The preference
  axis is **not monotone** — a larger preference reflows the page and can hand a
  box more room than a smaller one did. `p5_wardrobe`'s item card is the same
  story at 640×320: it fires at +4 and +14 and *not* at +10.
- **"The full set only at the narrowest viewport"** misses **5 of the 35**
  findings, four of them `p2_cartwheel`'s, which appear **only** at
  tablet-landscape 1079×809 — and it would drop **61 of 304** findings at
  console-ten-foot 1920×1078, where the `Large` display class multiplies the type
  scale by 1.5 **on top of** the preference. Narrow is where large-text risk is
  easiest to imagine, not where it lives.

### The mutation, and its negative control

Both anchors were asserted to match **exactly once** before the run (this session
had a sibling mutation silently match nothing and report a false "0 reddened").

1. **A real swept surface, mutated to overflow only at a large preference.**
   `examples/gallery/scenarios/probe.luau`'s twelve rows were changed from a
   `UI.Text` of fixed height 30 to a fixed-height-34 `UI.VStack` wrapping the same
   text — a body line is 20px at +0, 24px at +4, 32px at +10 and 36px at +14, so
   the slot fits at every preference but the largest.
   - **With the axis:** RED, `scenario 'probe'`, **108 findings = 12 rows × 8
     viewports × the +14 pass only**.
   - **Without it (the pre-axis sweep, `OFFSETS = { 0 }`):** `scenario 'probe'`
     **GREEN**. That is the negative control the axis is worth its 1.3 s for.
   - The file was restored byte-identically (md5 verified, `git status` clean) and
     was never staged.
2. **A permanent control case in the spec.** `AXIS CONTROL: a slot sized for
   Larger is SILENT at +0/+4/+10 and REPORTED at +14` mounts a 102px slot holding
   three body lines (60/72/96/108px at the four preferences) through the same
   world, settle and collector the surfaces use, and asserts the silence as
   strictly as the finding — including the exact 6px overflow. If the axis is ever
   disabled, this case says so on that run.
3. **The waiver machinery, three mutations, each red exactly where it should be:**
   lowering one ceiling (`p4_foyer` `/Foyer/Root/TopBar` 10 → 9) reported
   *"WORSE than the recorded waiver: 10px against a 9px ceiling"*; raising one
   `since` (`composition` `/CompositionScreen/Body/OfferBar` 4 → 10) reported
   *"EARLIER than the recorded waiver: reported at +4, recorded from +10"*;
   renaming one node (`progress_ring` `Dots` → `DotsX`) reddened both the surface
   (a new unwaived finding) and the stale-waiver case.

### What it found: 35 defects, and why the sweep still ships green

Turning the axis on produced **304 findings, collapsing to 35 distinct
(surface, node) defects** — keyed siblings (sixteen wardrobe cards, seven rail
cards, six list rows) are one template and are recorded once. **Zero of them are
at offset 0**: every one was invisible to the pre-axis sweep, which is the whole
argument for the axis.

None of the 35 is in a file this mission owned, and **a permanently-red always-on
check is worse than none** — it teaches people to skim the suite, which is exactly
how the nine device bugs shipped. So the axis lands green over an **enumerated
waiver list in the spec**, under three rules that keep it a to-do list rather than
a shrug:

1. **Nothing is waived at offset 0.** The pre-axis contract is untouched.
2. **A waiver is a ceiling, not a pardon.** `px` is the largest overflow measured
   and `since` the smallest preference that reports it; a finding that exceeds the
   ceiling, or that appears at a *smaller* preference, fails.
3. **A waiver that fires nowhere fails too.** Fix a surface and the suite tells you
   to delete the line, so the list can only shrink.

**Triage classes.** `fixed-px-vs-text` = a px extent fixed against content that is
not (`docs/lessons/facet-fixed-px-heights.md`); `row-cannot-shrink` = a row of
labels or controls wider than the screen with nothing allowed to shrink;
`page-not-scrollable` = a whole surface taller than a short canvas (usually
640×320) with no page scroller; `wrap-clamp` = a `hwrap` line clamping a child it
could not fit. **Not one of the 35 carries the solver's *"every shrinkable child is
already at its floor"* suffix**, so every one of them is still repairable by
authoring — a `shrinkWeight`, a `ViewThatFits` rung, a wrap — rather than blocked
on the framework.

| px | surface | node | from | class | where |
|---:|---|---|---:|---|---|
| 198 | composition | `/CompositionScreen/Body/OfferBar` | +4 | row-cannot-shrink | 320×640, compact-portrait |
| 113 | virtual_list_native | `/VLNative` | +4 | page-not-scrollable | both narrow + both compact |
| 109 | row_actions `[vlist]` | `/MailActions/VListWhen/then/VListPane` | +4 | fixed-px-vs-text | 320×640, 640×320, compact-landscape |
| 95 | sponsor_list | `/ListLab/Body/Controls` | +10 | row-cannot-shrink | 320×640, compact-portrait |
| 92 | adaptive_controls | `…/Hud/Legend` | +10 | row-cannot-shrink | four phone views |
| 92 | theme_authoring | `…/Hud/Legend` | +10 | row-cannot-shrink | the same fixture under the theme package |
| 82 | 07_match3 | `/Match3/Page/Stats` | +10 | row-cannot-shrink | the device-bug round's own ladder runs out of rungs at +10 |
| 68 | card_rail | `…/W/[*]/Row/Card` | +10 | fixed-px-vs-text | 640×320, compact-landscape (7 cards, one template) |
| 64 | sponsor_billboard | `/BillboardLab` | +4 | page-not-scrollable | 640×320, compact-landscape |
| 59 | composition | `…/Summary/Actions/ActionsRow` | +10 | row-cannot-shrink | 320×640, compact-portrait |
| 52 | p4_foyer | `…/FeedPage/Sections/[*]/Body/Header` | +10 | row-cannot-shrink | 320×640, compact-portrait (4 sections, one template) |
| 46 | drag_session | `/DragLab` | +4 | page-not-scrollable | 640×320, compact-landscape |
| 43 | p4_foyer | `…/HomeBody/TabRow` | +10 | row-cannot-shrink | 320×640, compact-portrait |
| 43 | authoring | `/AuthoringScreen` | +4 | page-not-scrollable | 640×320, compact-landscape |
| 36 | row_actions `[table]` | `…/TablePane/MailTable/Main` | +10 | fixed-px-vs-text | 640×320, compact-landscape |
| 35 | sponsor_list | `…/W/[*]/Row/Card/Labels` | +10 | fixed-px-vs-text | the row-height memo caps the detail at **two** caption lines; at +10 it needs three |
| 30 | p2_cartwheel | `…/Sky/Skyglow/Axis` | +14 | row-cannot-shrink | tablet-landscape **only** |
| 26 | p2_cartwheel | `…/ChatterCard/OpenChatter` | +14 | row-cannot-shrink | tablet-landscape **only** |
| 26 | scroll_host | `/ScrollHost` | +10 | page-not-scrollable | 640×320, compact-landscape |
| 25 | async_images | `/AsyncImages` | +10 | page-not-scrollable | 640×320, compact-landscape |
| 25 | row_actions `[table]` | `/MailActions/TableWhen/then/TablePane` | +10 | page-not-scrollable | 640×320, compact-landscape |
| 24 | 03_settings_sync | `/Settings/Page/State` | +4 | fixed-px-vs-text | compact-portrait **at +4 only** — the non-monotone cell |
| 24 | p5_wardrobe | `…/PickedGrid/Items/[*]/*` | +4 | fixed-px-vs-text | six of eight views |
| 24 | p5_wardrobe | `…/PickedGrid/Items/[*]/*/Col/Meta` | +10 | row-cannot-shrink | 320×640, ten-foot |
| 24 | p5_wardrobe | `…/RestGrid/Items/[*]/*` | +4 | fixed-px-vs-text | six of eight views (12 cards, one template) |
| 24 | p5_wardrobe | `…/RestGrid/Items/[*]/*/Col/Meta` | +10 | row-cannot-shrink | 320×640, ten-foot |
| 23 | perf_capture | `/PerfCapture` | +10 | page-not-scrollable | 640×320, compact-landscape |
| 20 | progress_ring | `/ProgressRing/Page/Dots` | +14 | row-cannot-shrink | 320×640 only |
| 16 | p4_foyer | `…/ContentHost/HomeWhen/then/HomeBody` | +4 | page-not-scrollable | 640×320 only |
| 16 | sponsor_toast | `/ToastLab` | +10 | page-not-scrollable | 640×320 only |
| 12 | sponsor_avatars | `/AvatarLab` | +10 | page-not-scrollable | 640×320 only |
| **10** | **p4_foyer** | **`/Foyer/Root/TopBar`** | **+14** | **row-cannot-shrink** | **320×640 only — the reported defect, reproduced** |
| 8 | sponsor_drop | `/DropLab/Main` | +14 | page-not-scrollable | 320×640 only |
| 5 | p2_cartwheel | `…/RackSlot/Rack/OpenPotions` | +14 | row-cannot-shrink | tablet-landscape only |
| 0 | p2_cartwheel | `…/ChatterCard/Cloud` | +14 | wrap-clamp | `Tag3` clamped by 0px, the degenerate end of the class |

The two heaviest are worth naming as design defects rather than constants:
`composition`'s `OfferBar` runs **198px** past a 320px phone, and
`virtual_list_native` is **113px** taller than a 640×320 landscape with nothing to
scroll it. The most instructive is `sponsor_list`'s row — its height is *already*
derived from live theme facts and the preference offset (the fixed-px lesson
applied), and it still overflows, because the derivation caps the detail line at
two caption lines and large text needs three. Deriving the height was necessary
and not sufficient.

### What is still NOT covered — logged, not silent

- **The locale axis.** Both sweeps run one locale (each surface's default copy).
  It is an independent expansion axis and it is *stronger* than this one on at
  least one surface: `p4_foyer`'s `TopBar` is clean at 390×844 in English at every
  preference and overflows by **33px at +10 and 58px at +14** under the shipping
  1.4× `xa` pseudo-locale — and at 359×718 it overflows by 2px there **at +0**.
  Measured 2026-08-13; not swept.
- **390×844 is not a swept viewport.** The reference agent measured the `TopBar`
  finding there; the sweep reaches the same node at 320×640 and 359×718. Adding
  the plan's canonical phone would cost ~1/8 of both sweeps and was not taken.
- **The perf lab** (`examples/performance/**`) is not a swept surface, so the
  first of the two reported defects cannot be reproduced by this instrument. It
  was fixed at `8b11393` before this work began.
- **`tests/lib/tiers.luau` still records `overflow_sweep.spec` at 1036 ms** with
  the reason "37 showcase surfaces x six viewports x both orientations". Both
  numbers are now stale (≈2.5 s, 42 surfaces, eight viewports, four preferences).
  The file belonged to another agent this round; the tier spec only asserts
  `ms > 250`, so nothing is red — it is a one-line correction owed.
- **The readout axis found nothing, and that was verified rather than assumed.**
  An independent probe checked every node of all seven tutorial examples at all
  eight viewports: **no node that has area at +0 loses it at +4, +10 or +14**. The
  axis there is insurance against the candidate-ladder class returning, at +152 ms;
  it has no real mutation to bite on today.

# The lying `itemExtent` guard (2026-08-13, game-director approved)

`newVirtualList` windows by `index × itemExtent`. That arithmetic is O(1) and
exact **only because the extent is one declared number** — and the control makes
the CONSUMER predict its own row's height, for every live fact the cell reads.
Nothing checked the prediction.

The case study is the perf lab's `rows.heightFor`, whose own comments record it
learning each input *after* that input broke something: viewport width, then the
type scale (the ten-foot row overflowed its 56px slot by **3px**), then the theme
insets (**19px** under fantasy-ornate), and — found on a real device on
2026-08-13 — never the accessibility text preference (**11/39/59px** at
`preferredTextOffset` 4/10/14, and the lab refused to mount). Four inputs, three
of them added post-mortem. The class is `docs/lessons/facet-fixed-px-heights.md`.

The director's ruling was to build the CHECK, not variable extents.

## The mechanism, and why this channel

A **runtime solver diagnostic**, not a construction refusal.

`virtual_list.luau` stamps every row's ZStack with a new public `ZStack` prop —
`virtualSlot = { list, extent, axis?, contentFrom? }` — and `solver.luau`'s zstack
arrange compares the slot's content measure against `extent` on the list's axis.

- **Construction cannot know the answer.** A row's true extent is a function of
  the viewport, `typographyScale`, `themeMetrics` and `preferredTextOffset`; the
  first two are not decided until a solve. A spec guard could only re-check the
  arithmetic the consumer already got wrong.
- **The diagnostic channel is enforced.** `tests/overflow_sweep.spec.luau` fails
  the suite on solver findings, the perf lab refuses to mount with one, and
  RascalRally's own fixtures assert an empty `diagnostics()` at four preferences.
  This is the channel `docs/lessons/the-solver-already-told-you.md` exists to make
  people read.
- **It compares against the DECLARED extent, never the row's current box.** A
  hosted row-actions commit collapse drives one row's box down its own height
  ladder on purpose; reading the box would make that animation shout.
- **It does not excuse a `fill` axis** — the one place in `solver.luau` that
  doesn't. A slot is a declared px cap, never a grant, so `height = fill` on a
  cell is a statement about paint and not about fit. The exception that survives
  is the one `zstack_fill_diagnostic.spec` was written for: a child that scrolls
  or clips absorbs its own overflow (`absorbsOverflow`).
- **`contentFrom = 2`** keeps the control's own full-row hit Button out of the
  comparison. Measured: an empty-label hit is 24px whatever the slot is, so
  without it every list denser than 24px would be accused of a lie the framework
  itself wrote.
- **One shared table per list**, not one per row: every field is a property of the
  LIST, and the row's identity is already its node path (`…/W/[key]/Row/…`), which
  is what the finding is filed under. A row's marginal cost is one prop
  assignment.
- The finding **names both numbers**: *"newVirtualList 'VL' declares itemExtent =
  56, but this row's content measures 74px on the list's y axis — 18px taller than
  the slot it is windowed into"*. The sibling overlap finding's advice (a `minMax`
  FLOOR rather than a fixed CAP) is exactly the wrong repair for a windowed row,
  so on the axis this names, that finding is suppressed — the cross axis still
  reports through it, so a row that is also too wide still says so exactly once.

`newTable` is deliberately NOT marked: it caps each cell's line count against
that row's own height (`table.luau`'s `capFor` — "physically unable to paint
outside the row it belongs to"), so it does not hand the consumer an uncapped
slot the way this control does.

## The tolerance, measured rather than picked

The comparison is `math.floor(measured - extent + 0.5) > 0` — round-to-nearest,
the same rounding the sibling overlap finding uses, i.e. **0.5px and no more**.

That was measured, not assumed. A probe printed `measured - extent` for **every**
marked-row comparison in both suites:

| suite | comparisons | distinct lists | deltas in (0,1)px | tightest fitting row |
|---|---|---|---|---|
| Facet (4819 cases) | 56 298 | 7 | **0** | exactly 0.0 |
| RascalRally (3150 cases) | 5 143 | 1 | **0** | −17.0 |

The distribution is quantized: an honest row lands on **0 or below**, and the
smallest defect anywhere in either suite is **+2px**. There is no band a slack
tolerance could sit in, and any tolerance ≥ 3px would have silenced the ten-foot
row's original 3px overflow — the very defect that taught `heightFor` about the
type scale. Direction is asymmetric on purpose: content SHORTER than its slot is
legitimate over-reservation (the lab's own `ROW_HEIGHT` comment calls a slot a few
px too tall the correct direction) and says nothing.

## Off-path cost — `tier 1 (headless Lune, regression signal only)`

Off the path it is **one `nil` field read per ZStack** (`local slot =
node.virtualSlot`, hoisted out of the child loop) plus one `slot ~= nil` test per
child inside a block that was already gated on `hiddenDepth`. On the path it adds
**no measure**: it reuses the `measure(ctx, child, innerW, innerH)` the overlap
diagnostic already takes, which is memoized per solve.

`tools/perf.sh`, ABBA (A B B A A B B A, 8 runs × 20 scenes × 5 profiles, quiet
machine). Same-arm spread first, then the delta:

| aggregate | arm A spread (no guard) | B vs A |
|---|---|---|
| whole-suite Σp50 | 2.72 % | **−1.42 %** |
| whole-suite Σp95 | 4.72 % | **−1.94 %** |
| the 5 VirtualList-bearing scenes, Σp50 | 3.48 % | −1.58 % |
| the 5 VirtualList-bearing scenes, Σp95 | 4.17 % | −1.75 % |

Both deltas are negative and both are inside the same-arm spread, which itself
matches the session floor (2.69 % Σp50 / 4.99 % Σp95). No cost is measurable. Per
scene the noise is ~27 %, so no single-scene number is quoted.

## What the guard found, and what it cannot yet enforce

- **The fill-axis lift is not theoretical.** Of 791 positive deltas across the
  Facet suite, **254 sit on a `fill` main axis** — shapes the previous ZStack
  overlap finding was structurally blind to. The paths are the gallery sponsor
  labs' row cards: `/ListLab/…/Row/Card` (+5px) and `/DropLab/…/Row/Card` (+4px).
  (`/ListLab/…/Row/Card/Labels` is already on the overflow sweep's waiver list for
  the same underlying cause — the guard names the slot, one level up.) Neither
  reproduces at the swept viewport × preference cross product with every scenario
  step driven, so they are state-specific and belong to whoever owns those
  scenarios.
- **`perf_capture`'s `Roster` row overflows its declared slot by 2px at +10 and
  6px at +14 at console-ten-foot 1920×1078** — reproducible, and pre-existing (it
  is not on a fill axis, so the old finding reported it too).
- ~~**The always-on sweep cannot see the new class.**~~ **CLOSED the same day** —
  and not by adding the phrase. `overflow_sweep.spec.luau` no longer greps
  anything: a swept surface must produce **no finding of any class**. The sweep
  found this class on three surfaces immediately (`row_actions [vlist]`,
  `virtual_list_native`, `perf_capture`), all now recorded as waivers with their
  measurements. See "The overflow sweep asks about every finding" below.
- RascalRally's two consumers fire **nothing**: every one of its 5 143 marked-row
  comparisons has ≥17px of headroom, at all four text preferences.

## The solve count on a viewport change — L-27's lever, paid (2026-08-13)

Brief item E named "start measuring performance with the instrument we already
ship". The device capture did its job: it produced a ranked list, and the top
item was not a slow function. It was a **count**.

`rr.html` (tier 3, physical device): `arrange` **8.270 ms/occurrence**, `measure`
**3.057 ms/occurrence**, **9.67 arranges per step**, `arrange` + `measure` =
**58.5 % of wall**. Against L-27's standing record — *"one viewport change costs
5 solves and 2 structural syncs, reproducibly"* — that prices the waste at
roughly **45 ms of a ~200 ms frame**, and L-27's own conclusion said where to
push: *"the lever for a resize is the solve COUNT, not the solve."*

### The investigation, and the step that mattered

The first probe **failed to reproduce it**. A bare `env:set("viewportRect", …)`
on a mounted 40-row tree cost exactly **1** solve — at every size, and across
every size-class boundary, five shapes tested. A device number that will not
reproduce headless is a signal about *where* the cost lives, not about whether it
is real, and the answer was the seam headless does not have: the **adapter**.

`src/client/roblox_env.luau` `pushViewport()` writes **six** facts on one real
resize. Mimicking exactly those six writes reproduced **5 solves** — L-27's
number, on the first try.

Two multipliers were compounding, and neither fix works alone:

| configuration | solves |
|---|---|
| six loose writes + eight independent key observers (as shipped) | **5** |
| batching the writes alone | 5 |
| coalescing the observers alone | 4 |
| **both** | **1** |

The renderer had observed eight geometry keys *independently*, each callback
running a full `solveAndApply()`; and `typographyScale` is a *memo over* two of
the others, so even a single loose write fired twice.

### What shipped

`env:batch(body)` — the core's existing `core:transaction`, exposed on the
environment and applied to the adapter's three fact-groups (viewport, input,
accessibility) — plus **one scope-owned memo** over all eight geometry keys in
`src/render/renderer.luau`. The core is glitch-free, so that memo recomputes at
most once per flush however many dependencies moved.

`8560f2b` (framework) · `0c3f507` (lab) · `d67af17` (log L-29) · `b631b50` (api.md)
· RascalRally `1fb175a` (consumer rider) · `4fde677` (log L-29 residual 2).

### And the lab was measuring a resize no device performs

`resizeStorm` set `viewportRect` **alone**. The pass that exists to measure
resize cost was therefore under-counting the shipped path's solve count — the
very quantity L-27 named. It now drives the whole six-fact group, batched as the
adapter batches it, with insets derived from the shape so an inset-driven
re-solve regression cannot hide in a constant.

### Three traps worth carrying forward

1. **Headless could not see it.** When a device number will not reproduce
   headless, suspect the adapter before the framework. Ten minutes of mimicking
   what the adapter actually writes replaced a plausible story with the number.
2. **An unowned `core:memo` is a leak.** The first cut of the coalescing memo was
   not `scope:own(...)`-ed and turned **24** registry-neutrality specs red at
   once. That suite is the tripwire for this whole class.
3. **A compressed `.rbxl` is not a greppable oracle.** Probing the built binary
   for `geometryFacts` returned **0** occurrences while the fix was demonstrably
   in it; the same project built to `.rbxlx` showed **2**. Any past claim of the
   form "the built bytes contain/lack X", taken from a binary place file, is
   unsound and should be re-taken against XML.

### Open, measured, not guessed

A presented **modal** still costs **2** solves per geometry change where a plain
surface costs 1 — and it is 2 whether or not the rotation crosses a size class
(probed both ways). So it is neither the adaptive rebuild nor per-key fan-out.
It is a second solve site on the modal presentation path, recorded as L-29
residual 2 with the probe recipe that would settle it. The consumer rider
asserts a **ceiling of 2** rather than an equality of 1, so that second solve can
be removed later without the check moving, while a return to fan-out (~5) still
reddens immediately.

The lab's overlay adds its own: `forgetReservation` zeroes `coreSafeInsets` when
the viewport moves and `onGeometry` republishes the measured dock height — two
extra unbatched writes per resize, measured at **11** `coreSafeInsets` fires over
4 steps against 4–5 for every other fact. That is a *measure-then-publish
feedback loop*, the shape any app reserving space from measured geometry will
have, and the honest fix (a measure→publish cycle settling inside one flush) is a
design question rather than a patch.

---

# The overflow sweep asks about every finding (2026-08-13) — ledger row 14

Row 14 said the always-on sweep filtered its findings on the literal
`"on the main axis"`, so the **five recorded non-main-axis findings structurally
could not fail it**, and that the five had never been re-verified. Both halves
were true, and the measurement turned out to be twice as bad as the row claimed.

## What the instrument could actually see, measured before anything was changed

A probe mounted the sweep's own corpus — 42 surfaces × 8 viewports × 4
preferences, the same worlds, the same settle — and collected **every**
`controller.diagnostics()` entry rather than the ones the file greps for:

| finding class | findings | distinct (surface, node) | visible to the sweep before today |
|---|---:|---:|---|
| `content overflows this <stack> by Npx on the main axis` | 303 | 33 | **yes** |
| `'X' is Npx wider than this hwrap's line on the main axis` (wrap clamp) | 1 | 1 | yes (by accident — it says "main axis") |
| `the wrapped lines overflow this <kind> … on the cross axis` | 0 | 0 | yes (added with flow-wrap) |
| **`this child overflows its zstack by NxNpx`** | **191** | **9** | **no** — invisible since 2026-08-02 |
| **`newVirtualList … than the slot it is windowed into`** | **184** | **3** | **no** — invisible from the hour it shipped |
| **`content box collapses to Npx on <axis>`** | **13** | **3** | **no** |
| **`no declared arrangement is legal … showing the declared fallback`** | **5** | **1** | **no** |
| **total** | **697** | **51** | **393 findings / 16 defects could not fail it** |

## The fix is a deletion, because a second phrase would be the same defect

The standing rule was "the general mechanism, never a special case", and a list
of remembered sentences is a special case that has to be edited every time the
solver learns to speak. So the filter is **gone**: a swept surface must now
produce **no solver finding at all**, which is the contract RascalRally's
fixtures (`diagnostics()` empty at four preferences) and the perf lab (refuses to
mount with one) already hold their surfaces to. Nothing has to be added here when
a new diagnostic ships.

Three mechanisms make that affordable, and each is derived rather than listed:

- **A finding's class is `signature(issue)`** — numbers and quoted names blanked,
  cut at a word boundary. It exists because two *different* defects can share one
  node: `perf_capture`'s Roster row is both too tall for its declared slot and
  too wide for its zstack, and `card_rail`'s card both overflows its vstack and
  collapses its own content box. One waiver covering both would have been a
  ceiling measured on the wrong defect.
- **`findingPx` reads the largest px figure any message carries**, so a ceiling
  works on `by 0x29px` (two numbers, one per axis) and `measures 74px` as well as
  on `by 46px`. The old reader returned **0** for every overlap finding.
- **`normalizePath` collapses a segment that RESTATES its key by containment,
  not equality.** A Table row composes `[m1@0]/RowActions-m1` and p2_cartwheel
  names tiles `[120]/Tile120`; under equality those are six and four identical
  waiver lines for one template each.

Waiver rule 1 is **restated, not broken**: a waiver recorded from +4 or later
still does not apply at +0, so the pre-axis contract is exactly as strong as it
was. Seven of the 51 entries admit a defect at the default preference; every one
belongs to a class this file was blind to, so none of them surrenders a contract
that was ever green, and `DEFAULT_WAIVERS` is pinned at 7 so an eighth is a
decision rather than a slipped line.

## The five recorded findings, re-verified — all five are REAL and reproduce

Re-measured at `preferredTextOffset` **+0**, against the numbers
`device-bug-round-2026-08-12.md` recorded on 2026-08-12:

| # | recorded 2026-08-12 | measured 2026-08-13 | verdict |
|---|---|---|---|
| 1 | `row_actions [vlist]` `…/Row/RowBody` overflows its zstack by **0x4px** on both portrait phones, **0x15px** at ten-foot | **4px / 4px / 15px**, byte-identical — but now reported by the **lying-`itemExtent`** guard, which took the y axis from the overlap finding on 2026-08-13. `ROW_HEIGHT = 84`, the row measures 88 | **REAL, unchanged at +0, and far worse under large text: 249px of content in the 84px slot at 320×640 @ +14** |
| 2 | `row_actions [table]` `…/Cell-from/Value` by **0x7px** at ten-foot | **0x7px** at ten-foot @ +0, exact | **REAL, unchanged** — and it now fires on all eight views and all six rows once text grows (max 32px) |
| 3a | `sponsor_drop` `…/ListZone/Rows` by **0x38px** (705×338) and **0x47px** (640×320) | **38px** and **47px**, exact | **REAL, unchanged** |
| 3b | `sponsor_drop` `…/Chev{Top,Bottom}/Glyph` by **0x6px** at ten-foot | **0x6px** at ten-foot, exact — and at every other viewport too | **REAL, and the 2026-08-12 enumeration was narrower than the defect**: both glyphs fire on all eight views at +0, up to 23px |
| 4 | `sponsor_toast` `/ToastLab/Stage/Beneath` by **0x11px** at 640×320 | **0x11px** at 640×320, exact | **REAL, unchanged** (63px at +14) |
| 5 | `p4_foyer` `…/HomeBody/FeedPage` "content box collapses to 0px on y: **padding 16 + 16**" at 705×338 (**21px** of height) and 640×320 (**3px**) | 640×320 @ +0: collapses on a **3px** height — but the padding is now **8 + 8**. 705×338 is **clean at +0** and collapses from +4 (16px height) | **REAL, and the numbers moved**: the padding halved since it was recorded, which bought back the 705×338 default-preference cell and nothing else |

**Nothing in the five is stale.** Five of five reproduce; two are worse than the
line recorded (3b at every viewport rather than one; 1 catastrophic at large
text); one has drifted in its inputs (5).

## The eleven the widening found that nobody had recorded

Everything above the line is one of the five. Below it is what the same run found:

| px | surface | node | from | class |
|---:|---|---|---:|---|
| 322 | composition | `…/OfferFrame/Summary` | +10 | declared-fallback |
| 50 | perf_capture | `…/Roster/…/[*]/Row/Row` | +10 | lying-itemExtent |
| 46 | virtual_list_native | `…/VL/…/[*]/Row/Label` | +10 | lying-itemExtent |
| 28 | sponsor_motion | `…/WashRow/WashLabel` | +10 | layer-overlap |
| 24 | row_actions `[table]` | `…/Cell-subject/Value` | +10 | layer-overlap |
| 20 | perf_capture | `…/Roster/…/[*]/Row/Row` | +14 | layer-overlap (the cross axis the slot guard leaves alone) |
| 16 | p4_foyer | `…/HomeBody/FeedPage` | +0 | collapsed-box (= five, above) |
| 15 | card_rail | `…/[*]/Row/Card` | +14 | collapsed-box |
| 11 | scroll_host | `/ScrollHost/List` | +4 | collapsed-box (non-monotone: clean at +14) |
| 8 | p2_cartwheel | `…/TileRows/[*]/*/Body` | +14 | layer-overlap |

The two `lying-itemExtent` rows on `perf_capture` and `virtual_list_native` are
the class the guard's own author expected the sweep to catch and could not; both
are the ten-foot type scale against a declared px pitch, which is
`docs/lessons/facet-fixed-px-heights.md` for the fourth time.

## Mutation-proved, eight ways, each naming the case it reddened

Every anchor was asserted to match **exactly one** site before the run.

| # | mutation | reddened |
|---|---|---|
| M1 | the OLD main/cross-axis phrase filter, restored | **the waiver list — 16 stale**, i.e. exactly the 16 defects the filter is blind to. *The negative control for the whole change* |
| M2 | the `virtualSlot` class alone filtered out | the waiver list — 3 stale |
| M3 | the zstack-overlap class alone filtered out | the waiver list — 9 stale |
| M4 | rule 1: `sponsor_toast`'s `since = 0` demoted to `since = 4` | `scenario 'sponsor_toast'` (1 unwaived at +0) **and** the waiver list (`DEFAULT_WAIVERS` 6 ≠ 7) |
| M5 | the ceiling on an `NxNpx` finding, 20 → 19 | `scenario 'perf_capture'`, *"WORSE than the recorded waiver: 20px against a 19px ceiling"* ×7 |
| M6 | `normalizePath`'s restates-by-containment reverted to equality | `scenario 'row_actions'` (107 unwaived), `proof 'p2_cartwheel'` (4), waiver list (3 stale) |
| M7 | `findingPx` reverted to the old `by (%d+)px` reader | `BREADTH CONTROL` — *expected 0 to be 20*, i.e. the old reader scored every overlap finding at zero |
| M8 | an eighth `since = 0` waiver slipped in | the waiver list — *expected 8 to be 7* |

`BREADTH CONTROL` is the permanent version of M1: it mounts a layered overlap and
a lying `itemExtent` through the same world, asserts both reach the collector, and
asserts that **neither message contains either phrase the old filter grepped for**.

## The Rascal Rally rider — the same blindness, on the live consumer

The game holds two of its own always-on diagnostic checks, and both had the same
defect in a narrower form. Measured first, then widened:

- `code/tests/facet_large_text_sweep.spec.luau` greped `"overflow"`. **The
  surface it sweeps is built on `newVirtualList`**, whose slot guard never uses
  that word — a lying `itemExtent` on the production racer list, every row
  painting over the next, would have left it green. It now collects **every**
  finding; measured before the change, that world produces **zero** findings of
  any class at 3 views × 4 preferences, so the wider check needed no waiver.
- `code/tests/facet_large_text_results.spec.luau` greped `"overflows its"`, and
  therefore could not see either the slot class or `"content box collapses to
  0px"`. It now collects everything **except** the declared-fallback note, which
  the case below it already pins with a director-level reason.

Both mutation-proved: with the racer row's padding forced to 400 (a real lying
`itemExtent`, 766px of content in a 56px slot), the widened sweep case is **RED**
and the same defect under the old `"overflow"` grep is **GREEN**; removing the
results spec's fallback exclusion reddens its case on the six cells that carry
one. RascalRally suite: **3153 passed**, green, before and after.

One measurement worth keeping: the slot guard is **structurally quiet on the
production racer list**. Shrinking its declared `itemExtent` by 40px produces no
finding at all, because the row's cell takes `fill` and measures far under its
slot — so on that surface the guard is not the protection; the geometry pins are.

## What is NOT closed

- **Sixteen defects are recorded, none is fixed.** Every one is in a fixture or
  proof this work does not own, and the file's own precedent (35 waivers, "none
  of them in a file this mission could touch") is to record with a measurement
  rather than to guess at somebody else's design. Seven of them are live at the
  **default** preference.
- **`composition`'s declared fallback may not be a defect at all** and is the one
  entry here that wants a ruling: RascalRally already excludes the identical note
  from its own check, with the reason on the record (*"the surface still paints
  its declared last resort"*). If the director agrees, it stops being a waiver
  and becomes a permanent exclusion with that sentence attached; nobody guessed
  it either way here.
- **`tests/lib/tiers.luau` still records this spec at 1036 ms** with a stale
  reason. The widening adds no measurable cost (the loop is unchanged; only the
  `continue` was removed), and the file belongs to another agent this round.

---

# Rows 8 and 9 shipped — row actions are no longer pointer-only

**Closed 2026-08-13.** `e54d671` (Table), `e725c68` (VirtualList), `2774513`
(showcase), `245e6bb` (the engine measurement). Facet **4842 → 4856**, Rascal
Rally **3154 → 3160**, both green.

## One sentence, two hosts

The ledger filed these as separate items and they are one defect: **a row's
row-actions surface was built by the pointer path, so every non-pointer path was
missing whatever the pointer had not yet produced.**

- **Table** wraps a row that declares `rowActions` — `row_actions.build`'s root
  Anchor sits between the ForEach slot and the row's own `Row` node, and the tray
  `When`s and the edit-mode minus are that wrapper's OTHER children. The focus
  contribution walked `Row`, so everything the wrapper owns was in **no focus
  group**, and a contribution owns its subtree's focus — nothing downstream could
  pick them up.
- **`newVirtualList`** builds a hosted row's engine at a pointer gesture's **axis
  lock**, and that engine owns the row's key bindings. A row that had only been
  focused had none.

They do not collapse into one patch, and the honest reason is that the two hosts
mount a tray in deliberately different places — that difference *is* hosted
mode. What is shared is the rule and one declaration: `row_actions.ROW_KEYS` +
`ROW_KEY_PRIORITY` now carry the row's key vocabulary once, read by the engine's
own context and by any host standing in for one, so a host cannot ship half a
verb. (Mutation N5: dropping `Backspace` from that table reddens the hosted
case.)

## What the ledger's row 9 under-stated

The priced fix named Delete. **The action menu was in the same hole** — `ButtonX`
and `Shift+Return` are a pad's whole route to a *non-destructive* action, and
they live on the same engine. The stand-in binds both verbs, so the fix is the
row's key surface rather than one key.

## Two decisions worth keeping

**The row's own content stays FIRST in its focus group.** Index 1 is where every
vertical entry into a row lands (`focus_graph.enterGroup` — a perpendicular entry
is *ordinal* nearest, and the group above a row has one stop), so ordering the
group by pure left-to-right geometry puts the edit-mode **minus — a Delete
button — under the ring** the moment a pad walks down into an editing table.
Measured: that ordering reddens `examples_gallery`'s own end-to-end pad case,
which presses A there expecting to grab a row. The cost of the choice, stated:
a *leading* affordance is reached by continuing Right off the row rather than by
pressing Left toward where it is painted. The honest repair is per-row
`exit.up`/`exit.down` declarations, which would free the group array for
edge-side groups the way `newVirtualList` uses them — a navigation-model change
for every table, not a reachability fix, and not taken.

**One engine per press that needs one.** Building an engine when focus *arrives*
would have been simpler and spends exactly the laziness hosted mode exists for on
a d-pad walk that presses nothing. The stand-in is enabled by focus and
**constructs nothing** until a key lands (case P8d).

## The engine fact this rests on, measured rather than modelled

The two-binder design is safe only because a higher-priority sinking
`InputContext` consumes the key. The tree's only citation for that was a
**headless spike**. Probed live under Play, 2026-08-13: two sinking contexts on
`Delete` deliver to the higher **alone**; the lower receives it the moment the
higher is disabled; and a `PrimaryModifier = LeftShift` binding fires on the
chord and not on a bare `Return`. Both directions, each the other's control —
`docs/lessons/input-context-arbitration-measured.md`, which also corrects
`engine-input-truths-phaseb` truth 3 (a `PrimaryModifier` chord *is* drivable by
injection today).

## Where it is proved

`tests/table_input.spec.luau` (4 cases, 5 mutations) ·
`tests/virtual_list_row_actions.spec.luau` ((P8b) re-decided from the known-gap
pin it was, plus 5 more; 6 mutations) · `tests/row_actions_scenario.spec.luau` +
`examples/gallery/scenarios/row_actions.luau` (`keyDeleteVList`, `menuVList`,
`padMinusTable` — the showcase demo the rule requires) ·
`tests/examples_gallery.spec.luau` (the shipped playlist, by keyboard) ·
`games/RascalRally/code/tests/facet_row_actions_reach_contract.spec.luau`
(7 cases, 4 mutations).

## Found and NOT fixed

**A value control inside a row traps directional navigation.** On the shipped
playlist the rating strip owns Left/Right (measured: `DPadRight` on it moves the
rating 4 → 5 and never the ring, *even at the maximum*), so nothing later in that
row is reachable by d-pad — the tray included. That is the rating control's arrow
ownership, not this fix, and it is why the playlist's showcase case is driven by
Tab. It is a genuine cross-platform gap on a shipped surface and it wants a
ruling: should a focused value control own the arrows along its own group's axis,
or should it yield at its limit?
