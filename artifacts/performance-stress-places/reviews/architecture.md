# Architecture review — LuauUI roadmap Step 9 (`performance-stress-places`)

**Reviewer:** fresh-context architecture verifier, 2026-08-04.
**Transcription note:** this reviewer's session had Read and Bash only and could not
write the file itself; the text below is its returned report, transcribed verbatim by
the implementing agent. Its scratch artifacts (two source copies, the differential
fuzz and the delta-debugging shrinker) are the primary evidence and were re-run
independently against the fix — see the verification line at the end.

**Verdict: FINDINGS — 1 BLOCKER.**

## Lead finding first

### BLOCKER-1 — the per-solve `measure` memo publishes a *stale* `compact` / `textFacts` verdict; the solved box and the painted label can disagree

**File:** `src/layout/solver.luau:959-974`
**Confidence:** High — reproduced, shrunk to four minimal trees, direction confirmed
against the pre-change build.

**What is wrong.** `measure` is not memo-safe under the contract the solver actually
relies on. Its keyed `ctx` writes (`ctx.compact[node.id]`, `ctx.textFacts[node.id]`,
`ctx.textStates[node.id]`) are idempotent *per box*, but the published value is decided
by **last-write-wins across boxes**. The solver states this explicitly at
`solver.luau:248-252` ("assigned on EVERY measure of the node, so the facts published
are the ones the reserved box was built from") and at `solver.luau:716-720` ("the flag
is assigned on EVERY measure ... never only set: this node is measured repeatedly at
different widths ... and a verdict that could only latch true would keep a compact form
after a re-solve made room").

The memo changes that rule to: *the last **distinct** box to be **first**-measured
wins.* Those coincide only when the final logical `measure` call uses a box not already
measured earlier in the same solve. When the sequence is `measure(X, A) →
measure(X, B) → measure(X, A)`, the third call is now a cache hit, so
`ctx.compact`/`ctx.textFacts` retain **B's** verdict while `arrange` snapshots them into
`out[node.id]` at `solver.luau:1109-1126` for box **A**.

**How I verified it.** Differential fuzz: copied `src/` twice into scratch, patched one
copy's `measure` to bypass the memo, then solved 800 seeded random trees (kinds:
vstack/hstack/zstack/grid/scroll/anchor/fits/text/box/spacer; dims incl. `hug`, `fill`,
`minMax`, `percent`, `aspect`; text with `compactText`, `singleLine`, `lineLimit`,
`disclose`) at five viewports with and without `scrollBarReserve = 8`, and diffed the
full per-node output.

```
cases=800  rectDiff=0  textFactsDiff=12  compactDiff=3  diagSetDiff=0  diagDupCountOnly=298
```

**Geometry is identical (`rectDiff = 0`) — only the published verdicts diverge.** That
is the worst possible shape: the box is right, the flag describing it is wrong. This is
the "painted at a size nobody measured for it" family, and specifically the
disagreement `ctx.compact` was introduced to make impossible
(`docs/lessons/one-word-two-subsystems.md`).

**Minimal reproductions** (auto-shrunk by delta debugging; `rectSame=true` in all four):

```
seed 132, viewport 800x600  — node n30 COMPACT memo=true  plain=false
  zstack width=percent(0.59) > zstack width=minMax(37,57)
    > scroll axis=y gap=6 width=fixed(239) height=minMax(34,46)
      > text "Continue" size=10 compactText="OK" singleLine width=minMax(45,122) height=fixed(4)

seed 612, viewport 800x600  — node n8  COMPACT memo=false plain=true
seed 205, viewport 320x480  — node n40 COMPACT memo=false plain=true
seed 91,  viewport 400x900  — node n52 TRUNCATED memo=false plain=true
```

**Why each direction is a product defect.**

- `compact = false` where the pre-change solver said `true`: `applyCompactLabel`
  (`renderer.luau:1925-1943`) paints the **full** label into a box whose sibling
  geometry was settled with the full-label measure — the ellipsized-icon-button case
  `compactLabel` was built for.
- `compact = true` where it said `false`: the short form is painted when the label fits.
- `truncated = false` where it was `true`: `presenter.luau:1687` and `:1987` gate
  **full-value disclosure** on `facts.truncated == true`, and `:2105`/`:2306` gate the
  `reveal` marquee on it. A cut label that reports `truncated = false` silently loses
  its accessible full-value path — a direct regression against the Step 8.5 large-text
  contract.

