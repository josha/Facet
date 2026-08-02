# Decision packets — for Fable 5 or the director

**Stage:** roadmap Step 5.5, gate `code-simplicity-cleanup`, 2026-07-28.

These are **not implemented**, deliberately. Each is a design choice with more than
one defensible answer, which the cleanup plan routes out rather than settles:
*"Record larger architectural opportunities as evidence-backed decision packets for
Fable 5 or the user; do not smuggle them into cleanup."*

Each packet gives the evidence, the options, the cost of each, and a recommendation.

---

## DP-1 — RR-1-R1: motion-clock quarantine is frame-granular

**Evidence (reproduced this stage, `tools/lune/_probe_carryovers.luau`).**
One clock, two springs. Spring A gets a live target that throws from its second
read; spring B is aimed at 100. After **600** steps:

```
a = 0   b = 0   activeCount = 2      (b's target is 100)
```

B never moves and never leaves the active set — for the life of the clock, while A
keeps throwing. `stats.steps` climbs; `stats.transactions` stays 0 (that is DP-1's
sibling, RR-1-R2, which was a documentation defect and is fixed).

**What is already fixed and must not be re-opened.** RR-1's actual wedge — a throw
stranding `stepping = true` and freezing the clock *permanently* — is fixed: the
step body is `pcall`'d and the flag always clears. This residual is about **blast
radius while the throw persists**, not about latching.

**Why it was not fixed here.** The one-line shape (move the `pcall` inside each
phase loop) is not the decision. The decision is the **eviction policy**:

| Option | Behaviour | Cost |
|---|---|---|
| **A. Per-entry pcall, retry every frame** | One entry's throw costs only that entry; healthy motion keeps running | A permanently-throwing target burns a `pcall` per entry per frame forever, and floods `lastError` |
| **B. Per-entry pcall + detach after N consecutive throws** | Bounded cost; the sick entry leaves the active set | The motion silently *stops* — and an INTERMITTENT thrower gets evicted for a transient fault. "Rest costs zero" (SF-M8) then no longer distinguishes settled from evicted |
| **C. Leave as-is** | A throwing consumer callback stalls that surface's motion until it stops throwing | The exit-cap analogue: `clock:timer{...}` `onSettle` never fires while another value's live target throws, so a retiring subtree can outlive its cap |

**Recommendation: A, with the error recorded once per entry rather than per frame.**
It preserves the framework's stated rule ("a throwing USER callback is quarantined
and never wedges a scheduler") without inventing a silent-stop state that the
"rest costs zero" instrumentation cannot tell apart from a settled motion. B's
eviction is the part that needs a director, because it changes what
`activeCount() == 0` means.

**Smallest corrective test** (from the verifier, unchanged): one clock, two springs;
A's live target throws on every read, B aimed at 100; after 400 steps assert
`math.abs(B:get() - 100) < 1` and that B has left the active set.

---

## DP-2 — ESC-1: interactive-state roles are missing from the authored vocabulary

**Unchanged from `artifacts/sponsor-framework-gaps/responsibility-ledger.md`.**
Three treatments in the UI Designer's §4.2 state table are inexpressible through
public authoring: `controlSelected` as an authored `Box.surface`, selected content
stepping to `contentStrong`, and a disabled-opacity treatment for
ineligible-but-inspectable rows (`enabled = false` is wrong — those rows must still
activate to explain themselves).

**Why not here.** It is a **feature**: a theme-vocabulary extension across the
package schema, the generated sheet rules, and all nine reference packages. The
cleanup's hard boundary forbids adding features, and forbids weakening the theme
capability in either direction.

**Recommendation carried forward unchanged:** extend `surface`/`role` with the
interactive-state entries rather than widening `tint` into a state channel — the
tint schema's own rule is that a closed-set state is never a continuous colour.

**Note added by this stage.** The working alternatives Step 5 shipped are still in
place and were re-verified as untouched: the unified list's native `selected` tag,
and verdict washes riding `tint` role-blends.

---

## DP-3 — ESC-2: pointer-zone callbacks receive layout-space rects

**Unchanged from the responsibility ledger.** Authored `onPointerDown/Move/Up`, the
presenter's zone-A test, and the presenter's `syncGeometry` feed (which Slider's
track math reads) all receive `rectOf` — layout space — while drag hit-tests now
use presentation-aware `screenRectOf`. A slider dragged DURING a live enter/exit
slide computes against the solved rect, offset by the slide.

**Why not here.** Changing `rectOf`'s meaning under existing consumers is exactly
the "behaviour merely because the reviewer would have designed it differently"
case the plan excludes, and the consumer sweep it requires is a mechanism change,
not a simplification. No current consumer drags mid-slide.

**Recommendation carried forward:** hand pointer-zone callbacks `screenRectOf`,
with the enumerated consumer sweep (authored handlers, presenter zone-A,
`syncGeometry`). `api.md`'s slider wording is already qualified pending this.

---

## DP-4 — ARCH-F6: two exemption mechanisms, and a stale record

**New evidence this stage.** The Step 5 record states two things about
`focus_graph.beginInteraction` / `endInteraction`; call-path tracing shows one is
stale and the other is unsupported.

