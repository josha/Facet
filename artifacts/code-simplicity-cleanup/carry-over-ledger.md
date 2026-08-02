# Step 5 carry-over ledger — every item dispositioned

**Stage:** roadmap Step 5.5, gate `code-simplicity-cleanup`, 2026-07-28.
**Sources of truth for this list (nothing here was rediscovered — every row is
copied from one of these two files and then acted on):**

- `artifacts/sponsor-framework-gaps/verifier-responses.md`
- `artifacts/sponsor-framework-gaps/responsibility-ledger.md`

The reproductions were **run**, not read: `tools/lune/_probe_carryovers.luau`
executes each residual's own reproduction verbatim against current source.
Its output at the frozen baseline is in
`baseline/carryover-probe-before.txt`.

---

## A. The five that had to be fixed or retired WITH EVIDENCE

| ID | Verdict | What the measurement showed | What was done |
|---|---|---|---|
| **RR-7-R1** | **FIXED** | The scope semantics Step 5 changed (quarantined cleanup, early-child disposal, owned deregistration) were pinned against the DEFAULT core only; `tests/conformance/suite.luau` had no check for any of them, so `fusion` and `imperative` were never asked. | One conformance check added — `scope-cleanup-quarantined-and-early-child-is-not-a-double-dispose` — which owns a throwing cleanup between two healthy ones, disposes a child early, and requires both healthy cleanups to run in reverse order, the scope counter to return to baseline, and NO double-dispose report. It runs against all three candidates. **PASS on custom, fusion and imperative** (`artifacts/conformance-*.json`). |
| **RR-5-R1** | **RETIRED — the report is correct, not false** | Reproduced: `p:own(function() c:dispose() end); c = p:child("c"); p:dispose()` → `core:lastError()` = `"double disposal of scope 'c' detected"`, counters exact (`scopes` back to 0, no double free). **The control run settles it**: the same cleanup SHAPE over a scope the parent does not own (`standalone = core:scope(...)`) reports `nil`. So the diagnostic fires only when one child has TWO owners — the parent's own child list AND a cleanup closure — which is the §6.3 aliasing violation ARCH-F4 already names. The reverse walk does not manufacture the report; the second owner does. | Not suppressed. Suppressing it would weaken a diagnostic to hide a real caller bug. Instead: both directions pinned in `tests/runtime_quarantine.spec.luau` ("the double-dispose report fires for an ALIASED child and stays silent otherwise (RR-5-R1)"), and the reasoning written into `src/core/scope_impl.luau`'s header where the rule lives. |
| **RR-3-R1** | **RETIRED — verified clean, now pinned** | The residual was explicitly *unexecuted* ("not executed this round, most likely benign"). Executed now: two commit flights airborne on the presenter clock, `registry.dispose()` mid-air. No error; `motionClock:activeCount() == 0` and it stays 0 across 120 further ticks; core counters return to the value a control rig that never dragged leaves behind. Clearing an EXISTING key during generalized iteration is legal in Luau, and this is the proof it is legal *here*. | Pinned in `tests/presenter_drag_integration.spec.luau` ("disposing the registry with several flights in the air is clean (RR-3-R1)"), with an A/B control rig so "counters returned to baseline" means something. |
| **RR-1-R2** | **FIXED (the documentation was the defect)** | Reproduced exactly: 30 steps under a persistently throwing live target → `stats.steps == 30`, `stats.transactions == 0`. The doc comment claimed `transactions` "must equal `steps`". | The comment was wrong, not the counter. A `pre`/`advance` throw aborts the step **before** the commit phase, so that frame genuinely opened no transaction — counting one would report a flush that never happened. `src/motion/clock.luau`'s `Stats` type now documents the true invariant, `transactions <= steps` with equality exactly when `lastError()` is nil, and cites the measurement. Pinned both directions in `tests/runtime_quarantine.spec.luau` ("transactions counts frames that really committed, never the aborted ones"). No counter was added: a third counter would be new public surface to describe a rule a sentence already describes. |
| **scope-less `adaptive.conditions` callers** | **FIXED where it mattered; the rest RETAINED with evidence** | The two gallery scenarios RR-8-R1 named were already fixed at Step 5 close (`adaptive_controls`, `perf_capture` both pass `{ scope = scope }`). Full re-sweep of the repo found the remaining scope-less callers are `tests/adaptive.spec.luau:67` and `:173` — **and `docs/reference/api.md`**. Measured: 50 scope-less calls on ONE core leak `memos: 9 → 309` (six per call), so the mechanism is real. The two test call sites each construct their own `customFactory.new()` per case, so the memos die with a core that lives one `it()` — no observable leak, nothing to own. | The **documentation** was the live one: `api.md`'s `AdaptiveStack` example taught the scope-less form, and `opts` was named without its only field ever being documented. Both fixed — the example now passes a scope, and a new paragraph states the six-memo cost and that omitting `scope` means owning them by hand. The two test call sites are retained, with the reason recorded. |