**Per-side-effect audit of `measure` (requested enumeration):**

| ctx side effect | Written at | Safe to skip a repeat call? |
|---|---|---|
| `ctx.textStates[node.id]` | `solver.luau:304` | **No** — snapshotted by `arrange`; last-write-wins across boxes. |
| `ctx.compact[node.id]` | `solver.luau:738, 742` | **No — proven divergent** (3/800). Drives the painted string. |
| `ctx.textFacts[node.id]` | `solver.luau:317` | **No — proven divergent** (12/800), including `truncated` and `policy`. |
| `ctx.diagnostics` | `solver.luau:979` | Set-safe, count-unsafe. `diagSetDiff = 0` over 800 trees: nothing lost or gained. But it is a `table.insert`, not an idempotent keyed write, so duplicate counts change in 298/800. |
| `ctx.compositions[node.id]` | `solver.luau:615` | Safe **by accident**: `arrange` re-derives it with its own box. Fragile — one future arrange branch reading the leftover reintroduces the bug. |
| `ctx.regionForm` | `solver.luau:1383, 1395` | Safe — written only in `arrange`. |

**Is `hiddenDepth` the only missing contextual input?** For the *returned size*, yes:
`ctx.metrics` and `ctx.scrollBarReserve` are fixed per `solve`, node content is not
mutated during a solve, and `rectDiff = 0` over 800 trees is direct evidence. The
missing input is not a *value* at all — it is **call order**, which no key can encode.

**Suggested direction:** either (a) cache only `(w, h)` and always re-run the
fact-publishing writes, or (b) store the verdict tuple alongside `{w, h}` and **replay**
it on a hit. (b) preserves both the saving and last-write-wins.

---

## Area 1 — `src/core/profile.luau` containment, cardinality, error semantics, `setHooks`

**Containment: correct in shape.** Not exported from `src/init.luau`; reached only
through the named exemption at `tools/lune/check_boundary.luau:134`, mechanically
enforced at `:246-253`. Same pattern as the existing `text_calibration` /
`text_metrics` / `text_premeasure` entries. **No finding on the principle.**

**Cardinality: the closed set and `MAX_SCOPES = 12` are the right boundary.** Label
derived mechanically from the key; `tests/profile_scopes.spec.luau` asserts scope count
is invariant under a 10× row increase — the cardinality rule stated as behaviour, not
as a name check. Strong. **No finding.**

**`span`'s pcall and error semantics: no defect found on the "not active" fast path.**
Returns `fn()` unwrapped, so Lune and scopes-off keep exact stack/level. Error value
preserved unchanged at level 0 while active, including a non-string sentinel.

### MINOR-2 — `span`'s pcall truncates the traceback while scopes are active
`src/core/profile.luau:200-206`. Confidence: medium. The value is preserved; the
*trace* is not, so a production stack trace is shaped differently from the headless
one.

### MINOR-3 — the safety comment's stated invariant is factually wrong
`src/layout/solver.luau:954-958`. "every side effect `measure` has is an idempotent
write into a ctx table keyed by `node.id`" is false for `ctx.diagnostics`, and the keyed
writes are idempotent per box but not order-independent. **This wrong invariant is the
direct cause of BLOCKER-1** — the comment is where the review would have caught it.

### MINOR-4 — `profile` is a process-global mutable singleton in a per-core framework
`enabled`, the hook pair and all counters are module upvalues, while everything else in
LuauUI is per-instance. A deliberate simplification for a capture tool, but an authority
seam nothing declares.

### MINOR-5 — `setHooks` can silently replace real engine hooks with no provenance marker
`counters().engine` reports `true` for an installed pair, so a lab bug could produce a
capture that *looks* instrumented and contains no engine scopes.

### MINOR-6 — `span` is unsafe around a yielding body, and nothing says so
Every current call site was checked — **none yields today**. A missing contract, not a
live defect.

---

## Area 2 — call sites: scope placement, balance, observable behaviour

