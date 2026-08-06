# Reactive-runtime review — roadmap Step 9 (`performance-stress-places`)

Fresh-context, read-only audit. No file in the repository was modified by this review;
every probe ran against copies under the session scratchpad.

Reviewed at working-tree state of 2026-08-04 **after** two in-flight corrections landed:
`src/core/profile.luau` now defaults `enabled = false`, and `src/layout/solver.luau`'s
measure memo now REPLAYS its cached verdicts on a hit. Both were re-checked below; the
conclusions in this report are against the current files, and where an earlier version
behaved differently that is stated explicitly.

## Verdict

**FINDINGS** — 1 MAJOR, 8 MINOR, 0 BLOCKER. Nothing found in the framework's reactive core
changes the propagation, ordering, quarantine or ownership contracts. The MAJOR is a
use-after-dispose in the new lab example code (area 4). The core-runtime findings are all
narrow-reachability robustness/attribution issues.

The three questions asked directly:

1. **Can `flushing` be stranded true on a path it could not be stranded on before?**
   **Yes — one new path, narrow.** If `profile`'s `begin` hook throws, the error escapes
   `profile.span("react", flushBody)` and `flushing = false` (custom.luau:257) never runs;
   the core is silently dead for the rest of the session. Before the hoist, `flush` called
   nothing external before its body, so this path did not exist. Not reachable with scopes
   off (the new default) and not plausible with the engine's own `debug.profilebegin`, but
   it IS live in exactly the configuration Step 9 ships (the lab enables scopes at boot)
   and through `profile.setHooks`, which the suite already uses. Finding RR-1.
   *No other new stranding path:* everything inside `flushBody` is still pcall-quarantined
   exactly as before, and `span`'s own pcall closes the profiler scope and re-raises, so
   an error out of `flushBody` strands `flushing` in precisely the same cases it did
   before the hoist.

2. **Is the double pcall in `transaction` observably different from one?**
   **No, for the error value.** Measured both ways: a table error keeps its identity
   (`err == thrown` is true), a string error keeps a byte-identical message including its
   original `file:line:` prefix, and `error(nil)` still surfaces as `nil`; the trailing
   flush still runs exactly once (observer fired exactly once) whether or not the body
   threw, and a nested transaction whose inner body throws still leaves value = 2 with one
   observer fire. Two residual differences, both cosmetic and both recorded below: the
   re-raise at level 0 means an outer `xpcall` handler's traceback no longer contains the
   original throw-site frames (RR-3), and the instrumented and un-instrumented paths differ
   in stack shape because `span` only pcalls while active (RR-4). With `enabled = false`
   as the new default, `span` is a straight `return fn()` on Roblox and there is only ONE
   pcall in production; the second exists only in an instrumented capture run.

3. **Can the perf_lab data-scope / cell-scope ownership double-dispose or use-after-dispose?**
   **No double disposal. Yes, use-after-dispose** — `rebuildDataset` disposes every per-row
   value/toggle signal while the rows that bind them are still mounted, and `UI.ForEach`
   never rebuilds a row whose key is unchanged. Finding RR-9 (MAJOR).

## Requirements checked

UI-RUNTIME-001 (equality / no spurious fire), UI-RUNTIME-002 (keyed structural regions),
UI-RUNTIME-003 (transaction batching, glitch-freedom, dynamic dependency swap, cycle
detection, write-during-memo, feedback cap, quarantine), UI-LIFE-001 (scope ownership,
reverse-order idempotent cleanup, double-disposal detection), UI-LIFE-002 (memory-neutral
churn), UI-LAYOUT-001/002 (solve determinism and published verdicts), plus the Step 9 plan's
PL-3/PL-4/PL-5 lab rules and PLN-2/PLN-4 as they touch lifetimes.

## Evidence and commands

All commands run from the repository root unless noted. Scratchpad root abbreviated `$SP`.