---

## B. Design decisions — recommendation only, deliberately NOT implemented

Full packets in `decision-packets.md`. Summarized here so this ledger is complete.

| ID | Status | One-line recommendation |
|---|---|---|
| **RR-1-R1** | ESCALATED — reproduced, not fixed | Clock quarantine is frame-granular; a persistently throwing consumer callback freezes all motion on that clock. Reproduced (`a=0, b=0` against a target of 100, `activeCount()==2` forever). The fix is an **eviction policy** choice, not a cleanup. |
| **ESC-1** | ESCALATED — unchanged | Interactive-state roles missing from the authored surface/content vocabulary. A theme-vocabulary extension across the schema, the sheet rules and all nine reference packages — a feature, and explicitly out of a behaviour-preserving pass. |
| **ESC-2** | ESCALATED — unchanged | Pointer-zone callbacks still receive layout-space `rectOf` while drag hit-tests use `screenRectOf`. Changing `rectOf`'s meaning under existing consumers is a behaviour change with a named consumer sweep. |

---

## C. Every remaining carry-over, dispositioned

### Architecture (round 1 findings carried, plus round-2 residuals)

| ID | Disposition |
|---|---|
| **ARCH-F3** asymmetric enter/exit reversal cut | **RETAINED as documented.** The Step 5 lead accepted it and documented it; nothing in the cleanup's remit changes a designer-vocabulary default. Re-confirmed the documentation exists. |
| **ARCH-F4** aliased-owner double-dispose silenced | **CLOSED by RR-5-R1's work.** The two are the same nuance from opposite ends: F4 says an aliased double dispose is *not detected* when the guard skips it; RR-5-R1 says one *is* reported when the walk reaches it first. Both are now stated together in `scope_impl.luau`'s header, and the RR-5-R1 pin covers the reported direction. |
| **ARCH-F6** two exemption mechanisms | **RECORD CORRECTED, decision escalated.** The Step 5 record says `focus_graph.beginInteraction/endInteraction` are "test-only in production" and remain "the public API for non-drag interactions". Traced: the only callers repo-wide are `tests/focus_skip.spec.luau` **and `examples/gallery/scenarios/sponsor_drop.luau`** — a shipped gallery consumer that is itself under test. So "test-only" is stale. But that one consumer is a *drag* fixture doing what `registry.interactionTarget()` already does, so **no non-drag consumer exists** and that half of the record is unsupported. Not dead surface (documented at `api.md`, exercised, public) → not deletable here. The real choice — let the focus graph own the exemption, or keep it free of any drag concept — is an architecture call. Escalated. |
| **ARCH-F7** one ghost vs N flights | **RETAINED as documented.** Behaviour is token-guarded and safe; the disagreement is a documented model note. RR-3-R1's new pin now also exercises the N-flight teardown path, which is the part that had no test. |
| **ARCH-F8** dead `host` authority | **CLOSED — it was documentation drift, and the docs were wrong in two places.** Confirmed: `"host"` appears exactly once in the whole repo, its own type-union member; no `MANIFEST` entry carries it and no `assertWrite` call passes it, because the custom-control seam (UI-EXT-001) never shipped a blueprint class. The union member is **retained** — the theme linter's rejections and ADR-0019 §4 classify engine properties against this same five-name list, so deleting it strands that vocabulary to save six characters. What was fixed is the false claim: `src/render/authority.luau`'s header and `docs/guide/02-architecture.md` now say it is declared-but-unused and that there are four live authorities. |
| **R1** mid-drag-retirement path untested | **RETAINED, carried.** The verifier could not execute it either (its probe tripped the fade-group precondition). Writing that test is new coverage for a Step 5 mechanism, not a simplification, and the cleanup's remit is not to grow Step 5's test surface. Recorded with the verifier's exact reproduction so it stays actionable. |
| **R2** `retiringRoots` invariant unasserted | **RETAINED, carried.** Same reasoning as R1: asserting "every host that sets `mounted.retiring` pushes a `structure` dirty entry" is a new invariant test for a Step 5 mechanism. Noted that the C-05 mount consolidation did **not** touch the retiring paths — the structural-region *bookkeeping tail* was consolidated, `mountWhen`/`mountForEach` bodies are untouched. |
| **R3** six MINORs not dispositioned | **CLOSED by this table** — that was the ask. |
| **R4** gate.json unconfirmed at final source | **CLOSED.** Every prior gate was re-run at the final cleanup source (`prior-gates.txt`). |

