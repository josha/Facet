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
| 5 | **`api.md` round-2 prose skim** | **12 concrete defects**, listed below. The mechanical half is closed; `check_prop_parity` is a bare substring test, so one mention anywhere satisfies it | headless |
| 6 | **Shrink gap (a): a shrinkable label lands outside its box** | **TRUE, measured.** Three `shrinkWeight=1` texts in a 120px box solve to `x0 w120 / x120 w120 / x240 w100` — two land wholly outside. `absorbTier` absorbs at most `Σ(basis−floor)`; residual deficit is simply not absorbed and nothing clips. The shrink pass is **best-effort and its own diagnostic says so** | headless + a ruling |
| 7 | **Shrink gap (b): `shrinkWeight` flips the `ViewThatFits` winner** | **TRUE, measured — and round 2's §2.4 claim is FALSE.** That doc says `ViewThatFits` "picks its candidate before any of this and is therefore unaffected"; PASS 1.5 (the measure-side shrink, landed a day later) invalidated it. Swept 150→420px, adding `shrinkWeight=1` to a candidate's children flips the winner at **10 of 28 widths (290–380px)**, because the candidate now *reports* a shrunk extent and `fitsW` becomes true | headless + a ruling |
| 8 | **Table tray-focus: trays are in no focus group** | **OPEN, confirmed.** `buildFocusGroups` collects focusables *inside* the Row node; tray buttons live under the `RowActions/` wrapper, which is the Row's **parent**. Siblings, not descendants — so Tab and D-pad reach neither a Table-composed tray nor its edit-minus | headless |
| 9 | **Keyboard/pad Delete on an unswiped hosted row** | **OPEN.** Lazy engines mean no engine exists until a swipe. The fix is already priced | headless |
| 10 | **A BLOCK table publishes a scroll path it has no host for** | **OPEN, not named by the brief.** `table.luau:2869-2871` returns `…/Main/Body` unconditionally with no `scrolls` check. The crash half is fixed; the design half is live in the shipped playlist example — open a tray, scroll the page, and the tray rides along still open, because "any scroll closes the tray" binds to a node that never scrolls | headless + a ruling |
| 11 | **Reduced-motion settings surface** | **NOT BUILT.** `with_animation` writes the real env fact but restores it on dispose (`:159`, `:486`), so the reduced-motion axis is reachable only while that one demo is on screen. **Hard-blocked behind #4** — a settings surface only a finger can open cannot run the keyboard or gamepad axis of a canary | headless |
| 12 | **Row-actions menu not clamped to the viewport** | **OPEN**, comment unchanged. Trigger at y=508 on a 600px viewport → menu at y=556..629 | a ruling |
| 13 | **The "Edit item" wrap rule** | **OPEN.** `renderer.luau:452` unchanged. The honest rule, per the doc's own root-cause: wrapping is right only when the phrase's **longest word** fits the drawable width | a ruling |
| 14 | **The overflow sweep cannot see cross-axis findings** | `overflow_sweep.spec.luau:129` filters on `"on the main axis"`, so the five recorded non-main-axis findings structurally cannot fail it. **The five themselves are not re-verified** — documented only | headless |

### Deferred, with the reason

`presenter.animator()` (build it when a composite asks, not before) · size animation in `withAnimation` (its own mission; the five blocking mechanisms stand) · variable item extents (needs a consumer; both candidate designs are recorded) · §6.4's perf follow-ups (**worse than reported** — `perf_lab.spec` is now 16,494 ms, **37 %** of the suite, against round 2's 13.7 s/32 % — but it is runtime, not correctness) · the five unfulfilled placement intents and the rendered-canary-set proposal (**both are director decisions, surfaced not built**) · every `PENDING_PHYSICAL` row, including brief item **E2**, which the brief itself says not to block on and is right: its fix rests on an unverified engine premise that only a device can settle.

### Two process findings worth more than any single item

1. **No round-2 review artifact exists in the tree.** `artifacts/swiftui-parity-round2/` holds three files and none is a review; `[SHOWCASE-CHROME]: CONCERNS 16` survives only as prose citations, and `gate.json` cites a `prior-gates-rerun.txt` that **does not exist**. Every round-2 review finding is unrecoverable except as summary. *Reviews must land as artifacts.*
2. **The tree was not exclusively this mission's, and checking is what proved it.** A concurrent session's `tools/gate.sh swiftui-parity-round2` had been hung for 2 h 37 m holding `/tmp/luauui_prior_gates.lock`, which is why round 2's `prior-gates-unregressed` reads `FAIL_RECOVERABLE`. The reconnaissance recommended clearing the lock as "the cheapest unblock in the ledger"; **`pgrep` showed a live process holding it, and clearing it blind would have broken that run.** It also explains the perf place changing mid-session. Killed with director authorisation, 2026-08-13, along with three further orphans. *`ListAgents` is not enough — check the process table.*

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
`Gauge` shape LuauUI now has.

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
rider in Rascal Rally's `tests/luauui_sponsor_results.spec.luau`, which asserts
the bar's three registry cells directly (mutating `bar.valueLabel` to `false`
reddens that one case and nothing else; mutating `bar.hasTrack` reddens 388,
because the rally bar stops presenting).

---

## Item A shipped — flow-wrap, as one prop and no new alignment words

Built 2026-08-13 against the Phase 0 verdict above, which is not re-litigated here:
flow-wrap is a **native arrange branch**, the public `Layout` protocol stays a
conditional refusal with a trigger, and the engine's cross-axis rule is a measured
fact rather than a divergence LuauUI has to own. This section records the five
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
by 88. That is `docs/lessons/luauui-fixed-px-heights` arriving on schedule, caught
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
plus `games/RascalRally/code/tests/luauui_flow_wrap_contract.spec.luau` (8 cases).

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
`p3_sipworks`, `p4_foyer`, `p5_wardrobe`. Suites **4725 → 4734** (LuauUI) and
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
- all five `examples/places/LuauUI-Ref-*.rbxl` rebuilt