| # | Command | Result |
|---|---|---|
| E1 | `./run-tests.sh` | **3361 passed, exit 0** (baseline, current working tree) |
| E2 | `git diff src/core/custom.luau src/mount.luau src/async/resources.luau` | read in full |
| E3 | `git diff -w --ignore-blank-lines src/async/resources.luau` | the ONLY non-comment changes are `+local profile = require(...)`, `+return profile.span("resource", function(): string` and `+end)` ×2 — the two bodies are otherwise byte-identical, so the stale/retry/give-up verdicts cannot have moved |
| E4 | differential solver fuzz, 400 seeded random trees, memoized vs memo-disabled build, comparing every node's rect + `hidden` + `contentSize` + `overflow` + full `textFacts`, and the diagnostic list (`$SP/diffsolve2.luau`, two full source copies under `$SP/memo` and `$SP/probe`) | **against the PRE-replay memo: 4/400 trees published different `textFacts`** (see RR-13 note); **against the CURRENT replaying memo: `rectMismatches=0`, `uniqueDiagMismatches=0`, `totalMismatches=64` (duplicate-diagnostic counts only)** |
| E5 | full suite run against a memo-DISABLED copy of the tree (`$SP/probe`) | 3361 passed, and `diff` of the two suite transcripts is **0 lines** — the memo is invisible to every existing test either way |
| E6 | core probe (`$SP/memo/probe_core.luau`): transaction error identity/message/nil round-trip with scopes active and inactive; nested-transaction inner throw; write-during-flush; feedback cap then recovery; throwing `begin` hook | see the per-finding reproductions below |
| E7 | lab probe (`$SP/memo/tests/probe_lab.luau`, built on the spec's own `newHarness`): mount `dense-scroll` at 60 rows, then run the declared `localeSwap` pass | `signals 92 -> 74` while `memos` stayed 112 and `scopes` stayed 36 — 18 per-row signals disposed with **zero** cells rebuilt |
| E8 | code reads: `src/core/custom.luau`, `src/core/profile.luau`, `src/core/scope_impl.luau`, `src/mount.luau` (ForEach reconcile), `src/render/renderer.luau` (solve call site, `textAt`), `src/layout/solver.luau`, `src/controls/virtual_list.luau`, `src/controls/stepper.luau`, `src/controls/async_image.luau`, `examples/performance/lab/{rows,perf_lab,dataset}.luau`, `tests/perf_lab.spec.luau`, `tests/profile_scopes.spec.luau` | — |

## Findings

### RR-1 — a throwing profiler `begin` hook strands `flushing = true` forever (MINOR, confidence HIGH)

`src/core/custom.luau:246-258`.

```lua
flush = function()
    if flushing then return end
    flushing = true
    profile.span("react", flushBody)   -- may now throw BEFORE flushBody runs
    flushing = false
end
```

`profile.span` increments its counters and calls `open(label)` before pcall'ing the body
(`src/core/profile.luau:191-200`). An error out of `open` therefore escapes `span` without
ever entering the protected region, propagates through `flush`, and leaves `flushing = true`
permanently. Every later write takes the `if flushing then return end` early-out, so the
core stops flushing with no diagnostic at all — `core:lastError()` stays `nil`.

Reproduction (E6, last block):

```
P1 throwing-hook write ok=false err=...: hook exploded fired=0
P1 after: value=3 fired=0            <- observer never fires again; core is dead
P1 profile counters opens=14 closes=13 depth=1 balanced=false
```

Reachability: not with `enabled = false` (the new default), and Roblox's
`debug.profilebegin` will not throw on a short constant literal. It is live whenever scopes
are enabled and a host installs hooks — which is the lab's shipping configuration and the
mechanism `tests/profile_scopes.spec.luau` is built on. The same throw also permanently
corrupts `profile.counters().balanced`, which that module documents as "the load-bearing
assertion".

Violated requirement: UI-RUNTIME-003 quarantine ("nothing may unwind and strand
`flushing = true`" — the comment the hoist itself added at custom.luau:240-243).

Smallest corrective test: install `profile.setHooks(function() error("hook") end, function() end)`,
write a signal, then assert (a) a subsequent write still notifies its observer and
(b) `profile.counters().balanced` is true. Today (a) fails and (b) fails.

### RR-2 — `profile.span` is not balanced if `open` or `close` throws (MINOR, confidence HIGH)

`src/core/profile.luau:191-207`. `opens`, `byScope` and `depth` are advanced BEFORE
`open(label)`, and `close()` runs outside any protection, so a throwing hook leaves
`opens > closes` and `depth > 0` for the life of the process. Same evidence as RR-1
(`opens=14 closes=13 depth=1 balanced=false`). This is the module's own contract
("BALANCED ON EVERY EXIT PATH", rule 2 in its header) and it is the root cause of RR-1;
fixing it here fixes both. `tests/profile_scopes.spec.luau` covers a throwing BODY
thoroughly (lines 120-160) but never a throwing HOOK.

### RR-3 — the level-0 re-raise erases the original traceback frames (MINOR, confidence MEDIUM)

`src/core/profile.luau:204-206` and `src/core/custom.luau:443-450`. The error VALUE is
preserved exactly (verified: table identity, string bytes, `nil`), but while scopes are
active the throw that reaches `transaction`'s `pcall` originates inside `span`, not at the
user's `error()` call site. Any host that wraps a transaction in `xpcall(..., debug.traceback)`
gets a shorter, differently-rooted stack when scopes are on than when they are off. No
current caller does this; recorded because "the error is re-raised unchanged" is claimed in
two comments and is only true of the value, not the stack.

### RR-4 — instrumented and un-instrumented runs do not share error semantics (MINOR, confidence HIGH)

`src/core/profile.luau:188-189` — while inactive, `span` does `return fn()` and does not
pcall; while active it pcalls and re-raises at level 0. This is deliberate and documented,
but it means a capture run and a normal run differ in error propagation shape, so a fault
reproduced with scopes on is not, strictly, the same execution as with them off. Worth one
line in the lab's capture metadata. `tests/profile_scopes.spec.luau:237-247` already pins
the OFF behaviour, so the divergence is at least intentional and tested.

### RR-5 — `LuauUI/react` is not disjoint from `measure` / `arrange` / `commit` / `mount` (MINOR, confidence HIGH)

`src/render/renderer.luau:2514-2516` re-solves from inside `core:observe(...)`; observer
callbacks run inside `notify` inside `flushBody`, i.e. inside `profile.span("react", ...)`.
Every solve, commit and structural remount that a flush causes is therefore nested INSIDE
the `react` scope. MicroProfiler renders that hierarchy correctly, but any programmatic
consumer that sums `LuauUI/*` timers double-counts, and `react` cannot be read as "the
dirty walk" — it is "the dirty walk plus everything it caused". The transaction comment
(custom.luau:441-442, "The trailing flush stays OUTSIDE this scope on purpose — it is
`react`") sets an expectation of disjoint phases that `react` itself does not meet.
Recommend stating the nesting in the capture's phase legend, or asserting it in
`profile_scopes.spec` so a future reader is not surprised.

### RR-6 — a yielding transaction body leaves `LuauUI/mutate` open across the yield (MINOR, confidence MEDIUM)

`src/core/custom.luau:443`. Pre-existing in shape (a yielding transaction body already
stranded `txDepth > 0`), but the span makes a second resource — an open MicroProfiler
scope on that thread — hostage to the same mistake, and an open scope misattributes every
later frame in the capture (profile.luau's own rule 2). Not introduced by this change and
not reachable from framework code; recorded as a boundary note for game callers.

### RR-7 — `provider.complete` / `provider.fail` allocate a closure per completion (MINOR, confidence HIGH)

`src/async/resources.luau:359` and `:385` (the two `return profile.span("resource", function(): string` wrappers). The flush change was made specifically to
avoid "a closure allocated on every frame" (custom.luau:240-242); these two call sites take
the opposite trade, one closure per resource landing, on the cold-image path that is the
most allocation-sensitive one in the lab's own workload. Correctness is unaffected: `span`
returns `fn`'s first result, every branch returns exactly one string, and `git diff -w`
shows the bodies are otherwise unchanged (E3), so `stale` / `applied` / `retrying` /
`failed` verdicts, the generation bump, the wave carry-over and `giveUp` are all identical.

### RR-8 — nesting of `resource` over `mutate` is safe (CLEAN)

`provider.complete` and `provider.fail` each contain a `core:transaction`, so an active
capture nests `LuauUI/resource` > `LuauUI/mutate`, and if the completion arrives from an
effect the whole thing nests under `LuauUI/react`. Depth accounting is correct (span's
pcall closes before re-raising) and `maxDepth` is bounded by 4. No re-entrancy hazard: a
`transaction` that reaches `txDepth == 0` inside a flush calls `flush()`, which returns
immediately on the `flushing` guard and leaves the writes for the running loop — verified
still true (E6 P4: `a=2,b=20` in one flush, then `a=3,b=30` on the next write).

### RR-9 — perf_lab disposes live per-row signals under mounted rows (MAJOR, confidence HIGH)

`examples/performance/lab/perf_lab.luau:434-444` (`rebuildDataset`), reached from
`passes.localeSwap` (`:865-878`) and `steps.select` (`:1280`) — neither of which unmounts
first. `steps.reset` (`:1399-1417`) DOES unmount first and is correct.

```lua
local function rebuildDataset()
    items = dataset.build(...)
    dataScope:dispose()                    -- disposes every per-row value/toggle signal
    dataScope = labScope:child("perf-lab-data")
    values, toggles = {}, {}
    rowsSignal:set(items)
end
```

The row's signals are owned by `dataScope` (`rows.luau:77-93`), but the CONTROLS that bind
them live in the VirtualList cell, and `UI.ForEach` does not rebuild a row whose key is
unchanged — `src/mount.luau:285-311`: `if node.itemsByKey[key] == nil then ... mountNode(bp.props.row(...))`.
Dataset ids are `r{i}` (`examples/performance/lab/dataset.luau:206`), stable across every
seed and content variant, so a content or seed swap changes NO key and rebuilds NO cell.

Result: every mounted row is left holding disposed signals, and `values` / `toggles` are
fresh empty tables so nothing rebinds them. Disposal marks each live observer disposed and
decrements `counts.observers` (`custom.luau:336-343`), so writes to those signals no longer
notify anything — the Toggle and Stepper freeze silently. It is not a crash and not a
double-free; it is a quiet use-after-dispose.

Measured (E7): mount `dense-scroll` at 60 rows → `signals=92, memos=112, scopes=36`; run
the declared `localeSwap` pass → `signals=74, memos=112, scopes=36`. Eighteen signals were
disposed and not one cell was rebuilt.

Second-order consequence, which matters for the stage's purpose: because no cell rebuilds,
the mounted rows keep the OLD dataset's text, so `passes.localeSwap` does not swap any
locale a player would see — it times three re-solves of unchanged content. The workload
does not measure what its name and its `swaps` record claim.

Violated requirements: UI-LIFE-001 (a resource must not be used after its owning scope is
disposed) and the stage's own PLN-4 ownership note; PL-10 (a pass must measure the workload
it is labelled with).

Smallest corrective test: mount the dense-scroll scenario, snapshot
`core:counters().signals` and `report().mountedRows`, run `steps.pass("localeSwap")`, and
assert the signal count did **not** drop while `mountedRows` was unchanged. Stronger:
assert the first mounted row's `Name` text equals the NEW dataset's `r1.name`.
Both fail today.

Note: the fix belongs in the lab, not the framework. `steps.reset`'s ordering (unmount, then
rebuild) is the shape that is already correct.

### RR-10 — the ownership shapes in `rows.luau` are correct; no double disposal anywhere (CLEAN)

- `rows.luau:126` `scope:own(LuauUI.newStepper(...))` is legal: `Scope.own` accepts a table
  carrying a `dispose` (`scope_impl.luau:61-76`) and the walk invokes `resource:dispose()`
  (`:119-121`); `stepper.luau:276` declares `function api.dispose()` and ignores the
  implicit self. The PLN-4 comment describing the two opposite shapes is accurate.
- `newAsyncImage` owns its memos and its provider release into the cell scope
  (`async_image.luau:81-100`), so a row leaving the window cancels its image.
- `dataScope` is a child of `labScope` and deregisters itself from the parent on dispose
  (`scope_impl.luau:134-141`), so `built.dispose()`'s explicit `dataScope:dispose()`
  followed by `labScope:dispose()` is NOT a double disposal; and the parent walk skips an
  already-disposed child silently by design. Confirmed empirically: `core:lastError()`
  stayed `nil` through a full build → select → mount → pass → dispose cycle, and a double
  disposal would have written "double disposal of scope 'perf-lab-data' detected".
- Repeated `rebuildDataset` calls do not grow `labScope.owned` (the child deregisters).

### RR-11 — the "does NOT grow the reactive core" regression bound is meaningful but leaky (MINOR, confidence HIGH)

`tests/perf_lab.spec.luau:298-323`. For the leak it was written for — a `newStepper` scope
per materialized row — the bound is real and would fire loudly (the live regression was
17 078 memos / 4 278 scopes against a bound of 200). Two ways it can pass with a leak
present:

1. It asserts only `memos` and `scopes`, and its comment explicitly exempts `signals`
   because they are retained by design. But the OTHER half of the live defect this stage
   found was exactly a signal leak — "a live Studio reset left 488 undisposed signals"
   (`rows.luau:74-76`, `perf_lab.luau:228-234`) — and no assertion in the suite covers it.
   A regression that leaks one signal per visited row passes.
2. The bound is absolute, not per-row, over a fixed workload: 240 scroll steps across 600
   rows materialize a few hundred distinct rows, so any leak below roughly one memo per
   three visited rows fits inside 200. A leak that is genuinely proportional to rows
   visited but small per row is invisible.

Tighter form: run the six passes TWICE and require the second run's delta ≈ 0 (steady
state is the property, not a magic constant), assert the signal delta is bounded by the
number of DISTINCT rows visited, and assert the counters return to the pre-mount baseline
after `built.dispose()`.

### RR-12 — the measure memo cannot strand a reactive dependency (CLEAN, confidence HIGH)

The question asked for area 5, answered directly: **no**.

- `solver.solve` is invoked from `solveAndApply` (`src/render/renderer.luau:1955`, call at
  `:2046`), a plain function; the solver module requires no core and creates no
  subscriptions.
- The measure path reads exactly one reactive value: the live `eligible` gate in
  `compositionResolution` (`src/layout/solver.luau:575`, `(gate):get()`), and it is read
  through `:get()`, never through a tracking `use`, so no subscription exists that a
  skipped call could drop. Grep confirms it is the only `:get()` in the file.
- Within one solve no writes occur, so a skipped repeat call cannot observe a different
  value than the call it replaced.
- `ctx.hiddenDepth` — the one contextual input outside the argument list — is mutated only
  in `arrange` (`:1345, 1396, 1432`), never in `measure`, and is part of the cache key.

### RR-13 — the memo's side-effect staleness class was real; the replay fixes it, and the fix is confirmed (CLEAN NOW, confidence HIGH)

Recorded because the evidence is independent and worth keeping. Against the PRE-replay
version of the memo (the one I was originally handed), a differential fuzz over 400 seeded
random trees found **4 trees whose published `textFacts` differed** from the un-memoized
solve while geometry was byte-identical — e.g. `lines=2, naturalLines=2` (memo) versus
`lines=10, naturalLines=10` (uncached) for the same text node, and `naturalLines=2` versus
`4`. The reproducing shape is ordinary: `fits → hstack → (fill) vstack → percent-width text`,
i.e. a ViewThatFits candidate measured at box A, then at box B, then at A again, where the
memo returned A's size but left the facts from the B measure in place. Those facts are a
public surface (`controller.textAt`, `renderer.luau:3257`) consumed by the presenter's
auto-reveal (`presenter.luau:1686, 2104, 2148, 2308`) and by `text_audit`.

Against the CURRENT replaying memo the same 400 trees produce **`rectMismatches=0`** and an
identical unique-diagnostic set. The replay (`solver.luau:966-996`) covers every channel
`measure` writes except `ctx.diagnostics` — `textStates`, `compact`, `textFacts`,
`compositions` — and restores last-write-wins exactly. `ctx.regionForm` is written and read
only in `arrange` (`:1383, 1395, 1406`), so it is correctly outside the memo's blast radius.

### RR-14 — the memo silently de-duplicates diagnostics (MINOR, confidence HIGH)

`src/layout/solver.luau:960-1014`. `ctx.diagnostics` is an array appended with
`table.insert` and is NOT replayed, so a node measured twice at the same box now reports its
diagnostic once instead of twice. Over the 400-tree differential, **64 trees differed in
diagnostic COUNT while the unique diagnostic SET was identical in all 400** — nothing is
lost (the first measure always misses), but `#result.diagnostics` is not the number it was.
Consumers that count rather than de-duplicate: `tests/lib/fuzzers/layout.luau:262`,
`layout/dump.luau`, the doctor. Arguably an improvement; the problem is that the memo's
SAFETY comment (`:955-959`) still claims "every side effect `measure` has is an idempotent
write into a ctx table keyed by `node.id`", and `table.insert(ctx.diagnostics, ...)` is
neither keyed nor idempotent. One sentence in that comment, or a replay of the diagnostic
slice, closes it.

### RR-15 — the replay list is a fifth channel away from silently regressing (MINOR, confidence MEDIUM)

`src/layout/solver.luau:989-996` enumerates four ctx channels by hand. `ctx.regionForm` is
the fifth measure/arrange channel and is deliberately omitted because only `arrange` writes
it today. That is correct today and undetectable if it stops being true: a future measure
branch that writes `regionForm` reintroduces exactly the bug the replay was added to fix,
silently, with geometry unchanged. Cheapest guard is the differential fuzz itself — the
harness used for E4 finds this class in seconds and nothing in `tests/` currently does.

### RR-16 — mount spans are semantically transparent (CLEAN)

`src/mount.luau:547-549` and `:577-579`. `mountNode` returns a single value and `span`
returns `fn`'s first result, so `rootNode` is unchanged; `root.dispose` returns nothing in
both versions. Disposal ordering is untouched — `rootScope:dispose()` is still the only
call, still reverse-order and still quarantined per resource inside `scope_impl`. Double
disposal still reports through the scope's own detector and stays idempotent; the span
cannot swallow it because `Scope.dispose` does not throw. `conformance` rows
`scope-dispose-reverse-order-idempotent` and `double-dispose-detected` pass (E1).

### RR-17 — ordering, glitch-freedom and quarantine are unchanged (CLEAN)

Re-verified directly rather than by trusting the suite:

- **Re-entrancy / write during flush** — an observer writing another signal is folded into
  the SAME flush loop, in the next round: `seen=a=2,b=20`, and a later write still flushes
  (`a=3,b=30`). The guard at `custom.luau:189` and the early-out at `:247` behave as before.
- **Feedback cap** — still fires with the same message and the same discarded-write count,
  and the core is still usable afterwards (a subsequent write notified exactly once). The
  `break` inside `flushBody` returns from the function, `span` closes, `flushing = false`
  runs — identical to the old fall-through.
- **Transaction batching and revert** — one observer fire per transaction with or without a
  throwing body; nested transaction with a throwing inner body leaves the outer write
  discarded (`value=2`), one fire, `ok=false`.
- **Dynamic dependency swap, cycle detection, write-during-memo, memo quarantine,
  observer-added-mid-flush, disposed-observer-never-fires, memory-neutral-churn** — the
  conformance rows for all of these pass unchanged (E1), and none of their code paths was
  touched by the diff (E2).

## Checks not run, and why

- **Roblox Studio / engine run.** This review is headless. Everything about a REAL
  `debug.profilebegin` — whether an open scope survives a yield, what the MicroProfiler
  shows for the `react`-over-`measure` nesting in RR-5, and the actual cost of the spans
  with `enabled = false` — is unverified here and needs the lab's Studio session.
- **`tools/check_perf_*.py`, the gate manifest, bench budgets.** Out of scope for a
  reactive-runtime review and owned by other reviewers.
- **The native reference implementation** (`examples/performance/client/native_list.luau`)
  is a host seam and unavailable headlessly; the `HOST seam` refusal path is covered by the
  existing spec.
- **A minimal hand-authored composition/region scene** for the RR-13 class. The 400-tree
  differential covers `fits`, `scroll` (both measure passes), `grid`, `zstack` and text, but
  the tree generator does not emit `composition`/`region` nodes, so the replay's correctness
  for compositions rests on code reading (the channel is captured and replayed) rather than
  on measurement. Adding composition nodes to that generator is the cheapest way to close it.
- **Long-running soak of the lab** (thousands of scroll steps with counters sampled per
  step). RR-11 argues the existing bound could hide a small per-row leak; proving whether one
  exists needs the soak, not an argument.