### Roblox platform

| ID | Disposition |
|---|---|
| **PLAT-2** touch/pen consumption unmeasured | **RETAINED as PENDING_PHYSICAL** (review packet SFP-2). No instrument in this build can close it. |
| **PLAT-7** purity unpinned | **RETAINED.** `check_boundary` still exits 0 at the final source; the scope note stands. |
| **PLAT-8** parity pin is a source regex | **RETAINED** with its recorded E3 compensation. |
| **P2-4** 50 ms echo window is wall-clock | **RETAINED as an accepted risk, unchanged.** Replacing the window with a press epoch fed by the adapter is a mechanism change with a device row attached, not a simplification. |
| **P2-5** `setPresentationOffset(0)` writes `{x=0,y=-0}` rather than clearing | **RETAINED.** Deliberate — "restored" is a value the presenter's own tests read back. The cost is an O(path-length) walk per hit-test after the first keyboard raise; correctness is unaffected (the shift is 0). Making an all-zero transform clear the geometry cache while still reporting to the presenter is a behaviour change to a read-back contract. |
| **P2-6** public `attachDragDetector` is not echo-guarded | **RETAINED.** Harmless today (its only caller is the slider track, class `Grip`, which is not in `TAPPABLE` and has no native `Activated` handler). Routing the public seam through the same wrapper is a behaviour change on a public method. |

### Phase-gate

| ID | Disposition |
|---|---|
| **PG-9** shallow `test -f` checks | **PARTLY ADDRESSED, and one was found genuinely broken.** The cleanup did not sweep the manifest for shallow checks — but tracing the theme flow found one that was worse than shallow: `theme-packages-and-skinning`'s `metric-snapshot-single-source` `cmp`'d **two stored files** against each other, which proves nothing about the current tree, and had gone red when a defaulting generator overwrote one of them. Replaced with `check_flat_baseline`, which regenerates from live source. See ledger **C-08**/**C-09**. |
| **PG2-1..PG2-7** | **CLOSED at Step 5 close** (mutation-tested pins, final gate run). Re-confirmed only insofar as every prior gate re-ran green here. |

### Riders from the responsibility ledger

| Rider | Disposition |
|---|---|
| `preferredTextOffset` placeholder values sweep | **RETAINED, carried.** Needs a physical device to choose real values; no instrument here. |
| `topbarInset` has zero consumers | **CORRECTED — the rider is wrong.** `topbarInset` is consumed: `src/env/environment.luau` derives the safe-area policy from `coreSafeInsets`/`topbarInset`, `client/roblox_env.luau` sets it, and the gallery runner reads it. The Studio row above shows it live and non-zero (`{x=164, y=0, w=196, h=58}`) on the phone-portrait profile. Nothing to do. |
| `env.locale` has zero consumers | **CONFIRMED and RETAINED.** No `src/` reader; only fixtures set it. It is a documented public environment fact (`api.md`), so removing it is a public-API change — forbidden here. Recorded as a genuine unconsumed fact for a stage that may add localization. |
| Gallery runner `reset()` leak fix has no automated regression | **RETAINED, carried** (Studio-dependent). |
| VirtualList variable row heights | **RETAINED** — a deferred §17 feature gate, not cleanup. |
| XP-S4 / NS-P1/P2 / XP-P1..P4 physical rows | **RETAINED as PENDING_PHYSICAL.** |

---

## D. Found while dispositioning, reported not fixed

**The `imperative` conformance scorecard is nondeterministic.** Running
`lune run tests/conformance/cli imperative` five times returned 37, 38, 36, 37, 38
of 42. Isolated it: over 40 repeats of the full suite on fresh `imperative` cores,
`observer-added-mid-flush-fires-next-flush-only` passes 16/40 and
`observer-disposed-by-sibling-does-not-fire` passes 23/40. Both are observer-ORDER
checks and `imperative` iterates observers in hash order.

This is **pre-existing** — it was reproduced before any `src/core` edit, the new
RR-7-R1 check is deterministic and passes 100 % on all three cores, and `custom`
(the reference implementation, and the only core the main suite asserts) is
42/42 on every run. It is reported, not fixed: making `imperative` order-stable is
a behaviour change to a bake-off candidate. Its practical consequence is that the
`conformance-all-cores` gate check asserts the **named** check on each core, never
a total.