- *"test-only in production"* — **stale.** Callers repo-wide are
  `tests/focus_skip.spec.luau` **and `examples/gallery/scenarios/sponsor_drop.luau`**,
  a shipped gallery consumer that is itself under test
  (`tests/sponsor_scenarios.spec.luau` asserts `pres.focus.interactionTarget()`).
- *"remains the public API for **non-drag** interactions"* — **unsupported.** That
  one consumer is a drag fixture doing precisely what the registry seam
  (`registry.interactionTarget()`, the production path used by
  `virtual_list.luau`'s `focusable` predicate and by the presenter's armed-aim
  sync) already does. **No non-drag consumer exists.**

So: two mechanisms answering one question — "is this node inside a live
interaction, and therefore exempt from focus skipping?"

**Options.**

| Option | Cost |
|---|---|
| **A.** `virtual_list` calls `graph.beginInteraction`; the focus graph owns the exemption | The focus graph gains a drag-shaped concept it is currently free of |
| **B.** The registry stays the sole owner; `beginInteraction`/`endInteraction` are deprecated under ADR-0011 and `sponsor_drop` moves to the registry seam | A public deprecation — needs a `DEPRECATIONS` entry and a MINOR, i.e. its own stage |
| **C.** Keep both, and correct the documentation to say which is production and which is the escape hatch | Two mechanisms stay; the ambiguity becomes explicit rather than accidental |

**Recommendation: C now, B when the next MINOR opens.** The API is public,
documented and exercised, so deletion is out of scope for a pass that freezes
exports; but the record should stop claiming a non-drag consumer that does not
exist. This packet is the correction.

---

## DP-5 — the `imperative` conformance scorecard is not deterministic

**Evidence.** `lune run tests/conformance/cli imperative` returned 37, 38, 36, 37,
38 of 42 across five consecutive runs. Isolated over 40 repeats on fresh cores:

```
observer-added-mid-flush-fires-next-flush-only   16 pass / 24 fail
observer-disposed-by-sibling-does-not-fire       23 pass / 17 fail
```

Both are observer-ORDER checks; `imperative` iterates observers in hash order.
Pre-existing (reproduced before any `src/core` edit); `custom`, the reference
implementation and the only core the main suite asserts, is 42/42 every run.

**Why it matters.** `artifacts/conformance-imperative.json` is a checked-in
artifact whose numbers change without any source change, and
`ENGINEERING.md` requires deterministic tests. A future agent diffing that file
will chase a phantom.

**Options.** (A) make `imperative` iterate observers in a stable order — a
behaviour change to a bake-off candidate; (B) mark the two checks
`orderDependent` and let the scorecard record them as N/A for cores that do not
claim ordering, the way `claims` already works for `dynamicDependencies` and
friends; (C) leave it and document.

**Recommendation: B.** It matches the honesty mechanism the scorecard already has
(a factory may not claim a semantic its scorecard fails), and it makes the
artifact deterministic without touching a candidate's behaviour.

---

## DP-6 — three consolidations found, evidenced, and deliberately not taken

Reported so the evidence is not lost. Each was traced; each was judged to cost more
than it saves *in a behaviour-preserving pass*, which is not the same as judging it
wrong.

1. **`presenter.autoGroups` vs `layoutGroups`** — two ~55-line tree walks deriving
   the same `NavigationGroup[]`. Equivalence on the reachable domain is closed
   (the contribution branch is constant-false in the layout-only path; `Grip` is a
   schema leaf; the group-name prefixes are referenced nowhere). **Not taken**
   because the merge needs a `skipContributions` parameter to avoid adding an O(n)
   subtree walk per HStack/Grid to *every* `refresh()` — i.e. it trades two clear
   functions for one function with a mode flag, on a path reached by two of the
   four supported input paradigms. Worth doing with a perf row attached; not worth
   doing quietly.
2. **`sheet_model.build` vs `buildPackage`** — 8 byte-identical state rules emitted
   twice (hover/pressed for Control/Primary/Destructive, the semantic-icon
   replacement, the held-drag-source rule), and 38 rule names emitted by both
   builders. The file has closed this class three times already
   (`emitOwnSlotPaint`, `emitSlotSuppression`, `emitShapeChrome`) and its own
   comment records a shipped defect from exactly this shape. **Not taken** because
   it rewrites rule emission — the paint path — and the three Studio rows that
   would prove it were unreachable in this session (see `studio/README.md`).
3. **`SLOT_FILL_TOKEN` / `chromeFillOf` / `SLOT_ROUND` triple mirror** — 16
   slot→role entries hand-maintained in `tokens/sheet_model.luau` and again in
   `client/screen_chrome.luau`, with three specs existing *solely* to alarm on
   drift. Both files already require `chrome_slots`, which already hosts the shared
   `TINT` ladder for this exact reason. **Not taken** for the same reason as (2).

**Recommendation:** take 2 and 3 together as one small follow-up with the five-view
Studio matrix attached; they are the two highest-value consolidations the audit
found, and they share the same evidence requirement.
