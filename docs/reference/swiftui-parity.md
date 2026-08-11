# SwiftUI ↔ LuauUI capability audit and selected control inventory

> **2026-07-22 Roblox correction:** Read
> [`../plans/roblox-native-audit-corrections.md`](../plans/roblox-native-audit-corrections.md)
> with this inventory. Roblox has `UIDragDetector`, per-`GuiObject` touch gesture
> events, `Path2D`, and `UIPageLayout`; older feasibility notes must not be used
> to justify rebuilding those engine behaviors.

**Report only.** No library, example, or test code was changed to produce this document.

| | |
|---|---|
| LuauUI version | `0.9.0` (`src/init.luau:90`) |
| Audit date | 2026-08-11 — full fresh re-audit: nine independent fresh-context passes, one per area (state & reactivity, layout, controls, styling, input & accessibility, motion, performance, presentation, tooling), each verdict evidence-cited against HEAD `fff48b2` on `luauui/row-actions` |
| Prior audit | 2026-07-22 validation of the 2026-07-21 source inventory, against `v0.5.0` — superseded by this revision |
| SwiftUI baseline | Shipping surface plus Apple's **June 2026 / Xcode 27** update (WWDC26 / iOS 27) |
| LuauUI baseline | source only — `src/blueprint.luau`, `src/init.luau`, `src/controls/`, `src/layout/`, `src/render/`, `src/present/`, `src/client/`, `src/motion/`, `src/themes/`, `src/input/`, plus `tests/conformance/controls_registry.luau` |
| Area audits (source of every claim below) | `.superpowers/sdd/row-actions-implementation/audit/{state-reactivity,layout,controls,styling,input-a11y,motion,performance,presentation,tooling}.md` — nine fresh-context passes, synthesized here without inventing or softening any claim |

This document is not a percentage. It is a selected control and container
catalog plus nine cross-cutting area audits. SwiftUI also supplies an
authoring model, environment propagation, accessibility behavior, previews,
animation, presentation, gesture composition, and diagnostics; those
qualities, not a row count, decide whether a framework delivers "write the UI
once" — especially for agent-authored code. The status scale, its
anti-inflation rules, and the standing physical-device rider are in §1 below
and are unchanged in spirit since the first audit.

**Verification commands** (all run live for this report; results folded into
the sections below and cited per-claim):

```bash
cd GameStudio/ui/LuauUI
./run-tests.sh                                   # 4038 passed, exit 0
lune run tools/lune/check_registration_cli       # PASS (16 controls, 87 exports documented,
                                                  #   153 specs registered, 15/15 four-input + paradigm)
lune run tools/lune/check_boundary                # PASS (97 src files, 379 consumer files)
lune run tests/conformance/corpus_cli             # a11y-l10n-corpus: 15/15 passed
lune run tools/lune/check_docs_cli                # PASS (8 documents, 77 surface anchors, 64 local links,
                                                   #   7 themes exports documented, 11 stale phrases absent)
lune run tools/lune/check_prop_parity_cli         # PASS (25 classes, 438 properties, 2 diagnosed)
python3 tools/check_manifest_integrity.py         # 650 suite greps, all anchored to the pass marker
python3 tools/check_row_actions_matrix.py         # row-actions gate PASS at re-baselined ceilings
```

---

## 1. Changed since 2026-07-22 — executive summary

The single biggest theme of this cycle: **six items the July audit filed as
"here's a recipe" are now first-class, exported, four-input-proven
composites**, a new screen-level adaptation container shipped that SwiftUI
has no single built-in equivalent for, native theming went from nothing to a
complete capability class, and — the mission's headline delta — **generalized
`swipeActions` moved from Missing to Partial** with a real, gated, honestly-limited
construct. Several claims the July doc still carried were independently found
**stale** by this cycle's area audits; they are corrected below, named
explicitly, not silently dropped.

### Headline flips

