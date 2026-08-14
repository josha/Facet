# SwiftUI ↔ LuauUI: what LuauUI has, what it doesn't

**Report, plus one checker.** Producing this document changed no library or
example code. The citation pass of 2026-08-13 added one rule to
`tools/lune/check_docs.luau` — a row that asserts something about SwiftUI must
cite the Apple page it rests on — and the tests that prove that rule bites.

**This is a fresh draft, not a patch.** The previous revision was rewritten rather
than edited because it had gone wrong in ways that cost real time: it called
`containerRelativeFrame` "composable via the `percent` dimension" (false — see
§4), it said the solver had no shrink pass months after one shipped, it marked
`GridRow` missing after it landed, and it called ZStack's per-child `zIndex`
absent while the schema had carried it with documented sort behaviour. Every row
below was re-verified against source or a named test between 2026-08-12 and
2026-08-13. Nothing was inherited from the old draft.

**Every claim this document makes about SwiftUI now carries a citation.** That is
the second half of the same lesson, and it was learned the same way: a rewrite
caught sixteen false claims about *our* code, and then a single afternoon of
actually opening Apple's documentation caught three false claims about *Apple's*
— including an API we had named after a SwiftUI symbol that does not exist.
Citing the rest of the document then caught **ten more**, listed in §15.
Wrong claims about our side are caught by `check_docs`, `check_prop_parity` and
`check_registration`. Nothing was watching the other side, which is the side the
whole comparison rests on. So: a row that says what SwiftUI does, when it does
it, what a modifier means, or which platforms ship it, carries a bracketed id —
`[SW-16]` — resolved in **§16**, where each id gives the page, the sentence the
claim rests on quoted verbatim, the availability Apple states, and the date the
page was read. A row that merely *names* a SwiftUI type with no assertion about
its behaviour attached carries none: a citation on "SwiftUI has `HStack`" is
noise. Where Apple documents nothing, the row says so in those words and names
what the claim rests on instead — an unsupported citation is worse than none,
because it looks checked.

**The dates are load-bearing.** Every citation is dated `YYYY-MM-DD`, and every
one below was read on **2026-08-13**. SwiftUI ships once a year, in June. If you
are reading this after a June that is later than the dates in §16, treat every
SwiftUI-side claim here as *unverified* rather than as wrong — open the URL, and
if the page still says what §16 quotes, move the date. `check_docs` enforces that
a claim carries a citation and that a citation carries a URL, a quote and a date;
no checker can enforce that a quote is still true.

---

## 1. What this document is, and how to read it

LuauUI is a declarative UI framework for Roblox. SwiftUI is the most complete
declarative UI framework in wide production use, so it is the yardstick this
document measures against — capability by capability, with a citation on every
verdict. The point is not a score. The point is that a developer (or an agent)
picking up LuauUI can find out, in one read, whether the thing they need exists,
exists-with-caveats, or does not exist at all.

### This document covers a bounded catalog — read this before you trust a silence

**A capability that is absent from this document was not necessarily
considered.** That sentence is the most important one in §1, and until
2026-08-13 the document did not say it.

The four verdicts below are *findings*: **Missing** means we looked and we do not
have it. But a SwiftUI capability that never entered the catalog at all is
neither Covered nor Missing — it is **unexamined**, and from inside this document
the two are indistinguishable. A reader who looks up `onAppear`, `Section`,
`.disabled()`, rich text, or scroll snapping finds nothing here and could
reasonably conclude those were weighed and judged irrelevant. All five were
simply never weighed.

A completeness audit measured the bound on 2026-08-13
([`../plans/parity-completeness-audit-2026-08-13.md`](../plans/parity-completeness-audit-2026-08-13.md)).
Against Apple's own editorial groupings — 365 scored capability groups across 49
SwiftUI collection pages — this document had **examined 127**. Of the remainder,
120 have no Roblox substrate to bind to (OS windows, Apple frameworks, UIKit
interop, Apple-only input devices), 54 are applicable but deliberately out of
scope, and **64 were genuinely unexamined**, deduplicating to **39 named
capabilities**.

