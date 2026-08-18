# Reuse ledger (acceptance RC-10)

Every two-or-more similarity finding from
`artifacts/release-candidate-review/reviews/reuse.md` (plus the architecture
review's ARCH-17/18/19/23/24) is here in one of three states: **CONSOLIDATED**
with the commit that did it, **KEPT SEPARATE** with the concrete recorded reason,
or **SCOPED** with the trigger that reopens it. "They may diverge later" is not a
reason and appears nowhere below.

Wave R5, 2026-08-18. Framework commits `8fe8482`, `1776fb14`, `d1b2d7b2`,
`d32364c5`; RascalRally `6a12637e`.

---

## Consolidated

| Finding | Owner it landed on | Commit | What the guard is |
|---|---|---|---|
| REUSE-1 `isFinite` ×17 | `src/num.luau` (`isFinite`) | `8fe8482` | `tests/leaf_helpers.spec.luau` pins the exact expression against a written-out copy of the original — the risk of one owner is that one edit changes seventeen call sites |
| REUSE-39 whole-pixel rounding | `src/num.luau` (`roundPx`) | `8fe8482` | pinned as `floor(v + 0.5)`, explicitly NOT `math.round`: they differ at negative halves and the layout code was written against this one |
| REUSE-3 segment-aligned path prefix ×7 + **2 unsafe live copies** | `src/paths.luau` (`isPrefix`) | `8fe8482` | a presenter tap case: two screens named `Menu` and `MenuBar`, tap the longer one, assert it fired. Reverting `presenter.luau:3333` reddens it; a positive control with unrelated names stays green |
| REUSE-6 `patternEscape` ×6 | `src/paths.luau` (`escape`) | `8fe8482` | five of six migrated; `src/controls/table.luau` is OFF-LIMITS this wave (cap headroom) and keeps its copy — see *Scoped* |
| REUSE-4 rect algebra, 15+ bodies | `src/rect.luau` | `8fe8482` | both point-in conventions ship under names that say what they do; the epsilons stay arguments at the call sites, because they were decisions |
| REUSE-5 / ARCH-17 bounded Levenshtein ×5, two thresholds | `src/text_distance.luau` | `8fe8482` | `tests/text_distance.spec.luau`: the arithmetic pinned directly, and BOTH threshold policies pinned through their own callers. Eight mutations bite, including the one-character `<` → `<=` that had survived the entire fast tier |
| REUSE-109 client-host bootstrap ×8, three with a frozen motion clock | `src/client/host.luau` (blessed entry point #12) | `1776fb14` | `tests/client_host.spec.luau`, hand-cranked frames: the shipped defect reddens three cases, and one proves a tick hook's write is solved in the SAME frame |
| REUSE-115 13 per-frame loops on three RunService signals | `presenter.onTick` (already existed; the host routes consumers to it) | `1776fb14` / `6a12637e` | RR contract spec pins the ABSENCE: the hosted three acquire no `RunService` and connect to none of the three frame signals |
| REUSE-122 cross-surface z-order had no owner | `screen_target.Opts.displayOrder` | `1776fb14` | absent still means 0, so no existing consumer's layering moved |
| REUSE-88 headless world builder ×106, **two incompatible 5-tuple orders** | `tests/lib/world.luau` | `d1b2d7b2` | `tests/world_substrate.spec.luau` refuses the retired order in BOTH spellings (bare tuple and `w.core, …` shim, via a backreferenced pattern) |
| REUSE-96 `press` ×17 / `settle` ×26 | `world.press` / `world.settle` / `world.tick` | `d1b2d7b2` | `press` is both edges, proved by pressing TWICE; `settle(0)` is one frame, never zero. Default frame counts stay at the call sites — 6, 8, 90 and 120 are each a claim about what is settling |
| ARCH-8 `spec_guard` unreachable from outside the repo | `Facet.specGuard` | `d32364c5` | api.md §`specGuard` + the extension playbook's four-line shape; `check_surface_ledger` and `check_registration` classify both members |
| ARCH-10 / ARCH-11 `controls/contract.luau` | `src/class_contract.luau` (root leaf) | `d32364c5` / `3ca4b51` | zero requires, so `render/` and `layout/` may both take it without depending on `controls/` or on each other |
| ARCH-12 / ARCH-13 two session factories with no teardown | `system.dispose()` / `provider.dispose()` | `d32364c5` | `tests/session_lifetime.spec.luau`, asserted against the core's COUNTERS — the only instrument that tells "disposed" from "the reference went out of scope" |

---

## Kept separate, with the reason

These are the reuse audit's own **(c)** findings plus the ones this wave
measured and declined. Each reason is a property of the code, not a preference.

| Finding | Reason it stays split |
|---|---|
| REUSE-4 the two point-in-rect conventions | They are not the same question. A point exactly on a shared edge is INSIDE for `modal_zones`' zone test and a MISS for `drag_session`'s tiled drop test, and both are right for what they do. `rect.luau` ships `containsClosed` and `containsHalfOpen`; exporting one `contains` would silently pick a winner for six call sites that never discussed it |
| REUSE-4 the four epsilons | 0, 0.5 and 1 are decisions about how much rounding a given caller forgives. They stay arguments; the module takes them |
| REUSE-5 the two suggest thresholds | Case-sensitive ≤2 (closed key sets) vs case-folded `max(2, floor(#name/3))` (motion registries) is a real, user-visible disagreement nobody ever decided. The consolidation moved the ARITHMETIC so the disagreement is legible in one place and settleable later; erasing it silently would have changed error text five call sites' specs pin |
| REUSE-68 three cores' `defaultEq` diverge on NaN | The three cores are ADR-0002's bake-off arms and are *supposed* to differ where their semantics differ; unifying them would remove the thing the benchmark measures |
| REUSE-69 scalar validators at ~25 public boundaries | Each names its own boundary in its own error text, which is the property `spec_guard`'s `where` argument exists to preserve. A shared validator that cannot name the caller makes 25 errors worse to buy one function |
| REUSE-70 `chrome_props.colorSeq`/`numSeq` | Two engine types with two different constructors; the bodies rhyme, the return types do not |
| ARCH-18 `tokens/` ↔ `themes/` directory inversion | Real, and NOT fixed. `tokens/sheet_model` uses **nine** distinct members of `themes/package` (`SCHEMA`, `deriveTypeRole`, `pixelUnitOf`, `VARIANT_STATES`, `TYPE_ROLES`, `ICON_FALLBACK_GLYPHS`, `resolveIcon`, `lintProperty`, `REQUIRED_SPACE_STEPS`) while `themes/package` uses three `tokens/` modules. There is no true cycle. The seam that untangles it is a third module owning the shared authoring vocabulary, which means moving public-ish constants out of two files of 124k and 133k characters — real regression risk against no evidence that anything is wrong today. **Trigger:** the next change that needs `sheet_model` to reach a TENTH member of `themes/package`, or any change that would make `themes/package` require `sheet_model` (which would close the cycle) |
| ARCH-19 `themes/` → `render/authority` | **Not an inversion.** `render/authority.luau` has ZERO requires, so consulting it couples the theme compiler to nothing — the `spec_guard` rule. The traffic is one-way by construction: `themes/package` only READS the manifest, and only to REFUSE a theme property the renderer owns, which is the alternative to a theme silently losing to the renderer on a device. Recorded in `authority.luau`'s header |
| ARCH-23 process-global text-metric caches | **Content-addressed, so sharing is a cache hit and not a coupling.** The key is `(canonical font, size, word)` and the value is what the engine answers for exactly that triple; two cores measuring the same word MUST agree or one is wrong. Per-core scoping would remove the sharing that makes a second surface free and double the round trips `docs/lessons/roblox-text-bounds-boot-window.md` exists because of. Reset seams already existed; the missing part was a stated owner, now in the header, plus `tests/process_globals.spec.luau` |
| ARCH-24 process-global motion registries | **Shared on purpose: the sharing IS the API.** A motion class is a design-system decision and `classes.luau`'s own header says the registry is the only dial, so re-registering a name is the sanctioned tuning move. Two consumers in one VM therefore share a vocabulary and the last writer wins a name — pinned as behaviour in `tests/process_globals.spec.luau` rather than left to be discovered. Making it per-core would change the public shape of `Facet.motion.registerClass` (a break on a compatible-minor wave) and stop the dial working across surfaces, which is what it was built for |
| Dead-code interim: `motion.isRegisteredClass`, `motion.resolveClass` | **NOT DEAD — the finding scanned one repository.** `isRegisteredClass` has a SHIPPED consumer (`games/RascalRally/code/src/client/FacetSponsor/init.luau:413`) plus four RR contract specs; `resolveClass` is read by RR's motion contract spec. Deprecating either would tell the one live consumer to stop using the thing it correctly uses. Facade tests added in `tests/motion_clock.spec.luau` |
| Dead-code interim: `motion.resetClasses`, `motion.resolveCurve` | No caller in either repository, and still kept and undeclared, for two reasons. They are the exact twins of `resetCurves` and `resolveClass`, which ARE called — half a symmetric registry API is a worse surface than all of it. And ADR-0011's ledger requires a non-empty `replacement` (`tests/api_surface.spec.luau`); there is no successor to name, so a row would mean inventing one. Facade tests added |
| Vendor bake-off: `vendor/Fusion` + `core/fusion_adapter` + `core/imperative` | Candidates B and C of ADR-0002's foundation bake-off, kept so the benchmark stays runnable: a decision whose losing arms are deleted cannot be re-checked and becomes an assertion. Not entry points — VERIFIED, not assumed: planting a consumer require of `Facet.vendor.Fusion` and `Facet.core.custom` reddens `check_boundary` with two named violations. Provenance signposts now in `vendor/Fusion/VENDOR.md` and `src/core/README.md` |

---

## Scoped, with the trigger

| Finding | Scope taken | Trigger that reopens it |
|---|---|---|
| **REUSE-88 / 95 / 96 / 104** (controller ruling **R12**) | The shared substrate `tests/lib/world.luau` landed, and ONLY the 26 files carrying the two incompatible 5-tuple return orders migrated onto it — the drift the audit measured. The other ~78 spec-local builders stay: each is a few lines, read beside the spec that uses it, and rewriting a hundred files to prove a point is how a suite acquires a regression nobody can bisect | **The next spec file that ADDS a builder migrates its file.** REUSE-95 (scenario-fixture world ×9) and REUSE-104 (renderer-attach world ×10) are the two natural next layers, and `world.attach` is deliberately left unbuilt until a caller wants it |
| REUSE-6 `patternEscape` in `src/controls/table.luau` | Five of six sites migrated; `table.luau` was OFF-LIMITS this wave (Source-write cap headroom) | The next wave that is allowed to edit `table.luau` — it is a two-line deletion and one require |
| REUSE-109 `examples/gallery`, `examples/performance`, `FacetSponsor` | Not migrated to the host. Both examples bind `motion_driver`, which owns the tick, and the perf lab wraps its refresh in a named profiler span that IS the instrument; migrating either would double-tick, measured in this repository at 0.279 ms/frame on a Galaxy A10e (45% of all Facet time in that capture). `FacetSponsor` does four things between its tick and its refresh and injects `onFrame` as a construction seam its own specs drive — and it was the surface that had the frame RIGHT; the host encodes its idiom | Either example dropping its `motion_driver` bind; or `FacetSponsor`'s frame body reducing to tick+refresh, at which point its work moves to `presenter.onTick`, which is where the racer list's poll went |
| REUSE-3 `presenter.luau:644` (focus ring + adjust bindings) | Fixed by the same one-line owner, but claimed as LATENT rather than proven. Reverting it alone leaves the entire fast tier green — and green through the engine-selection bridge, because a surface that wrongly claims a foreign path resolves it to no node of its own and so paints nothing and selects nothing: the same nothing the correct answer produces | The first shipped pair of prefix-sharing surfaces that both declare adjust targets. Recorded in `tests/leaf_helpers.spec.luau`'s header rather than dressed in a test that proves nothing |

---

## Enforcement (the gap the audit named)

The audit's "Enforcement gap" section observed that none of the 14 `check_*.luau`
or 19 `check_*.py` checkers asserted single ownership of any mechanism in the
report — every finding was held by review alone. What this wave added:

- `tests/world_substrate.spec.luau` — the retired 5-tuple order, both spellings.
  In the SUITE rather than a checker on purpose: the rule is about the test
  suite's own source, and a rule that only runs under `tools/gate.sh` is one an
  author meets for the first time at the gate.
- `tools/check_call_shape_drift.py` (wave §1) — a NEW old-form composite call in
  either repository, with a selftest that plants one of each spelling.
- `tools/check_brand_drift.py` (wave §2) — the `luau-*` theme-tag family, with
  the toolchain names (`luau-analyze`, `luau-lsp`) asserted NOT caught, because a
  guard that cries wolf is a guard people route around.
- `tools/lune/check_boundary.luau` — verified by planting, this wave, that a
  consumer require of `vendor/Fusion` or `src/core/` is refused.
- `tests/session_lifetime.spec.luau`, `tests/process_globals.spec.luau`,
  `tests/leaf_helpers.spec.luau`, `tests/text_distance.spec.luau`,
  `tests/client_host.spec.luau` — each pins the owner's contract, and each was
  mutation-tested against the defect it exists to catch.