| Claim (2026-07-22) | Now (2026-08-11) | Area |
|---|---|---|
| Generalized `swipeActions` — **Missing** | **Partial** — `LuauUI.newRowActions`/`newRowActionsCoordinator`, real public composites, four-input-proven (tray reveal, full-swipe commit, keyboard Delete/Backspace, Shift+Return + gamepad ButtonX menu, one-open coordinator, hot-switch CARRY/CANCEL). Named residual gaps: scroll-cost regression re-baselined not closed (+57%/+81% scroll/fling, +5 instances/row vs the original ≤5%/≤4 plan budget — director-ruled 2026-08-11), no RTL (explicit non-goal), no mouse secondary-click/touch long-press trigger for the menu | §3.3 Controls, §5 |
| Slider / Stepper / segmented+inline Picker / determinate ProgressView / Label / DisclosureGroup — **Composable** (recipes) | **Partial** — six real, exported, four-input-proven composites (`newSlider`, `newStepper`, `newPicker`, `newProgressView`, `newLabel`, `newDisclosureGroup`). `Picker`'s two old recipes unify into one adaptive composite that auto-resolves segmented↔inline from option count/`sizeClass`/label length | §3.3 Controls |
| `UI.Grid`/`ViewThatFits`-class whole-screen adaptation — **Missing** | **`UI.Composition` + `UI.Region` (ADR-0023) — new, Available.** A screen declares ranked regions, each with an ordered richest→minimum-viable form ladder; the framework legality-tests arrangements and steps down/drops by rank — closer to a full `Layout` protocol + `layoutPriority` combined than SwiftUI ships as one construct. Proven across all 5 Step-11 reference apps with zero device-name branches | §3.2 Layout |
| ScrollView — **Partial, weakest container** (does not scroll, does not clip, no engine `ScrollingFrame`, `axis="x"` silently broken) | **Available** — real `ScrollingFrame` host (native-substrate stage), correct `axis="x"`, scroll-indicator policy, drag-to-edge autoscroll. The single most-cited weakness in the July product-quality table is substantially closed | §3.2 Layout |
| Incremental layout — **absent, one bound change re-solves the whole tree** | **Shipped ON by default.** A single bound-value change now costs 141→8 arranged nodes (~17×) in the measured Studio surface, closing a real performance-correctness gap with a differential-fuzz-caught history | §3.2 Layout, §3.7 Performance |
| Modifier-aware keyboard bindings — did not exist | **New.** `action.bind(..., { modifiers = { shift = true } })` compiles to two real `InputBinding`s (`PrimaryModifier`); first shipped consumer is row-actions' Shift+Return menu, no double-fire vs plain Return | §3.5 Input & Accessibility |
| Floating/non-descendant presenter surfaces for a composite — no named seam | **New public contract: `bindPresent`.** RowActions' menu measures as **zero contribution** to any ancestor's box (a pinned test asserts a sibling row's solved rect is byte-identical whether the menu is open or not) — closes the exact RED-TEAM-caught defect where the first implementation inflated its own row/list. Reusable by any future secondary-surface composite | §3.3 Controls, §3.8 Presentation |
| Semantic feedback event surface — **"No public semantic feedback event surface"** | **`src/present/feedback.luau` — Composable/Available.** A closed 12-verb taxonomy (`activate, select, adjust, pickup, commit, reject, cancel, arrive, land, dismiss, supersede, celebrate`), causal-frame-synchronous, "LuauUI plays nothing" by design, **live-consumed in production by RascalRally** (`games/RascalRally/code/src/client/LuauUISponsor/PlayFlow.luau:609`) | §3.5 Input & Accessibility, §3.8 Presentation |
| Native theming — did not exist | **Entirely new capability class** (ADR-0018/0019/0020): StyleSheet-backed Dark/Light swap with no remount; theme packages owning typography/metrics/insets/chrome with a single-transaction swap preserving focus/scroll/mount identity; rich/image-driven skinning (layered art, per-state art, value-display hosts, pixel mode). This is the largest capability delta in the Styling area | §3.4 Styling |

### Stale claims this cycle caught and corrects

The July doc carried these forward by inertia rather than a re-check against
current code. Each is corrected here, not silently dropped:

1. **"`sizeClass` is consumed by nothing in `src/`."** False today. Sixteen-plus
   call sites (`renderer.luau`, `layout/adaptive.luau`, `presenter.luau`,
   `table.luau`, `text_input.luau`, `rating.luau`, `row_actions.luau`,
   `theme_controller.luau`, `hint.luau`, `popup_button.luau`, `picker.luau`)
   contradict the old claim. It was true at v0.5.0 and is false at v0.9.0. —
   §3.1 State & Reactivity, §3.3 Controls.
2. **"Every style hint is mount-time-only... a reactive `surface`/`role` write
   is silently dropped."** Fixed under "Milestone 0 (swiftui-parity-next
   investment 1)": `renderer.luau`'s `STYLE_PROPS`/`STYLE_PROP_ORDER` re-apply
   on every reactive change, and the live paint/semantics dirty loop dispatches
   to `applyStyleProp`. The July doc's own §7.2 text never caught up to this
   fix. — §3.4 Styling.
3. **"`GuiService.SelectedObject`... is deliberately NOT driven" (ADR-0014).**
   It IS driven now — opt-in, modal-only, `presentModal({ engineSelectionBridge
   = true })`, with explicit `Selectable` restore-on-move-off. ADR-0014 itself
   is the stale artifact; it was never updated after its own requested probe
   (NS-M9, 2026-07-23) ran and shipped. This does **not** touch VoiceOver/
   TalkBack — the assistive-technology headline finding is unchanged. — §3.5
   Input & Accessibility.
4. **"No secondary-action model" (§12, 2026-08-08 reference-app validation).**
   Corrected in place in §12 below: row-actions now delivers a real
   cross-input secondary-action model for 3 of 5 named mechanisms (swipe,
   keyboard, gamepad — not mouse secondary-click or touch long-press). — §3.3
   Controls, §3.5 Input & Accessibility, §5.

### Also new since 2026-07-22 (not headline flips, but material)

- **General drag/drop contract** (`UI.draggable`/`UI.dropTarget`,
  `src/input/drag_contract.luau`, `drag_session.luau`, `drag_registry.luau`):
  broad native `UIDragDetector` adoption unifying pointer/touch/keyboard/
  gamepad acquisition behind one session lifecycle — the July doc's own §6.3
  recommendation ("Roblox `UIDragDetector` should own supported acquisition")
  is now the delivered design, not an open recommendation.
- **Touch-gesture normalization + arbitration layer** (`src/input/touch_gestures.luau`,
  `LuauUI.touchGestures`): real, tested, adapter-wired, publicly exported —
  but **zero shipped controls consume it yet**. `.contextMenu`'s presentation
  half (an action-list menu) is proven buildable by RowActions' own menu; its
  trigger half (long-press/secondary-click) is still unwired.
- **Toasts** (`presenter.presentToast`) and **`UI.Divider`** as a real
  axis-aware leaf (not a `Box{height=1}` recipe) both shipped since baseline.
- **Strict spec validation** — the July doc's own named top priority ("reject
  unknown properties") shipped and was independently reproduced live this
  session (`UI.Button({ lable = "hi" })` → named property + did-you-mean +
  full valid-set enumeration).

---

## 2. Status scale

| Status | Means |
|---|---|
| **Available** | A first-class equivalent exists, is exported, and its conformance tests pass. |
| **Partial** | It exists, but with named behavior gaps that a consumer will hit. Per `ui_todo.md:3-13`, **anything that works on only some input classes is Partial at best** — "a control that only works with a mouse is an unfinished control". |
| **Composable** | Not shipped as a construct, but buildable today from the existing public surface with no framework change. The recipe is named where relevant. |
| **Missing** | No construct and no honest recipe. A Roblox-engine feasibility note is given where one exists. |

Two anti-inflation rules apply throughout, unchanged since the first audit:

1. A control whose *reachability* is proven on four inputs is still **Partial** if its *paradigm* idiom is incomplete (ADR-0016, `docs/adr/ADR-0016-three-axes-contract.md:15-18`).
2. **Nothing** in LuauUI has been confirmed on physical hardware. Every four-input claim below rests on headless Lune + Studio MCP drives. This standing rider is reconfirmed, unchanged, by every one of the nine area audits and is restated with fresh riders in §6.

Engine-feasibility verdicts use three grades: **engine gives it to us** (the platform supplies the primitive; a library gap), **engine makes it hard** (possible but needs a spike/workaround), **engine makes it impossible** (no reachable API).

---

## 3. Area re-audits (2026-08-11, fresh context per area)

Each subsection is one of the nine commissioned area audits, carried forward
with its own verdict table intact and its citations preserved. Prose around
each table is intentionally minimal; the evidence lives in the `file:line` /
test citations, not in restated narrative. Full source files:
`.superpowers/sdd/row-actions-implementation/audit/*.md`.

### 3.1 State & Reactivity

Scope: `LuauUI.newCore`, `LuauUI.newEnvironment`, `LuauUI.newResourceProvider`,
`LuauUI.mount`, `LuauUI.motion.newClock` (motion covered from the
transaction/reactive side here; §3.6 Motion covers the same ground from the
motion-authority side — the two are cross-checked and agree).

| SwiftUI capability | LuauUI status today | Evidence (file:line / test) | Change since 2026-07-22 |
|---|---|---|---|
| `@State` (owned, per-instance mutable value) | **Covered** (fine-grained signal, not per-view-struct) | `core:signal` — `src/core/custom.luau:356-372`; contract `src/core/contract.luau:21-26`; test `signal-read-write` — `tests/conformance/suite.luau:26` | No material change |
| `@Binding` (two-way reference to caller-owned state) | **Covered by convention, not by type** | Controls take a caller-supplied `Signal` directly (`value_model.luau:1-12`); no `@Binding`-equivalent projection/wrapper type exists | Unchanged |
| `@Observable` (auto-tracked property access, whole-object granularity) | **Partial — finer-grained than SwiftUI, not object-shaped** | Per-signal/per-memo tracking via `use()` — `src/core/custom.luau:104-109`; test `dynamic-dependencies-swap-atomically` — `suite.luau:134` | Unchanged mechanism; no object/model macro added |
| Derived/computed state (`computed`, memoized) | **Covered**, glitch-free | `core:memo` — `custom.luau:374-390`; eager-stale + pull-based lazy recompute (`:165-174`, `:85-132`); tests `memo-derives-and-updates`, `glitch-free-diamond`, `no-spurious-fire-on-unchanged-recompute` — `suite.luau:35,71,359` | Unchanged in mechanism |
| Transactions (`withTransaction`) | **Covered** as pure write-batching | `core:transaction` — `custom.luau:436-451`; tests `transaction-batches-observer-to-one-fire`, `mid-transaction-derived-reads-fresh`, `transaction-revert-produces-no-fire` — `suite.luau:50,383,399` | Unchanged |
| `withAnimation` (implicit state-write ⇄ interpolation coupling) | **Missing as an implicit coupling; present only as an internal detail** | The motion clock wraps its own per-frame commit in `core:transaction` (`src/motion/clock.luau:210-219`), but no public API lets an author wrap an arbitrary signal write and have it interpolate — animation is opt-in per value (`clock:spring/counter/timer/glide/chase`) | **New area since validation** — the whole motion authority (ADR-0022) postdates 2026-07-22 and was never assessed by the old doc |
| Cycles / self-referential derivation | **Covered**, reported not hung | `evalStack` cycle detection — `custom.luau:89-96`; test `cycle-reported-not-hung` — `suite.luau:164` | Unchanged |
| Write-during-derive illegal state | **Covered** | `write()` guard — `custom.luau:177-179`; test `write-during-memo-is-error` — `suite.luau:191` | Unchanged |
| `.task` (async work scoped to view lifetime, cancelled on disappear/identity change) | **Partial**, stronger cancellation than SwiftUI's identity-only cancel | `LuauUI.newResourceProvider` (`src/async/resources.luau`): scope-owned handles, generation-based stale-completion rejection (`:358-366`), bounded+spaced retry | Predates 2026-07-22 unmodified in this range; the old audit never scored it against `.task` directly (only as `AsyncImage`, Composable) |
| Environment values (`@Environment(\.foo)`) | **Covered, and now substantially exercised** — reversal of the old finding | `env:get`/`env:set` — `src/env/environment.luau:316-344`; per-key `Signal`s + derived `Memo`s (`:125-312`) | **Materially changed.** Old audit's "`sizeClass` consumed by nothing" claim is false against today's tree — 16+ call sites across `renderer.luau`, `adaptive.luau`, `presenter.luau`, `table.luau`, `text_input.luau`, `rating.luau`, `row_actions.luau:611`, `theme_controller.luau`, `hint.luau:69` |
| Environment derived/clamped facts | **Covered** | `typographyScale`/`effectiveTransparency`/`effectiveOverscanInsets` clamp/default on bad input — `environment.luau:125-153,200-218` | New facts (`topbarInset`, `topbarSafeInsets`, `textMeasureEpoch`, `presentationSpace`, `themeMetrics`) added post-2026-07-22 |
| Identity & structural diffing (`ForEach(id:)`, `.id()`) | **Covered**, closer to `ForEach` than whole-tree diffing | `mountForEach` — `src/mount.luau:224-407`: add/remove/move only, duplicate keys hard-error | **New since validation**: mid-exit re-entry resumes the same mounted subtree/scope/instances (`:288-300`) rather than remounting, shipped in `2497a13` (Step 9 / ADR-0022 Decision 3) |
| Instance-identity reuse below ForEach/When (recycling pool keyed by shape) | **Covered** — no direct SwiftUI analogue | `src/render/renderer.luau:1556-1722` (`recycleInstances`, `RECYCLE_POOL_CAP`, `recycleKey`) | **New since validation** (Step 9 perf lab + the later corpse-adoption guard, `tests/instance_park_corpse.spec.luau`) |
| Ownership scopes / disposal discipline | **Covered**, stricter than SwiftUI | `scope_impl.factory` — reverse-order idempotent dispose, double-dispose detection, releasability check at `own()`, quarantined cleanup errors | `scope_impl.luau` itself unmodified in this range; consumers (mount's retiring subtrees, motion clock's `values` set) grew new call patterns |
| Feedback-loop / effect re-entrancy bound | **Covered** — no SwiftUI equivalent surfaced publicly | `FEEDBACK_ROUND_CAP = 100` — `custom.luau:22,264-273`; test `feedback-loop-hits-iteration-cap` — `suite.luau:236` | Unchanged |

**Strengths:** atomic dependency-swap on success only (a failed memo keeps its
old deps, so a transient throw can't detach it from the fix); `scope:own()`
raises immediately on a handle with no `dispose()`; `ForEach` identity
survives mid-transition re-entry (stronger than SwiftUI's default remount);
environment facts are per-key signals (a keyboard-occlusion change can't
over-invalidate a color-only subscriber); async resource identity uses
generation counters, closing a `.task`-cancellation race class SwiftUI
developers still guard by hand.

**Gaps:** no `withAnimation`-equivalent implicit coupling (the largest
structural gap in this area — every animated value is a separately-typed
`MotionValue`); no `@Binding`-equivalent projection type (two-way flow is
convention, checked only at write time via a runtime assertion); no
`@Observable` whole-object ergonomics (signal-per-field is a deliberate
design difference, not an accident); `lastError()` is sticky/non-resettable —
a long-lived core can be asked "were you ever quarantined" but not "are you
OK right now."

Verification for this area: `./run-tests.sh` at HEAD `fff48b2` — **4038
passed, exit 0**; every citation above names a test that ran in that pass.

### 3.2 Layout

Scope: stacks/ZStack/grids/Layout protocol, `ViewThatFits`, alignment guides,
safe areas, `GeometryReader`, `containerRelativeFrame`, adaptive layouts,
scroll behaviors/targets, incremental layout performance. Method: direct
source read of `src/layout/solver.luau` (2275 lines), `adaptive.luau` (334
lines), `composition.luau` (1703 lines), `renderer.luau`, `screen_target.luau`,
`stage_content.luau`, `virtual_list.luau`, `row_actions.luau`.

| Capability | Status | Evidence | Change since 2026-07-22 |
|---|---|---|---|
| HStack/VStack core (weighted flexbox, `align`, `margin`) | **Partial — unchanged** | `solver.luau` vstack/hstack arrange path (~1917–2100) | No change to the fundamental contract |
| `layoutPriority` (shrink-on-overcommit) | **Missing — unchanged, deliberate** | No `priority`/shrink pass in `solver.luau` | No change. `Composition`'s `rank` is adjacent, not equivalent — it drops/steps-down ranked regions in one screen-level container, not a general stack-shrink negotiation |
| ZStack | **Partial — one gap closed** | `renderer.luau:419-437` deterministic paint order; **new**: `tests/zstack_fill_diagnostic.spec.luau` — the overflow diagnostic is now per-axis and `fill`-aware | **Changed** (2026-08-08 device-matrix finding). Unchanged: no `.zIndex` override |
| Grid — cell sizing | **Partial — two named defects closed** | `solver.luau:1890-1897`: a `fill`-dimensioned cell now occupies its full column/row (was: collapsed to content width). `solver.luau:1904-1906`: per-cell alignment now applied. `tests/grid_measure_arrange.spec.luau` proves the grid's measured size is a fixed point of its own arrange report | **Changed.** Both defects the July audit named (`fill`-collapse, no per-cell alignment) are fixed in source |
| `GridRow` / column-varying widths / `gridCellColumns` | **Missing — unchanged** | One uniform `colW` for every column (`solver.luau:1863`) | No change |
| `LazyHGrid` | **Missing — unchanged** | Grid is still row-major/vertical only | No change |
| `ViewThatFits` | **Available/Partial, real construct** | `solver.luau` `kind == "fits"`; `blueprint.luau`, `blueprint_schema.luau`, `layout/composition.luau` | Present at 2026-07-22 in nascent form; re-confirmed live this cycle |
| `UI.AdaptiveStack` (reactive-axis stack) | **Available** | `blueprint.luau:566-570`; `renderer.luau:386-389` — one class, `axis` is a bound `Readable`, a flip re-solves without remount | Present since Step 6, reconfirmed unchanged |
| `UI.Composition` + `UI.Region` (screen-level ranked, declared-content adaptation) | **New capability since 2026-07-22 — Available, exceeds SwiftUI in one respect** | `docs/adr/ADR-0023-declared-content-composition.md`; `src/layout/composition.luau` (1703 lines, pure resolve function); `renderer.luau:394-398`; `tests/composition.spec.luau` (1988 lines) | **Entirely new.** Declares content once (ranked regions, each with a richest→minimum-viable form ladder); the framework legality-tests arrangements in rank order and steps down/drops. Closer to a full `Layout` + `layoutPriority` combination than any single SwiftUI built-in |
| Adaptive size/height classes + `navPlacement` | **Available, went from zero consumers to real consumers** | `src/layout/adaptive.luau`: `sizeClass`/`heightClass`/`axisFor`/`columnsFor`/`navPlacement`/`conditions()`; consumed by all 5 Step-11 reference apps | **Changed materially.** The July audit's own most-quoted sentence ("`sizeClass` is consumed by nothing in `src/`") is now false |
| Safe areas | **Available — unchanged mechanism, one policy bug fixed** | `environment.luau:22-23`; `renderer.luau:2278-2315` — found-and-fixed bug: `rootPolicy = "edgeToEdge"` was passed and never read, so every scrim silently got ordinary content insets instead of full-bleed | Insets predate 2026-07-22; the `edgeToEdge` dead-policy-string fix is dated to the row-actions/Step-9-adjacent window |
| `GeometryReader` equivalent | **Partial — unchanged, no new gaps found** | `controller.rectOf`, `opts.onGeometry`, contribution `syncGeometry`; still a push callback, not a `Readable`, still path-keyed | No change this cycle. New consumer pattern: `row_actions.luau:2440-2452` computes a floating menu's anchor by re-reading `syncGeometry` on the same cadence a live scroll already drives — an ad hoc recipe on this seam, not a new primitive |
| `containerRelativeFrame` equivalent | **Composable — unchanged** | `percent` dimension type (`solver.luau:481-517`) | No change |
| Alignment guides (`.alignmentGuide`) | **Missing — unchanged** | No construct found in `src/` | No change |
| ScrollView — native scroll container | **Available — was "Partial, weakest container"** | `screen_target.luau:107-113` — `CLASS_TO_INSTANCE.ScrollView = "ScrollingFrame"`; `:2029-2036`; `:3097-3152` | **Changed materially.** The single most-cited weakness in the July product-quality table is substantially closed |
| ScrollView — `axis = "x"` | **Fixed — was a named silent defect** | `solver.luau:832-858` branches measure/arrange correctly by axis | **Changed.** July's §4.9 item 4 documented children stacking downward and under-reported overflow on `axis="x"`, "passes CI silently." Now correct |
| ScrollView — scroll indicators policy | **New capability since 2026-07-22** | `blueprint.luau:132` (`indicators: "auto" \| "none"`); `screen_target.luau:2998-3141` | New, director ruling 2026-08-09 |
| ScrollView — drag-to-edge autoscroll | **New capability since 2026-07-22** | `src/input/autoscroll.luau`; `renderer.luau:3384-3580` — any nested scroll chain, innermost-first with pinned-host fall-through | New, per project memory dated 2026-07-29 |
| ScrollView — virtualization | **Missing — unchanged** | Every ScrollView child is still measured/arranged; only `VirtualList` and `Table` virtualize independently | No change. "A long, reorderable list is unbuildable on any class today" still stands — Table reorders but doesn't virtualize, VirtualList virtualizes but doesn't reorder/select; row-actions shipped inside both independently rather than closing the gap |
| `LazyVStack` (`VirtualList`) | **Partial — capability additions, structural gaps unchanged** | `virtual_list.luau`: `rowGap` and `focusPolicy` (`"key"`\|`"index"`) new since 2026-07-22 | **Changed (additive).** Still fixed `rowHeight` only, vertical-only, no pinned headers, no fling/inertia, no scrollbar — all four prior gaps remain |
| Incremental layout (relayout boundaries) | **New capability — shipped and ON by default** | `solver.luau:462-465` (Stage 1 boundary detection); `renderer.luau:2262-2280` (Stage 2 v2); default ON unless explicitly disabled (`renderer.luau:2278`, `presenter.luau:2057`); `tests/incremental_layout.spec.luau` | **Entirely new.** Measured: 141→8 nodes arranged for a one-bound-value change in Studio (~17×), 0 differences in an engine-level visual diff over 185 nodes |
| `UI.Stage` (ViewportFrame adoption) | **New capability since 2026-07-22** | `src/render/stage_content.luau` (147 lines, pure camera/lighting contract); `blueprint.luau`, `screen_target.luau`, `billboard_target.luau` | **Entirely new.** For layout purposes falls into the generic `kind = "box"` bucket — a new content leaf, not a new layout algorithm. Live consumers: Cartwheel's 3D hero, Wardrobe's mannequin preview |
| Device profiles / matrix testing | **Available — unchanged mechanism, exercised further** | `src/preview/device_profiles.luau`, `matrix_rows.luau` | No structural change; five Step-11 reference apps + the row-actions device matrix are new *uses*, not new mechanism |
| Row-actions layout-adjacent mechanics (this branch) | **New, feature-scoped, not framework primitives** | `row_actions.luau:875-958` — a per-row `rowHeightOverride` signal driven by a physics spring, read as the row's own authored height (animated collapse-to-zero on destructive commit); `presenter.luau:2270-2271` + `row_actions.luau:2483` (`bindPresent`) | Both are ad hoc recipes built from existing seams (a reactive height prop; the modal/presenter stack), correctly excluded from the framework capability rows but noted as patterns that could generalize |

**Strengths (new since 2026-07-22):** `UI.Composition`/`UI.Region` is the
single biggest layout addition — a declarative, headlessly-testable answer to
"screen declares ranked content, framework picks placement and degrades
gracefully" that SwiftUI splits across `ViewThatFits`, `layoutPriority`, and
hand-written responsive branching; ScrollView went from four named defects to
a real native host; incremental layout shipped ON with a differential-fuzz
correctness history; Grid's two worst defects are fixed in source, not just
superseded; `adaptive.luau` went from zero consumers to a multi-app-consumed
policy module.

**Gaps (confirmed still open, unchanged):** no `layoutPriority`/shrink
negotiation for HStack/VStack (deliberate non-goal); no container unifies
virtualization + reorder + select (row-actions' own perf audit found the
VirtualList integration path costs +57%/+81% scroll/fling vs a ≤5% budget,
re-baselined not closed — the next lever is a `VirtualList`-level
gesture-composition hook, `docs/plans/row-actions-perf-mission.md`);
`GridRow`/`LazyHGrid`/spanning still entirely missing; VirtualList still
fixed-row-height/vertical-only/no pinned headers/no fling/no scrollbar; no
alignment guides; two explicitly-deferred §12 proposals (a flow-stack
"compress toward `min`" step, splitting the overloaded `align` channel) still
deferred, no corresponding commit since §12 was written.

Verification for this area: `./run-tests.sh` — **4038 passed, exit 0**.

### 3.3 Controls

Scope: the Controls area (old §3 Controls, plus §4 items that are really
controls-in-disguise — Table/List/PopupButton/Divider), and the named deltas:
swipeActions, reorderable Table, PopupButton, compactLabel/icon set,
themes-era controls, Stage. Authoritative inventory walked:
`tests/conformance/controls_registry.luau` (16 composite/leaf-with-proof rows
+ 20 non-interactive leaves) and every file under `src/controls/`.

**This is a delta table against the July verdicts, not a re-listing of the
full 69-item catalog.** The controls area audit re-verified changed items in
depth and reconfirmed a swath of unchanged "Missing" items by direct grep
(§3.3.5 below); it did not re-derive the full A–F breakdown, so this document
no longer carries that breakdown as a parallel structure — items not named
below or in §3.3.5 were not independently re-examined this cycle.

#### 3.3.1 Deltas since 2026-07-22

| SwiftUI item | Was (2026-07-22) | Now (v0.9.0) | Evidence |
|---|---|---|---|
| **Generalized `swipeActions`** | **Missing** | **Partial** (real construct, named perf/RTL gaps) | `src/controls/row_actions.luau` (`newRowActions`, `newRowActionsCoordinator`, `src/init.luau:186,191`); `tests/row_actions.spec.luau`, `tests/row_actions_input.spec.luau`; Table integration `table.luau:1159-1351`; gate `row-actions` PASS |
| **`Slider`** | **Composable** (recipe only) | **Partial** (real composite) | `LuauUI.newSlider` — `src/controls/slider.luau`, export `:135`; registry `controls_registry.luau:428-464` (pointer drag/tap-to-position, touch drag, keyboard/gamepad Adjust, hotSwitch=CANCEL) |
| **`Stepper`** | **Composable** | **Partial** (real composite) | `LuauUI.newStepper` — `src/controls/stepper.luau`, export `:134`; registry `:466-500` |
| **`Picker` `.segmented`/`.inline`** | **Composable** (two separate recipes) | **Partial** — ONE adaptive composite replaces both | `LuauUI.newPicker` — `src/controls/picker.luau`; `picker.resolvePresentation(optionCount, sizeClass, longestLabel)` auto-switches segmented↔inline from option count / `sizeClass` / label length — never a device branch; registry `:373-399` |
| **`ProgressView` (determinate)** | **Composable** | **Partial** (real composite) | `LuauUI.newProgressView` — `src/controls/progress_view.luau`, export `:140`; registry `:345-358` (`inputProofs=false` declared explicitly, non-interactive) |
| **`ProgressView` (indeterminate)** | **Missing** | **Still Missing, unchanged** | `grep -rn "indeterminate" src/controls/progress_view.luau` → 0 hits |
| **`Label` (title + icon)** | **Composable, awkwardly** — no `LabelStyle`, no `.iconOnly`/`.titleOnly` | **Partial** — real composite WITH the presentation resolution the July audit named as missing | `LuauUI.newLabel` — `src/controls/label.luau`; `presentation: "titleAndIcon" \| "titleOnly" \| "iconOnly"` (`:23,30`), `iconOnly` degrades safely to `titleOnly` when no icon. **Residual:** `title` is a static memo, not reactive/bindable (open follow-on, `framework-fixes.md:874`) |
| **`DisclosureGroup`** | **Composable** | **Partial** (real composite) | `LuauUI.newDisclosureGroup` — `src/controls/disclosure_group.luau`; registry `:400-426` (focus-to-header-before-unmount paradigm proof) |
| **`Divider`** | **Composable** (`Box{width=fill,height=1}` recipe) | **Partial/Available** — real leaf | `UI.Divider` — `blueprint.luau:699`, axis-aware hairline (infers orientation, no more manual sizing); leaf row `controls_registry.luau:869` |
| — (no catalog row) | — | **New: `newRating`** | `src/controls/rating.luau`; one-focus-stop strip (tap/scrub/Adjust), `hotSwitch = CANCEL` on mid-scrub loss — no SwiftUI standard-library counterpart |

**PopupButton — Partial, both remaining and closed:**

| | Was | Now |
|---|---|---|
| Presentation | "One style, everywhere" | **Adaptive**: `presentation: "automatic" \| "menu" \| "inline" \| "sheet"`, `resolvePresentation(optionCount, sizeClass, touchLive)` — `touchLive == true` → `"sheet"` unconditionally; compact + >6 options → `"sheet"`; ≤3 options + non-compact → `"inline"`; else `"menu"` |
| Touch row floor | `ROW_HEIGHT = 36` hardcoded, below the 44px `minHitSize` floor on every presentation | **Presentation-dependent and token-derived**: `sheet` uses `controlSizes.large.height = 56px` — the touch-live path no longer serves a sub-floor row at all. The pointer-only `menu` presentation still serves 36px rows — genuinely below 44px, but now confined to pointer only |
| `sizeClass` consumers | "Zero consumers in `src/`" | **Now false as a blanket claim.** Read by `popup_button.luau`, `picker.luau`, `layout/adaptive.luau`. Still not read by `presenter.luau`, `table.luau`, or the modal-dismissal/style system |
| Panel flip/clamp, selection-only rows | Unchanged | Still true, not touched by this stage |

**Table — reorderable, secondary actions, still-open gaps:**

| Old gap | Status now |
|---|---|
| "No secondary row actions, no `.onDelete`, no modifier-click multi-select" | **`.onDelete`/secondary actions: closed** via `spec.rowActions` (`table.luau:185-231,1159-1351`) — leading/trailing trays, per-edge `fullSwipe`, keyboard Delete/Backspace fires the row's first `destructive` action, gamepad ButtonX / keyboard Shift+Return open an action menu. **Modifier-click multi-select is still unshipped** — this stage did not touch selection |
| "No virtualization; column resize remounts every row" | **Unchanged.** Table still does not virtualize; VirtualList still does not reorder/select |
| "No compact adaptation... `sizeClass` has zero consumers" | Table itself still has zero `sizeClass` consumers — unchanged, even though the framework as a whole gained two |
| Row-actions perf cost (new, not in old audit) | **Named, gated, not silent.** A `newRowActions`-wrapped CLOSED row inside `newVirtualList` costs +57% steady-scroll / +81% fling / +5 instances/row vs an unwrapped row — well over the plan's original ≤5%/≤4-instance budget. Director-ruled 2026-08-11 to re-baseline the gate ceiling to the measured numbers rather than block release. **RascalRally is unaffected today**: no RR Table caller passes `spec.rowActions`, confirmed live in Studio with zero wrapper instances mounted (`artifacts/row-actions/rr-compat.md`) |

#### 3.3.2 RowActions — full capability confirmation (the mission's headline delta)

Public API: `LuauUI.newRowActions` (`src/init.luau:186`) and
`LuauUI.newRowActionsCoordinator` (`:191`) — both real exports.
`Table.rowActions` is Table's own wiring of the same two seams. Confirmed
shipped, per `tests/conformance/controls_registry.luau:612-734` and
`tests/row_actions*.spec.luau`:

- **Leading/trailing trays**, revealed by drag (mouse) or touch pan, spring-driven proportional growth.
- **Per-edge `fullSwipe`** (bool or `{leading, trailing}`) — commits the first action of the swiped edge.
- **Full-swipe commit, destructive and non-destructive**: row slides off, height collapses, `onAction` fires exactly once.
- **Keyboard Delete/Backspace**: fires the row's first destructive action, scoped to the row's own mounted subtree, inert while its own menu is open.
- **Shift+Return / gamepad ButtonX** open the same action menu — the first modifier-aware IAS binding in the framework.
- **Edit-mode minus affordance**: opens the edge that actually holds the destructive action.
- **One-open coordinator**: opening row B closes row A; scroll and outside taps close the open row.
- **Axis-lock arbitration vs. reorder drag**: horizontal claims RowActions, vertical stays with scroll, the reorder handle always wins on itself.
- **Touch parity with mouse**: every downstream branch (axis lock, clamp, settle) is shared, not a second code path.
- **hotSwitch is real and proven**: touch press mid-mouse-drag declined (mouse CARRIES); mouse press mid-touch-drag declined (touch CARRIES); touch cancel mid-drag springs back to closed (CANCEL).

**Named residual gaps:** perf (+57%/+81%/+5 instances, still over the
original ≤5%/≤4 budget — `docs/plans/row-actions-perf-mission.md` is an open,
not-started charter); no RTL (explicit non-goal, `docs/plans/row-actions.md:16`);
only Table's `rowActions` key is a turnkey integration — the coordinator is
public/general but no other composite (VirtualList) wires it today;
`artifacts/swiftui-reference-app-validation/capability-ledger.md:59` still
reads "no secondary-action/swipe model yet" — that ledger predates this
feature and should be corrected the next time its stage is touched (this
document supersedes it for the controls area).

**Bottom line: swipeActions moves from Missing to Partial** — a real,
four-input-proven, gate-enforced construct exists, with the perf overhead and
RTL gap as the two honest remaining items.

#### 3.3.3 `.contextMenu` — re-examined, not fully closed

Old verdict: **Missing**, blocked on two triggers (no long-press timing, no
secondary mouse button). **What changed:** `src/input/touch_gestures.luau`
is a new normalization + arbitration layer over the engine's own native
gesture recognizers (`GuiObject.TouchTap/TouchLongPress/TouchPan/TouchPinch/
TouchRotate/TouchSwipe`), publicly exported (`LuauUI.touchGestures`), wired
end-to-end at the adapter and part of the formal target contract. **What did
NOT change:** zero composite consumers call it — no control, RowActions
included, wires `TouchLongPress` or a secondary mouse button to open a menu;
Button still filters input to `MouseButton1`/`Touch` only. **Verdict: still
Missing**, but the blocker reclassifies from "no adaptation layer exists" to
"the adaptation layer is built, tested, exported, but no control consumes it
as a trigger" — a materially smaller remaining gap, and the next candidate
this document's priority list should name explicitly, since RowActions
already proves the *menu* half.

#### 3.3.4 compactLabel, themes-era controls, Stage — unchanged, verified live

`compactLabel` (shipped 2026-07-27, five days after the July validation date)
and `UI.Stage`/`UI.ViewThatFits`/`UI.AdaptiveStack`/`UI.Composition`/`UI.Region`/
the Grid/ScrollView corrections were not touched by row-actions
(`git log --oneline --since=2026-08-09 -- src/themes/ src/controls/ | grep -v
row_action` shows only row-actions-family commits touching `src/controls/`,
no theme-file commits at all). §12 below already carries the current, correct
verdicts. `UI.Stage` remains a leaf with `inputProofs=false`/
`affordanceProofs=false` by design.

#### 3.3.5 Notable gaps still open (verified, not just carried forward)

- **Palette Picker** — confirmed still absent (zero grep hits).
- **`sensoryFeedback`** — confirmed still absent as a semantic haptic/audio *event surface at the control level* — see §1's headline flip for the framework-level feedback bus, which is a different, real thing.
- **Indeterminate `ProgressView`** — confirmed still absent.
- **`GridRow`, `LazyHGrid`, `NavigationSplitView`, `DatePicker`, `ColorPicker`, `SecureField`, multi-line `TextEditor`, `Gauge`, `Link`/`ShareLink`** — all reconfirmed absent by direct grep against current `src/`. No change from the July verdicts or reasoning.
- **`ButtonStyle`/`ToggleStyle`/`*Style` protocols** — unchanged; every new composite follows the same "compose from styled primitives, no render-substitution protocol" shape. Not a regression, just not addressed by this stage.

#### 3.3.6 Notable strengths (new since 2026-07-22, beyond swipeActions)

Composable → real composite, six times over (Slider, Stepper, Picker,
ProgressView, Label, DisclosureGroup) — investment 4 and the bulk of
investment 7 off the July priority list, executed not merely planned;
`Divider` is a real leaf now, closing a correctness footgun in the old
recipe; PopupButton's touch path is floor-compliant by construction;
`sizeClass` has real consumers for the first time; a real touch-gesture
normalization/arbitration layer exists even though unconsumed; a new
modifier-aware input binding primitive (`action.bind(..., {modifiers=...})`).

Verification for this area: `./run-tests.sh` — **4038 passed**;
`python3 tools/check_row_actions_matrix.py` → exit 0; `artifacts/row-actions/gate.json`
→ `"gate": "row-actions", "status": "PASS"`.

### 3.4 Styling & Theming

| Capability | Status | Evidence | Change since 2026-07-22 (v0.5.0) |
|---|---|---|---|
| View modifiers/styles (`ButtonStyle` etc.) | **Missing** (no `*Style` protocol); data modifiers **Partial** | No `ButtonStyle`/`ToggleStyle`/`LabelStyle`/`PickerStyle`-equivalent anywhere in `src/`. Three shipped modifiers attach validated **data** to a node: `UI.shadow`, `UI.corners`, `UI.styleGroup`. A control's rendering stays imperative Roblox instance code in `screen_target.luau`; nothing is substitutable per-control except by writing a whole new render target | No structural change — still the sharpest structural divergence from SwiftUI. **But** the previous Partial rating leaned partly on a reactivity bug that has since been fixed (next row) |
| — reactive style updates (post-mount) | **Available** (this document's own prior text claimed otherwise — doc drift found and corrected) | `renderer.luau:76-106` defines `STYLE_PROPS` (`surface, role, shadow, gradient, corners, textAlign, shape, icon, compactLabel, stroke, scaleMode`) re-applied on every reactive change, per the code's own comment: "Milestone 0 (swiftui-parity-next investment 1) fixed the second half: a bound `surface`/`role` dirtied 'paint' and the refresh loop then dropped it" | **Doc correction, not a code gap** — see §1 stale-claims list |
| Materials (blur/vibrancy/translucency) | **Missing** | No blur, backdrop-filter, vibrancy, or frosted/translucent material construct anywhere. Every "glass" hit in source is a validation-rule metaphor, not a rendering material. Theme packages own flat fills, nine-slice art, gradients (capped `GRADIENT_ALPHA_MAX = 0.9`) and layered image chrome — all still opaque-paint techniques | Apple shipped `.glassEffect()`/`.glassProminent`/`GlassEffectContainer` (Liquid Glass, iOS 26/WWDC 2025 era) as a mature production system in the interim. **The gap widened, not narrowed** |
| Tints | **Partial** | Per-asset `tintRole` tints semantic icon art from the active theme's color roles; `Image.tint` is a real reactive `BINDING_PROPS` write; a continuous-colour blend channel (`{role, blend, from?}`, ADR-0022 Decision 6) exists for animating between two theme roles. **Absent**: an environment-cascading `.tint(Color)` that recolors an entire subtree — LuauUI's tint mechanisms are per-node opt-in, not inherited | Continuous-colour blend and full reactive `tint` are both new since baseline |
| Dark mode / color schemes | **Available** | Native StyleSheets (ADR-0018) ship `Theme Dark`/`Theme Light`, swapped at runtime with no remount, focus/scroll retained. Theme *packages* (ADR-0019) go further: `theme_controller.install`/`.swap` performs "one transaction — `SetDerives` plus the snapshot commit" so paint and geometry land in the same frame with mount identity/focus/selection/scroll/text-entry all surviving | **Shipped entirely since the 2026-07-22 baseline** — the single largest capability delta in this area |
| Dynamic type | **Available** (framework's own equivalent) | The player's Roblox "Text size" preference (Medium/Large/Larger/Largest) is first-class layout input: the engine paints `TextSize + offset` at a measured, per-preference constant; the solver reserves the exact painted box; a mid-session change re-solves every mounted surface in place, preserving identity/focus/scroll/state. Eight typography roles carry font descriptor + line height together | Unchanged in mechanism since baseline; now composes correctly with theme packages' typography ladders, motivated by a real clipping bug found in the gallery's own theme picker |
| Custom styling protocols | **Missing** | No protocol lets a consumer swap *what a control renders as* while the framework keeps interaction/state. The only per-instance rendering-injection seam in the whole library is Table's `cellFor` | No change |
| Liquid Glass-era design adoption | **Missing** | No translucent/blur material, no light-reactive surface, no `GlassEffectContainer`-style morphing group. LuauUI's answer to "rich visual identity" is data-driven: nine-slice panels/chrome slots, layered art (up to 8 layers, ADR-0020) and per-state art maps — all flat/opaque compositing | Confirmed via web search: Apple's Liquid Glass is shipped and actively used in production as of iOS 26. LuauUI has no counterpart at any layer and none is planned in any open ADR/plan file |
| Cascade / selector model (`sheet_model`) | **Available** (supporting infrastructure) | Cascade = "Priority first, then insertion order (later wins); no specificity" — deterministic priority (`rule.priority = #rules * 10`) so the generator and `native_style.priorityFor` can never disagree. `luau-*` CollectionService tags classify instances | Unchanged in design since ADR-0018 — the whole mechanism postdates v0.5.0 |
| Theme packages owning metrics/chrome (not just palette) | **Available** | ADR-0019: a package owns typography, spacing, control heights, radii, strokes, solver-visible content insets and asset-backed chrome; a swap re-solves rather than merely recolors. Validated for contrast, completeness, legal properties, insets, target floors at `themes.define`. `CONTROL_FAMILIES` now covers `rowActions = { buttonMinWidth, buttonPad, editAffordance }` — the newest family, added for this branch's feature | Entire capability shipped since baseline; `rowActions` family added on this branch |
| Rich/image-driven skinning (layers, per-state art, value displays, pixel mode, `selectBy`) | **Available** | ADR-0020: layered slots (up to 8 layers), per-state art maps, value-display hosts drawn full-size and revealed through a clip window (no adapter write per value change), semantic icons with ASCII-safe fallback (never tofu), pixel mode, `selectBy` (input paradigm → package). Tested extensively across 9 dedicated spec files | Entirely new since baseline. Doc flags open items: human Style-Editor walkthrough, physical-phone pass over ornate chrome, low-end-device cost — tracked, not closed by a device run |

**Gaps:** no `*Style` protocol / no per-control-instance rendering
substitution (durable, unchanged); no material/translucency system (gap
genuinely widened against Liquid Glass); no environment-cascading `.tint()`;
style lint (jagged-corner caveat, ~100-shadow budget) remains warnings-only,
no CLI, wired into no gate.

**Strengths:** Dark/Light theming and full theme packages are a complete,
shipped capability class that did not exist at the 2026-07-22 baseline;
dynamic-type equivalent is unusually rigorous (exact-once measured
per-preference offset, composes additively with ten-foot scaling); reactive
style-prop updates now work end-to-end, closing a real gap this document
itself had flagged without noticing the fix; `rowActions` is a live proof the
theme-package extension pattern generalizes to a genuinely new control
family, not just the ones it shipped with.

Verification for this area: `artifacts/test.json` (2026-08-11 04:03) —
**passed: 4038, failed: 0**.

### 3.5 Input & Accessibility

Standing rider, reconfirmed: **nothing in LuauUI has been confirmed on
physical hardware.** Six fresh `NEEDS_PHYSICAL_DEVICE` riders are carried by
this branch alone (§6).

| Capability | Status | Evidence | Change since baseline |
|---|---|---|---|
| Gesture normalization (value type) | Partial — real primitive, zero consumers | `touch_gestures.luau:19-28` (`Gesture` type: kind/state/positions/translation/velocity/scale/rotation); wired to the adapter contract and the real adapter (all six engine events connected); exported (`LuauUI.touchGestures`). **Grep-confirmed zero callers of `setTouchGestureHandlers`** in any `src/controls/*.luau` or `renderer.luau` | **New since baseline.** The old doc's "no normalized gesture layer" framing is now imprecise: the primitive exists and is real, but is dead machinery from any control's perspective |
| Gesture composition / arbitration | Partial — ranked single-owner claim, not simultaneous/sequenced | `touch_gestures.newArbiter()`: fixed `RANK` (pinch/rotate=3 > pan=2 > longPress=1 > tap/swipe=0), begin/change/end ownership lifecycle. No simultaneous delivery, no `.sequenced`/`.exclusively` chain. Same "dead machinery" caveat | New primitive, but the old "one crude one-bit `.highPriorityGesture`" verdict remains accurate for what controls actually run |
| Drag/drop general contract (`DragGesture` equiv.) | Partial, materially deeper than baseline | `src/input/drag_contract.luau` — public `UI.draggable`/`UI.dropTarget` (payload, `armOnTap`, `declineTouch`, per-class `promotionPx`). `drag_session.luau` — pure hover/predict/drop policy. `drag_registry.luau` — "ONE PROMOTION PATH, THREE ACQUISITIONS": native `UIDragDetector`, ADR-0008 pointer-capture fallback, non-pointer arm→navigate→commit, all funnel into one shared session lifecycle. Broad `UIDragDetector` adoption across `slider.luau`, `presenter.luau`, `renderer.luau`, `screen_target.luau`, `billboard_target.luau` | **Substantially expanded since baseline** (ADR-0022 Decision 5). The old doc's own recommendation is now the design already delivered |
| Row-actions cross-input secondary-action model | Partial→real, most-complete secondary-action story in the framework | `LuauUI.newRowActions` — public, standalone, **not Table-only** (proven in a hand-wrapped `ScrollView>VStack` list with zero Table involvement). Mouse+touch: unified pointer-capture drag, 8px axis lock, ties-go-vertical, rubber-band resistance, velocity-projected settle. Keyboard: Delete/Backspace, focus-subtree-scoped, menu-open-gated. Menu: gamepad ButtonX + keyboard Shift+Return. Full-swipe commit both edges. **Gap named honestly**: no mouse secondary-click and no touch long-press trigger for the menu — both reach it only via the reveal-tray. RED-TEAM: 16 findings, 15 fixed directly + 1 resolved via design change (floating `presentModal` surface), gate CLOSED. Five-view Studio device matrix PASS at all viewports. Six `NEEDS_PHYSICAL_DEVICE` riders open | **New this branch.** The framework's own §12 (2026-08-08, written before row-actions) says "swipe-row actions... no secondary-action model yet" — no longer true; corrected in §12 below |
| Gesture-machinery architecture (cross-cutting) | Fragmented — four independent implementations | (1) `touch_gestures.luau`'s arbiter (unconsumed), (2) `drag_contract`/`drag_session`/`drag_registry` (general draggable/dropTarget), (3) `row_actions.luau` (bespoke pointer-capture + its own axis-lock, sharing only `drag_velocity.luau` with #2), (4) `table.luau`'s own hand-rolled vertical reorder drag. None of #1/#3/#4 share axis-lock code | **Confirms and deepens** the framework's own prior diagnosis ("four hand-written code paths per control") — row-actions is live proof of the cost recurring a third/fourth time |
| Input-source selection (pointer/touch/pen/gamepad) | Partial, real | `interaction_tokens.luau:45-87` — per-class promotion thresholds, consumed by drag promotion and row-actions' own pointer-type gate. Live hot-switching proven mid-gesture | Unchanged in kind; row-actions is a new proof point of the same mechanism |
| Keyboard modifiers (`.onKeyPress`-adjacent chord support) | Partial, newly generalized | `actions.luau:96-112` — `action.bind` accepts additive `modifiers = {shift: boolean?}`; Ctrl/Alt intentionally not yet accepted. Real-engine realization compiles one binding into **two** `InputBinding`s (`LeftShift`/`RightShift` `PrimaryModifier`). Sole consumer: row-actions' Shift+Return | **New since baseline** — Task 8b, shipped after "Step 8" desktop keyboard nav |
| `onKeyPress`-equivalent raw key seam | Missing, confirmed unchanged | Zero matches for `onKeyPress`/`rawKey`/`KeyEvent` in `src/` | Unchanged; already correctly stated in the prior doc |
| Focus system (Tab order, `@FocusState`, `.focusSection`) | **Available**, confirmed accurate | `LuauUI.newFocusGraph` — flat/grouped scopes, `navigateDirection`, `traverse` (Tab/Shift+Tab) | Unchanged since Step 8 |
| Home/End/PageUp/PageDown/type-ahead | Missing, confirmed unchanged | Zero matches | Unchanged |
| Escape / modal keyboard dismiss | Partial, confirmed unchanged (citations moved) | Escape still permanently engine-reserved for the CoreGui menu; bindable Cancel remains gamepad ButtonB only; keyboard/mouse close is screen-provided | Unchanged in substance |
| Delete/Backspace hardware key (row-actions) | Partial, new this branch | Dedicated `sink=true, priority=10000` InputContext per row, built lazily on first focus-entry, disabled whenever focus leaves the row's own subtree, inert while the row's own menu is open | New |
| Assistive-technology bridge (VoiceOver/TalkBack equivalent) | **Missing**, confirmed unchanged | Repo-wide grep for `screenreader`/`voiceover`/`talkback`/`AccessibilityService`/`accessibilityLabel`/`aria`/`assistive` → zero real hits outside design-intent comments and directory naming | Unchanged. Headline rating stands |
| Engine-selection bridge (`GuiService.SelectedObject` mirror) | Partial, experimental — **a real capability the prior doc mis-described** | Shipped, opt-in, modal-only: `engineSelectionBridge: boolean?` on `presentModal`, `kind ~= "screen"` gate (passive surfaces never opt in), `adapter.setEngineSelection` literally sets `GuiService.SelectedObject`. Still gated behind a physical-device row before it is contract | **Changed since baseline, and the doc's supporting citation was stale** — see §1 stale-claims list. Does NOT touch VoiceOver/TalkBack |
| Dynamic Type equivalent (large-text/`PreferredTextSize`) | Partial, confirmed largely unchanged | Measured offsets {0,4,10,14} for Medium/Large/Larger/Largest, live `PreferredTextSize` subscription — unchanged since Step 8.5. Every automatable acceptance row `PASS_AUTOMATED`; the physical-phone-at-Largest row and the subjective-feel row remain `PENDING_PHYSICAL`/`PENDING_HUMAN` | Confirmed unchanged — this is the one accessibility area where the prior doc did not need correction |
| Custom accessibility actions (`.accessibilityAction`) | Missing, confirmed unchanged | Zero repo hits | Unchanged |
| `ControlContract.accessibility` | Partial — prose only, confirmed unchanged | `contract.luau:21` — typed as a readable summary string; sole consumer asserts only non-empty | Unchanged |
| Hover | Partial — real but framework-internal only, a gap not previously itemized | Framework-automatic, pointer-gated chrome effect (`target_contract.luau:42-47`, `screen_target.luau:3501-3529`); **no SwiftUI-`.onHover`/`isHovered` equivalent** — zero grep hits for a consumer-facing hover state. A narrower dwell-based seam exists for one feature only (truncated-text disclosure) | **New finding, not a code change** — a real, previously uncalled-out parity gap |
| Pointer styles (`.pointerStyle`, cursor shape) | Partial — seam live, no shipped art, unchanged | `cursorHint` prop on `UI.Grip` only; `CURSOR_ART` table still empty — falls back to the default arrow for any unmapped hint | Unchanged |
| Haptic / sensory feedback surface (`sensoryFeedback` equivalent) | Composable — real intent layer, confirmed new, live-consumed | `src/present/feedback.luau` — a closed v1 taxonomy of 12 verbs, causal-frame-synchronous emission, quarantined subscriber errors. Explicit design rule: "LuauUI PLAYS NOTHING." **Confirmed live-consumed by RascalRally** (`games/RascalRally/code/src/client/LuauUISponsor/PlayFlow.luau:609`). No `VibrationMotor`/`HapticService` reached anywhere by design | **New since baseline** — the doc's own §0 delta table said "No public semantic feedback event surface." Now stale — corrected in §1 |
| Four-input + paradigm conformance proof coverage | Available, materially expanded | **15 of 15** interactive controls prove four-input reachability and the paradigm axis (up from 8/8 at the 595-test baseline), across 16 registered classes and 153 conformance specs | Expanded — a 9th composite class (`RowActions`) added to the proof set |

**Gaps:** gesture machinery fragmented across four independent
implementations, none sharing axis-lock and only two sharing a velocity
tracker; `touch_gestures.luau`'s normalized `Gesture` type and ranked arbiter
are dead code from any control's perspective; row-actions' menu has no touch
long-press or mouse secondary-click trigger — of the five named
secondary-action mechanisms, 3 are real and 2 are absent; no
`onKeyPress`-equivalent, no Home/End/PageUp/PageDown, no type-ahead; no
consumer-facing hover state; no assistive-technology bridge of any kind;
`docs/adr/ADR-0014-first-responder.md` is stale (still frames the selection
bridge as an unprobed open risk though the probe ran and shipped); six
`NEEDS_PHYSICAL_DEVICE` riders newly owed by this branch (§6); keyboard
modifier support covers Shift only, Ctrl/Cmd collapsed into one untracked
group, Alt/Option untracked at all.

**Strengths:** row-actions delivers a real, tested, per-input-class
secondary-action model as a general public construct, closing a chunk of the
framework's own roadmap item earlier and more completely than the framework's
own committed docs reflected; Delete/Backspace and the action menu are
correctly gated on live focus-graph subtree ownership; the RED-TEAM
adversarial gate on the whole row-actions feature is closed with a real fix
history, not just a green count; the general drag/drop system matured
substantially; the semantic feedback bus is a genuine, narrow answer to
`sensoryFeedback`, already proven by a live production consumer; the
engine-selection bridge is a careful, reversible, opt-in experiment, not an
overclaim; four-input + paradigm proof coverage nearly doubled (8/8 → 15/15).

Verification for this area:
```
./run-tests.sh                        → 4038 passed, 0 failed
lune run tools/lune/check_registration_cli
  → PASS (16 controls, 87 exports documented, 153 specs registered,
     15 interactive controls prove four-input, 15 prove the paradigm axis)
lune run tests/conformance/corpus_cli → a11y-l10n-corpus: 15/15 passed
```

### 3.6 Motion & Animation

SwiftUI baseline confirmed current for June 2026/WWDC26 (Xcode 27):
`withAnimation`/`Transaction`, `.spring()` response/damping-ratio, `phaseAnimator`/
`keyframeAnimator`, `.transition(.insertion/.removal)`, `matchedGeometryEffect`,
`.scrollTransition`, `.sensoryFeedback`, Reduce Motion — none deprecated or
replaced by WWDC26. This area is cross-checked against §3.1 State &
Reactivity's `withAnimation` finding and the two agree.

| SwiftUI capability | LuauUI status today | Evidence | Change since 2026-07-22 |
|---|---|---|---|
| `withAnimation` (implicit: wrap a plain state write and have downstream reads interpolate) | **Missing.** Animation is always explicit, separately-typed | No caller can wrap `signal:set()` and get interpolation; a caller constructs a `MotionValue` via `clock:spring`/`counter`/`glide`/`timer` and drives it with `setTarget`/`setVelocity`/`snap`; a plain bound `Signal<number>` always jumps | **New area since validation.** The whole motion authority (ADR-0022) postdates 2026-07-22 and was never assessed by the old doc |
| Spring animation (`.spring(response:dampingRatio:)`) | **Covered**, response/damping-ratio model matching SwiftUI's, not stiffness/mass | `export type Params = { dampingRatio: number, response: number }` — deliberately "TWO numbers, never mass/stiffness/damping." Four named classes ship (`container`, `object`, `reward`, `decay`). An inline literal at a call site is a **hard error** naming `registerClass` — a design-system-enforced difference, not a gap | Unchanged in mechanism; the whole subsystem is new since 2026-07-22 |
| Spring interruption / retargeting | **Covered — interrupt-continues, independently proved** | `setTarget` never touches value or velocity — restated at three call sites. Tests include a differential test: a velocity-cut twin travels measurably less on the next frame than the carried-velocity spring; a visible-jump regression fails this | New since 2026-07-22 |
| Animation completion (`withAnimation(completionCriteria:completion:)`) | **Covered**, callback-based (no awaitable form) | `MotionValue:onSettle(fn)` fires exactly once per arrival, after the frame's writes commit | New since 2026-07-22 |
| `phaseAnimator` | **Missing.** No looping/state-driven phase construct | Zero hits for `phaseAnimator`/`phase_animator` | New area; still absent |
| `keyframeAnimator` | **Partial-only, via a different shape** | `clock:timeline(spec)` is beat-sequenced choreography with `interrupt()`/`skip()`, but each beat is a callback, not a per-property value track with its own curve, and a timeline never loops | New area; still no phase/keyframe declarative primitive |
| `.transition(.insertion/.removal)` on identity-diffed views | **Covered — a general, reusable primitive, independently of row-actions** | `UI.ForEach{transition?}` shares a generic structural-region prop with `When`. Forms: `fade`, `slide-*`, `materialize`, `instant`. A removed row RETIRES in place (stays mounted at its clamped slot, non-interactive, disposes on exit-complete) rather than vanishing, 500ms hard exit cap | **New since 2026-07-22.** The old doc's honest-approximations list still said "no secondary-action model yet" for swipe-row actions — that gap is closed by a different mission (row-actions); the *general* ForEach transition primitive is a separate, earlier capability the old doc never assessed at all |
| Row-actions' own commit-collapse | **Bespoke, not routed through the general ForEach transition above** | `row_actions.luau:875-887` builds a **second, independent** `"object"`-class spring purely to animate `rowHeightOverride` toward 0 — a per-control application of `clock:spring`, not `UI.ForEach{transition=}` | New since 2026-07-22 |
| `matchedGeometryEffect` | **Missing.** No cross-tree geometry interpolation exists | Zero hits for `matchedGeometry`/`heroTransition`/`sharedElement`. Nearest adjacent capability (`virtual_list.luau`'s `slideRow`) animates a row's offset delta within the same list, not a shared-identity transform between two different layout trees | Unchanged — still the framework's stated honest approximation |
| `.scrollTransition` | **Missing** | Zero hits for `scrollTransition`/`scroll_transition`. No API ties paint to live scroll-position proximity to the viewport edge | New gap surfaced by this audit; not mentioned in the 2026-07-22 doc |
| `.sensoryFeedback` (haptics tied to state changes) | **No host equivalent by design, not by omission** | `src/present/feedback.luau`: "LuauUI PLAYS NOTHING." A closed, versioned taxonomy fires synchronously on the causal frame for the game to map to its own haptics/sound policy | Unchanged philosophy; the bus itself (ADR-0022 Decision 7) is new since 2026-07-22 |
| Reduce Motion adaptation | **Covered — live-read, categorized, information-preserving** | Live OS signal (`GuiService.ReducedMotionEnabled`), read every retarget not boot-snapshotted; categorized decorative (snaps instantly, still fires `onSettle`) vs informational (keeps running to the same terminus, quantizes writes to a 250ms quantum) | New since 2026-07-22; the old doc's only RM mentions predate this machinery entirely |
| Animated numeral / `.numericText`-class emphasis | **Covered**, plus a compositional "hold/count/land" layer SwiftUI has no single built-in for | `clock:counter` publishes whole numbers only and never overshoots the target it's counting toward. `motion.newValueReveal` composes "must not state its new value before its moment, must never withdraw a stated one" — 5 documented rules, exhaustively tested | New since 2026-07-22 |
| Countdown/depleting timer, gauge | **Covered** | `clock:timer(spec)` advances by raw wall-clock `dt`, not frame-clamped, so a frame spike can't stretch a countdown | New since 2026-07-22 |
| Gesture → animation velocity handoff | **Covered — shipped for both general drag flights and row-actions flick momentum** | Velocity tracker (`drag_velocity.luau`, 100ms rolling window); drag-flight handoff (`flyTo` seeds velocity then chases a live target); row-actions flick momentum reads the tracker at release and seeds the persistent spring's animation | **New since 2026-07-22** — this whole seam postdates the validated baseline |
| 2-D "arrives at a live, moving target" motion | **Covered — a named primitive with no direct single-API SwiftUI equivalent** | `clock:chase(opts)`: two scalar springs against a live, re-read-every-frame target, firing `onArrive` once it enters a perceptual arrival radius (default 4px) rather than waiting for the physics settle epsilon, which the framework measured trails perceived landing by ~0.7s | New since 2026-07-22 |

**Strengths:** one spring, one progress value, every visual form derived from
it (offset/scale/alpha off a single `[0,1]` progress spring, so a form can
never disagree with itself mid-flight); `ForEach` transition identity
survives mid-exit re-entry (stronger than SwiftUI's default remount); Reduce
Motion is an information-parity contract, not a binary switch; the
interrupt-continues invariant is proved by a differential test, not just
documented; perceptual-arrival chase directly targets a UX defect class
SwiftUI developers must discover and hand-roll a fix for.

**Gaps:** no `withAnimation`-equivalent implicit coupling — the single
largest structural gap versus SwiftUI's authoring ergonomics in this area; no
`phaseAnimator`/`keyframeAnimator`; no `matchedGeometryEffect`/shared-element
transition subsystem; no `.scrollTransition`; row-actions' commit-collapse is
a second bespoke spring rather than a use of the general transition
primitive (a future generalization could unify them); `.sensoryFeedback` has
no in-framework playback by explicit design, not scored as a gap.

Verification for this area: `./run-tests.sh` — **4038 passed, exit 0**.

### 3.7 Performance

SwiftUI comparison points (June 2026): Instruments/SwiftUI graph diagnostics
(view-body invalidation counts, render-loop timing in-IDE), `List`/
`LazyVStack` virtualization behavior, per-property invalidation granularity.

| Capability | Status | Evidence | Change since 2026-07-22 (v0.5.0) |
|---|---|---|---|
| Named, production-shaped workloads | **Present, expanded** | `bench/perf_scenes.luau`; `examples/performance/lab/perf_lab.luau` — nine workloads (`idle-baseline`, `mount-ramp`, `dense-scroll`, `dense-scroll-native`, `collection-churn`, `layout-style-churn`, `large-text-overflow`, `async-image-churn`, `lifecycle-soak`) | New: the nine-workload lab place, `check_perf_place.py` doctor, `tools/build_places.sh` |
| p50/p95/p99 headless timing | **Present, unchanged in kind** | `bench/perf_runner.luau:413-415,461-471`; `tools/perf.sh` | Same mechanism the prior audit credited; now also exercised by `artifacts/row-actions/perf_workload.luau`'s scroll/fling/idle passes |
| Regression budgets as executable tests | **Present, materially deepened** | `bench/perf_budgets.json`; `tests/perf_principles.spec.luau` — five WORK-SCALES/CACHE-KEY/NOTHING-BUILT/UNCHANGED-VALUE/CHEAP-PATH rules encoded as ratio/invariant tests, not wall-clock | New: the perf-principles suite itself, each rule annotated with the real historical regression it once caught |
| Heap/reactive counters | **Present, unchanged in kind** | `handle.controller.stats()` (`propWrites`, `rectWrites`, `creates`, `removes`, `lastArranged`, `lastSkipped`); lifecycle census (GuiObjects/signals/memos/scopes) | Census now proven zero-drift across 8 identical cycles (`lifecycle-soak` workload) |
| MicroProfiler phase attribution | **New capability, not in prior audit** | `src/core/profile.luau` — nine closed phase scopes (`mutate`, `react`, `measure`, `arrange`, `commit`, `mount`, `resource`, `scenario`, `reset`) | Fully new; a fixed, closed set (scope count does not scale with row count) |
| Instance-cost engineering | **New capability, shipped and measured** | Instance recycling (park/adopt); themed recycling; incremental layout v2 (141→8, ~17×); inert-container elision (GuiObjects 137→91, −34%); lazy `UIScale` (framework-wide −10% instances) | All new since v0.5.0 |
| Device-performance proof (`deviceRun`) | **Still false — unchanged verdict from prior audit** | `artifacts/phase-4/perf.json`: `"deviceRun": false`, `"authoritative": false`, `"evidenceLevel": "E1"`, timestamped 2026-08-08. `bench/perf_budgets.json`'s `skippedDeviceBudgets` lists `phone-physical`/`desktop-retail`/`console-physical` all `PENDING_PHYSICAL` | **No change.** The prior audit's exact finding stands. The full phone-capture procedure is now documented in detail an agent can execute — the artifact slot itself remains unfilled |
| Row-actions feature perf cost | **New finding this cycle — budget missed, gated honestly** | See §5 below and `docs/plans/row-actions-perf-mission.md` | Not applicable to the prior audit (feature didn't exist at v0.5.0) |

**The row-actions scroll-cost finding** (see §5 for the full table and root
cause): a closed, wrapped row inside `LuauUI.newVirtualList` costs **+57%
steady-scroll / +81% fling / +5.00 nodes-per-closed-row** versus an unwrapped
row (200 rows, 13-row window). Root cause: ~98% of the delta is the shared
renderer/solver's cost of creating, measuring, and destroying 5 extra
Instances on every virtualization window-membership crossing, confirmed by a
scratch build forcing a true-inert-passthrough path (zero extra instances,
recovered wall time to within ~10% of baseline) — not row-actions' own
reactive-graph construction (~2% of the delta). The gate was re-baselined by
director ruling 2026-08-11 to the measured ceiling (steady ≤57%, fling ≤81%,
instances ≤5) rather than the original ≤5%/≤4 plan budget, which stays on
record as "missed, not massaged." The concrete next lever is named, not
started: a `VirtualList`-level gesture-composition hook (mirroring `table.luau`'s
`composeWithReorder`), or generic cell recycling in `VirtualList`.

**Where LuauUI's invalidation granularity stands vs. SwiftUI's:** a single
bound-value change costs the same at 100, 800, and 3200 rows — work scales
with what changed, not with what exists, enforced as a ratio test.
Incremental layout v2 narrows a single bound change from re-solving the full
tree to only its relayout boundary (~17× on the measured surface). The
sharpest current counterexample is the row-actions finding above — a windowed
list's virtualization boundary crossing is coarser-grained than SwiftUI's
`List`/`LazyVStack` recycling (which reuses cell identity/views rather than
destroy+recreate for anything wrapped in extra structure); LuauUI's own
instance recycling exists and is proven for the *unwrapped* row shape, but
`VirtualList` has no cell-recycling seam for a composite-wrapped row today.

**Strengths (new since prior audit):** the perf-principles suite reduces five
historically-real regressions to standing, ratio-based executable tests; a
nine-workload self-contained performance lab place with a build doctor,
scriptable driver, and a documented low-end-Android capture procedure a
Studio-relabeled row cannot spoof; real instance-cost wins shipped and
measured; honest gate discipline — the row-actions perf gate was re-baselined
to a measured ceiling rather than silently passing or being deleted, with a
named follow-on mission on file rather than a dropped TODO.

**Gaps:** device-performance proof is still absent — the single largest
unchanged item from 2026-07-22; row-actions' wrapped-row scroll/fling cost is
57–81% over baseline, gated at the measured ceiling rather than the original
≤5% target; `VirtualList` has no cell-recycling seam for composite-wrapped
rows — a gap that would affect any future consumer wrapping a `VirtualList`
row in extra structure, not just row-actions.

Verification for this area: `python3 tools/check_row_actions_matrix.py` →
exit 0; `tools/test.sh 4038` → `PASS passed=4038`.

### 3.8 Presentation & Surfaces

SwiftUI baseline: WWDC26/iOS 27/Xcode 27 surface (sheets,
`.confirmationDialog` item-binding, `.presentationDetents`, `.inspector`,
`NavigationStack`/`NavigationSplitView`, zoom/cross-fade navigation
transitions), confirmed by web search this session.

| Capability | Status | Evidence | Change since 2026-07-22 (v0.5.0) |
|---|---|---|---|
| `.sheet` (modal presentation) | **Partial** | `presenter.presentModal`; focus trap via `graph.pushScope`; priority `+500` per stacked depth above `BASE_SCREEN_PRIORITY = 1500` | **Materially deepened.** `cancelPolicy`, `scrim`, `outsideTapCancel` swallow semantics, and `initialFocus` are all new opts, validated at present time (`specGuard.assertKnownKeys`). None existed as named policy at v0.5.0 |
| Zone A/B outside-tap dismissal | **Available** internal mechanism (no public surface mirrors SwiftUI's `.interactiveDismissDisabled`) | `src/present/modal_zones.luau` (`zoneAContains`, `modalInZoneA`, `inflateToFloor`): Zone A = painted panel ⊕ 24px forgiveness ring ∪ each focusable's 44px hit rect; Zone B = everywhere else | **Extracted into its own module** (2026-08-06) and **the ring is now theme-derived**, not a magic number — it scales with theme metrics |
| `.fullScreenCover` | **Composable** | Recipe unchanged: `presentModal` + `rootPolicy="edgeToEdge"` + a full-bleed root | No change |
| `.alert` | **Composable** | Recipe unchanged | **No item-binding pattern** — SwiftUI's June 2026 `.alert(item:)`/`.confirmationDialog(item:)` has no LuauUI analogue; a consumer wires its own signal |
| `.confirmationDialog` | **Composable** | Recipe unchanged | Same gap as `.alert`; Button's new `role` prop supplies *some* of SwiftUI's role-driven tinting but nothing orders/tints a Cancel row automatically |
| `.popover` / transient panel | **Partial** | `newPopupButton` + `presenter.syncPopupCatcher`/`topPopupCatcherPath` | No material mechanism change; the catcher now supports a `consume == false` opt-out (row-actions Task 7 finding) so a popup can let a tap-away close it without swallowing the tap for the control underneath |
| `.contextMenu` / `.swipeActions` (generalized secondary-action container) | **Available** (first-class construct, not a recipe) | `LuauUI.newRowActions`; leading/trailing trays, `fullSwipe` commit, keyboard Delete/Backspace + Shift+Return, gamepad ButtonX/ButtonB, `newRowActionsCoordinator` | **This is the headline delta.** The v0.5.0 audit's #1 planning item ("Generalized `swipeActions` containers — Missing") has shipped as a general composite, any row content can be wrapped |
| The row-actions floating menu (`bindPresent`) | **Available**, architecturally significant | `row_actions.luau:675-838`; contract seam `bindPresent` in `src/input/contribution.luau:138-161` — deliberately `presentModal`, never `present` (two `kind=="screen"` surfaces sharing one priority band would double-deliver Navigate/Activate/Cancel) | **New public seam.** Closes the exact RED-TEAM-caught defect where the first implementation measured the menu as a child of the row, inflating the row (and, inside a Table, the whole list). A pinned test asserts a sibling row's solved rect is byte-identical whether the menu is open or not — a reusable pattern for any future secondary-surface composite |
| `ButtonRole` (destructive/cancel tinting) | **Partial** (upgraded from Missing) | `role: "normal" \| "destructive"` on `ActionSpec` paints the shipped danger/onDanger style rule | The prior doc stated flatly "No `ButtonRole`." `Button` now accepts a destructive role with a real style mapping. Still narrower than SwiftUI (no `cancel` role, no automatic dialog-row ordering) |
| `NavigationStack` (screen push/pop) | **Partial**, unchanged verdict | `presenter.presentModal` pushes, `back()` pops the top *modal*, `depth()` reports stack size | **No change.** Confirmed by source grep this session: no `pushScreen`/`navigationPath`/`screenStack` construct exists anywhere. Remains modals only |
| `NavigationSplitView` / `.inspector` | **Missing** | Zero hits for `inspector`/`NavigationSplitView`/`windowGroup`/`scene phase` outside one unrelated colloquial comment | No change; not attempted this window |
| Presentation detents (`.presentationDetents`) | **Missing** | Zero hits for `detent`/`presentationDetents`/`sheet size` | No change. A modal's size is whatever its blueprint measures to; no draggable/snap-to-fraction sheet contract. Now a materially bigger gap given detents' 2026 mainstream status in SwiftUI |
| Toast / transient feedback surface | **Available** | `presenter.presentToast`; scheduling in `src/present/toast_schedule.luau` (351 lines, pure/headless) | **Shipped in full since baseline** — the v0.5.0 Presentation table had no toast row at all. Max 3 visible, queue cap 8, priority-ordered FIFO, four typed dismiss reasons, reduced-motion parity, input-transparent by construction |
| Semantic feedback bus | **Available** | `presenter.onFeedback`/`emitFeedback`; closed v1 taxonomy of 12 verbs | Present at v0.5.0 in nascent form; now fully wired into presenter surface lifecycle and toast supersede. LuauUI still plays nothing |
| Focus trap / restore stack | **Available** | `graph.pushScope`/`popScope`/`removeScope`; modal use; transient-popup trap/restore | Unchanged mechanism, now demonstrably reused by row-actions' floating menu — evidence the mechanism generalizes beyond PopupButton, its original proving ground |
| `engage()`/`resign()` passive responder | **Available** | `handle.engage`/`handle.resign`; `responder = "passive"` opt | Unchanged since ADR-0014; confirmed still live this session (full suite green) |
| `exclusiveSurfaceActive` | **Available** | A `Readable<boolean>` | Not present as a named public Readable in the v0.5.0 audit text — new or previously undocumented |
| `SURFACE_LAYER` display-order bands | **Available** | Five bands (`base < toast < dragProxy < modal`) rather than one running counter | **New naming/documentation since v0.5.0**; the mechanism (an incrementing `displayOrder`) existed before, the band model and guarantee are now explicit |
| Full-value disclosure plate | **Available** | `presenter.disclosure()` — presenter-private surface, not in the stack, no focus scope, no input context | Not present in the v0.5.0 Presentation table at all; predates row-actions, postdates the July audit |
| Auto-reveal marquee | **Available** | `presenter.reveal()`/`presenter.movingText()` | Same as above — post-v0.5.0 addition |
| Structural transitions (surface enter/exit) | **Available** | `opts.transition` on `present`/`presentModal`; `dismiss` defers teardown to `coordinator.beginExit`, flat 500ms exit cap | Present at v0.5.0 as ADR-0022 Decision 3, unchanged in mechanism. A departing-surface focus-ring bug (fixed 2026-08-03) is new since July, a correctness fix not a new capability |
| Keyboard/gamepad modal dismissal parity | **Partial**, unchanged verdict | `ButtonB` bound to Cancel; Escape permanently CoreGui-reserved | **No change.** A keyboard-only user still has no framework-level Escape-to-dismiss |

**Honest items:**

- **Navigation-stack equivalent status**: LuauUI has no push/pop
  screen-navigation model — only surface stacking. Exactly one `kind` besides
  `"modal"`: `"screen"`. Two `present()` screens share one priority band (the
  reason `bindPresent` only ever hands out `presentModal`) — no
  "navigate from screen A to screen B" with title/back-button/transition; a
  consumer swaps blueprints under one `present()` call by hand. No
  `NavigationPath`-equivalent, no deep-link/state-restoration surface. Confirmed
  unchanged by source search this session.
- **Detents**: confirmed missing by grep. Building one would need
  canvas-height-aware drag physics that don't exist anywhere in the
  framework — the closest primitive, `Grip`, is a 1-D value-adjuster, not a
  sheet-height controller.
- **Alert/dialog vocabulary**: still Composable recipes, unchanged. `Button`'s
  new `role: "normal"|"destructive"` narrows the gap without closing it —
  still no automatic Cancel-row ordering, no destructive-role-driven
  placement, no item-binding sugar.

**Strengths:** the presenter's option surface is closed and validated, not
`any` — this closes exactly the class of bug the prior audit most worried
about, for the presentation surface specifically; the row-actions floating
menu is a genuine architectural generalization, not a one-off; toasts and the
feedback bus are fully specified and input-transparent by construction; modal
dismissal geometry is theme-derived, not a hardcoded pixel value; **4038/4038
tests passed** this session including the full presenter, toast-presentation,
presentation-channel, and presenter-drag-integration suites.

**Gaps:** no navigation-stack equivalent for screens — the single largest
structural gap against `NavigationStack`/`NavigationSplitView`, unchanged
since July; no detents; no item-binding sugar for alert/dialog/sheet; keyboard-only
modal dismissal still has no framework-level Escape (an engine constraint,
not a library choice); no `.inspector`, no window/scene management, no zoom
navigation transition — none investigated in depth this session, continuing
"not yet attempted" rather than a regression.

Verification for this area: `./run-tests.sh` → **4038 passed, 0 failed**
(this session, HEAD `fff48b2`).

### 3.9 Tooling, Authoring Model & Agentic Maintainability

| Capability | Status | Evidence | Change since 2026-07-22 |
|---|---|---|---|
| Strict spec validation, unknown-property refusal | **Covered, shipped and live** | Live repro this session: `LuauUI.UI.Button({ lable = "hi" })` → `false  LuauUI UI.Button: unknown property 'lable'. Did you mean 'label'? Valid properties: ...` | **Reversal of the old top material gap.** This was the July doc's own named blocker for further API growth |
| Typed public constructor surface | **Covered — large expansion** | **51** exported `*Spec` types (`grep -c "^export type.*Spec" src/blueprint.luau src/controls/*.luau`); public core types re-exported at `src/init.luau:36-40` with the comment naming the prior defect directly: "the library's own boundaries said `core: any` 35 times" | **New since validation.** `grep -c ": any" src/init.luau` today returns 1, inside the explanatory comment quoted above, not a live type |
| Property-authority reconciliation (schema ⇄ dirty-map ⇄ render-authority ⇄ adapter ⇄ layout ⇄ docs ⇄ types) | **Covered — a new checker class** | `tools/lune/check_prop_parity.luau` reconciles six independent views of every declared property — the direct fix for the old audit's named live bug (`Text.color` silently dropped) | **New since validation** |
| Conformance registry | **Covered, exercised live during this feature** | `tests/conformance/controls_registry.luau` (919 lines); enforced by `tests/extension_checker.spec.luau` | Machinery predates 2026-07-22; row-actions is now a live trial of it — see the "core claim" below |
| Docs/exports drift check | **Covered** | `tools/lune/check_docs.luau` + CLI; the 0.8.0 documentation package closed all 14 tolerance entries and the tolerance list has stayed at zero | Tolerance-to-zero happened before this branch; row-actions' Task 12 re-touched `docs/reference/api.md` and passed the same zero-tolerance bar |
| Example-gallery property-authority drift lint | **Covered — new checker class** | `tools/lune/check_example_drift.luau`: reads its role vocabularies live from the framework itself, fails on raw-number style-owned props, unknown string roles, raw colors, engine reach-arounds | **New since validation** |
| Surface-ledger coverage check | **Covered — new checker class** | `tools/lune/check_surface_ledger.luau`: verifies every top-level export and nested-namespace member of the live public surface appears in `artifacts/api-architecture-consistency/surface-ledger.md` | **New since validation.** *Live-verified this session: currently FAILING — `newRowActions`/`newRowActionsCoordinator` are not yet classified in the surface ledger. Flagged as a concern; not part of the row-actions gate's three required checks and not in scope for this document's own rewrite* |
| Client/server require-graph boundary check | **Covered** | `tools/lune/check_boundary.luau` (97 src files, 379 consumer files, live-verified PASS this session) | Machinery predates the validation date |
| Gate system (phase-gate manifest + integrity + prior-gates re-run) | **Covered — 25 named gates today** | Includes `row-actions` (this branch); `python3 tools/check_manifest_integrity.py` → `650 suite greps, all anchored to the pass marker`, exit 0 live-verified | **Grown by one gate** since validation |
| row-actions gate, live-verified this session | **PASS** | `check_row_actions_matrix.py` → "functional matrix intact, perf numbers within re-baselined ceilings: steady <= 57.0%, fling <= 81.0%, instances <= 5.0"; `./run-tests.sh` → 4038 passed | This branch's own gate, closed 2026-08-11 |
| Scenario verification surface for Studio drives | **Covered** | `examples/gallery/scenarios/runner.luau:1359` builds a `LuauUIScenarioAPI` Folder of BindableFunctions consumed by MCP Studio drives | Predates validation, actively reused by row-actions' five-view device matrix |
| Deterministic render dumps | **Covered** | `tests/conformance/corpus_cli.luau`; per-control `dump()` seam required by the scaffold template and the registry | Unchanged mechanism; new instances added per control incl. row-actions |
| Runtime `controller.diagnostics()` surface | **Covered, live in source** | `renderer.luau:3754-3756`: a defensive copy, same pattern as `controller.stats()` | Present pre-validation; project memory records this exact surface catching a shipped layout defect a screenshot review missed |
| Reference apps (clean-room SwiftUI-scale proofs) | **Covered — 5 apps** | `examples/reference/{p1_glade,p2_cartwheel,p3_sipworks,p4_foyer,p5_wardrobe}/` | **New since validation** — Step 11, closed 2026-08-09 |
| Extension scaffold | **Covered** | `tools/lune/scaffold.luau` — stamps source with a `build()` seam + dump surface, a deliberately-failing TODO spec, and registration edits so a scaffolded control cannot ship silently unregistered | Predates validation, unchanged in this range |
| Extension playbooks | **Covered — 6 playbooks** | `docs/extending/{new-control,new-engine-feature,new-platform-mode,new-render-target,new-theme,skinned-control}.md` | Unchanged count/mechanism; `skinned-control.md`/`new-theme.md` back the theme-packages stage, which is new since validation |
| Deprecation policy | **Covered** | ADR-0011: machine-readable `LuauUI.DEPRECATIONS` ledger; a deprecated surface keeps working ≥1 MINOR version | Unchanged mechanism; version bumped 0.8.0 → 0.9.0 in this branch |
| Fuzz / fault / soak tooling | **Covered** | `tests/fuzz_layout.spec.luau`, `fuzz_replication.spec.luau`, `fuzz_scheduler.spec.luau`, `faults.spec.luau` | Unchanged inventory; the old ScrollView `axis="x"` defect is a named example of what a no-throw-only fuzz oracle still misses — a residual gap, not re-investigated this session |
| Xcode Previews / `#Preview` + resize-testable Live Previews | **Missing (no Roblox analogue), mitigated** | No in-editor live-preview-with-state surface exists for LuauUI in Studio. Mitigated by deterministic dumps, the reference-app corpus, `LuauUIScenarioAPI` Studio drives, and the showcase place — but none is a live, resizable, hot-reloading in-IDE preview | SwiftUI's June 2026 delta added interactive resize handles to Live Previews (Xcode 27/WWDC26). LuauUI's device-matrix drives are a batch/scripted analogue, not interactive |
| Instruments-class runtime profiling | **Partial — headless only, not device-integrated** | `tools/perf.sh`/`tools/bench.sh` give p50/p95/p99 headless timing with versioned regression budgets; row-actions' own perf work measured honest regressions against a self-declared budget, missed it, and the gate was re-baselined rather than silently waived | SwiftUI's June 2026 delta: Xcode 27 Instruments added Processor Trace, an updated CPU Counters instrument, expanded Swift Concurrency visibility, a hitches metric. LuauUI has no on-device, symbolicated, UI-specific profiler equivalent; `deviceRun=false` for every perf artifact |
| Compile-time strict typing / refactoring safety | **Partial — runtime-enforced, not compiler-enforced** | `--!strict` Luau + the property-authority/prop-parity/registration checkers + a 4038-case suite, all running in seconds, catching misuse at test time not edit time | SwiftUI's 2026 direction is compiler-level (Swift 6 strict concurrency as the mandatory default). LuauUI cannot get compiler-enforced data-race safety from Luau; its equivalent is a fast, comprehensive, runtime/test-time layer |
| Documentation culture | **Covered, mechanically enforced — a stronger claim than DocC alone provides** | `check_docs.luau`, `check_surface_ledger.luau`, `check_example_drift.luau` together enforce that docs, the live export table, and tutorial examples cannot drift from shipped code without failing a gate | DocC (2026) is fundamentally a doc-generation/publishing tool, not a doc-drift enforcement gate |

**The core claim re-tested: "agentic development" as a strength axis.**
Verdict: still true, and the row-actions branch is the strongest evidence yet
— not because the machinery is new, but because it caught a real mistake in
real time, repeatedly, exactly as designed. Task 1's registration checker
caught a missing conformance-registry row **and** an implementer's incorrect
claim that the failure predated their change; a second, distinct trap in the
same task found the registry checker's own name-matching pattern couldn't see
an underscore-containing export, silently passing when it should have
failed; a location-based architecture correction ("module moves to
`src/input/`... avoids forced public export from the `controls/` walker") was
steered directly by the registry's shape of enforcement; the identical class
of failure recurred at Task 9 ("api.md whole-file sweep AGAIN — 5th
foreign-sweep incident") and the RED-TEAM whole-feature pass found 16 issues
under an all-green suite — the registry catches *absence*, RED-TEAM catches
*presence of wrong behavior*, and they are complementary, not redundant. **One
caveat that keeps this axis "strength" rather than "solved":** the machinery
frequently failed to prevent the *first* instance of a mistake — it only
refused to let it merge. The foreign-sweep problem recurred at least five
times on this one branch, a process/isolation gap (agents sharing one working
tree), not a conformance-machine defect.

**Gaps:** no live, in-editor, hot-reloading preview equivalent to `#Preview`
(named in the July audit, unchanged); no compiler-enforced type/concurrency
safety comparable to Swift 6; no on-device, UI-specific profiler equivalent
to Xcode 27 Instruments; the registration/doc machinery is a backstop, not a
preventer, for shared-working-tree mistakes (real friction it repeatedly
absorbs, not a tooling defect); the residual fuzz-oracle weakness (a fuzzer
asserting only no-throw/finite/determinism can pass over a real behavioral
bug) was not re-investigated this session and is carried forward unchanged.

Verification for this area:
```
./run-tests.sh                                    # 4038 passed, 0 failed
python3 tools/check_manifest_integrity.py         # exit 0: 650 suite greps, all anchored
python3 tools/check_row_actions_matrix.py         # exit 0: functional matrix clean
grep -c '^\t\["' tools/lune/gate_manifest.luau    # 25 gates
grep -c '^export type.*Spec' src/blueprint.luau src/controls/*.luau  # 51 exported Spec types
grep -c ': any' src/init.luau                     # 1 (inside an explanatory comment)
```

---

## 12. Reference-app validation (2026-08-08, roadmap Step 11)

*Carried forward from the prior revision, with one correction (marked below)
this cycle's area audits require. Its section number ("12") is kept as
originally assigned — several gate checks (`tools/lune/gate_manifest.luau`'s
`docs-updated` check, part of the closed `swiftui-reference-app-validation`
gate) anchor on the literal heading text below and on `UI.Stage`/`no host
equivalent` appearing in this document; renumbering it would break a passing
gate for no benefit.*

The question this document opened with — can a Roblox developer build the
in-experience parts of Apple's reference apps from one declarative
description — was answered with five running clean-room proofs (stage
`swiftui-reference-app-validation`; ledgers and evidence under
`artifacts/swiftui-reference-app-validation/`):

| Proof | Interprets | Representative loop proven |
|---|---|---|
| Glade (`examples/reference/p1_glade`) | Backyard Birds | supply drain/refill, visit schedule, premium consumables + three-tier subscription-shaped commerce with scripted rejections |
| Cartwheel (`p2_cartwheel`) | Food Truck | adaptive split navigation, live order arrivals, status machine + service-owned countdown surviving navigation, charts, entitlement gates, a `UI.Stage` 3D hero |
| Sipworks (`p3_sipworks`) | Fruta | catalog/search/favorites, order + rewards stamps + threshold redeem, purchase-shaped recipe unlock, deep localization incl. plural fixtures and a ≥1.4× pseudo-locale, and a compact entry flow sharing the full components |
| Foyer (`p4_foyer`) | Roblox app home (director-added scope) | sectioned discovery feed, friends carousel, search collapse, refresh/visit command lifecycles |
| Wardrobe (`p5_wardrobe`) | Roblox app avatar editor (director-added scope) | try-on with undo/redo history over a live `UI.Stage` mannequin, purchase lifecycle with visible rejections, split ⇄ stacked survival |

**What the stage changed in this document's own claims (2026-08-08):**

- **ScrollView "does not scroll" is long obsolete** (native `ScrollingFrame`
  since the native-substrate stage) — and this stage additionally made a hug
  scroller's MEASURE include the scrollbar its arrange reserves.
- **Grid**: cells fill their columns, and as of this stage the grid's
  measured size is a fixed point of its own report.
- **"No `ViewThatFits`, no adaptive stack"** is obsolete: `UI.ViewThatFits`,
  `UI.AdaptiveStack` and the screen-level `UI.Composition`/`UI.Region` carry
  all five proofs' adaptation with zero device-name branches.
- **New engine-content leaf `UI.Stage`** (ViewportFrame adoption): live 3D
  content inside a solver-owned box through `controller.stageHost` — the
  surface behind the avatar-editor preview and the dashboard's city hero.
- The **namespaced-icon ASCII floor** documented under the circle Button now
  actually exists (`package.iconGlyph` derives a glyph for `ns:name`).

**Honest approximations the proofs declare (unchanged classifications except
the one marked below):** shared-element/hero transitions (materialize modal,
no matched-geometry subsystem), 3D perspective card flips (width-collapse),
UI-over-UI blur (translucent surfaces — engine limit), area-fill charts
(banded strips; Path2D is stroke-only). **Correction (2026-08-11, row-actions):**
~~swipe-row actions (visible affordances; no secondary-action model
yet)~~ — **superseded.** `LuauUI.newRowActions` now delivers a real,
four-input-proven secondary-action model; see §3.3 Controls and §5 below.
Apple host-OS surfaces (widgets, App Clips, Live Activities, Dynamic Island,
WeatherKit, StoreKit/Pay chrome, Sign in with Apple) remain
**no host equivalent** ledger rows and are never simulated. The complete per-feature
classification lives in the stage's `capability-ledger.md` (itself not yet
updated for row-actions — see §3.3.2's residual-gaps note); the follow-on
candidates (reactive `compactLabel`, bindable `newLabel.title`, fill-in-hug
contribution, the rest) are in its `framework-fixes.md`.

**Late-stage additions from the live device matrix (same day, unchanged):**

- **The recycle pool can never hold a destroyed instance** — `parkEligible`
  now refuses an unparented instance and `adopt` guards the one write that
  can still detect one (`tests/instance_park_corpse.spec.luau`).
- **The ZStack overflow diagnostic is per-axis and fill-aware** — a `fill`
  axis is granted its box at arrange, so it is no longer reported as
  overflowing a box it cannot leave, confirmed live again this cycle
  (`tests/zstack_fill_diagnostic.spec.luau`, §3.2).
- **Two follow-on proposals with live evidence, still deferred** (confirmed
  unchanged this cycle, §3.2): a flow-stack compress step, and splitting the
  overloaded `align` channel.

---

## 4. Durable gaps

Cross-area gaps that no single mission is scoped to close, each with its
owning area section:

| Gap | Status | Owning area |
|---|---|---|
| Assistive-technology bridge (VoiceOver/TalkBack equivalent) | **Missing**, confirmed by fresh whole-repo grep | §3.5 |
| Materials / Liquid Glass-era translucency | **Missing, gap widened** against Apple's shipped Liquid Glass system | §3.4 |
| Navigation stack (`NavigationStack`/`NavigationSplitView`) / presentation detents / item-binding sugar | **Missing/Partial** — modal stacking only, no screen push/pop, no detents | §3.8 |
| `matchedGeometryEffect` / `phaseAnimator` / `keyframeAnimator` / `.scrollTransition` | **Missing** | §3.6 |
| `layoutPriority` shrink negotiation / alignment guides | **Missing, deliberate non-goal for the former** | §3.2 |
| Palette Picker | **Missing** | §3.3 |
| RTL / BiDi | **Missing** — row-actions' leading=left/trailing=right is an explicit non-goal, matching the framework-wide absence | §3.3, §5 |
| Device-run performance proof | **Absent** — `deviceRun=false`, `evidenceLevel=E1`, unchanged since 2026-07-22 | §3.7 |
| Gesture-layer fragmentation | **Confirmed and deepened** — four independent implementations (touch-gesture arbiter, general drag contract, row-actions' own axis-lock, Table's reorder drag), none sharing axis-lock code | §3.5 |
| `#Preview`-equivalent authoring loop | **Missing (no Roblox analogue), mitigated** by batch/scripted device-matrix drives, not interactive | §3.9 |
| `*Style` protocols (`ButtonStyle` etc.) | **Missing**, the sharpest structural divergence from SwiftUI | §3.4 |
| Cell-recycling for composite-wrapped `VirtualList` rows | **Missing** — the concrete lever the row-actions perf mission needs | §3.7, §5 |
| Surface-ledger classification for `newRowActions`/`newRowActionsCoordinator` | **Live-failing check**, found during this audit's own verification pass; not part of the row-actions gate's three required checks, out of scope for this rewrite | §3.9 |

---

## 5. Row-actions feature (2026-08-09→11, roadmap Step 14)

The mission's headline delta in one place. Full detail: §3.3.2 Controls,
§3.5 Input & Accessibility, §3.7 Performance, §3.8 Presentation.

**Shipped cross-input secondary-action model.** `LuauUI.newRowActions` and
`LuauUI.newRowActionsCoordinator` are real, standalone, public exports — not
Table-only. Proven per input class: mouse+touch unified pointer-capture drag
(8px axis lock, ties-go-vertical, rubber-band resistance, velocity-projected
settle), keyboard Delete/Backspace (focus-subtree-scoped, menu-open-gated),
gamepad ButtonX + keyboard Shift+Return (the menu, doc order), full-swipe
commit on both edges, one-open coordinator, and proven hot-switch CARRY/CANCEL
semantics across every device-arrival/loss case. `Table.rowActions` wires the
same seams for consumers who don't want to hand-roll a list. The RED-TEAM
adversarial gate on the whole feature closed at 16 findings, 15 fixed
directly and 1 resolved by a design change (the menu became its own floating
`presentModal` surface via the new `bindPresent` contribution seam, so it
contributes zero to any ancestor row's or list's measured box). Of the five
SwiftUI-style secondary-action mechanisms (swipe, long-press, mouse
secondary-click, keyboard, gamepad), **3 are real and 2 are absent** — mouse
secondary-click and touch long-press both still reach the menu only through
the reveal-tray, not a direct trigger, even though the touch-gesture
normalization layer that could drive a long-press trigger already exists,
unconsumed.

**The re-baselined perf gate.** A closed, wrapped row inside
`LuauUI.newVirtualList` costs **+57% steady-scroll / +81% fling / +5.00
nodes-per-closed-row** versus an unwrapped row — well over the original plan
budget of ≤5% scroll/fling and ≤4 instances. Root-cause profiling attributed
~98% of the delta to the shared renderer/solver's Instance creation/
measurement/destruction cost on every virtualization window-membership
crossing, not to row-actions' own reactive-graph construction (~2%). By
director ruling (2026-08-11), `tools/lune/gate_manifest.luau`'s `row-actions`
gate was re-baselined to the *measured* ceiling (steady ≤57%, fling ≤81%,
instances ≤5 — `tools/check_row_actions_matrix.py:52-55`) rather than the
original plan budget, which stays on record in the same artifact as "missed,
not massaged." One in-task fix shipped regardless: `syncKeysEnabled` now
defers building a row's action-system context until real focus enters it,
instead of building and immediately disabling it on every windowed mount.

**Follow-on charter.** The gap back to the original ≤5%/≤4 budget is not
started. `docs/plans/row-actions-perf-mission.md` names the concrete next
lever: a `VirtualList`-level gesture-composition hook (mirroring `table.luau`'s
`composeWithReorder`) so a wrapped row's capture surface rides the list's own
hit surface instead of mounting its own, or — larger-scoped — generic cell
recycling in `VirtualList` reusing mounted Instances across
window-membership changes, the Step 9 lab's own recycling precedent applied
one layer up.

**RascalRally impact.** Confirmed unaffected today: no RascalRally `Table`
caller passes `spec.rowActions`, confirmed live in Studio with zero wrapper
instances mounted (`artifacts/row-actions/rr-compat.md`); the RascalRally
game suite was re-run live against current source as part of this branch's
own Task 13 evidence.

---

## 6. Standing riders

**Nothing in LuauUI has been confirmed on physical hardware.** This rider is
unchanged since the first audit and independently reconfirmed by all nine
2026-08-11 area audits. Every four-input claim in this document rests on
headless Lune tests plus Studio MCP (`studio-emulated`) drives.

**Device-performance proof is absent.** `artifacts/phase-4/perf.json`:
`"deviceRun": false`, `"authoritative": false`, `"evidenceLevel": "E1"`.
Headless Lune (E1) and Studio-emulated (E3) evidence exist in depth; no
`phone-physical`/`console-physical` (E4) row has been filled. §3.7.

**Six `NEEDS_PHYSICAL_DEVICE` riders are freshly owed by the row-actions
branch alone**, carried from `artifacts/row-actions/device-matrix.md` §riders
(Task 5/6/8b reviews plus the Step-14 session's own findings). Each is a
single physical-device check a human can run in under a minute with the
`row_actions` scenario already selected and Playing:

| Rider | One-line instruction |
|---|---|
| Touch-capture-vs-native-scroll | On a real touch device, swipe a list row mostly-vertically starting ON the row: confirm the list scrolls (not the row) and no residual horizontal offset is left on the row after release. |
| Scroll-steals-pan | Fling the list fast enough to still be decelerating, then touch down on a row and immediately drag horizontally: confirm the row still opens (native momentum scroll doesn't eat the gesture). |
| PrimaryModifier live probe | Hold physical Shift and press Return on a focused row: confirm the action menu opens (not the row's own Activate) — exercises the real `InputBinding.PrimaryModifier` engine path headless suites can only simulate via `deviceKey`. |
| Shift-release-mid-chord | Press Shift, press Return, **release Shift before releasing Return**: confirm the menu still opens exactly once (no double-fire, no stuck-open state) — the real-hardware release-ordering case a scripted sequence can't reproduce. |
| Same-frame chord | On a gamepad, press ButtonX and a D-pad direction in the same physical input frame: confirm the menu opens and D-pad navigation inside it isn't swallowed by the same-frame ambiguity. |
| Multi-touch bleed | With two fingers, touch down on two different rows simultaneously and drag both outward (opposite trays): confirm each row's tray opens independently and the shared coordinator doesn't cross-close one because of the other's claim (MED12 from the RED-TEAM pass). |

Prior standing riders (large-text/Dynamic-Type physical proof, subjective
feel, engine-selection-bridge physical confirmation) remain open per §3.5 and
are not repeated here in full — see `artifacts/large-text-accessibility/acceptance.md`
and `artifacts/native-substrate/acceptance-ledger.md`.

---

## 7. Verification commands run for this report

```bash
cd GameStudio/ui/LuauUI
./run-tests.sh                                    # 4038 passed, exit 0
lune run tools/lune/check_registration_cli        # PASS (16 controls, 87 exports documented,
                                                   #   153 specs registered, 15/15 four-input + paradigm)
lune run tools/lune/check_boundary                 # PASS (97 src files, 379 consumer files)
lune run tests/conformance/corpus_cli              # a11y-l10n-corpus: 15/15 passed
lune run tools/lune/check_docs_cli                 # PASS (8 documents, 77 surface anchors, 64 local links,
                                                    #   7 themes exports documented, 11 stale phrases absent)
lune run tools/lune/check_prop_parity_cli          # PASS (25 classes, 438 properties, 2 diagnosed, 473 typed fields)
python3 tools/check_manifest_integrity.py          # 650 suite greps, all anchored to the pass marker
python3 tools/check_row_actions_matrix.py          # row-actions gate PASS at re-baselined ceilings
```

Not part of this document's own required checks, but discovered live during
this verification pass and worth carrying forward: `lune run
tools/lune/check_surface_ledger` currently **FAILS** — `newRowActions`/
`newRowActionsCoordinator` are unclassified in `artifacts/api-architecture-consistency/surface-ledger.md`.
This is not one of the row-actions gate's three required checks
(`row-actions-suite`, `row-actions-device-matrix`, `library-suite-green`, all
PASS per `artifacts/row-actions/gate.json`) and fixing it is out of scope for
this document's rewrite; it is recorded here so it is not lost.