The blind spots are not randomly scattered, which is the useful part. Four
collections supply 19 of the 64: [scroll
views](https://developer.apple.com/documentation/swiftui/scroll-views) (6
unexamined of 12), [view
groupings](https://developer.apple.com/documentation/swiftui/view-groupings) (5
of 7), [preferences](https://developer.apple.com/documentation/swiftui/preferences)
(**5 of 5** — the largest single hole), and [custom
layout](https://developer.apple.com/documentation/swiftui/custom-layout) (3 of
4). That is this document inheriting the shape of a framework built control-first
and layout-first, where scroll *behaviour*, *grouping semantics* and *extension
points* were never their own areas.

So: **strength in the areas below is real; silence outside them is not
evidence.** Where a gap has since been examined it has moved into the tables and
carries a verdict like anything else. The audit found no *false* row — every one
of its findings was an absence, which is the failure mode a catalog has and a
checker cannot see.

There is a second yardstick, and §4.1 uses it: **Roblox's own layout controls.**
SwiftUI parity says nothing about whether LuauUI is worth using *on this
platform*. The standing bar from the director is that LuauUI must do **more**
than `UIListLayout`/`UIFlexItem`, never less, so §4.1 states where it is a
superset and where it is not.

**How to read a verdict.** Each area below opens with a few sentences of plain
framing, then a table of capabilities, then the caveats that did not fit in a
table cell. Four verdicts are used:

| Verdict | Means |
|---|---|
| **Covered** | A first-class equivalent ships, is exported, and its conformance tests pass. |
| **Partial** | It ships and works, but with named behavior gaps a consumer will hit. |
| **Composable** | Not a shipped construct, but buildable today from the public surface with no framework change. The recipe is named. |
| **Missing** | No construct and no honest recipe. Where the Roblox engine is the reason, that is said. |

Two rules keep those verdicts from inflating:

1. **A control that works on only some input devices is Partial at best.** LuauUI
   targets mouse, touch, keyboard, and gamepad; "a control that only works with a
   mouse is an unfinished control." Being *reachable* on all four is also not
   enough — if the control does not behave the way that device's users expect
   (a slider you can only jump-to-value with a gamepad, never nudge), it stays
   Partial. ([`ADR-0016`](../adr/ADR-0016-three-axes-contract.md), `ui_todo.md:3-13`)
2. **Nothing in LuauUI has been confirmed on physical hardware.** Every
   four-input claim in this document rests on headless test runs plus scripted
   drives of the Roblox Studio device emulator. §14 lists what a human with a
   real phone, keyboard, and gamepad still needs to check.

**Vocabulary you need for the rest of the document.** LuauUI's terms, in SwiftUI
terms where an analogue exists:

| LuauUI term | What it is |
|---|---|
| **Blueprint** | The tree of plain Lua tables describing what should be on screen — LuauUI's equivalent of a SwiftUI `View` body. `UI.VStack{ UI.Text{...} }`. |
| **Signal** / **Memo** | The reactive primitives. A signal is a mutable observed value (`@State`); a memo is a derived, cached value (`computed`). Tracking is per-value, not per-view. |
| **Solver** | The layout engine. It measures the blueprint, then arranges it into rectangles. Runs headlessly, with no engine objects involved. |
| **Renderer** / **target** | The layer that turns solved rectangles into real Roblox `GuiObject` instances. Swappable — that is why the solver can be tested with no Roblox running. |
| **Presenter** | The layer that owns on-screen surfaces (screens, modals, popovers, toasts) and their focus, layering, and dismissal rules. |
| **Composite** | A shipped, exported, tested control assembled from primitives — `LuauUI.newSlider`. The opposite of a "recipe" the consumer writes by hand. |
| **Four-input proof** | An automated conformance test asserting a control is genuinely operable with mouse, touch, keyboard, *and* gamepad. |
| **Gate** | A named CI check that must pass before a piece of work is considered landed. |
| **Evidence level** | How a claim was verified: **E1** headless test run, **E3** Roblox Studio device emulator, **E4** physical hardware. No E4 evidence exists yet. |
| **Director** | The human product owner. Where this document says "director ruling", a person decided a trade-off that the framework could not decide for itself. |

Three different things in this codebase are called a "contract". They are
genuinely distinct, and knowing which is which makes several rows below
readable:

| Contract | What it governs |
|---|---|
| **Render-target contract** (`src/render/target_contract.luau`) | The method list every render target must implement — required, optional (each absence is one named, non-crashing degrade), and theme-related. This is the *adapter* seam; "adapter contract" and "target contract" name the same list. |
| **Input contribution** (`src/input/contribution.luau`) | How a composite advertises its input story to the presenter, by attaching a bundle to its blueprint's root node. Mounting the control then yields its whole navigation/activation/focus story with no consumer wiring. |
| **Control contract** (`src/controls/contract.luau`) | A per-control *declaration*: focus role, which semantic actions it consumes, its minimum hit-target size (enforced by the renderer), and a readable accessibility summary. |

---

## 2. The honest summary

LuauUI's reactive core, layout solver, motion system, theming system, and tooling
are strong — in several places stronger than SwiftUI's equivalents, and in a few
(screen-level adaptive composition, information-preserving Reduce Motion,
arrival-radius chase animation) there is no single SwiftUI built-in that does the
same job. This round closed the two ergonomic gaps that had been at the top of
the list for a year: **`withAnimation` now ships** (position only — §8), and the
**layout vocabulary is complete enough to be a strict superset of Roblox's own
flex controls in every respect but one** (§4.1).

The gaps that remain are structural rather than incidental. There is still no way
to swap what a control *renders as* while keeping its behavior — no
`ButtonStyle`-style protocol — and after this round that is a **decision, not an
omission**: native Roblox StyleSheets and theme packages own paint, and §6
carries the mapping a SwiftUI author needs instead. There is no screen-to-screen
navigation model, only surface stacking. There is no translucent-material system,
and Apple's Liquid Glass — shipped across the 26 releases and still the current
material system a year later ([SW-74], [SW-76]) — has widened that gap rather
than narrowed it. There is
no right-to-left or bidirectional layout or text support anywhere. And there is
no assistive-technology bridge at all — nothing in LuauUI talks to a screen
reader; a blind player cannot use a LuauUI interface.

On performance the framework has deep headless instrumentation, executable
regression budgets, and real shipped wins (incremental layout, instance
recycling, inert-container elision). **The one shipped feature that used to cost
materially more than its own plan budgeted — row swipe actions — no longer
does**: hosted mode landed on 2026-08-12, the gate ceilings were restored from
the re-baselined 57 %/81 %/5-instance numbers to the original ≤5 %/≤5 %/≤1, and
the current five-run ABBA means are −0.28 % steady, +2.83 % fling and 0.08
wrapper instances per closed row
(`tools/check_row_actions_matrix.py:81-83`; `artifacts/row-actions/device-matrix.md:209-219`).
What has *not* changed is the bigger caveat: **zero measurements from a physical
device.** Where a verdict here is generous, the caveat is in the same section,
not buried.

**Verdict counts across §§3–11**, so the shape of the answer is visible before
the detail: **164 capability rows — 98 Covered, 34 Partial, 4 Composable, 28
Missing.** Fifteen of those rows are additionally marked as having *no
equivalent on the other side* — Roblox-specific or LuauUI-specific capabilities
the comparison cannot score in either direction. A count is not a score: the
28 Missing rows include the three that matter most (assistive technology,
navigation, materials) and the 98 Covered ones include several that are one
Roblox primitive wrapped honestly.

Five of those rows arrived on 2026-08-13 without a line of library code, and
they are worth naming because of *why* they were absent. The completeness audit
found four capabilities that had shipped for months and had never entered this
table — `AsyncImage`, the `canvasGroup` compositing group, `TextField`'s
`keyboardType`, and the Reduce-Transparency preference — plus one, `.onSubmit`,
that is reachable today through `onFocusLost(reason)` and had never been scored
either way. Silence in a catalog reads as "considered and rejected"; all five
were simply never looked at. Two of the four turned out to be **Partial** rather
than Covered once the source was actually read, which is the more useful half of
the result: `keyboardType` is validated, typed, mapped and *inert* on the
shipped engine, and the transparency preference is read, clamped, fault-tested
and consumed by nothing.

---

## 3. State & data flow

This is LuauUI's strongest area. Where SwiftUI invalidates a view and recomputes
its `body` — Apple documents the *effect*, that it "automatically updates the
affected parts of the interface", and nowhere documents body re-execution and
diffing as the mechanism ([SW-04]) — LuauUI tracks dependencies per *value*: a signal read inside a
memo subscribes that memo to that signal alone. That makes invalidation
finer-grained than SwiftUI's, at the cost of SwiftUI's whole-object ergonomics —
there is no `@Observable`-style "mark the model, forget about it" macro, and
two-way binding is a convention (pass the signal down) rather than a type.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `@State` — owned, per-instance mutable value ([SW-01]) | **Covered** | `core:signal`, a fine-grained observable value rather than a per-view struct field | `src/core/custom.luau`; `src/core/contract.luau`; test `signal-read-write` (`tests/conformance/suite.luau`) |
| `@Binding` — two-way reference to caller-owned state ([SW-02]) | **Covered by convention, not by type** | A control simply takes the caller's `Signal` and writes to it. There is no projection/wrapper type; misuse is caught at write time by a runtime assertion, not at authoring time | `src/controls/value_model.luau` |
| `@Observable` — auto-tracked property access ([SW-03]) | **Partial** — finer-grained, not object-shaped | Tracking is per-signal/per-memo via `use()`. You get precision SwiftUI does not have; you do not get "one annotation on a model class" | `src/core/custom.luau`; test `dynamic-dependencies-swap-atomically` |
| Derived/computed state | **Covered**, glitch-free | `core:memo`, eager-stale marking plus pull-based recompute, so a diamond dependency never fires an observer twice with inconsistent inputs | `src/core/custom.luau`; tests `memo-derives-and-updates`, `glitch-free-diamond`, `no-spurious-fire-on-unchanged-recompute` |
| Transactions (`withTransaction`) ([SW-06]) | **Covered** as pure write-batching | Many writes, one observer fire; a reverted transaction fires nothing. `Core` exposes `transaction(body)` and nothing else — there is no per-signal write hook and no public `inTransaction()`, which is why `withAnimation` (§8) has to probe rather than ask | `src/core/custom.luau`; `src/core/contract.luau` |
| `withAnimation` — wrap a state write, downstream reads interpolate ([SW-05]) | **Covered** (new, 2026-08-13) | `presenter.withAnimation(class, fn)`. Position only; see §8 for exactly what it does and does not animate | `src/present/presenter.luau:3942`; `tests/with_animation.spec.luau`; `docs/reference/api.md` §`presenter.withAnimation` |
| `onAppear(perform:)` ([SW-138]) / `onDisappear(perform:)` ([SW-139]) — run code as a view enters and leaves | **Covered** (new, 2026-08-13) | `onAppear` / `onDisappear` are shared box props on **every** rendered class, each called with the node's path. Before this round `grep -rn "onAppear" src/` returned zero hits, which is the useful part of the finding: mount scopes have owned this lifetime since the framework's first phase, so the tracking existed and only the author-facing hook did not. **The lifetime measured is the rendered one, not the mounted one** — a virtualized row that scrolls out of its window disappears, and a subtree still playing its exit transition has not — which is the answer Apple's own pages decline to give: “The exact moment that SwiftUI calls this method depends on the specific view type that you apply it to” ([SW-138], [SW-139]). LuauUI's two ordering rules are exact instead: **appear fires after that frame's layout solve**, so the callback can read its own rect, and still before anything reaches the screen (a refresh is one synchronous call) — Apple's guarantee is the weaker “the action closure completes before the first rendered frame appears” ([SW-138]); **disappear fires after the render instance is released**, so `rectOf(path)` is already `nil` inside the callback. Teardown fires every still-mounted hook, so a cleanup is never silently dropped — Apple documents nothing about window or scene teardown here ([SW-139]). Not reactive: a lifetime is not a value that changes, and the OLD closure is the one that has to run when the node leaves | `src/blueprint_schema.luau` (`onAppear`/`onDisappear` in the shared box group); `src/render/renderer.luau` (queued at mount, drained after the solve; queued in the removal sweep, drained after it); `tests/lifecycle_hooks.spec.luau`; fixture `examples/gallery/scenarios/lifecycle_hidden.luau` |
| Cycles / self-referential derivation | **Covered** — reported, not hung | A dependency cycle raises with a readable error instead of recursing | `src/core/custom.luau`; test `cycle-reported-not-hung` |
| Writing state during a derivation | **Covered** — refused | Illegal by construction, not by convention | `src/core/custom.luau`; test `write-during-memo-is-error` |
| `.task` — async work scoped to view lifetime ([SW-07]) | **Partial**, with stronger cancellation than SwiftUI | `LuauUI.newResourceProvider` gives scope-owned handles and generation-counter stale-completion rejection: a slow request that returns after its owner changed identity is discarded rather than applied. Bounded, spaced retry. SwiftUI's own guarantee is that it cancels the task when the view goes away or changes identity ([SW-07]); what is added here is refusing a stale result that *completed*. Not a `.task`-shaped modifier, though | `src/async/resources.luau` |
| `@Environment(\.foo)` — implicit value propagation ([SW-08]) | **Covered** | Per-key signals with derived memos on top, so a keyboard-occlusion change cannot invalidate a subscriber that only reads colors. Widely consumed (`themeMetrics`, `effectiveInput`, `interactionClasses`, `typographyScale`, `preferredTextOffset`, and more) | `src/env/environment.luau` |
| Environment values that clamp/default bad input | **Covered** | `typographyScale`, `effectiveTransparency`, `effectiveOverscanInsets` all sanitize rather than propagate garbage | `src/env/environment.luau` |
| `ForEach(id:)` / `.id()` — identity and structural diffing ([SW-09]) | **Covered**, closer to `ForEach` than to whole-tree diffing | Adds, removes, and moves only; duplicate keys are a hard error. A row removed and re-added *while its exit animation is still playing* resumes the same mounted subtree, scope, and instances rather than remounting. **Apple documents no behaviour here** — nothing on the `ForEach` page says what happens to an element removed and re-added mid-transition ([SW-09]) — so read that as a LuauUI guarantee, not as a win over a documented rule (the previous revision called it "stronger than SwiftUI's default") | `src/mount.luau` |
| Instance reuse below `ForEach`/`When` | **Covered** — no direct SwiftUI analogue ([SW-34]) | A recycling pool keyed by node shape hands a retiring node's Roblox instances to the next node that needs the same shape, instead of destroy-then-create. Pool cap 64 | `src/render/renderer.luau:1719`; `tests/instance_park_corpse.spec.luau` |
| Ownership scopes / disposal | **Covered**; Apple documents no disposal or ownership contract to be stricter *than* ([SW-10]) | Reverse-order idempotent dispose, double-dispose detection, and a releasability check at registration time — `scope:own()` raises immediately if handed something with no `dispose()`. Cleanup errors are quarantined, not propagated | `src/core/scope_impl.luau` |
| Runaway-effect protection | **Covered** — no public SwiftUI equivalent ([SW-10]) | A feedback loop between effects is capped and reported rather than hanging the client | `src/core/custom.luau`; test `feedback-loop-hits-iteration-cap` |

**Caveats.**

- `withAnimation` closes the *ergonomic* half of the old gap but not all of it.
  It animates a node's **position** because its box moved; it does not retrofit
  interpolation onto an arbitrary bound *value*. A number that must count rather
  than jump still has to be a `MotionValue` (§8).
- `lastError()` on the core is sticky and cannot be reset. You can ask a
  long-lived core "were you ever in a quarantined state", but not "are you
  healthy right now."
- The *raw* environment key describing screen size class (`sizeClass`) is named
  in exactly four files: `src/env/environment.luau` (which defines it) and three
  consumers — `src/layout/adaptive.luau`, `src/controls/popup_button.luau`,
  `src/controls/picker.luau` — and of those three, **only `adaptive.luau`
  actually calls `env:get("sizeClass")`**; the two controls take a size class in
  as a spec parameter. That is narrower than it sounds: application code is not
  meant to read the raw key at all, it is meant to call the derived helpers the
  policy module builds on top of it (`axisFor`, `columnsFor`, `navPlacement`,
  `conditions()`), and those *are* consumed throughout, by all five reference
  apps (§12). Read it as "one policy module owns this key", not as "almost
  nothing adapts to screen size."

---

## 4. Layout

LuauUI's solver is a headless, testable measure-then-arrange pass over the
blueprint, with weighted flexbox-style stacks, two grid modes, a `ViewThatFits`
equivalent, and safe-area insets. Two things here go beyond SwiftUI. The first is
`UI.Composition`/`UI.Region`, where a screen declares its content once as a set
of *ranked regions*, each carrying an ordered ladder of forms from richest to
minimum-viable; the framework then tests arrangements and steps a region down its
ladder — or drops it entirely, lowest rank first — until everything fits. That is
closer to a full `Layout` protocol ([SW-24]) plus `layoutPriority` ([SW-13])
combined than SwiftUI ships in any single construct, and it means no screen contains a device-name
branch. The second is incremental layout: a single changed bound value re-solves
only the smallest enclosing subtree it can affect, not the whole tree.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `HStack`/`VStack` core (weighted, aligned, with margins) | **Covered** | Weighted `fill` distribution with largest-remainder rounding, container `align`, per-child `margin`, `gap`, `Spacer` main-axis fill, and — new this round — `distribute` and a real shrink pass (next two rows) | `src/layout/solver.luau:294` (`SPACER_FILL`), `:309-316` (margin), `:566-581` (gap), `:2177-2181` (`alignOffset`) |
| Main-axis distribution — SwiftUI has **no prop for this** ([SW-11]) and needs hand-placed `Spacer`s ([SW-12]) | **Covered, and wider than SwiftUI's** | `distribute = "start" \| "center" \| "end" \| "spaceBetween" \| "spaceAround" \| "spaceEvenly"` on `HStack`/`VStack`/`AdaptiveStack`/`Screen`, default `"start"` (byte-identical to the previous hard-anchored cursor). It closes the case a static `Spacer` recipe cannot reach at all: a variable-count child list goes through `UI.ForEach`, whose `row` returns exactly one blueprint, so separators cannot be interleaved on the parent's main axis. A tab bar whose tab count varies used to be inexpressible. `distribute ~= "start"` while `fill` children have already eaten the remainder is a **diagnostic**, not a silent no-op | `src/blueprint_schema.luau:780-788` (enum), `:1029,1035,1041,1196` (the four hosts); `src/layout/solver.luau:3401-3419` (arrange + conflict diagnostic); `tests/stack_distribution.spec.luau:213-227` |
| `layoutPriority` — who shrinks first when over-committed | **Covered, and wider than SwiftUI's** | Shipped 2026-08-12. `layoutPriority` (default `0`) is the **outer sort** — tiers consumed lowest-first, SwiftUI's model, which Apple states as a rule about the *lowest* tier: the parent offers the highest-priority children everything except the minimum its lower-priority children need ([SW-13]). `shrinkWeight` (default `0`) is the **inner** one — proportional to `weight × basis` inside a tier, which is CSS's `flex-shrink` and Roblox's `UIFlexMode`, and which SwiftUI has no equivalent of — `layoutPriority` is the only shrink dial its documentation offers ([SW-13]). Both default inert (`shrinkWeight = 0` is exactly `Enum.UIFlexMode.None`), so nothing shipped moved. Floors are `minMax.min` → a text node's minimum wrap width → `0`. The pass runs in **both** solver passes: arrange negotiates against the real rect, and the measure branch runs the same negotiation whenever the *offer* is already too small — without that, a label squeezed to its floor wrapped onto lines nobody had reserved, the "painted at a size nobody measured" family again. `Composition.rank` is adjacent but not equivalent: it drops or degrades whole screen regions, it does not negotiate sizes inside one stack | `src/blueprint_schema.luau:576-584` (`layoutPriority`), `:585-596` (`shrinkWeight`); `src/layout/solver.luau:2395-2444` (`shrinkStack`), `:2242-2261` (`shrinkFloorOf`), `:2413` (`weight * basis`), `:1535` (measure PASS 1.5), `:3303` (arrange); `tests/stack_distribution.spec.luau` |
| `.frame(alignment:)` on ONE child of a stack — SwiftUI's route to per-child cross alignment ([SW-14]) | **Covered** | `lineAlign = "start" \| "center" \| "end" \| "stretch"` is a shared box prop, so a `Text`, `Image`, `Box` or `Spacer` can align itself in its parent's line. It outranks the container's `align` and a nested stack's own `align` — which is what disentangled one word that used to mean two jobs (a nested `VStack{ align = "center" }` both centred its own children *and* centred itself in its parent's line) | `src/blueprint_schema.luau:549-559`; `src/layout/solver.luau:3462` (`child.lineAlign or child.align or node.align`); `tests/stack_distribution.spec.luau` |
| `ZStack` | **Covered** | Deterministic paint order, **and a per-child `zIndex` override** — the previous revision of this document said there was none, and that was wrong. SwiftUI's `zIndex` is the same idea and the same default of `0` ([SW-15]), though Apple documents no *scoping* rule for it, so the next sentence is LuauUI's own. `zIndex` is a shared, non-reactive box prop: siblings sort by `(zIndex or 0, tree order)` and a lifted node's whole subtree travels with it, inside its parent's stacking scope, so lifting can never cross scopes. It is implemented generically for **every** container, not just ZStack. Separately, the overflow diagnostic is per-axis and understands `fill` children, so a child granted its full box is not reported as overflowing a box it cannot leave | `src/blueprint_schema.luau:687-694`; `src/render/renderer.luau:2921-2952` (`orderedChildren`), `:2954-2971` (`syncZOrder`); `tests/paint_extensions.spec.luau:657-699`; `tests/zstack_fill_diagnostic.spec.luau` |
| `Grid` — uniform flow grid | **Covered** | Row-major wrap at one shared column width `(innerW − gap × (cols − 1)) / cols`, `minColumnWidth = "intrinsic"`, per-cell `alignH`/`alignV`. The grid's measured size is a proven fixed point of its own arrange report (measure it, arrange it, measure again — same answer) | `src/layout/solver.luau:1392` (measure), `:3146` (arrange), `:513` (`intrinsic`), `:1924` (per-cell align); `tests/layout_vocabulary.spec.luau:64-70,661-756`; `tests/grid_measure_arrange.spec.luau` |
| `GridRow` / per-column widths / `gridCellColumns` (spanning) | **Covered** | Shipped 2026-08-13. `UI.GridRow` is a solver primitive, and a `UI.Grid` whose children are all rows switches to **row mode**: column *n* is as wide as the widest natural cell in column *n* across every row (SwiftUI's rule, and Apple states it in those terms: the column matches "the needs of column's widest cell" — [SW-16]), against the flow grid's one shared width. `gridSpan` is SwiftUI's `gridCellColumns` ([SW-18]), and a spanning cell here contributes to no single column's maximum and is fitted to the columns it covers plus the gaps between them — but that sizing rule is **ours**: `gridCellColumns` documents the span and its anchor-alignment consequence and **documents no column-sizing behaviour at all** ([SW-18]). **The mode is selected by the children, never by a prop**; a mix of rows and loose cells files a diagnostic and keeps the flow reading rather than guessing. Naturals that do not fit are reduced proportionally rather than overflowing, because the flow grid cannot overflow and a row grid under the same name must not either. `GridRow`'s prop set is deliberately tiny — `width`, `height`, `padding` and `margin` are construction errors on it (each would be a second authority against the grid that owns the columns), while its paint props (`surface`, `shadow`, `gradient`, `corners`, `stroke`, `zIndex`) are the striped-row case. A Grid with no `GridRow` child is byte-identical to what it always was, pinned on both sides. Not covered: SwiftUI's per-row `alignment:` ([SW-17]), `gridCellAnchor` ([SW-19]), and `gridCellUnsizedAxes` ([SW-20]) — which this document called `gridCellUnsizedAxis` until 2026-08-13, a symbol that does not exist | `src/blueprint_schema.luau:1165,1177-1186`; `src/layout/solver.luau:604-618` (column and span rules), `:626-641` (`gridMode`), `:3113-3122` (mixed-children diagnostic); `tests/grid_row.spec.luau`; `games/RascalRally/code/tests/luauui_grid_row_contract.spec.luau` |
| `LazyHGrid` / `LazyVGrid` | **Missing** | Neither grid mode is lazy: every cell is measured and arranged. SwiftUI's non-lazy `Grid` is the same and says so — it "renders all of its child views immediately" ([SW-16]) — and its lazy grids are the ones that create items only as needed ([SW-21]); LuauUI ships only the eager half | — |
| `ViewThatFits` | **Covered** | A real solver construct (`kind == "fits"`) that measures candidates against the offered box and picks the first that fits — SwiftUI's own rule, in its own words ([SW-22]). It chooses its candidate *before* the shrink pass runs and is therefore unaffected by `layoutPriority` | `src/layout/solver.luau:1133,1295,2805`; `tests/layout_vocabulary.spec.luau` |
| Reactive-axis stack (no SwiftUI single equivalent; nearest is `AnyLayout`, whose documented point is switching layout type without destroying subview state — [SW-23]) | **Covered** | `UI.AdaptiveStack` — one class whose `axis` is a bound value, `dirty = { "measure" }`. Flipping horizontal↔vertical re-solves in place without remounting the children or re-running the factory | `src/blueprint_schema.luau:1201-1208`; `tests/adaptive.spec.luau:182-233` |
| Whole-screen adaptive composition | **Covered** — exceeds SwiftUI in one respect ([SW-10], [SW-24]) | `UI.Composition` + `UI.Region`: ranked regions with richest→minimum-viable form ladders, legality-tested in rank order. Carries all five reference apps' adaptation (§12) with zero device-name branches. The resolver is a pure function, so it is exhaustively testable headlessly | [`ADR-0023`](../adr/ADR-0023-declared-content-composition.md); `src/layout/composition.luau` (1703 lines); `src/blueprint_schema.luau:1231,1276`; `tests/composition.spec.luau` (1988 lines) |
| Size-class-driven adaptation (`horizontalSizeClass` etc.) | **Covered** | One policy module, `src/layout/adaptive.luau`, owns the raw `sizeClass`/`heightClass` environment keys and exposes the derived helpers callers actually use — `axisFor`, `columnsFor`, `navPlacement`, `conditions()`. Those helpers are consumed by all five reference apps | `src/layout/adaptive.luau` |
| Safe areas | **Covered** | Four-edge insets as environment facts, with a full-bleed (`edgeToEdge`) root policy for scrims and backgrounds | `src/layout/solver.luau:3507` (`SafeInsets`), `:3517-3519` (root policy) |
| `GeometryReader` — a container that defines its content as a function of its own size ([SW-32]) | **Partial** | You can learn a node's solved rectangle three ways — `controller.rectOf`, an `onGeometry` callback, a `syncGeometry` contribution — but all three are **push** seams keyed by node path, not a readable value you can compose into a memo | `src/render/renderer.luau:1114,3442`; `src/present/presenter.luau:154,2401-2402`; `src/input/contribution.luau:91` |
| `containerRelativeFrame` | **Covered** | Shipped 2026-08-13. `UI.containerRelativeFrame(bp, { axis, fraction })`, or the paging form `{ axis, count, span?, spacing? }` whose arithmetic is SwiftUI's verbatim — Apple publishes the three-line formula and the meaning of `count` and `span` ([SW-26]). **The old "composable via the `percent` dimension" reading was wrong about the ruler**, and this is the correction worth reading twice: `percent` resolves against the *immediate parent's offer*, so any wrapper between the view and its scroller silently changes the answer — and on a scroller's **own axis** the offer is `math.huge`, so `percent` cannot express anything there at all. `containerRelativeFrame` resolves against the nearest ancestor that owns a viewport (a `ScrollView`'s content viewport, else the surface root), which is what a paged carousel needs and what SwiftUI means by "the nearest container" ([SW-25]). It is a **dim type** (`{ type = "containerRelative", … }`) rather than a parallel prop, so it inherits dim validation and the incremental-layout boundary predicate for free; an unbounded container (a scroller nested inside another scroller's own axis) files a diagnostic and falls back to content, exactly as `percent` does. Not covered: SwiftUI's multi-axis form (`[.horizontal, .vertical]`) and the `alignment:`/closure variants — both real, both documented ([SW-27]) — the spec's field set is closed to `{ axis, fraction, count, span, spacing }` | `src/blueprint.luau:1357-1359,1371-1377,1387-1466`; `src/layout/solver.luau:829-841`; `tests/container_relative_frame.spec.luau`; `tests/container_relative_incremental.spec.luau` |
| `.alignmentGuide` — custom alignment anchors / `AlignmentID` ([SW-28], [SW-29]) | **Missing** | No construct exists; zero occurrences in source. Closing it needs a per-axis guide-resolution pass threaded through arrange. See §4.4 | — |
| Baseline alignment (`.firstTextBaseline` / `.lastTextBaseline` — a guide on the top-most or bottom-most text baseline in a view, [SW-30]) | **Missing** | The `alignH`/`alignV` enum is closed to `start`/`center`/`end`, and the solver computes no per-child baseline. Closing it needs the text-measure pass to publish an ascent per child plus a new arrange term. See §4.4 | `src/blueprint_schema.luau:629,638` |
| `Spacer(minLength:)` — Apple's `minLength` is "the minimum length this spacer can be shrunk to" ([SW-12]) | **Composable** | Already expressible as `width`/`height` `= { type = "minMax", min = X }` on the `Spacer`, which inherits the shared box dim vocabulary. A first-class `minLength` prop would be sugar over exactly that, and is deliberately not built | `src/blueprint_schema.luau:1404-1408` (Spacer is `merge(BOX)` only) |
| `ScrollView` — a real scroll container | **Covered** | Backed by a native Roblox `ScrollingFrame`: it genuinely scrolls, clips, and reports its content size | `src/client/screen_target.luau:141` |
| `ScrollView` — horizontal axis | **Covered** | `axis = "y" \| "x"`, construction-only (a reactive engine scroll axis would rebuild native scroll state mid-gesture) | `src/blueprint_schema.luau:1055-1061` |
| Scroll-indicator policy | **Covered** | `indicators: "auto" \| "none"`; a size-to-content scroller's *measure* includes the scrollbar its *arrange* reserves, so it cannot under-measure itself | `src/blueprint_schema.luau:1068-1082` |
| Drag-to-edge autoscroll | **Covered** — no SwiftUI built-in ([SW-10]) | Dragging an item toward a scroller's edge scrolls it, through any nested chain of scrollers, innermost first, falling through when the innermost is pinned | `src/input/autoscroll.luau` |
| `ScrollView` content virtualization | **Missing** | Every `ScrollView` child is measured and arranged regardless of visibility. Only the dedicated `VirtualList` and `Table` virtualize, and each does so independently — the solver's own comment names exactly those two | `src/layout/solver.luau:245-248` |
| `LazyVStack` / `LazyHStack` (as `VirtualList`) ([SW-31]) | **Partial** | Windowed rendering of a long collection **on either axis** (`axis = "y" \| "x"`, construction-only), with a configurable gap and a focus policy keyed by item identity or index. **Neither SwiftUI name ships as a constructor** — see §4.2 for the decision and for the variable-extent gap that is the reason. Named divergences: uniform `itemExtent` only, no pinned section headers, no fling/inertia, no scrollbar. `rowActions` are refused at construction on a horizontal list, because there the tray's reveal swipe *is* the scroll gesture | `src/controls/virtual_list.luau:391` (axis), `:181-188,416,457` (naming), `:449` (uniform extent), `:581,2495` (refusal) |
| Flow-wrap ("as many as fit per line", ragged widths) | **Covered** (new, 2026-08-13) — and there is **no SwiftUI equivalent to be parity with** | `UI.HStack{ wrap = true }` / `UI.VStack{ wrap = true }` — Roblox's `UIListLayout.Wraps`. Apple's symbol index was searched on 2026-08-13 for every node whose title contains "flow" or "wrap" and every hit is `wrappedValue` / `FileWrapper` / `toolbarOverflowMenu`: **SwiftUI ships no flow layout**, and its answer to this shape is "write a custom `Layout`" ([SW-10]). So this row closes a NATIVE gap, not a SwiftUI one. One prop and no new alignment vocabulary — see §4.3 | `src/layout/solver.luau` (`flowPartition`/`flowPlan`, the `hwrap`/`vwrap` measure and arrange branches); `src/blueprint_schema.luau` (`WRAP`); `tests/flow_wrap.spec.luau` |
| Incremental relayout | **Covered** — no SwiftUI-visible equivalent ([SW-10]) | A changed bound value re-solves only the subtree that can be affected. Measured on the framework's own instrumented surface: 141 arranged nodes down to 8 (~17×) for a one-value change, with zero pixel differences across 185 nodes in an engine-level visual diff. On by default | `src/render/renderer.luau:2442`; `src/present/presenter.luau:2152`; `artifacts/performance-stress-places/optimization-log.md:1017,1020`; `tests/incremental_layout.spec.luau` |
| A property that is accepted must do something | **Covered** — no SwiftUI or Roblox equivalent ([SW-10]) | The nine placement props (`anchor`, `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign`, `gridSpan`, `layoutPriority`, `shrinkWeight`) are legal on every node but read only by particular parent arrange branches. `solver.auditPlacement` reports every (parent kind, prop) pair the parent will never read, through `controller.diagnostics()`, so an inert prop is a complaint instead of a silent wrong result. The read table lives next to the arrange branches it describes, because a copy kept anywhere else goes stale the first time a branch learns a new prop | `src/layout/solver.luau:1919-1930`, `:2079`; `tests/placement_audit.spec.luau`; the twelve cleared call sites and the queue of *unfulfilled* intents: [`unfulfilled-placement-intents.md`](../plans/unfulfilled-placement-intents.md) |
| Live 3D content inside a laid-out box | **Covered** — no SwiftUI equivalent (Roblox-specific) ([SW-10]) | `UI.Stage` hosts a Roblox `ViewportFrame` inside a solver-owned rectangle, with a pure camera/lighting contract. To the solver it is just another content leaf. Live consumers: a 3D dashboard hero and an avatar mannequin preview (§12) | `src/render/stage_content.luau` (147 lines); `src/client/screen_target.luau:145` |
| Device-matrix testing | **Covered** | Named device profiles and a matrix runner drive any surface across five viewport shapes headlessly and in the Studio emulator | `src/preview/device_profiles.luau`; `src/preview/matrix_rows.luau` |

**Caveats.**

- **No container unifies virtualization, reordering, and selection.** `Table`
  reorders and selects but does not virtualize; `VirtualList` virtualizes but
  does neither. A long, reorderable, selectable list is still not buildable on
  any single class. The yardstick moved this June: SwiftUI generalised reordering
  out of `List` entirely — `reorderable()` inside a `reorderContainer(for:isEnabled:move:)`
  makes lists, stacks, grids *and custom layouts* reorderable by drag ([SW-35],
  [SW-36], iOS 27 and equivalents) — so this gap is now measured against a wider
  surface than it was. Swipe actions are no longer evidence for this gap, though:
  since hosted mode landed, `newVirtualList` takes `spec.rowActions` directly
  (§5.1), so that one capability *is* shared across both classes.
- **There is no `LayoutOrder` analogue.** Declaration order is the only order.
  Roblox's `SortOrder.LayoutOrder` lets you reorder siblings without moving them
  in the tree; in LuauUI you reorder the `children` array, or the keys a
  `UI.ForEach` yields, and the structural-transition system animates the move.
  That is the declarative equivalent rather than a gap, but it is a real
  behavioural difference worth knowing before porting engine-shaped code.
- Both of the "deliberately deferred layout proposals" the previous revision of
  this document listed have since **shipped**: the flow-stack compress-toward-min
  step is the `layoutPriority` × `shrinkWeight` pass, and the overloaded `align`
  property was split by `lineAlign`.
- Two patterns in `src/controls/row_actions.luau` are worth knowing about but are
  *recipes built on existing seams*, not framework primitives: a per-row height
  override signal driven by a physics spring (to animate a row collapsing to
  zero), and reading `syncGeometry` on the scroll cadence to keep a floating
  menu anchored to a moving row.

### 4.1 Stacks vs Roblox's own flex controls — where LuauUI is a superset, and where it is not

SwiftUI parity is the wrong question for a Roblox developer choosing between
LuauUI and the engine's own `UIListLayout` + `UIFlexItem`. The right question is
whether the framework does **more** than the controls it replaces. A
live-verified audit on 2026-08-12 found LuauUI **behind** the native controls in
four places. Three closed this round; the fourth is deferred and named.

Native surface as documented on `create.roblox.com`, re-read 2026-08-13:
`UIListLayout` carries `FillDirection`, `HorizontalAlignment`, `VerticalAlignment`,
`Padding`, `SortOrder`, `Wraps`, `ItemLineAlignment`, `HorizontalFlex` and
`VerticalFlex`; `UIFlexItem` carries `FlexMode`, `GrowRatio`, `ShrinkRatio` and a
per-item `ItemLineAlignment`.

| Native capability | LuauUI | Verdict |
|---|---|---|
| `FillDirection` | `UI.HStack` / `UI.VStack` as distinct classes, plus `UI.AdaptiveStack` whose `axis` is a **bound** value that re-solves without remounting | **Superset** — native's `FillDirection` is a plain settable property with no reactive re-solve contract (`src/blueprint_schema.luau:1201-1208`) |
| `Padding` | `gap` (number or theme metric). Absent means `0`, not a platform-standard adaptive value — a deliberate divergence from SwiftUI's `nil` spacing, which Apple defines as "the stack to choose a default distance for each pair of subviews" ([SW-11]) — documented rather than "fixed", because changing it now would move every shipped screen | **Equal**, with a named divergence (`src/layout/solver.luau:581,1110,2541` — `node.gap or 0`) |
| `HorizontalAlignment` / `VerticalAlignment` (whole-group) | `align` on the cross axis (`start`/`center`/`end`/**`stretch`**) and `distribute` on the main axis | **Superset** — `align = "stretch"` has no whole-group native equivalent, and `distribute` carries `start`/`center`/`end` *and* the three space modes in one word, where native splits the same information across two unrelated property groups |
| `HorizontalFlex` / `VerticalFlex` (`Enum.UIFlexAlignment`: `SpaceBetween`, `SpaceAround`, `SpaceEvenly`) | `distribute` — **closed 2026-08-12**. All three space modes ship, plus `start`/`center`/`end` | **Superset.** This was gap 1: before `distribute`, the solver packed from the start of the axis unconditionally, and a variable-count list could not be spaced at all (`src/layout/solver.luau:3401-3419`) |
| `UIFlexMode` `Shrink`/`Fill` + `ShrinkRatio` | `shrinkWeight` (proportional, `weight × basis`) **inside** `layoutPriority` tiers (ordered, lowest-first) | **Superset.** This was gap 2: the solver had no shrink pass at all — `hug`/`content`/`fixed` never shrank and overflow only produced a diagnostic. Native gives a flat per-item ratio with no tiering concept; CSS gives only the proportional level and SwiftUI only the ordered one ([SW-13]). LuauUI composes both, for one sort |
| `UIFlexMode` `Grow` + `GrowRatio` | weighted `fill` dims with largest-remainder rounding | **Equal** — already shipped before this round |
| `ItemLineAlignment` (per-item cross-axis) | `lineAlign` (`start`/`center`/`end`/`stretch`) | **Superset.** This was gap 3: LuauUI had no leaf-level route to per-child cross-axis alignment at all — the solver read `child.align`, but `align` is a container-only prop, so it only worked on a child that was itself a stack, where the one word then meant two things. `lineAlign` is legal on **every** box, where native needs a `UIFlexItem` instance per item (`src/blueprint_schema.luau:549-559`, `src/layout/solver.luau:3462`) |
| `Wraps` | `wrap` on `UI.HStack`/`UI.VStack` — **closed 2026-08-13** | **Superset.** This was gap 4. Native's `Wraps` is a plain settable boolean; LuauUI's is a **reactive** prop, so a row can be bound to wrap on a phone and not on a desktop without remounting a child. It also reports what native silently does not: a child wider than its line is clamped **and named**, and a block of lines taller than its box files a cross-axis diagnostic — the first overflow message in the file that is not about a main axis |
| `SortOrder` | document order only; no `LayoutOrder` analogue | **Divergence**, see the caveat above |
| — | `layoutPriority` tiers, per-child `margin`, `minMax` dims, hug/content sizing, `ViewThatFits`, `UI.Composition`/`Region` ranked degradation, `containerRelativeFrame`, `GridRow` spanning, incremental layout, and the inert-placement-prop audit | **Ten capabilities with no native equivalent at all.** Native silently ignores a property the current layout mode does not use (`HorizontalFlex` under a vertical `FillDirection`, say) with no diagnostic channel; LuauUI files a complaint |

**The honest scorecard, as of 2026-08-13: nothing behind.** Flow-wrap was the one
place a Roblox developer could do something with `UIListLayout` that they could
not do with LuauUI, and `wrap` closed it. The single remaining divergence in this
table is `SortOrder`, which is a deliberate one (document order is the only
order, see the caveat above) rather than a missing capability.

### 4.2 Lazy stacks, and the variable-item-extent gap underneath them

**No `LazyVStack` and no `LazyHStack` ship as names** (game-director decision,
2026-08-12). The locked decision going into this round was that they must be thin
sugar over the existing virtualized substrate rather than a second virtualizer.
Holding to that, the substrate turned out not to leave room for the sugar:
`newVirtualList` requires a **uniform** item extent, an explicit `key` and an
explicit `cell`, where SwiftUI's `LazyVStack` takes arbitrary heterogeneous
content with no declared height and no key function. That last part is an
argument from *absence*, and it is worth being precise about: Apple documents the
laziness — the stack "doesn't create items until it needs to render them
onscreen" — and imposes no declared extent and no key anywhere on the page
([SW-31]). A constructor wearing
SwiftUI's name over those requirements would be a parity claim the code does not
honour, which the API constitution rates as a defect of the same severity as the
reverse. Stripped of the name, the sugar adds nothing but different words for the
same fields.

So `newVirtualList` is LuauUI's one lazy-collection surface, and it gained the
cheap half of what the names promised: **both axes.** `axis = "y" | "x"`,
construction-only for the same reason `ScrollView.axis` is (a reactive engine
scroll axis would rebuild native scroll state mid-gesture). With the axis came
axis-neutral naming — `itemExtent` and `viewportExtent` are canonical, and the
old `rowHeight` / `viewportHeight` keep working as **deprecated aliases**
registered in `LuauUI.DEPRECATIONS` for at least one MINOR per
[`ADR-0011`](../adr/ADR-0011-semver-and-deprecation.md). A `rowHeight` on a
sideways list is a lying name, and this codebase punishes those.

#### The requirement that is not built: variable item extents

This is the expensive half, and it gets a section rather than a table row because
a future mission should start from the problem rather than from the symptom.

**The requirement.** A collection where each item's extent along the scroll axis
differs — a feed of posts with different body lengths, a chat log, a settings
list with wrapped explanatory text — should still be virtualized: only the items
near the viewport built, measured and mounted.

**Why `index × pitch` cannot express it.** Today's windowing arithmetic is
`index × pitch`, which is O(1) and exact: to know which items are in view, the
list multiplies. Variable extents need a **running-offset index** instead — a
prefix sum of every preceding item's extent. And the honest problem underneath is
that *an item's extent is only known by building it*, which is precisely the work
virtualization exists to avoid. The refusal in the source says the operational
half of this out loud: a per-row wrap difference would silently mis-window, and
it would do so worst at the largest preferred-text offset, where the wrap
differences are biggest and the player is least able to tolerate a list that
jumps (`src/controls/virtual_list.luau:449`).

**The two candidate designs, and what each costs.**

| Design | How it works | What it costs |
|---|---|---|
| **Estimate and correct** | Assume an estimated extent for unmeasured items; replace each estimate with the real measurement as the item enters the window; re-derive the running offsets | The scroll thumb **jumps**. Total content extent is a moving estimate, so the scrollbar's proportions change under the player's finger as they scroll, and a long scroll back to a place they have been changes where that place is. Mitigations (freeze the estimate once seen, anchor corrections above the viewport) are all partial |
| **Measure up front** | Measure every item's extent at mount, then window exactly | Laziness survives for *instance creation* but not for *measurement*. A 10 000-item list pays a full measure pass at mount — text measurement is the expensive part and it is exactly what would run. The list is no longer lazy in the sense that matters for a first frame |

**Why it is not built.** Choosing between two designs that each give something up
needs a screen that actually wants it, and there is none: every Rascal Rally list
and every gallery collection is uniform. Building the wrong one now would be
worse than building neither, because the windowing arithmetic is load-bearing for
`Table`'s culling as well. The requirement and both designs are recorded here so
the next mission starts from the problem statement.

### 4.3 Flow-wrap — closed 2026-08-13, and the "undefined rule" was defined

Roblox's `UIListLayout.Wraps` packs "as many as fit per line" with ragged item
widths. LuauUI could not express it, and no combination of shipped constructs
faked it: `UI.Grid` is a **uniform-pitch** layout where every cell gets
`innerW / cols`, and `minColumnWidth = "intrinsic"` sizes every column to the
widest child — a different and more wasteful shape, not a ragged one.

`UI.HStack{ wrap = true }` / `UI.VStack{ wrap = true }` is the closure. Three
things about how it landed are worth keeping, because two of them contradict what
this section previously predicted.

**It is a prop, not a mission-sized construct.** The construction ladder's test is
whether the thing "needs its own layout/paint/input semantics an existing class
cannot compose". A wrapping stack has the same children, the same paint, the same
input, the same `gap`/`align`/`lineAlign`/`distribute` as the stack it is a mode
of; one boolean is the entire difference. Making it a class would also have made
"wrap on a phone, one line on a desktop" a `UI.When` swap, i.e. a remount of every
child — the exact defect `UI.AdaptiveStack` exists to prevent.

**The "cross-axis rule the documentation does not define" is defined — it just is
not written down.** This section said LuauUI "would have to define it, and own the
divergence". `AlignContent` does appear zero times in the engine API dump, and
neither the `UIListLayout` reference nor the flex-layouts guide discusses how
wrapped *lines* are positioned. But undocumented is not undefined, and the engine
had never been asked. Probed live in Studio on 2026-08-13 — a 300×400 container,
six 100×40 items, so 80px of lines inside 400px:

| `VerticalAlignment` | item `y` offsets | reading |
|---|---|---|
| `Top` (default) | `0,0,0, 40,40,40` | the block of lines packs at the start |
| `Center` | `160,160,160, 200,200,200` | the **block** is centred — `(400−80)/2` exactly |
| `Bottom` | `320,320,320, 360,360,360` | the block sits at the end — `400−80` exactly |
| ragged (item 2 is 90 tall) | `0,0,0, 90,90,90` | a line is as tall as its **tallest** item |

So the lines pack with no space between them, the whole block is placed by the
alignment property the container already had, and there is **no separate
`align-content` to invent**. LuauUI's `align` / `lineAlign` / `distribute` map
one-to-one onto `VerticalAlignment` / `ItemLineAlignment` / `HorizontalFlex`
already, so flow-wrap added **one prop and no alignment vocabulary at all**. The
divergence this section expected to own does not exist; CSS's `space-between`
*between lines* has no native counterpart and LuauUI does not add one.

**SwiftUI is not the reference here.** Apple's live symbol index was searched on
2026-08-13 for every node whose title contains "flow" or "wrap": every hit is
`wrappedValue` / `FileWrapper` / `toolbarOverflowMenu`. SwiftUI ships **no** flow
layout, and its answer to this shape is "write a custom `Layout`" ([SW-10]). That
is the strongest argument for building a public `Layout` protocol instead, and it
loses here for a reason recorded in full in `docs/plans/swiftui-parity-round3.md`:
the gap is a native one, and a public `Layout` would be the first
consumer-authored code inside the solve, which the measure memo's cache key, the
incremental-arrange reuse skip and the placement-prop audit are each unsound
without. The protocol is recorded there as a **conditional refusal with a
trigger**, not an open TODO.

The third prediction held: it does interact with the machinery around it, and the
answers are all refusals rather than integrations. It does not compose with
`newVirtualList` (the virtualizer windows by `index × pitch` and needs a uniform
extent), the shrink pair is not read on a wrapping stack (wrapping *is* what this
stack does with a deficit), and `align = "stretch"` is refused because it would
mean two things at once.

### 4.4 Baseline alignment and `alignmentGuide` — named non-deliveries

Both are **Missing**, both were audited this round, and both were deliberately
not attempted. They are recorded here rather than left as bare table rows because
each has a known shape and a known cost:

- **Baseline alignment** (`.firstTextBaseline` / `.lastTextBaseline`) needs the
  text-measure pass to publish an **ascent per child** alongside the extents it
  already publishes, plus a new arrange term that offsets each child so those
  ascents line up. It is a solver change in both passes, not a new enum value.
- **`.alignmentGuide` / custom `AlignmentID`** needs a per-axis guide-resolution
  pass threaded through arrange: a child declares a guide value, the parent
  collects them, and alignment resolves against the collected guides rather than
  against the box edges.

Neither has a consumer asking for it. Both are listed in §13.

---

## 5. Controls catalog

LuauUI's conformance registry holds **42 rows: 16 composite control classes and
26 non-interactive leaves**. Fifteen of those rows are interactive, and **all
fifteen carry an automated four-input proof and also prove the device-idiom
axis.** That is far short of SwiftUI's catalog in breadth and ahead of it in
per-control rigour. Six controls that used to be "here's how you'd build it"
recipes are real exported composites: `newSlider`, `newStepper`, `newPicker`,
`newProgressView`, `newLabel`, `newDisclosureGroup`.

| SwiftUI item | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `.swipeActions` — secondary actions on a row ([SW-37]) | **Covered** | `LuauUI.newRowActions` / `LuauUI.newRowActionsCoordinator`, a general construct that wraps *any* row content, plus turnkey `spec.rowActions` on **both** `Table` and `newVirtualList`. The defaults match Apple's: trailing edge, full-swipe on ([SW-37]). Being *general* rather than list-bound used to be a LuauUI lead, and this June it stopped being one — SwiftUI's own swipe actions now apply "to a row in a list or container", meaning scroll views, stacks, grids and custom layouts ([SW-38]). The one place LuauUI is still ahead of the modifier itself is platform reach: Apple ships `swipeActions` on iOS, macOS and watchOS and **not on tvOS** ([SW-37]). Detail and remaining gaps in §5.1 | `src/controls/row_actions.luau`; `src/init.luau:229,234`; `tests/row_actions.spec.luau`, `tests/row_actions_input.spec.luau` |
| `Slider` | **Partial** | Real composite: pointer drag, tap-to-position, touch drag, keyboard/gamepad nudge. Cancels cleanly if the input device changes mid-drag | `src/controls/slider.luau:139`; `tests/conformance/controls_registry.luau` |
| `Stepper` | **Partial** | Real composite | `src/controls/stepper.luau:73`; registry |
| `Picker` (`.segmented` and `.inline`) ([SW-41]) | **Partial** | One adaptive composite replaces both styles: `picker.resolvePresentation(optionCount, sizeClass, longestLabel)` chooses segmented vs inline from option count, screen size class, and label length — never from a device name. `presentation` is `"automatic" \| "segmented" \| "inline"` | `src/controls/picker.luau:33,67,79-81`; registry |
| `ProgressView` (determinate) | **Covered** | Real composite, declared non-interactive (so it is exempt from the four-input proof by design, not by omission) | `src/controls/progress_view.luau`; registry row `ProgressView` (`inputProofs = false`) |
| `ProgressView` (circular, indeterminate) + the `Gauge` capacity ring | **Covered** | Shipped 2026-08-13 (parity round 3, D2). `presentation = "circular"` accepts BOTH modes, and both are one function of one scalar: determinate binds `arc(0, 360 x fraction)` over a static capacity ring, indeterminate binds `arc(360 x phase, 90deg)` — a fixed sweep whose START ANGLE advances, which is how it rotates with no rotation channel in the blueprint. There is **no native radial primitive in the engine** (searched 2026-08-13: no angular `UIGradient` mode, no `ImageLabel` fractional fill, no `EditableImage` arc, and `GuiObject.Rotation` has a fixed pivot and is documented incompatible with `ClipsDescendants`), so both forms are strokes on the shipped `UI.Path` + `LuauUI.pathShapes.arc`; `points` is `dirty = { "paint" }`, so a value change and a frame of rotation are each one prop write and **zero re-solves**. **The parity claim is split on purpose**: the INDETERMINATE ring is `ProgressView(.circular)`, whose own documentation says "in cases where no determinate circular progress view style is available, circular progress views use an indeterminate style" ([SW-130]), while the DETERMINATE ring is the `Gauge` shape `.accessoryCircularCapacity` ([SW-131], "a closed ring that's partially filled in") rather than a `ProgressView`, and this document does not claim `ProgressView` parity for it. It adds **no blueprint prop and no decoration slot** — the arc paints through the Path's own `role`, and its size is two OPTIONAL theme metrics (`controls.progress.circularSize` / `circularThickness`) so no shipped package's content stamp moves. Refusals, generated from the same capability registry as the two below rather than hand-written: `height` (the bar's track) and `showValue` (Apple centres it inside the ring, and that is `Gauge`'s complication-sized dial, not this small theme-sized one). Two platform facts a caller must know: a `Path2D` has **no transparency at all**, so the ring cannot fade without a caller-declared `canvasGroup` container, and a path not FULLY inside every clip host above it does not paint rather than being cropped | `src/controls/progress_view.luau`; `tests/progress_circular.spec.luau`; `tests/display_controls.spec.luau`; fixture `examples/gallery/scenarios/progress_ring.luau` |
| `ProgressView` (indeterminate / dot spinner) | **Covered** | Shipped 2026-08-13. Indeterminate is selected by **`value = nil`**, SwiftUI's own rule — Apple's is "use an initializer that doesn't take a progress value", and its `value` parameter is documented as nil-for-indeterminate ([SW-43]) — so no second flag that could disagree with the value. `presentation = "bar" \| "spinner"`. The spinner is a ring of five fixed-size **dots** rather than an arc (round 2 had no arc; round 3 built one as `presentation = "circular"`, and the dots are kept unchanged as the fallback if the arc's per-frame paint ever proves too costly on a device — its refusal message now names `circular` instead of the rotation channel the framework no longer lacks); its travelling pulse rides the `tint` channel, which is `dirty = { "paint" }`, so the ring animates for **zero re-solves** and can be dropped into any container without asking what its parent's axis is. (The first shape sized each dot as a `percent` of its row, and the solver said what it always says the moment it was mounted inside a vertical `ScrollView`: a fraction of an unbounded axis is not a size.) Narrowings, all refusals rather than silent drops: a spinner requires `value = nil`; `min`/`max`/`format`/`showValue` are refused on an indeterminate view; and `height` — the BAR's track thickness — is refused on a spinner rather than silently becoming the dot's size (the dot is the theme metric `controls.progress.spinnerDotSize`). **An indeterminate view also names its owner**: `scope` is required for `value = nil`, exactly as `newAsyncImage` requires one, because the cycle holds a live motion-clock entry for as long as the view exists and nothing else would ever retire it (measured: a dismissed — and an unpresented — indicator kept writing its phase 121 times per 120 clock steps, forever). **Reduced motion is the deliberate opposite of the usual call**: the indicator is `kind = "informational"`, so it keeps advancing on the motion authority's quantized 250 ms tick instead of freezing — a frozen spinner and a hung process look identical | `src/controls/progress_view.luau:108,154,180,194,196-201,203-210,213-233,326-343`; `tests/display_controls.spec.luau:1057-1180,1352-1382` |
| `AsyncImage` — a picture that loads later, with a placeholder in the meantime ([SW-132]) | **Covered** | `LuauUI.newAsyncImage`. The load runs through `newResourceProvider`, so the composite is engine-free and testable: `state` is `"pending" | "ready" | "failed"`, the placeholder is painted while pending, and **a failure keeps the placeholder** rather than drawing a broken-image glyph. That last rule is Apple's own, arrived at independently — SwiftUI's page says that if an `Image` placeholder “doesn’t load, SwiftUI doesn’t show anything as a placeholder and doesn’t report an error” ([SW-132]). Two things LuauUI adds that SwiftUI has no counterpart for: a required `scope` (the provider handle is released with its owner, and a stale completion is rejected by generation counter rather than applied to a reused node), and per-call-site `retry = { count, delaySeconds }`. Two it lacks: there is no `phase`-closure initializer — the three states are the composite's own layers, not a consumer-authored view per phase — and no image cache (SwiftUI's is transport-level from the 27.0 releases, [SW-132]); Roblox's content system does its own caching underneath, which this framework neither controls nor observes | `src/controls/async_image.luau`; `src/init.luau:198`; `tests/async_image.spec.luau` |
| `Label` (title + icon) | **Partial** | Real composite with the presentation resolution SwiftUI's `LabelStyle` provides: `presentation: "titleAndIcon" \| "titleOnly" \| "iconOnly"`, default `titleAndIcon`, and `iconOnly` degrades safely to `titleOnly` when no icon resolves. That last comparison used to read "better than SwiftUI's, which shows nothing", and it is withdrawn: **Apple documents no behaviour here.** `LabelStyle.iconOnly` documents only that the title survives for VoiceOver ([SW-46]) and says nothing about what is painted when the icon is missing, so the honest claim is that LuauUI defines the case and Apple's documentation does not. **Its `title` is a static string, not bindable** — a known follow-on with no shipped screen asking for it. It also does **not** compose into `newPopupButton`: that control builds its trigger and its rows as `UI.Button{ label = … }` with a flat string, never a Label blueprint | `src/controls/label.luau:21,23,30,49-56,65-70`; `src/controls/popup_button.luau:232-238,285-291` |
| `DisclosureGroup` | **Partial** | Real composite, including the correct focus behavior on collapse (focus moves to the header before the content unmounts, so it is never lost). `content` is a function mounted only while expanded | `src/controls/disclosure_group.luau:29,45`; registry |
| `Divider` | **Covered** | A real axis-aware hairline leaf that infers its own orientation — not a hand-sized box. Same rule SwiftUI states: in a stack the divider extends across the stack's minor axis ([SW-48]) | `src/blueprint_schema.luau:1354` |
| Star-rating strip | **Covered** — no SwiftUI standard-library counterpart ([SW-10]) | `newRating`: a single focus stop that supports tap, scrub, and keyboard/gamepad adjust, and cancels back to its prior value if the pointer is lost mid-scrub | `src/controls/rating.luau:123` |
| `Menu` / dropdown button | **Partial** | `newPopupButton` adapts its presentation: `resolvePresentation(optionCount, sizeClass, touchLive)` returns a sheet whenever touch is live, a sheet on compact screens with more than 6 options, an inline list at 3 or fewer options on larger screens, and a menu otherwise. See §5.4 on row heights | `src/controls/popup_button.luau:67-78` |
| `Table.onPrimaryAction` (SwiftUI: `contextMenu(forSelectionType:menu:primaryAction:)`) | **Covered** | Shipped 2026-08-13; touch model corrected to Apple's documented one 2026-08-13. **`onPrimaryAction` is our name, not SwiftUI's** — there is no such symbol in SwiftUI; the verb arrives as the `primaryAction:` argument of the item-based context-menu modifier. Its documentation is the rule implemented: *"In macOS, a single click… selects that row, and a double click performs the primary action. In iOS and iPadOS, tapping on the row activates the primary action. To select a row without performing an action, either enter edit mode or hold shift or command on a keyboard while tapping the row."* So: pointer **double-click**, touch **plain single tap**, and **edit mode is the touch selection mode** (`EditMode`, HIG Lists and tables) — where a tap toggles selection and never opens, which restores `multi`'s tap-to-deselect. The **cost is Apple's own and is documented rather than hidden**: with an action declared, touch loses tap-to-select in normal mode entirely, including the single selection iOS 16+ allows; a table whose dominant touch use is selecting should not declare the action. Gamepad **A/Cross** and keyboard `Return` are **conventions, not parity** — Apple documents no key for row activation (`Return` matches `NSTableView` practice). A modified click (Shift / Cmd / Ctrl) never opens, on any input. The double-click window takes an injected clock through the existing `bindMotion` contribution seam and falls back to `os.clock` — without a scripted `now`, two `adapter.tap` calls in a spec are microseconds apart and the window is satisfied by the test's own speed rather than by the code | `src/controls/table.luau:176-185,1932-1989,2187-2196`; `tests/table_input.spec.luau` §5 |
| `Table` / `List` with selection and reordering | **Partial** | Reorderable rows, selection, per-cell rendering via `column.cell`/`cellFor`, and swipe actions via `spec.rowActions`. **Modifier-click multi-select IS shipped** — Shift-click ranges and Cmd/Ctrl-click toggles, anchor-tracked, with the anchor pruned on row removal. The previous claim that it was not came from a stale "Phase B" file header, which now says what shipped and cites the lesson it taught. **No virtualization**; column resize still remounts every row | `src/controls/table.luau:6-7,8-14,526,2016,2168-2173`; `tests/table.spec.luau` |
| `selectionDisabled(_:)` (iOS 17 / macOS 14) — per-row selection opt-out | **Missing** — a named gap, deliberately deferred 2026-08-13 | `selection` is whole-table (`Table`) or whole-list (`newVirtualList`); there is no per-row opt-out anywhere. `newVirtualList` has `rowFocusable` (a live per-row predicate) but it is **focus-only and says so** — "a tap on a focus-INELIGIBLE row still activates and still sets the logical key"; `Table` has no per-row machinery at all. **Why deferred rather than built:** Apple's opt-outs are a *family*, one per capability — `selectionDisabled` / `deleteDisabled(_:)` / `moveDisabled(_:)` — and LuauUI has both other capabilities (reorder, destructive row actions) on **two** controls that §13 already records should be unified, so shipping one member commits to six predicates in the expensive order. And the one production surface that refuses selection per row would **not adopt it**: RascalRally's sponsor racer list must *explain* the refusal (a toast, a refusal counter, and the selection visibly returning to the watched racer), which an inert row cannot do. A capability its only candidate consumer would not switch to fails rung 1 of the simplicity ladder | `src/controls/virtual_list.luau:369,987,2459` (`rowFocusable`, focus-only and said so at `:999-1000`); zero occurrences of a per-row selection predicate in `src/controls/table.luau`; the workaround at `games/RascalRally/code/src/client/LuauUISponsor/init.luau:1645-1653` |
| `.contextMenu` ([SW-50]) | **Missing** | No `contextMenu` construct exists in source at all. Apple documents the trigger this would have to honour — "touch and hold in iOS or iPadOS" ([SW-50]). What exists is the *menu* half (row actions render exactly that kind of action list) and a normalized gesture layer nothing consumes as a trigger — see §5.2 | zero occurrences of `contextMenu` in `src/` |
| `ButtonStyle` / `ToggleStyle` / `PickerStyle` / `LabelStyle` / `ProgressViewStyle` / `ListStyle` / `GaugeStyle` protocols — each documented as the way to give a control family a custom appearance ([SW-51], [SW-52], [SW-41], [SW-45], [SW-53], [SW-54], [SW-55]) | **Missing, by decision** | Not an omission: native StyleSheets and theme packages own paint. §6 carries the mapping table a SwiftUI author needs | — |
| Palette `Picker` ([SW-42]) | **Missing** | `presentation` is closed to `automatic`/`segmented`/`inline`. Apple's `.palette` is itself narrow — iOS 17 and macOS 14 up, and absent from tvOS and watchOS ([SW-42]) | `src/controls/picker.luau:79-81` |
| `DatePicker` ([SW-62]), `ColorPicker` ([SW-63]), `SecureField` ([SW-64]), multi-line `TextEditor` ([SW-65]), `Gauge` ([SW-66]), `Link` ([SW-67]), `ShareLink` ([SW-68]), `NavigationSplitView` ([SW-69]) | **Missing** | Each reconfirmed absent by direct search of current source, 2026-08-13. Worth knowing before treating this row as eight uniform holes: SwiftUI itself does not ship five of them on tvOS (`DatePicker`, `ColorPicker`, `TextEditor`, `Gauge`, `ShareLink`) or two of them on watchOS (`ColorPicker`, `TextEditor`) — the availability is on each citation | — |
| `.sensoryFeedback` at the control level ([SW-70]) | **Covered** as a blueprint modifier, **Missing** as a per-control hook | `UI.sensoryFeedback(bp, { trigger, event })` ships and any node can carry it (§7). There is still no per-control "this control's activation feeds haptics" declaration — the author attaches the modifier | `src/blueprint.luau:1160` |

### 5.1 Row swipe actions, in detail

`LuauUI.newRowActions` and `LuauUI.newRowActionsCoordinator` are standalone
public exports — proven working in a hand-built `ScrollView > VStack` list with
no `Table` involved. `Table.rowActions` and `newVirtualList.rowActions` are those
two classes wiring the same two seams for consumers who don't want to hand-roll a
list.

What ships, per `tests/conformance/controls_registry.luau` and
`tests/row_actions*.spec.luau`:

- **Leading and trailing action trays**, revealed by mouse drag or touch pan,
  growing proportionally under a spring.
- **Full-swipe commit per edge** (`fullSwipe` as a bool or `{leading, trailing}`):
  swiping past the threshold fires the first action of that edge. For a
  destructive action the row slides off and its height collapses to zero;
  `onAction` fires exactly once either way.
- **Keyboard Delete/Backspace** fires the row's first destructive action. It is
  scoped to the row's own mounted subtree (so it cannot fire for a row you are
  not focused on) and inert while that row's menu is open.
- **Shift+Return and gamepad ButtonX** open an action menu listing every action —
  the framework's first modifier-aware key binding.
- **An edit-mode minus affordance** that opens whichever edge actually holds the
  destructive action.
- **A one-open coordinator**: opening row B closes row A; scrolling or tapping
  outside closes the open row.
- **Arbitration against reorder drag**: an 8 px axis lock sends horizontal motion
  to the actions and vertical motion to the scroller; ties go vertical; a drag
  starting on the reorder handle always wins.
- **Mid-gesture device switching** behaves predictably: a touch that lands
  mid-mouse-drag is declined and the mouse keeps the drag; the reverse likewise;
  a cancelled touch springs the row back to closed.

**Performance — the gap this feature used to own is closed.** The original
implementation cost +57 % steady-scroll time, +81 % fling time and 5 extra Roblox
instances per row inside `newVirtualList`, against its own plan's ≤5 % / ≤4
budget, and the gate was re-baselined to those measured numbers by director
ruling with the miss left on record. **Hosted mode superseded that** on
2026-08-12: `newVirtualList` gained `spec.rowActions`, a closed row now mounts
**nothing** extra (a shared dispatcher wires four static props onto the row's
existing `Hit` button, the gesture engine is built lazily on first pointer-down,
and the engaged row's slide rides the presentation channel rather than a layout
prop). The gate ceilings were restored to **≤5 % steady, ≤5 % fling, ≤1 instance**
and the current five-run ABBA means are **−0.28 % steady, +2.83 % fling, 0.08
instances per closed row** — all passing, with the fling number the only real
positive cost and about 2 pp of headroom. The measurement discipline is on record
with them: per-run sd is 0.96–2.90 pp, so the budget is called on ≥5-run means,
never a single run.
(`tools/check_row_actions_matrix.py:81-83`;
`artifacts/row-actions/device-matrix.md:209-219`;
[`row-actions-hosted-mode-design.md`](../plans/row-actions-hosted-mode-design.md);
the superseded charter is [`row-actions-perf-mission.md`](../plans/row-actions-perf-mission.md), now **CLOSED**.)

**Its remaining named gaps**, all real:

- **No right-to-left support.** "Leading" means left and "trailing" means right,
  unconditionally. This is an explicit non-goal and matches the framework-wide
  absence of RTL/BiDi.
- **Two of five secondary-action triggers are absent.** Of swipe, keyboard,
  gamepad, mouse secondary-click, and touch long-press, the first three are real.
  Mouse right-click and touch long-press reach the menu only through the reveal
  tray, not directly.
- **Vertical lists only.** On a horizontal `newVirtualList` the tray's reveal
  swipe *is* the scroll gesture, so `rowActions` is refused at construction
  naming the conflict rather than picking one meaning silently.

An adversarial code review of the whole feature closed at 16 findings — 15 fixed
directly, 1 resolved by a design change (`bindPresent`, §9). A five-viewport
Studio device matrix passes. Six physical-device checks remain owed (§14).

### 5.2 `.contextMenu` — why it is still Missing

The *menu* half is proven: row actions render exactly that kind of action list.
The *trigger* half is not. A normalization and arbitration layer over Roblox's
native gesture recognizers ships and is publicly exported
(`src/input/touch_gestures.luau`, `LuauUI.touchGestures`) — tap, long-press, pan,
pinch, rotate, and swipe, all wired end-to-end and listed on the render-target
contract (§1), so a target that cannot supply gestures degrades by name rather
than crashing. **No control calls it** — no file under `src/controls/` requires
the module. `Button` still filters input to primary mouse button and touch. So
the blocker is not "there is no adaptation layer" but "the adaptation layer is
built, tested, and exported, and nothing consumes it as a trigger" — a materially
smaller gap, and the most obvious next candidate.

### 5.3 Named non-deliveries recorded by this round

Three gaps were found by audit this round, understood, and deliberately not
closed. They are written down as decisions rather than left to be rediscovered:

- **`Toggle` cannot compose a `Label`.** `Toggle` is a non-container **leaf**
  with a flat `label` prop (`container = false`, `src/blueprint_schema.luau:1681,1684-1691`),
  so an icon-plus-title toggle needs a hand-rolled composite that would duplicate
  Toggle's focus and activation wiring. SwiftUI's `Toggle` takes an arbitrary
  label *view* ([SW-56]), which is exactly the affordance missing here. This is a **real** gap and an ordinary
  settings-screen pattern. Closing it means making `Toggle` a container the way
  `Button` became one (`container = true`, `:1558`) — control-authoring work
  outside this round's scope, flagged for a future mission rather than smuggled
  in. Note that `Button` being a container does *not* by itself solve the same
  problem for `Button`: its own `label` prop is likewise a flat string, so a
  Label-shaped button is custom content inside one activation surface, not a
  `Label` passed to `label`.
- **Baseline alignment and `.alignmentGuide`** — §4.4.
- **`Spacer(minLength:)`** — Composable today via `minMax`; a first-class prop
  would be sugar and is not built.

### 5.4 Caveats on the catalog

- **`PopupButton` row heights.** Its `sheet` presentation derives row height from
  the theme's `regular` control size, which resolves to the 44 px minimum hit
  target, so the touch path never serves a row below the floor. The pointer-only
  `menu` presentation still serves 36 px rows — genuinely below the 44 pt hit
  region Apple's HIG asks for ([SW-72]), but now confined to a pointer-only code
  path
  (`src/themes/snapshot.luau:118-120,137`). Panel flip/clamp behavior and
  selection-only rows are unchanged and unaddressed.
- **No `*Style` protocol** — see §6. This is a decision with a mapping, not a
  hole.
- The full 69-item SwiftUI catalog comparison is not re-listed here. Items not
  named above were not independently re-examined in this pass.

---

## 6. Styling & theming

Theming is a complete, shipped capability class, and it goes further than
"swap a palette": a *theme package* owns typography, spacing, control heights,
corner radii, strokes, content insets the solver can see, and asset-backed
chrome art. Installing or swapping one happens in a single transaction, so paint
and geometry land on the same frame with mount identity, focus, scroll position,
selection, and in-progress text entry all surviving. Dark/Light swapping rides
Roblox's native StyleSheets with no remount at all.

The durable difference is the opposite of the strength: LuauUI lets a *theme*
change everything about how controls look, but does not let a *consumer* change
what one control renders as.

### 6.1 The `*Style`-protocol decision, and the mapping a SwiftUI author needs

**LuauUI will not add `ButtonStyle` / `ToggleStyle` / `PickerStyle` /
`LabelStyle` protocols.** This was re-ratified for this round: native Roblox
StyleSheets and theme packages own paint, and a parallel custom
rendering-substitution protocol would be a second authority over the same pixels.
The roadmap's priority rule 4 is explicit that a Roblox-native mechanism ranks
above a parallel custom one when it meets the behaviour bar, and here it does.

What a SwiftUI author reaching for a `*Style` should reach for instead:

| SwiftUI protocol | What you are actually trying to change | LuauUI route |
|---|---|---|
| `ButtonStyle` — fills, corners, press/hover treatment | paint | The theme package's `control` decoration slot, its per-state art maps, and the semantic `role` prop. Native StyleSheets carry the state selectors |
| `ButtonStyle` — a button whose *content* is arbitrary | structure | `UI.Button` is a **container** (`src/blueprint_schema.luau:1558`): put your own blueprint inside it. All of it stays one activation surface with one focus stop |
| `ToggleStyle` | paint | The `toggleTrack` / `toggleKnob` decoration slots. **Structure is not reachable** — `Toggle` is a leaf (§5.3), and that is a named gap, not part of this decision |
| `LabelStyle` — a bespoke title/icon arrangement | structure | **Compose your own `UI.HStack` / `UI.VStack`** rather than calling `newLabel`. `newLabel` *is* the default style; there is no pluggable style object, and a hand-authored arrangement costs three lines |
| `PickerStyle` | which presentation | `picker.resolvePresentation(...)` decides segmented vs inline from option count, size class and label length. Force it with `presentation = "segmented" \| "inline"`; `"automatic"` is the default |
| `ProgressViewStyle` | paint + which presentation | `barTrack` / `barFill` / `barCap` / `barCenter` / `spinner` slots, plus `presentation = "bar" \| "circular" \| "spinner"` |
| `ListStyle` — per-row rendering | structure | `Table`'s `column.cell` / `spec.cellFor`, and `newVirtualList`'s `cell` — these are real per-instance rendering-injection seams and they *are* the answer for collections |
| `GaugeStyle` | — | No `Gauge` control exists. The ONE gauge shape that does ship is `.accessoryCircularCapacity`'s ([SW-131]) — a closed ring partially filled in — as `newProgressView{ presentation = "circular" }` with a value; nothing else of `Gauge` (ranges, marks, current/min/max labels) is built |

The honest residue: for a control whose *chrome* is the thing you want to
replace and whose slot vocabulary does not reach it — a slider whose thumb you
want to draw yourself in Luau rather than as art — there is no seam. That is the
cost of the decision, and it is stated rather than hidden.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `*Style` protocols | **Missing, by decision** | See the mapping above | — |
| View modifiers that attach validated data to a node | **Covered** | **Sixteen** ship, not the three the previous revision claimed: `shadow`, `gradient`, `corners`, `stroke`, `styleGroup`, `frame`, `padding`, `offset`, `aspectRatio`, `alignment`, `overlay`, `background`, `containerRelativeFrame`, `sensoryFeedback`, `draggable`, `dropTarget`. Each normalizes to bounded data at construction; none substitutes rendering. The positional-scalar sub-family (`offset`, `aspectRatio`, `alignment`) is declared **closed** by the API constitution — a new modifier with three or more fields takes a spec table | `src/blueprint.luau:1004,1061,1068,1083,1133,1137,1160,1201,1295,1325,1339,1387,1470,1480,1524,1540`; [`constitution.md`](constitution.md) E-18 |
| Style properties that react to state changes after mount | **Covered** | Eleven: `shape`, `surface`, `role`, `shadow`, `gradient`, `corners`, `stroke`, `textAlign`, `scaleMode`, `compactLabel`, `icon` — re-applied on every reactive change through the live paint/semantics dirty loop, in a declared order | `src/render/renderer.luau:129-141` (`STYLE_PROP_ORDER`) |
| Materials — blur, vibrancy, translucency ([SW-73]) | **Missing** | Nothing in the framework produces a blurred, backdrop-sampling, or translucent material. Apple's `Material` is explicit that this is not opacity — it is "a platform-specific blending that produces an effect that resembles heavily frosted glass", with vibrancy on top ([SW-73]). Theme packages work in flat fills, nine-slice art, gradients (alpha capped at 0.9), and layered image chrome — all opaque compositing | — |
| Liquid Glass (`.glassEffect()` ([SW-74]), `GlassEffectContainer` ([SW-75])) | **Missing**, and **the gap widened** | Apple shipped Liquid Glass across the 26 releases — iOS/iPadOS/macOS/tvOS/watchOS 26 ([SW-74]) — and a year later its HIG still presents it as the current functional layer above content ([SW-76]), so this is a settled production system rather than a preview. LuauUI has no counterpart at any layer, and none is planned in any open design record | — |
| `.tint(_:)` cascading down a subtree | **Partial** | Per-node tinting is real and reactive: `tintRole` tints semantic icon art from the active theme's roles, `Image.tint` is a live reactive write, and a continuous colour-blend channel (`{ role, blend, from? }`) can animate between two theme roles — the channel the indeterminate spinner's pulse rides (§5). **What is absent is inheritance**: no `.tint()` recolors an entire subtree; every tint is per-node opt-in. One honest wrinkle in the comparison: Apple's `tint(_:)` page says only that it "Sets the tint color within this view" and **documents no subtree-inheritance rule** ([SW-77]) — SwiftUI's cascade is a consequence of its environment model, not of a sentence anyone can point at | `src/blueprint_schema.luau:959`; [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 6 |
| Dark mode / color schemes ([SW-78]) | **Covered** | Native StyleSheets ship `Theme Dark` and `Theme Light`, swapped at runtime with no remount and no loss of focus or scroll | [`ADR-0018`](../adr/ADR-0018-native-stylesheets.md) |
| Theme packages owning metrics and chrome, not just colors | **Covered** — no SwiftUI equivalent ([SW-10]) | A package owns typography, spacing, control heights, radii, strokes, solver-visible content insets, and asset chrome. `theme_controller.install` / `.swap` / `.swapPackage` performs one transaction — repointing the engine's style-sheet inheritance plus committing the new metric snapshot — so geometry and paint cannot disagree for a frame. Validated at definition time for contrast, completeness, legal properties, insets, and touch-target floors | [`ADR-0019`](../adr/ADR-0019-theme-packages.md); `src/client/theme_controller.luau:15-16,320` |
| Rich, image-driven skinning | **Covered** — no SwiftUI equivalent ([SW-10]) | **Seventeen** decoration slots (`panel`, `control`, `field`, `selection`, `divider`, `scrollbar`, `sliderTrack`, `sliderThumb`, `badge`, `barTrack`, `barFill`, `barCap`, `barCenter`, `stepperPlate`, `toggleTrack`, `toggleKnob`, and — new this round — `spinner`), each recipe carrying **up to 8 art layers** from a closed kind vocabulary. Plus per-state art maps, value-display hosts drawn full-size and revealed through a clip window (so a value change costs no instance write), semantic icons with an ASCII-safe fallback that can never render as tofu, a `"pixel"` rendering mode with integer snapping, and `selectBy` to pick a package by input paradigm | [`ADR-0020`](../adr/ADR-0020-rich-skinning-v2.md); `src/tokens/chrome_slots.luau:198` (slots), `:327` (`MAX_LAYERS = 8`), `:328` (layer kinds); `src/themes/package.luau:1068` (rendering modes); `src/client/theme_controller.luau:228` (`selectBy`) |
| Dynamic Type ([SW-79], [SW-80]) | **Covered** — a rigorous equivalent | The player's Roblox "Text size" preference is first-class layout input, the way Apple's is on every platform it supports — and note that Apple's does *not* cover macOS ([SW-80]), while LuauUI's applies everywhere it runs. The framework measured the actual pixel offset each preference adds and uses those **measured per-preference constants** (Medium 0, Large 4, Larger 10, Largest 14 — uniform across font, weight, and size) rather than guesses; the engine paints `TextSize + offset` and the solver reserves exactly that box. Changing the preference mid-session re-solves every mounted surface in place, preserving identity, focus, scroll, and state. Eight typography roles carry font descriptor and line height together, and the offset composes additively with ten-foot (TV) scaling | `src/env/environment.luau:51-52,60`; `docs/guide/05-styling.md` |
| `compositingGroup()` ([SW-133]) / `drawingGroup()` ([SW-134]) — flatten a subtree into one composited layer | **Partial** — `compositingGroup`'s job is covered, `drawingGroup`'s is not | The `canvasGroup` prop on `Box` and `ZStack` materializes the node as a Roblox `CanvasGroup`: the subtree renders into that node's own buffer, and the node becomes its subtree's real instance parent. That is exactly what `compositingGroup()` buys — “A compositing group makes compositing effects in this view’s ancestor views, such as opacity and the blend mode, take effect before this view is rendered” ([SW-133]) — and it is what makes a whole-subtree fade one engine property (`GroupTransparency`) instead of a per-node transparency write that would contest native-sheet paint. It is **required, not optional**, for a fading transition: `controller.setPresentationTransparency` refuses a node that is not a declared `canvasGroup` and the message names the fix. The half that is missing is `drawingGroup`'s: SwiftUI's flattens “this view’s contents into an offscreen image before final display” ([SW-134]) as a **rasterization** step, and a `CanvasGroup` re-renders its children every frame — so declaring one buys grouped alpha, never a cached bitmap, and it costs a render buffer. It is deliberately **not reactive**: it decides which engine class the node *is*, at creation, so it cannot arrive as a later prop write | `src/blueprint_schema.luau:950-957` (the prop), `:1078,1431` (`Box`, `ZStack`); `src/render/renderer.luau:1807-1808` (creation-time class choice), `:3884-3890` (the refusal) |
| `hidden()` — invisible, uninteractive, and still occupying its layout box ([SW-140]) | **Covered** (new, 2026-08-13), and **wider than Apple's** | The `hidden` box prop, on every rendered class. Apple's sentence is the specification and all three clauses are implemented: hidden views “are invisible and can’t receive or respond to interactions. However, they do remain in the view hierarchy and affect layout” ([SW-140]). This is the one place where LuauUI arranging **absolutely** — it materializes no `UIListLayout`, `UIGridLayout` or `UITableLayout` anywhere — turns an engine limitation into a non-issue: Roblox documents `Visible = false` as freeing the layout slot *inside those layouts*, and there are none here, so the box simply stays. Neither existing answer was this: `UI.When` removes the node and the siblings close up, and a losing `ViewThatFits` candidate collapses to zero. **Wider than Apple's in one respect**: `hidden()` takes no argument (“Hides this view unconditionally”, [SW-140]) and Apple's page directs you to an `if` for the conditional case — which removes the view from layout, exactly what `UI.When` does — so LuauUI's is bindable, because otherwise the space-reserving case would have no spelling at all. It dirties `arrange` and merges into the **same** hidden set the solver publishes for a losing `ViewThatFits` candidate, so one line buys the paint walk, the hit-rect retraction, the focus-order filter and the structure-epoch bump | `src/blueprint_schema.luau` (`hidden` in the shared box group); `src/render/renderer.luau` (the merge, and the tap gate on the merged verdict); `tests/lifecycle_hooks.spec.luau`; fixture `examples/gallery/scenarios/lifecycle_hidden.luau` |
| `opacity(_:)` — fade a view without removing it ([SW-141]) | **Missing**, and deliberately deferred 2026-08-13 — it is an authority decision, not a prop | A subtree CAN be faded: `controller.setPresentationTransparency` drives `GroupTransparency` on a declared `canvasGroup` node (see the compositing-group row above). What does not exist is an **authored** `opacity`, and the reason it was not added beside `hidden` in the same round is structural rather than a matter of effort: `transparency` is owned by the **presentation** channel (`src/render/authority.luau:59`), the manifest permits exactly one authority per engine property per class, and the schema has no presentation channel for an authored prop to declare. So an authorable opacity means either a second writer for a property the manifest exists to keep single, or a composition rule — effective transparency as a function of the authored value and the live presentation alpha — resolved at the one write site, which then has to be reconciled with `withAnimation`'s fade records and with the native sheet's ownership of `BackgroundTransparency`/`TextTransparency`. Apple's own page states the composition rule this would have to honour: applying `opacity` to a view “that has already had its opacity transformed… multiplies the effect of the underlying opacity transformation” ([SW-141]). That is a seam design with an ADR behind it, not a prop, and forcing it into a prop round is how a second silent authority gets shipped | `src/render/authority.luau:59`; `src/render/renderer.luau` (`setPresentationTransparency`, and its refusal for a non-`canvasGroup` node) |
| Cascade / selector model | **Covered** (supporting infrastructure) | Rules resolve by priority first, then insertion order (later wins); there is no CSS-style specificity, on purpose, so the generator and the runtime can never disagree about which rule applies. Instances are classified for the cascade by `luau-*` CollectionService tags | [`ADR-0018`](../adr/ADR-0018-native-stylesheets.md); `src/client/native_style.luau:312` |

**Caveats.**

- The style lint (jagged-corner warnings, a ~100-shadow budget) is warnings-only.
  It has no CLI and is wired into no gate — nothing fails if you ignore it.
- Rich skinning has three open verification items: a human walkthrough of the
  Roblox Style Editor, a physical-phone pass over ornate chrome art, and low-end
  device cost. All tracked, none closed by a device run.

---

## 7. Input & accessibility

**This is the area with the largest honest gap.** Focus management, keyboard
traversal, four-input conformance, drag-and-drop, and cross-device gesture
hand-off are all genuinely strong. But there is **no assistive-technology
bridge of any kind** — a repository-wide search for screen-reader, VoiceOver,
TalkBack, accessibility-label, or ARIA concepts returns nothing outside
design-intent comments. A blind player cannot use a LuauUI interface. There is
also no consumer-facing hover state, no raw key-press seam, and no
Home/End/PageUp/PageDown or type-ahead navigation.

The other structural issue here is architectural: gesture machinery exists in
**four independent implementations** that share almost nothing.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| Assistive-technology bridge (VoiceOver / TalkBack) | **Missing** | Nothing. Confirmed by whole-repository search, 2026-08-13. The bar this is measured against is SwiftUI's accessibility surface, whose own framing is to try the app "with accessibility features like VoiceOver, Voice Control, and Switch Control" ([SW-81]) | — |
| Focus system (`@FocusState` ([SW-85]), `.focusSection` ([SW-86]), Tab order) | **Covered** — and wider than the model it copies: Apple ships `focusSection()` on **macOS and tvOS only** ([SW-86]), while LuauUI's grouped scopes are the same everywhere | `LuauUI.newFocusGraph`: flat and grouped scopes, per-group axis/wrap/entry/exit, directional navigation, and Tab/Shift+Tab traversal in true document order | `src/focus/focus_graph.luau:41-51,99,657-675`; `src/init.luau:294` |
| Four-input + device-idiom conformance proof | **Covered** | **15 of 15** interactive controls prove reachability on mouse, touch, keyboard, and gamepad *and* prove the device-idiom axis, across 42 registered rows | `tests/conformance/controls_registry.luau`; `tools/lune/check_registration_cli` |
| `.sensoryFeedback` — feedback tied to state changes ([SW-70]) | **Covered** (new, 2026-08-13) | `UI.sensoryFeedback(bp, { trigger, event })`: when the `trigger` Readable changes, `{ type = event, path }` is emitted on the presenter's feedback bus. The taxonomy is **closed**, so an unregistered `event` name is an authoring error listing the twelve valid ones. **LuauUI still plays nothing.** SwiftUI's modifier does play, but not everywhere: its feedback cases are documented as playing "on iOS and watchOS" only ([SW-71]), so "the verbs are published, the playback is someone else's problem" is a narrower divergence than it sounds. Detail in §7.1 | `src/blueprint.luau:1160`; `src/present/feedback.luau:32-45,95-101,149-156`; `src/mount.luau:554-559`; `tests/sensory_feedback.spec.luau` |
| Haptics playback | **Partial** — opt-in, default off, three device rows unprovable here | `src/client/haptics.luau`, an opt-in client adapter over `HapticEffect`. §7.1 | `src/client/haptics.luau`; `tests/haptics.spec.luau` |
| Gesture value type (normalized `Gesture`) | **Partial** — real primitive, zero consumers | Kind, state, positions, translation, velocity, scale, rotation; all six gesture kinds connected; publicly exported. No control calls it | `src/input/touch_gestures.luau:20,32-43,139-172`; `src/init.luau:220` |
| Gesture composition (`.simultaneously` ([SW-92]), `.sequenced` ([SW-93]), `.exclusively` ([SW-94])) | **Partial** | A ranked single-owner arbiter (pinch/rotate > pan > long-press > tap/swipe) with a begin/change/end ownership lifecycle. No simultaneous delivery and no chaining. Same "no consumers" caveat as above | `touch_gestures.newArbiter()` |
| `DragGesture` → general drag & drop ([SW-95], [SW-96]) | **Partial**, materially deeper than SwiftUI's | Public `UI.draggable`/`UI.dropTarget` with a typed payload, tap-to-arm, per-input-class promotion thresholds. Three acquisition paths — Roblox's native `UIDragDetector`, a pointer-capture fallback, and a non-pointer arm→navigate→commit flow for keyboard and gamepad — funnel into **one** shared session lifecycle. Two facts about the other side: `draggable(_:)` is not offered on tvOS or watchOS at all, and the `dropDestination(for:action:isTargeted:)` overload was deprecated in the 27.0 releases in favour of a session-based one ([SW-95], [SW-96]) | `src/input/drag_contract.luau:34-37,60-66,101-105`; `src/input/drag_registry.luau:10-15`; [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 5 |
| Detecting and adapting to which device is in use | **Covered** | Per-class promotion thresholds; live hot-switching proven mid-gesture (a user who starts with a mouse and continues with touch is handled explicitly, not accidentally) | `src/input/interaction_tokens.luau` |
| Keyboard modifier chords ([SW-97]) | **Partial** | `action.bind` accepts `modifiers = { shift = true }` and the real-engine realization compiles that into two engine bindings (left and right Shift as `PrimaryModifier`). **Shift is the only *bindable* modifier.** Ctrl and Cmd/Meta are separately *trackable* — `system.modifiers()` exposes them collapsed into one `toggle` boolean, which is how `Table`'s Cmd/Ctrl-click works — but they are deliberately not accepted as bind flags, because a `ctrl` flag there would type-check and never fire. Alt/Option is untracked entirely. SwiftUI's own `EventModifiers` set is `capsLock`, `command`, `control`, `numericPad`, `option` and `shift` ([SW-97]), so this is a real narrowing rather than a difference of vocabulary | `src/input/actions.luau:79-88,102,271`; `src/client/roblox_input.luau:23-33` |
| `.keyboardType(_:)` — which soft keyboard a field raises ([SW-135]) | **Partial** — declared everywhere, honoured nowhere yet | `TextField.keyboardType` is a real closed-enum prop — `default | numeric | email | phone` — validated at construction, carried on the binding authority, and mapped by the adapter onto the closest `Enum.TextInputType` member by name. It is **capability-detected and currently inert**: `TextBox.TextInputType` is not writable from a LocalScript in the shipped engine, so the adapter records the intent and skips the write; the day the engine opens it, the flag flips and every declaration already in the tree starts working with no consumer edit. Apple's is narrower than its name suggests too — `keyboardType(_:)` has **no macOS and no watchOS availability at all** ([SW-135]) | `src/controls/text_input.luau:51-60,143,170-171,600,628-631`; `src/blueprint_schema.luau:1799`; `src/client/screen_target.luau:1038-1056,4455` |
| `accessibilityReduceTransparency` — the player asked for opaque backgrounds ([SW-136]) | **Partial** — the preference is read and published; nothing acts on it | Roblox surfaces the setting as `GuiService.PreferredTransparency`, a 0–1 scalar where 1 is the default and 0 means the player wants fully opaque backgrounds. LuauUI reads it into the `preferredTransparency` environment fact and derives `effectiveTransparency`, which clamps a garbage or NaN reading to the legal domain instead of propagating it. So the accessibility *signal* is first-class and fault-tested. The *response* is not: **no shipped paint path consults the key** — no theme, no gradient alpha cap, no scrim reads it — so a player who turns the setting down today sees no change in a LuauUI surface. Apple's is a boolean and its documented meaning is the same intent: “If this property’s value is true, UI (mainly window) backgrounds should not be semi-transparent; they should be opaque.” ([SW-136]) This is the one accessibility preference LuauUI reads and does not honour — Reduce Motion and Preferred Text Size are both honoured (§6, §8) | `src/env/environment.luau:79,147-153`; `src/client/roblox_env.luau:148`; `tests/lib/fault_scenarios.luau:364-367`; zero consumers in `src/` |
| `.onSubmit(of:_:)` — the player pressed Return in a field ([SW-137]) | **Composable**, and the recipe is one line | `TextField.onFocusLost(reason)` is called with `reason ∈ enter | focusLost | cancel`, so `if reason == "enter" then submit() end` is submit-on-Return. What is not there is SwiftUI's *scoping* half: Apple's modifier may be set “on an individual view or an entire view hierarchy” and filtered by submit trigger ([SW-137]), and LuauUI has no ancestor-level submit channel and no trigger taxonomy — a form with six fields wires six callbacks. Recorded here so the reachable half is not re-filed as a gap | `src/blueprint_schema.luau:1818-1822`; `src/controls/text_input.luau` |
| `.disabled(_:)` — one modifier disables a whole subtree ([SW-142]) | **Missing** — a named gap, examined and deliberately not taken 2026-08-13 | LuauUI has per-control `enabled` on exactly three leaves — `Button`, `Toggle`, `TextField` — and it is consistent across focus, activation, paint and semantics on each of them. What there is no spelling for is Apple's cascade: “The higher views in a view hierarchy can override the value you set on this view” ([SW-142]), so an outer `disabled(true)` wins over an inner `disabled(false)`. The engine has the leaf substrate (`GuiObject.Interactable`), and `active` is unrelated — it is the input-sinking flag a modal backdrop uses. **Why it was examined and left**: unlike `hidden`, there is no existing set to merge into. A disabled subtree has to reach three independent readers of `props.enabled` (the focus map's `isDisabled`, the renderer's drag-source gate, the renderer's tap gate), and then needs a *paint* answer for the classes that have no disabled look at all — a `Box`, a `Text`, an `Image` inside a locked panel. That is a cascading channel plus a theme vocabulary, which is a mission rather than a prop, and shipping the channel without the paint would give consumers a subtree that is inert and looks live | three readers of `props.enabled`: `src/present/focus_map.luau:30`, `src/render/renderer.luau` (drag-source gate, tap gate); [`the completeness audit`](../plans/parity-completeness-audit-2026-08-13.md) §5 row 9 |
| `.onKeyPress` — raw key seam ([SW-87]) | **Missing** | No raw key event surface. Apple's is hardware-keyboard-and-focus scoped and fires for key-down and key-repeat ([SW-87]) | — |
| Home / End / PageUp / PageDown / type-ahead | **Missing** | Confirmed by keycode grep | — |
| Escape to dismiss a modal | **Partial** — an engine constraint | The Escape key is permanently reserved by Roblox for the CoreGui menu and cannot be intercepted. Cancel is bindable on gamepad ButtonB; keyboard and mouse users close a modal via whatever the screen provides. A keyboard-only user has no framework-level dismiss | `src/present/presenter.luau:2796,2800`; `src/client/screen_target.luau:2844` |
| `GuiService.SelectedObject` mirror (engine selection bridge) | **Partial**, experimental | Ships opt-in and non-screen-only: `presentModal({ engineSelectionBridge = true })`, gated so passive surfaces never opt in, with explicit `Selectable` restore when selection moves off. **This does not touch VoiceOver or TalkBack** — it drives Roblox's own gamepad selection cursor, nothing more. Gated behind a physical-device check before it is treated as stable | `src/present/presenter.luau:81,194,2089`; supersedes the risk framing in [`ADR-0014`](../adr/ADR-0014-first-responder.md), which still describes driving engine selection as an unexplored risk. It is not: the investigation that record asked for was carried out (2026-07-23) and its result is this shipped, opt-in bridge. The record was simply never rewritten |
| Dynamic Type / preferred text size | **Partial** | See §6 — the mechanism is thorough; the physical-phone-at-Largest check and the subjective-feel check are still owed | — |
| `.accessibilityAction` — custom accessibility actions ([SW-83]) | **Missing** | Nothing. Apple's exists so that "assistive technologies, such as the VoiceOver, [can] interact with the view by invoking the action" ([SW-83]) — which is the layer LuauUI has none of | — |
| A control's accessibility description (`accessibilityLabel`, [SW-82]) | **Partial** — prose only | Every control declares an `accessibility` string on its control contract (§1), but it is typed as a human-readable summary and the only consumer asserts it is non-empty. It reaches no platform API and no assistive technology | `src/controls/contract.luau:21`; `tests/controls_conformance.spec.luau:141` |
| `.onHover` / `isHovered` ([SW-88]) | **Missing** as a consumer surface — and note Apple's is itself pointer-platform-scoped, absent from tvOS and watchOS ([SW-88]) | Hover exists but is framework-internal: an automatic, pointer-gated chrome effect. One narrow dwell-based seam exists for a single feature (revealing truncated text) | `src/render/target_contract.luau` |
| `.pointerStyle` — cursor shape ([SW-89]) | **Partial** — seam live, no art. The comparison is narrower than the row name suggests: Apple's `pointerStyle(_:)` is **macOS 15 and visionOS 2 only**, with no iOS or iPadOS availability at all ([SW-89]) | A `cursorHint` prop exists on `UI.Grip` only (the property-authority table restricts it to that class), and the cursor-art table is empty, so every hint falls back to the default arrow | `src/render/authority.luau:146`; `src/client/screen_target.luau:689` |
| Right-to-left / bidirectional layout and text ([SW-90], [SW-91]) | **Missing** | Nothing mirrors layout or reorders text runs. The presenter says so in its own source. The only `rtl` token in the codebase is an unrelated **progress-bar fill direction** for chrome recipes — do not mistake it for RTL support. The bar: Apple's frameworks "support right-to-left (RTL) by default, allowing system-provided UI components to flip automatically" ([SW-91]), with `layoutDirection` as the environment switch ([SW-90]) | `src/present/presenter.luau:1494`; `src/tokens/chrome_slots.luau:1638` |

### 7.1 `sensoryFeedback` and the haptics adapter

**`sensoryFeedback` is a semantic bus event, and LuauUI plays nothing.** That is
the whole design and it did not change this round; what changed is that the
emission is now a first-class blueprint modifier instead of something the
consumer wired by hand.

The taxonomy is **closed and versioned** — twelve verbs, frozen at
`src/present/feedback.luau:32-45`:

`activate`, `select`, `adjust`, `pickup`, `commit`, `reject`, `cancel`,
`arrive`, `land`, `dismiss`, `supersede`, `celebrate`.

Events fire synchronously on the frame that caused them, with subscriber errors
quarantined. The bus is live-consumed in production
(`games/RascalRally/code/src/client/LuauUISponsor/PlayFlow.luau`).

**One opt-in client adapter maps verbs to Roblox haptics, default off**
(`src/client/haptics.luau:196`). Its design is worth reading before assuming
anything about it:

- It uses **`HapticEffect`**, not `HapticService:SetMotor`. Roblox's own class
  reference says `SetMotor` is superseded, and its value range, persistence and
  zeroing requirement are undocumented — a motor you cannot prove stops is a
  stuck-rumble bug you cannot write a test for.
- The `activate` verb takes a **property route**: `GuiButton.PressHapticEffect`
  is assigned a reference and the **engine** fires it. The adapter never calls
  `Play()` for it, which keeps "LuauUI plays nothing" literally rather than
  nearly true. A test pins that exactly one `:Play()` call site exists in the
  whole module.
- **Five of the twelve verbs map to nothing from the bus, deliberately**:
  `activate` (the engine fires it through the property above), `arrive` (fires on
  every chase settle — a haptic there is per-frame noise), `cancel` (the
  *absence* of feedback is the signal for "nothing happened"), and `dismiss` and
  `supersede` (not player-caused; buzzing at a self-retiring toast is a phantom).
  The map is asserted **total** over the taxonomy, explicit "no" included, so a
  future taxonomy addition shows up as a visible gap instead of a silent drop.
- `adjust` is **rate-limited** (sliders and steppers fire per tick; unthrottled
  that is a buzzsaw that also blows the documented simultaneous-effect budget),
  and effects are **pooled**, one per mapped verb, never constructed per fire.
- The capability probe is a **lattice**, not a boolean:
  `supported | unsupported | unknown | blocked | absent`, with **`unknown` the
  default for touch and for the pre-first-gamepad state**, re-probed on
  `GamepadConnected` / `GamepadDisconnected` / `LastInputTypeChanged` rather than
  cached at boot. The only probe the platform offers belongs to the superseded
  service and is boolean, which is exactly the shape that lies: `false` means
  both "no motor" and "no gamepad connected *yet*".
- A grep test asserts no haptics symbol is reachable from `src/present/`,
  `src/layout/`, or the shared entry point — the adapter cannot leak into the
  solver or a server path.

**Evidence, split honestly.** Headless proves default-off costs zero
constructions and zero plays, mapping totality, `adjust` coalescing under a fake
clock, the probe returning `unknown` rather than `false` for touch, re-probe on
device change, and pool bounds (`tests/haptics.spec.luau`). **This machine cannot
produce positive evidence** — Roblox documents controllers on macOS 15+ as
unsupported — so three rows are `PENDING_PHYSICAL` and only a device closes them
(§14).

**Caveats.**

- **Gesture machinery is fragmented four ways**: the touch-gesture arbiter (which
  nothing consumes), the general drag contract, row actions' own pointer-capture
  and axis-lock, and `Table`'s hand-rolled vertical reorder drag. The count is
  still four; what has changed is that a thin arbitration layer
  (`row_actions.composeWithReorder`) now sits between two of them and they share
  the axis-lock constant. The underlying gesture state and math are still
  duplicated.
- Six physical-device checks are owed by row swipe actions and three more by
  haptics (§14).

---

## 8. Motion

LuauUI's motion system is authoritative and opinionated. Springs are declared
with SwiftUI's two-number model — Apple spells the second number `dampingFraction`
on `Animation.spring` ([SW-98]) and `dampingRatio` on its `Spring` type ([SW-99]),
and this document said "damping ratio" for both until 2026-08-13 — and never with
mass and stiffness, which SwiftUI *does* also offer, through
`interpolatingSpring(mass:stiffness:damping:initialVelocity:)` ([SW-100]); the
refusal is LuauUI's design choice, not a gap in Apple's. An inline spring literal
at a call site is a **hard error** that
names the registration function — springs must come from one of four registered
classes, so the design system cannot drift one call site at a time. Retargeting a
spring mid-flight never touches its current value or velocity, so a spring
interrupted by a new target continues rather than jumping; a differential test
proves it, by showing a velocity-cut twin travels measurably less on the next
frame.

**The large gap here closed this round.** `withAnimation` ships.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `withAnimation` — implicit write⇄interpolation coupling | **Covered** for position; see the detail below | `presenter.withAnimation(class, fn)` | `src/present/presenter.luau:3942`; `tests/with_animation.spec.luau`; `tests/animation_precedence.spec.luau`; `examples/gallery/scenarios/with_animation.luau` |
| `.spring(response:dampingFraction:)` ([SW-98]) | **Covered** | The same two-number model. Four named classes ship — `container`, `object`, `reward`, `decay` — and inline literals are refused with a did-you-mean | `src/motion/classes.luau:14-19,45-50,154-172` |
| Spring interruption / retargeting ([SW-100]) | **Covered** — the same guarantee Apple states for `interpolatingSpring`, which "Preserves velocity across overlapping animations" ([SW-100]) | `setTarget` never touches value or velocity, and `getVelocity()` makes carry-over implementable rather than aspirational | `src/motion/motion.luau:306-341,405-407` |
| Animation completion callbacks ([SW-101]) | **Covered**, callback-based | `MotionValue:onSettle(fn)` fires exactly once per arrival, after that frame's writes commit — the same once-only contract SwiftUI states for its completion variant ([SW-101]). No awaitable form | `src/motion/motion.luau:363-375` |
| `phaseAnimator` — effects over a sequence of phases driven by a trigger ([SW-102]) | **Missing** | No looping or state-driven phase construct | zero occurrences |
| `keyframeAnimator` / `KeyframeTimeline` — "a description of how a value changes over time" ([SW-103]) | **Partial**, via a different shape | `clock:timeline(spec)` is beat-sequenced choreography with `interrupt()` and `skip()`. Each beat is a callback, not a per-property value track with its own curve, and a timeline never loops | `src/motion/clock.luau:298-300` |
| `.transition(.insertion/.removal)` ([SW-104]) | **Covered** — general, reusable | `UI.ForEach{transition}` and `UI.When` share one structural-region property. Forms: `fade`, `slide-up`, `slide-down`, `slide-left`, `slide-right`, `materialize`, `instant`. A removed row **retires in place** — it stays mounted at its clamped slot, non-interactive, and disposes on exit-complete — rather than vanishing. Hard 500 ms exit cap | `src/render/transitions.luau:44,48-57`; [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 3 |
| `matchedGeometryEffect` — shared-element / hero transitions ([SW-105]) | **Missing** | No cross-tree geometry interpolation. `withAnimation` animates *surviving* paths inside one commit; it does not carry identity across two layout trees | zero occurrences |
| `.scrollTransition` ([SW-106]) | **Missing** | No API ties paint to a node's live proximity to the viewport edge — Apple's animates "as this view appears and disappears within the visible region of the containing scroll view" ([SW-106]) | zero occurrences |
| Reduce Motion ([SW-84]) | **Covered** — information-preserving, not a switch | The OS signal is read live on every retarget, not snapshotted at boot. Motion is categorized: *decorative* motion snaps instantly but still fires `onSettle`, so completion logic is unaffected; *informational* motion (a count-up whose number is the message, or the indeterminate spinner of §5) keeps running to the same terminus but quantizes its writes to a 250 ms step, so the information survives while the animation stops being animation | `src/motion/motion.luau:34-42,58` |
| `.numericText` / animated numerals ([SW-107]) | **Covered**, plus more | `clock:counter` publishes whole numbers only and never overshoots its target. On top of it, `motion.newValueReveal` composes a hold/count/land layer under two rules — never state a new value before its moment, never withdraw a stated one. SwiftUI's `numericText` transition is the numeral half only ([SW-107]); there is no single built-in for the hold/count/land layer ([SW-10]) | `src/motion/clock.luau:274-277`; `src/init.luau:258-260` |
| Countdown / depleting timer | **Covered** | `clock:timer(spec)` advances on raw wall-clock delta, not frame-clamped time, so a frame spike cannot stretch a countdown | `src/motion/clock.luau:279-282` |
| Gesture → animation velocity hand-off | **Covered** | A 100 ms rolling-window velocity tracker feeds both a general drag flight (seed velocity, then chase a live target) and row-actions flick momentum (read the tracker at release, seed the persistent spring) | `src/input/drag_velocity.luau` |
| "Arrive at a live, moving target" in 2-D | **Covered** — no single SwiftUI API ([SW-10]) | `clock:chase(opts)`: two scalar springs against a target re-read every frame, firing `onArrive` once the value enters a *perceptual* arrival radius (4 px by default) rather than waiting for physics settle epsilon — which the framework measured as trailing perceived landing by about 0.7 s | `src/motion/chase.luau:23` |
| `.sensoryFeedback` | **No host equivalent by design** | See §7.1 — the verbs are published, the playback is the game's | `src/present/feedback.luau` |

### 8.1 `withAnimation`, precisely

`presenter.withAnimation("container", function() open:set(true) end)` — **the
layout lands exactly and instantly as it always did, and every node whose box
moved is *painted* travelling from where it used to be to where it now is, over
one spring.**

- **It is a presenter method, not `UI.withAnimation`.** The constitution reserves
  `UI.lowerCase(bp, …)` for modifiers, which take a blueprint and return a frozen
  one; this takes no blueprint. It lives on the presenter because the presenter
  is the only thing that owns all three collaborators — the motion clock it
  builds, the controller scopes that own the records, and `refresh` itself.
- **The class is a NAME.** Inline `{ dampingRatio = … }` is refused here as
  everywhere else; `motion.registerClass` is the one dial.
- **Position only.** Size changes land instantly and exactly. Size was
  deliberately not animated this round: the write path (`applyRect`) also drives
  the hit expander, the focus-ring float, icon refitting and Path2D control
  points, and an interpolated size would re-run all four every frame of the
  flight — while a wrapped `TextLabel` re-wraps mid-flight and clip hosts and
  canvas groups crop rather than follow. A row that grows still reads correctly,
  because the rows below it slide.
- **Surviving paths only.** Structural insert and remove stay the transition
  system's job. A path another writer already owns — a structural transition,
  keep-visible — is excluded, and **the exclusion is the path, not its subtree**:
  the whole-subtree form shipped first and was a silent, permanent no-op on any
  surface holding a `UI.TextInput`, because every text field declares a
  keep-visible offset that writes a zero transform onto the *root* at boot.
- **Only `fn`'s consequences.** The presenter drains pending work *before*
  arming, so an unrelated discrete change that fired two milliseconds earlier
  does not animate at full delta. Env-driven relayouts — theme swap, viewport
  resize, preferred-text change — are never armed; animating a whole-tree theme
  relayout is a frame-budget accident, not a feature.
- **Records are relative and installed only at animation roots.** Both halves of
  the presentation channel already accumulate ancestor transforms, so an absolute
  per-node delta would paint a panel's children at two and three times its
  travel. One shared progress spring per call means a subtree provably cannot
  tear; records are owned per **path**, so a second call touching a path the
  first is still animating re-bases it rather than putting two springs on one
  slot.
- **Three refusals**, and one is late: nesting inside another `withAnimation`
  (arming is presenter-wide, so the inner call's disarm would silently kill the
  outer animation); an unknown class name; and "nothing flushed", which means
  either an outer `core:transaction` is still open **or** this ran during a core
  commit. That last one raises **after `fn` has already been applied**, so a
  caller catching it must not retry the mutation or it lands twice. The message
  says so.
- **Reduced motion is an explicit branch that installs no records at all.** `fn`
  still runs, the transaction still commits, the layout is still exact; there is
  simply no flight. That is legal precisely because this motion is **decorative**
  — the instant layout already carries every fact and the travel was pure
  continuity.
- **Not reachable from inside a control.** Controls receive the presenter's
  *products* through contributions, never the presenter itself, so
  `row_actions`, `table` and `disclosure_group` cannot animate their own internal
  state through this API. That matches SwiftUI, where `withAnimation` is called
  at the mutation site and takes the mutation itself ([SW-05]). The named escape hatch if it proves too tight is a
  `presenter.animator()` handle — **not built**, and confirmed absent from source.

**One drift to close.** `docs/reference/api.md` states that beyond a per-frame
cap the commit lands instantly and emits a diagnostic naming the count. **No such
cap is implemented** — `animationRecordCount()` exists as a test diagnostic and
nothing bounds it (`src/render/renderer.luau:3941-4061`, `:4086`). This document
does not repeat the claim; the reference entry needs correcting or the cap needs
building, and that is a follow-on, not something this report changed.

**Caveats.**

- Row swipe actions' collapse animation builds its **own second spring** rather
  than going through the general `ForEach` transition primitive. It works, but it
  is a duplicate mechanism a future generalization should unify.

---

## 9. Presentation & navigation

LuauUI presents *surfaces*: screens, modals, popovers, toasts, and a couple of
presenter-private surfaces. That stack is well specified — closed, validated
option sets rather than free-form tables; focus trapped and restored per surface;
named display-order bands rather than one running counter; theme-derived rather
than hardcoded dismissal geometry.

What it does not have is **navigation**. There is no push/pop screen model, no
`NavigationPath`, no back button, no titles, no deep-link or state-restoration
surface. A consumer swaps blueprints under a single `present()` call by hand.
That is the largest structural gap in this area.

One capability here is worth calling out because it generalizes: a control can
put a *floating* surface on screen — one that renders above everything and
contributes **zero** to any ancestor's measured size. That seam is `bindPresent`,
and it exists because the first version of the row-actions menu measured as a
child of its row, silently inflating the row and, inside a table, the whole list.
A pinned test now asserts a sibling row's solved rectangle is byte-identical
whether the menu is open or closed.

**One term used throughout this section: priority band.** Input in LuauUI is
routed by numeric priority, and every surface is assigned a band of priority
numbers when it is presented — modals get a base band, each stacked depth above
it gets a fixed increment. The band decides who receives an input first, so two
surfaces sharing one band is a bug, not a tie-break: both would receive the same
event. (Separately, coarse *display-order* bands decide what paints on top of
what — see the layering row below.)

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `.sheet` — modal presentation ([SW-108]) | **Partial** | `presenter.presentModal` with a focus trap and per-depth priority banding. Named, validated options: `cancelPolicy`, `scrim`, `outsideTapCancel` swallow semantics, `initialFocus` | `src/present/presenter.luau:3596` |
| `.interactiveDismissDisabled` / tap-outside behavior ([SW-109]) | **Covered** internally, no public mirror | The dismissal geometry is forgiving by design: the "inside" region is the painted panel plus a forgiveness ring, unioned with each focusable's minimum hit rectangle, so a near-miss on a control does not dismiss the modal. Both distances are **theme metric roles** (`space.l`, `targetSizes.minimum` — 24 px and 44 px under Studio Neutral), not magic numbers. No public property mirrors `.interactiveDismissDisabled` | `src/present/modal_zones.luau:57-96` |
| `.fullScreenCover` ([SW-110]) | **Composable** | `presentModal` + an edge-to-edge root policy + a full-bleed root blueprint. Apple's own is platform-scoped in a way the name hides — iOS, tvOS and watchOS, **not macOS** ([SW-110]) | — |
| `.alert` / `.confirmationDialog` ([SW-111], [SW-113]) | **Composable** | Recipes only. **No item-binding sugar** — SwiftUI's item-driven alert has no analogue; a consumer wires its own signal. Name that carefully: the live symbol is `alert(_:item:actions:)` ([SW-111]), and the `alert(item:content:)` this document used to name was **deprecated in the 27.0 releases** ([SW-112]), so the pattern is current and the old spelling is not. Nothing here orders or tints a Cancel row automatically, and SwiftUI does both — "The system may reorder the buttons based on their role and prominence", and a `cancel`-role button replaces the default dismiss action ([SW-113]) | — |
| `.popover` / transient panel ([SW-114]) | **Partial** | `newPopupButton` plus a presenter-managed tap-away catcher. The catcher supports a non-consuming mode, so a tap-away can close the popup *and* still reach the control underneath. Adaptation is the divergence worth knowing: on iPhone, SwiftUI's popovers adapt into sheets ([SW-114]); LuauUI's presentation choice is `resolvePresentation`'s, made from option count, size class and live input | `presenter.syncPopupCatcher` |
| `.swipeActions` / `.contextMenu` as a secondary-action container ([SW-37], [SW-50]) | **Partial** | `LuauUI.newRowActions` — a real construct, not a recipe, with the gaps named in §5.1 and no `contextMenu` trigger (§5.2) | `src/controls/row_actions.luau` |
| Floating surface that contributes nothing to its ancestor's layout | **Covered** — architecturally significant, no SwiftUI-named equivalent ([SW-10]) | `bindPresent`, part of the input contribution seam (§1). Deliberately routes through `presentModal`, never `present`: two screen-kind surfaces would share one priority band, so each would receive the same input twice. (Navigate, Activate and Cancel here are semantic *input actions* the presenter routes to whichever surface owns the band — an entirely separate vocabulary from the 12 feedback verbs in §7.1, which are outbound notifications and route to nothing) | `src/input/contribution.luau`; `src/present/presenter.luau:2365-2366` |
| `ButtonRole` (destructive / cancel) ([SW-115], [SW-116]) | **Partial** | `role: "normal" \| "destructive"` on an action paints the shipped danger style. No `cancel` role, and no automatic dialog-row ordering — which SwiftUI does have, though it is documented on the dialog rather than on the role ([SW-113]) | — |
| `NavigationStack` ([SW-117]) / `NavigationPath` ([SW-118]) — screen push/pop | **Partial** at best | Only surface stacking: `presentModal` pushes, `back()` pops the top *modal*, `depth()` reports the stack size. There are exactly two surface kinds, `"screen"` and `"modal"`. No `pushScreen`, no `navigationPath`, no `screenStack` construct exists anywhere in source | `src/present/presenter.luau:3596,3759,4361`; confirmed by source search 2026-08-13 |
| `NavigationSplitView` ([SW-69]) / `.inspector` ([SW-119]) / scene management | **Missing** | Zero occurrences | — |
| `.presentationDetents` — snap-to-fraction sheet heights ([SW-120]) | **Missing** | A modal's size is whatever its blueprint measures to. Apple's detents are not the phone-only feature they are often taken for — iOS 16 **and** macOS 13 up ([SW-120]). Building detents would need canvas-height-aware drag physics that do not exist; the closest primitive, `Grip`, is a 1-D value adjuster, not a sheet-height controller | zero occurrences |
| Toast / transient feedback surface | **Covered** — no SwiftUI built-in ([SW-10]) | `presenter.presentToast`, with pure headless scheduling: max 3 visible, queue cap 8, priority-ordered FIFO, typed dismiss reasons ("nothing may vanish untraceably"), reduced-motion parity, and input-transparent by construction | `src/present/presenter.luau:4246`; `src/present/toast_schedule.luau:18,39-40` (351 lines) |
| Semantic feedback bus | **Covered** | `presenter.onFeedback`/`emitFeedback` over the closed 12-verb taxonomy, wired into surface lifecycle and toast supersession, and now authorable per node via `UI.sensoryFeedback` (§7.1). LuauUI still plays nothing | `src/present/feedback.luau` |
| Focus trap and restore | **Covered** | Scope push/pop/remove on the focus graph, used by modals and transient popups alike. Row actions' floating menu reusing it unchanged is evidence the mechanism generalizes beyond its original proving ground | `src/focus/focus_graph.luau` |
| Passive (non-capturing) surfaces | **Covered** | `responder = "passive"` plus explicit `engage()`/`resign()`, so a surface can sit over a live 3D world without stealing its input | [`ADR-0014`](../adr/ADR-0014-first-responder.md) |
| Display-order layering | **Covered** | **Four** named `SURFACE_LAYER` bands with an explicit guarantee — `base` (10000) < `toast` (20000) < `dragProxy` (30000) < `modal` (40000) — rather than one incrementing counter. A scrim or tap-away catcher is a fifth *conceptual* layer but is positioned relative to its owner rather than given a band of its own; `api.md`'s "five-layer surface order" phrasing names only these four and should be read that way | `src/present/presenter.luau:387-393,721,724` |
| Full-value disclosure plate; auto-reveal marquee | **Covered** — no SwiftUI equivalent ([SW-10]) | `presenter.disclosure()` shows a truncated value in full on a presenter-private surface with no focus scope and no input context; `presenter.reveal()`/`movingText()` animates long text into view | `src/present/presenter.luau:1470,1858,1885` |
| Surface enter/exit transitions | **Covered** | `opts.transition` on `present`/`presentModal`; `dismiss` defers teardown to the exit coordinator under a flat 500 ms cap | [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 3 |
| Keyboard-only modal dismissal | **Partial** — engine constraint | Gamepad ButtonB is bound to Cancel; Escape is not bindable (§7) | — |

---

## 10. Performance

LuauUI has serious performance instrumentation: **20** named production-shaped
workloads in a self-contained lab place, p50/p95/p99 headless timing, live heap
and reactive-graph counters, a *fixed* set of **12** closed MicroProfiler phase
scopes (the scope count does not grow with row count), and — the most durable piece —
regression budgets encoded as **ratio tests rather than wall-clock thresholds**.
Those five rules (work scales with what changed; a cache key must cover what it
caches; nothing unchanged gets rebuilt; an unchanged value fires nothing; the
cheap path stays cheap) are each annotated with the real historical regression
that motivated them, so they cannot be quietly deleted as flaky.

Real instance-cost wins have shipped and been measured: instance recycling,
theme-aware recycling, incremental layout (141→8 arranged nodes, ~17×), eliding
inert containers (137→91 instances, −34%), and lazy `UIScale` (about −10%
instances framework-wide). This round added two more measured results and both
were reported honestly rather than flattered: the placement audit and the shrink
pass each landed **inside the same-arm noise floor** on an interleaved
20-scene × 5-profile suite, and the `containerRelativeFrame` cache-key widening
was measured at **+14 %/+19 %/+23 %** p95 on three scroll scenes when applied
unconditionally, which is why the container term joins the key only once a
container-relative dimension has actually been measured (conditioned: +0.8 % /
+1.5 % / +2.4 %, inside noise).

**The unavoidable caveat: none of this has ever run on a physical device.**

| Capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| Named, production-shaped workloads | **Covered** | **20** scenes, each with its own budget entry: `hud-binding-storm`, `settings-churn`, `scroll-focus-traversal`, `collection-mutation`, `animation-interruption`, `locale-textsize-change`, `async-image-burst`, `shadow-storm`, `virtual-list-scroll`, `native-scroll-drag`, `dense-hud`, `stylesheet-state-churn`, `async-image-grid`, `screen-lifecycle-churn`, `theme-swap-flat`, `theme-swap-metrics`, `theme-swap-assets`, `dense-motion`, `lab-dense-scroll`, `lab-collection-churn`. (The previous revision of this document listed nine scenes under names that do not exist in the source — corrected here) | `bench/perf_scenes.luau`; `bench/perf_budgets.json` (20 keys); `examples/performance/lab/perf_lab.luau` |
| Percentile timing | **Covered** | p50/p95/p99, headless | `bench/perf_runner.luau`; `tools/perf.sh` |
| Regression budgets as executable tests | **Covered** — stronger than a wall-clock gate | Five invariant/ratio rules, each tied to the regression it once caught | `bench/perf_budgets.json`; `tests/perf_principles.spec.luau` |
| Heap / reactive counters | **Covered** | `handle.controller.stats()` reports property writes, rect writes, creates, removes, arranged and skipped counts; a lifecycle census counts GuiObjects, signals, memos, and scopes, proven zero-drift across 8 identical mount/unmount cycles | — |
| Profiler phase attribution | **Covered** | **12** closed scopes, capped by `profile.MAX_SCOPES = 12` and asserted by a test: `mutate`, `react`, `measure`, `arrange`, `commit`, `resource`, `mount`, `scenario`, `reset`, `present`, `focusmap`, `tick`. (Nine was the count before `present`/`focusmap`/`tick` were added on 2026-08-05 — the source comment at `:70` says so, and the previous revision of this document had not caught up) | `src/core/profile.luau:51-90`; `tests/profile_scopes.spec.luau:76` |
| Per-property invalidation granularity vs SwiftUI ([SW-04]) | **Covered**, with one counterexample | A single bound-value change costs the same at 100, 800, and 3200 rows — work scales with what changed, not with what exists, enforced as a ratio test. Incremental layout narrows that change from a full-tree re-solve to its relayout boundary (~17× measured). The counterexample is the next row | `tests/perf_principles.spec.luau`; `tests/incremental_layout.spec.luau` |
| Cell recycling for composite-wrapped rows | **Missing**, and no longer the lever it was | `VirtualList` still has no cell-recycling seam: crossing the window boundary destroys and recreates a row's structure, which is coarser than SwiftUI's lazy containers, which "create items only as needed" ([SW-21], [SW-31]). The previous revision said it was coarser than "SwiftUI's `List`/`LazyVStack` reusing cell identity", and that is withdrawn: **Apple documents no view reuse or recycling for `List` or the lazy stacks anywhere** ([SW-34]) — reuse was our inference from behaviour, not a documented contract to be measured against. What changed is that the feature which made this hurt no longer needs it — hosted row actions mount **nothing** on a closed row, so the +57 %/+81 % cost is gone without recycling (§5.1). Generic cell recycling was explicitly weighed and **not chosen**, because recycling never removes wrapper instances from the tree and so could not have met the instance budget on its own | [`row-actions-hosted-mode-design.md`](../plans/row-actions-hosted-mode-design.md) |
| Measurement discipline | **Covered** — no SwiftUI or Xcode analogue ([SW-10]) | Same-arm A/A noise floors are measured and stated *before* any A/B number is reported; arms are interleaved (ABBA), never run in blocks; budgets are called on ≥5-run means. The project has a recorded **false signal** from a non-interleaved A/B taken when the same-arm floor had drifted from 0.31 % to 1.88 % across a session — which is why the rule exists | `docs/plans/swiftui-parity-round2.md` §2.1; `artifacts/row-actions/device-matrix.md` |
| On-device performance measurement | **Missing** | `artifacts/phase-4/perf.json` records `"deviceRun": false`, `"authoritative": false`, `"evidenceLevel": "E1"`. The budget file's `skippedDeviceBudgets` lists `phone-physical`, `desktop-retail`, and `console-physical` as all pending. The full phone-capture procedure is documented in enough detail for an agent to execute — the artifact slot is simply unfilled | `artifacts/phase-4/perf.json`; `bench/perf_budgets.json` |
| Xcode Instruments equivalent | **Partial** — headless only | Headless percentile timing with versioned budgets. No on-device, symbolicated, UI-specific profiler. The Instruments comparison had two versions wrong until 2026-08-13: **Processor Trace and the CPU Counters instrument shipped in Xcode 26** ([SW-121]), not 27. What Xcode 27 added is the Swift Executors instrument — tracks for the cooperative thread pool, the main actor and custom executors — and a Hitches metric that replaces the Organizer's Scrolling metric ([SW-122]). LuauUI has a counterpart to none of them | `tools/perf.sh`, `tools/bench.sh` |

**Caveats.**

- The lab place ships with a build doctor and a scriptable driver, and its
  low-end-Android capture procedure is written so that a Studio row relabeled as
  a phone cannot spoof it. It still has not been run on hardware.
- The swipe-actions perf story is now the project's best procedural example
  rather than its worst outcome: the gate was re-baselined to the measured
  ceiling with the original budget kept on record and a follow-on charter filed —
  not silently passed, not deleted, not converted to a TODO — and the follow-on
  then closed the gap and **restored the original ceiling**.

---

## 11. Tooling & authoring model

This is where LuauUI most clearly optimizes for something SwiftUI does not:
**being maintained by agents as well as humans.** Unknown properties are refused
at construction with a did-you-mean suggestion and the full valid set enumerated.
Exported `*Spec` types describe the public constructor surface. And a family of
checkers reconciles independent views of the same truth so they cannot drift:
one reconciles six views of every declared property (schema, dirty map, render
authority, adapter, layout, docs/types); one verifies every public export is
classified in the surface ledger; one verifies documentation matches the live
export table; one lints the example gallery against the framework's own live
role vocabularies.

What it lacks is the interactive half of Xcode: there is no live, hot-reloading,
resizable in-editor preview, and no compiler-enforced type safety comparable to
Swift 6 — Luau cannot provide it, so LuauUI's answer is a fast, comprehensive
runtime/test-time layer instead.

| SwiftUI / Xcode capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| Strict construction-time validation | **Covered** | `UI.Button({ lable = "hi" })` → *unknown property 'lable'. Did you mean 'label'? Valid properties: …* | `src/blueprint_schema.luau` |
| Typed public constructor surface | **Covered** | **55** exported `*Spec` types across blueprint, controls, motion, layout, drag and transitions. Public core types are re-exported at the boundary; the single `: any` in `src/init.luau` is inside an explanatory comment | `src/init.luau` |
| Property-authority reconciliation | **Covered** — no Xcode analogue | `tools/lune/check_prop_parity.luau` reconciles **six** independent views of every property — dirty classification, render authority, adapter binding, layout consumption, handler wiring, and documentation/types — plus a seventh cross-check restricting binding props by class. It exists because a bound `Text.color` was once silently dropped between two of those views | `tools/lune/check_prop_parity.luau:1-32` |
| Conformance registry | **Covered** | Every control must appear with its proofs; enforced by a test, so a control cannot ship unregistered | `tests/conformance/controls_registry.luau`; `tests/extension_checker.spec.luau` |
| Docs-vs-code drift check | **Covered** | `check_docs.luau` holds documentation to a zero-tolerance list against the live export table, including a stale-phrase list of sentences that were true before a feature shipped | `tools/lune/check_docs.luau` |
| Example-gallery drift lint | **Covered** | Reads its role vocabularies live from the framework; fails on raw numbers for style-owned properties, unknown role strings, raw colors, or reaching around the public API into the engine | `tools/lune/check_example_drift.luau` |
| Public-surface ledger coverage | **Covered** | Every top-level export and nested namespace member must be classified in the surface ledger | `tools/lune/check_surface_ledger.luau` |
| Client/server require-graph boundary check | **Covered** | Verified acyclic and correctly split, source against consumers | `tools/lune/check_boundary.luau` |
| Gate system | **Covered** | **25** named gates, plus an integrity checker that verifies every gate's test grep is anchored to the pass marker (a grep that could never fail is itself a defect), plus automated re-running of prior gates | `tools/lune/gate_manifest.luau`; `tools/check_manifest_integrity.py` |
| Scriptable in-Studio verification | **Covered** | A `LuauUIScenarioAPI` folder of BindableFunctions lets an external driver run scenarios inside a live Studio session | `examples/gallery/scenarios/runner.luau` |
| Deterministic render dumps | **Covered** | Every control exposes a `dump()` seam, required by the scaffold template and the registry, so layout output can be diffed exactly | `tests/conformance/corpus_cli.luau` |
| Runtime diagnostics surface | **Covered** | `controller.diagnostics()` returns a defensive copy of live layout complaints — overflow, unbounded percent, unbounded containers, mixed grid children, and (new this round) inert placement props. Project history records this surface naming a shipped layout defect that a screenshot review had missed | `src/render/renderer.luau`; `docs/lessons/the-solver-already-told-you.md` |
| Reference apps as scale proofs | **Covered** | Five clean-room apps (§12) | `examples/reference/` |
| Extension scaffold and playbooks | **Covered** | `tools/lune/scaffold.luau` stamps a new control's source seam, dump surface, deliberately-failing spec, and registration edits, so a scaffolded control cannot ship silently unregistered. Six playbooks cover new control / engine feature / platform mode / render target / theme / skinned control | `docs/extending/` |
| Deprecation policy | **Covered** | A machine-readable `LuauUI.DEPRECATIONS` ledger; a deprecated surface keeps working for at least one minor version. `newVirtualList`'s `rowHeight`/`viewportHeight` are the current entries, added this round | [`ADR-0011`](../adr/ADR-0011-semver-and-deprecation.md); `src/init.luau` |
| Fuzz / fault / soak testing | **Covered** | Layout, replication, and scheduler fuzzers plus a fault-injection suite | `tests/fuzz_*.spec.luau`, `tests/faults.spec.luau` |
| `#Preview` — live, resizable, hot-reloading in-editor preview | **Missing**, mitigated | No in-editor live preview exists for LuauUI. Mitigated by deterministic dumps, the reference-app corpus, scripted Studio drives, and the showcase place — but all of those are batch, not interactive, where Xcode's previews are "dynamic, interactive" in the canvas ([SW-123]). This row used to say Xcode 27 "added interactive resize handles to Live Previews"; Apple's release notes name no such thing, and the feature that did land is a **Resizable Canvas mode** for iOS previews, "arbitrarily sized containers" ([SW-122]). LuauUI's device matrix is the scripted analogue | — |
| Compiler-enforced type and concurrency safety | **Partial** — runtime-enforced | `--!strict` Luau plus the checkers above plus a 4562-case suite, all running in seconds. It catches misuse at test time, not edit time. Swift 6's strict concurrency is compiler-level — it "helps you find and fix data races at compile time" ([SW-125]) — and Luau cannot match it | — |
| Documentation tooling | **Covered** — a stronger claim than generation | Four checkers now: three make it impossible for documentation, the live export table, and tutorial examples to drift from shipped code without failing a gate, and the fourth (new this round) makes it impossible for a row of §§3–11 to assert something about SwiftUI without citing the Apple page it rests on. DocC "makes it easy to produce rich and engaging developer documentation" ([SW-124]); it does not enforce that documentation is true, and neither does the citation check — what that one enforces is that a claim about the other framework is *checkable* | — |

**Caveats — where the machinery does and does not help.**

The agentic-maintainability claim holds up, and the row-actions branch is its
best evidence: the registration checker caught a missing conformance row *and*
an implementer's incorrect claim that the failure predated their change; a
second trap in the same task exposed the checker's own name-matching pattern
being blind to underscore-containing exports (passing when it should have
failed); an architectural decision about which directory a module belonged in
was steered directly by the registry's shape of enforcement; and the adversarial
review pass found 16 issues under an all-green suite — the registry catches
*absence*, adversarial review catches *presence of wrong behavior*, and they are
complementary.

**But the machinery is a backstop, not a preventer.** It refused to let mistakes
merge; it rarely stopped the first occurrence. One class of mistake — an agent
sweeping a whole shared file it did not own — recurred at least five times on a
single branch, and this round added a sharper instance: a concurrently running
agent restored `docs/reference/api.md` to `HEAD` and destroyed four separate
pieces of uncommitted reference documentation, which nothing noticed until two
checkers went red naming symbols that no longer had entries
(`artifacts/swiftui-parity-round2/INCIDENT-api-md-reverted-2026-08-13.md`). That
is a process and isolation problem — multiple agents in one working tree — not a
tooling defect, and no checker fixes it.

Two residual weaknesses this pass did not close:

- A fuzzer that asserts only "does not throw / stays finite / is deterministic"
  can pass over a real behavioral bug. The historical `ScrollView`
  horizontal-axis defect is the named example.
- **The checkers reconcile documentation against the export *table*, not against
  behaviour.** `api.md` can describe a per-frame animation cap that does not
  exist (§8.1) and every checker stays green, because the *symbol* is documented.
  Nothing in the gate machinery reads a paragraph and asks whether it is true.

---

## 12. Reference-app validation

The question underneath this whole document — *can a developer build the
in-experience parts of Apple's own reference apps from one declarative
description?* — was answered by building five of them clean-room. Ledgers and
evidence: `artifacts/swiftui-reference-app-validation/`.

| Proof | Interprets | Representative loop proven |
|---|---|---|
| Glade (`examples/reference/p1_glade`) | Backyard Birds ([SW-126]) | supply drain/refill, visit schedule, premium consumables, three-tier subscription-shaped commerce with scripted rejections |
| Cartwheel (`p2_cartwheel`) | Food Truck ([SW-127]) | adaptive split navigation, live order arrivals, a status machine and service-owned countdown that survive navigation, charts, entitlement gates, and a `UI.Stage` 3D hero |
| Sipworks (`p3_sipworks`) | Fruta ([SW-128]) | catalog/search/favorites, orders plus reward stamps plus threshold redemption, purchase-shaped recipe unlock, deep localization including plural fixtures and a ≥1.4× pseudo-locale, and a compact entry flow reusing the full components |
| Foyer (`p4_foyer`) | Roblox app home screen | sectioned discovery feed, friends carousel, search collapse, refresh and visit command lifecycles |
| Wardrobe (`p5_wardrobe`) | Roblox app avatar editor | try-on with undo/redo history over a live `UI.Stage` mannequin, purchase lifecycle with visible rejections, split ⇄ stacked layout survival |

All five carry their adaptation through `UI.ViewThatFits`, `UI.AdaptiveStack`,
and `UI.Composition`/`UI.Region` with **zero device-name branches** — the
strongest available evidence that the adaptive-layout story is real rather than
demo-shaped.

**Honest approximations the proofs declare.** Where a SwiftUI original does
something LuauUI cannot, the proof says so instead of faking it: shared-element
and hero transitions become a materialize modal (no matched-geometry subsystem);
3-D perspective card flips become width collapses; UI-over-UI blur is not
attempted (an engine limit); area-fill charts become banded strips (Roblox's
`Path2D` is stroke-only).

**Apple host-OS surfaces are never simulated.** Widgets, App Clips, Live
Activities, Dynamic Island, WeatherKit, StoreKit and Apple Pay chrome, and Sign
in with Apple are all recorded as **no host equivalent** rows in the ledger. They
are not gaps in LuauUI; they are operating-system features with nothing on the
other side of the comparison. The complete per-feature classification lives in
that stage's `capability-ledger.md`, and its follow-on candidates (reactive
compact labels, a bindable `newLabel.title`, fill-inside-hug contribution, and
the rest) in its `framework-fixes.md`.

*One caveat on that ledger:* `capability-ledger.md:59` still reads "no
secondary-action/swipe model yet." That predates `LuauUI.newRowActions` and is
stale; **this document supersedes it** for the controls area (§5.1).

---

## 13. Durable gaps

Cross-cutting gaps that no single mission is scoped to close. Each names the
section that owns it.

| Gap | Verdict | Owning section |
|---|---|---|
| Assistive-technology bridge (screen readers) — nothing at all | **Missing** | §7 |
| Right-to-left and bidirectional layout and text — nothing at all | **Missing** | §7, §5.1 |
| Materials / translucency; Apple's Liquid Glass | **Missing, and the gap widened** | §6 |
| `*Style` protocols — no way to substitute a control's rendering | **Missing, by decision** — the mapping is in §6.1 | §6 |
| Screen navigation (`NavigationStack`, `NavigationSplitView`), presentation detents, alert item-binding | **Missing / Partial** — surface stacking only | §9 |
| `matchedGeometryEffect`, `phaseAnimator`, `.scrollTransition` | **Missing** | §8 |
| Alignment guides (`.alignmentGuide` / custom `AlignmentID`) and baseline alignment | **Missing** | §4.4 |
| Flow-wrap (`UIListLayout.Wraps`) — the one place LuauUI is behind Roblox's own controls | **Missing** — its own mission, scoped | §4.1, §4.3 |
| Variable item extents in the virtualized collection | **Missing** — requirement and two candidate designs recorded, no implementation | §4.2 |
| `Toggle` cannot compose a `Label` (it is a leaf, not a container) | **Missing** — named non-delivery | §5.3 |
| No container unifying virtualization + reorder + selection | **Missing** | §4 |
| Per-row capability opt-outs — SwiftUI's `selectionDisabled(_:)` / `deleteDisabled(_:)` / `moveDisabled(_:)` family. Blocked behind the container split above: the family would otherwise be built twice | **Missing** — deferred by decision 2026-08-13, evidence in §5 | §5, §4 |
| Cell recycling for `VirtualList` rows | **Missing**, no longer load-bearing after hosted row actions | §10, §5.1 |
| Authored `opacity` — an authority decision, not a prop. `transparency` is presentation-owned, one authority per engine property is the manifest's whole job, and the schema has no presentation channel for an authored prop to declare | **Missing** — examined and deferred 2026-08-13; a subtree fade through `canvasGroup` already works | §6 |
| `.disabled()` as a subtree **cascade**. Per-control `enabled` ships on three leaves and is consistent on each; there is no inherited channel, and the classes with no disabled look (`Box`, `Text`, `Image`) would need a theme vocabulary before one would be honest | **Missing** — examined and deferred 2026-08-13 | §7 |
| The other 36 of the completeness audit's 39 unexamined capabilities — rich text runs, 2-D transforms, scoped environment, programmatic scroll position, scroll snapping, `Section` headers, localization, `Form`, empty-state, pull-to-refresh, scroll observation, and the rest | **Unexamined**, now enumerated and ranked rather than silently absent | [`the audit`](../plans/parity-completeness-audit-2026-08-13.md) §5 |
| Physical-device performance measurement | **Absent** — `deviceRun=false`, evidence level E1 | §10 |
| Gesture machinery in four implementations that duplicate state and math | **Confirmed** | §7 |
| `#Preview`-equivalent interactive authoring loop | **Missing** (no Roblox analogue), mitigated by scripted drives | §11 |
| Palette `Picker`, `DatePicker`, `ColorPicker`, `SecureField`, `TextEditor`, `Gauge`, `Link`, `ShareLink` | **Missing** | §5 |
| Documentation checkers cannot catch a false *paragraph*, only a missing *symbol* | **Confirmed** | §11 |

---

## 14. What still requires a physical device

**Nothing in LuauUI has been confirmed on physical hardware.** Every four-input
claim above rests on headless test runs (evidence level E1) plus Roblox Studio
emulator drives (E3). No E4 row has ever been filled.

Six checks are owed by the row-actions work. Each is a single check a human can
run in well under a minute with the `row_actions` scenario selected and playing.
Source: `artifacts/row-actions/device-matrix.md`.

| Check | What to do |
|---|---|
| Touch capture vs native scroll | On a real touch device, swipe a list row *mostly vertically*, starting on the row: the list should scroll (not the row), and no residual horizontal offset should remain on the row after release. |
| Scroll steals pan | Fling the list hard enough that it is still decelerating, then touch down on a row and immediately drag horizontally: the row should still open — native momentum scrolling must not eat the gesture. |
| Shift+Return on real hardware | Hold physical Shift and press Return on a focused row: the action menu should open, not the row's own primary action. This exercises the real engine modifier-binding path, which headless tests can only simulate. |
| Releasing Shift mid-chord | Press Shift, press Return, then **release Shift before releasing Return**: the menu should open exactly once — no double-fire, no stuck-open state. |
| Same-frame gamepad chord | Press ButtonX and a D-pad direction in the same physical input frame: the menu should open *and* D-pad navigation inside it should still work. |
| Multi-touch bleed | With two fingers, touch down on two different rows at once and drag both outward (opposite trays): each row's tray should open independently, and the one-open coordinator must not cross-close one because of the other's claim. |

Three more are newly owed by the haptics adapter (§7.1). Source:
`artifacts/swiftui-parity-round2/phase-3-haptics-evidence.md`.

| Check | What to do | Why it cannot close here |
|---|---|---|
| `haptics-gamepad-felt` | Confirm a mapped verb produces a **perceptible** rumble on a PlayStation/Xbox/Quest pad | Roblox documents controllers on macOS 15+ as unsupported; a silent run on this machine is not evidence that haptics do not work |
| `haptics-phone-felt` | The same on a haptic-capable iOS/Android phone | No device in the loop, and the platform docs say only "most" modern phones have haptics — which is also why touch is permanently `unknown` rather than `supported` |
| `haptics-player-preference-honored` | Confirm the player's own Roblox haptics setting silences or scales what the adapter plays | `UserGameSettings.HapticStrength` is script-security-locked on read *and* write, so the question is unanswerable from inside the process |

Three older riders also remain open and are not repeated in full here: physical
confirmation of the Dynamic Type equivalent at the Largest preference, a
subjective feel pass on the same, and physical confirmation of the engine
selection bridge. See `artifacts/large-text-accessibility/acceptance.md` and
`artifacts/native-substrate/acceptance-ledger.md`.

---

## 15. Verification appendix

| | |
|---|---|
| LuauUI version | `0.9.0` (`src/init.luau:133`) |
| Audit date | 2026-08-13 (this rewrite, and the SwiftUI citation pass of §16); the nine-area sweep it builds on ran 2026-08-11 |
| Repository state | `3d60d24` — parity round 2, Phase 4, plus the citation pass |
| Method | A fresh draft. Every verdict in §§3–11 was re-checked against current source or a named test between 2026-08-12 and 2026-08-13; nothing was inherited from the previous revision, which had four confirmed false rows (§4's `containerRelativeFrame`, `layoutPriority`, `GridRow`, and ZStack `zIndex`). Where a line number is cited it was read during this pass. Where a claim could not be verified from here, it says so |
| SwiftUI baseline | The shipping surface as documented on developer.apple.com on **2026-08-13**, including Apple's **June 2026** update — the one that pairs with Xcode 27 and the 27.0 OS releases ([SW-129]). Three items in that update touch this comparison directly and are reflected above: drag reordering generalised to stacks, grids and custom layouts (`reorderable()` / `reorderContainer`, §4), swipe actions generalised out of `List` (§5), and item- and error-driven alerts (§9) |
| Roblox baseline | `UIListLayout` / `UIFlexItem` / `UIFlexAlignment` / `ItemLineAlignment` / `UIFlexMode` documentation re-read on create.roblox.com, 2026-08-13 (§4.1) |
| LuauUI baseline | Source only: `src/blueprint.luau`, `src/blueprint_schema.luau`, `src/init.luau`, `src/controls/`, `src/layout/`, `src/render/`, `src/present/`, `src/client/`, `src/motion/`, `src/themes/`, `src/tokens/`, `src/input/`, `src/focus/`, plus `tests/conformance/controls_registry.luau` |
| **The SwiftUI-side denominator** | **365** scored capability groups, being the `groupMarker` headings across Apple's 49 SwiftUI collection landing pages, pulled from the DocC symbol index (`developer.apple.com/tutorials/data/index/swiftui`, 10,988 nodes) on 2026-08-13; 392 groups found, 27 dropped as navigation scaffolding. Of the 365: **127 examined by this document**, 120 with no Roblox substrate, 54 applicable but deliberately out of scope, and **64 unexamined** (deduplicating to 39 named capabilities). Method, reproduction script and the full ranked list: [`../plans/parity-completeness-audit-2026-08-13.md`](../plans/parity-completeness-audit-2026-08-13.md). **This is a bounded catalog, not a percentage score for all of SwiftUI** — §1 says what that means for a reader |

**Claims about SwiftUI that citing them proved WRONG.** Every one had stood
uncited, which is exactly why. Each is corrected in place, in the section named:

| Was | Is | Where |
|---|---|---|
| `gridCellUnsizedAxis` named as a SwiftUI symbol | The symbol is `gridCellUnsizedAxes` — plural, `Axis.Set`. The singular does not exist | §4 |
| "a spanning cell contributes to no single column's maximum" read as SwiftUI's rule | Apple documents the span and its anchor-alignment consequence and **no column-sizing behaviour at all**; the rule is LuauUI's | §4 |
| springs are "response and damping ratio, never mass and stiffness" | Apple's parameter is `dampingFraction` (`Spring.dampingRatio` is the other spelling), and SwiftUI *does* also ship the mass/stiffness form as `interpolatingSpring` | §8 |
| `iconOnly` fallback "better than SwiftUI's, which shows nothing" | Apple documents no visual behaviour for an iconless `.iconOnly` label — only that the title survives for VoiceOver | §5 |
| "SwiftUI's `.alert(item:)` pattern" | `alert(item:content:)` was deprecated in the 27.0 releases; the live item-driven form is `alert(_:isPresented:presenting:actions:)` / `alert(_:item:actions:)` | §9 |
| "Nothing orders a Cancel row automatically" left as a LuauUI-only remark | SwiftUI's dialogs *do* reorder by role and let a `cancel` button replace the default dismiss — a real gap, now stated as one | §9 |
| "coarser than SwiftUI's `List`/`LazyVStack` reusing cell identity" | Apple documents laziness and **no reuse or recycling at all**; ours was an inference presented as a comparison | §10 |
| Xcode 27's Instruments "added Processor Trace, CPU counters, concurrency visibility, hitches" | Processor Trace and CPU Counters shipped in Xcode **26**; Xcode 27 added the Swift Executors instrument and the Hitches metric | §10 |
| Xcode 27 "added interactive resize handles to Live Previews" | No such phrase exists in Apple's notes; the feature is **Resizable Canvas mode** for iOS previews | §11 |
| "stronger than SwiftUI's default" (row re-added mid-transition), "stricter than SwiftUI" (disposal) | Apple documents neither behaviour; both are now stated as LuauUI guarantees rather than as wins | §3 |

Two more were left standing but re-labelled, because the claim is true and the
*support* was not what we thought: SwiftUI's `tint` cascade is a consequence of
its environment model rather than a documented sentence (§6), and "SwiftUI
re-runs a view's `body` and diffs the result" is a mechanism Apple never
documents — only the effect (§3).

**Things this pass could NOT verify, recorded rather than assumed.**

- **No physical-device evidence exists for anything.** Every four-input and
  haptics claim is E1/E3 (§14).
- **The per-frame `withAnimation` record cap described in `api.md` is not
  implemented** (§8.1). This document does not repeat it. Whether the right fix
  is to build the cap or to correct the reference entry is a decision, not a
  finding.
- **`api.md`'s "five-layer surface order"** names four `SURFACE_LAYER` constants
  (§9). The fifth is the scrim, which is positioned relative to its owner rather
  than banded. Recorded as a wording inconsistency, not a defect.
- Items in the 69-item SwiftUI catalog not named in §5 were not independently
  re-examined in this pass.
- **No citation in §16 proves a behaviour, only a sentence.** Every quote was
  checked as a literal substring of the page it names, on 2026-08-13. That
  catches a claim nobody sourced and a page that has since changed; it does not
  catch a claim that misreads a sentence it quotes correctly, and it says
  nothing about what SwiftUI does at runtime beyond what Apple wrote down.
- Prose paragraphs are cited where they make a SwiftUI claim, but the mechanical
  check covers **table rows only** (§16).

Every check below was run live for this report:

```bash
cd GameStudio/ui/LuauUI
./run-tests.sh                                    # 4562 passed, 0 failed, exit 0
lune run tests/conformance/corpus_cli             # a11y-l10n-corpus: 15/15 passed
lune run tools/lune/check_registration_cli        # PASS — 16 controls, 90 exports documented,
                                                  #   172 specs registered, 15/15 four-input + paradigm
lune run tools/lune/check_boundary                # PASS — 98 src files, 381 consumer files
lune run tools/lune/check_docs_cli                # PASS — 9 documents, 81 surface anchors,
                                                  #   118 SwiftUI citations, 64 local links,
                                                  #   7 themes exports, 11 stale phrases absent
lune run tools/lune/check_prop_parity_cli         # PASS — 26 classes, 532 properties, 2 diagnosed,
                                                  #   569 typed fields
lune run tools/lune/check_surface_ledger          # PASS — every public export and nested member classified
python3 tools/check_manifest_integrity.py         # exit 0 — 655 suite greps, all anchored to the pass marker
python3 tools/check_row_actions_matrix.py         # exit 0 — functional matrix intact; perf within the
                                                  #   RESTORED ceilings (steady ≤5%, fling ≤5%, ≤1 instance)
```

Counts quoted in §§5, 10 and 11, reproducible:

```bash
grep -c '^\t\["' tools/lune/gate_manifest.luau                        # 25 gates
grep -rc '^export type.*Spec' src/ | awk -F: '{s+=$2} END {print s}'  # 55 exported Spec types
grep -c ': any' src/init.luau                                         # 1 (inside an explanatory comment)
python3 -c "import json;print(len(json.load(open('bench/perf_budgets.json'))['scenes']))"  # 20 perf scenes
```

**A note on section numbering.** Section 12's heading text is load-bearing:
`tools/lune/gate_manifest.luau` greps this document for the literal strings
`## 12. Reference-app validation`, `no host equivalent`, `UI.Stage`, and
`measured per-preference constants` as part of two closed gates. Renumbering or
rewording that heading breaks a passing gate; the other section numbers are free.

---

## 16. Citations — what Apple's documentation actually says

Every `[SW-nn]` used above resolves here: the page a reader should open, the
sentence the claim rests on **quoted verbatim from that page**, the availability
Apple states, and the date the page was read. Quotes are literal — each was
checked as an exact substring of the page's own text on the date given, so a
quote that no longer appears means the page changed and the row above it is due
a re-read.

Three conventions worth knowing before you use this table:

- **Availability is part of the claim.** Several rows exist only because a
  capability is narrower than its name suggests — `focusSection()` is macOS and
  tvOS only, `pointerStyle(_:)` has no iOS availability at all, `fullScreenCover`
  is not on macOS, `swipeActions` is not on tvOS. Where a row above compares
  against SwiftUI "having" something, the availability column is where you find
  out where it has it.
- **Silence is recorded as silence.** Where Apple documents nothing, the row says
  **Apple documents no behaviour here** and the claim above it is restated as
  LuauUI's own rather than as a comparison. [SW-10] is the shared citation for
  absence claims ("no SwiftUI equivalent"): it means the SwiftUI framework index
  and topic tree were searched on the date given and list no such symbol.
- **A citation proves a sentence, not a behaviour.** It cannot tell you the
  sentence was read correctly, and it says nothing about runtime behaviour Apple
  never wrote down.
- **How to re-check a quote without a browser.** `developer.apple.com`
  documentation pages render client-side, so fetching one gives you an empty
  shell; the text lives at the JSON twin. Swap `developer.apple.com/documentation/`
  for `developer.apple.com/tutorials/data/documentation/` and append `.json`
  (for HIG pages, `developer.apple.com/design/` becomes
  `developer.apple.com/tutorials/data/design/`). Every quote below was checked as
  a literal substring of that payload on the date given — which is also why the
  quotes avoid sentences whose middle is a symbol link: those read as one
  sentence on the page and arrive as several fragments in the payload.
- **Two rows above are knowingly uncited**, and the checker names them: the
  `Table.onPrimaryAction` row in §5 (which quotes Apple inline but does not link
  it) and the per-row-opt-out row in §13. Both were being written by a
  concurrently running task while this pass ran, and editing them would have
  destroyed that work. They are the citation debt this round leaves behind, and
  `tools/lune/check_docs.luau` will complain the moment either exemption stops
  being needed.

| Id | Apple's page | The sentence the claim rests on | Availability Apple states | Checked |
|---|---|---|---|---|
| **SW-01** | [`State`](https://developer.apple.com/documentation/swiftui/state) | “Use state as the single source of truth for a given value type that you store in a view hierarchy.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-02** | [`Binding`](https://developer.apple.com/documentation/swiftui/binding) | “Use a binding to create a two-way connection between a property that stores data, and a view that displays and changes the data.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-03** | [`Observable()`](https://developer.apple.com/documentation/observation/observable()) | “Defines and implements conformance of the Observable protocol.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ | 2026-08-13 |
| **SW-04** | [Managing model data in your app](https://developer.apple.com/documentation/swiftui/model-data) | “When the data changes, either due to an external event or because of an action that the user performs, SwiftUI automatically updates the affected parts of the interface.” | Article, no per-platform table. **Apple documents no behaviour here** for the *mechanism* — body re-execution and diffing are nowhere stated on the `View` page or this one | 2026-08-13 |
| **SW-05** | [`withAnimation(_:_:)`](https://developer.apple.com/documentation/swiftui/withanimation(_:_:)) | “Returns the result of recomputing the view's body with the provided animation.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-06** | [`withTransaction(_:_:)`](https://developer.apple.com/documentation/swiftui/withtransaction(_:_:)) | “Executes a closure with the specified transaction and returns the result.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-07** | [`task(name:priority:file:line:_:)`](https://developer.apple.com/documentation/swiftui/view/task(name:priority:file:line:_:)) | “Use this modifier to perform an asynchronous task with a lifetime that matches that of the modified view.” | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+. The bare `task(priority:_:)` spelling no longer resolves in Apple's live tree; this named overload is where the modifier is documented now | 2026-08-13 |
| **SW-08** | [`EnvironmentValues`](https://developer.apple.com/documentation/swiftui/environmentvalues) / [`Environment`](https://developer.apple.com/documentation/swiftui/environment) | “A collection of environment values propagated through a view hierarchy.” “A property wrapper that reads a value from a view's environment.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-09** | [`ForEach`](https://developer.apple.com/documentation/swiftui/foreach) | “A structure that computes views on demand from an underlying collection of identified data.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. **Apple documents no behaviour here** for an element removed and re-added while a transition is in flight | 2026-08-13 |
| **SW-10** | [SwiftUI framework index](https://developer.apple.com/documentation/swiftui) | “Declare the user interface and behavior for your app on every platform.” | The shared citation for absence claims. **Apple documents no behaviour here**: the framework index and topic tree were searched on the date given and list no symbol for the capability the citing row names | 2026-08-13 |
| **SW-11** | [`HStack.init(alignment:spacing:content:)`](https://developer.apple.com/documentation/swiftui/hstack/init(alignment:spacing:content:)) | “The distance between adjacent subviews, or nil if you want the stack to choose a default distance for each pair of subviews.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. The initializer takes `alignment` and `spacing` and nothing else — there is no distribution parameter to cite, which is the claim | 2026-08-13 |
| **SW-12** | [`Spacer`](https://developer.apple.com/documentation/swiftui/spacer) | “A flexible space that expands along the major axis of its containing stack layout, or on both axes if not contained in a stack.” “The minimum length this spacer can be shrunk to, along the axis or axes of expansion.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-13** | [`layoutPriority(_:)`](https://developer.apple.com/documentation/swiftui/view/layoutpriority(_:)) | “A parent layout offers the child views with the highest layout priority all the space offered to the parent minus the minimum space required for all its lower-priority children.” “Raising a view's layout priority encourages the higher priority view to shrink later when the group is shrunk and stretch sooner when the group is stretched.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-14** | [`frame(width:height:alignment:)`](https://developer.apple.com/documentation/swiftui/view/frame(width:height:alignment:)) | “The alignment of this view inside the resulting frame.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-15** | [`zIndex(_:)`](https://developer.apple.com/documentation/swiftui/view/zindex(_:)) | “Controls the display order of overlapping views.” “A relative front-to-back ordering for this view” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. **Apple documents no behaviour here** for stacking *scope* — the page never says the value applies only among siblings of one container | 2026-08-13 |
| **SW-16** | [`Grid`](https://developer.apple.com/documentation/swiftui/grid) | “The grid sets the width of all the cells in a column to match the needs of column's widest cell.” “A grid can size its rows and columns correctly because it renders all of its child views immediately.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ | 2026-08-13 |
| **SW-17** | [`GridRow.init(alignment:content:)`](https://developer.apple.com/documentation/swiftui/gridrow/init(alignment:content:)) | “Provide a content closure that defines the cells of the row, and optionally customize the vertical alignment of content within each cell.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+. The per-row override is vertical only | 2026-08-13 |
| **SW-18** | [`gridCellColumns(_:)`](https://developer.apple.com/documentation/swiftui/view/gridcellcolumns(_:)) | “Tells a view that acts as a cell in a grid to span the specified number of columns.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+. **Apple documents no behaviour here** for how a spanning cell affects the width of the columns it spans — only the span itself and its anchor-alignment consequence | 2026-08-13 |
| **SW-19** | [`gridCellAnchor(_:)`](https://developer.apple.com/documentation/swiftui/view/gridcellanchor(_:)) | “Specifies a custom alignment anchor for a view that acts as a grid cell.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ | 2026-08-13 |
| **SW-20** | [`gridCellUnsizedAxes(_:)`](https://developer.apple.com/documentation/swiftui/view/gridcellunsizedaxes(_:)) | “Asks grid layouts not to offer the view extra size in the specified axes.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+. Plural, and it takes an `Axis.Set`; the singular `gridCellUnsizedAxis` this document used to name does not exist | 2026-08-13 |
| **SW-21** | [`LazyVGrid`](https://developer.apple.com/documentation/swiftui/lazyvgrid) | “A container view that arranges its child views in a grid that grows vertically, creating items only as needed.” | iOS 14+, macOS 11+, tvOS 14+, watchOS 7+, visionOS 1+ | 2026-08-13 |
| **SW-22** | [`ViewThatFits`](https://developer.apple.com/documentation/swiftui/viewthatfits) | “It selects the first child whose ideal size on the constrained axes fits within the proposed size.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ | 2026-08-13 |
| **SW-23** | [`AnyLayout`](https://developer.apple.com/documentation/swiftui/anylayout) | “Use an AnyLayout instance to enable dynamically changing the type of a layout container without destroying the state of the subviews.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ | 2026-08-13 |
| **SW-24** | [`Layout`](https://developer.apple.com/documentation/swiftui/layout) | “A type that defines the geometry of a collection of views.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ | 2026-08-13 |
| **SW-25** | [`containerRelativeFrame(_:alignment:)`](https://developer.apple.com/documentation/swiftui/view/containerrelativeframe(_:alignment:)) | “Positions this view within an invisible frame with a size relative to the nearest container.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ | 2026-08-13 |
| **SW-26** | [`containerRelativeFrame(_:count:span:spacing:alignment:)`](https://developer.apple.com/documentation/swiftui/view/containerrelativeframe(_:count:span:spacing:alignment:)) | “When using this modifier, the count refers to the total number of rows or columns that the length of the container size in a particular axis should be divided into.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+. The three-line arithmetic LuauUI copies is published on this page as a code sample | 2026-08-13 |
| **SW-27** | [`containerRelativeFrame(_:alignment:_:)`](https://developer.apple.com/documentation/swiftui/view/containerrelativeframe(_:alignment:_:)) | “Use this modifier to apply your own custom logic to adjust the size of the nearest container for your view.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+. The axes parameter is an `Axis.Set`, so the multi-axis form is real | 2026-08-13 |
| **SW-28** | [`alignmentGuide(_:computeValue:)`](https://developer.apple.com/documentation/swiftui/view/alignmentguide(_:computevalue:)) | “Use alignmentGuide(_:computeValue:) to calculate specific offsets to reposition views in relationship to one another.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-29** | [`AlignmentID`](https://developer.apple.com/documentation/swiftui/alignmentid) | “A type that you use to create custom alignment guides.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-30** | [`VerticalAlignment.firstTextBaseline`](https://developer.apple.com/documentation/swiftui/verticalalignment/firsttextbaseline) | “A guide that marks the top-most text baseline in a view.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-31** | [`LazyVStack`](https://developer.apple.com/documentation/swiftui/lazyvstack) | “the stack view doesn't create items until it needs to render them onscreen” | iOS 14+, macOS 11+, tvOS 14+, watchOS 7+, visionOS 1+. The page requires no declared item extent and no key function — that absence is the comparison in §4.2 | 2026-08-13 |
| **SW-32** | [`GeometryReader`](https://developer.apple.com/documentation/swiftui/geometryreader) | “A container view that defines its content as a function of its own size and coordinate space.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-34** | [`List`](https://developer.apple.com/documentation/swiftui/list) | “A container that presents rows of data arranged in a single column, optionally providing the ability to select one or more members.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. **Apple documents no behaviour here** for view reuse or recycling: the words "reuse" and "recycle" appear nowhere on this page or on the lazy-stack pages | 2026-08-13 |
| **SW-35** | [`reorderable()`](https://developer.apple.com/documentation/swiftui/dynamicviewcontent/reorderable()) | “Enables reordering of views from this content inside the scope of a reorderable container modifier.” | iOS 27+, macOS 27+, watchOS 27+, visionOS 27+ (June 2026) | 2026-08-13 |
| **SW-36** | [`reorderContainer(for:isEnabled:move:)`](https://developer.apple.com/documentation/swiftui/view/reordercontainer(for:isenabled:move:)) | “Declare this modifier on your list, stack, grid, or custom layout to define a reorderable container.” | iOS 27+, macOS 27+, watchOS 27+, visionOS 27+ (June 2026) | 2026-08-13 |
| **SW-37** | [`swipeActions(edge:allowsFullSwipe:content:)`](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:)) | “Adds custom swipe actions to a row in a list.” “A Boolean value that indicates whether a full swipe automatically performs the first action.” | iOS 15+, macOS 12+, watchOS 8+, visionOS 1+ — **no tvOS**. Edge defaults to trailing; full swipe defaults to true | 2026-08-13 |
| **SW-38** | [`swipeActions(edge:allowsFullSwipe:content:onPresentationChanged:)`](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:onpresentationchanged:)) | “Adds custom swipe actions to a row in a list or container, notifying you when the actions are revealed or dismissed.” | iOS 27+, macOS 27+, watchOS 27+, visionOS 27+ (June 2026) — this is the release that took swipe actions out of `List` | 2026-08-13 |
| **SW-41** | [`PickerStyle`](https://developer.apple.com/documentation/swiftui/pickerstyle) | “A type that specifies the appearance and interaction of all pickers within a view hierarchy.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. Built-in styles include `automatic`, `inline`, `menu`, `navigationLink`, `palette`, `radioGroup`, `segmented`, `tabs`, `wheel` | 2026-08-13 |
| **SW-42** | [`PickerStyle.palette`](https://developer.apple.com/documentation/swiftui/pickerstyle/palette) | “A picker style that presents the options as a row of compact elements.” | iOS 17+, macOS 14+, visionOS 1+ — **no tvOS, no watchOS** | 2026-08-13 |
| **SW-43** | [`ProgressView`](https://developer.apple.com/documentation/swiftui/progressview) | “To create an indeterminate progress view, use an initializer that doesn't take a progress value” | iOS 14+, macOS 11+, tvOS 14+, watchOS 7+, visionOS 1+ | 2026-08-13 |
| **SW-45** | [`LabelStyle`](https://developer.apple.com/documentation/swiftui/labelstyle) | “A type that applies a custom appearance to all labels within a view.” | iOS 14+, macOS 11+, tvOS 14+, watchOS 7+, visionOS 1+ | 2026-08-13 |
| **SW-46** | [`LabelStyle.iconOnly`](https://developer.apple.com/documentation/swiftui/labelstyle/icononly) | “The title of the label is still used for non-visual descriptions, such as VoiceOver.” | iOS 14+, macOS 11+, tvOS 14+, watchOS 7+, visionOS 1+. **Apple documents no behaviour here** for what an `.iconOnly` label paints when it has no icon | 2026-08-13 |
| **SW-48** | [`Divider`](https://developer.apple.com/documentation/swiftui/divider) | “When contained in a stack, the divider extends across the minor axis of the stack, or horizontally when not in a stack.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-50** | [`contextMenu(menuItems:)`](https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:)) | “When someone activates the context menu with an action like touch and hold in iOS or iPadOS, the system displays the menu next to the content” | iOS 13+, macOS 10.15+, tvOS 14+, watchOS 6+, visionOS 1+. **Apple documents no behaviour here** for the macOS trigger gesture specifically; the page notes only that macOS shows no preview | 2026-08-13 |
| **SW-51** | [`ButtonStyle`](https://developer.apple.com/documentation/swiftui/buttonstyle) | “A type that applies standard interaction behavior and a custom appearance to all buttons within a view hierarchy.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-52** | [`ToggleStyle`](https://developer.apple.com/documentation/swiftui/togglestyle) | “The appearance and behavior of a toggle.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-53** | [`ProgressViewStyle`](https://developer.apple.com/documentation/swiftui/progressviewstyle) | “A type that applies standard interaction behavior to all progress views within a view hierarchy.” | iOS 14+, macOS 11+, tvOS 14+, watchOS 7+, visionOS 1+ | 2026-08-13 |
| **SW-54** | [`ListStyle`](https://developer.apple.com/documentation/swiftui/liststyle) | “A protocol that describes the behavior and appearance of a list.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-55** | [`GaugeStyle`](https://developer.apple.com/documentation/swiftui/gaugestyle) | “Defines the implementation of all gauge instances within a view hierarchy.” | iOS 16+, macOS 13+, watchOS 7+, visionOS 1+ — **no tvOS** | 2026-08-13 |
| **SW-56** | [`Toggle`](https://developer.apple.com/documentation/swiftui/toggle) | “Set the label to a view that visually describes the purpose of switching between toggle states.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-62** | [`DatePicker`](https://developer.apple.com/documentation/swiftui/datepicker) | “A control for selecting an absolute date.” | iOS 13+, macOS 10.15+, watchOS 10+, visionOS 1+ — **no tvOS** | 2026-08-13 |
| **SW-63** | [`ColorPicker`](https://developer.apple.com/documentation/swiftui/colorpicker) | “A control used to select a color from the system color picker UI.” | iOS 14+, macOS 11+, visionOS 1+ — **no tvOS, no watchOS** | 2026-08-13 |
| **SW-64** | [`SecureField`](https://developer.apple.com/documentation/swiftui/securefield) | “A control into which people securely enter private text.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-65** | [`TextEditor`](https://developer.apple.com/documentation/swiftui/texteditor) | “A view that can display and edit long-form text.” | iOS 14+, macOS 11+, visionOS 1+ — **no tvOS, no watchOS** | 2026-08-13 |
| **SW-66** | [`Gauge`](https://developer.apple.com/documentation/swiftui/gauge) | “A view that shows a value within a range.” | iOS 16+, macOS 13+, watchOS 7+, visionOS 1+ — **no tvOS** | 2026-08-13 |
| **SW-67** | [`Link`](https://developer.apple.com/documentation/swiftui/link) | “A control for navigating to a URL.” | iOS 14+, macOS 11+, tvOS 14+, watchOS 7+, visionOS 1+ | 2026-08-13 |
| **SW-68** | [`ShareLink`](https://developer.apple.com/documentation/swiftui/sharelink) | “A view that controls a sharing presentation.” | iOS 16+, macOS 13+, watchOS 9+, visionOS 1+ — **no tvOS** | 2026-08-13 |
| **SW-69** | [`NavigationSplitView`](https://developer.apple.com/documentation/swiftui/navigationsplitview) | “A view that presents views in two or three columns, where selections in leading columns control presentations in subsequent columns.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ | 2026-08-13 |
| **SW-70** | [`sensoryFeedback(_:trigger:)`](https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)) | “Plays the specified feedback when the provided trigger value changes.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 26+ | 2026-08-13 |
| **SW-71** | [`SensoryFeedback.impact`](https://developer.apple.com/documentation/swiftui/sensoryfeedback/impact) | “Only plays feedback on iOS and watchOS.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+. The restriction is documented per feedback case, not on the modifier | 2026-08-13 |
| **SW-72** | [HIG: Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | “As a general rule, a button needs a hit region of at least 44x44 pt — in visionOS, 60x60 pt — to ensure that people can select it easily, whether they use a fingertip, a pointer, their eyes, or a remote.” | Design guidance, all platforms. Note the HIG's Accessibility page tabulates 44x44 pt as the iOS *default* control size and 28x28 pt as the minimum; this Buttons sentence is the one that states a floor | 2026-08-13 |
| **SW-73** | [`Material`](https://developer.apple.com/documentation/swiftui/material) | “The blurring effect provided by the material isn't simple opacity.” “When you add a material, foreground elements exhibit vibrancy, a context-specific blend of the foreground and background colors that improves contrast.” | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ | 2026-08-13 |
| **SW-74** | [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) | “Applies the Liquid Glass effect to a view.” | iOS 26+, iPadOS 26+, macOS 26+, tvOS 26+, watchOS 26+ | 2026-08-13 |
| **SW-75** | [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) | “A view that combines multiple Liquid Glass shapes into a single shape that can morph individual shapes into one another.” | iOS 26+, iPadOS 26+, macOS 26+, tvOS 26+, watchOS 26+ | 2026-08-13 |
| **SW-76** | [HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | “Liquid Glass forms a distinct functional layer for controls and navigation elements — like tab bars and sidebars — that floats above the content layer, establishing a clear visual hierarchy between functional elements and content.” | Design guidance, current on the date checked — a year after the 26 releases shipped it | 2026-08-13 |
| **SW-77** | [`tint(_:)`](https://developer.apple.com/documentation/swiftui/view/tint(_:)) | “Sets the tint color within this view.” | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+. **Apple documents no behaviour here** for subtree inheritance — the page says nothing about descendants | 2026-08-13 |
| **SW-78** | [`colorScheme`](https://developer.apple.com/documentation/swiftui/environmentvalues/colorscheme) | “The value that you receive depends on whether the user has enabled Dark Mode, possibly superseded by the configuration of the current presentation's view hierarchy.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-79** | [`dynamicTypeSize`](https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize) | “This value changes as the user's chosen Dynamic Type size changes.” | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ | 2026-08-13 |
| **SW-80** | [HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography) | “Dynamic Type is a system-level feature in iOS, iPadOS, tvOS, visionOS, and watchOS that lets people adjust the size of visible text on their device to ensure readability and comfort.” | Design guidance. macOS is deliberately absent from that list | 2026-08-13 |
| **SW-81** | [Accessibility fundamentals](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals) | “try using your app with accessibility features like VoiceOver, Voice Control, and Switch Control” | Article, all platforms | 2026-08-13 |
| **SW-82** | [`accessibilityLabel(_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)) | “Use this method to provide an accessibility label for a view that doesn't display text, like an icon.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ | 2026-08-13 |
| **SW-83** | [`accessibilityAction(_:_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilityaction(_:_:)) | “Actions allow assistive technologies, such as the VoiceOver, to interact with the view by invoking the action.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-84** | [`accessibilityReduceMotion`](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion) | “If this property's value is true, UI should avoid large animations, especially those that simulate the third dimension.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-85** | [`FocusState`](https://developer.apple.com/documentation/swiftui/focusstate) | “A property wrapper type that can read and write a value that SwiftUI updates as the placement of focus within the scene changes.” | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ | 2026-08-13 |
| **SW-86** | [`focusSection()`](https://developer.apple.com/documentation/swiftui/view/focussection()) | “Indicates that the view's frame and cohort of focusable descendants should be used to guide focus movement.” | **macOS 13+ and tvOS 15+ only** — no iOS, iPadOS, watchOS or visionOS availability at all | 2026-08-13 |
| **SW-87** | [`onKeyPress(_:action:)`](https://developer.apple.com/documentation/swiftui/view/onkeypress(_:action:)) | “Performs an action if the user presses a key on a hardware keyboard while the view has focus.” | iOS 17+, macOS 14+, tvOS 17+, visionOS 1+ — **no watchOS** | 2026-08-13 |
| **SW-88** | [`onHover(perform:)`](https://developer.apple.com/documentation/swiftui/view/onhover(perform:)) | “Adds an action to perform when the user moves the pointer over or away from the view's frame.” | iOS 13.4+, macOS 10.15+, visionOS 1+ — **no tvOS, no watchOS** | 2026-08-13 |
| **SW-89** | [`pointerStyle(_:)`](https://developer.apple.com/documentation/swiftui/view/pointerstyle(_:)) | “Sets the pointer style to display when the pointer is over the view.” | **macOS 15+ and visionOS 2+ only** — no iOS or iPadOS availability | 2026-08-13 |
| **SW-90** | [`layoutDirection`](https://developer.apple.com/documentation/swiftui/environmentvalues/layoutdirection) | “Use this value to determine or set whether the environment uses a left-to-right or right-to-left direction.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-91** | [HIG: Right to left](https://developer.apple.com/design/human-interface-guidelines/right-to-left) | “System-provided UI frameworks support right-to-left (RTL) by default, allowing system-provided UI components to flip automatically in the RTL context.” | Design guidance, all platforms | 2026-08-13 |
| **SW-92** | [`simultaneously(with:)`](https://developer.apple.com/documentation/swiftui/gesture/simultaneously(with:)) | “Combines a gesture with another gesture to create a new gesture that recognizes both gestures at the same time.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-93** | [`sequenced(before:)`](https://developer.apple.com/documentation/swiftui/gesture/sequenced(before:)) | “Sequences a gesture with another one to create a new gesture, which results in the second gesture only receiving events after the first gesture succeeds.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-94** | [`exclusively(before:)`](https://developer.apple.com/documentation/swiftui/gesture/exclusively(before:)) | “Combines two gestures exclusively to create a new gesture where only one gesture succeeds, giving precedence to the first gesture.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-95** | [`draggable(_:)`](https://developer.apple.com/documentation/swiftui/view/draggable(_:)) | “Activates this view as the source of a drag and drop operation.” | iOS 16+, macOS 13+, visionOS 1+ — **no tvOS, no watchOS** | 2026-08-13 |
| **SW-96** | [`dropDestination(for:action:isTargeted:)`](https://developer.apple.com/documentation/swiftui/view/dropdestination(for:action:istargeted:)) | “Defines the destination of a drag and drop operation that handles the dropped content with a closure that you specify.” | iOS 16+, macOS 13+ — **deprecated in the 27.0 releases** in favour of a session-based overload | 2026-08-13 |
| **SW-97** | [`EventModifiers`](https://developer.apple.com/documentation/swiftui/eventmodifiers) | “A set of key modifiers that you can add to a gesture.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. The set is `capsLock`, `command`, `control`, `numericPad`, `option`, `shift` (plus a deprecated `function`); `keyboardShortcut(_:modifiers:)` itself is iOS 14+/macOS 11+ and ships on neither tvOS nor watchOS | 2026-08-13 |
| **SW-98** | [`Animation.spring(response:dampingFraction:blendDuration:)`](https://developer.apple.com/documentation/swiftui/animation/spring(response:dampingfraction:blendduration:)) | “The amount of drag applied to the value being animated, as a fraction of an estimate of amount needed to produce critical damping.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. The parameter is `dampingFraction`; not deprecated, and the newer `spring(duration:bounce:blendDuration:)` form is not a replacement | 2026-08-13 |
| **SW-99** | [`Spring.dampingRatio`](https://developer.apple.com/documentation/swiftui/spring/dampingratio) | “The amount of drag applied, as a fraction of the amount needed to produce critical damping.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ | 2026-08-13 |
| **SW-100** | [`Animation.interpolatingSpring(mass:stiffness:damping:initialVelocity:)`](https://developer.apple.com/documentation/swiftui/animation/interpolatingspring(mass:stiffness:damping:initialvelocity:)) | “Preserves velocity across overlapping animations by adding the effects of each animation.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. This is the mass/stiffness form SwiftUI also ships | 2026-08-13 |
| **SW-101** | [`withAnimation(_:completionCriteria:_:completion:)`](https://developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:)) | “The completion callback will always be fired exactly one time.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ | 2026-08-13 |
| **SW-102** | [`phaseAnimator(_:trigger:content:animation:)`](https://developer.apple.com/documentation/swiftui/view/phaseanimator(_:trigger:content:animation:)) | “Animates effects that you apply to a view over a sequence of phases that change based on a trigger.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ | 2026-08-13 |
| **SW-103** | [`KeyframeTimeline`](https://developer.apple.com/documentation/swiftui/keyframetimeline) | “A description of how a value changes over time, modeled using keyframes.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ | 2026-08-13 |
| **SW-104** | [`AnyTransition.asymmetric(insertion:removal:)`](https://developer.apple.com/documentation/swiftui/anytransition/asymmetric(insertion:removal:)) | “Provides a composite transition that uses a different transition for insertion versus removal.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-105** | [`matchedGeometryEffect(id:in:properties:anchor:isSource:)`](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:)) | “the system will interpolate their frame rectangles in window space to make it appear that there is a single view moving from its old position to its new position.” | iOS 14+, macOS 11+, tvOS 14+, watchOS 7+, visionOS 1+ | 2026-08-13 |
| **SW-106** | [`scrollTransition(_:axis:transition:)`](https://developer.apple.com/documentation/swiftui/view/scrolltransition(_:axis:transition:)) | “Applies the given transition, animating between the phases of the transition as this view appears and disappears within the visible region of the containing scroll view.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ | 2026-08-13 |
| **SW-107** | [`ContentTransition.numericText(value:)`](https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(value:)) | “Creates a content transition intended to be used with Text views displaying numbers.” | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ | 2026-08-13 |
| **SW-108** | [`sheet(isPresented:onDismiss:content:)`](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)) | “Presents a sheet when a binding to a Boolean value that you provide is true.” | iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-109** | [`interactiveDismissDisabled(_:)`](https://developer.apple.com/documentation/swiftui/view/interactivedismissdisabled(_:)) | “Conditionally prevents interactive dismissal of presentations like popovers, sheets, and inspectors.” | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ | 2026-08-13 |
| **SW-110** | [`fullScreenCover(isPresented:onDismiss:content:)`](https://developer.apple.com/documentation/swiftui/view/fullscreencover(ispresented:ondismiss:content:)) | “Presents a modal view that covers as much of the screen as possible when binding to a Boolean value you provide is true.” | iOS 14+, tvOS 14+, watchOS 7+, visionOS 1+ — **no macOS** (Mac Catalyst only) | 2026-08-13 |
| **SW-111** | [`alert(_:item:actions:)`](https://developer.apple.com/documentation/swiftui/view/alert(_:item:actions:)) | “Presents an alert using the given data to produce the alert's content and a text view as a title.” | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ | 2026-08-13 |
| **SW-112** | [`alert(item:content:)`](https://developer.apple.com/documentation/swiftui/view/alert(item:content:)) | “Presents an alert to the user.” | iOS 13+ — **deprecated in the 27.0 releases**, which is why naming this spelling as "SwiftUI's pattern" was wrong | 2026-08-13 |
| **SW-113** | [`confirmationDialog(_:isPresented:titleVisibility:actions:)`](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:)) | “The system may reorder the buttons based on their role and prominence.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ | 2026-08-13 |
| **SW-114** | [`popover(isPresented:attachmentAnchor:arrowEdge:content:)`](https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)) | “On iPhone, popovers adapt into sheets.” | iOS 13+, macOS 10.15+, visionOS 1+ — **no tvOS, no watchOS** | 2026-08-13 |
| **SW-115** | [`ButtonRole.destructive`](https://developer.apple.com/documentation/swiftui/buttonrole/destructive) | “A role that indicates a destructive button.” | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ | 2026-08-13 |
| **SW-116** | [`ButtonRole.cancel`](https://developer.apple.com/documentation/swiftui/buttonrole/cancel) | “A role that indicates a button that cancels an operation.” | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ | 2026-08-13 |
| **SW-117** | [`NavigationStack`](https://developer.apple.com/documentation/swiftui/navigationstack) | “A view that displays a root view and enables you to present additional views over the root view.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ | 2026-08-13 |
| **SW-118** | [`NavigationPath`](https://developer.apple.com/documentation/swiftui/navigationpath) | “A type-erased list of data representing the content of a navigation stack.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ | 2026-08-13 |
| **SW-119** | [`inspector(isPresented:content:)`](https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:)) | “Inserts an inspector at the applied position in the view hierarchy.” | iOS 17+, macOS 14+, visionOS 1+ | 2026-08-13 |
| **SW-120** | [`presentationDetents(_:)`](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)) | “Sets the available detents for the enclosing sheet.” | iOS 16+, **macOS 13+**, tvOS 16+, watchOS 9+, visionOS 1+ — not the iPhone-only feature it is often taken for | 2026-08-13 |
| **SW-121** | [Xcode 26 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes) | “New instruments enhance app analysis with Processor Trace capturing every function call, SwiftUI for view profiling, Power Profiler for battery and thermal analysis, and CPU Counters for identifying performance bottlenecks.” | Xcode 26 (2025) — the release that actually added Processor Trace and CPU Counters | 2026-08-13 |
| **SW-122** | [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes) | “The new Hitches metric replaces the Scrolling metric in the Organizer, now displaying animation hitches for all animations in your app.” “iOS previews have a new Resizable Canvas mode that enables viewing the preview in arbitrarily sized containers.” | Xcode 27 (June 2026). The concurrency addition is a Swift Executors instrument; neither Processor Trace nor CPU Counters appears in these notes | 2026-08-13 |
| **SW-123** | [Previews in Xcode](https://developer.apple.com/documentation/swiftui/previews-in-xcode) | “Generate dynamic, interactive previews of your custom views.” | Xcode tooling, all SwiftUI platforms | 2026-08-13 |
| **SW-124** | [Documenting apps, frameworks, and packages](https://developer.apple.com/documentation/xcode/documenting-apps-frameworks-and-packages) | “makes it easy to produce rich and engaging developer documentation for your apps, frameworks, and packages” | Xcode tooling. `developer.apple.com/documentation/docc` now redirects to swift.org; this is the live Apple page | 2026-08-13 |
| **SW-125** | [Adopting Swift 6](https://developer.apple.com/documentation/swift/adoptingswift6) | “Strict concurrency checking in the Swift 6 language mode helps you find and fix data races at compile time.” | Swift 6 language mode, opt-in | 2026-08-13 |
| **SW-126** | [Backyard Birds sample](https://developer.apple.com/documentation/swiftui/backyard-birds-sample) | “Create an app with persistent data, interactive widgets, and an all new in-app purchase experience.” | Apple sample code, live on the date checked | 2026-08-13 |
| **SW-127** | [Food Truck sample](https://developer.apple.com/documentation/swiftui/food-truck-building-a-swiftui-multiplatform-app) | “Create a single codebase and app target for Mac, iPad, and iPhone.” | Apple sample code, live on the date checked | 2026-08-13 |
| **SW-128** | [Fruta sample](https://developer.apple.com/documentation/appclip/fruta-building-a-feature-rich-app-with-swiftui) | “Create a shared codebase to build a multiplatform app that offers widgets and an App Clip.” | Apple sample code; it now lives under the App Clips framework path rather than SwiftUI's | 2026-08-13 |
| **SW-129** | [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui) | “Present an alert or confirmation dialog from an optional data item or error object, and use that data to produce the content and title” | The June 2026 section — the release that pairs with Xcode 27 and the 27.0 OSes, and the one that added reorderable containers and container-wide swipe actions | 2026-08-13 |
| **SW-130** | [`CircularProgressViewStyle`](https://developer.apple.com/documentation/swiftui/circularprogressviewstyle) | “A progress view that uses a circular gauge to indicate the partial completion of an activity.” “On watchOS, and in widgets and complications, a circular progress view appears as a gauge with the `accessoryCircularCapacity` style. If the progress view is indeterminate, the gauge is empty.” “**In cases where no determinate circular progress view style is available, circular progress views use an indeterminate style.**” | iOS 14+, iPadOS 14+, Mac Catalyst 14+, macOS 11+, tvOS 14+, watchOS 7+, visionOS 1+. That last sentence is Apple’s own: the circular style is **not guaranteed to be determinate**, which is why LuauUI cites its determinate ring against `Gauge` ([SW-131]) instead. Read from the JSON twin (`developer.apple.com/tutorials/data/documentation/…json`), the route §16 documents for a page that renders client-side | 2026-08-13 |
| **SW-131** | [`GaugeStyle.accessoryCircularCapacity`](https://developer.apple.com/documentation/swiftui/gaugestyle/accessorycircularcapacity) | “A gauge style that displays a closed ring that’s partially filled in to indicate the gauge’s current value.” “This style displays the gauge’s `currentValueLabel` value at the center of the gauge.” | iOS 16+, iPadOS 16+, Mac Catalyst 16+, macOS 13+, watchOS **9**+, visionOS 1+ — **no tvOS**. (Note the watchOS floor: [SW-55]’s `GaugeStyle` row says watchOS 7+ for the protocol; this style is 9+.) The second sentence is the one LuauUI’s `showValue` refusal answers — Apple centres the readout INSIDE the ring, on a complication-sized dial | 2026-08-13 |
| **SW-132** | [`AsyncImage`](https://developer.apple.com/documentation/swiftui/asyncimage) | “A view that asynchronously loads and displays an image.” “Until the image loads, the view displays a standard placeholder that fills the available space.” “If you use an Image as a placeholder view and it doesn’t load, SwiftUI doesn’t show anything as a placeholder and doesn’t report an error.” “In iOS 27, macOS 27, watchOS 27, tvOS 27, and visionOS 27 and later, AsyncImage caches downloaded image data following the transport protocol.” | iOS 15+, iPadOS 15+, Mac Catalyst 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+. The transport-level cache is a 27.0-release addition, i.e. newer than the whole rest of the symbol | 2026-08-13 |
| **SW-133** | [`compositingGroup()`](https://developer.apple.com/documentation/swiftui/view/compositinggroup()) | “Wraps this view in a compositing group.” “A compositing group makes compositing effects in this view’s ancestor views, such as opacity and the blend mode, take effect before this view is rendered.” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-134** | [`drawingGroup(opaque:colorMode:)`](https://developer.apple.com/documentation/swiftui/view/drawinggroup(opaque:colormode:)) | “Composites this view’s contents into an offscreen image before final display.” “The drawingGroup(opaque:colorMode:) modifier flattens a subtree of views into a single view before rendering it.” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. The word that separates it from [SW-133] is *offscreen image* — a rasterization, not a grouping | 2026-08-13 |
| **SW-135** | [`keyboardType(_:)`](https://developer.apple.com/documentation/swiftui/view/keyboardtype(_:)) | “Sets the keyboard type for this view.” “A number of different keyboard types are available to meet specialized input needs, such as entering email addresses or phone numbers.” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, tvOS 13+, visionOS 1+ — **no macOS, no watchOS** | 2026-08-13 |
| **SW-136** | [`EnvironmentValues.accessibilityReduceTransparency`](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency) | “Whether the system preference for Reduce Transparency is enabled.” “If this property’s value is true, UI (mainly window) backgrounds should not be semi-transparent; they should be opaque.” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. There is no `View/accessibilityReduceTransparency` — the capability is an environment value only, which is why the LuauUI comparison is against an environment key rather than a modifier | 2026-08-13 |
| **SW-137** | [`onSubmit(of:_:)`](https://developer.apple.com/documentation/swiftui/view/onsubmit(of:_:)) | “Adds an action to perform when the user submits a value to this view.” “You may set this action on an individual view or an entire view hierarchy.” | iOS 15+, iPadOS 15+, Mac Catalyst 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ | 2026-08-13 |
| **SW-138** | [`onAppear(perform:)`](https://developer.apple.com/documentation/swiftui/view/onappear(perform:)) | “Adds an action to perform before this view appears.” “The exact moment that SwiftUI calls this method depends on the specific view type that you apply it to, but the action closure completes before the first rendered frame appears.” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-139** | [`onDisappear(perform:)`](https://developer.apple.com/documentation/swiftui/view/ondisappear(perform:)) | “Adds an action to perform after this view disappears.” “The exact moment that SwiftUI calls this method depends on the specific view type that you apply it to, but the action closure doesn’t execute until the view disappears from the interface.” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. **Apple documents no behaviour here** for scene or window teardown — the page says only that the closure runs after the view disappears, never whether tearing down the host runs it | 2026-08-13 |
| **SW-140** | [`hidden()`](https://developer.apple.com/documentation/swiftui/view/hidden()) | “Hides this view unconditionally.” “Hidden views are invisible and can’t receive or respond to interactions. However, they do remain in the view hierarchy and affect layout.” “If you want to conditionally include a view in the view hierarchy, use an if statement instead” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+. There is **no** `hidden(_:)` overload taking a Boolean — the unconditional signature is the whole API, which is why the LuauUI prop being bindable is a widening rather than a copy | 2026-08-13 |
| **SW-141** | [`opacity(_:)`](https://developer.apple.com/documentation/swiftui/view/opacity(_:)) | “Sets the transparency of this view.” “When applying the opacity(_:) modifier to a view that has already had its opacity transformed, the modifier multiplies the effect of the underlying opacity transformation.” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
| **SW-142** | [`disabled(_:)`](https://developer.apple.com/documentation/swiftui/view/disabled(_:)) | “Adds a condition that controls whether users can interact with this view.” “The higher views in a view hierarchy can override the value you set on this view.” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-13 |
