# Step 5.5 — simplicity cleanup: summary

**Date:** 2026-07-28 · **Gate:** `code-simplicity-cleanup` · **Version:** 0.7.0 (unchanged)

**Status: COMPLETE. Gate PASS, exit 0, all 13 checks PASS.** The three fresh-context
reviews closed on 2026-07-28 (`review-response.md` — four MAJOR findings, one phantom,
three fixed with mutation proofs), and `studio-evidence` closed the same day with all
five device rows green plus a sixth row driving the changed scroll path
(`studio/README.md`). Nothing is left open on this stage.

---

## What was deleted or consolidated

**Ten changes landed, one coherent change at a time, each with its focused checks
run before the next.**

**Deleted (proved unreachable, whole-repo traced including gate source-string greps,
doc-checker terms, Rojo instance-path requires and dynamic access):**
`schema.isContainer`, `schema.TYPE_CHECKS` and `schema.TRANSITION_FORMS` export
assignments, `transitions.activeCount`, `transitions.isRunning`,
`text_premeasure.isSettled`, `token_sync.weightNameOf`, `token_sync.pathForAttribute`,
`theme_controller.SUPPORTED_SCHEMA`, `standard_icons.SCHEMA`,
`standard_icons.SOURCE_PX`, a comment-only `if` branch and its unused local in
`themes/package.luau`, a `graph.focused = graph.focused` self-assignment in the
presenter, and a `game:GetService("Players")` handle in `roblox_env` whose only
consumer was a no-op silencing its own unused-variable warning.

**Consolidated to one owner:**

| | Was | Now |
|---|---|---|
| what `enabled` means | 8 spellings across 5 controls — and the stepper's two memos had **already drifted** into a third shape | `contract.enabledNow` / `contract.enabledIn` |
| mounted-node lookup in the renderer | 2 walks, one of them a closure allocated **per changed prop per frame** | one hoisted `findNode` |
| nearest scroll ancestor | a full-tree walk per `scrollToVisible` call, beside a map whose own comment says it exists so that would not happen | `scrollHostOf[path]` |
| grid column count | derived separately in measure and arrange — this file's documented recurring defect class | `gridColumnCount` |
| structural-region bookkeeping | 3 copied 11-line blocks | one `STRUCTURAL` dispatch table |
| `patternEscape` | 4 closures allocated per control instance for one call each | 4 module-scope functions |
| scope diagnostic wording | formatted identically in all 3 cores | formatted in `scope_impl`, where the rule lives |
| path↔attribute rename | a dead export in the codec, and the opposite direction hand-rolled in the controller | `token_sync.attributeForPath` |
| `isPathPrefix` | the same expression inlined 64 lines above the helper | the helper |

**A prior gate repaired.** `theme-packages-and-skinning` was **red before this stage
started** and nobody had noticed. Its `metric-snapshot-single-source` check ended in
`cmp` of **two stored files** — it could never say anything about the current tree —
and it went red when `tools/lune/_theme_baseline`, whose target **defaulted** to one
of those two files, was run without an argument. It now runs `check_flat_baseline`,
which regenerates the neutral render from live source and byte-compares 1 140 nodes;
and the generator now requires its target, so running it bare exits 2 instead of
destroying a comparison input. A prose "do not run this bare" warning in a handoff
doc is no longer load-bearing.

**Two stale claims corrected:** the guide and `authority.luau` presented `host` as a
fifth live authority when nothing writes it (ARCH-F8); and `api.md`'s `AdaptiveStack`
example taught the scope-less `adaptive.conditions` form — the exact six-memo leak
RR-8 was about — while never documenting `opts.scope`.

## What was deliberately retained

**19 candidates, more than were implemented.** The headline one: `isFinite` is
duplicated **15 times** across `src/` and stays that way. It is a zero-decision
predicate with one correct form, consolidating it costs 15 new edges in a
gate-enforced require graph, and the decisive evidence is that `table.luau` already
defines a *third* spelling that deliberately omits the `-math.huge` check — so a
shared owner would not have prevented the one drift that actually happened. Contrast
`enabled`, which encodes a policy and *had* drifted; that one was consolidated.

