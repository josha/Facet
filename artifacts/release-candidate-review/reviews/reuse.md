[REUSE-AUDIT]: 125 findings

# Facet release-candidate reuse / duplication audit

Commit `b230b87`. Read-only sweep of `src/`, `tools/`, `tests/`, `examples/`, `bench/`,
and the RascalRally consumer at `games/RascalRally/code/src/client`. Nothing was fixed;
`tools/gate.sh` and `tools/perf.sh` were not run.

**Binding rule applied:** two or more similar implementation chunks are a finding —
copied code *and* separate helpers/controls/adapters/pipelines doing the same job with
small variations. A `(c) keep separate` disposition is only recorded where a concrete
reason exists (merged semantics would differ, dependency reversal, more branching than
it removes, obscures a tutorial, measured hot path, or a written policy). "They may
diverge later" was never accepted as a reason.

Every line anchor below was verified with `grep -n` / `sed -n` against the working tree.

## Headline

Nine findings are not "two copies of a helper" — they are **live divergences where a
correct behavior exists in one copy and not its siblings**:

| | What drifted | Anchor of the correct copy | Anchors still carrying the old behavior |
|---|---|---|---|
| REUSE-109 | the per-frame drive steps the motion clock (`presenter.tick`), not just `refresh()` | `FacetSponsor/init.luau:1003` (`PreRender`) | `GaragePilotGui.luau:94-95`, `FacetRacerListGui.luau:73-85`, `FacetSettingsGui.luau:62,73,219,253` — all `Heartbeat` + `refresh()` only, so motion, toasts and transitions are frozen on three shipped surfaces. `presenter.tick` is never mentioned in `docs/guide/*.md` |
| REUSE-110 | the player's own Reduce Motion setting reaches the UI | `shared/ReducedMotion.luau:29-34` (3 readers) | 44 raw `GuiService.ReducedMotionEnabled` reads across 14 client modules; `env:set("reducedMotion", …)` appears **zero** times, so Facet's own `motionPolicy` never sees the app preference |
| REUSE-10 | scroll-anchor compares against the clamped memo instead of the raw engine mirror; a list scrolled to its end whose rows shrink writes nothing and shows blank space | `src/controls/table.luau:794-803` | `src/controls/virtual_list.luau:1097`, `src/controls/virtual_grid.luau:687` |
| REUSE-56 | the `raised` shadow was retuned after a measured director round (0.55/12/y2 "near-invisible"); the light theme still carries 12/y2 | `src/tokens/default_style.luau:74-87` | `src/tokens/default_light_style.luau:51-59` |
| REUSE-3 | segment-aligned path prefix (`/Menu` must not prefix `/MenuBar`) | `src/present/focus_map.luau:69-71` (exported, and imported by `presenter.luau:270`) | `src/present/presenter.luau:640`, `src/present/presenter.luau:3326` |
| REUSE-13 | theme-metrics sanity guard checks the derived keys, not just "a family table exists" | `src/controls/table.luau:481-493` | `src/controls/row_actions_metrics.luau:124-126`, `src/controls/selection_indicator.luau:386`, `src/present/presenter.luau:566-569`, `src/render/renderer.luau:837-840` |
| REUSE-94 | `scrollStub` returns a real unsubscribe so teardown can be asserted | `tests/virtualization.spec.luau:46-55` | `tests/virtual_list_axis.spec.luau:60`, `tests/virtual_list_measured_extents.spec.luau:69`, `tests/virtual_list_row_gap.spec.luau:51`, `tests/virtual_list_variable_extents.spec.luau:63` (all `return function() end`) |
| REUSE-71 | the "framework checkers green" precondition | `tools/lune/gate_manifest.luau:766` (7-command canonical form) | `:955` (no manifest-integrity, no stylua), `:982`, `:1094` (no surface ledger) |
| REUSE-72 | the prior-gates standing-exemption allowlist | `tools/lune/gate_manifest.luau:3209`/`:3467` (9 entries) | `:3689` (drops the traversal exemption, adds a different one) |

## Prior-pass context: three RETAIN decisions no longer hold

`artifacts/code-simplicity-cleanup/candidate-ledger.md` examined and deliberately retained
19 items on 2026-07-24. Most still stand. Three do not, and are re-opened here:

- **RETAIN-01 (`isFinite` ×15)** rests on two claims that are now false. Its "decisive
  evidence" was a third spelling, `finite(raw, fallback)`, in `src/controls/table.luau` —
  `grep -ci finite src/controls/table.luau` returns **0**; that function no longer exists.
  Its cost argument ("15 new inter-module edges… the motion package's headers advertise
  *depends only on the contract types*") over-counts: **7 of the 17 definers already
  require the dependency-free root helper `src/spec_guard.luau`** (`async/resources.luau`,
  `controls/value_model.luau`, `input/autoscroll.luau`, `input/drag_registry.luau`,
  `input/drag_velocity.luau`, `motion/motion.luau`, `render/stage_content.luau`), so those
  seven pay **zero** new edges. `spec_guard` itself has no requires, so the layering
  objection is backwards — anything may require *it*. See REUSE-1.
- **RETAIN-04 (`rectEq` ×3)** under-counted. There are now four rect-equality bodies plus
  a fifth shallow-value comparator duplicated verbatim across a layer boundary
  (`src/controls/selection_indicator.luau:256-278` ↔ `src/render/renderer.luau:2790-2812`),
  and the wider rect algebra has 15+ sites in four different epsilons. See REUSE-4.
- **RETAIN-02 (`toColor3` ×3)** gave "no shared client module exists" as its reason. Three
  independent findings (REUSE-54 shadow writes, REUSE-60 stroke writes, REUSE-62) each
  independently want that module, so the reason dissolves once any one of them lands.

## Enforcement gap

None of the 14 `tools/lune/check_*.luau` or 19 `tools/check_*.py` checkers asserts single
ownership of any mechanism in this report. Every finding below is currently held by review
alone. Acceptance row RC-10 asks for "consolidated under one narrow owner, or kept with a
concrete recorded reason" **plus structural guards** — the guards do not exist yet.

---

## Findings

| ID | Finding | Sev | Conf | Rec |
|---|---|---|---|---|
| REUSE-1 | `isFinite` predicate ×17, byte-identical | High | high | b |
| REUSE-2 | "is this a Readable" ×17 in two incompatible spellings, published owner ignored | High | high | a |
| REUSE-3 | Segment-aligned path prefix ×7 + 2 unsafe inline variants in live routing | High | high | a |
| REUSE-4 | Rect algebra (overlap/contain/point-in/equal/round), 15+ copies, 4 epsilons, 2 edge conventions | High | high | b |
| REUSE-5 | Bounded-Levenshtein "did you mean" ×5, two different thresholds | High | high | b |
| REUSE-6 | `patternEscape` ×6 with an exported owner | Medium | high | b |
| REUSE-7 | Closed-key-set validation bypassed by 3 modules that have the owner available | Medium | high | a |
| REUSE-8 | `deepFreeze` ×3 — one lacks the already-frozen guard, behind a public API | Medium | high | b |
| REUSE-9 | Engine-service acquisition: two conventions, `textService()` written twice | Low | high | a |
| REUSE-10 | Scroll anchoring ×3; two carry the bug the third fixed | High | high | b |
| REUSE-11 | `virtual_grid` re-authors `virtual_window` wholesale | High | high | a |
| REUSE-12 | Own-subtree walk (`adjustTargets` family) ×9 | High | high | b |
| REUSE-13 | Theme-metrics sanity guard ×5; four use the predicate the fifth argues is insufficient | High | high | b |
| REUSE-14 | Axis-lock verdict ×4 with an owner; and the gate is class-blind where the ratified token is class-keyed | High | high | a+b |
| REUSE-15 | Settable-Signal refusal ×8, wording already drifted | Medium | high | b |
| REUSE-16 | Scroll-offset clamp ×4; Table's copy has no NaN guard | Medium | high | b |
| REUSE-17 | Menu panel shell ×3 + a presentation-staleness drift the source predicted | Medium | high | b |
| REUSE-18 | Lazy persistent spring bound into a signal ×4 | Medium | medium | b |
| REUSE-19 | Axis transposition helper families ×3 | Medium | high | b |
| REUSE-20 | Key↔path↔item addressing ×5; Table's is O(N) where siblings are O(1) | Medium | high | b |
| REUSE-21 | `level_picker` re-authors `value_model`'s quantize/fromFraction | Medium | high | a |
| REUSE-22 | Row-keys action context ×2 | Medium | high | b |
| REUSE-23 | Reorder slot→index off-by-one ×2, `insertSlotAt` wrapper ×2 | Medium | high | b |
| REUSE-24 | `bindNativeScroll` public wrapper + latch ×3 | Low | high | b |
| REUSE-25 | Reactive-enum "validate now, tolerate later" ×3 | Low | high | b |
| REUSE-26 | Per-row selected memo: two lifecycle strategies | Low | medium | a |
| REUSE-27 | Two public `resolvePresentation` with different semantics | Low | high | c |
| REUSE-28 | Seven paint walks, each with a private per-path cache and one hand-maintained eviction list | High | high | b |
| REUSE-29 | Hidden-roots filter ×3 verbatim + an import shadowed by its own copy | High | high | a |
| REUSE-30 | Effective text size/face resolver ×5 across measure and paint | Medium | high | b |
| REUSE-31 | Aspect-ratio derivation ×5; grid handles one axis only | Medium | medium | b |
| REUSE-32 | Alignment factor/offset ×4 with two rounding rules | Medium | high | b |
| REUSE-33 | Weighted slack distribution: largest-remainder ×1, float shares ×3 | Medium | medium | b |
| REUSE-34 | Prop→write-channel declared twice, plus a third class-scoping table | Medium | high | b |
| REUSE-35 | Stage/Foreign host seam: three matched twins | Low | high | b |
| REUSE-36 | `screenRectOf`/`paintedRectIn` share 8 lines of shift math | Low | high | b |
| REUSE-37 | `drainDeparted`/`drainAppeared` identical | Low | high | b |
| REUSE-38 | `adaptive.sizeClass`/`heightClass`: one rule, two bodies | Low | medium | b |
| REUSE-39 | `math.floor(v + 0.5)` ×61, one named helper | Low | medium | b |
| REUSE-40 | Five diagnostic-record shapes for one concept | Low | medium | c |
| REUSE-41 | "first candidate that fits, else the declared fallback" ×2 | Low | high | c |
| REUSE-42 | Hand-mounted presenter-private chrome overlay ×7 | High | high | b |
| REUSE-43 | Document-order first-visible-match walker ×3 | High | high | b |
| REUSE-44 | Pointer-dwell engagement state machine ×2 | High | high | b |
| REUSE-45 | Listener list + unsubscribe ×6, two error policies | Medium | high | b |
| REUSE-46 | Duration-ramp driver ×3 inside one module, already asymmetric | Medium | high | b |
| REUSE-47 | `motion/classes` and `motion/curves` are the same registry twice | Medium | high | b |
| REUSE-48 | Blueprint meta-channel attach ×4, read ×2 | Medium | high | b |
| REUSE-49 | "Is this node focusable" ×7, no two agree on the guards | Medium | medium | b |
| REUSE-50 | `easeOutQuad` hand-rolled beside the curve evaluator | Low | medium | c |
| REUSE-51 | Clock-participant done-latch scaffold ×2 | Low | high | c |
| REUSE-52 | Colour-role resolution ×2, already divergent, with a live game workaround | High | high | b |
| REUSE-53 | Slot flat-paint tables hand-mirrored across the two paint paths | High | high | b |
| REUSE-54 | `UIShadow` property write ×3 | High | high | b |
| REUSE-55 | Descriptor→`Font` builder ×3 + the key format declared twice | High | high | b |
| REUSE-56 | `default_style` / `default_light_style` near-copy, with live shadow drift | High | high | b |
| REUSE-57 | Interaction-state colour derivation stated three times | Medium | high | b |
| REUSE-58 | `stampOf` (FNV-1a) written twice | Medium | high | a |
| REUSE-59 | Dotted-path traversal: 2 writers + 3 readers, all hand-rolled | Medium | high | b |
| REUSE-60 | Border `UIStroke` creation ×5 (one missing `ApplyStrokeMode`) + 3 partial name registries | Medium | high | b |
| REUSE-61 | Gradient sequence materialization ×2 | Medium | medium | a |
| REUSE-62 | `toColor3` ×3 plus inline copies | Low | high | b |
| REUSE-63 | The ten-foot rule stated twice inside `environment.luau` | Low | high | a |
| REUSE-64 | `imperative.luau` writes the same `fail` closure twice in one function | Low | high | a |
| REUSE-65 | Copy-on-write decoration hint ×2 in one file | Low | high | b |
| REUSE-66 | Haptics entry-connection teardown ×2 | Low | high | b |
| REUSE-67 | Capitalize-first ×6, sorted-key collection ×8 | Low | medium | b |
| REUSE-68 | Three cores' `defaultEq` diverge on NaN | Low | high | c |
| REUSE-69 | Scalar-shape validators at ~25 public boundaries | Low | medium | c |
| REUSE-70 | `chrome_props.colorSeq`/`numSeq` are the same function twice | Low | medium | c |
| REUSE-71 | Framework-checker chain copied into 12 gate rows, 5 different contents | High | high | b |
| REUSE-72 | Prior-gates allowlist inline-Python'd into 5 rows, 3 different policies | High | high | b |
| REUSE-73 | Python checker report skeleton ×13, 3 dialects, divergent missing-evidence handling | High | high | b |
| REUSE-74 | `check_sf_rows` / `check_spike` / `check_verdicts` are one checker three times | High | high | b |
| REUSE-75 | Shell preamble ×17; five wrappers byte-identical but for one line | Medium | high | b |
| REUSE-76 | `check_*_cli` printer written 4 times | Medium | high | b |
| REUSE-77 | Two Luau line-lints share a copied engine and a comment detector that under-delivers | Medium | high | b |
| REUSE-78 | Perf-lab harness built from scratch ×5 | Medium | high | b |
| REUSE-79 | `tools/lune/artifact.luau` exists and is bypassed by 5 sites | Medium | high | a |
| REUSE-80 | 48 gate rows re-assert the evidence check `gate.luau` already performs | Medium | high | a |
| REUSE-81 | Five ad-hoc `process.args` flag parsers; one already ran the wrong path silently | Medium | high | b |
| REUSE-82 | Capture sha256[:16] pin implemented 5 times in 3 languages | Medium | high | b |
| REUSE-83 | `percentile` ×2; one lacks the empty-sample guard | Medium | high | b |
| REUSE-84 | RascalRally consumer path hardcoded 74×, suite row duplicated 14× | Medium | high | b |
| REUSE-85 | `.luau` directory walkers ×6, two inside one file | Low | high | b |
| REUSE-86 | Probe scene-mount harness copied into 8 probes | Low | medium | b |
| REUSE-87 | Suite-transcript capture/grep idiom ×179/×1412 | n/a | high | c |
| REUSE-88 | Headless stack builder ×106 across 100 spec files, two incompatible return orders | High | high | b |
| REUSE-89 | Recursive deep-copy ×16 | High | high | b |
| REUSE-90 | Neutral-derived theme-package fixture ×10 | High | high | b |
| REUSE-91 | Reference theme-package registry ×9, already divergent | High | high | b |
| REUSE-92 | Five `ref_*` gallery scenarios, 122 lines each, differing in 4 identifiers | High | high | b |
| REUSE-93 | `adapter_source`/`renderer_source` bypassed by 29 raw reads — silent-green pins | High | high | a |
| REUSE-94 | `scrollStub` ×6; five return a no-op unsubscribe | High | high | b |
| REUSE-95 | Scenario-fixture world ×9 | Medium | high | b |
| REUSE-96 | `press` ×17 and `settle` ×26 drive helpers | Medium | high | b |
| REUSE-97 | Diagnostics assertions ×12 at three fidelities | Medium | high | b |
| REUSE-98 | Virtual-collection fixtures (`makeRows`/`makeItems`/`newList`) ×19 | Medium | high | b |
| REUSE-99 | Sponsor-scenario trace recorder ×8 | Medium | high | b |
| REUSE-100 | Theme-install step ×7; only one carries the refusal-reason lesson | Medium | high | b |
| REUSE-101 | `section()` source-slicing ×7, inconsistent inside one file | Medium | high | a |
| REUSE-102 | `device_views.VIEWS` vs `theme_matrix_audit`'s VIEWS — the comment says identical; they are not | Medium | high | a |
| REUSE-103 | `fails` ×8, `contains` ×8 (two contracts, one name), `near` ×2 re-implementing `toBeCloseTo` | Medium | high | a+b |
| REUSE-104 | Renderer-attach world ×10 | Medium | high | b |
| REUSE-105 | `fixed`/`fill` Dim shorthands ×21 | Low | high | b |
| REUSE-106 | `clip(text, chars)` in both gallery pickers | Low | high | b |
| REUSE-107 | Two bench registries share three workload names | Low | medium | c |
| REUSE-108 | `cloneRows` in a tutorial and in a fixture | Low | high | c |

| REUSE-109 | Facet client host bootstrap ×4; three of four freeze the motion clock | High | high | b |
| REUSE-110 | Reduced motion has three authorities; the player's own setting reaches ~3 of ~44 sites | High | high | b |
| REUSE-111 | Spring solver + motion-class registry duplicated wholesale in the game | High | high | a |
| REUSE-112 | `AVG_GLYPH_FRACTION = 0.62` copied into the game 5× beside the real measurer | High | high | a |
| REUSE-113 | Device-chrome facts re-derived 5× and watched 13× because they need a mounted surface | High | high | b |
| REUSE-114 | The racer list exists three times, two finish latches, three badges | High | high | a+b |
| REUSE-115 | 13 game modules own a per-frame loop across three different RunService signals | Medium | high | b |
| REUSE-116 | Settings pair: ~130 lines of dock chrome duplicated, plus a positional binding | Medium | high | a+b |
| REUSE-117 | Four surface-plate recipes, a triplicated ribbon, 15 corner-radius values | Medium | high | b |
| REUSE-118 | Hand-rolled keyed reconciler + transient banner in the always-on HUD | Medium | high | a |
| REUSE-119 | The Facet arm produces no UI sound and no haptics | Medium | high | a |
| REUSE-120 | External-observable→Signal adapter ×3 shapes, no framework owner | Medium | medium | b |
| REUSE-121 | Blueprint node identity is a hand-maintained path string; 17 `PATHS` tables | Medium | medium | b |
| REUSE-122 | Cross-surface z-order has no owner; Facet roots default to the bottom | Medium | high | b |
| REUSE-123 | Three input models the framework already extracted, still live in the game | Low | high | c |
| REUSE-124 | Boot-readiness is a game-invented viewport spin loop | Low | high | b |
| REUSE-125 | Studio-only preview modules ship to every production client | Low | high | b |

---

# Details

## A. Cross-cutting (spanning three or more directories)

### REUSE-1 — `isFinite` predicate ×17, byte-identical · High / high
**Responsibility:** "is this a real number" (`type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge`).
**Duplicates (all identical):** `src/async/resources.luau:62` · `src/controls/value_model.luau:43` · `src/input/autoscroll.luau:106` · `src/input/drag_registry.luau:92` · `src/input/drag_velocity.luau:40` · `src/input/spatial.luau:72` (`isFiniteNumber`) · `src/motion/chase.luau:46` · `src/motion/classes.luau:64` · `src/motion/curves.luau:105` · `src/motion/motion.luau:164` · `src/motion/spring.luau:75` · `src/motion/timeline.luau:48` · `src/present/toast_schedule.luau:70` · `src/render/stage_content.luau:24` · `src/themes/package.luau:536` (`isFiniteNumber`) · `src/tokens/chrome_props.luau:61` · `src/tokens/styling.luau:171`. Two coerce-with-fallback wrappers over it: `src/present/toast_schedule.luau:74-76` (`positive`), `src/input/autoscroll.luau:110-112` (`number`).
**Callers:** private to each module; ~120 call sites total.
**Invariants / lifecycle / errors / perf:** pure, no lifecycle. The *reason* it exists is stated once, at `src/motion/spring.luau:72-74` — a non-finite value "would pin a driver awake forever writing NaN into a property — which blanks the surface permanently". The other sixteen carry no reasoning. Motion copies run per frame, so the shared form must be bound to a local upvalue at each call site.
**(b) Extract** `spec_guard.isFinite(v): boolean` onto the existing dependency-free root helper `src/spec_guard.luau` (zero requires, already required by 39 modules across six directories), bound locally where it is hot. Re-opens RETAIN-01 for the reasons in "Prior-pass context" above.

### REUSE-2 — "Is this a Readable" ×17 in two incompatible spellings · High / high
**Responsibility:** decide whether a spec value is a reactive node and, if so, read it (subscribing when a `use` is in hand).
**The owner already exists and is public:** `src/blueprint.luau:491-494` defines and exports `isReadable`, surfaced as `Facet.UI.isReadable`; `src/controls/row_actions.luau:652-655` calls it "the framework's own published check" and uses it, as does `src/controls/async_image.luau:99` and `src/mount.luau:581`.
**Kind-typed copies (`kind == "signal" or "memo"`):** `src/present/feedback.luau:143-145` (whose comment at `:139` says "the same predicate as `blueprint.isReadable`, restated rather than imported") · `src/controls/text_input.luau:106-108` · inline at `src/blueprint_schema.luau:303`, `src/present/focus_map.luau:648`, `src/tokens/styling.luau:447`, `src/present/presenter.luau:318`. Wrapped into `readValue(source, use)` verbatim twice: `src/controls/picker.luau:281-286`, `src/controls/selection_indicator.luau:285-290`.
**Duck-typed copies (`.get ~= nil`), which accept a different set of values:** `src/controls/callout.luau:135-140` · `src/controls/menu.luau:326-332` and `:338-343` · `src/controls/popup_button.luau:226-231` · `src/controls/progress_view.luau:480`.
**Drift:** the two predicates disagree. A caller passing a table with a `get` method that is not a Facet node is read as reactive by Menu/PopupButton/Callout/ProgressView and treated as a literal value by Picker/SelectionIndicator/TextInput/feedback. `src/controls/selection_indicator.luau:288` documents the bug that motivated widening one of the kind-typed copies to cover memos; that fix never reached the duck-typed three.
**Invariants:** must subscribe when `use` is present and peek otherwise; `Facet.UI.isReadable` is public surface and cannot change shape.
**(a) Reuse** `blueprint.isReadable` at every kind-typed site. **(b)** additionally extract `src/controls/reactive_value.luau` with `read(v)`, `readIn(use, v)` and `pair(spec) -> (now, in_)` for the ten `xNow()/xIn(use)` hand-written pairs in `virtual_list`/`virtual_grid` (`virtual_list.luau:821/824, 830/833, 836/839, 660/663`; `virtual_grid.luau:350/355, 375/378, 389/392, 409/412`), and settle the duck-vs-kind question once.

### REUSE-3 — Segment-aligned path prefix ×7 + 2 unsafe inline variants in live routing · High / high
**Responsibility:** "is `path` inside `prefix`'s subtree", matched on the `/` separator so `/S/Row` never matches `/S/RowTwo`.
**Correct copies:** `src/present/focus_map.luau:69-71` (**exported** at `:829`, and already imported by `src/present/presenter.luau:270` and `src/present/text_reveal.luau:50`) · `src/present/help_plate.luau:80-85` · `src/layout/text_audit.luau:101-105` · `src/controls/row_actions_spec.luau:65-67` (also re-exported at `:161`) · inline at `src/render/renderer.luau:595` and `src/render/renderer.luau:3628`.
**Unsafe variants — no separator check:** `src/present/presenter.luau:640` (`string.sub(path, 1, #rootPath) == rootPath`, decides which surface draws the focus ring) and `src/present/presenter.luau:3326` (`handleByPath`, decides which surface a tap routes to). Two presented screens named `Menu` and `MenuBar` route each other's taps.
**This exact bug class is named in-tree twice:** `src/layout/text_audit.luau:99-100` — "the false-positive every prefix test in this repository has had to be fixed for at least once" — and `src/render/renderer.luau:592-594` (verifier P2-2). The file that imports the safe version at line 270 uses the unsafe form at lines 640 and 3326.
**Callers:** focus-ring ownership and tap routing are on every pointer event.
**(a) Reuse** `focusMap.isPathPrefix` at both presenter sites immediately (it is already in scope). **(b)** then move the 3-line function to a dependency-free `src/paths.luau` so `layout/`, `render/` and `controls/` can require it without depending on `present/` — that dependency direction is why `text_audit`, `renderer` and `row_actions_spec` grew their own.

### REUSE-4 — Rect algebra: 15+ copies, four epsilons, two edge conventions · High / high
**Responsibility:** overlap, containment, point-in-rect, rect equality, rect rounding.
**Pairwise intersection (`min(right) - max(left)` per axis):** `src/render/hit_lift.luau:73` (epsilon 0) · `src/layout/text_audit.luau:142` (caller epsilon 1) · `src/layout/composition.luau:1985-1986` (epsilon `EPS = 0.5`, `composition.luau:1500`) · `src/render/surface_overlap.luau:227-228` (epsilon 0) · `src/tokens/chrome_slots.luau:2314`.
**Containment:** `src/render/surface_overlap.luau:183` (exact) · `src/render/renderer.luau:540` (`CLIP_EPSILON = 0.5`, `:539`).
**Point-in-rect, two incompatible conventions:** closed `[x, x+w]` at `src/present/modal_zones.luau:35-37`, `src/render/renderer.luau:3640-3641`, `src/render/renderer.luau:3773`; half-open `[x, x+w)` at `src/input/drag_session.luau:53-55`, `src/input/drag_registry.luau:241`, `src/input/autoscroll.luau:154-158`. `drag_session.luau:50-52` documents why half-open is right for tiled rects; `modal_zones` documents nothing. A tap exactly on a shared edge is Zone A for the modal test and a miss for the drop test.
**Rect equality:** `src/render/renderer.luau:257-262` (injected into `rect_pass.new` at `:774`) · `src/controls/text_input.luau:110-115` (verbatim) · `src/controls/slider.luau:186-191` · `src/client/screen_presentation.luau:373,377` (field-by-field inline). Plus a shallow-value comparator duplicated across a layer boundary: `src/controls/selection_indicator.luau:256-278` (exported as `selection_indicator.sameGeometry`) and `src/render/renderer.luau:2790-2812` (`sameGeometryValue`) — logically identical bodies.
**Centres:** `src/input/drag_registry.luau:96-101` (`centerOf`) and `:418-423` (`centerAim`, re-derives the same expression).
**Self-declared:** `src/render/surface_overlap.luau:193-196` — "This is ADR-0025's collision loop with regions swapped for surfaces — same arithmetic, same `{ a, b, dx, dy }` row, same 'touching is not overlapping' epsilon of zero". ADR-0025's loop is `composition.luau:1983-2001`, which uses epsilon 0.5.
**Perf:** `hit_lift.overlaps` runs single-digit times per surface (`hit_lift.luau:86-91`); no hot-path exemption applies.
**(b) Extract** `src/layout/rect.luau` (engine-free, no requires, legal from `render/`, `layout/`, `present/`, `input/` and `controls/`): `intersection(a,b) -> (dx, dy)`, `overlaps(a,b,epsilon?)`, `contains(outer,inner,epsilon?)`, `containsClosed(r,x,y)`, `containsHalfOpen(r,x,y)`, `equal(a,b)`, `sameFlatValue(a,b)`, `centre(r)`, `round(r)`. Every call site passes its own epsilon; the two point-in conventions get two names, because exporting one `contains` would silently pick a winner.

### REUSE-5 — Bounded-Levenshtein "did you mean" ×5, two thresholds · High / high
**Responsibility:** suggest the nearest legal name for an unknown key/class/curve.
**Matrix implementations (byte-identical 24-line bodies in the last three):** `src/spec_guard.luau:45-69` (`nearest`, cutoff `bestD = 3`, case-sensitive) · `src/themes/package.luau:547-570` (`nearest`, same cutoff, same comment) · `src/blueprint_schema.luau:2479-2502` (`distance`) · `src/motion/classes.luau:71-94` (`distance`) · `src/motion/curves.luau:222-245` (`distance`).
**Threshold divergence, user-visible:** `spec_guard` and `themes/package` accept distance ≤ 2, case-sensitively. `motion/classes.luau:114-130`, `motion/curves.luau:268-282` and `blueprint_schema.luau:2629-2660` lowercase both sides and accept `d <= math.max(2, math.floor(#name / 3))`. A misspelled prop and a misspelled curve name therefore get different suggestion policies from one framework.
**List renderers, also duplicated:** `src/spec_guard.luau:71-78` (`", "` separator) vs `src/themes/package.luau:572-579` (`" | "` separator) — same function, different punctuation in the error the author reads.
**The reasoning is already recorded as backwards:** `src/spec_guard.luau:42-44` says its copy is "kept local because this module must stay dependency-free". `spec_guard` has **zero requires**; the direction that follows is that `themes/package` and `blueprint_schema` may require *it*.
**(b) Extract** `src/text_distance.luau` (leaf, no requires): `nearest(bad: string, candidates: { string }, opts: { maxDistance: number?, caseFold: boolean? }?) -> string?` plus `spec_guard.listOf(set) -> string`. Each caller keeps its own threshold as an argument; the matrix and the separator policy exist once. Then decide the case-folding question deliberately instead of five times.

### REUSE-6 — `patternEscape` ×6 with an exported owner · Medium / high
**Responsibility:** escape a node id for interpolation into a Lua pattern (`return (s:gsub("%W", "%%%0"))`).
**Duplicates (all byte-identical, 2 lines):** `src/controls/row_actions_spec.luau:53-55` (the owner — exported at `:160`, consumed by `src/controls/row_actions.luau:185`) · `src/controls/popup_button.luau:25-27` (used at `:170`) · `src/controls/text_input.luau:38-40` (`:508`) · `src/controls/table.luau:61-63` (`:1099`) · `src/controls/virtual_grid.luau:246-248` (`:850`) · `src/controls/virtual_list.luau:285-287` (`:860`).
**Prior disposition:** RETAIN-06 kept these on the reasoning that "these four live in four modules that otherwise have no reason to know about each other". That reason is answered by putting it on a leaf, not by a cross-require.
**(b) Extract** into the same `src/paths.luau` proposed in REUSE-3: `paths.escape(s)` and `paths.isPrefix(prefix, path)`. `row_actions_spec` keeps its re-export for API stability. Both helpers are pattern/path string work and belong to one owner.

### REUSE-7 — Closed-key-set validation bypassed by three modules · Medium / high
**Responsibility:** refuse an unknown key on a spec table and name the legal set.
**Owner:** `src/spec_guard.luau:85-97` (`assertKnownKeys`) + `:101-107` (`keySet`), used at 74 call sites in 39 modules.
**Private re-implementations:** `src/tokens/styling.luau:32-43` (array-based, message `unknown {what} field '…'`, no suggestion) — used at `styling.luau:79` and `:252`, i.e. behind the **public** `UI.shadow`/`UI.shadowData`/`UI.gradient`/`UI.gradientData`; `src/layout/composition.luau:516-535` (`fail`/`keyList`/`checkKeys`, with `keyList:520-527` being `spec_guard`'s sorted-concat verbatim); `src/layout/anchor_placement.luau:109-116` (`names(set)`, feeding three enum asserts at `:121,:127,:133`).
**Consequence:** four public boundaries produce a worse error than every other public spec in the framework — no "did you mean", different sentence shape.
**Constraint checked:** `spec_guard` has no requires, so none of the three creates a cycle.
**(a) Reuse** `spec_guard.assertKnownKeys` in `styling` and `composition`; expose `spec_guard.listOf(set)` for `anchor_placement`'s value-in-set asserts, which are a genuinely different question and keep their own bodies.

### REUSE-8 — `deepFreeze` ×3, one without the already-frozen guard, behind a public API · Medium / high
**Responsibility:** recursively freeze a compiled token tree.
**Guarded:** `src/blueprint_schema.luau:2392-2400` (its comment at `:2391` states the reason: "already-frozen table, so the walk checks `table.isfrozen` first") · `src/themes/package.luau:581-594` ("re-freezing one is an error in Luau, so the guard is load-bearing, not defensive noise").
**Unguarded:** `src/tokens/tokens.luau:134-141`, reached from `tokens.compile` (`:66`, exported publicly as `Facet.tokens`). `tokens.compile` shallow-`table.clone`s each section (`:143-152`), so nested tables are aliased from the caller's schema. A consumer calling `Facet.tokens.compile` with any already-frozen nested table therefore errors, where the same input through `themes.package` works — because `src/themes/package.luau:596-607` wraps the call in a bespoke `deepCopy` for exactly this reason. The workaround and the missing guard are the same defect seen twice.
**Adjacent copy/merge walkers with no owner:** `src/themes/package.luau:598-607` (`deepCopy`) · `src/themes/snapshot.luau:329-335` (`frozenClone`) · `src/blueprint_schema.luau:1275-1282` (shallow `merge`) · `src/client/theme_controller.luau:102-118` (`mergedExtra`, shallow 2-level) · `src/core/profile.luau:178-181` · `src/client/screen_target.luau:3169-3172` and `:3195-3198`.
**(b) Extract** `deepFreeze` (with the guard) and `deepCopy` onto `src/spec_guard.luau` or a new `src/table_util.luau`; `tokens.compile` uses the guarded one and `package.deepCopy`'s reason for existing disappears. Keep `inherit` (`package.luau:611`) and `mergedExtra` separate — **merge semantics genuinely differ** (deep-inherit vs 2-level override).

### REUSE-9 — Engine-service acquisition: two conventions, one helper written twice · Low / high
**Responsibility:** obtain a Roblox service from a module that may be required off-engine.
**Two conventions in one directory:** module-scope `local X = game:GetService(...)` in 13 files (`src/client/roblox_input.luau:12-13`, `screen_target.luau:21-25`, `roblox_env.luau:7-9`, `screen_chrome.luau:25`, `edit_preview.luau:18`, `screen_scroll_indicators.luau:30`, `motion_driver.luau:26-27`, `screen_paint.luau:53-54`, `screen_pointer.luau:40-41`, `roblox_resources.luau:23-24`) vs lazy accessor functions in five (`text_premeasure.luau:38-40,:41-43`, `text_calibration.luau:28-30`, `responder_effects.luau:34,:45`, `gamepad_contention.luau:160,:207,:247,:278,:294`, `native_style.luau:277-278`).
**Verbatim duplicate:** `textService()` at `src/client/text_premeasure.luau:38-40` and `src/client/text_calibration.luau:28-30`, both carrying the same lazy-resolve rationale in their headers — and `text_calibration.luau:34` already requires `text_premeasure`.
**Invariant:** `text_premeasure.luau:35-37` states it — a module-scope `game:GetService` "would make the require itself engine-only", which the theme controller's headless lifecycle depends on. That is a real distinction between the two conventions, not an accident; only the duplicated accessor is a finding.
**(a) Reuse:** export `text_premeasure.textService()`. Leave the convention split alone — it encodes which modules must stay require-safe off-engine.

## B. `src/controls`

### REUSE-10 — Scroll anchoring ×3; two carry the bug the third fixed · High / high
**Responsibility:** hold the leading-edge item still when the offset table re-derives.
**Duplicates (same six-part shape: `anchorKey`/`anchorDelta` upvalues, an `observe(scrollTop)` capture through `ix.window(top, 0, 0)`, an `observe(layoutIndex)` re-apply, a key→index lookup, a `math.clamp(offsetOf(i) + anchorDelta, 0, max(0, content - viewport))`, and a `< 0.5` drift skip):** `src/controls/virtual_list.luau:1061-1101` · `src/controls/virtual_grid.luau:652-691` · `src/controls/table.luau:757-807`.
**The live drift:** `src/controls/table.luau:803` compares against `scrollTop:get()` — the raw engine mirror — and its comment at `:794-802` gives the measured reason: *"a list scrolled hard against its end whose rows then SHRANK looks already-correct — the memo clamps to the new maximum while the real `CanvasPosition` is still a thousand pixels past the last row, so nothing is written and the player is left staring at blank space. Measured: 400 rows shrinking 43px -> 40px at the end of the list left the engine 1200px out of range."* `src/controls/virtual_list.luau:1097` and `src/controls/virtual_grid.luau:687` still compare against `clampedTop:get()`. Second divergence: when the anchored item is gone, `table.luau:788` clears `anchorKey = nil` while `virtual_list.luau:1092` and `virtual_grid.luau:681` bare-`return`, keeping a stale key.
**Callers:** `Facet.newTable`/`newVirtualList`/`newVirtualGrid` (`src/init.luau:172,173,177`); specs `table_virtualized`, `virtual_list_variable_extents`, `virtual_grid`, `virtual_hgrid`; `examples/gallery/examples/02_playlist_table.luau`; RascalRally `FacetSponsor/RacerList.luau` and `FacetRacerListScreen.luau`.
**Lifecycle / perf:** upvalues owned by the control scope; both observers `scope:own`ed; fires on every engine scroll report.
**(b) Extract** `src/controls/scroll_anchor.luau`: `new(deps: { core, scope, scrollTop, clampedTop, layoutIndex, indexOf, keyAt, slotOf, offsetOf, contentNow, viewportNow, write })`. The grid's line↔index mapping is the only real variation and fits `slotOf`. Fixing the two live bugs by hand without this leaves the fourth collection control free to reintroduce them.

### REUSE-11 — `virtual_grid` re-authors `virtual_window` wholesale · High / high
**Responsibility:** the running-offset windowing machinery over `src/virtual_extents.luau`.
**`src/controls/virtual_window.luau` exists as the extracted owner** (its header at `:9` and `:33` names `virtual_grid.luau` as the sibling), and `virtual_list` consumes it. `virtual_grid` does not; it re-authors every part:
per-slot extents + throwing validation `virtual_window.luau:122-166` ↔ `virtual_grid.luau:436-453`; identity cache `:169-191` (`sameLayoutInputs`) ↔ `:460-479` (`sameInputs`, element-wise body identical); cached `layoutIndex` memo `:192-201` ↔ `:481-497`; `layoutNow()` `:202-204` ↔ `:498-500`; construction-time validation `:222-225` ↔ `:503-508`; `indexByKey` memo ↔ `:508-515`; `canvasDim` `:319-321` ↔ `:521-523`; `clampedTop` `:326-333` ↔ `:525-532` (NaN guard included); `sameWindow` `:337-346` ↔ `:553-562`; `windowItems` `:348-361` ↔ `:566-583`; `pathOf` `:367-375` ↔ `:610-621`.
**Invariants:** the identity cache is what makes `observe(layoutIndex)` mean "offsets actually moved"; `sameWindow` is what keeps a same-window scroll at zero framework writes. `tests/virtual_list_variable_extents.spec.luau` counts index constructions directly; the grid has no equivalent guard.
**(a) Reuse** `virtual_window.new`, widened with `slotCountOf(use)` (grid: `lineCountOf(#items, lanes)`; list: `#rows`) and `keyOfSlot`. The grid keeps lane division, `bandOffset` and `lanesDim`, which are genuinely its own.

### REUSE-12 — Own-subtree walk (`adjustTargets` family) ×9 · High / high
**Responsibility:** walk the control's own mounted node tree and collect or resolve paths matching a predicate.
**Collect-by-class:** `src/controls/level_picker.luau:524-540` (Grip) · `src/controls/stepper.luau:227-240` (Button) · `src/controls/slider.luau:600-621` (Track Grip) · `src/controls/table.luau:3477-3494` (header-column pattern).
**Resolve-named-descendants:** `src/controls/tab_view.luau:558-576` · `src/controls/selection_indicator.luau:640-657` · `src/controls/slider.luau:541-552` (a second walk in the same file).
**Ordered focus-set collection:** `src/controls/virtual_grid.luau:903-943` · `src/controls/virtual_list.luau:2683-2748` · `src/controls/virtual_list.luau:358-372` · `src/controls/table.luau:3302-3311`.
**The invariant every copy restates in prose:** the walk must start at the *contribution's own node*, never the screen root — a live-found 2026-08-02 defect re-told at `level_picker.luau:521`, `stepper.luau:224` and `slider.luau:596`. One fix, three separate retellings, nine places it could regress.
**Callers:** `src/present/presenter.luau:2889` and `:2905` (`c.bundle.adjustTargets(c.node)`); contract at `src/input/contribution.luau:208`.
**(b) Extract** `src/controls/node_walk.luau`: `collect(rootNode, match) -> { string }` (document order), `set(rootNode, match) -> { [string]: boolean }`, `resolveByIds(rootNode, wanted) -> { [string]: string }`. The virtual controls' focus-descriptor rows stay local, built on `collect`.

### REUSE-13 — Theme-metrics sanity guard ×5, four use the weak predicate · High / high
**Responsibility:** a garbage `themeMetrics` fact must fall back to `themeSnapshot.neutral()` rather than leak past the seam that read it (§8.2).
**The strong predicate:** `src/controls/table.luau:481-493` checks `controls.table.rowHeight`/`.rowLines`/`.rowPadding` **and** `raw.type.body`, arguing at `:484-486` that the weak form is insufficient — *"a hand-built metrics table is exactly the shape that would have them missing"*.
**The weak predicate (`type(raw.controls) == "table"` or one section):** `src/controls/row_actions_metrics.luau:124-126` · `src/controls/selection_indicator.luau:386` · `src/present/presenter.luau:566-569` (`targetSizes`) · `src/render/renderer.luau:837-840` (`type`).
**And two of them cite Table as their precedent while implementing the weaker check:** `row_actions_metrics.luau:117-119` and `selection_indicator.luau:374-377`.
**Consequence:** a partial adapter fact reaching the solver produces wrong geometry; one of five doors is actually shut.
**(b) Extract** `snapshot.sane(raw) -> Metrics` onto `src/themes/snapshot.luau`, which already owns `neutral()`. All five call it. Naming it at the snapshot layer avoids a control depending on another control.

### REUSE-14 — Axis-lock verdict ×4 with an owner; and the gate is class-blind · High / high
**Responsibility:** "has this gesture crossed the lock, and which axis owns it — ties go vertical".
**Owner:** `src/input/row_actions_state.luau:32-37` (`self.axisVerdict(dx, dy)`), pure — `src/controls/row_actions.luau:2534-2536` records that it "never reads width/fullSwipe, so which decision instance answers it is immaterial", i.e. it is only accidentally trapped on the constructor's instance. Used at `row_actions.luau:2537`.
**Inline re-implementations:** `src/controls/row_actions_reorder.luau:88-99` · `src/controls/virtual_list.luau:1892-1900` (`hostedResolveAxis`) · `src/controls/table.luau:1855`. Each carries a comment asserting it is "the identical rule" (`row_actions_reorder.luau:85-87`, `virtual_list.luau:1881-1884`, `table.luau:1809`).
**The second, larger half — a class-blind gate:** `src/input/interaction_tokens.luau:29-35` is the framework's ratified press→drag token table (`pointer 6`, `touch 14`, `keyboard 0`, `gamepad 0`), with the predicate at `:81-92`. Its own header at `:6-12` says: *"Table shipped a private `DRAG_THRESHOLD = 6` for exactly this reason and it was correct for mice and wrong for fingers. It now reads the token."* `row_actions_state.AXIS_LOCK_PX = 8` (`:8`) is a single number for every input class, so the swipe/reorder lock is 8 px on a finger where the ratified touch gate is 14. Related: `src/controls/table.luau:1335` hardcodes `interactionTokens.promotionPx("pointer")`, so the column-drag gate is mouse-tuned on touch.
**Honest caveat:** an axis *lock* (which of two gestures owns this pan) and a press→drag *promotion* are not the same decision, so the two numbers need not be equal. The finding is that the lock's travel gate is class-blind where the framework's stated position is that travel gates are class-keyed, and that the tie-break rule is authored four times.
**(a)+(b):** hoist `row_actions_state.axisVerdict(dx, dy)` to module scope (keeping the instance method as a forwarder) and have the three inline sites call it; then have that one body take its gate from `interaction_tokens` keyed by the event's pointer class, with `AXIS_LOCK_PX` retained as the `pointer`-class value.

### REUSE-15 — Settable-Signal refusal ×8, wording already drifted · Medium / high
**Responsibility:** refuse a non-Signal (notably a read-only Memo, which duck-types as settable and fails on first tap) at build time.
**Duplicates:** `src/controls/chip.luau:51-58` · `disclosure_group.luau:54-61` · `level_picker.luau:251-258` · `picker.luau:297-299` · `popup_button.luau:104-111` · `slider.luau:145-152` · `stepper.luau:82-89` · `tab_view.luau:265-272`.
**Drift:** `src/controls/chip.luau:44-49` says "Same check, same wording, as Stepper/Slider/Rating/Picker/DisclosureGroup/TextInput (CTRL-03)" — but `picker.luau:298` has already lost the parenthetical explanation the other seven carry, so a Picker author gets a strictly worse message.
**(b) Extract** `contract.requireSignal(constructor, id, field, value, valueType?)` onto `src/controls/contract.luau` — the module that already owns the shared `enabled` policy (`contract.luau:154-185`), consolidated for exactly this reason.

### REUSE-16 — Scroll-offset clamp ×4; Table's copy has no NaN guard · Medium / high
**Sites:** `src/controls/virtual_window.luau:326-333` (with the NaN/garbage-mirror guard) · `src/controls/virtual_grid.luau:525-532` (guard included) · `src/controls/table.luau:730-733` (**no guard** — a garbage mirror value reaches `math.clamp` unfiltered, which is the "phantom window" case the other two defend against). Adjacent: `maxTop()` at `virtual_grid.luau:534-536` ↔ `virtual_list.luau:1111-1113` ↔ `table.luau:679-681` (`clampScroll`); `scrollTo` at `virtual_grid.luau:623-629` ↔ `virtual_list.luau:2959-2965`; `sameWindow` key-sequence equality at `virtual_window.luau:337-346` ↔ `virtual_grid.luau:553-562` ↔ `table.luau:1304-1313`.
**(b) Extract** `clampOffset(raw, content, viewport)` and `sameKeySequence(a, b, field?)` onto `src/virtual_extents.luau` — already the shared arithmetic owner and already required by `table.luau:49`. The grid's share is subsumed by REUSE-11.

### REUSE-17 — Menu panel shell ×3 and a presentation-staleness drift the source predicted · Medium / high
**Already shared correctly:** `src/controls/menu_recipe.luau` owns the row (`:127-176`), the divider (`:183-186`), the row height (`:104-111`) and the presentation rule (`:89-101`); `popup_button.luau:255-268`, `menu.luau:422-437` and `row_actions.luau:1773-1788` all use it.
**Not shared:** the divider-dispatch loop (`menu.luau:422-437`, `popup_button.luau:255-268`, `row_actions.luau:1773-1788`) and the panel shell (`menu.luau:437-449`, `popup_button.luau:287-305`, and a third at `row_actions.luau:2015-2033`) — the same `isSheet` ternary over `anchor`/`width`/`surface`/`padding` plus `gap = menuRecipe.ROW_GAP`.
**The drift the source predicted:** `src/controls/menu.luau:334-337` says *"The rule is `menu_recipe`'s, shared with `popup_button` — two copies drift, and the drift only shows on the input class nobody tested."* Verified: `menu.luau:355-367` resolves presentation through a reactive memo (`useFact(use, …)` subscribes), while `popup_button.luau:235-245` reads it once per panel build via non-subscribing `readFact`. An open Menu re-presents on rotation or an input-class hot-switch; an open PopupButton does not.
**(b) Extract** onto `menu_recipe`: `rows(UI, items, opts)`, `panel(UI, { id, presentation, rows, anchor?, offsetY? })`, and `presentationMemo(core, scope, { requested, count, sizeClass, interactionClasses })`. Adopting the memo in `popup_button` fixes the drift.

### REUSE-18 — Lazy persistent spring bound into a signal ×4 · Medium / medium
**Responsibility:** build a spring on first use once a `motionClock` exists, observe it into the control's own signal, and fall back to instant placement when there is no clock.
**Sites:** `src/controls/row_actions.luau:1030-1040` + `:1047-1054` · `row_actions.luau:1327-1340` + `:1342-1356` · `src/controls/selection_indicator.luau:538-560` + `:563-575` + `:576-596` · `src/controls/virtual_reorder.luau:242-263` (keyed, with `disposeSlide` at `:230-241`).
**Invariants restated in all four:** a spring is retargeted, never recreated (interruptibility); "no clock" is a supported degradation rather than a second code path (`row_actions.luau:1042-1046`, `selection_indicator.luau:404-408`, `virtual_reorder.luau:243`).
**(b) Extract** `src/motion/lazy_spring.luau`: `new(scope, core, { clock, initial, class, write }) -> { retarget(px), snap(px), settleThen(fn) }`. Confidence medium because the four differ in disposal shape (per-key vs single) — the keyed variant should be proven first.

### REUSE-19 — Axis transposition helper families ×3 · Medium / high
`fill()` at `src/controls/virtual_list.luau:794-797` ↔ `virtual_grid.luau:313-316`; `mainOf(point)` `:800-802` ↔ `:317-320`; `vec(value)` `:805-807` ↔ `:322-325`; `widthOf`/`heightOf` `:811-816` ↔ `:327-332`. Both close over a locally derived `isX` (`virtual_list.luau:505`, `virtual_grid.luau:286`); `virtual_reorder.luau:74` takes `isX` as a dep and adds a third family at `:366-385` (`autoscrollPoint`/`autoscrollRect`/`autoscrollBand`). Both `fill()` bodies carry the same multi-line "a fresh dim per node, never one shared table" argument, written twice (`virtual_list.luau:788-793`, `virtual_grid.luau:310-312`).
**(b) Extract** `src/controls/axis_math.luau`: `new(axis) -> { isX, fill, mainOf, vec, widthOf, heightOf, point, rect, band }`.

### REUSE-20 — Key↔path↔item addressing ×5; Table's is O(N) · Medium / high
`keyOfHit(path)`: `virtual_grid.luau:853-855` ↔ `virtual_list.luau:2370-2372`. `hitPathOf(key)`: `virtual_grid.luau:857-860` ↔ `virtual_list.luau:977-980`. `itemForKey(key)`: `virtual_grid.luau:862-865`, `virtual_reorder.luau:168-174`, `table.luau:575-582`, `virtual_list.luau:1311`. Linear index scans: `tab_view.luau:549-556`, `selection_indicator.luau:497-504`.
**Real divergence:** `src/controls/table.luau:575-582` is an O(N) linear scan over `spec.rows:get()` where every sibling is an O(1) `indexByKey` lookup, and it is called on every `api.select` and every capability gate — a full data walk per selection on a 10,000-row table.
**(b) Extract** `src/controls/keyed_index.luau`: `new(core, scope, rows, keyFn) -> { indexByKey, indexOf(key), itemFor(key) }`. Table gains the O(1) path as a side effect.

### REUSE-21 — `level_picker` re-authors `value_model`'s arithmetic · Medium / high
`src/controls/slider.luau:200-213` and `src/controls/stepper.luau:106-119` are byte-identical `apply` bodies over `model.quantize`. `src/controls/level_picker.luau:329-345` is the same body with `math.clamp(math.floor(next_ + 0.5), minValue, count)` inline instead — which is exactly what `src/controls/value_model.luau:108-115` (`quantize`) generalises. Likewise pointer→value: `slider.luau:215-221` (`setFromX` via `model.fromFraction`) vs `level_picker.luau:347-356` (`setFromPoint` via `math.ceil`). `level_picker` is the body of both `newLevelPicker` and `newRating`, so this covers two public controls.
**(a) Reuse** `value_model` (already a published export at `src/init.luau:207`): have `level_picker.compose` build `value_model.new({ min = minValue, max = count, step = 1 })` and route through `quantize`/`fromFraction`. The three `apply` wrappers stay separate — they differ in `readOnly` and diagnostics.
**Not a finding, recorded as the model:** `src/controls/rating.luau:145-197` is a genuine preset over `level_picker` and re-implements nothing; `contract.enabledNow` is correctly shared by five controls.

### REUSE-22 — Row-keys action context ×2 · Medium / high
`src/controls/row_actions.luau:2221-2262` (`ensureKeysContext`) + `:2335-2345` (`syncKeysEnabled`) ↔ `src/controls/virtual_list.luau:1831-1866` + `:1868-1879`. Same six steps in the same order; `virtual_list.luau:1873` says "the same deferral `row_actions`' own `syncKeysEnabled` makes (Task 11b)". Only the priority and the dispatch target vary.
**(b) Extract** `row_actions.newRowKeysContext(actionSystem, scope, { name, priority, onDelete, onMenu, guard? })`.

### REUSE-23 — Reorder slot→index off-by-one ×2, `insertSlotAt` ×2 · Medium / high
`src/controls/virtual_reorder.luau:217` and `src/controls/virtual_list.luau:2431` both compute `slot - (if from <= slot then 1 else 0) + 1`, ~1,200 lines apart in files that already share a dep. `insertSlotAt` wrappers around `ix.slotAt`/`ix.boundaryOffset`: `virtual_reorder.luau:136-142` ↔ `table.luau:1361-1365`, with the index's two rules restated in both (`table.luau:1345-1360`, `virtual_reorder.luau:129-142`).
**(b) Extract** `dropIndexFor(slot, from?)` and `insertionAt(ix, offset)` onto `src/virtual_extents.luau`. An off-by-one in a reorder is directly player-visible.

### REUSE-24 — `bindNativeScroll` wrapper + latch ×3 · Low / high
`src/controls/virtual_grid.luau:1008-1016` ↔ `virtual_list.luau:2944-2952` ↔ `table.luau:3824-3830` (identical assert + `mirror.bind`), and the three `install` closures (`virtual_grid.luau:990-1006`, `virtual_list.luau:2917-2942`, `table.luau:3794-3822`) each re-author the same bound-controller latch. `src/controls/native_scroll_binding.luau:15-25` already argues against three copies of the arbitration — this is the residue it left behind.
**(b)** `nativeScrollBinding.new` returns `bindPublic(controller, path?, mountedPath, controlName)` plus an optional `latch` pair; the varying extras stay in each `install`.

### REUSE-25 — Reactive-enum "validate now, tolerate later" ×3 · Low / high
`src/controls/picker.luau:327-338` (`axisNow`) · `picker.luau:339-350` (`sizingNow`) · `src/controls/selection_indicator.luau:335-348` (`axisNow`). Both files document the identical policy and each cites the other as precedent (`picker.luau:322-324`, `selection_indicator.luau:330-333`).
**(b)** `reactiveEnum(constructor, id, field, source, allowed, default)` on the `reactive_value` module from REUSE-2.

### REUSE-26 — Per-row selected memo: two lifecycle strategies · Low / medium
`src/controls/table.luau:1214-1229` uses a module-level `selectedMemoByKey` cache with a `scope:child(...)` per row, requiring the prune observer at `:1236-1260`. `src/controls/virtual_list.luau:2969-2973` owns it on the row's own scope, with the comment "no per-key cache to prune". The second is strictly simpler and cannot leak.
**(a) Adopt** `virtual_list`'s shape in Table — pass the row's item scope in and delete the cache plus the prune half that exists only for it. Table's `grabbedKey` fold-in is the one genuine difference and survives.

### REUSE-27 — Two `resolvePresentation` with different semantics · Low / high — **keep separate**
`src/controls/menu_recipe.luau:89-101` (`menu | inline | sheet`, from count + size class + live touch) and `src/controls/picker.luau:246-256` (`segmented | inline`, from count + size class + longest label). Same name, same signature shape, different vocabularies, different thresholds (`compact` + `>6` vs `compact` + `>3 or label > 10`).
**(c) Keep separate — merged semantics would differ:** they answer different questions about different controls, and a merged function would need both output vocabularies and both input sets. Recorded because the shared *name* across two modules is a real confusion risk; renaming one (e.g. `picker.resolveLayout`) is the cheap fix.

## C. `src/render` and `src/layout`

### REUSE-28 — Seven paint walks, seven private caches, one hand-maintained eviction list · High / high
**Responsibility:** walk the live tree, resolve one value per node from this solve, write it only if it differs from last time.
**The seven, all inside `solveAndApply`'s commit span (`src/render/renderer.luau:1917`):** `applyTextScale` `:1603-1644` (caches `lastTextSize:1586`, `lastTextFont:1602`) · `applyPadding` `:1670-1701` (`lastPadding:1669`) · `applyTextVerdicts` `:1772-1817` (`lastCompact:1721`, `lastWrapped:1734`) · `pushVisible` `:2107-2129` (`lastVisible:842`) · `pushHitRects` `:2148-2181` (`lastHitRects:831`) · the `rect_pass` walk `src/render/rect_pass.luau:93-103` (`lastRects:363`, `lastBarInsets:369`) · `pushRegions` `:2212-2301` (`lastScrollRegions:370`). Plus `walkZ` at `:2526`.
**Self-declared:** `renderer.luau:1646` — "PAINT SEAM FOR PADDING, exactly the shape applyTextScale has"; `:1714` — "the same shape applyTextScale and applyPadding have"; `:2144-2147` — "exactly as `pushVisible` carries it, and a hidden node takes the SAME diff path".
**The failure mode is documented and has shipped:** all 16 per-path caches are cleared by hand in one block, `renderer.luau:2658-2704`, which carries in-source records of three separate defects caused by a missing entry — verifier V10 (a re-created sub-floor control silently lost its hit expander), the hidden-candidate repaint, and the 2026-08-04 live find (*"RascalRally's watch-cycle buttons painted 'Previous racer' ellipsized after a pose toggle at EVERY preference … One mount looked right — which is why the device pass that shipped the feature saw chevrons — and every remount after it did not"*). `docs/lessons/a-per-path-cache-outlives-the-node-it-remembers.md` states the rule: *"Any `last*[path]` minimal-write cache must die in `structuralSync`'s removal block."* It is enforced by review only.
**Perf:** this is the measured hot path, and it argues **for** consolidation. `rect_pass.luau:15-19` — *"MEASURED IN STUDIO, 2026-08-17 … 240 engine Position changes across 120 descendants, two each"*; `:38-41` — *"DOCUMENT ORDER IS ANCESTORS-FIRST BY CONSTRUCTION, so this needs no sort … Do not put the hash back."* One document-order walk serving several seams costs less than seven.
**(b) Extract** `src/render/paint_pass.luau`: `newSeam(name, ctx) -> { visit(node, handle, prev) -> next?, clear(path) }` and `run(rootNode, seams)` performing **one** document-order walk, with the cache owned by the seam record so `paint_pass.forget(path)` replaces the 16-line hand list. Land it incrementally: the three `apply*` seams first (identical shape, no inherited state); `pushVisible`/`pushHitRects` thread `hidden` down and `rect_pass`'s document order is load-bearing, so those follow.

### REUSE-29 — Hidden-roots filter ×3 verbatim, plus an import shadowed by its own copy · High / high
**Owner, already exported:** `src/present/focus_map.luau:86-95` (`isHiddenPath(path, hidden)`), exported at `:831` and **already imported** by `src/present/presenter.luau:272`.
**Copies:** `src/present/presenter.luau:939-951` — which shadows the import it made 667 lines earlier · `src/present/help_plate.luau:135-147` (byte-identical, named `isHidden`) · `src/present/text_reveal.luau:133-146` (byte-identical). A different-source variant: `src/layout/text_audit.luau:113-131` derives roots from `entry.hidden` in the solve output.
**All three copies convert the `{[string]: boolean}` set returned by `controller.hiddenRoots()` (`renderer.luau:3435`) into an array for no reason; `focusMap.isHiddenPath` consumes the set directly.**
**(a) Reuse** `focusMap.isHiddenPath(path, ctrl.hiddenRoots())` at all three, and delete the shadowing local in `presenter`. `text_audit`'s root *derivation* stays (different input); its scan folds into the `src/paths.luau` of REUSE-3.

### REUSE-30 — Effective text size/face resolver ×5 across measure and paint · Medium / high
`src/themes/snapshot.luau:1119-1135` (`effectiveTypeRole`) · `snapshot.luau:1139-1146` (`intrinsicTextSize`, a strict specialization of the same lookup) · `src/render/layout_node.luau:208-230` (`textOf`, MEASURE seam; callers pass `INTRINSIC_TEXT_ROLE.*` at `:461,472,553,571`, redoing the class→role lookup) · `src/render/renderer.luau:1608-1612` (PAINT seam, the same three-branch rule written independently) · `src/layout/solver.luau:467-480` (`textTypography`, a third spelling of the role ladder).
**Documented drift history:** `layout_node.luau:210-217` — *"This used to hand back `nil` for an unauthored size, and the solver then keyed measurement on `body`'s descriptor — while the class's INTRINSIC role is `control` for a Button … the paint seam would have disagreed with it."* `renderer.luau:1596` claims both seams resolve through `effectiveTypeRole` — true for the *face*, not for the *size* branch, which is still two hand-written copies.
**Perf constraint to respect:** `solver.luau:465-466` — "Module-level, not a closure: this is on the per-text-node measure path, where a per-call allocation is a bench regression this file has already paid for once." That constrains allocation, not location.
**(b) Extract** `snapshot.effectiveTypography(snap, class, textSize) -> { size, role, fontKey, lineHeight, authored }` returning a module-level frozen record where possible; fold `intrinsicTextSize` into it. `renderer` keeps its `* scale`, `layout_node` keeps `text_metrics.reservedSize`.

### REUSE-31 — Aspect-ratio derivation ×5; grid handles one axis only · Medium / medium
`src/layout/solver.luau:1997` (w from h) · `:2004` (h from w) · `:3407-3419` (four branches for the fill-sibling repair) · `src/layout/grid.luau:597-599` (**hDim only**) · `grid.luau:720-722` (**hDim only**, with an extra `math.min(availH, …)` clamp) · `grid.luau:334-336` (flow-lane variant, both directions via `isCol`).
**Verified asymmetry:** the solver branches on both `wDim.type == "aspect"` and `hDim.type == "aspect"`; the grid paths branch only on `hDim`. **Confidence medium** on user impact: the grid calls `deps.measure`, which routes through the solver, so the solver's own aspect branch may already have applied the width case before the grid's re-derivation — the asymmetry is certain, the reachability of a visible wrong result is not. Worth a probe before it is called a bug.
**(b) Extract** `aspectOther(dimType, ratio, known) -> number` into `solver`'s module scope / `grid.Deps`; using it closes the asymmetry by construction.

### REUSE-32 — Alignment factor/offset ×4 with two rounding rules · Medium / high
`src/layout/solver.luau:2077-2083` (`alignOffset`; `center` → `math.floor((avail - size) / 2)`, `end` → `avail - size`, **no rounding**) · `solver.luau:2033-2039` (`ANCHOR_FACTORS`) with placement at `:2936-2937` (**round-half-up**) · `src/layout/composition.luau:1891-1892` (inline factor then **round-half-up**) · `composition.luau:934-943` (`placeWeights`, the same vocabulary as a weight pair) · `solver.luau:2147-2162` (`distributionOf`, same enum extended, `center` → `slack / 2`, **no rounding**).
**Consequence:** a `center` in a Composition lane and a `center` in a ZStack round differently.
**Already correct and the model to follow:** `src/layout/grid.luau:93` takes `alignOffset` as an explicit injected seam.
**(b) Extract** `src/layout/align.luau`: `factor(name?) -> number`, `offset(name?, avail, size) -> number` with one rounding rule; thread it the way `grid.AlignOffset` already is. `distributionOf` keeps its own function (it answers leading-pad *and* inter-gap) but reads `align.factor`.

### REUSE-33 — Weighted slack distribution: one integral rule, three float copies · Medium / medium
`src/layout/solver.luau:3291-3308` implements integer largest-remainder (floor each exact share, sort by remainder, hand out the leftover) — deterministic, sums exactly, integral. `src/layout/composition.luau:1849-1850` (spacers), `:1856-1857` (groups) and `:1880-1882` (regions) each compute `slack * (weight / total)` in floats; `composition.luau:2173-2183` (`roundRect`) then rounds at dump time, so the resolution carries non-integral rects while the dump reports integral ones and two participants can each take `x.5`.
**(b) Extract** `src/layout/distribute.luau`: `byWeight(slack, weights) -> { number }` implementing the solver's rule once; composition's three loops call it (spacers pass a leading weight rather than being special-cased). **Confidence medium** — nothing in-source says composition's fractional rects are deliberate, but nothing says they are not either.

### REUSE-34 — Prop→write-channel declared twice, plus a third class-scoping table · Medium / high
`src/render/authority.luau:23-186` (`MANIFEST`, class → prop → channel, asserted at every write by `authority.assertWrite:198`) and `src/render/renderer.luau` `BINDING_PROPS`/`STYLE_PROPS` (re-exported `:176-177`), `STYLE_PROP_ORDER:151-163`, `DIRECT_PROPS:209-219`, `BINDING_PROP_CLASSES:186-188`. Every emitted prop must appear in both with agreeing channels; nothing checks that. `renderer.applyProp` (`:920`) picks the channel from its own table and then asks `authority.assertWrite` to confirm it — a self-check between two hand-maintained lists.
**The drift already shipped:** `renderer.luau:180-185` — *"`UI.Divider{ thickness = … }` errored at first render for EVERY value, and always had"* — and the fix was `BINDING_PROP_CLASSES`, a *third* table restating what `authority.MANIFEST` already says at `authority.luau:158` (`Path = { … thickness = "binding" … }`, with no `thickness` under `Divider`).
**(b) Derive** the renderer's channel tables from `authority.MANIFEST` at load: `authority.propsWithAuthority("binding"|"style") -> { [class]: { [prop]: true } }`. That deletes `BINDING_PROP_CLASSES`. `STYLE_PROP_ORDER` stays hand-written (paint order is a real ordered fact, already asserted to cover the set at `:164-175`); `DIRECT_PROPS` stays as the non-channel-seam documentation whose value is the conformance test at `tests/render_target_contract.spec.luau`.

### REUSE-35 — Stage/Foreign host seam: three matched twins · Low / high
`src/render/foreign_content.luau:52-55` ↔ `src/render/stage_content.luau:142-145` (`disposedError`, identical bodies **and identical two-line comments**) · `src/render/renderer.luau:3943-3952` (`controller.stageHost`) ↔ `:3961-3970` (`controller.foreignHost`), byte-identical but for the adapter key · `src/client/screen_target.luau:1597-1614` ↔ `:1700-1715` (the same five-step lazy-API preamble).
**(b) Extract** `src/render/host_seam.luau`: `disposedError(seamName, className, path)` and `lazyApi(handle, class, cacheKey, live, build)`.

### REUSE-36 — `screenRectOf` / `paintedRectIn` share eight lines of shift math · Low / high
`src/render/renderer.luau:509-523` and `:525-538`. Lines 514-522 and 530-537 are identical (`scrollShift`, `presentationShift`, an all-zero identity short-circuit, else rebuild); only the base-rect source differs. `screenRectOf` is public (`controller.screenRectOf`, `:3393`) and consumed by `present/anchored.luau:213`, `presenter.luau:1029,1068`, `text_reveal.luau:206,303`.
**(b)** one local `shiftToWindow(rect)`; both become a source lookup plus that call.

### REUSE-37 — `drainDeparted` / `drainAppeared` identical · Low / high
`src/render/renderer.luau:2561-2571` and `:2572-2582` — take-batch-clear-then-call, differing only in which queue (`departedQueue:829` / `appearQueue:827`). The re-entrancy note at `:2535-2540` applies to both and is written once.
**(b)** one `drain(getQueue, setQueue)` returning the emptied batch.

### REUSE-38 — `adaptive.sizeClass` / `heightClass`: one rule, two bodies · Low / medium
`src/layout/adaptive.luau:80-92` and `:96-110`: same breakpoints (`HEIGHT_BREAKPOINTS = BREAKPOINTS`, `:59`), same `safeWidth` normalization, same ten-foot cap at the top class, same three-branch structure; only the three output names differ.
**(b)** `local function classify(v, names, opts)` with both public functions as three-line wrappers. Both names are documented API and stay. The ten-foot cap is the rule that must not drift.

### REUSE-39 — `math.floor(v + 0.5)` ×61, one named helper · Low / medium
`composition.luau` 22 · `solver.luau` 17 · `grid.luau` 3 · `surface_overlap.luau` 2, plus ~17 elsewhere in `src/`. Only `composition.luau:2173-2183` (`roundRect`) names it, and REUSE-32 shows two *different* rounding rules coexisting for alignment.
**(b)** fold into REUSE-4's `src/layout/rect.luau` as `rect.round(r)` plus a free `roundPx(v)`, rebound to a module-level local in `solver` and `composition` so the measured no-per-call-allocation constraint (`solver.luau:2064`) is preserved.

### REUSE-40 — Five diagnostic-record shapes for one concept · Low / medium — **keep separate**
`src/layout/text_audit.luau:50-57` (`{ check, node, other?, contract, fix, detail? }` + `sortFindings:70` + `finish:82`) · `src/layout/placement_audit.luau:303-306` (`{ node, issue, filedBy }`, no sort, no freeze, returns `nil` not `{}` — deliberate, `:299-301`) · `src/render/style_lint.luau:34` (`{ rule, path, detail }`) · `src/render/surface_overlap.luau:328` (`{ node, issue }`) · `src/layout/solver.luau:3287` (`{ node, issue }`).
**(c) Keep separate — merged semantics would differ:** `placement_audit`'s `filedBy` exists because a parent files a finding naming a child (`placement_audit.luau:335-340`), and its *absence* is load-bearing for the incremental-replay gate at `solver.luau:2369`; a merged record would carry a field meaningless to the other four. `style_lint` has one consumer (`tests/styling.spec.luau:179`) and no production caller, so unifying it buys nothing at the point of use. **Do** align the field *names* (`node` everywhere) — that is a rename, not a merge.

### REUSE-41 — "First candidate that fits, else the declared fallback" ×2 · Low / high — **keep separate**
`src/layout/solver.luau:751-770` (`chosenCandidate`, ViewThatFits) and `src/layout/composition.luau:2061-2095` (arrangements).
**(c) Keep separate — more branching than it removes:** a merged helper needs a fit predicate, a rejection reporter, an eligibility gate and a "re-run the fallback with `forced = true`" callback, to eliminate roughly six shared lines. The shared *rule* ("the last candidate is the declared fallback and always resolves") is already stated in both headers (`solver.luau:758`, `composition.luau:2063-2067`); keep the cross-reference, not the loop.

## D. `src/present`, `src/motion`, `src/focus`, `src/input`

### REUSE-42 — Hand-mounted presenter-private chrome overlay ×7 · High / high
**Responsibility:** mount a synthesized Screen outside the presented stack — `core:scope` → `mountLib.mount(scope:child("mount"))` → `renderer.attach(rootPolicy=…)` → `initialRender()` → `setDisplayOrder(base ± n)` → record `{scope, controller, root}`; teardown `controller.dispose(); scope:dispose()`.
| what | mount | display order | teardown |
|---|---|---|---|
| modal/engaged scrim | `src/present/catchers.luau:201-224` | `owner.displayOrder - 50` | `catchers.luau:102-108` |
| popup catcher | `src/present/catchers.luau:346-417` | `min(stack) - 50` | `catchers.luau:275-281` |
| disclosure plate | `src/present/presenter.luau:1065-1135` | `owner.displayOrder + 25` | `presenter.luau:997-1005` |
| drag proxy | `src/present/presenter.luau:1494-1506` | `SURFACE_LAYER.dragProxy` | `presenter.luau:1449-1452` |
| toast layer | `src/present/presenter.luau:3826-3884` | `SURFACE_LAYER.toast` | `presenter.luau:3776-3785` |
| reveal strip | `src/present/text_reveal.luau:223-293` | `owner.displayOrder + 24` | `text_reveal.luau:170-182` |
| anchored chrome mode | `src/present/anchored.luau:565-581` | `base + 25` | `anchored.luau:640-651` |
**Self-declared and already under-counted:** `src/present/anchored.luau:555-556` — *"this is the THIRD copy of that, written once"*. There are seven.
**Drift already visible:** `rootPolicy` is `"edgeToEdge"` at six sites (`catchers.luau:207`, `:362`, `presenter.luau:1115`, `:1502`, `text_reveal.luau:270`, `anchored.luau:566`) and `"coreSafeContent"` at the toast layer (`presenter.luau:3876`) — plausibly deliberate but unstated at that site, and `presenter.luau:1530` carries a comment about a `rootPolicy` typo that "silently kept the default". The catcher's display-order rule was fixed live twice (`catchers.luau:369-393`: `owner.displayOrder - 50` → `min(stack) - 50`, after coach marks stopped appearing on device) and no sibling learned it.
**(b) Extract** `src/present/chrome_layer.luau`: `mount(ctx, { id, blueprint, rootPolicy?, displayOrder, onNodeTap?, transitions?, feedback? }) -> { scope, controller, root, dispose }`. Seven call sites keep their blueprint and z-policy; the mount recipe, the `setDisplayOrder ~= nil` guard and the two-line teardown live once.

### REUSE-43 — Document-order first-visible-match walker ×3 · High / high
**Responsibility:** walk a mounted subtree in document order, prune `controller.hiddenRoots()` subtrees, return `(path, text)` for the first node matching a predicate.
**Sites:** `src/present/presenter.luau:922-980` (`disclosureTargetIn`) · `src/present/help_plate.luau:120-167` (`helpTargetIn`) · `src/present/text_reveal.luau:128-167` (`revealTargetIn`). Acknowledged in-tree: `text_reveal.luau:127` says "the same walk shape as disclosureTargetIn"; `help_plate.luau:115-119` says "the same shape (and the same hidden-candidate rule) as the disclosure walker".
**Lifecycle / perf:** stateless; `revealTargetIn` runs on a 0.5 s rescan (`text_reveal.luau:111`), the others on every engagement. `text_reveal.luau:86-89` states the bound — "an idle presenter pays a timer-gated rescan, never a per-frame tree walk". The F-1 hidden-candidate rule was a measured live defect (`presenter.luau:934-938`, `text_reveal.luau:374-379`) and had to be fixed three times.
**(b) Extract** onto `src/present/focus_map.luau` (already the shared vocabulary module for presenter/modal_zones/help_plate/text_reveal, already exporting `nodeAt`/`isPathPrefix`/`FOCUSABLE`): `firstVisibleMatch(rootNode, hiddenRoots?, predicate) -> (string?, string?)`. The three predicates stay at their call sites.

### REUSE-44 — Pointer-dwell engagement state machine ×2 · High / high
**Responsibility:** hover a target for 0.45 s, then **re-ask** and present a plate; moving to a different target retires the old answer; focus presents immediately; a live plate for this exact target is left alone.
**Disclosure:** constant `presenter.luau:835` · state `:839` · hover handler `:1259-1286` · tick countdown + re-ask `:3971-3990` · `plateShows` `:1144-1146` · revalidate `:1341-1357`.
**Help:** constant `help_plate.luau:74` · state `:110` · hover handler `:263-296` · tick + re-ask `:332-348` · `shows` `:256-258` · revalidate `:353-365`.
`help_plate.luau:70-73` states it: *"THE SAME 0.45 s DELIBERATION the disclosure plate's pointer dwell uses, and for the same reason"*. The two hover handlers match statement-for-statement, as do the two tick bodies — including the "re-ask at expiry, never present the hover-time snapshot" rule (architecture-review F-2), written twice.
**Both are driven from one seam** (`presenter.luau:1297-1300`) and one tick (`:3974`, `:3993`), and both guard so an idle presentation does zero per-frame work (`:3971-3973`, `help_plate.luau:330-331`) — a bound any extraction must keep.
**(b) Extract** `src/present/dwell.luau`: `new({ delayS, resolve, present, retire, shows }) -> { hover(owner, path), focus(owner, path), tick(dt), cancel() }`. Mechanical once REUSE-43 lands — the dwell's `resolve` is that walker.

### REUSE-45 — Listener list + unsubscribe ×6, two error policies · Medium / high
| site | storage | fan-out | quarantined |
|---|---|---|---|
| `src/present/feedback.luau:264-287` | boxes | `:306-318` `table.clone` | yes (`pcall`, `lastEmitError`) |
| `src/motion/motion.luau:210, 370-382` | boxes | `:230-241` `table.clone` | yes (`pcall` → `noteError`) |
| `src/present/presenter.luau:4029-4037` | plain fns | `:4019-4023` `table.clone` | yes (RR-12) |
| `src/present/presenter.luau:3398-3407` | plain fns | `:3390-3393` `table.clone` | **no** |
| `src/input/drag_registry.luau:252, 1048-1056` | plain fns | `:269-271` `table.clone` | **no** |
| `src/input/actions.luau:38-56` | plain fns | `:69-73` `table.clone` | **no** |
Both box-based copies carry an identical comment explaining the box idiom (`feedback.luau:265-266`, `motion.luau:209`). All six snapshot, so unsubscribe-during-fire is safe everywhere; three of six let a throwing subscriber escape into the emitter's causal frame, which the other three treat as a named defect class.
**Callers include the game:** `presenter.onTick` → `FacetSponsor/OmenState.luau:176`; `handle.onFeedback` (`presenter.luau:2646`) → `FacetSponsor/init.luau:2251`.
**(b) Extract** `src/core/listeners.luau` (must sit below `present`, `motion`, `input`): `new({ onError? }) -> { subscribe(fn) -> unsub, emit(...), count(), clear() }`. Sites that genuinely want a throw to escape pass no `onError` — an explicit choice instead of six accidental ones.

### REUSE-46 — Duration-ramp driver ×3 inside one module, already asymmetric · Medium / high
`src/motion/motion.luau:614-661` (`newGlide`) · `:734-794` (`newTween`) · `:816-845` (`newTimer`). Glide and tween are line-for-line identical in `advance`/`place`/`value`/`terminus`/`settled`/`aim`; the only differences are the fraction routed through `progress()` (`:727-732`) and a central-differenced velocity (`:778-793`) vs a constant one (`:655-660`). The header says so: `motion.luau:688-690` — *"WHY IT IS NOT A GLIDE OR A TIMER. Both already own duration; both are strictly LINEAR. A tween is the same ramp with the curve made authorable."*
**Drift already present:** `glide.advance` early-returns at `elapsed >= duration` (`:616-619`); `timer.advance` does not (`:817`), so a settled timer keeps re-clamping. `glide.aim` guards `duration <= 0` (`:648-650`); `timer` has no `aim`.
**Callers:** `src/motion/clock.luau:292-316`; game-side `clock:timer` at `FacetSponsor/PlayFlow.luau:439`, `StoryFlow.luau:586`, `OmenState.luau:279`, `RacerList.luau:390`, `clock:glide` at `MapCanvas.luau:189-190`.
**Perf:** `advance`/`value` run per frame per value inside `clock.step`'s phase loops (`clock.luau:206-241`); a shared factory closing over an easing function adds one indirection. The recorded measurement is that the *evaluator* dominates (`TweenService:GetValue` 6.3× slower than the Lua twin), not the ramp scaffold.
**(b) Extract** a private `rampDriver(duration, shape?, opts)` inside the same module. No public API change; the two `advance` asymmetries resolve.

### REUSE-47 — `motion/classes` and `motion/curves` are the same registry twice · Medium / high
`src/motion/classes.luau:97-195` ↔ `src/motion/curves.luau:247-367`: `names()`, `isRegistered()`, `nameList()`, `suggestion()`, `register*()` (differing only in which fields are range-checked and the message text), `resolve()` (both refusing an inline table), `reset()`. `curves.luau:42-48` cross-references: *"A CURVE IS A NAME, never an inline spec — the same refusal `classes.luau` makes, for the same reason."* The duplication is visible in the public surface: `src/init.luau:269-273` and `:286-290` publish five mirrored verbs each.
**(b) Extract** `src/motion/named_registry.luau`: `new({ label, validate, builtIns? }) -> { names, isRegistered, register, resolve, reset }`; `classes` and `curves` keep only their `validate` and their prose. The Levenshtein half is REUSE-5 and should land first regardless — it is unambiguous and dependency-free.

### REUSE-48 — Blueprint meta-channel attach ×4, read ×2 · Medium / high
**Responsibility:** clone `bp.meta`, set one reserved key, rebuild-and-freeze the blueprint (`class/id/props/children/meta`).
**Identical bodies:** `src/input/contribution.luau:264-272` · `src/input/drag_contract.luau:232-240` · `src/tokens/chrome_slots.luau:717-731` · `src/blueprint.luau:1465-1492`. Readers: `contribution.luau:276-289` (`read`) and `drag_contract.luau:246-256` (`readMeta`, whose comment at `:243` says "Type-guarded like `contribution.read`").
**Invariant at risk:** the rebuild enumerates the blueprint's fields by hand — a fifth field added later must be added in four places or the modifier silently drops it.
**(b) Extract** `blueprint.withMeta(bp, key, value)` and `blueprint.readMeta(node, key)` onto `src/blueprint.luau` (the module that owns the blueprint shape). Each of the four keeps its own validation prologue (`drag_contract.luau:222-231`, `chrome_slots.luau:707-716`, `contribution.luau:257-263`) and delegates the rebuild.

### REUSE-49 — "Is this node focusable" ×7, no two agree on the guards · Medium / medium
**The set is defined twice:** `src/present/focus_map.luau:23` (`FOCUSABLE`, exported `:826`) and `src/blueprint.luau:844` (`CONTENT_FOCUSABLE`), whose own comment at `:838` says "focus_map.FOCUSABLE plus the Grip's opt-in… one definition" — while being a second literal.
| site | Grip opt-in | `enabled == false` | `retiring` |
|---|---|---|---|
| `src/present/focus_map.luau:50-56` | yes | yes | yes |
| `src/present/focus_map.luau:438-441` | excluded | no | yes |
| `src/present/focus_map.luau:723` | no | no | yes |
| `src/present/focus_map.luau:807` | no | no | yes |
| `src/present/modal_zones.luau:78` | no | no | no |
| `src/present/help_plate.luau:385` | no | no | no |
| `src/blueprint.luau:846-851` | yes | no | n/a |
**Concrete consequence:** `help_plate.declarations()` reports `focus = true` for a **disabled** Button, so `text_audit.helpRoutes` — described at `help_plate.luau:29-31` as the mechanical proof that "help is never the only route" — can pass on a route the focus walk will never reach.
**(b) Extract** `focus_map.isFocusableNode(node, { grips? })` and, if the layering allows, a leaf `src/focus_classes.luau` holding the class set so `blueprint` can share the literal without depending on `present/`. Minimum honest fallback: a test pinning `blueprint.CONTENT_FOCUSABLE == focus_map.FOCUSABLE`.

### REUSE-50 — `easeOutQuad` hand-rolled beside the curve evaluator · Low / medium — **keep separate**
`src/input/autoscroll.luau:114-118` implements `1 - (1-t)²`, which is `curves.evaluate(t, "quad", "out")` (`src/motion/curves.luau:131-133` + `:193`). It runs per frame per autoscrolling host (`autoscroll.luau:188`, `:202`).
**(c) Keep separate — dependency reversal plus a measured shape:** `autoscroll` is deliberately dependency-free ("A PURE model… never reads a clock", `autoscroll.luau:2-6`) and `motion/curves` is the registry module with a table dispatch, a direction branch and a `-0` normalisation where this is two multiplies. The honest fix is a comment at `autoscroll.luau:114` naming the equivalence so a retune finds both.

### REUSE-51 — Clock-participant done-latch scaffold ×2 · Low / high — **keep separate**
`src/motion/chase.luau:65-86`, `:126-137`, `:146-161` ↔ `src/motion/timeline.luau:87-97`, `:149-181`, `:199-209`: a one-way `done` flag, an idempotent detach, and "under reduced motion, resolve now and never attach". `src/motion/motion.luau:243-248` is a third, smaller instance of the detach half.
**(c) Keep separate — merged semantics would differ:** `chase` fires an arrival with a `how` reason and distinguishes cancel-without-event; `timeline` runs terminals in two different orders (`interrupt` vs `skip`) and reports one of four reasons. A shared base is ~10 lines of scaffold wrapped in more branching than it removes, and both are per-frame `pre`/`post` participants. The reduced-motion early-out convention deserves a cross-reference comment, not an extraction.

## E. `src/core`, `src/async`, `src/themes`, `src/tokens`, `src/env`, `src/client`

### REUSE-52 — Colour-role resolution ×2, already divergent, with a live game workaround · High / high
**Responsibility:** resolve a colour role name against a palette (`colors` then `extra`).
`src/tokens/styling.luau:195` (`resolveColor(value, style, what)`) — hex → `style.colors[role]` → `style.extra[role]` → assert. **No derivation**, and `style` defaults to `default_style` (`:70,:114,:250,:429`), i.e. Studio Neutral **dark**, not the installed theme.
`src/tokens/sheet_model.luau:1448` (`paletteColor(theme, role)`) — the same two steps **plus** `effectiveExtra` derivation (`:1367`), a `"white"` case and a `danger` fallback, reading the **active theme**.
Both headers claim "the same two-step order". They are not the same: a package theme with partial `extra` resolves under `tint` and asserts under `UI.stroke`/`UI.gradient`, and an omitted `style` argument silently resolves against the dark neutral under any theme.
**Live consumer symptom:** `games/RascalRally/code/src/client/FacetSponsor/HandDock.luau:206-207` — *"`UI.strokeData` defaults to the theme's hairline OPACITY (0.92) — the bubble's shield ring was drawing at 8 % and reading as nothing."* `FacetSponsor/StartCountdown.luau:179-191` sidesteps it by passing literals.
**Callers:** `styling.resolveColor` ← `normalizeGradient` (`styling.luau:255`), `normalizeStroke` (`:486`) ← `src/blueprint.luau:1288,1346,1375,1391,1395,1531,1534,1542`. `paletteColor` ← `sheet_model.tintColor` (`:1498-1499`), `src/client/screen_paint.luau:300`.
**Constraint:** `sheet_model` requires `styling` (`:29`), so `styling` may not require back — Lune hangs on cycles, and `tokens.dangerPair` (`src/tokens/tokens.luau:62`) was moved down for exactly this reason.
**(b) Extract** `src/tokens/palette.luau` **below** `styling`: `effectiveExtra(theme) -> extra`, `roleColor(theme, role) -> Rgb?`. Both resolvers call it, and the default-style fallback becomes a deliberate decision rather than a default argument.

### REUSE-53 — Slot flat-paint tables hand-mirrored across the two paint paths · High / high
`src/tokens/sheet_model.luau:615-643` (`SLOT_FILL_TOKEN`, 20 slots → `"$Token"`), `:645` (`SLOT_ROUND`), `:647-654` (`slotRadius`) ↔ `src/client/screen_chrome.luau:126-147` (`chromeFillOf`, the same 20 slots → `Color3`), `:150-151` (`SLOT_ROUND_FALLBACK` — verified byte-identical to `SLOT_ROUND`). Each file's comment points at the other. `screen_chrome:177` re-derives the radius decision but omits `slotRadius`'s `panel → radii.panel` and `divider/scrollbar → 0` cases — currently unreachable because `hasOwnPaint` gates it to five slots, so a latent trap rather than a live bug.
**Callers:** `chromeFillOf` at `screen_chrome.luau:175, 231, 1534, 1849` (asset-failure fallbacks reach the whole map); `SLOT_FILL_TOKEN` at `sheet_model.luau:676`.
**(b) Move both** to `src/tokens/chrome_slots.luau` — already required by *both* (`sheet_model:25`, `screen_chrome:27`) and depending only on `chrome_props`: `SLOT_FILL_ROLE`, `SLOT_ROUND`, `slotRadius(metrics, slot)`. Each path maps the role its own way.

### REUSE-54 — `UIShadow` property write ×3 · High / high
`src/client/screen_paint.luau:522-530` (`applyShadow`) · `src/client/screen_chrome.luau:1218-1226` (`syncChromeShadow`) · `src/client/screen_target.luau:2822-2829` (focus glow; overrides `Color`, forces `Enabled = true`). Same seven properties, same `UDim`/`UDim2` unpacking, same normalized shape from `styling.normalizeShadow` (produced at `blueprint.luau:1288,1391,1534`, `snapshot.luau:554`, `package.luau:1949,1961,2520`, `screen_target.luau:2814`, `screen_chrome.luau:1197`).
**Invariant:** blur/offset/spread are `UDim`/`UDim2`, `zIndex` negative-only, `Enabled` honoured — a new shadow field must land in all three.
**(b) Extract** `src/client/paint_primitives.luau` with `writeShadow(instance, shadow, color?)`. This *removes* bytes from three files already near the 200k `Source` write cap, so it moves with the cap constraint rather than against it.

### REUSE-55 — Descriptor→`Font` builder ×3, and the key format declared twice · High / high
`src/client/text_premeasure.luau:123-145` (`fontFor(key)` — string key, **cached**, pcall-guarded, falls back to `Font.new(file)` on an unknown weight) · `src/client/native_style.luau:72-88` (`toFont(v)` — table descriptor, no cache, no fallback) · `src/client/theme_controller.luau:799-817` (`materializeFont` — table descriptor + engine-absent fallback via its own probes at `:786-791`). Plus `src/themes/snapshot.luau:53` (`fontKey` builds `"family#weight#style"`), the exact inverse of `text_premeasure.parseDescriptor` (`:110`) — the format string declared in two modules.
**Layering already permits the fix:** `theme_controller` requires `native_style` (`:53`), and `native_style` has no module-scope engine access.
**(b) Extract** `native_style.font(descriptor) -> Font | descriptor` (engine-absent tolerant, delegating to `text_premeasure`'s cache); delete the other two bodies and move `fontKey`'s format next to `parseDescriptor`.

### REUSE-56 — `default_style` / `default_light_style` near-copy, with live shadow drift · High / high
**Neither is derived from the other.** Byte-identical by copy: the `rgb` helper (`src/tokens/default_style.luau:22-25` ↔ `src/tokens/default_light_style.luau:11-14`), `type` (`:67` ↔ `:47`), `space` (`:68` ↔ `:48`), `radii` (`:69` ↔ `:49`), `strokes` (`:98` ↔ `:70`), `targetSizes` (`:99` ↔ `:71`), `motion` (`:100` ↔ `:72`), and the whole compile→assert→`table.clone`→re-attach `extra`→`table.freeze` tail (`:103-115` ↔ `:75-86`).
**The drift, and it contradicts the file's own stated invariant.** `default_light_style.luau:45-46` says *"a light variant changes colour, never metrics"*. The shadows differ on three metrics: `raised` blurRadius offset **14** (`default_style.luau:79`) vs **12** (`default_light_style.luau:52`); y-offset **3** vs **2**; transparency **0.35** vs **0.75**. `overlay` transparency **0.45** vs **0.65**. And `default_style.luau:75-78` records the reason its numbers are what they are: *"0.55/12/y2 measured near-invisible against a mid sky (max pixel delta 18/255 over the Quality row, director fix round 2026-07-25) — a depth cue nobody can see is cost without information."* The light theme still carries **12 / y2** — the exact geometry that round rejected — at an even more transparent alpha. **Confidence:** high that the divergence exists and violates the stated invariant; medium that it is a failed fix propagation rather than a deliberate light-surface choice (history is squashed, and no test pins the relationship).
**No test pins it:** `tests/preferred_transparency.spec.luau:36-37`, `theme_matrix_audit.spec.luau:52-53`, `styling.spec.luau:540` and `sheet_model.spec.luau:15` load both, none compares their metrics.
**(b) Extract** `tokens.buildStyle(schema, name)` owning `rgb` + the compile/assert/clone/freeze tail, and a shared `NEUTRAL_METRICS` table both schemas spread. Palettes stay literal. Whether the shadows should also be shared is a design call the extraction *forces someone to make once* — which is the point.

### REUSE-57 — Interaction-state colour derivation stated three times · Medium / high
`src/tokens/sheet_model.luau:505-506` (`AccentHover = lerp(accent, WHITE, 0.12)`, `AccentPressed = lerp(accent, BLACK, 0.18)`, with a comment noting "bespoke path computes these with Color3:Lerp at the edge") ↔ `src/client/screen_paint.luau:788` and `:794` (the same two constants, hand-written) ↔ `sheet_model.luau:439-447` (`selectedSurfaceOf` rewrites `lerp(control, accent, 0.35)` a second time inside the same file, with a different missing-`control` fallback). `effectiveExtra` (`sheet_model.luau:1374-1391`) also re-declares literals `default_style.luau:52-70` already owns (`scrimOpacity 0.45`, `hairlineOpacity 0.92`, `focusRingThickness 2`, `pressedScale 0.985`, `tenFootFocusRingThickness 4`, `tenFootFocusScale 1.05`) — they agree today.
**(b)** the `src/tokens/palette.luau` of REUSE-52 owns the derivation constants and the neutral `extra` floor; `screen_paint` reads the derived token instead of re-lerping.

### REUSE-58 — `stampOf` (FNV-1a) written twice · Medium / high
`src/themes/package.luau:632-641` ↔ `src/tokens/sheet_model.luau:577-586`, byte-identical, with package's comment saying "same algorithm as sheet_model.stampOf, so both stamps read alike in artifacts".
**Invariant:** stamps drive the seed-once / freshness gates (`native_style` schema+stamp attributes) — a silent divergence either re-seeds a designer's edited sheet or fails to migrate one. `sheet_model` already requires `themes/package` (`:30`), so there is no layering cost.
**(a) Reuse:** export `package.stampOf(parts)`. The two *serializers* (`package.serialize:644` vs `sheet_model`'s model walk `:2909-2951`) are genuinely different shapes and stay.

### REUSE-59 — Dotted-path traversal: 2 writers + 3 readers, all hand-rolled · Medium / high
Writers: `src/themes/snapshot.luau:340-361` (returns false when the path names nothing) and `src/themes/token_sync.luau:286-307` (creates missing levels, plus the `type`→`typography` rename). Readers: `snapshot.luau:967-977` (`lookupPath`), `src/client/theme_controller.luau:844-846` (inline), `src/themes/package.luau:3091` (inline). All five share `string.gmatch(path, "[^%.]+")` — the split rule is the same namespace `token_sync.attributeName:99-110` encodes for engine attributes.
**(b) Extract** `src/themes/metric_path.luau`: `split(path)`, `read(tree, path)`, `write(tree, path, value, create?)`. The `type`→`typography` rename stays in `token_sync` — that is that module's declared responsibility.

### REUSE-60 — Border `UIStroke` creation ×5 and three partial name registries · Medium / high
Creation: `src/client/screen_chrome.luau:180-186` ("Hairline") · `src/client/screen_paint.luau:624-630` ("Hairline") · `screen_paint.luau:392-402` (`authority.INSTANCE_NAMES.stroke`) · `src/client/screen_target.luau:2878-2887` ("FocusRing") · `src/client/edit_preview.luau:51-54` — **which omits `ApplyStrokeMode = Enum.ApplyStrokeMode.Border`**, the exact engine trap `sheet_model.luau:1230-1246` and `screen_paint.luau:399-402` both document. `screen_paint`'s `hairlineWouldShow` skip (`:605-615`, a measured 30-instances-per-5-rows saving) is absent from the `screen_chrome` copy.
Names: a registry exists (`src/render/authority.luau:270-297`) and a second in `src/tokens/chrome_slots.luau:107,108,110,1304,1682,1683`; `authority` restates those strings as bare literals (`:284-296`). `"Hairline"` (7 sites), `"FocusRing"` (5) and `"FacetGradient"` (`screen_paint.luau:554`) are in **neither** — a `FindFirstChild` typo there is a silent no-op.
**(b)** `paint_primitives.borderStroke(instance, { name, color, transparency, thickness })` (with the visibility skip), and add `hairline`/`focusRing`/`gradient` to `authority.INSTANCE_NAMES`, keying `BESPOKE_INSTANCES` off `chrome_slots`' constants instead of literals.

### REUSE-61 — Gradient sequence materialization ×2 · Medium / medium
`src/client/screen_paint.luau:557-568` builds `ColorSequenceKeypoint`/`ColorSequence` and `NumberSequenceKeypoint`/`NumberSequence` from `{t,r,g,b}`/`{t,v}` stops — the identical loops `src/tokens/chrome_props.luau:164-193` (`materialize`) already owns over the *same* stop shape. `chrome_props`' header states it exists "because a second copy of 'what does kind=… mean' is exactly the drift this module exists to prevent"; `screen_paint` is that second copy for two of the four kinds.
**(a) Reuse:** `screen_paint.applyGradient` calls `chrome_props.materialize({ kind = "colorseq", stops = … })` / `{ kind = "numseq", … }`, or a thin `chrome_props.colorSequence(stops)` wrapper. Confidence medium pending a check that `styling.normalizeGradient`'s frozen stops satisfy `chrome_props` ordering — `ramp` already sorts and pins, so they should.

### REUSE-62 — `toColor3` ×3 plus inline copies · Low / high
`src/client/screen_target.luau:184` · `src/client/screen_chrome.luau:37` · `src/client/native_style.luau:65`, plus inline `Color3.new(c.r, c.g, c.b)` at `screen_target.luau:1648,1652`, `screen_chrome.luau:1219`, `screen_paint.luau:523,559`. `screen_chrome:35-36` gives the reason ("cheaper to repeat than to widen the Context"), and RETAIN-02 accepted it.
**(b)** lands for free on the `paint_primitives.luau` of REUSE-54/REUSE-60 — the reason holds only while there is no shared client leaf, and three independent findings each want one.

### REUSE-63 — The ten-foot rule stated twice inside `environment.luau` · Low / high
`src/env/environment.luau:190` inlines `if use(signals.displaySize) == "Large" then "ten-foot" else "near"` inside `derived.sizeClass`, while `:219-221` is `derived.distanceProfile` computing exactly that — and `src/render/renderer.luau:1974, 3182, 3198` and `src/client/screen_target.luau:2715` all read the derived fact. The comment immediately above the inline copy (`:183-188`) claims the module single-sources this class of rule ("ONE implementation of the breakpoints and the ten-foot density floor … verifier finding V15").
**(a) Reuse:** have `derived.sizeClass` read `derived.distanceProfile`. If a future rule makes `distanceProfile` depend on more than `displaySize`, `sizeClass` silently keeps the old one.

### REUSE-64 — `imperative.luau` writes the same closure twice in one function · Low / high
`src/core/imperative.luau:27-29` passes an inline `function(message) lastError = message end` to `scope_impl.factory`, and `:42-44` declares `local function fail(message) lastError = message end` — the same two-line body, thirteen lines apart in the same function scope. `src/core/custom.luau:70-78` gets it right: declare `fail`, then pass it.
**(a) Reuse:** hoist the named `fail` above the factory call, as `custom.luau` does.

### REUSE-65 — Copy-on-write decoration hint ×2 in one file · Low / high
`src/client/screen_target.luau:3168-3176` (`icon`) and `:3194-3202` (`compactLabel`) — identical 8 lines, one key differs. Both exist because `chrome_slots.attachHint` freezes the table.
**(b)** `local function withHint(handle, key, value)`.

### REUSE-66 — Haptics entry-connection teardown ×2 · Low / high
`src/client/haptics.luau:776-783` ↔ `:886-893`, identical `for _, connection in { entry.connection, entry.destroying } … guard(… :Disconnect())`.
**(b)** `local function releaseEntry(entry)`.

### REUSE-67 — Capitalize-first ×6, sorted-key collection ×8 · Low / medium
Capitalize-first: `src/tokens/sheet_model.luau:1331` (`pascal`) and `:1140` (inline) · `src/themes/token_sync.luau:108` · `src/tokens/chrome_slots.luau:1317` · `src/motion/curves.luau:82` · `src/client/motion_driver.luau:59`. Sorted-key collection: `src/spec_guard.luau:71` · `src/themes/package.luau:572,648,2776` · `src/themes/token_sync.luau:119` · `src/tokens/sheet_model.luau:1152,2913` · `src/tokens/chrome_slots.luau:2094`.
**(b)** fold both into the same `spec_guard`/util export as REUSE-1. Each is one line; the win is consistency, not bytes.

### REUSE-68 — Three cores' `defaultEq` diverge on NaN · Low / high — **keep separate**
`src/core/custom.luau:44-46` is NaN-safe (`a == b or (a ~= a and b ~= b)`, with the reason in its comment); `src/core/imperative.luau:18-20` is plain `a == b`; `src/core/fusion_adapter.luau:80-84` accepts an `eq` argument and ignores it (Fusion has no per-signal equality). Same for the `fail` closures (`custom.luau:70`, `fusion_adapter.luau:61`, `imperative.luau:42`).
**(c) Keep separate — merged semantics would differ, and the difference is the measurement.** `docs/adr/ADR-0002-foundation-core-selection.md:11` scores the imperative baseline as "21/26: … NaN refires", and `artifacts/conformance-{custom,imperative,fusion}.json` all carry the named check `nan-equal-write-skipped`. The three cores are the Phase-0 bake-off candidates and `tests/conformance/cli.luau:20-22` is their only loader. Recorded so the divergence is not "fixed" by a future reader. One non-reuse note: both alternates ship inside `build/Facet.rbxm` — a packaging question, not a duplication one.

### REUSE-69 — Scalar-shape validators at ~25 public boundaries · Low / medium — **keep separate**
`src/async/resources.luau:86-101` (`requireIntegerAtLeast`, `requireNonNegativeNumber`) are the mechanical form of an idiom repeated ~25× with bespoke wording (`src/blueprint.luau:1720,1776`, `src/themes/package.luau:1099,1102,1257,1365,1373,1431,1448,1473,1486,1523,1532,1578`, `src/controls/virtual_grid.luau:346,369,386,399,407,419`, `src/controls/value_model.luau:76`).
**(c) Keep separate — merged semantics would differ:** most of these messages carry teaching text that *is* the error's value, and `package.luau` uses report-collecting `reject()` rather than `error()`, so a merged helper needs a mechanism parameter. Only `resources.luau`'s two are purely mechanical, and two call sites do not earn an extraction.

### REUSE-70 — `chrome_props.colorSeq` / `numSeq` are the same function twice · Low / medium — **keep separate**
`src/tokens/chrome_props.luau:82-101` ↔ `:103-121` (validate stops, copy, sort by `t`, tag); likewise the two `describe` branches (`:143-158`) and the two `materialize` branches (`:177-193`).
**(c) Keep separate — more branching than it removes, and it obscures a tutorial:** the stop payloads genuinely differ (`{r,g,b}` vs `{v}`), a generic version needs a per-stop reader callback plus a kind parameter, and the 201-line file is the framework's stated single-owner explanation of "what does `kind = …` mean".

## F. `tools/`

### REUSE-71 — Framework-checker chain copied into 12 gate rows, five different contents · High / high
**Responsibility:** run the standing framework checkers before a stage closes.
**Sites (one `run` string each) in `tools/lune/gate_manifest.luau`:** `:504`, `:633`, `:766`, `:858`, `:955`, `:982`, `:1094`, `:2253`, `:2799`, `:3184`, `:3434`, `:3663`.
**Verified contents:**
- `:504`, `:633`, `:766`, `:858` — `check_registration_cli`, `check_docs_cli`, `check_boundary`, `check_prop_parity_cli`, `check_surface_ledger`, `check_manifest_integrity`
- `:955` — **drops `check_manifest_integrity`** (and stylua)
- `:982`, `:1094` — **drop `check_surface_ledger`**
- `:3184`, `:3434`, `:3663` — add `check_flat_baseline` + `check_example_drift_cli`
- `:2253`, `:2799` — one/two checkers only
`stylua` args also drift: `--check src tests tools bench examples` ×7 vs `--check src tests tools examples` ×2, leaving `bench/` unscanned (`gate_manifest.luau:349`).
**Consequence:** a gate can close "with the framework checkers green" while the surface ledger was never run. `check_manifest_integrity.py` audits *suite greps*, not checker coverage, so nothing detects this.
**Callers:** `tools/lune/gate.luau:47-84` executes each `run`; `tools/gate.sh:11`; `tools/prior_gates.sh:158`.
**(b) Extract** a manifest-layer constant: `local FRAMEWORK_CHECKS: (extra: { string }?) -> string`, so the 12 rows read `FRAMEWORK_CHECKS()` / `FRAMEWORK_CHECKS({ "check_flat_baseline", "check_example_drift_cli" })` and a per-row omission has to be written down.

### REUSE-72 — Prior-gates allowlist inline-Python'd into 5 rows, three different policies · High / high
**Sites:** `tools/lune/gate_manifest.luau:195`, `:3094`, `:3209`, `:3467`, `:3689` — each embedding `allowed = {(gate, check), …}` inside a `python3 -c` string.
**Verified contents:** `:195` and `:3094` carry 8 entries. `:3209` and `:3467` carry the same 8 **plus** `('traversal-document-order', 'studio-evidence')`. `:3689` carries the 8 **plus** `('theme-packages-and-skinning', 'style-editor-sync')` and **drops** the traversal entry the two rows above it added — so a stage-specific exemption silently reverts.
**Precedent and stated policy already exist for the fix:** `tools/check_perf_gate_evidence.py:4-9` and `tools/check_eq6_evidence.py:5-8` both explain in prose *why* these assertions must be files rather than inline manifest strings (stylua quote-mangling; embedded-newline collapse — `docs/lessons/embedded-newlines-measure-as-one-line.md`, `docs/lessons/luau-interpolated-strings-single-line.md`). `check_perf_gate_evidence.py:196-241` already implements the same roll-up parse.
**(b) Extract** `tools/check_prior_gates_rollup.py` with `main(rollup_path, stage) -> int`, owning the allowlist as one module-level table.

### REUSE-73 — Python checker report skeleton ×13, three dialects, divergent missing-evidence handling · High / high
**Shared skeleton** (`errors = []` … emit … exit 0/1/2) at `tools/check_device_captures.py:29,105-108,126` · `check_perf_metrics.py:38,187-190,212` · `check_perf_budgets.py:47,115-118,137` · `check_xp_matrix.py:34,148-151,157` · `check_perf_scenes.py:80,158-161,168` · `check_matrix_rows.py:16,78-81` · `check_perf_captures.py:97,210-214,223` · `check_perf_place.py:113,239,252` · `check_row_actions_matrix.py:104,137-141,150` · `check_spike.py:86,112-115,122` · `check_verdicts.py:66,76-79,86` · `check_manifest_integrity.py:204,248,344` · `check_source_size.py:441,472`.
**Three emission dialects:** `print(f"FAIL {e}")` to stdout (5 files); `print(f"{tool}: {p}", file=sys.stderr)` (4); `raise SystemExit(1)` via a byte-identical `fail()` at `check_no_screen_key_bindings.py:106-108` and `check_traversal_evidence.py:66-68`.
**Missing-evidence behavior is not identical.** Handled: `check_sf_rows.py:39-44`, `check_verdicts.py:35-38`, `check_spike.py:66-71`, `check_eq6_evidence.py:18-21`, `check_device_captures.py:30-32`, `check_row_actions_matrix.py:100-102`, `check_perf_gate_evidence.py:269-271`. Uncaught traceback: `check_matrix_rows.py:15`, `check_perf_budgets.py:46` and `:100`, `check_perf_metrics.py:37`, `check_perf_scenes.py:79`, `check_xp_matrix.py:33`, `check_traversal_evidence.py:106`. The gate still reddens (`gate.luau:51-52` reads exit status), so this is a diagnosability defect, not a false-green — but in the many `python3 tools/check_X.py >/dev/null && …` chains the operator gets a stack trace instead of a sentence.
**(b) Extract** `tools/gatecheck.py` — `class Report: add(msg); load_json(path); finish(ok_summary) -> int`, where `load_json` turns FileNotFound/JSONDecodeError into a one-line problem. `tools/__pycache__/` already exists, so intra-`tools/` imports are established. The best in-repo model is `check_perf_gate_evidence.py:27-29,244-256,259-271`.

### REUSE-74 — `check_sf_rows` / `check_spike` / `check_verdicts` are one checker three times · High / high
`tools/check_sf_rows.py` (78 lines, exact match against `doc["rows"]`, schema pinned to `"luauui-sf-row/1"` at `:26`) · `tools/check_spike.py` (122 lines, the same job generalised: `ROW_KEYS:26` **includes `"rows"`**, `ID_FIELDS:27`, prefix match `:90`, optional `=<expected>` status `:100-110`) · `tools/check_verdicts.py` (86 lines, the same job for single-verdict artifacts, `FIELDS:28`, prefix match `:48`). `check_spike` is a strict superset of `check_sf_rows` except the schema pin, and the JSON-load-and-validate preamble is line-for-line the same in all three (`check_sf_rows.py:36-48`, `check_spike.py:63-75`, `check_verdicts.py:32-41`).
**Callers:** `gate_manifest.luau` invokes `check_sf_rows.py` ×28, `check_spike.py` ×10, `check_verdicts.py` ×7.
**(b) Fold** `check_sf_rows` into `check_spike` behind `--schema <s>` (one new option, one deleted file, 28 call sites gain `--schema luauui-sf-row/1`); give `check_verdicts` the shared loader from REUSE-73.

### REUSE-75 — Shell preamble ×17; five wrappers byte-identical but for one line · Medium / high
The block (`cd "$(dirname "$0")/.."` + the 5-line ROKIT comment + `export PATH="$HOME/.rokit/bin:…"`) at `tools/bench.sh:3-9`, `decision.sh:3-9`, `interact.sh:3-9`, `render.sh:3-9`, `soak.sh:3-9`, `gate.sh:4-10`, `faults.sh:6-12`, `fuzz.sh:6-12`, `perf.sh:8-14`, `doctor.sh:5-11`, `build_model.sh:9-15`, `build_places.sh:11-17`, `build_reference_places.sh:10-16`, `prior_gates.sh:68-74`, `test.sh:61-67`, `suite_transcript.sh:21-22`, `suite_cache_selftest.sh:19-20`.
**Verified:** `bench.sh`, `decision.sh`, `interact.sh`, `render.sh`, `soak.sh` are 11-line files whose first 10 lines are byte-identical; only `exec lune run tools/lune/<name> "$@"` differs.
**Also drifting:** `set -euo pipefail` (10 scripts) vs `set -uo pipefail` (7). `run-tests.sh:14` exports `PATH="/opt/homebrew/bin:$PATH"` with **no rokit pin** — harmless today (it only runs `lune`), but it is the one file the preamble's own comment does not protect.
**(b) Extract** `tools/_common.sh` exporting `FACET_ROOT` and the PATH pin, sourced on line 2 of each. The five thin wrappers collapse to two lines each.

### REUSE-76 — `check_*_cli` printer written four times · Medium / high
`tools/lune/check_registration_cli.luau:9-21` · `check_prop_parity_cli.luau:11-25` · `check_docs_cli.luau:35,45-62` · `check_example_drift_cli.luau:9,24-35`. The FAIL blocks are textually identical modulo the tool name (`FAIL [UI-AGENT-001] — N problem(s)`, bullets, hint, `process.exit(1)`). The library halves already return the same shape (`{ ok, problems, counts }` — `check_prop_parity.luau:571`, `check_docs.luau:962`, `check_registration.luau:635`, `check_theme_drift.luau:198-203`, `check_example_drift.luau:400-405`), so only the printer is copied.
**Callers:** `check_registration_cli` ×25, `check_docs_cli` ×19, `check_prop_parity_cli` ×12, `check_example_drift_cli` ×8 in `gate_manifest.luau`.
**(b) Extract** `tools/lune/checker_cli.luau`: `report(name, result, { summary, hint? }): never`. `tools/lune/scaffold_cli.luau` is **not** part of this family (it drives writes/edits, `:18-38`) and must not be folded in.

### REUSE-77 — Two Luau line-lints share a copied engine, and a comment detector that under-delivers · Medium / high
`tools/lune/check_theme_drift.luau` ↔ `tools/lune/check_example_drift.luau`, block for block: `isComment` (byte-identical) `:104-107` ↔ `:268-271`; `Options` `:109-113` ↔ `:274-278`; file collection + sort `:118-130` ↔ `:280-306`; per-file read + injection `:134-138` ↔ `:311-316`; the `gmatch` line loop `:139-145` ↔ `:317-323`; ALLOWLIST suppression `:167-174` ↔ `:366-374`; the return shape `:198-203` ↔ `:400-405`; `checker.ALLOWLIST` `:206` ↔ `:408`. Only the rule tables differ. `check_example_drift.luau:5-11` names `check_theme_drift.luau` as its sibling — the fork is acknowledged in prose, not in code.
**Latent gap in both copies:** `check_theme_drift.luau:103` claims lines "inside a block comment carry no code", but `isComment` only tests a leading `--`; a `--[[ … ]]` body line and a trailing comment are both scanned as code. A correct Luau comment stripper already exists in this repo, in Python: `tools/check_no_screen_key_bindings.py:103-170`.
**(b) Extract** `tools/lune/source_lint.luau`: `run({ files, dirs, recursive?, rules, allowlist, opts? }) -> { ok, problems, violations, counts }`, with one correct comment stripper. The block-comment gap then closes once instead of twice.

### REUSE-78 — Perf-lab harness built from scratch ×5 · Medium / high
`tools/lune/_probe_levers.luau:29-77` (`newHarness`) · `tools/lune/_probe_profile_aim.luau:22-75` (near byte-identical; differs in `telemetry.clock` and a hoisted `host`) · `tools/lune/_probe_lab_settle.luau:29-98` (inline, plus a `host.facts()` block) · `tests/perf_lab.spec.luau:37-125` (**the superset** — already parameterised `(hostOverrides, viewport, labOpts)` and already carrying `host.facts()`) · `tests/mount_unmount_soak.spec.luau:37-98`. The `counts()` helper is byte-identical at `_probe_levers.luau:83-93` and `_probe_profile_aim.luau:77-87` — except that one `SCOPES` list has `"present"` and the other does not.
**(b) Extract** `tests/lib/perf_lab_harness.luau`: `new({ hostOverrides?, viewport?, labOptions?, telemetry? })`, promoting `tests/perf_lab.spec.luau:37`'s version verbatim.

### REUSE-79 — `tools/lune/artifact.luau` exists and is bypassed by five sites · Medium / high
**Owner:** `tools/lune/artifact.luau:10-16` ("Dropbox drops empty dirs" — ensure dir, then pretty JSON). Correct users: `bench.luau:282`, `check_boundary.luau:344`, `decision.luau:99`, `faults.luau:36`, `fuzz.luau:98`, `perf.luau:227,232,355`, `matrix_report.luau:109`, `prove_perf_gate.luau:141`, `registry_runner.luau:36,49`.
**Bypassers:** `tools/lune/check_example_drift_cli.luau:10-23` (hand-rolls the whole thing and does not require `./artifact`) · `gate.luau:101-102` (unguarded `fs.writeDir` + manual encode) · `studio_sync.luau:130-131,:142,:169` · `_theme_baseline.luau:240` · `perf_baseline_scene.luau:106` (appends `"\n"` — the only behavioural difference in the set).
**(a) Reuse** `artifact.luau`. If the trailing newline is wanted, add it there once; inconsistent trailing newlines across artifacts are a diff-noise source.

### REUSE-80 — 48 gate rows re-assert the evidence check `gate.luau` already performs · Medium / high
**Owner:** `tools/lune/gate.luau:54-58` — "a passing run must leave its evidence artifact behind"; on PASS it stats `check.evidence` and downgrades to `FAIL_RECOVERABLE`.
**Duplicated:** of 471 `run` strings in `tools/lune/gate_manifest.luau`, **48** open with `test -f "<path>"` where `<path>` is that same check's own `evidence` field (counted programmatically; anchors include `:125`, `:132`, `:139`, `:146`, `:153`, `:772`, `:884`, `:935`, `:975`, `:1040`, `:1107`, `:1373`, `:1392`, `:1507`, `:1520`, `:1955`, `:1993`, `:2023`, `:2030`, `:2037`, …). A further 46 rows begin with `test -f` against a *different* target — those are genuine second preconditions and stay.
Not a false-green (both layers fail closed), but two layers own one invariant and a reader cannot tell which is authoritative.
**(a) Reuse** `gate.luau:54-58`; drop the redundant prefix from those 48 rows only.

### REUSE-81 — Five ad-hoc `process.args` flag parsers; one already ran the wrong path silently · Medium / high
`tools/lune/check_flat_baseline.luau:768` (`process.args[1] == "--list"`) — its header at `:29-32` records the scar: *"`-- --list` … has never worked on this toolchain: lune 0.10.4 does not forward the args after a bare `--`, so `process.args[1]` was nil and **the form silently ran the full check instead of listing**."* · `check_elision_census.luau:169` (defends by checking both `args[1]` and `args[2]`; its usage line at `:5` still documents the broken form) · `studio_sync.luau:134` (same both-positions defence) · `check_docs_cli.luau:19-25` (iterates all args) · `theme_sync_cli.luau:37-62` (a full parser that explicitly `continue`s past a bare `--` at `:42-45`). Five workarounds for one toolchain behaviour, one of which failed silently.
**(b) Extract** `tools/lune/cli_args.luau`: `parse(argv?) -> { flags, values, positional }`, stripping a leading bare `--` once.

### REUSE-82 — Capture sha256[:16] pin implemented five times in three languages · Medium / high
Producers: `tools/studio/matrix_capture.sh:26` (`shasum -a 256 … | cut -c1-16`) and `tools/lune/matrix_report.luau:27-33` (`process.exec("shasum", …)` + `string.sub(…, 1, 16)`). Consumers: `tools/check_matrix_rows.py:65-76` and `tools/check_xp_matrix.py:58-68` (`hashlib.sha256(…).hexdigest()[:16]`), plus two inline Python heredocs in `tools/lune/gate_manifest.luau` (`hashlib` appears twice there — `:2461` and `:2604`) doing the same `isfile` + hash + assert loop with only the artifact dir and row-count floor changed. The two Luau/shell producers depend on `shasum`'s stdout layout; nothing tests that against the Python consumers.
**(b) Extract** `tools/check_capture_pins.py`: `main(matrix_json, base_dir, min_rows) -> int`, deleting both heredocs and the duplicated capture sections; keep one `sha16` on the Luau side for the producers.

### REUSE-83 — `percentile` ×2; one lacks the empty-sample guard · Medium / high
`bench/perf_runner.luau:291-298` guards `if #sorted == 0 then return 0 end`; `tools/lune/bench.luau:67-70` does not (verified). `bench.luau:62-65` guards only the empty *scenario registry*, so `percentile({}, 0.95)` returns `nil` there and would land in `artifacts/bench.json` as a null, consumed by `gate_manifest.luau:995`/`:1107`.
**(b) Extract** `bench/stats.luau: percentile(sorted, p)` (the guarded version); `bench/` already hosts `perf_runner`, `perf_scenes`, `perf_profiles`.

### REUSE-84 — Consumer path hardcoded 74×, suite row duplicated 14× · Medium / high
Exact-duplicate `run = "cd ../../../games/RascalRally/code && tools/suite_transcript.sh >/dev/null"` at `tools/lune/gate_manifest.luau:1088, 1208, 1254, 1342, 1429, 1619, 1681, 2100, 2196, 2323, 2475, 2638, 2786, 2973` (14), plus a 15th variant at `:1596`. The literal `../../../games/RascalRally/code` appears 70× in the manifest and 4× outside it: `tools/check_manifest_integrity.py:79` and `:81`, `tools/suite_cache_selftest.sh:256`, `tools/lune/check_boundary.luau:122`. Per the root `CLAUDE.md`, Facet and Rascal Rally are contractually coupled, so this path moving is foreseeable.
**(b)** declare it once at the top of `gate_manifest.luau` (`local RR`, `local RR_SUITE`) and have the four out-of-manifest sites read one small `tools/consumer.json`.

### REUSE-85 — `.luau` directory walkers ×6, two inside one file · Low / high
`tools/lune/check_boundary.luau:81-93` (`walk`) and `:271-283` (`walkConsumer`) — same file, identical structure, differing by one leaf callback · `check_example_drift.luau:293-306` (`addDir`) · `check_theme_drift.luau:122-130` (non-recursive) · `tools/check_no_screen_key_bindings.py:173-177` · `tools/check_source_size.py:406`. `check_boundary.luau:292-300` had to add "a scan that found nothing is not a pass" for the *second* walker only; the first (`walk("src")`, `:95`) still has no such guard.
**(b) Extract** `tools/lune/fs_walk.luau: luauFiles(root, { recursive? })` returning a sorted list and erroring on an unresolvable root. The two Python walkers stay (different language, different lint).

### REUSE-86 — Probe scene-mount harness copied into eight probes · Low / medium
Byte-identical span counter: `tools/lune/_probe_settle.luau:13-22` ↔ `_probe_lab_settle.luau:18-27`. Same six-line scene-mount preamble at `_probe_settle.luau:32-37`, `_probe_lab_settle.luau:29-34`, `_probe_levers.luau:30-35`, `_probe_profile_aim.luau:23-28`, `_probe_modal_solves.luau`, `_probe_new2.luau`, `_probe_vlist_release.luau`, `_probe_matrix.luau`. Ad-hoc output: `_probe_carryovers.luau:13-17` invents a local `say()`.
**Checked: no harness of this shape exists to reuse.** `tools/lune/registry_runner.luau:20-56` is the fixture runner for `render`/`interact`/`soak` only; `tests/lib/` has `fake_target` but no scene-mount harness.
**(b) Extract** `tests/lib/scene_harness.luau`: `new({ viewport?, traceScopes? }) -> { core, env, adapter, presenter, actionSystem, spans, trace, dispose }`. REUSE-78's `perf_lab_harness` should be built on top of it.

### REUSE-87 — Suite-transcript capture/grep idiom ×179 / ×1412 · **keep separate**
179 copies of `out="$(tools/suite_transcript.sh)"` and 1412 of `echo "$out" | grep -q "✓.*…"` in `tools/lune/gate_manifest.luau`. On volume alone this looks like the largest finding in the tree.
**(c) Keep separate — a written policy makes the literal shape the subject of an existing audit.** `tools/check_manifest_integrity.py:99-102` pins `SUITE_CMD`, `CAPTURE`, `FORM_A` and `FORM_B` as regexes over these exact strings, and its header (`:18-32`) documents why FORM A is safe while FORM B is blind — *"Twenty-six checks shipped in this shape."* Collapsing the 179 captures into a helper would move the audited construct out of the manifest and blind that auditor for all 1412 assertions until it is rewritten in lockstep — more branching than it removes, against an invariant with a recorded false-green history. The 1412 patterns are data (one spec-case name each), not logic. Caching, the other motive, is already solved a layer down (`tools/test.sh:19-58` + `tools/suite_transcript.sh:24-36`).

## G. `tests/`, `examples/`, `bench/`

`tests/lib/` currently owns: `testkit` (all 231 specs), `fake_target` (189 files), `large_text`, `device_views`, `adapter_source`, `renderer_source`, `tiers`, `fault_scenarios`, `fuzz`, `prng`, `fuzzers/*`, `framework_icons`, `gui_value_shim`, `theme_sweep_ledger`, `large_text_fixtures`. It owns **no** deep-copy, **no** generic world builder, **no** node/rect accessor, **no** input-drive helper, and **no** diagnostics assertion — which is where every finding below sits.

### REUSE-88 — Headless stack builder ×106 across 100 spec files, two incompatible return orders · High / high
**Responsibility:** core + environment + viewportRect + action system + fake_target + presenter.
**Scale (measured):** 106 spec-local definitions named `world`/`makeWorld`/`harness` across 100 files; `env:set("viewportRect", …)` appears 563 times.
**The drift:** two incompatible return orders of the same 5-tuple. `return core, env, system, adapter, pres` at 12 sites (`tests/paradigm_input_axis.spec.luau:134`, `responder.spec.luau:27`, `paradigm_table.spec.luau:23`, `auto_input_screens.spec.luau:23`, `keyboard_navigation.spec.luau:256`, `paradigm_carry.spec.luau:18`, `virtual_list_input.spec.luau:26`, `auto_input.spec.luau:18`, `late_contributions.spec.luau:35`, `table_input.spec.luau:26`, `slice_mutation.spec.luau:14`, `modal_dismissal.spec.luau:23` — ten of them byte-identical); `return core, env, adapter, system, pres` at 16 (`control_feedback.spec.luau:48`, `display_controls.spec.luau:23,228`, `anchored_surface.spec.luau:324`, `text_reveal.spec.luau:37`, `presenter.spec.luau:16`, `level_picker.spec.luau:35`, `text_disclosure.spec.luau:29,361`, `theme_value_displays.spec.luau:212`, `toast_presentation.spec.luau:27`, `feedback.spec.luau:25`, `help.spec.luau:57`, `button_complete.spec.luau:41`, `transitions.spec.luau:622`, `menu.spec.luau:764`). Two more shapes at `examples_games.spec.luau:27`, `example_word_game.spec.luau:31`, and `bench/perf_scenes.luau:81` (`newStack(profile)`).
**Invariants:** the presenter must be constructed after the adapter and before any `present`; `viewportRect` must be set before the first solve or the first frame runs at a 1×1 viewport (a known past defect).
**Perf:** ~6000 tests; the builder runs thousands of times and must stay allocation-cheap.
**(b) Extract** `tests/lib/world.luau` with a **keyword-argument** constructor so ordering cannot drift: `new({ viewport?, safeInsets?, capabilities?, preferredInput?, displaySize?, themeMetrics?, presenterOpts? }) -> { core, env, system, adapter, pres, present, settle, tick }`. `tests/lib/large_text.world` is the working prototype and should be re-expressed on top of it. Migrate opportunistically; the ten byte-identical copies are the zero-risk first batch.

### REUSE-89 — Recursive deep-copy ×16 · High / high
Verified byte-identical bodies at `tests/theme_icons.spec.luau:24` · `theme_icons_applied.spec.luau:55` · `theme_assets.spec.luau:25` · `theme_layers.spec.luau:28` · `theme_value_displays.spec.luau:81` · `theme_pixel_content.spec.luau:29` · `theme_layer_application.spec.luau:85` · `theme_package.spec.luau:17` · `theme_variants.spec.luau:27` · `theme_pixel.spec.luau:25` · `theme_chrome.spec.luau:1371` (`deepCopy`, block-local) · `virtual_list_row_actions_identity.spec.luau:212` (`deepCopy`) · `examples/themes/layered_test.luau:197` · `examples/themes/fantasy_parchment_stub.luau:114` · `examples/themes/fantasy_ornate.luau:369` · and the production one at `src/themes/package.luau:598`.
**Invariants:** none preserves metatables or cycles; all assume plain data — correct for theme definitions, silently wrong for anything else, and a future caller cannot tell which contract they got.
**(b) Extract** `tests/lib/table_util.luau: deepCopy(value)`, documented "plain data only". The two `examples/themes/*` *authoring examples* are a legitimate **(c)** — importing from `tests/lib` in a user-facing authoring example is wrong — but `layered_test.luau` is a `testOnly` fixture (per `tests/gallery_theme_picker.spec.luau:141`) and should import. Exporting `package.deepCopy` publicly would give the example authors a supported one. See also REUSE-8.

### REUSE-90 — Neutral-derived theme-package fixture ×10 · High / high
The `def()` builder — identity + `style = copy(base.style)` / `metrics = copy(base.metrics)` / `chrome = copy(base.chrome)` + `compatibility = { requiresSchema = themes.SCHEMA }` — at `tests/theme_icons.spec.luau:35` (fields `:44-46`) · `theme_icons_applied.spec.luau:66` (`:75-77`) · `theme_assets.spec.luau:35` (`:45-47`) · `theme_layers.spec.luau:41` (`:50-52`) · `theme_value_displays.spec.luau:112` (`:121-123`) · `theme_pixel_content.spec.luau:40` (`:44-46`) · `theme_layer_application.spec.luau:96` (`:105-107`) · `theme_package.spec.luau:16` (`:34-36`) · `theme_variants.spec.luau:38` (`:47-49`) · `theme_pixel.spec.luau:36` (`:47-49`). Companion: `compile(d)` at `theme_pixel_content.spec.luau:52`, re-expressed as `built(...)` at `theme_reference_packages.spec.luau:56` and `theme_value_displays.spec.luau:205`.
**Invariants:** the definition must be freshly deep-copied per test (every file says so) or a mutation leaks; `schemaVersion` and `compatibility.requiresSchema` must both track `themes.SCHEMA` — a schema bump today is ten edits.
**Perf:** `snapshot.neutralPackage()` + three deep-copies runs on every case in the theme family; a memoized frozen base with per-call copy-on-write would measurably cut that block.
**(b) Extract** `tests/lib/theme_fixture.luau: definition({ id, assets?, chrome?, metricsPatch?, identityExtra? })` + `compile(def)`. ~200 duplicated lines collapse and the schema bump becomes one edit.

### REUSE-91 — Reference theme-package registry ×9, already divergent · High / high
Re-declared at `tests/gallery_theme_picker.spec.luau:218-226` (also `:22-25`, `:132-142`) · `renderer.spec.luau:721-729` · `theme_reference_packages.spec.luau:24-38` + `:41` · `theme_authoring_scenario.spec.luau:22-36` · `theme_matrix_audit.spec.luau:58-62` · `table_themed_header.spec.luau:51-70` · `overflow_sweep.spec.luau:226-234` · `tools/lune/check_docs.luau:354-364` · `tools/lune/_probe_matrix.luau:8-13`. The dynamic loader `packageOf(name)` is byte-identical at `tests/icon_box.spec.luau:54`, `chrome_inset_yield.spec.luau:53`, `row_actions.spec.luau:1697`, plus ~20 inline copies of the same require expression across the suite and `bench/perf_scenes.luau:1074,1095,1096,1118`.
**Self-declared and already false:** `tests/table_themed_header.spec.luau:48` — "the eight shipped reference packages (tests/theme_reference_packages.spec.luau holds the same list)". `theme_matrix_audit` carries four, `overflow_sweep` eight, `theme_authoring_scenario` eleven.
**Invariant:** `examples/themes/` has **no index module**, so a new package must be hand-added to nine lists and one added to eight is silently unswept by the ninth. `build(themes)` returns `(pkg, report)` and can fail; only `overflow_sweep.spec.luau:239-243` asserts it did not.
**(b) Add** `examples/themes/init.luau` (or `tests/lib/theme_packages.luau`) exporting `MODULES`, `ORDER`, `PICKABLE` and `build(name)` that asserts on a failed compile; every list becomes a filter over it.

### REUSE-92 — Five `ref_*` gallery scenarios, 122 lines each, differing in four identifiers · High / high
`examples/gallery/scenarios/ref_foyer.luau:1-122` · `ref_glade.luau:1-122` · `ref_cartwheel.luau:1-122` · `ref_sipworks.luau:1-122` · `ref_wardrobe.luau:1-122` — verified by `diff` to differ only in the proof name, title, ledger row and module name. Two sub-mechanisms are also five-way identical: the keyboard bracket `steps.armKeys/readKeys/focusOrder/focusOn` (`:36-79`) and `installTheme(moduleName)` (`:83-119`).
**(b) Extract** `examples/gallery/scenarios/reference_scenario.luau: build({ name, title, ledgerRow, module })`; each `ref_*.luau` becomes ~6 lines. ~600 lines collapse to ~150.

### REUSE-93 — `adapter_source` / `renderer_source` bypassed by 29 raw reads — silent-green pins · High / high
`tests/lib/adapter_source.luau:26-28` states the hazard: *"ADD A PART HERE WHENEVER MORE OF THE ADAPTER MOVES OUT — otherwise the pins quietly stop seeing the code they name."* It joins `screen_target`, `screen_paint`, `screen_scroll_indicators`, `screen_presentation`, `screen_pointer`.
**Measured:** 24 spec sites read `src/client/screen_target.luau` raw and 5 read `src/render/renderer.luau` raw, against 11 specs that use the helper. Anchors include `tests/chrome_padding_refit.spec.luau:64`, `control_feedback.spec.luau:711`, `foreign.spec.luau:214,266,432,541,608,586`, `instance_park_corpse.spec.luau:48`, `instance_recycling_themed.spec.luau:214`, `preferred_transparency.spec.luau:357`, `reduced_motion_seam.spec.luau:171`, `render_target_contract.spec.luau:133,218,339`, `stage.spec.luau:194,401`, `theme_icons_applied.spec.luau:41`, `theme_layer_application.spec.luau:48`, `touch_gestures.spec.luau:147`, `paint_extensions.spec.luau:37`.
**Failure mode:** these are *pins*. A pin that stops finding the code it names goes **green**. The next extraction out of `screen_target` silently disarms all of them.
**(a) Reuse** `adapter_source.live()` / `renderer_source.all()`. Where a spec genuinely means "only `screen_target.luau`" (a per-file size check), keep the raw read and say so — that is the only legitimate (c) here. Related: `adapter_source.luau` and `renderer_source.luau` are the same module shape (~15 duplicated lines) and `renderer_source.luau:22-23` says so.

### REUSE-94 — `scrollStub` ×6; five return a no-op unsubscribe · High / high
`tests/virtualization.spec.luau:42-60` · `virtual_grid.spec.luau:59` · `virtual_list_axis.spec.luau:55` · `virtual_list_measured_extents.spec.luau:62` · `virtual_list_row_gap.spec.luau:44` · `virtual_list_variable_extents.spec.luau:56`.
**Verified:** `virtualization.spec.luau:46-55` returns a **real** unsubscribe that removes the observer; `virtual_list_axis.spec.luau:60` returns `return function() end`, as do the other four. Any leak or teardown assertion written against those five is vacuous. `tests/virtual_list_row_gap.spec.luau:42-43` states in a comment that it is *"the same seam virtualization.spec uses"* — verified false.
**(b) Extract** `tests/lib/scroll_stub.luau: new() -> { observeScroll, scrollTo, lastPos, observerCount }` with the real unsubscribe and an `observerCount()` so teardown can actually be asserted.

### REUSE-95 — Scenario-fixture world ×9 · Medium / high
`tests/callout_scenario.spec.luau:35` · `menu_scenario.spec.luau:54` · `tab_view_scenario.spec.luau:53` · `row_capabilities_scenario.spec.luau:54` · `row_actions_scenario.spec.luau:25` · `theme_authoring_scenario.spec.luau:39` · `sponsor_scenarios.spec.luau:109` · `nested_compositing_scenario.spec.luau` · `native_style_scenario.spec.luau`. `callout_scenario:35-60` and `menu_scenario:54-79` are line-for-line identical through `built.handle = pres.present(...)`. The `ctx`/`deps` literal is written out in 30 files (44 occurrences).
**Invariant:** the ctx table is the runner's contract (`examples/gallery/scenarios/runner.luau`) — a field added there (`themePackages`, `themeController`, `referenceModules`, `telemetry`, `flags`, `attributes`, `stage`, `facts`) must be added to each spec's hand-written copy or that spec silently tests a degraded scenario.
**(b) Extract** `tests/lib/scenario_world.luau: mount(module, { view, package, flags, themePackages })` layered on REUSE-88's world, constructing the ctx from the *same* field list the runner uses.

### REUSE-96 — `press` ×17 and `settle` ×26 drive helpers · Medium / high
`press(system, key)` (byte-identical) at `tests/responder.spec.luau:37`, `auto_input_screens.spec.luau:33`, `keyboard_navigation.spec.luau:270`, `examples_games.spec.luau:42`, `paradigm_carry.spec.luau:13`, `gallery_chrome.spec.luau:217`, plus ~11 nested copies (`examples_gallery.spec.luau:769,833,905,995,1416`, `sponsor_scenarios.spec.luau:879,931,962`, `paradigm_table.spec.luau:538,647`, `grid_row.spec.luau:473`, `virtual_list_row_actions.spec.luau:2009`). `settle(frames)` at ~26 sites, only the default N differing (6, 8, 90, 120): `callout_scenario.spec.luau:53`, `menu_scenario.spec.luau:72`, `tab_view_scenario.spec.luau:75`, `row_capabilities_scenario.spec.luau:82`, `row_capability_optouts.spec.luau:465,668`, `virtual_list_row_actions.spec.luau:243`, `virtual_list_row_actions_identity.spec.luau:116`, `row_actions_hosted.spec.luau:232`, `row_actions_input.spec.luau:85,1152,1450,3139`, `popup_catcher_paint.spec.luau:119`, `table.spec.luau:2303,3075`, `table_input.spec.luau:1680,1901`, `examples_gallery.spec.luau:474,898,988`, `animation_precedence.spec.luau:40`, `with_animation.spec.luau:44`, `authored_presentation.spec.luau:37`, `overflow_sweep.spec.luau:1062`, `hud_chrome_rotation.spec.luau:124`, `tests/reference/{wardrobe,foyer,glade}_spec.luau`.
**Perf:** `settle(120)` is 240 presenter calls per invocation and several of these files are on `tiers.SLOW`; a shared implementation is the natural place for a "settle until quiescent, cap N" form.
**(b)** fold into REUSE-88's world object as `w.press(key)`, `w.tick(dt)`, `w.settle(frames?)`; the default frame counts stay per-call-site arguments.

### REUSE-97 — Diagnostics assertions ×12 at three fidelities · Medium / high
`assertClean(handle, where)` byte-identical at `tests/instance_recycling.spec.luau:69`, `instance_recycling_themed.spec.luau:41`, `perf_principles.spec.luau:39`, `fine_grained_reactivity.spec.luau:86`, `example_word_game.spec.luau:534` (variant at `large_text_layout.spec.luau:71`). `issues(x)` at `grid_row.spec.luau:82`, `flow_wrap.spec.luau:67`, `container_relative_frame.spec.luau:82`, `grid_column_flow.spec.luau:62`, `grid_measure_arrange.spec.luau:63`. `expectNoDiagnostics` byte-identical (15 lines) at `examples_gallery.spec.luau:2153` and `nested_compositing_scenario.spec.luau:93` — strictly the best of the three (it prints the offending node's rect) and the one with the fewest copies.
**(b) Extract** `tests/lib/diagnostics.luau: expectNone(label, world, handle)` and `format(diags)`, promoting the `expectNoDiagnostics` body. All 12 collapse and every one gains the rect in its failure message.

### REUSE-98 — Virtual-collection fixtures ×19 · Medium / high
`makeRows(n)` byte-identical at `tests/virtualization.spec.luau:22`, `virtual_list_axis.spec.luau:44`, `virtual_list_input.spec.luau:18`, `collection_list.spec.luau:18`, `virtual_list_row_gap.spec.luau:34`, `virtual_list_measured_extents.spec.luau:51`, `virtual_list_variable_extents.spec.luau:46`, `virtual_list_focus_policy.spec.luau:37`, `virtual_list_row_actions.spec.luau:44`, `virtual_list_row_actions_identity.spec.luau:45`. `makeItems(n)` at `virtual_grid.spec.luau:49`, `virtual_hgrid.spec.luau:56`, `virtual_grid_input.spec.luau:29`, `native_scroll_autobind.spec.luau:61`. `bigRows(n)` at `paradigm_table.spec.luau:33`, `table_input.spec.luau:36`, `table.spec.luau:1292,1560`. `newList`/`newGrid` at `virtualization.spec.luau:69`, `virtual_list_axis.spec.luau:76`, `virtual_list_measured_extents.spec.luau:82`, `virtual_list_variable_extents.spec.luau:76`, `virtual_list_row_gap.spec.luau:64`, `virtual_grid.spec.luau:79`.
**(b) Extract** `tests/lib/collection_fixtures.luau: rows(n)`, `items(n)`, `newList(core, opts)`, `newGrid(core, opts)` beside REUSE-94's `scroll_stub`, accepting a superset opts table rather than five near-copies.

### REUSE-99 — Sponsor-scenario trace recorder ×8 · Medium / high
The `trace`/`elapsed`/`note` triple at `examples/gallery/scenarios/sponsor_avatars.luau:31-42`, `sponsor_billboard.luau:35-39`, `sponsor_celebration.luau:35-46`, `sponsor_toast.luau:33-47`, `sponsor_markers.luau:31-35`, `sponsor_list.luau:54-65`, `sponsor_motion.luau:45-56`, `sponsor_drop.luau:62-67`; six also copy the `pres.onFeedback` subscription block verbatim. `drag_session.luau` carries the `trace` half.
**Invariants:** the subscription is `scope:own`ed so dispose unhooks it, and `at` must be the injected `elapsed`, never `os.clock` — stated in every header, and exactly the kind of rule that survives extraction and rots under copying.
**(b) Extract** `examples/gallery/scenarios/trace.luau: new(scope, presenter, clock) -> { note(kind, info), entries() }`.

### REUSE-100 — Theme-install step ×7; only one carries the lesson · Medium / high
`examples/gallery/scenarios/ref_foyer.luau:83-119` and its four identical siblings · `examples/gallery/scenarios/examples.luau:139-193` (`swapPackage` + `uninstallCurrent`) · `theme_authoring.luau:432,1746-1750,1861-1865`.
**The load-bearing invariant lives in one copy:** `examples.luau:130-138` documents a live 2026-08-06 defect — `theme_controller.install` refuses a second controller on an environment that already has one and *returns a reason rather than throwing*, so a loop that ignores the reason silently keeps the first package and a capture pair reads `ornate / ornate`. The five `ref_*` copies uninstall but do not surface the refusal the same way.
**(b) Extract** `examples/gallery/scenarios/theme_axis.luau: new(ctx) -> { install(moduleName) -> { ok, reason, package }, uninstall(), step }`. Subsumed by REUSE-92 for the five `ref_*` files.

### REUSE-101 — `section()` source-slicing ×7, inconsistent inside one file · Medium / high
`tests/theme_icons_applied.spec.luau:46` · `tests/native_style_scenario.spec.luau:157, 233, 339, 425, 495` · `tests/paint_extensions.spec.luau:64`. Within `native_style_scenario`, `:157`, `:233` and `:425` fall back to `chromeSource` when the anchor is not in `source` while `:339` and `:495` do not — the same-named helper behaving differently five definitions apart. `paint_extensions.spec.luau:64` uses the **fixed-length** `string.sub(source, at, at + length)` form that `tests/lib/adapter_source.luau:54-75` documents as the failure mode: *"A pin that fails because somebody EXPLAINED the code is a pin that trains people to delete explanations."*
**(a) Reuse** `adapter_source.bodyOf(source, anchor)`, extended with `between(source, fromAnchor, toAnchor)`, and delete all seven.

### REUSE-102 — Two device matrices claim to be identical and are not · Medium / high
`tests/lib/device_views.luau:16-21` says its rows are *"kept identical to tests/theme_matrix_audit.spec.luau's VIEWS"*. `tests/theme_matrix_audit.spec.luau:106-110` gives `console-ten-foot` `capabilities = { touch = false, mouse = true, keyboard = true, gamepad = true }`; `tests/lib/device_views.luau:53` gives `{ touch = false, mouse = false, keyboard = false, gamepad = true }`. Same viewport row, different input world — a console-only regression can pass one sweep and fail the other. Adjacent: the touch capability literal is written out 17× and the desktop one 20× across `tests/` (e.g. `scroll_indicators.spec.luau:56,67,83,155`, `scroll_window_clip.spec.luau:72`, `reference/glade_spec.luau:703,714,725`, `reference/foyer_spec.luau:163`, `reference/sipworks_spec.luau:169,224`, `adaptive.spec.luau:1754`, `menu_scenario.spec.luau:400`).
**(a) Reuse** `device_views.VIEWS` and `device_views.CAPABILITIES` in `theme_matrix_audit` and at the literal sites. Which console capability set is correct must be decided once — it is currently decided twice, differently.

### REUSE-103 — `fails` ×8, `contains` ×8 (two contracts, one name), `near` ×2 · Medium / high
`fails(fn) -> string` byte-identical at `tests/stage.spec.luau:40`, `presentation_channel.spec.luau:47`, `paint_extensions.spec.luau:54`, `foreign.spec.luau:45`, `fractional_offsets.spec.luau:38`, `button_shape.spec.luau:74`, aliased `refusal` at `traversal_order.spec.luau:317` and `table_virtualized.spec.luau:560`. `testkit` has `toThrow()` but no message-returning form, which is why everyone wrote one.
`contains(haystack, needle)` string form byte-identical at `stage.spec.luau:46`, `paint_extensions.spec.luau:60`, `lifecycle_hooks.spec.luau:93`, `spec_guard_sweep.spec.luau:39`, `foreign.spec.luau:51`, `authoring.spec.luau:33`; **the same name with a different signature** (list form) at `matrix_rows.spec.luau:99` and `gallery_chrome.spec.luau:285` — while `tests/lib/large_text.luau:284` already exports `contains(list, needle)`. Two contracts under one name is a live footgun.
`near(a, b, eps)` at `anchored_surface.spec.luau:374` (6 uses) and `path.spec.luau:18` (15 uses) re-implements `testkit.expect().toBeCloseTo`; `expect(near(x,y)).toBe(true)` fails with "expected false to be true" where `toBeCloseTo` prints both values and the tolerance. `theme_paint_repaint.spec.luau:96` gets it right — its `near` wraps `toBeCloseTo` per channel.
**(b)** add `testkit.expectError(fn): string` and delete the eight; **(b)** `tests/lib/str.luau: contains(haystack, needle)` and rename the two list-form helpers to `includes`; **(a)** use `toBeCloseTo` at the 21 `near` call sites.

### REUSE-104 — Renderer-attach world ×10 · Medium / high
`mountLib.mount` → `fake_target.new()` → `renderer.attach` → `initialRender()` at `tests/renderer.spec.luau:45-50, 345, 405` · `paradigm_tenfoot.spec.luau:20-31` · `native_scroll.spec.luau:50-59` · `paradigm_hover.spec.luau:24-33` · `preferred_text_seam.spec.luau:220-225` · `composition.spec.luau:1144-1152` · `theme_roles.spec.luau:27-35` · `adaptive.spec.luau:401-405`.
**(b) Extract** `tests/lib/world.attach(build, opts)` as a **sibling** of REUSE-88's `new`. Keeping two named world constructors (presented vs attached) is correct — collapsing them into one would obscure which seam a spec is testing.

### REUSE-105 — `fixed` / `fill` Dim shorthands ×21 · Low / high
11 `fixed` + 10 `fill` definitions at `tests/layout.spec.luau:15,18`, `layout_v1.spec.luau:11,14`, `layout_vocabulary.spec.luau:16,20`, `button_complete.spec.luau:24,27`, `grid_row.spec.luau:49,52`, `flow_wrap.spec.luau:48,51`, `text_degrade_cascade.spec.luau:52,55`, `container_relative_frame.spec.luau:60,63`, `lifecycle_hooks.spec.luau:69`, `adaptive.spec.luau:22,25`, `stack_distribution.spec.luau:55,58`, `tests/fixtures/render_fixtures.luau:12,15`. `src` exposes no public Dim constructor.
**(b) Extract** `tests/lib/dims.luau: fixed(px)`, `fill(weight?)`. **Genuine (c) exception:** `tests/layout.spec.luau` and `tests/layout_v1.spec.luau` are *about* the Dim algebra — their locals stand next to hand-written `{ type = "…" }` literals under test, so importing the shorthand there would let a change to the shorthand mask a change to the thing it describes. Keep those two local, with that reason in a comment.

### REUSE-106 — `clip(text, chars)` in both gallery pickers · Low / high
Byte-identical including the comment at `examples/gallery/client/demo_picker.luau:476` and `examples/gallery/client/theme_picker.luau:155`; both exported and asserted separately by `tests/gallery_demo_picker.spec.luau` and `tests/gallery_theme_picker.spec.luau`.
**(b) Extract** `examples/gallery/client/chip_text.luau: clip(text, chars)`, re-exported from both so the two existing specs keep their public assertion target.
*(Related, no action: the `choose(current, …) -> Command` / `mount(opts)` shape in `demo_picker.luau:506`, `theme_picker.luau:194,209`, `settings_panel.luau:86`, `showcase_chrome.luau:140` is a shared convention with different payloads — design, not duplication.)*

### REUSE-107 — Two bench registries share three workload names · Low / medium — **keep separate**
`bench/scenarios.luau` and `bench/perf_scenes.luau` both register `hud-binding-storm` (`:34` vs `:96`), `settings-churn` (`:62` vs `:133`) and `collection-mutation` (`:85` vs `:202`). The bodies are different workloads — `scenarios` is a core bake-off (100 writes, no presenter, ×3 cores); `perf_scenes` is a full-stack scene (50 writes + a refresh, per-phase metrics). Two artifacts (`artifacts/bench.json`, `artifacts/phase-4/perf.json`) and two baselines key on the same three strings.
**(c) Keep separate — merged semantics would differ:** they measure different subjects and merging makes each number unattributable. But the *names* should be disambiguated (`core-…` vs `stack-…`), because "hud-binding-storm regressed" currently does not say which instrument spoke.
*(Otherwise `bench/` is healthy: `perf_scenes.luau:61` reuses `examples/performance/lab/rows`, `perf_profiles.luau:22` reuses `src/preview/device_profiles`.)*

### REUSE-108 — `cloneRows` in a tutorial and in a fixture · Low / high — **keep separate**
`examples/gallery/examples/05_word_game.luau:288` and `examples/gallery/scenarios/row_actions.luau:96`.
**(c) Keep separate — obscures a tutorial, and the semantics differ:** different record shapes (`{letters, submitted, states}` vs `{id, from, subject, preview}`) and different jobs (immutable snapshot per edit vs seed a fresh mail list). `05_word_game` is a teaching file whose family header (`01_temperature_converter.luau:21-29`) commits every example to being readable end to end without cross-imports; sharing would make a tutorial depend on a verification fixture.

### Also checked in this area — not findings
`tests/run.luau` / `run_fast.luau` / `run_one.luau` (`tiers.fullOrder()` parses `run.luau`, so the spec list has exactly one source of truth) · `tests/conformance/cli.luau` vs `corpus_cli.luau` (different suites, different artifacts; a shared runner would obscure which corpus a scorecard came from) · the tutorial examples' `{ title, build(Facet, core, deps) }` contract (a documented contract with 7 conforming implementations).

## H. The RascalRally consumer — mechanisms the framework should own

Wiring is clean: both Rojo projects mount the live framework source
(`games/RascalRally/code/default.project.json:14-15` and
`code/places/debug.project.json:14-15` → `GameStudio/ui/Facet/src` as
`ReplicatedStorage.Facet`); `GameStudio/ui/LuauUI` no longer exists, and the only
surviving `LuauUI` spellings are the deliberate pre-rename attribute fallbacks in
`code/src/client/FacetFlags.luau:32-36`. Note there are **five** flags, not one:
`sponsor` (`~= false`, Facet is the production default) and
`settings`/`garagePilot`/`racerList`/`nativeStyle` (`== true`, opt-in — so for those
three the *legacy* arm is what ships today).

### REUSE-109 — Facet client host bootstrap ×4; three of four freeze the motion clock · High / high
**Responsibility:** stand up a Facet surface on Roblox and drive it per frame.
**Game sites, all hand-rolled and all deep-importing framework internals:** `client/GaragePilotGui.luau:24-27,35-46,94-96` · `client/FacetRacerListGui.luau:14-17,38-49,73-86` · `client/FacetSettingsGui.luau:34-37,78-90` (refresh at `:62,73,219,253`) · `client/FacetSponsor/init.luau:226-228,419-452,1001-1041`.
**There is no framework host to reuse** — verified: no `Facet/src/client/init.luau`. The pieces are `src/client/roblox_env.luau:15`, `src/client/screen_target.luau:263`, `src/init.luau:151-157`, `src/client/motion_driver.luau:70-90`, `src/present/presenter.luau:3645` (`refresh`) and `:3957` (`tick`, which steps the motion clock at `:3970`).
**Verified live consequence:** `presenter.tick` is called at **exactly one** place in the game — `FacetSponsor/init.luau:1003` (plus a one-off drain at `:2934`). `GaragePilotGui.luau:94-95`, `FacetRacerListGui.luau:73-85` and `FacetSettingsGui.luau:62,73,219,253` call **only `refresh()`**, so on those three surfaces the motion clock, the toast schedule and every transition are frozen. All three also use `Heartbeat`, which `src/client/motion_driver.luau:10` states is the wrong signal ("Heartbeat runs after render… adds a frame of latency"); only FacetSponsor uses `PreRender` (`:1037`) and documents why (`:996-999`).
**The root cause is framework-side, and verified:** `docs/guide/03-getting-started.md:236-237,252-255` teaches exactly `RunService.Heartbeat:Connect(function() presenter.refresh() end)`, and **`presenter.tick` is never mentioned anywhere in `docs/guide/*.md`**. All three framework examples reproduce it — `examples/gallery/client/init.client.luau:715`, `examples/table_phaseb/client/init.client.luau:146`, `examples/performance/client/init.client.luau:221` — the last of which carries a comment at `:198` saying PreRender "is where it belongs (Heartbeat runs AFTER render…)" immediately above a `Heartbeat` connection.
**(b) Extract** `Facet/src/client/init.luau`: `host.new({ nativeStyle?, style?, parent?, now? }) -> { core, env, presenter, adapter, inputSystem, dispose }`, binding env, building adapter + input system, and driving **both** `tick(dt)` and `refresh()` on one `PreRender` connection. Adopters: the four game sites, the three examples, and the guide. Fixing the guide without the host leaves four hand-rolled hosts free to drift again.

### REUSE-110 — Reduced motion has three authorities; the player's setting reaches ~3 of ~44 sites · High / high
**Three sources of one truth:** (1) raw `GuiService.ReducedMotionEnabled` — **44 reads across 14 client modules** (verified), always-on ones including `ItemFx.luau:412-414`, `ItemOutcomeFx.luau:495,523,567`, `KartStateFx.luau:65-67`, `ShowrunnerPillGui.luau:72-74`, `SocialBannerGui.luau:203`, and legacy-arm ones across `SponsorGesture`, `SponsorCelebration`, `SponsorRacerList`, `SponsorResults`, `SponsorGui`, `SponsorWidgetKit`, `SponsorController`. (2) `shared/ReducedMotion.luau:29-34` (explicit override > system), read at only `SponsorResults.luau:2176`, `SettingsGui.luau:86-88`, `FacetSettingsGui.luau:50-70`. (3) Facet's `env.derived.motionPolicy` (`src/env/environment.luau:193`, fed by `src/client/roblox_env.luau`), read at `FacetSponsor/OmenState.luau:615`, `StoryFlow.luau:667,691,708,743`, `ResultsScreen.luau:707`.
**Verified consequence:** `env:set("reducedMotion", …)` appears **zero** times in the game. A player who enables Reduce Motion in the game's own Settings screen is honored by roughly three surfaces and ignored by the other forty-plus — including the entire production-default Facet Sponsor, whose motion policy reads the engine flag only.
**(b) Extract** an app-preference hook on the framework's binding seam: `roblox_env.bind(env, { reducedMotion: (() -> boolean?)? })`, composed over the engine flag inside `pushAccessibility`. The game calls it once with `ReducedMotion.isEnabled`; the direct reads then retire onto `env.derived.motionPolicy`. The framework cannot own the game's settings store, but it must own the composition.

### REUSE-111 — Spring solver and motion-class registry duplicated wholesale · High / high
`games/RascalRally/code/src/shared/Spring.luau` vs `Facet/src/motion/spring.luau`: same `MAX_DT = 0.1` (`:42` vs `:39`), `MAX_SUBSTEP = 1/120` (`:43` vs `:40`), `DEFAULT_EPS = 1e-3` (`:51` vs `:46`), same semi-implicit Euler, near-verbatim headers. `client/SponsorMotion.luau:29-32` (`panel 1.0/0.35`, `card 1.0/0.28`, `pop 0.7/0.18`, `fade 1.0/0.5`) is byte-identical in value to `Facet/src/motion/classes.luau:47-52` (`container`, `object`, `reward`, `decay`) — two registries, one set of numbers, different names.
**18 call sites, and not all legacy:** `ItemFx.luau:410,458,459` and `ShowrunnerPillGui.luau:174` are **always-on**; the remainder are the legacy Sponsor arm (`SponsorGui.luau:879,2087`, `SponsorRacerList.luau:1163`, `SponsorGesture.luau:232,1266-1268,1356-1357,1672-1673`, `SponsorResults.luau:1298,1528`, `SponsorCelebration.luau:534`).
**(a) Reuse** `Facet.motion.newClock` + `resolveClass("object"|"reward"|…)` at the two always-on callers and in `SponsorMotion`. **(c)** for the legacy Sponsor call sites only — the authorized rollback arm per the root `CLAUDE.md`. `shared/Spring.luau` and `SponsorMotion.luau` become deletable once the always-on callers move.

### REUSE-112 — `AVG_GLYPH_FRACTION = 0.62` copied into the game five times, beside the real measurer · High / high
**Game copies:** `FacetSponsor/TableMetrics.luau:887` (plus a `LINE_HEIGHT_FACTOR` twin at `:1052`) · `FacetSponsor/StartCountdown.luau:76` · `FacetSponsor/RolePickScreen.luau:134` · `FacetSponsor/ResultsParts.luau:427` · a bare inline `0.62` at `ItemFx.luau:901`. Estimate call sites: `TableMetrics.luau:908,912,1021`, `StartCountdown.luau:98`, `RolePickScreen.luau:200,247,279`, `ResultsParts.luau:450,520,1096`, `ItemFx.luau:899-901`.
**Framework:** the constant is `src/layout/text_metrics.luau:23,25`, and the real answer is `Facet.text.fit/size/facts/lineBox` (`src/layout/text_fit.luau:112,174,241,302`). `src/init.luau:308-325` states these were exported *specifically* to end this: "three private approximations of the same 0.62 fallback constant had grown in one game."
**Sharpest anchor:** `ItemFx.luau:95` imports `Facet.text.size` and `ItemFx.luau:901` hand-estimates — two answers to "does this fit" in one file.
**(a) Reuse** `Facet.text.size{…}` / `text.fit` at every site; where the caller wants "largest size that fits this box", that *is* `text_fit.fit`.

### REUSE-113 — Device-chrome facts re-derived 5× and watched 13× · High / high
**Value half** (`GetInsetArea(TopbarSafeInsets).Min − GetInsetArea(None).Min`): `ShowrunnerPillGui.luau:209-213` · `SponsorGui.luau:1022-1028` · `SettingsGui.luau:204-211` · `FacetSettingsGui.luau:179-185`, plus the `DeviceSafeInsets` sibling at `SponsorResults.luau:715-720`. **Already drifted:** `ShowrunnerPillGui.luau:209-213` computes only `clusterOffsetX` and never the Y offset the other three compute, so the objective chip is vertically misplaced on any device reporting a non-zero topbar-safe Y.
**Change-signal half** (`camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)` + manual disconnect), 13 independent copies: `DebugHud.luau:305` · `DriverHints.luau:186` · `FtueDriverFx.luau:143` · `ItemFx.luau:523` · `ItemOutcomeFx.luau:297` · `RaceHud.luau:275` · `SocialBannerGui.luau:140` · `SettingsGui.luau:225` · `FacetSettingsGui.luau:196` · `ShowrunnerPillGui.luau:188` · `SponsorResults.luau:507` · `SponsorFtue.luau:221` · `SponsorGui.luau:1181`.
**The framework already owns both** — `src/client/roblox_env.luau:59-70` (the conversion) and `:181` (the signal), published as `topbarSafeInsets` / `platformChrome` (`src/env/environment.luau:47,305`). Proof the fact is correct and sufficient: `FacetSponsor/init.luau:1286-1305` documents migrating off its own hand-derivation onto `platformChrome`. The other five cannot follow because they are plain `ScreenGui`s with no env — the fact is only reachable through a mounted Facet surface.
**(b) Expose the pure half core-free:** `src/client/screen_chrome.luau` gains `read() -> { viewport, band, insets, bandInsets }` and `observe(fn) -> () -> ()` over one shared connection set. Adopters: the 5 value sites and the 13 listener sites.

### REUSE-114 — The racer list exists three times, with two finish latches and three badges · High / high
**Latch:** `SponsorRacerList.luau:175,661,708-712` and `FacetSponsor/SemanticModel.luau:524,1030,1048-1051` each hand-roll `_finishedPlace` gated by `SponsorListModel.finishLatchArmed` — `SemanticModel.luau:1045` even cites the other copy by line. `FacetRacerListScreen.luau:34` + `FacetRacerListGui.luau:55` instead use `shared/FinishOrder`, which is also the *server's* authority (`shared/KartRaceScore.luau:163`). Three clients, two latch semantics, one of which disagrees with the server.
**Badge:** a colour swatch (`SponsorRacerList.luau`), a family colour (`FacetSponsor/RacerList.luau:281`), and an avatar headshot via `rbxthumb` (`FacetRacerListScreen.luau:113-127`) whose comment at `:110-112` claims it matches "the old list's convention" — it does not.
**Collection primitive:** `Facet.newTable` (`FacetRacerListScreen`) vs `Facet.newVirtualList` (`FacetSponsor/RacerList`) — which is also why REUSE-10's live anchor bug reaches this screen.
**(a) for the latch** — both hand-rolls call `shared/FinishOrder`. This is correctly a *game* module: the framework must not learn about laps, so extracting it upward would be a dependency reversal. **(b) for the badge** — `Facet/src/controls/async_image.luau` already models pending/ready/failed for exactly this and **nothing in the game uses it**; publish the initial-fallback form as a documented recipe.

### REUSE-115 — 13 game modules own a per-frame loop across three RunService signals · Medium / high
`GaragePilotGui.luau:94` · `FacetRacerListGui.luau:73` · `FacetSponsor/init.luau:1037` · `SponsorFtue.luau:417` · `SponsorGesture.luau:123,640,1359,1700` · `ItemOutcomeFx.luau:315,323` · `InputBridge.luau:330` · `PredictProbe.luau:182` · `DbgMinNet.luau:61` · `MinClient.luau:437` · `AssistPilot.luau:155` · `ItemAudio.luau:667` · `init.client.luau:929` — a mix of `RenderStepped`, `Heartbeat` and `PreRender` for what is conceptually one UI frame.
**(b)** folds into REUSE-109: one host, one `PreRender` connection, subscribers.

### REUSE-116 — Settings pair: ~130 lines of dock chrome duplicated, plus a positional binding · Medium / high
`FacetSettingsGui.luau:105-203` vs `SettingsGui.luau:117-234` — same `ScreenGui`, same `GearDockModel.placeLocal`, same inset belt, same rebind-camera dance; `FacetSettingsGui.luau:10-13` admits it ("IDENTICAL chrome, kept as plain instances").
**Drift:** `FacetSettingsScreen.luau:43,48,51` binds `view.entries[1]` / `entries[2]` **by position** where `SettingsGui.luau:435,438` dispatches by `SettingsModel.ENTRY_REDUCED_MOTION` / `ENTRY_HOW_TO_PLAY` **by id** — inserting a settings row silently mislabels the Facet arm.
**(a)** for the id binding (use the same constants — a game-owned module, correctly game-owned). **(b)** for the dock chrome: it is REUSE-113's `screen_chrome` seam plus `screen_target.new({ displayOrder })` from REUSE-122.

### REUSE-117 — Four surface-plate recipes, a triplicated ribbon, 15 corner-radius values · Medium / high
`DriverHints.luau:97-114` (radius `0.5`, `AutomaticSize.X`, 24px H pad, no V pad) vs `FtueDriverFx.luau:77-95` (radius `0.5`, fixed size, `PILL_PAD_X/Y` on all four sides) — same `Color3.fromRGB(10,10,16) -- surface-scrim` comment, same `Active/Selectable = false`, same "hidden until faded in", two sizing models. Third and fourth: `ShowrunnerPillGui.luau:91-116` (radius `0.28`, two `UIStroke`s) and `SocialBannerGui.luau:58-76` (radius `0.14`, one stroke, `ZIndex 35`). Client-wide there are **15 distinct `CornerRadius` values**.
**The ribbon is triplicated and the source asks for the fix:** `SponsorFtue.luau:149-232` · `SocialBannerGui.luau:58-130` (its own header at `:7,13` calls itself "a FACTORED TWIN") · `FacetSponsor/MessageLayer.luau:15-22`, which documents the twin and explicitly requests this extraction.
**The framework owns the vocabulary:** `src/tokens/tokens.luau:16-18` (`surface`/`surfaceStrong`/`accent`), `src/tokens/styling.luau:315-333` (`TINT_ROLES`, `hairline`), `styling.luau:104-105` (named radii).
**(b) Promote** `MessageLayer.ribbon` into `src/controls/banner.luau` with `build({ form, head, sub, badge?, alignV })`; the four plate sites adopt `UI.Box{ surface = … }` plus a named radius token.

### REUSE-118 — Hand-rolled keyed reconciler and transient banner in the always-on HUD · Medium / high
`RaceHud.luau:540-620` is create-on-first-sight-by-key / tween-to-slot (`:555`) / remove-when-absent, repeated for minimap dots at `:653-695`; `SponsorRacerList.luau:200-310` is the same shape. Facet owns keyed reconciliation (`UI.ForEach`) and `src/render/transitions.luau`. `RaceHud.luau:591` (`AbsoluteSize.X < 200 → shortName`) is the `compactLabel` decision Facet owns at `src/blueprint.luau:339,1154`. `RaceHud.luau:470-496` is a hand-rolled transient banner whose own comment documents the exact bug ("the countdown died at 2") that `src/present/toast_schedule.luau:12-23`'s read-floor and supersede rules prevent mechanically.
**(a) Reuse** across the board once `RaceHud` is ported. Recorded now because the always-on HUD is the surface a player sees every race.

### REUSE-119 — The Facet arm produces no UI sound and no haptics · Medium / high
14 `UiSound.haptic` sites live in the always-on and legacy arms (`ItemFx.luau:1069,1159,1277,1419`, `ItemOutcomeFx.luau:699,764`, `ShowrunnerPillGui.luau:308`, `SponsorResults.luau:2225,2493,2777`, `SponsorCelebration.luau:822,900`, `SponsorGui.luau:2074`, `DebugHud.luau:211`). **Zero `UiSound` calls exist anywhere under `client/FacetSponsor/`.** `FacetSponsor/init.luau:2251` does subscribe `handle.onFeedback`, but routes it only to `PlayFlow` counters and a log (`PlayFlow.luau:609-631`). Facet ships `src/client/haptics.luau` as the ready-made feedback→haptics adapter and the game never requires it.
**(a) Reuse:** subscribe `presenter.onFeedback` → `UiSound.play/haptic` once in REUSE-109's host, and bind `Facet.client.haptics` for the button-press property route. The verbs already reach the seam; only the last hop is missing.

### REUSE-120 — External-observable→Signal adapter ×3 shapes, no framework owner · Medium / medium
`FacetSponsor/bridge.luau:53+` (one `core:signal` per external cell, one subscription, one `dispose`), plus two more shapes of the same idea at `FacetSponsor/FtueSource.luau:42-59` and `FacetSponsor/runtime.luau:69-93` (`lazyAttrReader`). `Facet.replication` (`src/replication/adapters.luau`) is revision/patch-based and solves a different problem.
**(b) Extract** `Facet.fromExternal(core, { get, subscribe }) -> Readable` at the core layer — the `useSyncExternalStore` equivalent, scope-owned. Adopters: `bridge.luau`, `FtueSource.luau`, and the ~20 `GetAttributeChangedSignal` adapters in `SponsorController.luau` (33 sites), `SponsorResults.luau` (27), `ItemFx.luau` (17).

### REUSE-121 — Blueprint node identity is a hand-maintained path string; 17 `PATHS` tables · Medium / medium
`FacetSponsor/{ChipRow:50, MapCanvas:105, RacerList:97, HandDock:124, HudScreen:98,295, TableScreen:97, ResultsScreen:143, RolePickScreen:98, FollowScreen:56, MessageLayer:41, FtueLayer:33, BeatLayer:39, Ticker:48, OmenBillboard:123, StartCountdown:102}` plus `FacetSettingsScreen.luau:118` and `FacetSponsor/init.luau:2211`. These encode framework-owned structure — e.g. the `/then/` segment a `When` branch inserts (`MessageLayer.luau:44`). Facet's public surface is path-string-based throughout (`presenter.luau:2646,2820,2858`, `screenRectOf`) with no builder and no compile-time check.
**(b) Extract** a `UI.path(...)` builder, or return a handle at declaration, so a structural rename is a compile error rather than a silently dead path. Confidence medium: this is a design change, not a mechanical extraction, and belongs in a decision packet rather than a cleanup.

### REUSE-122 — Cross-surface z-order has no owner; Facet roots default to the bottom · Medium / high
17 hand-made `ScreenGui`s in the client, with `DisplayOrder` as scattered magic numbers: `DbgMinNet.luau:32` (90) · `PredictProbe.luau:84` (95) · `DebugHud.luau:18` (100) · `FacetSettingsGui.luau:110` (100) · `SettingsGui.luau:122` (`gui.DisplayOrder + 1`) · `EffectGlow.luau:125`. Facet creates its roots with `DisplayOrder` **unset = 0** (`src/client/screen_target.luau:1000-1016`), `screen_target.new` has no `displayOrder` option (`:263`), and `adapter.setRootDisplayOrder` (`:2044`) is never called by the game — so every native game surface floats above every Facet surface by default.
**(b) Add** `displayOrder` to `screen_target.Opts`, so the consumer can state the layering instead of discovering it.

### REUSE-123 — Three input models the framework already extracted, still live in the game · Low / high — **keep separate (for now)**
`shared/DragVelocity.luau` (whole file, `WINDOW_S = 0.1` at `:26`) vs `src/input/drag_velocity.luau:32`, exported as `Facet.newDragVelocity` (`src/init.luau:237`) — the framework copy adds finite guards (`:40-42,65-67`) the game copy lacks, so a NaN sample poisons the game's velocity straight into a spring. `SponsorGesture.luau:97-98` (`14`/`6` px) vs `src/input/interaction_tokens.luau:30-31`. `SponsorGesture.luau:723-830` vs `src/input/autoscroll.luau`, whose own header at `:37` cites `SponsorGesture:762-770` as its source. The sole caller of each is the legacy Sponsor arm (`SponsorGesture.luau:58,196`).
**(c) Keep separate — an explicitly authorized policy:** the root `CLAUDE.md` states the legacy Sponsor modules stay shipped and untouched as the `UseLuauUISponsor = false` rollback arm. But the three *modules* are now dead-code-in-waiting: record in the migration doc that `shared/DragVelocity.luau` is deleted when the rollback arm retires, so the two 0.1 s windows cannot drift meanwhile.

### REUSE-124 — Boot-readiness is a game-invented viewport spin loop · Low / high
`init.client.luau:754-760` busy-waits on `RenderStepped` until `ViewportSize > 1×1`, because `environment.set` refuses a placeholder viewport while `roblox_env.bind` pushes one at bind time. The comment at `:744-753` reasons it out correctly, but this is framework knowledge living in a game file — and it guards only the FacetSponsor construction, not the three later Facet surfaces.
**(b)** `roblox_env.bind` should defer its first push until the viewport is real, or expose `roblox_env.awaitViewport()`. Related to the 1×1 first-frame class the framework has already paid for once.

### REUSE-125 — Studio-only preview modules ship to every production client · Low / high
Both Rojo projects mount all of `src/` (139 modules), including `src/preview/device_profiles.luau`, `src/preview/matrix_rows.luau` (a Studio device-matrix selection policy, required only by `src/client/edit_preview.luau:21`) and `src/client/edit_preview.luau` itself. Nothing in the runtime graph reaches them.
**(b)** either a production subtree, or a documented `globIgnorePaths` line in the framework's integration guide. A distribution question rather than a duplication one, recorded because it is the consumer boundary this audit covered.

### What the consumer already does right — worth protecting
`shared/HudZoneModel` is genuinely single-sourced across 12 modules; `shared/MinimapModel`'s projection math is shared rather than copied; `shared/GearDockModel` is shared across both settings arms; `FacetFlags.luau` puts each flag's *predicate* next to its name so no caller can write `== true` where `~= false` is meant; and the game carries ~40 `facet_*_contract.spec.luau` consumer contract tests among its 212 spec files.

## Also checked across `src/` — not findings

- **`billboard_target` vs `screen_target`** — `src/client/billboard_target.luau` (131 lines) is a `rootFactory` swap over `screen_target.new` plus four deliberate seam removals (`:100-121`). No instance-creation, property-application, lifecycle or teardown machinery is copied.
- **The `screen_*` family** (`screen_paint`, `screen_pointer`, `screen_presentation`, `screen_scroll_indicators`, `screen_chrome`) — every header states these are extractions from `screen_target.luau` forced by the 200k `Source` write cap, each strictly one-way. Decomposition, not duplication; the only cross-module repeats are REUSE-54, REUSE-60 and REUSE-62.
- **The `row_actions_*` seven-file split** — same reasoning, same cap; every header states the shared test ("it shares nothing mutable with the engine"). The duplications that *do* live inside the family are REUSE-6, REUSE-13, REUSE-14 and REUSE-22.
- **Five contract modules** (`core/contract`, `controls/contract`, `render/target_contract`, `input/drag_contract`, `blueprint_schema`) — distinct responsibilities and distinct error mechanisms (types-only / lookup / result-record / `error(…, 0)` / `reject`). No shared validation machinery beyond REUSE-5 and REUSE-7.
- **`scope_impl` is already the shared owner** — required by all three cores (`custom.luau:77`, `imperative.luau:27`, `fusion_adapter.luau:27`); `async/resources.luau` uses `scope:own` correctly. No parallel "own and clean up" implementation exists.
- **`env/environment.luau` vs `client/roblox_env.luau`** — a clean model/binding split. **`render/presentation_channel.luau` vs `client/screen_presentation.luau`** — renderer-side composer vs adapter-side writer.
- **Four per-class registries** (`blueprint_schema` CLASSES / `render/authority` MANIFEST / `controls/contract` CONTROLS / `blueprint` prop→dirty) — the split is documented at `controls/contract.luau:3-5` and cross-checked by `tests/conformance/controls_registry.luau`; schema, authority, semantics and invalidation are four different questions about one prop.
- **Present-layer queues are already unified** — `src/present/callout_queue.luau` is a *driver* over `src/present/toast_schedule.luau` (`callout_queue.luau:170-188`, header `:12-18`), and `presenter.presentToast` (`:3913-3941`) is a second driver over the same model. One scheduler, three drivers.
- **Spatial navigation is not duplicated** — `src/input/spatial.luau` is a 3-D pointer-event contract (`:5-10` opens "Facet does not support VR"), not directional focus movement; `focus_graph.luau:933-995` navigates by index into declared orders, never by rect scoring.
- **Velocity tracking is already unified** — `src/input/drag_velocity.luau` is the single tracker (`drag_registry.luau:495,564,610,814`; `row_actions.luau:2367,2621`).
- **Timers** — everything rides `presenter.tickBody` (`presenter.luau:3963-4024`); no stray `RunService`/`task.delay` in `present/`, `motion/`, `focus/`, `input/`.
- **`text_reveal` vs `value_reveal`** — a travelling-strip marquee vs a hold-then-count epoch machine; no shared code or shape. Separate note: `value_reveal` is exported (`src/init.luau:298`) with **zero consumers** in `src/`, `examples/` or the game — a dead-export question, not a duplication one.
- **`rating` over `level_picker`** and **`contract.enabledNow` across five controls** — correct reuse, recorded as the model the other findings should follow.
