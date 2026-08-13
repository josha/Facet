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

### The one place the brief overstates its own case — and it matters

Standing rule 3 says the MicroProfiler instrument has **"never once"** been read.
That is very nearly true and the imprecision is worth fixing, because the
difference is exactly the thing the rule is trying to buy.

`artifacts/performance-stress-places/studio/pl9-row4-luauui-1.json` — a real
Studio session, 2026-08-05 — carries a `scopes` block reading
`engine: true`, `balanced: true`, `opens: 60824`, `closes: 60824`, and a
`byScope` map with real counts for `scenario`, `mount`, `measure`, `commit`,
`resource`, `react`, `mutate`, `arrange` and `reset`. So the **Lua-side counters**
in `profile.counters()` have been read on the engine, and the balance claim has
been confirmed against a real `debug.profilebegin` rather than only against the
recording hooks the suite installs.

The same row carries `capturePath: "not captured in this run"` and
`summaryPath: "not derived in this run"`.

> **The precise statement, which this mission uses instead:** LuauUI has counted
> how many times each scope opened on a real engine. It has never measured how
> many **milliseconds** any of them cost. Counters are not timings, and only the
> timings answer "what does a frame cost".

*(Fuller verification of this reading, across every capture row, is in Phase 1.)*

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

*(Phases 1–6 follow once Phase 0's five reconnaissance tracks report. This
document is written as they land; a section that is not here yet has not been
decided yet, and that is deliberate — round 2's lesson is that a plausible story
ahead of the data is worse than no story.)*