Also retained with reasons: `toColor3` ×3 and `rgb` ×3 (a new module or cross-require
would cost more than three lines of arithmetic), `authority.nativeSheetOwnedSet` (no
code consumer, but cited by name as a closed gate's PASS evidence),
`feedback.bus.lastError` (write-only, but the named instrument of RR-12's fix),
`fusion_adapter` and `imperative` (277 + 273 apparently-dead lines that a gate
actually runs), `env.locale`, `presenter.onModalPresented`, and eleven more — all in
`candidate-ledger.md`.

## Step 5 carry-overs — every one dispositioned

Reproductions were **run**, not read (`tools/lune/_probe_carryovers.luau`).

- **RR-7-R1 FIXED** — the changed scope semantics now live in
  `tests/conformance/suite.luau`, so they run against custom | fusion | imperative.
  PASS on all three.
- **RR-5-R1 RETIRED — the report is correct, not false.** The control run settles it:
  the same cleanup shape over a scope the parent does *not* own reports `nil`. It
  fires only for a child with two owners, which is the §6.3 aliasing violation
  ARCH-F4 names. Not suppressed; pinned in both directions.
- **RR-3-R1 RETIRED — verified clean.** The residual was explicitly unexecuted.
  Executed: two flights airborne, `registry.dispose()` mid-air — no error, clock
  empty and stays empty, counters match an A/B control rig. Pinned.
- **RR-1-R2 FIXED — the documentation was the defect.** 30 steps, 0 transactions,
  reproduced. The counter is right; the comment claiming `transactions == steps` was
  wrong. Corrected to `transactions <= steps`, equality iff healthy. No counter added.
- **scope-less `adaptive.conditions`** — the live one was the *docs*. The two
  remaining code call sites are per-test cores where the memos die with the core.
- **RR-1-R1, ESC-1, ESC-2** — decision packets only, as instructed, plus three more
  (ARCH-F6's record is stale and is corrected there; the `imperative` conformance
  scorecard is nondeterministic; and three evidenced consolidations were deliberately
  not taken).
- ARCH-F3/F4/F6/F7/F8, R1–R4, PLAT-2/7/8, P2-4/5/6, PG-9 and every rider from the
  responsibility ledger are dispositioned in `carry-over-ledger.md`. One rider was
  **wrong** and is corrected: `topbarInset` does have consumers, and the Studio row
  shows it live and non-zero.

## Verification results

| | Result |
|---|---|
| Library suite | **2567 → 2571**, green. +4 pins, nothing removed or weakened |
| RascalRally suite | 2425 green — no game code touched |
| Public surface | **byte-identical** (139-line dump, `diff` empty) — exports and deprecations frozen |
| `check_registration` / `check_boundary` / `check_docs` / `check_prop_parity` | all exit 0 |
| `stylua --check` | exit 0 — the diff is not a reformat |
| Conformance | custom 42/42; the new cross-core check PASS on all three |
| `check_flat_baseline` | PASS — **1 140 flat nodes** byte-compared (every rect, hit rect, class and adapter prop write); no new change anywhere |
| Prior gates | 16 re-run. **15 exit zero, nothing regressed, one repaired.** `authoring-adaptive-ui` fails identically before and after on its own standing PENDING physical row |
| Headless bench | all 17 scenes same-or-faster; every scene `regression: false`. Explicitly **not** a speedup claim |
| Studio | preflight PASS at the injected final-source stamp; **2 of 5** device rows green with zero diagnostics |

## What is open

**1. `studio-evidence` — CLOSED 2026-07-28.** The place was re-injected at the
review-response source (stamp `efbe185e-2570354`) and **all five rows were re-run**,
not carried forward: desktop-standard 1280×720, compact-phone-portrait 360×691,
compact-phone-landscape 678×339, tablet-landscape 1080×810, console-ten-foot
1920×1080. Every row `ok`, `diagnostics: []`, `solverDiagnostics: 0`, no offscreen
nodes, no node cap, five distinct viewports. The three rows that had never run are
now green. Real adaptation is visible rather than asserted: the phone collapses the
Quality picker segmented → inline, and the console brings up the whole ten-foot
profile (`isTenFoot`, `typographyScale 1.5`, `preferredInput Gamepad`).

A sixth row drives the code the cleanup actually changed: `scroll_host` calls
`scrollToVisible` against **real `ScrollingFrame`s** and reads `CanvasPosition` back —
already-visible is a no-op, the vertical target moves `FocusList` to 456, the
horizontal one moves `Strip` to 570, and the sibling host does not move. That is the
direct evidence that `scrollHostOf[path]` resolves the same host the deleted
full-tree walk did.

The gate check now validates row **content**, not file existence, and was
negative-controlled (drop a row → fail; inject a diagnostic → fail).

Two things are recorded honestly rather than claimed: `preferredInput` reads
`KeyboardAndMouse` on the emulated phone/tablet rows (the earlier session's `Touch`
does not reproduce — an E3 instrument limit, not a library result), and `unfitText` is
non-empty on every row with no pre-cleanup capture to say whether that is new.
Physical touch, rotation and gamepad delivery remain E4 and unproven.

**2. `fresh-context-reviews` — CLOSED 2026-07-28.** All three reviews ran
fresh-context on the raw evidence, none given this file: phase-gate **ACCEPT**,
architecture **ACCEPT WITH FINDINGS**, reactive-runtime **ACCEPT WITH FINDINGS**.
Zero BLOCKERs; no reviewer could establish a behaviour change smuggled into the
cleanup. Four MAJORs were raised — one phantom, three real and all fixed with
mutation proofs. Full account in **`review-response.md`**; reports in
`verifier-{phase-gate,architecture,reactive-runtime}.json`.

The three real MAJORs were all the same defect class, and it is the one this stage
existed to remove: **a check that passes without proving anything.** Two were in this
stage's own gate manifest (`prior-gates-unregressed` compared two stored files and
re-ran no gate; `performance-unregressed` read a `bench.json` written by a different
gate), and two were test pins that pinned nothing (the RR-1-R2 assertion, and the
cross-core conformance check this stage *added*). Fixed by making each one actually
execute what it claims — each verified by mutation: break the thing, watch exactly the
right check go red, restore. That the class survived its own cleanup stage is the
finding worth carrying, and MINOR PG-7's sweep of the remaining manifest is now the
obvious next move.

Everything else the reviewers raised is MINOR and dispositioned in `review-response.md`.
ARCH-3 (a suspected lost liveness check in the renderer) was investigated and
**rejected** — no defect.