**Placement is sound and the naming is genuinely low-cardinality.** `mutate` outside the
trailing flush and `react` around it is the right split. `measure`/`arrange` as two
whole-tree scopes is correct and is what made the asymmetry legible. `mount` shared
between initial build and `structuralSync` is right for a mount-ramp profile.

**Balance on error paths: clean.** `pcall(profile.span, "mutate", body)` + `error(err, 0)`
preserves the pre-change error value and level. `flush()`'s `flushing` bracket is
unchanged in risk. The commit scope is correctly guarded on `#dirty > 0`.

**Observable-behaviour changes: none found**, other than the traceback shape (MINOR-2)
and two closure allocations per solve. The `flushBody` hoist is a real improvement and
is behaviour-neutral.

### MINOR-7 — a solve triggered from inside an effect nests layout under `LuauUI/react`
Legal for the profiler, but a reader comparing `react` against `measure` will
double-count unless they use exclusive time. Worth one sentence in the capture doc.

---

## Area 3 — the layout memo

Covered above (BLOCKER-1, MINOR-3).

### MINOR-8 — the memo is not free, and I could not reproduce a win on the shapes I tried
On a 60-row list-shaped tree it measured **slower** in Lune (memo 1.794ms vs plain
1.493ms flat; 2.662 vs 2.197 with a scroll host). My synthetic scroll shape wraps the
rows in a single VStack child, which defeats the memo — this is **not** the lab's
dense-scroll shape, so it does not contradict the 6.6× arrange figure. Reported as: on
trees where nodes are measured once, the memo costs ~20% of solve time, and nothing
scopes it to the shapes that benefit. Recommend publishing the flat-tree number beside
the dense-scroll number.

### MINOR-9 — NaN box dimensions collapse to one cache key
Negligible in practice.

---

## Area 4 — the example surface and the `ctx.host` / `ctx.lab` passthrough

**Ownership boundary holds where it matters.** `perf_lab.luau` is genuinely `script`-free
and engine-free. `lab/init.luau` is the correct place for `script:WaitForChild`.
`dataset.luau` declares and honours its determinism contract. The engine seams the lab
needs arrive as seams, and the lab **degrades honestly** when they are absent rather
than faking evidence.

**`ctx.lab` is a reasonable extension** — the same idea as the existing registry, and it
is asserted on with a message naming the supplier.

### MINOR-10 — `ctx.host` is an unvalidated, unschema'd `any` bag at the runner boundary
`examples/gallery/scenarios/runner.luau:240`. Every *other* engine seam on that ctx is
runner-owned and typed by construction; `host` moves the enforcement to convention plus
a boundary checker that inspects `require` expressions, never values. Not a hole today —
the lab's use is disciplined and each field is asserted — but it is the one seam in that
file with no declared shape.

### MINOR-11 — the `profile` boundary exemption is broader than its justification
Keyed on the last path component and applied to **all** of `examples/`, while the stated
reason is specifically the performance lab.

**Nothing game-specific leaked into the lab.** No RascalRally content, no product
policy, and no framework-shaped mechanism that belongs behind a public API.

---

## Checks I did not run, and why

- Full LuauUI suite / the stage gate — the coordinator directed me to stop and report.
  My differential fuzz is independent of the suite and would not be caught by it (the
  suite has no memo-vs-no-memo oracle).
- Studio/device evidence — out of scope for an architecture review.
- RascalRally consumer lockstep — not audited. `ctx.compact` and `textFacts` are
  consumed by the production Sponsor surfaces, so BLOCKER-1 has a plausible game-side
  blast radius.
- `composition`/`region` measure ordering — my fuzz corpus contained no such nodes, so
  that path is **unproven in both directions**.

---

## Verification of the fix (added by the implementing agent, 2026-08-04)

The reviewer's own harness was re-run against the corrected solver, with the memo copy
refreshed from the shipped source and the bypassed copy left as the oracle:

```
cases=800  rectDiff=0  textFactsDiff=0  compactDiff=0  diagSetDiff=0  diagDupCountOnly=298
```

All three divergence classes are gone. `diagDupCountOnly` remains by design — the
diagnostic **set** is identical and only duplicate counts shrink, which is recorded in
PLN-8 rather than restored. The shrunk trees for seeds 132, 612 and 91 are now
`tests/measure_memo.spec.luau`; removing the replay reddens the 612 and 91 cases.
