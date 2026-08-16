# SwiftUI ↔ LuauUI: what LuauUI has, what it doesn't

LuauUI is a declarative UI framework for Roblox. SwiftUI is the most complete
declarative UI framework in wide production use, so it is the yardstick this
document measures against — capability by capability, with a citation on every
verdict.

The point is not a score. The point is that a developer, or an agent, picking up
LuauUI can find out in one read whether the thing they need exists, exists with
caveats, or does not exist at all — and, where LuauUI and SwiftUI genuinely
differ, why.

The rest of the document is row-by-row detail. This first section is not: it is
the shape of the thing, in plain language, before any table.

---

## Two frameworks, in plain language

**Read this if you have never used either.** It answers one question — *what kind
of thing is LuauUI, and how does its thinking differ from SwiftUI's?* — without
assuming you know what a view modifier or a solver is. If you already write
SwiftUI, this is the part that tells you which of your instincts will not
transfer.

### What both frameworks are

You do not build the screen. You **describe** it — "a column holding a title and
three buttons, and the third one is disabled right now" — and the framework works
out what to create, move, repaint, and delete so the real screen matches the
description. When your data changes you change the description, never the screen.
That is what "declarative" means, and both frameworks are that.

Everything below is a difference *inside* that shared idea, and most of the
differences trace back to one fact about the platform: **LuauUI does not own the
screen it draws on.** It drives real Roblox `GuiObject`s, and those objects are
written to by other authors at the same time.

### One writer per property, because the engine will not police it

A Roblox screen object is written to by more than one author: Roblox's own
StyleSheets, the player's CoreGui, engine defaults, and any game code that
happens to reach in. Two writers on one property is not a disagreement to be
resolved with a precedence rule — it is a bug that leaves no trace. Measured in
Studio: **an explicit property write silently defeats a StyleSheet rule and fires
no signal.** Nothing tells you it happened, and the rule never comes back.

So LuauUI keeps a manifest — `src/render/authority.luau` — that names, for every
engine property of every class, the **one** part of the framework allowed to
write it. Rects are written by layout. Token paint is written by style. A
data-driven colour is written by binding. A transient fade or slide is written by
presentation. Every write in the framework goes through one site, and that site
checks the manifest.

That constraint sounds bureaucratic until you watch it decide an API. `opacity`,
`scale` and `rotation` are all authorable — things you would expect any UI
framework to let you set — and none of them is a second writer, because the
framework is often already animating the same property. The authored value is a
second **term** inside the one writer's arithmetic instead: the engine gets
`compose(what the framework is doing, what you asked for)`, resolved at a single
write site, and **nothing writes an engine property called "opacity" at all**
([`ADR-0026`](../adr/ADR-0026-authored-presentation-composition.md)). The manifest
asks how many *functions* may write a property. It never asks how many *facts*
that one function may read.

The same rule is why `UI.Text{ opacity = 0.4 }` is a construction error. To
compose you need a base term — the value the style rule would otherwise have
produced — and the only way to read one is `Instance:GetStyled(prop)`, which
**returns your own last write** from the first composition onward. Measured
2026-08-15: a leaf recomposing on each state change multiplied its own output
back in and faded to invisible after four disable/enable cycles. So the act of
composing destroys the input the composition needs, and the fade is refused with
the one line that does work —
`UI.ZStack{ opacity = 0.4, children = { … } }`
([`ADR-0029`](../adr/ADR-0029-leaf-opacity-refusal.md)). That happens to be
SwiftUI's answer too: without a compositing group, ancestor opacity applies per
descendant, which is exactly what `compositingGroup()` exists for ([SW-133]).

### A refusal, where another framework would guess

The second habit follows from the first. **Where a value could plausibly mean two
things, LuauUI raises at construction and names the alternative, instead of
picking the reasonable one.** The stated reason is that a silent reinterpretation
is a defect the author cannot see: the screen looks nearly right, and nothing
anywhere says which of the two meanings was chosen.

Five shipped examples, each a real error message rather than a policy:

- `presentation = "spinner"` **with a `height`** — `height` is the *bar's* track
  thickness. On a spinner it would have to silently become the dot's size, which
  is a theme metric, so it is refused instead (§5).
- **`virtualized` beside `rowActions` on a `Table`** — Table wraps each swipeable
  row in its own composite whose lifetime is pruned by the data, so a row
  scrolling out of the window would strand a live gesture engine. The message
  names the control that does support the combination (§4.2.1).
- **`align = "stretch"` on a wrapping stack** — it would mean "each child fills
  its line" and "the block of lines fills the box" at once, and there is no
  honest way to pick (§4.3).
- **An inline spring literal** at a call site — springs must come from one of four
  registered motion classes, or a design system drifts one call site at a time
  (§8).
- **`UI.Text{ opacity }`**, above — and note the shape of that message. It does
  not say "unknown property". It says which engine property carries a fade, which
  two classes can be one, what breaks if you force it, and the one-line wrap.

The cost is real and worth knowing before you start: **you cannot try something
and see what happens.** Passing a property that the framework has thought about
and declined gets you an error with a route, not a silent no-op. Passing one it
has never heard of gets you *"unknown property 'lable'. Did you mean 'label'?"*
plus the full legal set. There is very little middle ground where a screen
quietly does the wrong thing — which is the trade this framework makes on
purpose, and it is a different trade from a framework that optimizes for the
first five minutes.

### The engine is a fact to be measured, not a fact to be assumed

A large part of this framework's design is the residue of *asking the engine*
where its documentation is silent — and Roblox's is silent, or wrong by
omission, in several of the places that matter most here. Four measured readings,
each of which changed an API:

- **Roblox has no overlay scrollbar.** The engine shrinks the scrollable window
  by the bar's thickness whatever the bar paints. A policy that treats a
  fading touch indicator as free therefore lays every scroller's content out into
  a box 8 px wider than the one the player can see: measured live,
  `AbsoluteSize` 703×203 against `AbsoluteWindowSize` 695×203, nine nodes painted
  past an invisible edge, a value reading "0.35" clipped to "0.3". So the reserve
  is always taken, on every platform, whatever the bar looks like (§4).
- **Input goes to the topmost interactive object, and only that one.** The
  plausible assumption is the opposite — that every Active object under the point
  receives the event independently of paint order — and it is false. A
  `GuiButton` sinks the input and a hit surface behind it receives nothing, which
  is why a row whose content holds a button cannot be swiped where that button
  covers it.
- **A `Path2D` is not a `GuiObject`.** No stylesheet rule can select one, no
  image layer can follow a partial arc, and clipping does not crop it. That is
  why the circular progress ring takes a colour and two metrics from a theme and
  no art at all, and why a ring scrolled out of a clipping host still paints
  (§6.1).
- **Reading a styled property returns your own last write** — the fact under the
  leaf-fade refusal above.

The rule that produces those readings is a standing one: check the platform's
*current* documentation first, and where the documentation does not answer,
measure the running engine rather than reason from the code. Each reading is
written down at the place in the source that depends on it, with its date and its
numbers, so the next author can re-run it instead of re-deriving it.

### Layout is decided before anything is drawn

SwiftUI's layout vocabulary is a negotiation described in terms of *proposals* —
`ViewThatFits` "selects the first child whose ideal size on the constrained axes
fits within the **proposed** size" ([SW-22]) — and its extension point is a
`Layout` protocol, "a type that defines the geometry of a collection of views"
([SW-24]).

LuauUI splits the same job into two pieces that never touch each other:

| | |
|---|---|
| **The solver** | Measures the description, then arranges it into plain rectangles. No engine object is involved, so the whole of layout runs headlessly in a terminal. |
| **The adapter** | Takes those rectangles and paints them onto real Roblox instances. It is a swappable seam with a written contract, which is why the solver can be tested with no Roblox running at all. |

Three consequences a reader should carry into the tables:

- **The instance tree is deliberately flat.** Objects are not parented to their
  container unless something (clipping, a fade group) requires it. Every node is
  positioned by an absolute rectangle the solver computed. That is why a
  container moving carries nothing inside it — and it is why animating a *move*
  has to accumulate offsets down the subtree while animating a *size* must not
  (§8.1).
- **Changing the theme is a re-solve, not a rebuild.** Nothing is torn down, so
  mount identity, focus, scroll position, selection and half-typed text all
  survive a theme swap (§6).
- **And a re-solve does not repaint** — the hazard that sits directly under that
  feature. A theme commit re-derives everything the *solver* reads and nothing
  the *adapter* paints, because a colour is not a layout. Most paint survives
  anyway because a stylesheet rule owns it and the sheet is swapped wholesale.
  The exceptions are exactly the paints **no rule can express**: a focus ring is
  a bespoke child, a rule cannot see a *value*, and a `Path2D` cannot be selected
  at all. Each of those needs an explicit repaint sweep of its own, and when one
  is missing nothing complains — the node simply keeps the outgoing theme's
  colour, and a person has to notice.

### What LuauUI deliberately is not

The document's credibility rests on this part, so it is up front rather than at
the end. Some of these are decisions and some are simply holes, and the
difference is stated in each case:

- **There is no assistive-technology bridge of any kind.** Nothing talks to a
  screen reader. A blind player cannot use a LuauUI interface. That is a hole,
  not a decision (§7).
- **There is no right-to-left or bidirectional support** anywhere in layout or
  text (§7).
- **There is no screen-to-screen navigation model** — no push, no pop, no back
  button, no titles. Surfaces stack; screens do not (§9).
- **There is no way to swap what a control renders as while keeping its
  behaviour** — no `ButtonStyle`-shaped protocol. *This one is a decision*:
  native Roblox StyleSheets and theme packages own paint, and a parallel
  rendering-substitution protocol would be a second authority over the same
  pixels — the thing the first part of this section is about. §6.1 carries the
  mapping a SwiftUI author needs instead, including the residue it costs.
- **Nothing here has ever run on a physical device.** Every claim in this
  document is a headless test run or a scripted drive of Roblox Studio's
  emulator (§14).

### Where it goes further than SwiftUI

Three places, and in each the reason is the platform rather than ambition.

**A screen declares its content once, and the framework arranges it.** Instead of
writing "if the screen is short, drop the header", an author declares *ranked
regions*, each carrying an ordered ladder of forms from richest to
minimum-viable; the framework tests arrangements and steps a region down its
ladder — or drops it entirely, lowest rank first — until everything fits. That is
closer to a `Layout` protocol ([SW-24]) plus `layoutPriority` ([SW-13]) combined
than SwiftUI ships in any single construct, and the practical result is that none
of the five reference apps (§12) contains a device-name branch anywhere.

**A property that is accepted has to do something.** Nine placement properties are
legal on every node but only read by particular parents. Rather than let one sit
inert, the solver audits every (parent, property) pair the parent will never read
and files a complaint you can query at runtime. The same diagnostics channel
reports overflow, unbounded percentages, mixed grid children, HUD zone collisions
and two surfaces painting over each other. LuauUI's answer to "this looks nearly
right" is a machine-readable complaint rather than a screenshot review, and
neither SwiftUI nor Roblox ships an equivalent inert-property audit ([SW-10]).

**It is built to be maintained by agents as well as by people.** Unknown
properties are refused with a did-you-mean and the full legal set; the public
constructor surface is typed; and a family of checkers reconciles independent
views of the same truth so that documentation, the export table, property
authority, and the tests cannot drift apart without something going red (§11).
The honest limit of that machinery is stated in the same place: **it catches a
missing symbol, never a false paragraph.**

### If you are arriving from somewhere else

**From SwiftUI**, the four things most likely to surprise you: state is tracked
per *value* rather than per view, so there is no one-annotation-per-model-class
shape like `@Observable`'s ([SW-03], §3); there is no navigation stack (§9);
there is no `*Style` protocol, and theming is the answer instead (§6.1); and a
property the framework has considered and declined raises an error naming the
route rather than doing something reasonable.

**From ordinary Roblox UI code**, the four that matter: you never mutate an
instance, you change a description; declaration order is the only order, because
there is no `LayoutOrder` analogue (§4); the framework's layout vocabulary is a
strict superset of `UIListLayout` + `UIFlexItem` in every respect but that one
(§4.1); and anything the engine will not let the framework prove — haptics
playback, physical-device performance, the arrow keys under a live camera — is
labelled as unproven here rather than rounded up.

---

## 1. What this document is, and how to read it

### The four verdicts

Each area below opens with a few sentences of plain framing, then a table of
capabilities, then the caveats that did not fit in a table cell.

| Verdict | Means |
|---|---|
| **Covered** | A first-class equivalent ships, is exported, and its conformance tests pass. |
| **Partial** | It ships and works, but with named behaviour gaps a consumer will hit. |
| **Composable** | Not a shipped construct, but buildable today from the public surface with no framework change. The recipe is named. |
| **Missing** | No construct and no honest recipe. Where the Roblox engine is the reason, that is said. |

Two rules keep those verdicts from inflating:

1. **A control that works on only some input devices is Partial at best.** LuauUI
   targets mouse, touch, keyboard, and gamepad; "a control that only works with a
   mouse is an unfinished control." Being *reachable* on all four is also not
   enough — if the control does not behave the way that device's users expect
   (a slider you can only jump-to-value with a gamepad, never nudge), it stays
   Partial. ([`ADR-0016`](../adr/ADR-0016-three-axes-contract.md), `ui_todo.md`)
2. **Nothing in LuauUI has been confirmed on physical hardware.** Every
   four-input claim in this document rests on headless test runs plus scripted
   drives of the Roblox Studio device emulator. §14 lists what a human with a
   real phone, keyboard, and gamepad still needs to check.

### This document covers a bounded catalog — read this before you trust a silence

**A capability that is absent from this document was not necessarily
considered.** That sentence is the most important one in §1.

The four verdicts are *findings*: **Missing** means we looked and we do not have
it. But a SwiftUI capability that never entered the catalog at all is neither
Covered nor Missing — it is **unexamined**, and from inside this document the two
are indistinguishable. A reader who looks up rich text, scroll snapping, or
`Form` finds nothing here and could reasonably conclude those were weighed and
judged irrelevant. They were simply never weighed.

A completeness audit measured that bound
([`../plans/parity-completeness-audit-2026-08-13.md`](../plans/parity-completeness-audit-2026-08-13.md)).
Against Apple's own editorial groupings — 365 scored capability groups across 49
SwiftUI collection pages — this document has **examined 127**. Of the remainder,
120 have no Roblox substrate to bind to (OS windows, Apple frameworks, UIKit
interop, Apple-only input devices), 54 are applicable but deliberately out of
scope, and **64 are genuinely unexamined**, deduplicating to **39 named
capabilities**.

The blind spots are not randomly scattered, which is the useful part. Four
collections supply 19 of the 64: [scroll
views](https://developer.apple.com/documentation/swiftui/scroll-views) (6
unexamined of 12), [view
groupings](https://developer.apple.com/documentation/swiftui/view-groupings) (5
of 7), [preferences](https://developer.apple.com/documentation/swiftui/preferences)
(**5 of 5** — the largest single hole), and [custom
layout](https://developer.apple.com/documentation/swiftui/custom-layout) (3 of
4). That is the shape of a framework built control-first and layout-first, where
scroll *behaviour*, *grouping semantics* and *extension points* were never their
own areas.

So: **strength in the areas below is real; silence outside them is not
evidence.** Where a gap has been examined it carries a verdict like anything
else. The audit found no *false* row — every one of its findings was an absence,
which is the failure mode a catalog has and a checker cannot see.

There is a second yardstick, and §4.1 uses it: **Roblox's own layout controls.**
SwiftUI parity says nothing about whether LuauUI is worth using *on this
platform*. The standing bar from the director is that LuauUI must do **more**
than `UIListLayout`/`UIFlexItem`, never less, so §4.1 states where it is a
superset and where it is not.

### Every claim about SwiftUI carries a citation

Claims about *our* side are guarded by checkers: `check_docs`,
`check_prop_parity`, `check_registration`, `check_surface_ledger`,
`check_boundary`. Nothing guards the other side, which is the side the whole
comparison rests on — and an uncited comparison is how a document ends up naming
an API after a SwiftUI symbol that does not exist.

So: a row that says what SwiftUI does, when it does it, what a modifier means, or
which platforms ship it, carries a bracketed id — `[SW-16]` — resolved in **§16**,
where each id gives the page, the sentence the claim rests on quoted verbatim,
the availability Apple states, and the date the page was read. A row that merely
*names* a SwiftUI type with no assertion about its behaviour attached carries
none: a citation on "SwiftUI has `HStack`" is noise. Where Apple documents
nothing, the row says so in those words and names what the claim rests on
instead — an unsupported citation is worse than none, because it looks checked.
`check_docs` enforces that every such row is cited and that every citation
carries a URL, a quote and a date. No checker can enforce that a quote is still
true.

**The dates are load-bearing.** Every citation is dated `YYYY-MM-DD`. SwiftUI
ships once a year, in June. If you are reading this after a June later than the
dates in §16, treat every SwiftUI-side claim here as *unverified* rather than as
wrong — open the URL, and if the page still says what §16 quotes, move the date.

### Vocabulary you need for the rest of the document

LuauUI's terms, in SwiftUI terms where an analogue exists:

| LuauUI term | What it is |
|---|---|
| **Blueprint** | The tree of plain Lua tables describing what should be on screen — LuauUI's equivalent of a SwiftUI `View` body. `UI.VStack{ UI.Text{...} }`. |
| **Signal** / **Memo** | The reactive primitives. A signal is a mutable observed value (`@State`); a memo is a derived, cached value (`computed`). Tracking is per-value, not per-view. |
| **Solver** | The layout engine. It measures the blueprint, then arranges it into rectangles. Runs headlessly, with no engine objects involved. |
| **Renderer** / **target** | The layer that turns solved rectangles into real Roblox `GuiObject` instances. Swappable — that is why the solver can be tested with no Roblox running. |
| **Presenter** | The layer that owns on-screen surfaces (screens, modals, popovers, toasts) and their focus, layering, and dismissal rules. |
| **Surface** | One independently mounted tree with its own controller and its own solve. A HUD, a modal and a toast layer are three surfaces. |
| **Composite** | A shipped, exported, tested control assembled from primitives — `LuauUI.newSlider`. The opposite of a "recipe" the consumer writes by hand. |
| **Four-input proof** | An automated conformance test asserting a control is genuinely operable with mouse, touch, keyboard, *and* gamepad. |
| **Gate** | A named CI check that must pass before a piece of work is considered landed. |
| **Evidence level** | How a claim was verified: **E1** headless test run, **E3** Roblox Studio device emulator, **E4** physical hardware. No E4 evidence exists. |
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
same job. The layout vocabulary is a strict superset of Roblox's own flex
controls in every respect but one deliberate divergence (§4.1). `withAnimation`
ships and interpolates everything a commit produces plus the three authored paint
values (§8.1). One collection class — `newTable` — now unifies windowing,
reordering and multi-selection (§4.2.1).

The gaps that remain are structural rather than incidental:

- There is **no assistive-technology bridge at all**. Nothing in LuauUI talks to
  a screen reader; a blind player cannot use a LuauUI interface. This is the
  largest gap in the document and the one least mitigated by anything else in it.
- There is **no right-to-left or bidirectional** layout or text support anywhere.
- There is **no screen-to-screen navigation model**, only surface stacking. No
  push/pop, no back button, no titles, no deep links.
- There is **no way to swap what a control renders as while keeping its
  behaviour** — no `ButtonStyle`-style protocol. That is a *decision*, not an
  omission: native Roblox StyleSheets and theme packages own paint, and §6.1
  carries the mapping a SwiftUI author needs instead.
- There is **no translucent-material system**, and Apple's Liquid Glass —
  shipped across the 26 releases and still the current material system a year
  later ([SW-74], [SW-76]) — has widened that gap rather than narrowed it.

On performance the framework has deep headless instrumentation, executable
regression budgets, and real shipped wins: incremental layout, instance
recycling, inert-container elision, and a windowed rich table. **The unavoidable
caveat is that none of it has ever run on a physical device.** Where a verdict
here is generous, the caveat is in the same section, not buried.

**Verdict counts across §§3–11**, so the shape of the answer is visible before
the detail: **175 capability rows — 110 Covered, 34 Partial, 4 Composable, 26
Missing**, plus one scored as having no host equivalent by design. Twenty-one of
those rows are additionally marked as having *no equivalent on the other side* —
Roblox-specific or LuauUI-specific capabilities the comparison cannot score in
either direction.

A count is not a score. The Missing rows include the three that matter most
(assistive technology, navigation, materials), the Covered ones include several
that are one Roblox primitive wrapped honestly, and §1 explains why the
denominator is a bounded catalog rather than all of SwiftUI.

---

## 3. State & data flow

This is LuauUI's strongest area. Where SwiftUI invalidates a view and recomputes
its `body` — Apple documents the *effect*, that it "automatically updates the
affected parts of the interface", and nowhere documents body re-execution and
diffing as the mechanism ([SW-04]) — LuauUI tracks dependencies per *value*: a
signal read inside a memo subscribes that memo to that signal alone. That makes
invalidation finer-grained than SwiftUI's, at the cost of SwiftUI's whole-object
ergonomics — there is no `@Observable`-style "mark the model, forget about it"
macro, and two-way binding is a convention (pass the signal down) rather than a
type.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `@State` — owned, per-instance mutable value ([SW-01]) | **Covered** | `core:signal`, a fine-grained observable value rather than a per-view struct field | `src/core/custom.luau`; `src/core/contract.luau`; test `signal-read-write` (`tests/conformance/suite.luau`) |
| `@Binding` — two-way reference to caller-owned state ([SW-02]) | **Covered by convention, not by type** | A control simply takes the caller's `Signal` and writes to it. There is no projection/wrapper type; misuse is caught at write time by a runtime assertion, not at authoring time | `src/controls/value_model.luau` |
| `@Observable` — auto-tracked property access ([SW-03]) | **Partial** — finer-grained, not object-shaped | Tracking is per-signal/per-memo via `use()`. You get precision SwiftUI does not have; you do not get "one annotation on a model class" | `src/core/custom.luau`; test `dynamic-dependencies-swap-atomically` |
| Derived/computed state | **Covered**, glitch-free | `core:memo`, eager-stale marking plus pull-based recompute, so a diamond dependency never fires an observer twice with inconsistent inputs | `src/core/custom.luau`; tests `memo-derives-and-updates`, `glitch-free-diamond`, `no-spurious-fire-on-unchanged-recompute` |
| Transactions (`withTransaction`) ([SW-06]) | **Covered** as pure write-batching | Many writes, one observer fire; a reverted transaction fires nothing. `Core` exposes `transaction(body)` and nothing else — there is no per-signal write hook and no public `inTransaction()`, which is why `withAnimation` (§8) has to probe rather than ask | `src/core/custom.luau`; `src/core/contract.luau` |
| `withAnimation` — wrap a state write, downstream reads interpolate ([SW-05]) | **Covered** | `presenter.withAnimation(class, fn)`. See §8.1 for exactly what it does and does not animate | `src/present/presenter.luau`; `tests/with_animation.spec.luau`; `docs/reference/api.md` §`presenter.withAnimation` |
| `onAppear(perform:)` ([SW-138]) / `onDisappear(perform:)` ([SW-139]) — run code as a view enters and leaves | **Covered** | `onAppear` / `onDisappear` are shared box props on **every** rendered class, each called with the node's path. **The lifetime measured is the rendered one, not the mounted one** — a virtualized row that scrolls out of its window disappears, and a subtree still playing its exit transition has not — which is the answer Apple's own pages decline to give: "The exact moment that SwiftUI calls this method depends on the specific view type that you apply it to" ([SW-138], [SW-139]). LuauUI's two ordering rules are exact instead: **appear fires after that frame's layout solve**, so the callback can read its own rect, and still before anything reaches the screen (a refresh is one synchronous call) — Apple's guarantee is the weaker "the action closure completes before the first rendered frame appears" ([SW-138]); **disappear fires after the render instance is released**, so `rectOf(path)` is already `nil` inside the callback. Teardown fires every still-mounted hook, so a cleanup is never silently dropped — Apple documents nothing about window or scene teardown here ([SW-139]). Not reactive: a lifetime is not a value that changes, and the OLD closure is the one that has to run when the node leaves | `src/blueprint_schema.luau` (`onAppear`/`onDisappear` in the shared box group); `src/render/renderer.luau` (queued at mount, drained after the solve; queued in the removal sweep, drained after it); `tests/lifecycle_hooks.spec.luau`; fixture `examples/gallery/scenarios/lifecycle_hidden.luau` |
| Cycles / self-referential derivation | **Covered** — reported, not hung | A dependency cycle raises with a readable error instead of recursing | `src/core/custom.luau`; test `cycle-reported-not-hung` |
| Writing state during a derivation | **Covered** — refused | Illegal by construction, not by convention | `src/core/custom.luau`; test `write-during-memo-is-error` |
| `.task` — async work scoped to view lifetime ([SW-07]) | **Partial**, with stronger cancellation than SwiftUI | `LuauUI.newResourceProvider` gives scope-owned handles and generation-counter stale-completion rejection: a slow request that returns after its owner changed identity is discarded rather than applied. Bounded, spaced retry. SwiftUI's own guarantee is that it cancels the task when the view goes away or changes identity ([SW-07]); what is added here is refusing a stale result that *completed*. Not a `.task`-shaped modifier, though | `src/async/resources.luau` |
| `@Environment(\.foo)` — implicit value propagation ([SW-08]) | **Covered** | Per-key signals with derived memos on top, so a keyboard-occlusion change cannot invalidate a subscriber that only reads colours. Widely consumed (`themeMetrics`, `effectiveInput`, `interactionClasses`, `typographyScale`, `preferredTextOffset`, `platformChrome`, and more) | `src/env/environment.luau` |
| Environment values that clamp/default bad input | **Covered** | `typographyScale`, `effectiveTransparency`, `effectiveOverscanInsets` all sanitize rather than propagate garbage | `src/env/environment.luau` |
| `ForEach(id:)` / `.id()` — identity and structural diffing ([SW-09]) | **Covered**, closer to `ForEach` than to whole-tree diffing | Adds, removes, and moves only; duplicate keys are a hard error. A row removed and re-added *while its exit animation is still playing* resumes the same mounted subtree, scope, and instances rather than remounting. **Apple documents no behaviour here** — nothing on the `ForEach` page says what happens to an element removed and re-added mid-transition ([SW-09]) — so read that as a LuauUI guarantee, not as a win over a documented rule | `src/mount.luau` |
| Instance reuse below `ForEach`/`When` | **Covered** — no direct SwiftUI analogue ([SW-34]) | A recycling pool keyed by node shape hands a retiring node's Roblox instances to the next node that needs the same shape, instead of destroy-then-create. Pool cap 64 | `src/render/renderer.luau`; `tests/instance_park_corpse.spec.luau` |
| Ownership scopes / disposal | **Covered**; Apple documents no disposal or ownership contract to be stricter *than* ([SW-10]) | Reverse-order idempotent dispose, double-dispose detection, and a releasability check at registration time — `scope:own()` raises immediately if handed something with no `dispose()`. Cleanup errors are quarantined, not propagated | `src/core/scope_impl.luau` |
| Runaway-effect protection | **Covered** — no public SwiftUI equivalent ([SW-10]) | A feedback loop between effects is capped and reported rather than hanging the client | `src/core/custom.luau`; test `feedback-loop-hits-iteration-cap` |
| A subtree that throws takes itself down, not the screen | **Covered** — no SwiftUI equivalent ([SW-10]) | `UI.ErrorBoundary{ view, fallback }`: an error raised while building or rebuilding the subtree swaps to `fallback(err)` instead of failing the surface. An error inside the *fallback* stays hard, deliberately — a fallback that can itself fail has no floor | `src/blueprint.luau` (`ErrorBoundary`) |

**Caveats.**

- `withAnimation` closes the *ergonomic* half of the interpolation problem but
  not all of it. It animates a node's **position and size** because its box
  changed, and the three authored paint values; it does not retrofit
  interpolation onto an arbitrary bound *value*. A number that must count rather
  than jump still has to be a `MotionValue` (§8).
- `lastError()` on the core is sticky and cannot be reset. You can ask a
  long-lived core "were you ever in a quarantined state", but not "are you
  healthy right now."
- Application code is **not meant to read the raw `sizeClass` environment key**.
  One policy module owns it (`src/layout/adaptive.luau`) and exposes the derived
  helpers callers actually use — `axisFor`, `columnsFor`, `navPlacement`,
  `conditions()` — and those are consumed throughout, by all five reference apps
  (§12). Two controls (`popup_button`, `picker`) take a size class in as a spec
  parameter rather than reading the key. Read that as "one policy module owns
  this key", not as "almost nothing adapts to screen size."

---
## 4. Layout

LuauUI's solver is a headless, testable measure-then-arrange pass over the
blueprint, with weighted flexbox-style stacks, three grid modes, a `ViewThatFits`
equivalent, flow-wrapping stacks, and safe-area insets.

Two things here go beyond SwiftUI. The first is `UI.Composition`/`UI.Region`,
where a screen declares its content once as a set of *ranked regions*, each
carrying an ordered ladder of forms from richest to minimum-viable; the framework
then tests arrangements and steps a region down its ladder — or drops it
entirely, lowest rank first — until everything fits. That is closer to a full
`Layout` protocol ([SW-24]) plus `layoutPriority` ([SW-13]) combined than SwiftUI
ships in any single construct, and it means no screen contains a device-name
branch. The second is incremental layout: a single changed bound value re-solves
only the smallest enclosing subtree it can affect, not the whole tree.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `HStack`/`VStack` core (weighted, aligned, with margins) | **Covered** | Weighted `fill` distribution with largest-remainder rounding, container `align`, per-child `margin`, `gap`, `Spacer` main-axis fill, `distribute`, a real shrink pass, and a wrapping mode (the next four rows) | `src/layout/solver.luau` |
| Main-axis distribution — SwiftUI has **no prop for this** ([SW-11]) and needs hand-placed `Spacer`s ([SW-12]) | **Covered, and wider than SwiftUI's** | `distribute = "start" \| "center" \| "end" \| "spaceBetween" \| "spaceAround" \| "spaceEvenly"` on `HStack`/`VStack`/`AdaptiveStack`/`Screen`, default `"start"`. It closes a case a static `Spacer` recipe cannot reach at all: a variable-count child list goes through `UI.ForEach`, whose `row` returns exactly one blueprint, so separators cannot be interleaved on the parent's main axis. A tab bar whose tab count varies is otherwise inexpressible. `distribute ~= "start"` while `fill` children have already eaten the remainder is a **diagnostic**, not a silent no-op | `src/blueprint_schema.luau` (enum, four hosts); `src/layout/solver.luau` (arrange + conflict diagnostic); `tests/stack_distribution.spec.luau` |
| `layoutPriority` — who shrinks first when over-committed ([SW-13]) | **Covered, and wider than SwiftUI's** | `layoutPriority` (default `0`) is the **outer sort** — tiers consumed lowest-first, SwiftUI's model, which Apple states as a rule about the *lowest* tier: the parent offers the highest-priority children everything except the minimum its lower-priority children need ([SW-13]). `shrinkWeight` (default `0`) is the **inner** one — proportional to `weight × basis` inside a tier, which is CSS's `flex-shrink` and Roblox's `UIFlexMode`, and which SwiftUI has no equivalent of; `layoutPriority` is the only shrink dial its documentation offers ([SW-13]). Both default inert (`shrinkWeight = 0` is exactly `Enum.UIFlexMode.None`). Floors are `minMax.min` → a text node's minimum wrap width → `0`. The pass runs in **both** solver passes: arrange negotiates against the real rect, and the measure branch runs the same negotiation whenever the *offer* is already too small — without that, a label squeezed to its floor wraps onto lines nobody reserved, the "painted at a size nobody measured" family. `Composition.rank` is adjacent but not equivalent: it drops or degrades whole screen regions, it does not negotiate sizes inside one stack | `src/blueprint_schema.luau` (`layoutPriority`, `shrinkWeight`); `src/layout/solver.luau` (`shrinkStack`, `shrinkFloorOf`, measure PASS 1.5, arrange); `src/layout/text_metrics.luau` (the floor chain); `tests/stack_distribution.spec.luau` |
| `.frame(alignment:)` on ONE child of a stack — SwiftUI's route to per-child cross alignment ([SW-14]) | **Covered** | `lineAlign = "start" \| "center" \| "end" \| "stretch"` is a shared box prop, so a `Text`, `Image`, `Box` or `Spacer` can align itself in its parent's line. It outranks the container's `align` and a nested stack's own `align` — which disentangles one word that used to mean two jobs (a nested `VStack{ align = "center" }` both centring its own children *and* centring itself in its parent's line) | `src/blueprint_schema.luau`; `src/layout/solver.luau` (`child.lineAlign or child.align or node.align`); `tests/stack_distribution.spec.luau` |
| Flow-wrap ("as many as fit per line", ragged widths) | **Covered** — and there is **no SwiftUI equivalent to be parity with** | `UI.HStack{ wrap = true }` / `UI.VStack{ wrap = true }` — Roblox's `UIListLayout.Wraps`. Apple's symbol index was searched for every node whose title contains "flow" or "wrap" and every hit is `wrappedValue` / `FileWrapper` / `toolbarOverflowMenu`: **SwiftUI ships **no** flow layout**, and its answer to this shape is "write a custom `Layout`" ([SW-10]). So this row closes a NATIVE gap, not a SwiftUI one. One prop and no new alignment vocabulary — see §4.3 | `src/layout/solver.luau` (`hwrap`/`vwrap` measure and arrange branches, `flowPartition`/`flowPlan`); `src/blueprint_schema.luau`; `tests/flow_wrap.spec.luau` |
| `ZStack` | **Covered** | Deterministic paint order, **and a per-child `zIndex` override**. SwiftUI's `zIndex` is the same idea and the same default of `0` ([SW-15]), though Apple documents no *scoping* rule for it, so the next sentence is LuauUI's own. `zIndex` is a shared, non-reactive box prop: siblings sort by `(zIndex or 0, tree order)` and a lifted node's whole subtree travels with it, inside its parent's stacking scope, so lifting can never cross scopes. It is implemented generically for **every** container, not just ZStack. Separately, the overflow diagnostic is per-axis and understands `fill` children, so a child granted its full box is not reported as overflowing a box it cannot leave | `src/blueprint_schema.luau`; `src/render/renderer.luau` (`orderedChildren`, `syncZOrder`); `tests/paint_extensions.spec.luau`; `tests/zstack_fill_diagnostic.spec.luau` |
| `Grid` — uniform flow grid | **Covered** | Wrap at one shared LANE extent `(innerLane − gap × (lanes − 1)) / lanes`, `minColumnWidth = "intrinsic"`, per-cell `alignH`/`alignV`. **`flow = "row"` (default) or `"column"`** (CSS's `grid-auto-flow`): row-major wraps across the width and advances down, column-major wraps down the height and advances rightward. It is a MODE of one arithmetic, not a second layout — the flow grid is written once in LANE/FLOW terms and binds those words to width/height in exactly two places, so a column-flow grid is the exact TRANSPOSE of the row-flow grid it mirrors (same box turned on its side, same children with their axes exchanged, every rect back with x/y and w/h swapped). Measure and arrange read ONE plan rather than two agreeing loops. The grid's measured size is a proven fixed point of its own arrange report — measure it, arrange it, measure again, same answer — and that is asserted for BOTH directions, because under column flow the lane axis is the HEIGHT and every fixed-point failure has a transposed twin no row-flow test can see. `columns` and `minColumnWidth` keep their names in both directions (one lane count, one lane minimum); `flow` on a ROW grid is refused with a diagnostic | `src/layout/grid.luau` (`gridFlowPlan`, and the measure/arrange pair that reads it); `tests/layout_vocabulary.spec.luau`; `tests/grid_measure_arrange.spec.luau`; `tests/grid_column_flow.spec.luau`; `games/RascalRally/code/tests/luauui_grid_row_contract.spec.luau` |
| `GridRow` / per-column widths / `gridCellColumns` (spanning) | **Covered** | `UI.GridRow` is a solver primitive, and a `UI.Grid` whose children are all rows switches to **row mode**: column *n* is as wide as the widest natural cell in column *n* across every row (SwiftUI's rule, and Apple states it in those terms: the column matches "the needs of column's widest cell" — [SW-16]), against the flow grid's one shared width. `gridSpan` is SwiftUI's `gridCellColumns` ([SW-18]), and a spanning cell here contributes to no single column's maximum and is fitted to the columns it covers plus the gaps between them — but that sizing rule is **ours**: `gridCellColumns` documents the span and its anchor-alignment consequence and **documents no column-sizing behaviour at all** ([SW-18]). **The mode is selected by the children, never by a prop**; a mix of rows and loose cells files a diagnostic and keeps the flow reading rather than guessing. Naturals that do not fit are reduced proportionally rather than overflowing, because the flow grid cannot overflow and a row grid under the same name must not either. `GridRow`'s prop set is deliberately tiny — `width`, `height`, `padding`, `margin`, `align` and `gap` are construction errors on it (each would be a second authority against the grid that owns the columns), while its paint props (`surface`, `shadow`, `gradient`, `corners`, `stroke`, `zIndex`) are the striped-row case. A Grid with no `GridRow` child is byte-identical to the flow grid, pinned on both sides. Not covered: SwiftUI's per-row `alignment:` ([SW-17]), `gridCellAnchor` ([SW-19]), and `gridCellUnsizedAxes` ([SW-20]) | `src/blueprint_schema.luau`; `src/layout/grid.luau` (column and span rules, `gridMode`, mixed-children diagnostic); `tests/grid_row.spec.luau`; `games/RascalRally/code/tests/luauui_grid_row_contract.spec.luau` |
| `LazyVGrid` | **Covered** | Shipped 2026-08-15 as `LuauUI.newVirtualGrid`: a collection in `columns` lanes that builds and mounts only the LINES OF CELLS the viewport touches — SwiftUI's own stated property, "creating items only as needed" ([SW-21]). The previous revision of this row said the windowing substrate existed and no grid consumed it; this is that consumer, and it consumes it **without a second arithmetic of either kind**. Windowing: the same running-offset index `newVirtualList` and `newTable` use (`src/virtual_extents.luau`), with one entry meaning one LINE — `count = ceil(#items / columns)`, `gap = rowGap` — so the index needed no generalisation, only a change of unit; the cell↔line mapping is plain division (`line = floor((index − 1) / columns) + 1`), which is an index transform, not windowing. Columns: the mounted band **is a real `UI.Grid`**, absolutely positioned at the first windowed line's canvas offset, so the column width is `floor((innerW − gap × (columns − 1)) / columns)` because that formula is *executing* — not because a copy of it agrees today. A short last line keeps its column width and stays left-aligned for the same reason. Scroll anchors on the **item**, which is what covers a grid's own destabilizer: the LANE COUNT changing moves every item to a different line, and a line-keyed anchor would faithfully hold a line the player was never looking at. Keyboard/gamepad get a windowed ring whose SHAPE is two-dimensional — Left/Right step a cell, **Down steps a whole line** — the vertical axis arriving through `navigateIntercept` because the focus graph has no 2-D group axis. Measured headless (regression signal, never a device claim): mount is **54.2x** cheaper than the eager `UI.Grid` at 10 000 items against a ≤21.5% A/A control band, and a scroll frame is **flat in N** — 1.50 / 1.47 / 1.50 ms at N = 1 000 / 10 000 / 40 000. Named non-deliveries, each refused at construction *with a route*: `minColumnWidth` (bind `columns` to `adaptive.columnsFor`, the flow grid's own exported arithmetic), and selection / reorder / `rowActions` (a cell is the consumer's blueprint). §4.2.2 has the full argument | `src/controls/virtual_grid.luau`; `tests/virtual_grid.spec.luau` (21 cases incl. the two-sided build counter and both differentials), `tests/virtual_grid_input.spec.luau` (12); `games/RascalRally/code/tests/luauui_virtual_grid_contract.spec.luau` |
| `LazyHGrid` | **Covered** | Shipped 2026-08-15 as `newVirtualGrid { axis = "x" }` — lanes down the height, lines advancing rightward. The previous revision of this row recorded a REFUSAL with a stated reason: `UI.Grid` wrapped row-major only, so a horizontal grid had no lane mechanism to inherit and hand-rolling one inside the control would have been the second lane arithmetic the vertical grid was built to avoid. That prerequisite is the `Grid` row above (`flow = "column"`), and with it the horizontal band is a real `UI.Grid` on exactly the same terms the vertical one is — the lane formula EXECUTING, not copied. **The control gained an axis without gaining any arithmetic**: `virtual_extents` needed nothing (it is a prefix sum over numbers; the word "item" appears nowhere in its interface), and the four places the axis becomes a coordinate are one seam of four helpers. The FOCUS SHAPE is the one part that is not a mechanical transpose and it transposes the OPPOSITE way from a virtual list's: a grid's declared group axis is the LANE axis, always perpendicular to the scroll, because document order walks a line's lanes before the next line — so `axis = "y"` declares `horizontal` and `axis = "x"` declares `vertical`, with the whole-line step arriving through `navigateIntercept` in both. Copying the list's answer would be reachable and wrong in SHAPE. Laziness is the vertical grid's own two-sided counter, re-proved: **exactly 28** cells built on 10 000 items and **28 on 40**. `width` is refused on this axis (there the width IS the scroll axis; the cross axis is the height and it fills). Measured headless (regression signal, never a device claim): mount is **51–58x** cheaper than the eager sideways grid at 10 000 items against a ≤10.5% A/A control band, and a scroll frame shows **no trend in N** — the across-N spread over a 40x range is the same size as the run-to-run spread at fixed N | `src/controls/virtual_grid.luau`; `tests/virtual_hgrid.spec.luau` (16 cases); `examples/gallery/scenarios/virtual_hgrid.luau`; `artifacts/lazy-hgrid/perf.md` |
| `ViewThatFits` | **Covered** | A real solver construct (`kind == "fits"`) that measures candidates against the offered box and picks the first that fits — SwiftUI's own rule, in its own words ([SW-22]). **The choice is made at each candidate's ideal size**: the measure runs with the shrink pass explicitly suppressed (a `fitProbe` flag), so `layoutPriority` and `shrinkWeight` cannot change which candidate wins at any width. The winner is then shrunk normally like any other subtree. The suppression is deliberate and pinned by a full-width sweep, because without it a shrinkable candidate reports a smaller ideal size than it has and wins boxes it should have lost | `src/layout/solver.luau` (`chosenCandidate`, `ctx.fitProbe`); `tests/layout_vocabulary.spec.luau` ("shrinkWeight DOES NOT change which ViewThatFits candidate wins, at ANY width"); [`a-candidate-is-judged-at-its-ideal-size`](../lessons/a-candidate-is-judged-at-its-ideal-size.md) |
| Reactive-axis stack (no SwiftUI single equivalent; nearest is `AnyLayout`, whose documented point is switching layout type without destroying subview state — [SW-23]) | **Covered** | `UI.AdaptiveStack` — one class whose `axis` is a bound value, `dirty = { "measure" }`. Flipping horizontal↔vertical re-solves in place without remounting the children or re-running the factory | `src/blueprint_schema.luau`; `tests/adaptive.spec.luau` |
| Whole-screen adaptive composition | **Covered** — exceeds SwiftUI in one respect ([SW-10], [SW-24]) | `UI.Composition` + `UI.Region`: ranked regions with richest→minimum-viable form ladders, legality-tested in rank order. Carries all five reference apps' adaptation (§12) with zero device-name branches, and the same machinery expresses a game HUD (§4.5). The resolver is a pure function, so it is exhaustively testable headlessly | [`ADR-0023`](../adr/ADR-0023-declared-content-composition.md); `src/layout/composition.luau`; `src/blueprint_schema.luau`; `tests/composition.spec.luau` |
| Size-class-driven adaptation (`horizontalSizeClass` etc.) | **Covered** | One policy module, `src/layout/adaptive.luau`, owns the raw `sizeClass`/`heightClass` environment keys and exposes the derived helpers callers actually use — `axisFor`, `columnsFor`, `navPlacement`, `conditions()`. Those helpers are consumed by all five reference apps | `src/layout/adaptive.luau` |
| Safe areas | **Covered** | Four-edge insets as environment facts, with a full-bleed (`edgeToEdge`) root policy for scrims and backgrounds. A *partial* clearance — free space beside the platform's own controls rather than below them — is a separate fact, `platformChrome` (§4.5) | `src/layout/solver.luau` (`SafeInsets`, root policy); `src/env/environment.luau` |
| `GeometryReader` — a container that defines its content as a function of its own size ([SW-32]) | **Partial** | You can learn a node's solved rectangle three ways — `controller.rectOf`, an `onGeometry` callback, a `syncGeometry` contribution — but all three are **push** seams keyed by node path, not a readable value you can compose into a memo | `src/render/renderer.luau`; `src/present/presenter.luau`; `src/input/contribution.luau` |
| `containerRelativeFrame` | **Covered** | `UI.containerRelativeFrame(bp, { axis, fraction })`, or the paging form `{ axis, count, span?, spacing? }` whose arithmetic is SwiftUI's verbatim — Apple publishes the three-line formula and the meaning of `count` and `span` ([SW-26]). **It is not the same ruler as `percent`**, and the difference is the reason it exists: `percent` resolves against the *immediate parent's offer*, so any wrapper between the view and its scroller silently changes the answer — and on a scroller's **own axis** the offer is `math.huge`, so `percent` cannot express anything there at all. `containerRelativeFrame` resolves against the nearest ancestor that owns a viewport (a `ScrollView`'s content viewport, else the surface root), which is what a paged carousel needs and what SwiftUI means by "the nearest container" ([SW-25]). It is a **dim type** (`{ type = "containerRelative", … }`) rather than a parallel prop, so it inherits dim validation and the incremental-layout boundary predicate for free; an unbounded container (a scroller nested inside another scroller's own axis) files a diagnostic and falls back to content, exactly as `percent` does. Not covered: SwiftUI's multi-axis form (`[.horizontal, .vertical]`) and the `alignment:`/closure variants — both real, both documented ([SW-27]) — the spec's field set is closed to `{ axis, fraction, count, span, spacing }` and an unknown field is a construction error | `src/blueprint.luau` (`CRF_FIELDS`); `src/layout/solver.luau`; `tests/container_relative_frame.spec.luau`; `tests/container_relative_incremental.spec.luau` |
| `.alignmentGuide` — custom alignment anchors / `AlignmentID` ([SW-28], [SW-29]) | **Missing** | No construct exists; zero occurrences in source. Closing it needs a per-axis guide-resolution pass threaded through arrange. See §4.4 | — |
| Baseline alignment (`.firstTextBaseline` / `.lastTextBaseline` — a guide on the top-most or bottom-most text baseline in a view, [SW-30]) | **Missing** | The `alignH`/`alignV` enum is closed to `start`/`center`/`end`, and the solver computes no per-child baseline. Closing it needs the text-measure pass to publish an ascent per child plus a new arrange term. See §4.4 | `src/blueprint_schema.luau` |
| `Spacer(minLength:)` — Apple's `minLength` is "the minimum length this spacer can be shrunk to" ([SW-12]) | **Composable** | Already expressible as `width`/`height` `= { type = "minMax", min = X }` on the `Spacer`, which inherits the shared box dim vocabulary and adds nothing to it. A first-class `minLength` prop would be sugar over exactly that, and is deliberately not built | `src/blueprint_schema.luau` (Spacer is `merge(BOX)` only) |
| `ScrollView` — a real scroll container | **Covered** | Backed by a native Roblox `ScrollingFrame`: it genuinely scrolls, clips, and reports its content size | `src/client/screen_target.luau` |
| `ScrollView` — horizontal axis | **Covered** | `axis = "y" \| "x"`, construction-only (a reactive engine scroll axis would rebuild native scroll state mid-gesture) | `src/blueprint_schema.luau` |
| Scroll-indicator policy | **Covered** | `indicators: "auto" \| "none"`; a size-to-content scroller's *measure* includes the scrollbar its *arrange* reserves, so it cannot under-measure itself | `src/blueprint_schema.luau` |
| Drag-to-edge autoscroll | **Covered** — no SwiftUI built-in ([SW-10]) | Dragging an item toward a scroller's edge scrolls it, through any nested chain of scrollers, innermost first, falling through when the innermost is pinned | `src/input/autoscroll.luau` |
| `ScrollView` content virtualization | **Missing** | Every `ScrollView` child is measured and arranged regardless of visibility. Windowing is a property of the two collection controls (`newVirtualList`, `newTable{ virtualized = true }`), not of the scroll container — see §4.2 | `src/layout/solver.luau` |
| `LazyVStack` / `LazyHStack` (as `newVirtualList`) ([SW-31]) | **Partial** | Windowed rendering of a long collection **on either axis** (`axis = "y" \| "x"`, construction-only), with a configurable gap, a focus policy keyed by item identity or index, and per-item extents that may be uniform or a function of the item. **Neither SwiftUI name ships as a constructor** — see §4.2 for that decision. Named divergences: no pinned section headers, no fling/inertia, no scrollbar, single selection only. `rowActions` are refused at construction on a horizontal list, because there the tray's reveal swipe *is* the scroll gesture; `wrap` is refused for the same class of reason | `src/controls/virtual_list.luau` |
| Incremental relayout | **Covered** — no SwiftUI-visible equivalent ([SW-10]) | A changed bound value re-solves only the subtree that can be affected. Measured on the framework's own instrumented surface: 141 arranged nodes down to 8 (~17×) for a one-value change, with zero pixel differences across 185 nodes in an engine-level visual diff. On by default | `src/render/renderer.luau`; `src/present/presenter.luau`; `tests/incremental_layout.spec.luau`; `artifacts/performance-stress-places/optimization-log.md` |
| A property that is accepted must do something | **Covered** — no SwiftUI or Roblox equivalent ([SW-10]) | The nine placement props (`anchor`, `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign`, `gridSpan`, `layoutPriority`, `shrinkWeight`) are legal on every node but read only by particular parent arrange branches. `solver.auditPlacement` reports every (parent kind, prop) pair the parent will never read, through `controller.diagnostics()`, so an inert prop is a complaint instead of a silent wrong result | `src/layout/placement_audit.luau`; `tests/placement_audit.spec.luau`; the queue of *unfulfilled* intents: [`unfulfilled-placement-intents.md`](../plans/unfulfilled-placement-intents.md) |
| Live 3D content inside a laid-out box | **Covered** — no SwiftUI equivalent (Roblox-specific) ([SW-10]) | `UI.Stage` hosts a Roblox `ViewportFrame` inside a solver-owned rectangle, with a pure camera/lighting contract. To the solver it is just another content leaf. Live consumers: a 3D dashboard hero and an avatar mannequin preview (§12) | `src/render/stage_content.luau`; `src/client/screen_target.luau` |
| Device-matrix testing | **Covered** | Named device profiles and a matrix runner drive any surface across five viewport shapes headlessly and in the Studio emulator | `src/preview/device_profiles.luau`; `src/preview/matrix_rows.luau` |

**Caveats.**

- **There is no `LayoutOrder` analogue.** Declaration order is the only order.
  Roblox's `SortOrder.LayoutOrder` lets you reorder siblings without moving them
  in the tree; in LuauUI you reorder the `children` array, or the keys a
  `UI.ForEach` yields, and the structural-transition system animates the move.
  That is the declarative equivalent rather than a gap, but it is a real
  behavioural difference worth knowing before porting engine-shaped code.
- Two patterns in `src/controls/row_actions.luau` are worth knowing about but are
  *recipes built on existing seams*, not framework primitives: a per-row height
  override signal driven by a physics spring (to animate a row collapsing to
  zero), and reading `syncGeometry` on the scroll cadence to keep a floating
  menu anchored to a moving row.
- **A public `Layout` protocol is a conditional refusal with a named trigger**,
  not an open TODO. Consumer-authored code inside the solve is what the measure
  memo's cache key, the
  incremental-arrange reuse skip and the placement-prop audit are each unsound
  without. The trigger and the full argument are in
  `docs/plans/swiftui-parity-round3.md`.

### 4.1 Stacks vs Roblox's own flex controls — where LuauUI is a superset, and where it is not

SwiftUI parity is the wrong question for a Roblox developer choosing between
LuauUI and the engine's own `UIListLayout` + `UIFlexItem`. The right question is
whether the framework does **more** than the controls it replaces.

Native surface as documented on `create.roblox.com`: `UIListLayout` carries
`FillDirection`, `HorizontalAlignment`, `VerticalAlignment`, `Padding`,
`SortOrder`, `Wraps`, `ItemLineAlignment`, `HorizontalFlex` and `VerticalFlex`;
`UIFlexItem` carries `FlexMode`, `GrowRatio`, `ShrinkRatio` and a per-item
`ItemLineAlignment`.

| Native capability | LuauUI | Verdict |
|---|---|---|
| `FillDirection` | `UI.HStack` / `UI.VStack` as distinct classes, plus `UI.AdaptiveStack` whose `axis` is a **bound** value that re-solves without remounting | **Superset** — native's `FillDirection` is a plain settable property with no reactive re-solve contract |
| `Padding` | `gap` (number or theme metric). Absent means `0`, not a platform-standard adaptive value — a deliberate divergence from SwiftUI's `nil` spacing, which Apple defines as "the stack to choose a default distance for each pair of subviews" ([SW-11]) — documented rather than "fixed", because changing it now would move every shipped screen | **Equal**, with a named divergence |
| `HorizontalAlignment` / `VerticalAlignment` (whole-group) | `align` on the cross axis (`start`/`center`/`end`/**`stretch`**) and `distribute` on the main axis | **Superset** — `align = "stretch"` has no whole-group native equivalent, and `distribute` carries `start`/`center`/`end` *and* the three space modes in one word, where native splits the same information across two unrelated property groups |
| `HorizontalFlex` / `VerticalFlex` (`Enum.UIFlexAlignment`: `SpaceBetween`, `SpaceAround`, `SpaceEvenly`) | `distribute` — all three space modes plus `start`/`center`/`end` | **Superset** |
| `UIFlexMode` `Shrink`/`Fill` + `ShrinkRatio` | `shrinkWeight` (proportional, `weight × basis`) **inside** `layoutPriority` tiers (ordered, lowest-first) | **Superset.** Native gives a flat per-item ratio with no tiering concept; CSS gives only the proportional level and SwiftUI only the ordered one ([SW-13]). LuauUI composes both, for one sort |
| `UIFlexMode` `Grow` + `GrowRatio` | weighted `fill` dims with largest-remainder rounding | **Equal** |
| `ItemLineAlignment` (per-item cross-axis) | `lineAlign` (`start`/`center`/`end`/`stretch`) | **Superset** — `lineAlign` is legal on **every** box, where native needs a `UIFlexItem` instance per item |
| `Wraps` | `wrap` on `UI.HStack`/`UI.VStack` | **Superset.** Native's `Wraps` is a plain settable boolean; LuauUI's is a **reactive** prop, so a row can be bound to wrap on a phone and not on a desktop without remounting a child. It also reports what native silently does not: a child wider than its line is clamped **and named**, and a block of lines taller than its box files a cross-axis diagnostic |
| `SortOrder` | document order only; no `LayoutOrder` analogue | **Divergence**, deliberate — see the caveat above |
| — | `layoutPriority` tiers, per-child `margin`, `minMax` dims, hug/content sizing, `ViewThatFits`, `UI.Composition`/`Region` ranked degradation, `containerRelativeFrame`, `GridRow` spanning, incremental layout, and the inert-placement-prop audit | **Ten capabilities with no native equivalent at all.** Native silently ignores a property the current layout mode does not use (`HorizontalFlex` under a vertical `FillDirection`, say) with no diagnostic channel; LuauUI files a complaint |

**The scorecard: nothing behind.** The single divergence in this table is
`SortOrder`, and it is a deliberate one (document order is the only order) rather
than a missing capability.

### 4.2 Lazy collections, and how a window is computed

**No `LazyVStack` and no `LazyHStack` ship as names** (game-director decision).
The rule was that they must be thin sugar over the existing virtualized substrate
rather than a second virtualizer — and the substrate does not leave room for the
sugar. `newVirtualList` requires an explicit `key` and an explicit `cell`, where
SwiftUI's `LazyVStack` takes arbitrary heterogeneous content with no key
function. That is an argument from *absence*, and it is worth being precise
about: Apple documents the laziness — the stack "doesn't create items until it
needs to render them onscreen" — and imposes no declared extent and no key
anywhere on the page ([SW-31]). A constructor wearing SwiftUI's name over those
requirements would be a parity claim the code does not honour, which the API
constitution rates as a defect of the same severity as the reverse. Stripped of
the name, the sugar adds nothing but different words for the same fields.

So LuauUI has **two** windowed collection controls, and they share their
arithmetic:

- **`newVirtualList`** — a plain list of identical-shaped rows, on either axis.
- **`newTable{ virtualized = true }`** — the rich container: columns, a header,
  single/multi/range selection, every reorder route (§4.2.1).

**How a window is computed, in plain language.** A windowed collection only
builds the items the viewport can see. To know which items those are it needs to
answer "where does item *n* start?" If every item is the same size that is one
multiplication. If they are not, it is a **running total** — the sum of every
preceding item's extent — and that is what `src/virtual_extents.luau` is: a
prefix-sum index shared by both controls, with the uniform case proved to be
exactly the pre-existing formulas by a differential test.

**Variable item extents.** `itemExtent` accepts a number *or* a function
`(item, index, use) -> px`, so a feed of posts with different body lengths, a
chat log, or a settings list with wrapped explanatory text can still be
windowed. Two consequences an author has to know:

- **A declared extent is still a prediction.** The framework does not measure
  each row before deciding where it goes, so a row that lies about its extent
  paints outside its slot. A per-row guard reports exactly that, and it is
  sharpened rather than retired by the variable form. The measured case that
  motivated it: a row declaring `itemExtent = 84` measured 88 at the default text
  preference and **249 in that same 84 px slot** at the largest one, on a
  320×640 phone.
- **The scroll anchors on the item under the viewport's leading edge** when the
  extents re-derive, so a text-preference change does not move the player out
  from under their own finger. Anchoring is variable-extents-only, deliberately.

**Measured extents are not built.** `itemExtent = "measured"` — rows hug,
`syncGeometry` learns each row's real extent, the same prefix sum consumes it —
is the named next stage and is not started. Nothing is staged for it and nothing
needs to be: the index takes an array of numbers and does not care where they
came from. Its opposite, "measure every item at mount", is **refused** on a
standing constraint rather than on cost: the list would stop being lazy in the
sense that matters for a first frame, and a build counter on a ten-thousand-item
ragged list is the check that keeps it refused. The full argument is in
[`docs/plans/variable-item-extents.md`](../plans/variable-item-extents.md).

#### 4.2.1 `newTable{ virtualized = true }` — the unified collection

A long, reorderable, selectable list is buildable on one class. `Table` windows
on the same `virtual_extents` index `newVirtualList` uses, and the three
hand-rolled O(N) row-geometry loops it used to carry (a key→cumulative-top memo,
a `contentHeight()` that re-summed the same numbers, an `insertSlotAt` that
walked them a third time with its own midpoint rule) are one prefix sum — **for
the flowing table as well**, so the two paths cannot drift into disagreeing about
one list. Measured on that shipped flowing path: −95.4 % ± 0.1 across three
order-swapped rounds against a ±3 % A/A band, because the old `contentHeight()`
was O(N) *per call* and `clampScroll` calls it.

**Table never had the lying-extent problem**, which is why it was the right first
virtualization consumer: `rowHeightOf` DERIVES a row's height from the theme
metrics, the typography scale, the accessibility text offset and the input
paradigm, and an authored `rowHeight` is floored by one line of its own cell
text. Nobody predicts anything.

| | |
|---|---|
| **What it does** | `virtualized` is construction-only: only the rows the viewport touches are mounted, plus `OVERSCAN = 2` each side, absolutely positioned on a full-extent canvas. The viewport is MEASURED through `syncGeometry`, seeded from the screen height so the first frame over-mounts rather than under-mounts. Scroll anchors on the item under the leading edge. `api.revealRow(key)` reaches a row that has no path at all. Selection, order, focus and the sort are model state and survive the window. |
| **What it refuses** | `scrolls = false` (a block table has no viewport to window against) and `rowActions` (Table WRAPS a composite per row, and that composite's lifecycle is pruned by the DATA, not by the window, so a row scrolling out would strand its engine). Both are construction errors that name why. |
| **What it trades** | A cell's own state dies with its row — which is why this is opt-in and a flowing table keeps every byte of its behaviour. Anchoring is virtualized-only. At `rowGap > 0` the insertion-slot rule takes the SLOT's midpoint rather than the ROW's and clamps the last hairline into the canvas; at the default `rowGap = 0`, every shipped table, the two rules are equal everywhere. |
| **What is left** | Row actions on a virtualized Table, by teaching Table to HOST rather than wrap; multi-selection on `newVirtualList` (the mirror hole); anchoring generalized to the flowing path. |

**A one-collection-substrate refactor was rejected**, and not for its size: the
two controls' height authority is *inverted*, their row-actions hosting is
opposite by design (and each one's other capabilities depend on which side it
took), their selection cardinality and focus-group shape differ in kind, and
`ENGINEERING.md` forbids folding a broad refactor into feature work. The part
that CAN be shared already is — `virtual_extents`, `row_capability`,
`solverLib.keepVisibleOffset`. Full argument:
[`docs/plans/unified-collection.md`](../plans/unified-collection.md).

#### 4.2.2 `newVirtualGrid` — the lazy grid, shipped 2026-08-15

The gap this closes was stated flatly in the table above, and the previous
revision of that row ended with the sentence that turned out to be the whole
brief: *the windowing substrate a lazy grid would need does exist, and is
consumed by the two collection controls only.* So the question was never "how do
you window a grid" — it was **whether a grid could be a third consumer of the one
index without becoming a second implementation of it.** It could, and the two
reuses below are the entire design.

##### The extent index served AS-IS. It needed a change of UNIT, not a generalisation.

`src/virtual_extents.luau` is a prefix sum over a list of numbers with a gap
between them. It has **no notion of an "item" anywhere in it** — that word appears
in its prose, never in its interface — so a grid uses it by deciding that one
entry means one LINE OF CELLS:

```
count   = ceil(#items / columns)
extents = the per-line extents
gap     = rowGap
```

`offsetOf`, `extentOf`, `window` and `content` then answer in line units and not
one line of that module changed. The cell↔line mapping that sits on top —

```
line          = floor((index - 1) / columns) + 1
the cells of line L are indices (L-1)*columns + 1 .. min(N, L*columns)
```

— is an **index transform, not windowing**: it involves no offsets, no search and
no extents, and it is exact for the same reason integer division is. Two smaller
facts confirm the fit rather than merely permit it. `slotAt` and `boundaryOffset`
are the index's *insertion* vocabulary (which slot does a drop land in, where is
the hairline drawn) and a grid asks neither, because it has no reorder — so the
interface is used as-is and **under-used**, which is the shape of a primitive that
was general enough already. And the uniform-vs-variable divergence the index
documents shows up here unchanged and in the same direction: at a viewport of 200
over 40px lines the uniform rule names 7 lines and the variable rule names 8,
because the variable rule asks the exact containing-slot question and is a strict
superset. That is
[`variable-item-extents.md`](../plans/variable-item-extents.md)'s recorded trade
arriving in a second consumer, and `tests/virtual_grid.spec.luau` pins the
superset *relationship*, not just the number.

##### The mounted band IS a `UI.Grid`. There is no second column arithmetic.

The windowed lines are a contiguous run of items that always **starts on a line
boundary** — which is exactly what a row-major flow grid wraps. So the control
mounts **one** `UI.Grid { columns }`, absolutely positioned at
`index.offsetOf(firstLine)` inside the full-extent canvas, holding the window's
cells in order:

```
ScrollView (engine ScrollingFrame; clip host)
└─ Anchor "Canvas"   height = index.content        ← the FULL virtual extent
   └─ Grid "Band"    offsetY = offsetOf(firstLine) ← arrange-only; a slide never re-measures
      └─ ForEach over the windowed cells, keyed by ITEM
         └─ ZStack "Cell"  height = its LINE's extent
```

The column width is `floor((innerW − gap × (columns − 1)) / columns)` because the
flow grid's own formula is executing, not because a copy of it agrees today; a
change to that rule moves both sides of the differential in
`tests/virtual_grid.spec.luau` together, which is the point of writing it as a
differential. The short last line keeps its column width and stays left-aligned
for free, because the flow grid derives the column from the OFFER and the lane
count and never from how many cells turned up.

The `Cell` wrapper earns its instance three times over: it pins the cell to its
line's extent (so the flow grid's per-line natural height *is* the number the
index already committed to), it carries the `virtualSlot` declaration the solver's
lying-extent guard reads, and it holds the focusable hit. It also makes a
structural cell (`UI.When`, `UI.ForEach`) safe — those splice several children
into their parent, which inside the band would shift every following cell into the
wrong lane. "One item, one grid child" is true by construction, not by convention.

##### Two things this cost, both found by mutation testing rather than by reading

**A contribution owns its subtree's focus.** The first draft attached an input
contribution purely to learn its own mounted path and returned no focus groups —
and `focus_map.autoGroups` does not descend into a contribution, so every
focusable inside every cell would have been unreachable by Tab *and* by the D-pad.
A lazy grid that is a focus black hole is worse than no lazy grid. The full-cell
hit exists to give the control something to name.

**A grid's ring is two-dimensional and the focus graph's is not.** A
`NavigationGroup` axis is `"vertical"` or `"horizontal"` (`focus_graph.luau`), and
the band's document order is row-major — so ±1 is a sideways step and the group is
emitted as `horizontal`, while **Down is ±`columns`** and arrives through the
existing `navigateIntercept` seam rather than by widening the focus graph from
inside a control. Emitting the group as `vertical` would have been *reachable* and
wrong in *shape*: Down walking visually rightward. That is the cleanest example in
this document of why the paradigm axis is a separate gate from the reachability
axis — the mutation that flips the group to `vertical` reddens named cases in both
files.

Mutation testing also deleted code: the control was written with a `focusMoved`
contribution mirroring `newVirtualList`'s, and withholding it changed the scroll
behaviour on **no path at all** — the presenter's own keep-visible already reacts
to a focus move it observes. The intercept's keep-visible is *not* dead, and the
difference is the mechanism: `navigateIntercept` moves focus programmatically, so
nothing else brings its ±`columns` target into view. One was removed, the other is
pinned by a named case.

##### What it refuses, and what it is honest about

| | |
|---|---|
| **`axis = "x"` (`LazyHGrid`)** | ~~Refused~~ — **SHIPPED 2026-08-15**, and the route is exactly the one the refusal named. The refusal was never about principle: it was a missing capability in the EAGER grid, stated in the error message. `UI.Grid { flow = "column" }` supplied it as a MODE of the one flow arithmetic, and the horizontal band is then a real `UI.Grid` with the lane formula executing. What changed in the control is an axis seam of four helpers and a transposed focus shape; the windowing index and the lane arithmetic are byte-unchanged |
| **`minColumnWidth`** | Refused *with a route*. Deriving lanes from a minimum cell width needs the cross-axis size in px — a second measured seam beside `viewportExtent`. `adaptive.columnsFor(available, minColumnWidth, gap)` is the flow grid's own arithmetic, already exported, so `columns` binds to a memo over it |
| **selection / reorder / `rowActions`** | Not offered. A cell is the consumer's blueprint and carries its own interaction beyond the hit's Activate |
| **A cell's state dies with the window** | Stated, not hidden — the same honesty `newTable { virtualized = true }` owes. But **the tension that made Table refuse `rowActions` does not exist here**, and copying that refusal to look consistent would have been a lie about the mechanism: Table WRAPS each actionable row in a composite whose lifecycle is pruned by the DATA, so a row scrolling out strands its engine. This control's only wrapper is the `Cell`, and it lives *inside* the window's `ForEach` — its lifecycle **is** the window's. There is nothing to strand |

##### The numbers

Headless Lune, evidence class **regression signal** — not Studio, not a device.
The A/A control band is stated first because four missions this week found
apparent wins inside one: mounting the same lazy grid twice, order-swapped ABBA,
9 rounds, spreads **21.5%** at N = 1 000 and **2.6%** at N = 10 000.

| | N = 1 000 | N = 10 000 |
|---|---|---|
| mount, lazy | 4.08 ms | 7.77 ms |
| mount, eager `UI.Grid` | 30.69 ms | 421.01 ms |
| **ratio** | **7.5x** | **54.2x** |

Both are an order of magnitude outside the widest control band. The claim that
actually matters is the third row, though, and it is the one a ratio cannot make:
a **scroll frame is flat in N** — 1.498 ms / 1.471 ms / 1.504 ms at N = 1 000 /
10 000 / 40 000, a 2.2% spread across a 40x range of collection size, i.e. inside
the control band. That is "creates items only as needed", measured rather than
asserted. What is **not** claimed: any Studio or device number. A perf-lab arm on
the real engine is the outstanding measurement.

### 4.3 Flow-wrap, and the cross-axis rule nobody had written down

Roblox's `UIListLayout.Wraps` packs "as many as fit per line" with ragged item
widths. No combination of the other shipped constructs fakes it: `UI.Grid` is a
**uniform-pitch** layout where every cell gets `innerW / cols`, and
`minColumnWidth = "intrinsic"` sizes every column to the widest child — a
different and more wasteful shape, not a ragged one.

`UI.HStack{ wrap = true }` / `UI.VStack{ wrap = true }` is the closure, and three
things about it are worth keeping.

**It is a prop, not a class.** The construction ladder's test is whether a thing
"needs its own layout/paint/input semantics an existing class cannot compose". A
wrapping stack has the same children, the same paint, the same input, the same
`gap`/`align`/`lineAlign`/`distribute` as the stack it is a mode of; one boolean
is the entire difference. Making it a class would also have made "wrap on a
phone, one line on a desktop" a `UI.When` swap — a remount of every child, the
exact defect `UI.AdaptiveStack` exists to prevent.

**The engine's cross-axis rule is defined; it just is not documented.**
`AlignContent` appears zero times in the engine API dump, and neither the
`UIListLayout` reference nor the flex-layouts guide discusses how wrapped *lines*
are positioned. But undocumented is not undefined, and the engine had never been
asked. Probed live in Studio — a 300×400 container, six 100×40 items, so 80 px of
lines inside 400 px:

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
already, so flow-wrap costs one prop and no alignment vocabulary at all. CSS's
`space-between` *between lines* has no native counterpart and LuauUI does not add
one.

**What it does not compose with, and why each is a refusal rather than an
integration.** It does not compose with `newVirtualList` (`wrap` is a
construction error there — the virtualizer's window is an index along one axis).
The shrink pair is not read on a wrapping stack, and the placement audit says so:
wrapping *is* what this stack does with a deficit. And `align = "stretch"` is
refused with a diagnostic, because on a wrapping stack it would mean two things
at once.

### 4.4 Baseline alignment and `alignmentGuide` — named non-deliveries

Both are **Missing**, both have a known shape and a known cost, and neither has a
consumer asking for it:

- **Baseline alignment** (`.firstTextBaseline` / `.lastTextBaseline`) needs the
  text-measure pass to publish an **ascent per child** alongside the extents it
  already publishes, plus a new arrange term that offsets each child so those
  ascents line up. It is a solver change in both passes, not a new enum value.
- **`.alignmentGuide` / custom `AlignmentID`** needs a per-axis guide-resolution
  pass threaded through arrange: a child declares a guide value, the parent
  collects them, and alignment resolves against the collected guides rather than
  against the box edges.

### 4.5 Screen-anchored HUD zones, and the platform's own chrome

**What a HUD zone is, in plain language.** A game HUD is a handful of things
pinned to the edges and corners of the screen — an ammo counter bottom-right, a
minimap top-left, an objective chip along the top. Every one of them wants to sit
in a fixed place and none of them wants to be pushed around by its neighbours
when the window changes shape.

LuauUI expresses that with the composition machinery of §4, not a second system.
`composition.HUD`, `composition.HUD_GROUPS` and `composition.ZONES` are frozen
presets: three lanes (`left`, `center`, `right`) each carrying three vertical
bands, giving the nine anchors an author names directly — `topLeft`, `top`,
`topRight`, `left`, `center`, `right`, `bottomLeft`, `bottom`, `bottomRight` —
plus a tenth full-width row above them, `topbar` (below). An author writes
ordinary `UI.Region`s whose `group` is one of those zone ids. There is no new
blueprint class, no new solver kind, and no second resolution path.

Lanes cannot overlap each other — that is the existing invariant, and it is what
"the zones partition the screen" means. Two additions were needed and both are
general rather than HUD-specific: `holdsLane` keeps an empty lane's width
reserved, so a centre column with nothing in it does not let the right column
slide inward; and a per-group `align` positions a zone's content *across* its
lane, where the pre-existing `place` positions it *down* the lane.

**What lanes cannot prevent is a zone's content outgrowing its own box**, and
that is a real defect that used to be invisible. So `composition.resolve` reports
`collisions` — every pair of mounted regions whose **painted** boxes intersect,
each pair named with the overlap in pixels — through `controller.diagnostics()`,
where the always-on overflow sweep reads it. It is a finding, not an authored
intent: it is never marked `designed`.

**The platform's own chrome is an L, not an edge.** Roblox puts its own controls
in part of the top band, and they do not span the full width — on a reference
viewport they occupy roughly the leftmost 164 px of a 58 px strip, leaving the
rest of that strip free. Every safe-area primitive LuauUI already had expresses
"clear this whole edge", which is a rectangle cut off a rectangle, and cannot say
"there is free space *beside* the platform's controls, at the same height". The
derived environment fact `platformChrome` says it:

| Field | What it is |
|---|---|
| `band` | The free strip, in window space — or `nil`, never a zero rect, so "no strip exists" is distinct from "a strip at the origin" |
| `rects` | A **list** of the rects the platform's own controls occupy. A list, because on some devices (a notched phone in landscape) it is genuinely two disjoint rects, and a bounding box around them would throw away the gap |
| `insets` | Clears the whole band, byte-identical to what the existing device-safe content policy applies |
| `bandInsets` | Clears everything *except* the free band, for a surface that wants to ride level with the chrome. Equal to `insets` when there is no band |

The `topbar` zone is the HUD's use of it: a full-width span row above all three
lanes, so the lanes below start clear of the platform's controls by construction
rather than by an authored numeric offset. A span group with no regions in it
costs nothing, pinned by a byte-identical additivity test.

One correction this fact carries, because it is the kind of thing that produces
a doubled offset in a consumer: `GuiService.TopbarInset` is already expressed in
physical window space, **not** relative to the topbar-safe area. The two facts
are two encodings of the same rectangle and must be intersected, never summed.

([`ADR-0025`](../adr/ADR-0025-screen-anchored-hud.md),
[`ADR-0027`](../adr/ADR-0027-platform-chrome-band.md);
`src/layout/composition.luau`; `src/env/environment.luau`;
`tests/hud_composition.spec.luau`; fixture `examples/gallery/scenarios/hud.luau`)

---
## 5. Controls catalog

LuauUI's conformance registry holds **51 rows: 25 composite classes and 26
non-interactive leaves**. Sixteen of those rows are interactive, and **all
sixteen carry an automated four-input proof and also prove the device-idiom
axis.** That is far short of SwiftUI's catalog in breadth and ahead of it in
per-control rigour.

| SwiftUI item | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `.swipeActions` — secondary actions on a row ([SW-37]) | **Covered** | `LuauUI.newRowActions` / `LuauUI.newRowActionsCoordinator`, a general construct that wraps *any* row content, plus turnkey `spec.rowActions` on **both** `Table` and `newVirtualList`. The defaults match Apple's: trailing edge, full-swipe on ([SW-37]). Being *general* rather than list-bound used to be a LuauUI lead and no longer is — SwiftUI's own swipe actions now apply "to a row in a list or container", meaning scroll views, stacks, grids and custom layouts ([SW-38]). The one place LuauUI is still ahead of the modifier itself is platform reach: Apple ships `swipeActions` on iOS, macOS and watchOS and **not on tvOS** ([SW-37]). Detail and remaining gaps in §5.1 | `src/controls/row_actions.luau`; `src/init.luau`; `tests/row_actions.spec.luau`, `tests/row_actions_input.spec.luau` |
| `Slider` | **Partial** | Real composite: pointer drag, tap-to-position, touch drag, keyboard/gamepad nudge. Cancels cleanly if the input device changes mid-drag | `src/controls/slider.luau`; `tests/conformance/controls_registry.luau` |
| `Stepper` | **Partial** | Real composite | `src/controls/stepper.luau`; registry |
| `Picker` (`.segmented` and `.inline`) ([SW-41]) | **Partial** | One adaptive composite replaces both styles: `picker.resolvePresentation(optionCount, sizeClass, longestLabel)` chooses segmented vs inline from option count, screen size class, and label length — never from a device name. `presentation` is `"automatic" \| "segmented" \| "inline"` | `src/controls/picker.luau`; registry |
| `ProgressView` (determinate bar) | **Covered** | Real composite, declared non-interactive, so it is exempt from the four-input proof by design rather than by omission | `src/controls/progress_view.luau`; registry row `ProgressView` (`inputProofs = false`) |
| `ProgressView` (circular, indeterminate) + the `Gauge` capacity ring | **Covered** | `presentation = "circular"` accepts BOTH modes, and both are one function of one scalar: determinate binds `arc(0, 360 × fraction)` over a static capacity ring; indeterminate binds `arc(360 × phase, fixedSweep)` — a fixed sweep whose START ANGLE advances, which is how it rotates with no rotation channel in the blueprint. There is **no native radial primitive in the engine** (no angular `UIGradient` mode, no `ImageLabel` fractional fill, no `EditableImage` arc, and `GuiObject.Rotation` has a fixed pivot and is documented incompatible with `ClipsDescendants`), so both forms are strokes on the shipped `UI.Path` + `LuauUI.pathShapes.arc`; `points` is a paint-channel property, so a value change and a frame of rotation are each one prop write and **zero re-solves**. **The parity claim is split on purpose**: the INDETERMINATE ring is `ProgressView(.circular)`, whose own documentation says "in cases where no determinate circular progress view style is available, circular progress views use an indeterminate style" ([SW-130]), while the DETERMINATE ring is the `Gauge` shape `.accessoryCircularCapacity` ([SW-131], "a closed ring that's partially filled in") rather than a `ProgressView`, and this document does not claim `ProgressView` parity for it. It adds **no blueprint prop and no decoration slot** — the arc paints through the Path's own `role`, and its size is two theme metrics (`controls.progress.circularSize` / `circularThickness`). Refusals: `height` (that is the bar's track) and `showValue` (Apple centres the readout inside the ring, and that is `Gauge`'s complication-sized dial, not this small theme-sized one). Two platform facts a caller must know: a `Path2D` has **no transparency at all**, so the ring cannot fade without a caller-declared `canvasGroup` container, and a path is not clipped by anything, so a ring scrolled out of a clipping host still paints | `src/controls/progress_view.luau`; `tests/progress_circular.spec.luau`; `tests/display_controls.spec.luau`; fixture `examples/gallery/scenarios/progress_ring.luau` |
| `ProgressView` (indeterminate / dot spinner) | **Covered** | Indeterminate is selected by **`value = nil`**, Apple's own rule — "use an initializer that doesn't take a progress value", with `value` documented as nil-for-indeterminate ([SW-43]) — so there is no second flag that could disagree with the value. `presentation = "bar" \| "circular" \| "spinner"`. The spinner is a ring of five fixed-size **dots** rather than an arc; its travelling pulse rides the `tint` channel, which is paint-only, so the ring animates for **zero re-solves** and can be dropped into any container without asking what its parent's axis is. Narrowings, all refusals rather than silent drops: a spinner requires `value = nil`; `min`/`max`/`format`/`showValue` are refused on an indeterminate view; and `height` — the BAR's track thickness — is refused on a spinner rather than silently becoming the dot's size (the dot is the theme metric `controls.progress.spinnerDotSize`). **An indeterminate view also names its owner**: `scope` is required for `value = nil`, exactly as `newAsyncImage` requires one, because the cycle holds a live motion-clock entry for as long as the view exists and nothing else would ever retire it (measured: a dismissed — and an unpresented — indicator kept writing its phase 121 times per 120 clock steps, forever). **Reduced motion is the deliberate opposite of the usual call**: the indicator is `kind = "informational"`, so it keeps advancing on the motion authority's quantized 250 ms tick instead of freezing — a frozen spinner and a hung process look identical | `src/controls/progress_view.luau`; `tests/display_controls.spec.luau` |
| `AsyncImage` — a picture that loads later, with a placeholder in the meantime ([SW-132]) | **Covered** | `LuauUI.newAsyncImage`. The load runs through `newResourceProvider`, so the composite is engine-free and testable: `state` is `"pending" \| "ready" \| "failed"`, the placeholder is painted while pending, and **a failure keeps the placeholder** rather than drawing a broken-image glyph. That last rule is Apple's own, arrived at independently — SwiftUI's page says that if an `Image` placeholder "doesn't load, SwiftUI doesn't show anything as a placeholder and doesn't report an error" ([SW-132]). Two things LuauUI adds that Apple has no counterpart for: a required `scope` (the provider handle is released with its owner, and a stale completion is rejected by generation counter rather than applied to a reused node), and per-call-site `retry = { count, delaySeconds }`. Two it lacks: there is no `phase`-closure initializer — the three states are the composite's own layers, not a consumer-authored view per phase — and no image cache (Apple's is transport-level from the 27.0 releases, [SW-132]); Roblox's content system does its own caching underneath, which this framework neither controls nor observes | `src/controls/async_image.luau`; `src/init.luau`; `tests/async_image.spec.luau` |
| `Label` (title + icon) | **Partial** | Real composite with the presentation resolution SwiftUI's `LabelStyle` provides: `presentation: "titleAndIcon" \| "titleOnly" \| "iconOnly"`, default `titleAndIcon`, and `iconOnly` degrades safely to `titleOnly` when no icon resolves. **Apple documents no behaviour here** for the iconless case: `LabelStyle.iconOnly` documents only that the title survives for VoiceOver ([SW-46]) and says nothing about what is painted, so the honest claim is that LuauUI defines the case and Apple's documentation does not. **Its `title` is a static string, not bindable** — a known follow-on with no shipped screen asking for it. It also does **not** compose into `newPopupButton`: that control builds its trigger and its rows as `UI.Button{ label = … }` with a flat string, never a Label blueprint | `src/controls/label.luau`; `src/controls/popup_button.luau` |
| `DisclosureGroup` | **Partial** | Real composite, including the correct focus behaviour on collapse (focus moves to the header before the content unmounts, so it is never lost). `content` is a function mounted only while expanded | `src/controls/disclosure_group.luau`; registry |
| `Divider` | **Covered** | A real axis-aware hairline leaf that infers its own orientation — not a hand-sized box. Same rule Apple states: in a stack the divider extends across the stack's minor axis ([SW-48]) | `src/blueprint_schema.luau` |
| Star-rating strip | **Covered** — no SwiftUI standard-library counterpart ([SW-10]) | `newRating`: a single focus stop that supports tap, scrub, and keyboard/gamepad adjust, and cancels back to its prior value if the pointer is lost mid-scrub | `src/controls/rating.luau` |
| `Menu` / dropdown button | **Partial** | `newPopupButton` adapts its presentation: `resolvePresentation(optionCount, sizeClass, touchLive)` returns a sheet whenever touch is live, a sheet on compact screens with more than 6 options, an inline list at 3 or fewer options on larger screens, and a menu otherwise. See §5.4 on row heights | `src/controls/popup_button.luau` |
| `Table.onPrimaryAction` (SwiftUI spells it as the `primaryAction:` argument of `contextMenu(forSelectionType:menu:primaryAction:)`) | **Covered** | **`onPrimaryAction` is our name, not Apple's** — there is no such symbol; the verb arrives as an argument of that modifier. Its documentation is the rule implemented: *"In macOS, a single click… selects that row, and a double click performs the primary action. In iOS and iPadOS, tapping on the row activates the primary action. To select a row without performing an action, either enter edit mode or hold shift or command on a keyboard while tapping the row."* So: pointer **double-click**, touch **plain single tap**, and **edit mode is the touch selection mode** — where a tap toggles selection and never opens, which restores `multi`'s tap-to-deselect. The **cost is Apple's own and is documented rather than hidden**: with an action declared, touch loses tap-to-select in normal mode entirely, so a table whose dominant touch use is selecting should not declare the action. Gamepad **A/Cross** and keyboard `Return` are **conventions, not parity** — Apple documents no key for row activation (`Return` matches `NSTableView` practice). A modified click (Shift / Cmd / Ctrl) never opens, on any input. The double-click window takes an injected clock through the existing `bindMotion` contribution seam and falls back to `os.clock` — without a scripted `now`, two `adapter.tap` calls in a spec are microseconds apart and the window is satisfied by the test's own speed rather than by the code | `src/controls/table.luau`; `tests/table_input.spec.luau` |
| `Table` / `List` with selection and reordering | **Partial** | Reorderable rows, single/multi/range selection, per-cell rendering via `column.cell`/`cellFor`, swipe actions via `spec.rowActions`, optional windowing via `virtualized` (§4.2.1), and per-row capability opt-outs (next row). Modifier-click multi-select ships — Shift-click ranges and Cmd/Ctrl-click toggles, anchor-tracked, with the anchor pruned on row removal. The committed column widths are readable as a `Readable`, so a consumer can persist or mirror them. **Column resize still remounts every row on commit** — the live drag preview does not, only the commit does | `src/controls/table.luau`; `tests/table.spec.luau` |
| Apple's per-row opt-out family — `selectionDisabled(_:)`, `deleteDisabled(_:)`, `moveDisabled(_:)` | **Covered** | `rowSelectable`, `rowMovable`, `rowDeletable`: three per-item predicates, on **both** `Table` and `newVirtualList`. One implementation (`src/row_capability.luau`) with two wirings, not two implementations — the predicate was extracted rather than the controls unified. Two design rules worth knowing. **It fails closed**: the predicate runs inside a `pcall`, and a throw, or `false`, is a refusal; anything else allows, so a broken predicate locks a row rather than opening it. And **declaring a predicate without its capability is a construction error** — `rowMovable` on a table that cannot reorder is refused by name instead of sitting inert. The refusal itself is **silent** by design: a disallowed row simply does not select, move or delete. Nothing paints differently and nothing is announced, so a screen that must *explain* a refusal (a toast, a counter, the selection visibly returning) still writes that itself | `src/row_capability.luau`; `src/controls/table.luau`; `src/controls/virtual_list.luau`; `tests/row_capability_optouts.spec.luau`; `tests/row_capabilities_scenario.spec.luau` |
| `.contextMenu` ([SW-50]) | **Missing** | No `contextMenu` construct exists in source at all. Apple documents the trigger this would have to honour — "touch and hold in iOS or iPadOS" ([SW-50]). What exists is the *menu* half (row actions render exactly that kind of action list) and a normalized gesture layer nothing consumes as a trigger — see §5.2 | zero occurrences of `contextMenu` in `src/` |
| `ButtonStyle` / `ToggleStyle` / `PickerStyle` / `LabelStyle` / `ProgressViewStyle` / `ListStyle` / `GaugeStyle` protocols — each documented as the way to give a control family a custom appearance ([SW-51], [SW-52], [SW-41], [SW-45], [SW-53], [SW-54], [SW-55]) | **Missing, by decision** | Not an omission: native StyleSheets and theme packages own paint. §6.1 carries the mapping table a SwiftUI author needs | — |
| Palette `Picker` ([SW-42]) | **Missing** | `presentation` is closed to `automatic`/`segmented`/`inline`. Apple's `.palette` is itself narrow — iOS 17 and macOS 14 up, and absent from tvOS and watchOS ([SW-42]) | `src/controls/picker.luau` |
| `DatePicker` ([SW-62]), `ColorPicker` ([SW-63]), `SecureField` ([SW-64]), multi-line `TextEditor` ([SW-65]), `Gauge` ([SW-66]), `Link` ([SW-67]), `ShareLink` ([SW-68]), `NavigationSplitView` ([SW-69]) | **Missing** | Each confirmed absent by direct search of source. Worth knowing before treating this row as eight uniform holes: SwiftUI itself does not ship five of them on tvOS (`DatePicker`, `ColorPicker`, `TextEditor`, `Gauge`, `ShareLink`) or two of them on watchOS (`ColorPicker`, `TextEditor`) — the availability is on each citation | — |
| `.sensoryFeedback` at the control level ([SW-70]) | **Covered**, and wider than SwiftUI's | Two forms of one modifier. The change form `UI.sensoryFeedback(bp, { trigger, event })` is Apple's; the control form `UI.sensoryFeedback(bp, { activation = "commit" })` has no SwiftUI equivalent — it names what a control's own press means, replacing the generic `activate`, and it **cascades** down the mounted tree so one declaration reaches a composite's inner Button or every control in a panel. Detail in §7.1 | `src/blueprint.luau`; `src/present/feedback.luau`; `src/mount.luau`; `tests/control_feedback.spec.luau` |

### 5.1 Row swipe actions, in detail

`LuauUI.newRowActions` and `LuauUI.newRowActionsCoordinator` are standalone
public exports — proven working in a hand-built `ScrollView > VStack` list with
no `Table` involved. `Table.rowActions` and `newVirtualList.rowActions` are those
two classes wiring the same two seams for consumers who do not want to hand-roll
a list.

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

**Cost.** Inside `newVirtualList` a closed row mounts **nothing** extra: a shared
dispatcher wires four static props onto the row's existing `Hit` button, the
gesture engine is built lazily on first pointer-down, and the engaged row's slide
rides the presentation channel rather than a layout prop. The gate ceilings are
≤5 % steady-scroll time, ≤5 % fling time and ≤1 extra Roblox instance per closed
row; the current five-run ABBA means are **−0.28 % steady, +2.83 % fling, 0.08
instances**, all passing, with the fling number the only real positive cost. The
measurement discipline is on record with them: per-run sd is 0.96–2.90 pp, so the
budget is called on ≥5-run means, never a single run
(`tools/check_row_actions_matrix.py`; `artifacts/row-actions/device-matrix.md`;
[`row-actions-hosted-mode-design.md`](../plans/row-actions-hosted-mode-design.md)).

**Its named gaps**, all real:

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
- **Not on a virtualized `Table`.** `Table` WRAPS a composite per row, and that
  composite's lifecycle is pruned by the data rather than by the window, so a row
  scrolling out would strand its engine. `virtualized` + `rowActions` is a
  construction error that says so. Teaching `Table` to HOST instead of wrap is
  the named next stage ([`unified-collection.md`](../plans/unified-collection.md)).

An adversarial code review of the whole feature closed at 16 findings — 15 fixed
directly, 1 resolved by a design change (`bindPresent`, §9). A five-viewport
Studio device matrix passes. Six physical-device checks remain owed (§14).

### 5.2 `.contextMenu` — why it is Missing

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

### 5.3 Named non-deliveries

Three gaps are understood and deliberately not closed. They are written down as
decisions rather than left to be rediscovered:

- **`Toggle` cannot compose a `Label`.** `Toggle` is a non-container **leaf**
  with a flat `label` prop, so an icon-plus-title toggle needs a hand-rolled
  composite that would duplicate Toggle's focus and activation wiring. SwiftUI's
  `Toggle` takes an arbitrary label *view* ([SW-56]), which is exactly the
  affordance missing here. This is a **real** gap and an ordinary settings-screen
  pattern. Closing it means making `Toggle` a container the way `Button` is one —
  control-authoring work, flagged for a future mission. Note that `Button` being
  a container does *not* by itself solve the same problem for `Button`: its own
  `label` prop is likewise a flat string, so a Label-shaped button is custom
  content inside one activation surface, not a `Label` passed to `label`.
- **Baseline alignment and `.alignmentGuide`** — §4.4.
- **`Spacer(minLength:)`** — Composable today via `minMax`; a first-class prop
  would be sugar and is not built.

### 5.4 Caveats on the catalog

- **`PopupButton` row heights.** Its `sheet` presentation derives row height from
  the theme's `regular` control size, which resolves to the 44 px minimum hit
  target, so the touch path never serves a row below the floor. The pointer-only
  `menu` presentation still serves 36 px rows — genuinely below the 44 pt hit
  region Apple's HIG asks for ([SW-72]), but confined to a pointer-only code
  path. Panel flip/clamp behaviour and selection-only rows are unchanged and
  unaddressed.
- **No `*Style` protocol** — see §6.1. This is a decision with a mapping, not a
  hole.
- The full SwiftUI control catalog is not exhaustively re-listed here. Items not
  named above were not independently examined; §1 says what that silence means.

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
`LabelStyle` protocols.** Native Roblox StyleSheets and theme packages own paint,
and a parallel custom rendering-substitution protocol would be a second authority
over the same pixels. The roadmap's priority rule is explicit that a
Roblox-native mechanism ranks above a parallel custom one when it meets the
behaviour bar, and here it does.

What a SwiftUI author reaching for a `*Style` should reach for instead:

| Apple's protocol | What you are actually trying to change | LuauUI route |
|---|---|---|
| `ButtonStyle` — fills, corners, press/hover treatment | paint | The theme package's `control` decoration slot, its per-state art maps, and the semantic `role` prop. Native StyleSheets carry the state selectors |
| `ButtonStyle` — a button whose *content* is arbitrary | structure | `UI.Button` is a **container**: put your own blueprint inside it. All of it stays one activation surface with one focus stop |
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

**Two things a theme is refused, and why each refusal is the honest answer.**

- **The circular progress ring takes no art.** A `Path2D`'s entire property
  surface is `Color3`, `Thickness`, `Closed`, `Visible`, `ZIndex` — every cap and
  join name was probed by name and is absent — and `IsA("GuiObject")` is
  **false**, so no stylesheet rule can ever select one and no image layer can be
  parented to follow a partial arc. A package therefore gets the ring's *colour*
  and its two metrics (`circularSize`, `circularThickness`) and nothing else; cap
  shape is not a thing the engine has. This is enforced by the absence of a slot
  rather than by a named validator.
- **The spinner's dot takes no art, and the compiler says so.** The five dots
  differ only in the tint the control rewrites every frame; a `tint` on a Box
  claims `BackgroundColor3`; and the moment art covers a node, the
  image-is-the-element rule suppresses exactly that plate. The decoration's own
  colour then comes from the per-state chrome tint ladder, which is identical
  across all five dots — so the first package to declare a dot image would ship
  five identical pictures that never move. A frozen spinner is the one lie this
  control must not tell, and nothing headless would have caught it. So
  `themes.define` **refuses a `spinner` art recipe at compile time**, and the
  message ends at the knobs that do retune a dot (`spinnerDotSize`,
  `radii.control`, `strokes.hairline`, `colors.accent`). The criterion is
  general and written down beside the table, so a second slot can join without a
  second argument: a slot is refused art when the control writes its colour
  continuously and that colour is the only thing carrying a live fact.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `*Style` protocols | **Missing, by decision** | See the mapping above | — |
| View modifiers that attach validated data to a node | **Covered** | **Sixteen** ship: `shadow`, `gradient`, `corners`, `stroke`, `styleGroup`, `frame`, `padding`, `offset`, `aspectRatio`, `alignment`, `overlay`, `background`, `containerRelativeFrame`, `sensoryFeedback`, `draggable`, `dropTarget`. Each normalizes to bounded data at construction; none substitutes rendering. The positional-scalar sub-family (`offset`, `aspectRatio`, `alignment`) is declared **closed** by the API constitution — a new modifier with three or more fields takes a spec table | `src/blueprint.luau`; [`constitution.md`](constitution.md) E-18 |
| Style properties that react to state changes after mount | **Covered** | Eleven: `shape`, `surface`, `role`, `shadow`, `gradient`, `corners`, `stroke`, `textAlign`, `scaleMode`, `compactLabel`, `icon` — re-applied on every reactive change through the live paint/semantics dirty loop, in a declared order | `src/render/renderer.luau` (`STYLE_PROP_ORDER`) |
| Materials — blur, vibrancy, translucency ([SW-73]) | **Missing** | Nothing in the framework produces a blurred, backdrop-sampling, or translucent material. Apple's `Material` is explicit that this is not opacity — it is "a platform-specific blending that produces an effect that resembles heavily frosted glass", with vibrancy on top ([SW-73]). Theme packages work in flat fills, nine-slice art, gradients (alpha capped at 0.9), and layered image chrome — all opaque compositing | — |
| Liquid Glass (`.glassEffect()` ([SW-74]), `GlassEffectContainer` ([SW-75])) | **Missing**, and **the gap is widening** | Apple shipped Liquid Glass across the 26 releases — iOS/iPadOS/macOS/tvOS/watchOS 26 ([SW-74]) — and a year later its HIG still presents it as the current functional layer above content ([SW-76]), so this is a settled production system rather than a preview. LuauUI has no counterpart at any layer, and none is planned in any open design record | — |
| `.tint(_:)` cascading down a subtree | **Partial** | Per-node tinting is real and reactive: `tintRole` tints semantic icon art from the active theme's roles, `Image.tint` is a live reactive write, and a continuous colour-blend channel (`{ role, blend, from? }`) can animate between two theme roles — the channel the indeterminate spinner's pulse rides (§5). **What is absent is inheritance**: no `.tint()` recolours an entire subtree; every tint is per-node opt-in. One honest wrinkle in the comparison: Apple's `tint(_:)` page says only that it "Sets the tint color within this view" and **documents no subtree-inheritance rule** ([SW-77]) — SwiftUI's cascade is a consequence of its environment model, not of a sentence anyone can point at | `src/blueprint_schema.luau`; [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 6 |
| Dark mode / colour schemes ([SW-78]) | **Covered** | Native StyleSheets ship `Theme Dark` and `Theme Light`, swapped at runtime with no remount and no loss of focus or scroll | [`ADR-0018`](../adr/ADR-0018-native-stylesheets.md) |
| Theme packages owning metrics and chrome, not just colours | **Covered** — no SwiftUI equivalent ([SW-10]) | A package owns typography, spacing, control heights, radii, strokes, solver-visible content insets, and asset chrome. `theme_controller.install` / `.swap` / `.swapPackage` performs one transaction — repointing the engine's style-sheet inheritance plus committing the new metric snapshot — so geometry and paint cannot disagree for a frame. Validated at definition time for contrast, completeness, legal properties, insets, and touch-target floors | [`ADR-0019`](../adr/ADR-0019-theme-packages.md); `src/client/theme_controller.luau` |
| Rich, image-driven skinning | **Covered** — no SwiftUI equivalent ([SW-10]) | **Seventeen** decoration slots (`panel`, `control`, `field`, `selection`, `divider`, `scrollbar`, `sliderTrack`, `sliderThumb`, `badge`, `barTrack`, `barFill`, `barCap`, `barCenter`, `stepperPlate`, `toggleTrack`, `toggleKnob`, `spinner`), each recipe carrying **up to 8 art layers** from a closed kind vocabulary. Plus per-state art maps, value-display hosts drawn full-size and revealed through a clip window (so a value change costs no instance write), semantic icons with an ASCII-safe fallback that can never render as tofu, a `"pixel"` rendering mode with integer snapping, and `selectBy` to pick a package by input paradigm | [`ADR-0020`](../adr/ADR-0020-rich-skinning-v2.md); `src/tokens/chrome_slots.luau`; `src/themes/package.luau`; `src/client/theme_controller.luau` |
| Dynamic Type ([SW-79], [SW-80]) | **Covered** — a rigorous equivalent | The player's Roblox "Text size" preference is first-class layout input, the way Apple's is on every platform it supports — and note that Apple's does *not* cover macOS ([SW-80]), while LuauUI's applies everywhere it runs. The framework measured the actual pixel offset each preference adds and uses those **measured per-preference constants** (Medium 0, Large 4, Larger 10, Largest 14 — uniform across font, weight, and size) rather than guesses; the engine paints `TextSize + offset` and the solver reserves exactly that box. Changing the preference mid-session re-solves every mounted surface in place, preserving identity, focus, scroll, and state. Eight typography roles carry font descriptor and line height together, and the offset composes additively with ten-foot (TV) scaling | `src/env/environment.luau`; `docs/guide/05-styling.md` |
| Text that must fit a box it cannot fit | **Covered** — no SwiftUI equivalent ([SW-10]) | A four-step degrade cascade, described below the table | `src/layout/shrink.luau`; `tests/text_degrade_cascade.spec.luau` |
| `compositingGroup()` ([SW-133]) / `drawingGroup()` ([SW-134]) — flatten a subtree into one composited layer | **Partial** — `compositingGroup`'s job is covered, `drawingGroup`'s is not | The `canvasGroup` prop on `Box` and `ZStack` materializes the node as a Roblox `CanvasGroup`: the subtree renders into that node's own buffer, and the node becomes its subtree's real instance parent. That is exactly what `compositingGroup()` buys — "A compositing group makes compositing effects in this view's ancestor views, such as opacity and the blend mode, take effect before this view is rendered" ([SW-133]) — and it is what makes a whole-subtree fade one engine property (`GroupTransparency`) instead of a per-node transparency write that would contest native-sheet paint. It is **required, not optional**, for a fading transition: `controller.setPresentationTransparency` refuses a node that is not a declared `canvasGroup` and the message names the fix. The half that is missing is `drawingGroup`'s: Apple's flattens "this view's contents into an offscreen image before final display" ([SW-134]) as a **rasterization** step, and a `CanvasGroup` re-renders its children every frame — so declaring one buys grouped alpha, never a cached bitmap, and it costs a render buffer. It is deliberately **not reactive**: it decides which engine class the node *is*, at creation, so it cannot arrive as a later prop write | `src/blueprint_schema.luau`; `src/render/renderer.luau` (creation-time class choice, and the refusal) |
| `hidden()` — invisible, uninteractive, and still occupying its layout box ([SW-140]) | **Covered**, and **wider than Apple's** | The `hidden` box prop, on every rendered class. Apple's sentence is the specification and all three clauses are implemented: hidden views "are invisible and can't receive or respond to interactions. However, they do remain in the view hierarchy and affect layout" ([SW-140]). This is the one place where LuauUI arranging **absolutely** — it materializes no `UIListLayout`, `UIGridLayout` or `UITableLayout` anywhere — turns an engine limitation into a non-issue: Roblox documents `Visible = false` as freeing the layout slot *inside those layouts*, and there are none here, so the box simply stays. Neither existing answer was this: `UI.When` removes the node and the siblings close up, and a losing `ViewThatFits` candidate collapses to zero. **Wider than Apple's in one respect**: `hidden()` takes no argument ("Hides this view unconditionally", [SW-140]) and Apple's page directs you to an `if` for the conditional case — which removes the view from layout, exactly what `UI.When` does — so LuauUI's is bindable, because otherwise the space-reserving case would have no spelling at all. It dirties `arrange` and merges into the **same** hidden set the solver publishes for a losing `ViewThatFits` candidate, so one line buys the paint walk, the hit-rect retraction, the focus-order filter and the structure-epoch bump | `src/blueprint_schema.luau`; `src/render/renderer.luau`; `tests/lifecycle_hooks.spec.luau`; fixture `examples/gallery/scenarios/lifecycle_hidden.luau` |
| `opacity(_:)` — fade a view without removing it ([SW-141]) | **Covered**, on `Box` and `ZStack` | The `opacity` prop: `1` is opaque, `0` is invisible while the node stays laid out, focusable and tappable — `hidden` is the modifier that takes all three away. **Declaring it makes the node a fade group**, so an author never writes `canvasGroup = true` beside it. That restriction is the whole design rather than a shortcut: a fade in this framework is one `CanvasGroup.GroupTransparency` write, which is the only alpha property no style rule owns, and a leaf fade would have to write `BackgroundTransparency`/`TextTransparency` — both natively sheet-owned, where an explicit write does not win a frame but **permanently defeats the rule**. The price is concrete: `TextTransparency`'s rule is the disabled state's, so a `UI.Text` that accepted an opacity would stop dimming when disabled, forever — measured in Studio 2026-08-15, `GetStyled("TextTransparency")` reads `0.6` disabled before the write and `0.5` (the write) disabled after it, and unparenting does not recover it. **The deeper fact, and the one that closes the question** ([ADR-0029](../adr/ADR-0029-leaf-opacity-refusal.md)): a composition needs a base term, and `GetStyled` is the only way to read the sheet's value — so the act of composing destroys the input the composition needs. A leaf fade built on `GetStyledPropertyChangedSignal` re-multiplies its own output on every state transition and reaches `T = 0.998` after four disable/enable cycles. **The refusal now speaks**: `opacity` and `canvasGroup` on any other class are a construction error naming the rule, the consequence and the wrap, rather than a generic unknown-property message. The **offerable-term rule** it generalizes to: a term is offerable on a class where ONE engine property no rule owns expresses it for that class's whole painted output — which is exactly why `scale` and `rotation` are on all 21 rendered classes and this is on two. The spelling for a leaf is one wrap, `UI.ZStack { opacity = 0.4, children = { … } }`, which is SwiftUI's own answer too — without a compositing group, ancestor opacity applies per-descendant, and that is what `compositingGroup()` exists for ([SW-133]). **The composition rule is Apple's, verbatim**: applying opacity to a view "that has already had its opacity transformed… multiplies the effect of the underlying opacity transformation" ([SW-141]). LuauUI resolves it at the ONE presentation write site as `T = 1 − (1 − T_framework) × opacity_authored`, so an authored `0.5` inside a transition at half-way paints `0.25`, and a framework fade to nothing still reaches nothing. **The authored value is a second TERM, never a second WRITER** — nothing writes an engine property called opacity, and the prop-parity checker *refuses* an adapter branch for one. Across nodes the framework composes nothing at all: a fade group really is its subtree's instance parent, so a nested group's alpha is multiplied by the **engine**, and doing it in the framework as well would fade a descendant faster than its parent. Reactive, and animatable through `withAnimation` (§8.1) | [`ADR-0026`](../adr/ADR-0026-authored-presentation-composition.md); `src/blueprint_schema.luau`; `src/render/presentation.luau` (`composeAlpha`); `tests/authored_presentation.spec.luau` (the offerable-term rule is pinned there as an invariant over every class, not a spot check) |
| `scaleEffect(_:anchor:)` — scale rendered output without changing layout ([SW-147]) | **Covered**, on every rendered class | The `scale` prop: paint-only uniform scale about the node's centre, `1` unscaled. **The solver never sees it** — the layout box, the tap target and the focus position are all the unscaled ones — which is Apple's own rule: the view's "original dimensions … are considered to be unchanged by scaling the contents. To change the dimensions of the view, use a modifier like `frame()` instead" ([SW-147]). It **multiplies** with whatever scale the framework is applying (a motion pop, an enter transition), composed at the same one write site as `opacity`. Two differences from Apple's, both stated rather than hidden: there is **no `anchor` parameter** (the pivot is always the centre, because the adapter re-anchors the instance to `0.5, 0.5` while a scale is live), and there is no non-uniform `x`/`y` form. A `Button`'s press dip shares the engine's single `UIScale` per object, so the dip is relative to the authored scale — down to `resting × pressedScale`, back to `resting` — and an authored scale survives every press | [`ADR-0026`](../adr/ADR-0026-authored-presentation-composition.md); `src/blueprint_schema.luau`; `src/render/presentation.luau` (`composeTransform`); `tests/authored_presentation.spec.luau` |
| `rotationEffect(_:anchor:)` — rotate rendered output in two dimensions ([SW-146]) | **Covered**, on every rendered class | The `rotation` prop, in **degrees**, `0` upright and positive clockwise, about the node's centre. Like `scale` it moves no layout and no hit geometry — LuauUI hit-tests solved rects, so a rotated button's tap target is its unrotated box — which is Apple's rule too: the modifier "has no effect on the view's frame" ([SW-146]). It **adds** to any rotation the framework is applying, because rotations compose by addition; that is the same one rule the other two follow, each in its own group. Apple's takes an `anchor` and LuauUI's does not, for the same reason `scale` does not. Reactive and animatable | [`ADR-0026`](../adr/ADR-0026-authored-presentation-composition.md); `src/render/presentation.luau` (`composeTransform`); `examples/gallery/scenarios/with_animation.luau` |
| Cascade / selector model | **Covered** (supporting infrastructure) | Rules resolve by priority first, then insertion order (later wins); there is no CSS-style specificity, on purpose, so the generator and the runtime can never disagree about which rule applies. Instances are classified for the cascade by `luau-*` CollectionService tags | [`ADR-0018`](../adr/ADR-0018-native-stylesheets.md); `src/client/native_style.luau` |

#### The text degrade cascade — what happens when a label cannot fit

A label that is offered less room than its words need has to give something up,
and the order it gives things up in is a design decision rather than an accident.
LuauUI's is a ladder of **derived floors**: each rung is a smaller width the text
node is allowed to be squeezed to, and a rung is only reached when the one above
it still does not fit.

1. **Natural.** An authored `minMax.min` if there is one; otherwise the width of
   the longest single word, because that is the narrowest a wrapped paragraph can
   honestly be.
2. **Compact.** If the node declared a shorter form of itself — a `Button`'s
   `compactLabel` is the shipped case — the floor drops to *that* string's
   longest word. "Add to favourites" becomes "Favourite" before anything is cut.
3. **Truncate.** The floor drops to the width of a single ellipsis. The string is
   now narrower than its own longest word, so it cannot wrap, and the engine's
   always-on end truncation cuts it with `…`.
4. **Clip.** Whatever the ladder still cannot absorb is clipped at the box edge
   in the arrange pass. Clip is the pass's floor guarantee, not a fourth rung —
   it is what makes "text never paints outside its box" true unconditionally.

Two rules keep it predictable. A text node opts in by declaring `shrinkWeight`;
a node that has not asked to shrink is never degraded. And an authored
`minMax.min` is never a rung — it wins at every level, so a caller who has said
"this may never be narrower than 120 px" is believed.

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
hand-off are all genuinely strong. But there is **no assistive-technology bridge
of any kind** — a repository-wide search for screen-reader, VoiceOver, TalkBack,
accessibility-label, or ARIA concepts returns nothing outside design-intent
comments. A blind player cannot use a LuauUI interface. There is also no
consumer-facing hover state, no raw key-press seam, and no
Home/End/PageUp/PageDown or type-ahead navigation.

Two structural issues sit underneath the table. Gesture machinery exists in
**four independent implementations** that share almost nothing. And LuauUI's
input model has a **platform prerequisite** the framework cannot enforce — §7.2.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| Assistive-technology bridge (VoiceOver / TalkBack) | **Missing** | Nothing. Confirmed by whole-repository search. The bar this is measured against is SwiftUI's accessibility surface, whose own framing is to try the app "with accessibility features like VoiceOver, Voice Control, and Switch Control" ([SW-81]) | — |
| Focus system (`@FocusState` ([SW-85]), `.focusSection` ([SW-86]), Tab order) | **Covered** — and wider than the model it copies: Apple ships `focusSection()` on **macOS and tvOS only** ([SW-86]), while LuauUI's grouped scopes are the same everywhere | `LuauUI.newFocusGraph`: flat and grouped scopes, per-group axis/wrap/entry/exit, directional navigation, and Tab/Shift+Tab traversal in true document order — which is deliberately a different order from the concatenated group arrays | `src/focus/focus_graph.luau`; `src/init.luau` |
| Four-input + device-idiom conformance proof | **Covered** | **16 of 16** interactive controls prove reachability on mouse, touch, keyboard, and gamepad *and* prove the device-idiom axis, across 51 registered rows | `tests/conformance/controls_registry.luau`; `tools/lune/check_registration_cli` |
| `.sensoryFeedback` — feedback tied to state changes ([SW-70]) | **Covered**, plus a per-control form Apple has no equivalent of | The change form: when the `trigger` Readable changes, `{ type = event, path }` is emitted on the presenter's feedback bus. The control form: `{ activation = verb }` names what THIS control's press means and replaces the `activate` the presenter would otherwise emit — cascading down the mounted tree, nearest declaration winning, so it reaches every composite control with no per-control plumbing. The taxonomy is **closed** for both, so an unregistered name is an authoring error listing the twelve valid ones plus `none`. **LuauUI itself still plays nothing** — but the declaration now reaches the engine, and the engine does. Detail in §7.1 | `src/blueprint.luau`; `src/present/feedback.luau`; `src/mount.luau`; `src/present/presenter.luau`; `tests/sensory_feedback.spec.luau`; `tests/control_feedback.spec.luau` |
| Haptics playback | **Partial** — opt-in, **default off**, three device rows unprovable here | `src/client/haptics.luau`, an opt-in client adapter over `HapticEffect`. It plays a control's DECLARED verb through that button's own press-effect property, so a Buy button and a Cancel button feel different — and LuauUI still never calls `Play()` for a press. §7.1 | `src/client/haptics.luau`; `tests/haptics.spec.luau`; `tests/control_feedback.spec.luau` |
| Gesture value type (normalized `Gesture`) | **Partial** — real primitive, zero consumers | Kind, state, positions, translation, velocity, scale, rotation; all six gesture kinds connected; publicly exported. No control calls it | `src/input/touch_gestures.luau`; `src/init.luau` |
| Gesture composition (`.simultaneously` ([SW-92]), `.sequenced` ([SW-93]), `.exclusively` ([SW-94])) | **Partial** | A ranked single-owner arbiter (pinch/rotate > pan > long-press > tap/swipe) with a begin/change/end ownership lifecycle. No simultaneous delivery and no chaining. Same "no consumers" caveat as above | `touch_gestures.newArbiter()` |
| `DragGesture` → general drag & drop ([SW-95], [SW-96]) | **Partial**, materially deeper than SwiftUI's | Public `UI.draggable`/`UI.dropTarget` with a typed payload, tap-to-arm, per-input-class promotion thresholds. Three acquisition paths — Roblox's native `UIDragDetector`, a pointer-capture fallback, and a non-pointer arm→navigate→commit flow for keyboard and gamepad — funnel into **one** shared session lifecycle. Two facts about the other side: `draggable(_:)` is not offered on tvOS or watchOS at all, and the `dropDestination(for:action:isTargeted:)` overload was deprecated in the 27.0 releases in favour of a session-based one ([SW-95], [SW-96]) | `src/input/drag_contract.luau`; `src/input/drag_registry.luau`; [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 5 |
| Detecting and adapting to which device is in use | **Covered** | Per-class promotion thresholds; live hot-switching proven mid-gesture (a user who starts with a mouse and continues with touch is handled explicitly, not accidentally) | `src/input/interaction_tokens.luau` |
| Keyboard modifier chords ([SW-97]) | **Partial** | `action.bind` accepts `modifiers = { shift = true }` and the real-engine realization compiles that into two engine bindings (left and right Shift as `PrimaryModifier`). **Shift is the only *bindable* modifier.** Ctrl and Cmd/Meta are separately *trackable* — `system.modifiers()` exposes them collapsed into one `toggle` boolean, which is how `Table`'s Cmd/Ctrl-click works — but they are deliberately not accepted as bind flags, because a `ctrl` flag there would type-check and never fire. Alt/Option is untracked entirely. Apple's own `EventModifiers` set is `capsLock`, `command`, `control`, `numericPad`, `option` and `shift` ([SW-97]), so this is a real narrowing rather than a difference of vocabulary | `src/input/actions.luau`; `src/client/roblox_input.luau` |
| `.keyboardType(_:)` — which soft keyboard a field raises ([SW-135]) | **Partial** — declared everywhere, honoured nowhere | `TextField.keyboardType` is a real closed-enum prop — `default \| numeric \| email \| phone` — validated at construction, carried on the binding authority, and mapped by the adapter onto the closest `Enum.TextInputType` member by name. It is **capability-detected and currently inert**: `TextBox.TextInputType` is not writable from a game script in the shipped engine, so the adapter probes, records the intent, and skips the write; the day the engine opens it, every declaration already in the tree starts working with no consumer edit. Apple's is narrower than its name suggests too — `keyboardType(_:)` has **no macOS and no watchOS availability at all** ([SW-135]) | `src/controls/text_input.luau`; `src/blueprint_schema.luau`; `src/client/screen_target.luau` |
| `accessibilityReduceTransparency` — the player asked for opaque backgrounds ([SW-136]) | **Covered** (ADR-0035, 2026-08-15) | Roblox surfaces the setting as `GuiService.PreferredTransparency`, a 0–1 scalar where 1 is the default and 0 means the player wants fully opaque backgrounds. LuauUI reads it into the `preferredTransparency` fact and derives `effectiveTransparency`, which clamps a garbage or NaN reading to the legal domain instead of propagating it — and **the framework now paints with it**. The scope is a measurement rather than a taste call: `Scrim backdrop` is the ONLY rule in LuauUI's generated sheet whose `BackgroundTransparency` is strictly between 0 and 1, and the bespoke painter mirrors it exactly, so the backdrop is the one background there is to make opaque. Every other framework background is already 0 (a surface) or already 1 (a class default), and multiplying the second kind would REVEAL it rather than dim it. The composition is Roblox's own documented recipe (`BackgroundTransparency × PreferredTransparency`), applied by the single writer each paint mode already had — the `Scrim backdrop` StyleRule natively, the adapter's own write in fallback — so no engine property changed hands and `NATIVE_SHEET_OWNED` is untouched. Measured live on a real ScreenTarget: `GetStyled` reports 0.45 → 0.225 → 0.1125 → 0 as the preference falls, with the raw property at 0.0000 throughout. What it deliberately does NOT move: an authored `opacity` (the author's number, and `withAnimation` drives it), the disabled dim (the alpha IS the state), the hairline (a border, not a background), shadows and the focus glow. Apple's is a boolean and its documented meaning is the same intent: "If this property's value is true, UI (mainly window) backgrounds should not be semi-transparent; they should be opaque." ([SW-136]) Reduce Motion and Preferred Text Size were already honoured (§6, §8); this was the last one that was not | `src/tokens/sheet_model.luau` (`backdropTransparency`, `PREFERENCE_RULE_PROPS`); `src/render/renderer.luau`; `src/client/screen_target.luau`; `src/client/screen_paint.luau`; `tests/preferred_transparency.spec.luau`; `examples/gallery/scenarios/preferred_transparency.luau`; [ADR-0035](../adr/ADR-0035-preferred-transparency.md) |
| `.onSubmit(of:_:)` — the player pressed Return in a field ([SW-137]) | **Composable**, and the recipe is one line | `TextField.onFocusLost(reason)` is called with `reason ∈ enter \| focusLost \| cancel`, so `if reason == "enter" then submit() end` is submit-on-Return. What is not there is Apple's *scoping* half: the modifier may be set "on an individual view or an entire view hierarchy" and filtered by submit trigger ([SW-137]), and LuauUI has no ancestor-level submit channel and no trigger taxonomy — a form with six fields wires six callbacks | `src/blueprint_schema.luau`; `src/controls/text_input.luau` |
| `.disabled(_:)` — one modifier disables a whole subtree ([SW-142]) | **Missing** as a cascade; per-control `enabled` is real | Every interactive control takes its own `enabled`, and each is consistent across focus, activation, paint and semantics: the three leaves (`Button`, `Toggle`, `TextField`) read it directly, and the composites (`Slider`, `Stepper`, `Rating`, `Picker`, `DisclosureGroup`) resolve it through one shared helper on the control contract — a `Slider` gates its own drag and its own paint rather than delegating to an inner leaf. What there is no spelling for is Apple's cascade: "The higher views in a view hierarchy can override the value you set on this view" ([SW-142]), so an outer `disabled(true)` wins over an inner `disabled(false)`. The engine has the leaf substrate (`GuiObject.Interactable`), and `active` is unrelated — it is the input-sinking flag a modal backdrop uses. **Why a cascade is a mission rather than a prop**: unlike `hidden`, there is no existing set to merge into. A disabled subtree has to reach several independent readers of `props.enabled` (the focus map, the renderer's drag-source gate, the renderer's tap gate, the virtual list's tray-focusable collector), and then needs a *paint* answer for the classes that have no disabled look at all — a `Box`, a `Text`, an `Image` inside a locked panel. That is a cascading channel plus a theme vocabulary, and shipping the channel without the paint would give consumers a subtree that is inert and looks live | `src/controls/contract.luau` (`enabledNow`/`enabledIn`); `src/present/focus_map.luau`; `src/render/renderer.luau`; `src/controls/virtual_list.luau` |
| `.onKeyPress` — raw key seam ([SW-87]) | **Missing** | No raw key event surface. Apple's is hardware-keyboard-and-focus scoped and fires for key-down and key-repeat ([SW-87]) | — |
| Home / End / PageUp / PageDown / type-ahead | **Missing** | Confirmed by keycode grep | — |
| Escape to dismiss a modal | **Partial** — an engine constraint | The Escape key is permanently reserved by Roblox for the CoreGui menu and cannot be intercepted. Cancel is bindable on gamepad ButtonB; keyboard and mouse users close a modal via whatever the screen provides. A keyboard-only user has no framework-level dismiss | `src/present/presenter.luau`; `src/render/target_contract.luau`; `src/client/screen_target.luau` |
| `GuiService.SelectedObject` mirror (engine selection bridge) | **Partial**, experimental | Ships opt-in and non-screen-only: `presentModal({ engineSelectionBridge = true })`, gated so passive surfaces never opt in, with explicit `Selectable` restore when selection moves off. **This does not touch VoiceOver or TalkBack** — it drives Roblox's own gamepad selection cursor, nothing more. Gated behind a physical-device check before it is treated as stable | `src/present/presenter.luau`; supersedes the risk framing in [`ADR-0014`](../adr/ADR-0014-first-responder.md), which still describes driving engine selection as an unexplored risk — the investigation that record asked for was carried out and its result is this shipped, opt-in bridge |
| Dynamic Type / preferred text size | **Partial** | See §6 — the mechanism is thorough; the physical-phone-at-Largest check and the subjective-feel check are still owed | — |
| `.accessibilityAction` — custom accessibility actions ([SW-83]) | **Missing** | Nothing. Apple's exists so that "assistive technologies, such as the VoiceOver, [can] interact with the view by invoking the action" ([SW-83]) — which is the layer LuauUI has none of | — |
| A control's accessibility description (`accessibilityLabel`, [SW-82]) | **Partial** — prose only | Every control declares an `accessibility` string on its control contract (§1), but it is typed as a human-readable summary and the only consumer asserts it is non-empty. It reaches no platform API and no assistive technology | `src/controls/contract.luau`; `tests/controls_conformance.spec.luau` |
| `.onHover` / `isHovered` ([SW-88]) | **Missing** as a consumer surface — and note Apple's is itself pointer-platform-scoped, absent from tvOS and watchOS ([SW-88]) | Hover exists but is framework-internal: an automatic, pointer-gated chrome effect. One narrow dwell-based seam exists for a single feature (revealing truncated text) | `src/render/target_contract.luau` |
| `.pointerStyle` — cursor shape ([SW-89]) | **Partial** — seam live, no art. The comparison is narrower than the row name suggests: Apple's `pointerStyle(_:)` is **macOS 15 and visionOS 2 only**, with no iOS or iPadOS availability at all ([SW-89]) | A `cursorHint` prop exists on `UI.Grip` only (the property-authority table restricts it to that class), and the cursor-art table is empty, so every hint falls back to the default arrow | `src/render/authority.luau`; `src/client/screen_target.luau` |
| Right-to-left / bidirectional layout and text ([SW-90], [SW-91]) | **Missing** | Nothing mirrors layout or reorders text runs. The presenter says so in its own source. The only `rtl` token in the codebase is an unrelated **progress-bar fill direction** for chrome recipes — do not mistake it for RTL support. The bar: Apple's frameworks "support right-to-left (RTL) by default, allowing system-provided UI components to flip automatically" ([SW-91]), with `layoutDirection` as the environment switch ([SW-90]) | `src/present/presenter.luau`; `src/tokens/chrome_slots.luau` |

### 7.1 `sensoryFeedback`, the per-control hook, and the haptics adapter

**The question this section answers, in plain language: when a player presses a
button, what happens?**

Three things are involved, and keeping them apart is the whole design.

1. **A control says what its press MEANT.** Not "buzz", not "play a click" — a
   verb from a closed list, like `commit` or `reject`. That verb
   **is a semantic bus event, and LuauUI plays nothing**.
2. **A game decides what a verb is worth.** It subscribes to one bus and may play
   a sound, a haptic, a particle, or nothing at all.
3. **An optional adapter turns verbs into Roblox haptics**, off unless a game
   switches it on.

**The taxonomy is closed and versioned** — twelve verbs, frozen at
`src/present/feedback.luau`:

`activate`, `select`, `adjust`, `pickup`, `commit`, `reject`, `cancel`,
`arrive`, `land`, `dismiss`, `supersede`, `celebrate`.

Growing it is a contract amendment with a gate, never an ad-hoc string at a call
site — taxonomy sprawl, every control inventing its own verb, is the named risk.
An unknown verb is an authoring error that lists the vocabulary. Events fire
synchronously on the frame that caused them, with subscriber errors quarantined,
and the bus is live-consumed in production
(`games/RascalRally/code/src/client/LuauUISponsor/PlayFlow.luau`).

#### The two forms of the modifier

`UI.sensoryFeedback` takes either of two spec shapes, discriminated by key set
and never mixed — a spec carrying both would have two causes and one verb, and
there would be no honest answer for which cause the verb described.

```lua
-- THE CHANGE FORM (Apple's). A Readable moved; say so.
UI.sensoryFeedback(bp, { trigger = score, event = "celebrate" })

-- THE CONTROL FORM (no SwiftUI equivalent). This control's own press is a
-- commit, not a generic activation.
UI.sensoryFeedback(UI.Button({ id = "Buy", label = "Buy" }), { activation = "commit" })
```

`activation` accepts the twelve verbs plus one extra word, `"none"`, for a
control that must be felt as nothing. `"none"` is not a thirteenth verb —
nothing is emitted at all — and it has to be spellable, or the only way to
silence one control is to silence the whole adapter.

**The control form is a CASCADE, and that is what makes it a general mechanism
rather than a Button special case.** Every activatable thing in this framework
except three leaves (`Button`, `Toggle`, `TextField`) is a *composite*: a Chip, a
Stepper, a Table row and a PopupButton each build their own inner Button. A
`sensoryFeedback` *prop* would therefore have to be threaded through ten control
specs and remembered by the eleventh. Resolved down the mounted tree instead —
nearest declaration wins — one declaration reaches a composite's inner button,
every control in a panel, and every row a `ForEach` mounts later, with no
per-control plumbing anywhere:

```lua
-- every button inside this panel, however deeply nested, is a `select`
UI.sensoryFeedback(UI.VStack({ id = "Filters", children = { … } }), { activation = "select" })
```

Resolution lives in `mount.luau`, the only layer that walks blueprint-to-node
top-down; the presenter reads the resolved value off the node it already looked
up, so a press costs one extra field read. A tree that declares nothing stores
the field nowhere and buys no observer.

**What a press emits.** The presenter emits the resolved verb in place of
`activate`, on the same causal frame, from every input class, and stamps
`reason = "activation"` on it. That stamp is load-bearing: without it a
subscriber cannot tell "a player pressed a control" from "the game emitted
`commit` for its own reason", and the haptics adapter has to, for the reason
below. A control declaring `"none"` emits nothing at all rather than a verb every
subscriber would have to know to ignore.

#### What Roblox actually offers, measured

The engine facts are recorded with sources in
[`../research/2026-08-12-haptics-engine-facts.md`](../research/2026-08-12-haptics-engine-facts.md)
and re-confirmed live in Studio against client `0.734.0.7340915`.

- **`HapticEffect`, never `HapticService:SetMotor`.** Roblox's own class
  reference says the service is superseded; `SetMotor`'s value range,
  persistence and zeroing requirement are all undocumented, and a motor you
  cannot prove stops is a stuck-rumble bug with no test.
- **`Enum.HapticEffectType` has exactly six members** — `Custom`, `UIHover`,
  `UIClick`, `UINotification`, `GameplayExplosion`, `GameplayCollision` — and
  indexing a name that is not one of them **throws** rather than answering `nil`,
  so the lookup has to sit inside a `pcall` or a typo is a crash.
- **`GuiButton.PressHapticEffect` and `HoverHapticEffect` are assignable
  references the ENGINE fires**, writable from a LocalScript with no security
  tag.
- **There is no capability API.** `UserInputService` has zero haptic members;
  `HapticEffect` has no `IsSupported` and no `IsPlaying`. The only probe on the
  platform belongs to the superseded service, is boolean, and answers `false`
  both for "this device has no motor" and for "no gamepad connected *yet*" —
  measured with zero pads attached, `false` on all eight slots and all six
  motors.
- **The player's own haptics preference is unreadable from game code.**
  `UserGameSettings.HapticStrength` refuses the read with *"The current thread
  cannot read 'HapticStrength' (lacking capability RobloxScript)"*.

**Per input class, honestly.** Gamepad is documented and physically verifiable.
Phone is documented ("most iPhone, Pixel and Samsung Galaxy devices") and
unverified here. Desktop with no controller has nothing to play on and is a
silent no-op by construction. And this repository's dev machine is macOS, which
the full-release announcement lists as unsupported for *all* attached game
controllers — so **no Studio session on this machine can ever be positive
evidence**, and a silent run must never be recorded as "haptics do not work".

#### How playback works, and what it cannot do

**Note how narrow SwiftUI's own playback is before treating this as a gap.**
Apple's `SensoryFeedback` cases are documented as playing **"on iOS and
watchOS"** only ([SW-71]) — so on macOS, tvOS and visionOS `.sensoryFeedback`
publishes an intent that nothing plays either. "The verbs are published; the
playback is a platform question" is the same answer both frameworks give, and
LuauUI's version covers Roblox's two haptic-capable classes of device.

**One opt-in client adapter, DEFAULT OFF** (`src/client/haptics.luau`). Off means
no construction, no play, and no device listener. It is a *subscriber*: nothing
in `src/` outside `src/client/` names a haptic symbol or requires it, pinned by a
grep test over every file in the tree.

```lua
local hap = haptics.new({ enabled = settings.haptics })  -- default false
hap.bind(presenter)          -- the verbs with no engine hook
hap.attachButtons(screenGui) -- the press route
```

The `activate` verb takes a **property route**: the adapter assigns a
`HapticEffect` reference to a button and the **engine** fires it, so "LuauUI
plays nothing" stays literally rather than nearly true — a test pins that exactly
one `:Play()` call site exists in the whole module, and it is the bus path.

**The per-control declaration reaches that route through an attribute.** The
renderer publishes each activatable control's resolved verb to the adapter
(`setActivationFeedback`, an optional seam), and the Roblox adapter realizes it
as `LuauUI_ActivationFeedback` on the materialized button. The haptics adapter
reads that attribute and hands the button the pooled effect for its verb: a
`commit` button gets `UIClick`, a `reject` button gets `UINotification`, a
`"none"` button has its reference actively **cleared** rather than skipped, and a
verb the map deliberately silences is unfelt too. Effects are pooled by
*sensation*, so forty buttons wanting a click share one Instance. The seam is
pushed for every activatable node including the `nil`, because instance recycling
would otherwise let a commit button hand its sensation to whatever control adopts
its object next.

**Why that route, and not simply playing the bus event: a press would be felt
twice.** The engine is already firing the button's own press effect, so the
adapter drops every event stamped `reason = "activation"`, whatever verb it
names.

**What this cannot do, plainly.** Four things:

- **A `TextField` is a `TextBox`, not a `GuiButton`**, so it has no press-effect
  property and its declared verb is published but not felt on the engine route.
  The bus still carries it; a game that wants that press felt plays it itself.
- **`attachButtons` must actually be called.** A game that binds the presenter
  and never attaches a surface gets no press haptics at all — a wiring step
  nothing warns about.
- **The adapter cannot honour the player's own haptics preference**, because the
  platform will not let it read it. It owns its own switch and makes no claim
  about the player's; a game with a haptics setting is the answer, and that is
  the accessibility position rather than an omission.
- **Nothing here is felt on this machine.** Effects construct and `Play()`
  without throwing in Studio; they cannot be felt without hardware Roblox
  supports.

**Reduced motion is deliberately NOT a gate on haptics.** `ReducedMotion` is a
statement about animation — a preference against vestibular triggers — and a
haptic tick is not motion on screen. Apple keeps the two settings separate for
the same reason. The player-facing control for haptics is the adapter's own
switch, which is why it is opt-in and default off.

**Five of the twelve verbs map to nothing from the bus, deliberately**:
`activate` (the engine fires it through the property route), `arrive` (fires on
every chase settle — a haptic there is per-frame noise), `cancel` (the *absence*
of feedback is the signal for "nothing happened"), and `dismiss` and `supersede`
(not player-caused; buzzing at a self-retiring toast is a phantom). The map is
asserted **total** over the taxonomy, explicit "no" included, so a future
taxonomy addition shows up as a visible gap instead of a silent drop. `adjust` is
**rate-limited** — sliders and steppers fire per tick, and unthrottled that is a
buzzsaw that also blows the documented simultaneous-effect budget.

The capability probe is a **lattice**, not a boolean:
`supported | unsupported | unknown | blocked | absent`, with **`unknown` the
default for touch and for the pre-first-gamepad state**, re-probed on
`GamepadConnected` / `GamepadDisconnected` / `LastInputTypeChanged` rather than
cached at boot — because the only probe the platform offers is exactly the shape
that lies.

**Evidence, split honestly.** Headless proves the cascade, the closed vocabulary,
what each press emits from every input class, the engine-route resolution, pool
bounds, default-off costing zero constructions and zero plays, mapping totality,
`adjust` coalescing under a fake clock, and the probe returning `unknown` rather
than `false` for touch. Live Studio proves the engine facts above and that the
adapter's resolution rules produce the right reference on a real `TextButton`.
**No machine here can produce positive playback evidence**, so three rows stay
`PENDING_PHYSICAL` and only a device closes them (§14).

### 7.2 The platform prerequisite: LuauUI needs the Input Action System

**Plain language first.** Roblox ships its own player scripts — the camera, the
jump control — and historically they claim keys through an older mechanism,
`ContextActionService`. LuauUI claims keys through the newer one, `InputContext`.
Those two are **not one arbitration space**, and that is not a tuning problem:

> Measured live: a sinking `ContextActionService` binding at priority **100**
> beat a LuauUI `InputContext` at priority **10000**. With the camera unbound the
> same LuauUI claim worked immediately. A sinking legacy binding consumes a key
> before *any* `InputContext` is offered it, at any priority.

So there is no number this framework can write that takes a key back from a
legacy binding. Two concrete consequences in a default place:

- **Gamepad ButtonA is eaten** by the legacy jump action, so gamepad Activate
  goes silently dead on every button.
- **The arrow keys are eaten** by the default camera script, so arrow-key focus
  navigation does nothing — and any control that wants Left/Right, such as
  `Table`'s column resize, cannot have them. That claim was built, measured
  against the camera, and *withdrawn* rather than shipped inert.

**The resolution is `Workspace.PlayerScriptsUseInputActionSystem`.** With it
enabled, Roblox's own player scripts join the same `InputContext` arbitration
LuauUI uses, and priority means what it says. Be precise about the evidence
level: the ButtonA case has been researched against Roblox's own documentation
and devforum guidance; **the arrow-key case has been measured only with the flag
off.** "Enabling the flag fixes the arrows" is reasoned from the same mechanism,
not separately confirmed live here.

**Nothing in LuauUI enforces this, deliberately.** The framework ships opt-in
probes — `legacyStackActive()`, `cameraKeysContended()`, `traversalKeyContended()`
and `describeContention()` in `src/client/gamepad_contention.luau` — that a
consumer or a doctor tool can call, and the example bootstraps call them. They
are *not* wired to a boot-time warning, because in every place that has not
ticked the flag the warning would fire always, and a warning that always fires
is noise that trains people to ignore it.

A third contention is unrelated to this flag and worth not confusing with it:
**Tab** is the CoreGui players-list key, a documented and readable condition
rather than a priority fight.

(`docs/lessons/the-camera-still-owns-the-arrow-keys.md`;
`docs/lessons/gamepad-buttona-jumpaction.md`;
`docs/research/2026-07-21-first-responder-platform-research.md`;
`src/controls/table.luau`, which carries the four measured readings in full.)

**Caveats.**

- **Gesture machinery is fragmented four ways**: the touch-gesture arbiter (which
  nothing consumes), the general drag contract, row actions' own pointer-capture
  and axis-lock state machine, and `Table`'s hand-rolled vertical reorder drag.
  No file imports more than one of them. A thin arbitration layer sits between
  two of them and they share the axis-lock constant; the underlying gesture state
  and math are still duplicated.
- Six physical-device checks are owed by row swipe actions and three more by
  haptics (§14).

---
## 8. Motion

LuauUI's motion system is authoritative and opinionated. Springs are declared
with SwiftUI's two-number model — Apple spells the second number
`dampingFraction` on `Animation.spring` ([SW-98]) and `dampingRatio` on its
`Spring` type ([SW-99]) — and never with mass and stiffness, which SwiftUI *does*
also offer, through `interpolatingSpring(mass:stiffness:damping:initialVelocity:)`
([SW-100]); the refusal is LuauUI's design choice, not a gap in Apple's. An
inline spring literal at a call site is a **hard error** that names the
registration function — springs must come from one of four registered classes, so
the design system cannot drift one call site at a time. Retargeting a spring
mid-flight never touches its current value or velocity, so a spring interrupted
by a new target continues rather than jumping; a differential test proves it, by
showing a velocity-cut twin travels measurably less on the next frame.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `withAnimation` — implicit write⇄interpolation coupling ([SW-143]) | **Covered** over the solver's whole output — position **and** size — and over the authored presentation triple (`opacity`, `scale`, `rotation`) | `presenter.withAnimation(class, fn)`. Apple's page is silent on which properties animate ([SW-143]); the rule lives on `Animatable`, which states that SwiftUI "reads the old and new `animatableData` values, then interpolates between them over successive frames" ([SW-144]). LuauUI's answer to "which values" is exact, and §8.1 states it | `src/present/presenter.luau`; `src/render/renderer.luau` (`installAnimationRecords`); `src/render/presentation.luau`; `tests/with_animation.spec.luau`; `tests/animation_precedence.spec.luau`; `tests/authored_presentation.spec.luau`; `examples/gallery/scenarios/with_animation.luau` |
| `.animation(_:value:)` — implicit animation attached to a VIEW rather than to a mutation ([SW-148]) | **Missing** | Every animation in LuauUI is declared at the mutation site or by a control that owns its own motion. There is no modifier that says "animate this subtree whenever *that* value changes" — Apple's returns "a view that applies `animation` to this view whenever `value` changes" ([SW-148]). The gap is a *declaration site*, not a capability: `withAnimation` reaches the same result when the author owns the write, and cannot when the write is somebody else's | zero occurrences |
| `.spring(response:dampingFraction:)` ([SW-98]) | **Covered** | The same two-number model. Four named classes ship — `container` (ζ 1.0, 0.35 s), `object` (1.0, 0.28 s), `reward` (0.7, 0.18 s), `decay` (1.0, 0.5 s) — and inline literals are refused with a did-you-mean. `reward` is the only under-damped class, deliberately: overshoot is earned, and liveliness elsewhere comes from inherited gesture velocity rather than decorative bounce | `src/motion/classes.luau` |
| Spring interruption / retargeting ([SW-100]) | **Covered** — the same guarantee Apple states for `interpolatingSpring`, which "Preserves velocity across overlapping animations" ([SW-100]) | `setTarget` never touches value or velocity, and `getVelocity()` makes carry-over implementable rather than aspirational | `src/motion/motion.luau` |
| Animation completion callbacks ([SW-101]) | **Covered**, callback-based | `MotionValue:onSettle(fn)` fires exactly once per arrival, after that frame's writes commit — the same once-only contract SwiftUI states for its completion variant ([SW-101]). No awaitable form | `src/motion/motion.luau` |
| `phaseAnimator` — effects over a sequence of phases driven by a trigger ([SW-102]) | **Missing** | No looping or state-driven phase construct | zero occurrences |
| `keyframeAnimator` / `KeyframeTimeline` — "a description of how a value changes over time" ([SW-103]) | **Partial**, via a different shape | `clock:timeline(spec)` is beat-sequenced choreography with `interrupt()` and `skip()`. Each beat is a callback, not a per-property value track with its own curve, and a timeline never loops | `src/motion/clock.luau` |
| `.transition(.insertion/.removal)` ([SW-104]) | **Covered** — general, reusable | `UI.ForEach{transition}` and `UI.When` share one structural-region property. Forms: `fade`, `slide-up`, `slide-down`, `slide-left`, `slide-right`, `materialize`, `instant`. A removed row **retires in place** — it stays mounted at its clamped slot, non-interactive, and disposes on exit-complete — rather than vanishing. Slide travel is a theme metric, not a magic number, so a roomier theme slides further. Hard 500 ms exit cap | `src/render/transitions.luau`; [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 3 |
| `matchedGeometryEffect` — shared-element / hero transitions ([SW-105]) | **Partial** (built 2026-08-16, navigation-and-menus D4) | The **selection** case ships, as a PROPERTY rather than a construct: `newPicker`'s `indicator = "underline" | "pill"` interpolates one decoration's frame rectangle from the previously selected option's solved rect to the new one — Apple's own description of the effect, "interpolate their frame rectangles… to make it appear that there is a single view moving from its old position to its new position" ([SW-105]) — in two skins on both axes. It is scoped to ONE tree: the seam resolves its segments' rects by id inside the strip it wraps, in `rectOf`'s raw host space. The general form — carrying identity across **two** layout trees, a hero transition between screens — is still missing: `withAnimation` animates *surviving* paths inside one commit and does not carry identity across two trees | `src/controls/selection_indicator.luau` (internal); `newPicker` in [`api.md`](api.md) |
| `.scrollTransition` ([SW-106]) | **Missing** | No API ties paint to a node's live proximity to the viewport edge — Apple's animates "as this view appears and disappears within the visible region of the containing scroll view" ([SW-106]) | zero occurrences |
| Reduce Motion ([SW-84]) | **Covered** — information-preserving, not a switch | The OS signal is read live on every retarget, not snapshotted at boot. Motion is categorized: *decorative* motion snaps instantly but still fires `onSettle`, so completion logic is unaffected; *informational* motion (a count-up whose number is the message, or the indeterminate spinner of §5) keeps running to the same terminus but quantizes its writes to a 250 ms step, so the information survives while the animation stops being animation | `src/motion/motion.luau` |
| `.numericText` / animated numerals ([SW-107]) | **Covered**, plus more | `clock:counter` publishes whole numbers only and never overshoots its target. On top of it, `motion.newValueReveal` composes a hold/count/land layer under two rules — never state a new value before its moment, never withdraw a stated one. SwiftUI's `numericText` transition is the numeral half only ([SW-107]); there is no single built-in for the hold/count/land layer ([SW-10]) | `src/motion/clock.luau`; `src/init.luau` |
| Countdown / depleting timer | **Covered** | `clock:timer(spec)` advances on raw wall-clock delta, not frame-clamped time, so a frame spike cannot stretch a countdown | `src/motion/clock.luau` |
| Gesture → animation velocity hand-off | **Covered** | A 100 ms rolling-window velocity tracker feeds both a general drag flight (seed velocity, then chase a live target) and row-actions flick momentum (read the tracker at release, seed the persistent spring) | `src/input/drag_velocity.luau` |
| "Arrive at a live, moving target" in 2-D | **Covered** — no single SwiftUI API ([SW-10]) | `clock:chase(opts)`: two scalar springs against a target re-read every frame, firing `onArrive` once the value enters a *perceptual* arrival radius (4 px by default) rather than waiting for physics settle epsilon — which the framework measured as trailing perceived landing by about 0.7 s | `src/motion/chase.luau` |
| `.sensoryFeedback` | **No host equivalent by design** | See §7.1 — the verbs are published, the playback is the game's | `src/present/feedback.luau` |

### 8.1 `withAnimation`, precisely

`presenter.withAnimation("container", function() open:set(true) end)` — **the
layout lands exactly and instantly as it always did, and every node whose box
changed is *painted* travelling from where it used to be to where it now is,
over one spring.**

**What it animates, stated as a rule rather than a list.** `withAnimation`
interpolates the difference between two commits, so the values it can interpolate
are the values a commit *produces*: the solver's rect — `x`, `y`, `w`, `h` — and
the three authored paint values `opacity`, `scale`, `rotation`. A node that moves
slides; a node that grows or shrinks opens and closes; a node that does both does
both, on one shared progress spring, so a panel finishes growing on the very
frame the rows it displaced finish sliding. A card that slides, grows *and* fades
finishes all three on one frame — three separate springs would drift apart in a
way no screenshot could catch.

The authored triple is a different kind of thing from a solved rect, and that
difference is why an *authority* decision had to come before the animation
could. LuauUI's presentation channel had no authored prop in it at all — its
three presentation-authority properties (`transform`, `transparency`,
`dragHeld`) were every one of them renderer-driven — so there was literally
nothing authored for `withAnimation` to diff.
[ADR-0026](../adr/ADR-0026-authored-presentation-composition.md) is the decision
that opened it, and §6 carries the composition rules the three props follow.

**What is still left is colour.** A `tint` is a binding-authority prop written
straight to the adapter, so animating it would mean interpolating a value the
renderer does not diff between commits. It is a real gap and it is not closed.

**The position/size asymmetry an author has to know.** A record carries a
per-path delta and the write composes it onto the solved rect at the adapter's
one `Position`/`Size` write. The position half **accumulates down the subtree** —
LuauUI's instance tree is flat, so a container's move carries nothing inside it
and every descendant must re-add its ancestors' offsets. The size half **does
not**, and it is the same fact reaching the opposite conclusion: a container's
growth carries nothing inside it either, and there that means a child must keep
its own solved size while the box around it opens. Records are therefore
installed at animation *roots* for position and per node for size, and a
`UI.Text` inside a growing card neither drifts nor stretches. The authored deltas
are likewise per-node and do not accumulate: a fade group genuinely *is* its
children's instance parent, so a descendant that also faded on its own would fade
twice.

**Why animating a size is legitimate and not a hack.** Apple's own pages will not
settle it for you — `withAnimation`'s says nothing about which properties animate
([SW-143]) and `frame(width:height:alignment:)` does not contain the string
"animat" at all ([SW-145]); the rule lives on `Animatable` and is stated in terms
of *animatable values* ([SW-144]). So the decision is LuauUI's. Animating a size
means a wrapped `TextLabel` re-wraps, a `Slice`/`Tile` image re-caps, a clip host
crops, a `CanvasGroup` re-buffers and a `Stage` re-projects — those are what
animating a size *means*, and SwiftUI's frame animation means them too. The one
genuinely new per-frame cost is buffer-backed nodes (`canvasGroup`,
`Stage`/`ViewportFrame`) re-allocating to a size that changes every frame, and
the performance lab's `motion-flight` workload is where that is measured rather
than argued. Icon art and normalized `Path2D` control points are *not* an extra
cost: the position animation already calls `applyRect` on every handle in the
animated subtree every frame, and `applyRect` already refits both — size changes
two numbers inside calls that were already happening.

None of the three authored values is a substitute for the size half, and Apple is
explicit about why: `rotationEffect` "has no effect on the view's frame"
([SW-146]), and `scaleEffect`'s dimensions "are considered to be unchanged by
scaling the contents. To change the dimensions of the view, use a modifier like
`frame()` instead" ([SW-147]). LuauUI keeps that exactly.

**Hit geometry follows the painted POSITION and the solved SIZE.** That is the
ratified rule: `screenRectOf` composes presentation offsets so a shifted control
is pressable where it looks, and a node mid-growth hit-tests at the box it will
have — the same rule a scaled node follows. A flight is short and its geometry is
exact at both ends.

The rest of the contract, in one list:

- **It is a presenter method, not `UI.withAnimation`.** The constitution reserves
  `UI.lowerCase(bp, …)` for modifiers, which take a blueprint and return a frozen
  one; this takes no blueprint. It lives on the presenter because the presenter
  is the only thing that owns all three collaborators — the motion clock it
  builds, the controller scopes that own the records, and `refresh` itself.
- **The class is a NAME.** Inline `{ dampingRatio = … }` is refused here as
  everywhere else; `motion.registerClass` is the one dial.
- **Surviving paths only.** Structural insert and remove stay the transition
  system's job. A path another writer already owns — a structural transition,
  keep-visible — is excluded, and **the exclusion is the path, not its subtree**:
  a whole-subtree exclusion would be a silent, permanent no-op on any surface
  holding a `UI.TextInput`, because every text field declares a keep-visible
  offset that writes a zero transform onto the *root* at boot.
- **Only `fn`'s consequences.** The presenter drains pending work *before*
  arming, so an unrelated discrete change that fired two milliseconds earlier
  does not animate at full delta. Env-driven relayouts — theme swap, viewport
  resize, preferred-text change — are never armed; animating a whole-tree theme
  relayout is a frame-budget accident, not a feature.
- **One shared progress spring per call.** A subtree provably cannot tear,
  because every component of every record is the same `p` times its own delta.
  Records are owned per **path**, so a second call touching a path the first is
  still animating re-bases it — carrying the offset *and* the extent it is
  painted at right now — rather than putting two springs on one slot.
- **Three refusals**, and one is late: nesting inside another `withAnimation`
  (arming is presenter-wide, so the inner call's disarm would silently kill the
  outer animation); an unknown class name; and "nothing flushed", which means
  either an outer `core:transaction` is still open **or** this ran during a core
  commit. That last one raises **after `fn` has already been applied**, so a
  caller catching it must not retry the mutation or it lands twice. The message
  says so.
- **Reduced motion is an explicit branch that installs no records at all.** `fn`
  still runs, the transaction still commits, the layout is still exact; there is
  simply no flight, and a size lands instantly for the same reason a position
  does. That is legal precisely because this motion is **decorative** — the
  instant layout already carries every fact and the travel was pure continuity.
  Worth knowing when writing a test against it: under reduced motion the spring
  settles *synchronously inside* `setTarget`, so records install and clear within
  the call and no record **count** can tell the branch from its absence. What the
  branch buys is the writes it never spends, and that is what
  `tests/with_animation.spec.luau` asserts.
- **Not reachable from inside a control.** Controls receive the presenter's
  *products* through contributions, never the presenter itself, so
  `row_actions`, `table` and `disclosure_group` cannot animate their own internal
  state through this API. That matches SwiftUI, where `withAnimation` is called
  at the mutation site and takes the mutation itself ([SW-05]). The named escape
  hatch if it proves too tight is a `presenter.animator()` handle — **not
  built**, and confirmed absent from source.
- **There is no per-frame record cap.** Nothing bounds `animationRecordCount()`.
  The roots-only rule keeps the count near the number of things that actually
  started moving, which is why this is a gap and not a live defect. It is named
  here because a reference entry once described a cap that was designed and never
  built.

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
| `.sheet` — modal presentation ([SW-108]) | **Partial** | `presenter.presentModal` with a focus trap and per-depth priority banding. Named, validated options: `cancelPolicy`, `scrim`, `outsideTapCancel` swallow semantics, `initialFocus` | `src/present/presenter.luau` |
| `.interactiveDismissDisabled` / tap-outside behaviour ([SW-109]) | **Covered** internally, no public mirror | The dismissal geometry is forgiving by design: the "inside" region is the painted panel plus a forgiveness ring, unioned with each focusable's minimum hit rectangle, so a near-miss on a control does not dismiss the modal. Both distances are **theme metric roles** (`space.l`, `targetSizes.minimum` — 24 px and 44 px under Studio Neutral), not magic numbers. No public property mirrors `.interactiveDismissDisabled` | `src/present/modal_zones.luau`; `src/tokens/default_light_style.luau` |
| `.fullScreenCover` ([SW-110]) | **Composable** | `presentModal` + an edge-to-edge root policy + a full-bleed root blueprint. Apple's own is platform-scoped in a way the name hides — iOS, tvOS and watchOS, **not macOS** ([SW-110]) | — |
| `.alert` / `.confirmationDialog` ([SW-111], [SW-113]) | **Composable** | Recipes only. **No item-binding sugar** — the item-driven alert has no analogue; a consumer wires its own signal. Name that carefully: the live symbol is `alert(_:item:actions:)` ([SW-111]), and the `alert(item:content:)` spelling was **deprecated in the 27.0 releases** ([SW-112]). Nothing here orders or tints a Cancel row automatically, and SwiftUI does both — "The system may reorder the buttons based on their role and prominence", and a `cancel`-role button replaces the default dismiss action ([SW-113]) | — |
| `.popover` / transient panel ([SW-114]) | **Partial** | `newPopupButton` plus a presenter-managed tap-away catcher. The catcher supports a non-consuming mode, so a tap-away can close the popup *and* still reach the control underneath. Adaptation is the divergence worth knowing: on iPhone, SwiftUI's popovers adapt into sheets ([SW-114]); LuauUI's presentation choice is `resolvePresentation`'s, made from option count, size class and live input | `presenter.syncPopupCatcher` |
| `.swipeActions` / `.contextMenu` as a secondary-action container ([SW-37], [SW-50]) | **Partial** | `LuauUI.newRowActions` — a real construct, not a recipe, with the gaps named in §5.1 and no `contextMenu` trigger (§5.2) | `src/controls/row_actions.luau` |
| Floating surface that contributes nothing to its ancestor's layout | **Covered** — architecturally significant, no SwiftUI-named equivalent ([SW-10]) | `bindPresent`, part of the input contribution seam (§1). Deliberately routes through `presentModal`, never `present`: two screen-kind surfaces would share one priority band, so each would receive the same input twice. (Navigate, Activate and Cancel here are semantic *input actions* the presenter routes to whichever surface owns the band — an entirely separate vocabulary from the 12 feedback verbs in §7.1, which are outbound notifications and route to nothing) | `src/input/contribution.luau`; `src/present/presenter.luau` |
| `ButtonRole` (destructive / cancel) ([SW-115], [SW-116]) | **Partial** | `role: "normal" \| "destructive"` on an action paints the shipped danger style. No `cancel` role, and no automatic dialog-row ordering — which SwiftUI does have, though it is documented on the dialog rather than on the role ([SW-113]) | — |
| `NavigationStack` ([SW-117]) / `NavigationPath` ([SW-118]) — screen push/pop | **Partial** at best | Only surface stacking: `presentModal` pushes, `back()` pops the top *modal*, `depth()` reports the stack size. There are exactly two surface kinds, `"screen"` and `"modal"`, and a `"screen"` surface is not part of any pop stack. No `pushScreen`, no `navigationPath`, no `screenStack` construct exists anywhere in source | `src/present/presenter.luau`; confirmed by source search |
| `NavigationSplitView` ([SW-69]) / `.inspector` ([SW-119]) / scene management | **Missing** | Zero occurrences | — |
| `.presentationDetents` — snap-to-fraction sheet heights ([SW-120]) | **Missing** | A modal's size is whatever its blueprint measures to. Apple's detents are not the phone-only feature they are often taken for — iOS 16 **and** macOS 13 up ([SW-120]). Building detents would need canvas-height-aware drag physics that do not exist; the closest primitive, `Grip`, is a 1-D value adjuster, not a sheet-height controller | zero occurrences |
| Toast / transient feedback surface | **Covered** — no SwiftUI built-in ([SW-10]) | `presenter.presentToast`, with pure headless scheduling: max 3 visible, queue cap 8, priority-ordered FIFO, typed dismiss reasons (`timeout`, `supersede`, `capacity`, `preempt`, `manual` — "nothing may vanish untraceably"), reduced-motion parity, and input-transparent by construction | `src/present/presenter.luau`; `src/present/toast_schedule.luau` |
| Semantic feedback bus | **Covered** | `presenter.onFeedback`/`emitFeedback` over the closed 12-verb taxonomy, wired into surface lifecycle and toast supersession, and authorable per node via `UI.sensoryFeedback` (§7.1) | `src/present/feedback.luau` |
| Focus trap and restore | **Covered** | Scope push/pop/remove on the focus graph, used by modals and transient popups alike. Row actions' floating menu reusing it unchanged is evidence the mechanism generalizes beyond its original proving ground | `src/focus/focus_graph.luau` |
| Passive (non-capturing) surfaces | **Covered** | `responder = "passive"` plus explicit `engage()`/`resign()`, so a surface can sit over a live 3D world without stealing its input | [`ADR-0014`](../adr/ADR-0014-first-responder.md) |
| Display-order layering | **Covered** | **Four** named `SURFACE_LAYER` bands with an explicit guarantee — `base` (10000) < `toast` (20000) < `dragProxy` (30000) < `modal` (40000) — rather than one incrementing counter. A scrim or tap-away catcher is a fifth *conceptual* layer but is positioned relative to its owner rather than given a band of its own | `src/present/presenter.luau` |
| Two surfaces silently painting over each other | **Covered** — no SwiftUI equivalent ([SW-10]) | Surfaces are independent trees: a HUD, a modal and a debug overlay each solve alone, so nothing in a single solve can see that two of them collide. A cross-surface alarm compares what each surface actually paints — see §9.1 | [`ADR-0028`](../adr/ADR-0028-cross-surface-overlap.md); `src/render/surface_overlap.luau`; `tests/surface_overlap.spec.luau` |
| Full-value disclosure plate; auto-reveal marquee | **Covered** — no SwiftUI equivalent ([SW-10]) | `presenter.disclosure()` shows a truncated value in full on a presenter-private surface with no focus scope and no input context; `presenter.reveal()`/`movingText()` animates long text into view | `src/present/presenter.luau`; `src/present/text_reveal.luau` |
| Surface enter/exit transitions | **Covered** | `opts.transition` on `present`/`presentModal`; `dismiss` defers teardown to the exit coordinator under a flat 500 ms cap | [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 3 |
| Keyboard-only modal dismissal | **Partial** — engine constraint | Gamepad ButtonB is bound to Cancel; Escape is not bindable (§7) | — |

### 9.1 When two surfaces overlap, and who said so

**The problem, in plain language.** Everything a solver knows about "does this
fit" is scoped to one surface. A HUD and a modal and a stray debug overlay are
three separate trees with three separate solves, so a debug probe left mounted on
top of the pause menu is invisible to every diagnostic the framework has — right
up until a player cannot press the button underneath it.

So the renderer keeps a small live registry of surfaces and, when
`controller.diagnostics()` is called, compares each surface's **cover rect**: the
union of what that surface actually paints, with hidden content, `opacity = 0`
content and faded-to-nothing content excluded, because a thing that paints
nothing cannot cover anything.

**It only complains when nobody declared the overlap.** A modal covering a HUD is
the entire point of a modal. The alarm fires only when two surfaces' cover rects
intersect *and* neither side declared an intent to cover, where "declared" means
one of the vocabulary words that already existed: an `edgeToEdge` root policy
("I am decoration, not content"), or a different `SURFACE_LAYER` band (different
bands are intentional layering). An **unset display order** counts as declaring
nothing — which is exactly the shape of the accident this was cut for.

**Who said so.** The finding names both surfaces and the geometry, and it is
filed on *both* of them, because neither is more at fault than the other. Partial
overlap and total containment get different sentences on purpose — "surface 'A'
overlaps surface 'B' by 200×120px" against "surface 'Backdrop' completely covers
surface 'Panel'" — because a clipped corner and a hidden screen with a dead
dismiss are different bugs.

**Cost.** Nothing runs on the frame, solve or commit path. A surface pays one
table write when it attaches and one when it retires; the pairwise scan happens
only on an inspection call, and only when more than one surface is live.

---

## 10. Performance

LuauUI has serious performance instrumentation: **20** named production-shaped
workloads in a self-contained lab place, p50/p95/p99 headless timing, live heap
and reactive-graph counters, a *fixed* set of **12** closed MicroProfiler phase
scopes (the scope count does not grow with row count), and — the most durable
piece — regression budgets encoded as **ratio tests rather than wall-clock
thresholds**. Those five rules (work scales with what changed; a cache key must
cover what it caches; nothing unchanged gets rebuilt; an unchanged value fires
nothing; the cheap path stays cheap) are each annotated with the real historical
regression that motivated them, so they cannot be quietly deleted as flaky.

**Read every number in this document with its tier attached.** Headless Lune is a
**regression signal** and never a device claim; the MicroProfiler in Studio is
real engine work with real instance counts; only a physical device run supports a
device claim. **No physical device run has ever happened.**

Real instance-cost wins have shipped and been measured: instance recycling,
theme-aware recycling, incremental layout (141→8 arranged nodes, ~17×), eliding
inert containers (137→91 instances, −34 %), lazy `UIScale` (about −10 % instances
framework-wide), and replacing three O(N) row-geometry loops in `Table` with one
prefix sum (−95.4 % ± 0.1 on the flowing path, against a ±3 % A/A band). Two
results were reported honestly rather than flattered: the placement audit and the
shrink pass each landed **inside the same-arm noise floor** on an interleaved
20-scene × 5-profile suite, and the `containerRelativeFrame` cache-key widening
measured **+14 %/+19 %/+23 %** p95 on three scroll scenes when applied
unconditionally, which is why the container term joins the key only once a
container-relative dimension has actually been measured (conditioned: +0.8 % /
+1.5 % / +2.4 %, inside noise).

| Capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| Named, production-shaped workloads | **Covered** | **20** scenes, each with its own budget entry: `animation-interruption`, `async-image-burst`, `async-image-grid`, `collection-mutation`, `dense-hud`, `dense-motion`, `hud-binding-storm`, `lab-collection-churn`, `lab-dense-scroll`, `locale-textsize-change`, `native-scroll-drag`, `screen-lifecycle-churn`, `scroll-focus-traversal`, `settings-churn`, `shadow-storm`, `stylesheet-state-churn`, `theme-swap-assets`, `theme-swap-flat`, `theme-swap-metrics`, `virtual-list-scroll` | `bench/perf_scenes.luau`; `bench/perf_budgets.json`; `examples/performance/lab/perf_lab.luau` |
| Percentile timing | **Covered** | p50/p95/p99, headless | `bench/perf_runner.luau`; `tools/perf.sh` |
| Regression budgets as executable tests | **Covered** — stronger than a wall-clock gate | Five invariant/ratio rules, each tied to the regression it once caught | `bench/perf_budgets.json`; `tests/perf_principles.spec.luau` |
| Heap / reactive counters | **Covered** | `handle.controller.stats()` reports property writes, rect writes, creates, removes, arranged and skipped counts; a lifecycle census counts GuiObjects, signals, memos, and scopes, proven zero-drift across 8 identical mount/unmount cycles | `src/render/renderer.luau` |
| Profiler phase attribution | **Covered** | **12** closed scopes, capped by `profile.MAX_SCOPES` and asserted by a test: `mutate`, `react`, `measure`, `arrange`, `commit`, `resource`, `mount`, `scenario`, `reset`, `present`, `focusmap`, `tick`. The last three exist because a frame that solves nothing read zero on every other scope while the frame was not free — measured at 2.09 ms/frame of unattributed presenter work, most of it re-deriving the focus map | `src/core/profile.luau`; `tests/profile_scopes.spec.luau` |
| Per-property invalidation granularity vs SwiftUI ([SW-04]) | **Covered**, with one counterexample | A single bound-value change costs the same at 100, 800, and 3200 rows — work scales with what changed, not with what exists, enforced as a ratio test. Incremental layout narrows that change from a full-tree re-solve to its relayout boundary (~17× measured). The counterexample is the next row | `tests/perf_principles.spec.luau`; `tests/incremental_layout.spec.luau` |
| Cell recycling for composite-wrapped rows | **Missing**, and not the lever it looks like | `newVirtualList` has no cell-recycling seam: crossing the window boundary destroys and recreates a row's structure, which is coarser than SwiftUI's lazy containers, which "create items only as needed" ([SW-21], [SW-31]). Be careful with the comparison, though: **Apple documents no view reuse or recycling for `List` or the lazy stacks anywhere** ([SW-34]) — reuse is an inference from behaviour, not a documented contract to measure against. And the feature that made this hurt no longer needs it: hosted row actions mount **nothing** on a closed row (§5.1). Generic cell recycling was weighed and **not chosen**, because recycling never removes wrapper instances from the tree and so could not have met the instance budget on its own | [`row-actions-hosted-mode-design.md`](../plans/row-actions-hosted-mode-design.md) |
| Measurement discipline | **Covered** — no SwiftUI or Xcode analogue ([SW-10]) | Same-arm A/A noise floors are measured and stated *before* any A/B number is reported; arms are interleaved (ABBA), never run in blocks; budgets are called on ≥5-run means. The project has a recorded **false signal** from a non-interleaved A/B taken when the same-arm floor had drifted from 0.31 % to 1.88 % across a session — which is why the rule exists | `artifacts/row-actions/device-matrix.md` |
| On-device performance measurement | **Missing** | `artifacts/phase-4/perf.json` records `"deviceRun": false`, `"authoritative": false`, `"evidenceLevel": "E1"`. The budget file's `skippedDeviceBudgets` lists `phone-physical`, `desktop-retail`, and `console-physical` as all pending. The full phone-capture procedure is documented in enough detail for an agent to execute — the artifact slot is simply unfilled | `artifacts/phase-4/perf.json`; `bench/perf_budgets.json` |
| Xcode Instruments equivalent | **Partial** — headless only | Headless percentile timing with versioned budgets. No on-device, symbolicated, UI-specific profiler. For the record on the other side: Processor Trace and the CPU Counters instrument shipped in **Xcode 26** ([SW-121]); Xcode 27 added the Swift Executors instrument — tracks for the cooperative thread pool, the main actor and custom executors — and a Hitches metric that replaces the Organizer's Scrolling metric ([SW-122]). LuauUI has a counterpart to none of them | `tools/perf.sh`, `tools/bench.sh` |

**Caveats.**

- The lab place ships with a build doctor and a scriptable driver, and its
  low-end-Android capture procedure is written so that a Studio row relabelled as
  a phone cannot spoof it. It still has not been run on hardware.
- The swipe-actions perf story is the project's best procedural example: an
  original budget was missed, the gate was re-baselined to the measured ceiling
  with the original kept on record and a follow-on charter filed — not silently
  passed, not deleted, not converted to a TODO — and the follow-on then closed
  the gap and restored the original ceiling.

---

## 11. Tooling & authoring model

This is where LuauUI most clearly optimizes for something SwiftUI does not:
**being maintained by agents as well as humans.** Unknown properties are refused
at construction with a did-you-mean suggestion and the full valid set enumerated.
Exported `*Spec` types describe the public constructor surface. And a family of
checkers reconciles independent views of the same truth so they cannot drift.

What it lacks is the interactive half of Xcode: there is no live, hot-reloading,
resizable in-editor preview, and no compiler-enforced type safety comparable to
Swift 6 — Luau cannot provide it, so LuauUI's answer is a fast, comprehensive
runtime/test-time layer instead.

| SwiftUI / Xcode capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| Strict construction-time validation | **Covered** | `UI.Button({ lable = "hi" })` → *unknown property 'lable'. Did you mean 'label'? Valid properties: …* | `src/blueprint_schema.luau` |
| Typed public constructor surface | **Covered** | **57** exported `*Spec` types across blueprint, controls, motion, layout, drag and transitions. Public core types are re-exported at the boundary; the single `: any` in `src/init.luau` is inside an explanatory comment | `src/init.luau` |
| Property-authority reconciliation | **Covered** — no Xcode analogue | `tools/lune/check_prop_parity.luau` reconciles **six** independent views of every property — dirty classification, render authority, adapter binding, layout consumption, handler wiring, and documentation/types — plus a seventh cross-check restricting binding props by class. It exists because a bound `Text.color` was once silently dropped between two of those views | `tools/lune/check_prop_parity.luau` |
| Conformance registry | **Covered** | Every control must appear with its proofs; enforced by a test, so a control cannot ship unregistered | `tests/conformance/controls_registry.luau`; `tests/extension_checker.spec.luau` |
| Docs-vs-code drift check | **Covered** | `check_docs.luau` holds documentation to a zero-tolerance list against the live export table, including a stale-phrase list of sentences that were true before a feature shipped | `tools/lune/check_docs.luau` |
| Example-gallery drift lint | **Covered** | Reads its role vocabularies live from the framework; fails on raw numbers for style-owned properties, unknown role strings, raw colours, or reaching around the public API into the engine | `tools/lune/check_example_drift.luau` |
| Public-surface ledger coverage | **Covered** | Every top-level export and nested namespace member must be classified in the surface ledger | `tools/lune/check_surface_ledger.luau` |
| Client/server require-graph boundary check | **Covered** | Verified acyclic and correctly split, source against consumers | `tools/lune/check_boundary.luau` |
| Gate system | **Covered** | **28** named gates, plus an integrity checker that verifies every gate's test grep is anchored to the pass marker (a grep that could never fail is itself a defect), plus automated re-running of prior gates | `tools/lune/gate_manifest.luau`; `tools/check_manifest_integrity.py` |
| Scriptable in-Studio verification | **Covered** | A `LuauUIScenarioAPI` folder of BindableFunctions lets an external driver run scenarios inside a live Studio session | `examples/gallery/scenarios/runner.luau` |
| Deterministic render dumps | **Covered** | Every control exposes a `dump()` seam, required by the scaffold template and the registry, so layout output can be diffed exactly | `tests/conformance/corpus_cli.luau` |
| Runtime diagnostics surface | **Covered** | `controller.diagnostics()` returns a defensive copy of live complaints — overflow, unbounded percent, unbounded containers, mixed grid children, inert placement props, HUD zone collisions, and cross-surface overlap. Project history records this surface naming a shipped layout defect that a screenshot review had missed | `src/render/renderer.luau`; [`the-solver-already-told-you`](../lessons/the-solver-already-told-you.md) |
| Reference apps as scale proofs | **Covered** | Five clean-room apps (§12) | `examples/reference/` |
| Source-size guard | **Covered** — Roblox-specific, no analogue on either side ([SW-10]) | A module whose source crosses the engine's 200,000-character `Script.Source` write cap cannot be synced into Studio at all, so a checker fails the build before the file becomes unsyncable rather than after. Several modules have been split under it, which is why some solver and control logic lives in files named for one job | `tools/check_source_size.py` |
| Extension scaffold and playbooks | **Covered** | `tools/lune/scaffold.luau` stamps a new control's source seam, dump surface, deliberately-failing spec, and registration edits, so a scaffolded control cannot ship silently unregistered. Six playbooks cover new control / engine feature / platform mode / render target / theme / skinned control | `docs/extending/` |
| Deprecation policy | **Covered** | A machine-readable `LuauUI.DEPRECATIONS` ledger; a deprecated surface keeps working for at least one minor version. `newVirtualList`'s axis-neutral rename left `rowHeight`/`viewportHeight` as the current entries — a `rowHeight` on a sideways list is a lying name, and this codebase punishes those | [`ADR-0011`](../adr/ADR-0011-semver-and-deprecation.md); `src/init.luau` |
| Fuzz / fault / soak testing | **Covered** | Layout, replication, and scheduler fuzzers plus a fault-injection suite | `tests/fuzz_*.spec.luau`, `tests/faults.spec.luau` |
| `#Preview` — live, resizable, hot-reloading in-editor preview | **Missing**, mitigated | No in-editor live preview exists for LuauUI. Mitigated by deterministic dumps, the reference-app corpus, scripted Studio drives, and the showcase place — but all of those are batch, not interactive, where Xcode's previews are "dynamic, interactive" in the canvas ([SW-123]). Xcode 27's addition here is a **Resizable Canvas mode** for iOS previews, "arbitrarily sized containers" ([SW-122]). LuauUI's device matrix is the scripted analogue | — |
| Compiler-enforced type and concurrency safety | **Partial** — runtime-enforced | `--!strict` Luau plus the checkers above plus a suite of several thousand cases, all running in seconds. It catches misuse at test time, not edit time. Swift 6's strict concurrency is compiler-level — it "helps you find and fix data races at compile time" ([SW-125]) — and Luau cannot match it | — |
| Documentation tooling | **Covered** — a stronger claim than generation | Four checkers: three make it impossible for documentation, the live export table, and tutorial examples to drift from shipped code without failing a gate, and the fourth makes it impossible for a row of §§3–11 to assert something about SwiftUI without citing the Apple page it rests on. DocC "makes it easy to produce rich and engaging developer documentation" ([SW-124]); it does not enforce that documentation is true, and neither does the citation check — what that one enforces is that a claim about the other framework is *checkable* | `tools/lune/check_docs.luau` |

**Caveats — where the machinery does and does not help.**

The agentic-maintainability claim holds up, and the row-actions branch is its
best evidence: the registration checker caught a missing conformance row *and* an
implementer's incorrect claim that the failure predated their change; a second
trap in the same task exposed the checker's own name-matching pattern being blind
to underscore-containing exports (passing when it should have failed); an
architectural decision about which directory a module belonged in was steered
directly by the registry's shape of enforcement; and an adversarial review pass
found 16 issues under an all-green suite — the registry catches *absence*,
adversarial review catches *presence of wrong behaviour*, and they are
complementary.

**But the machinery is a backstop, not a preventer.** It refuses to let mistakes
merge; it rarely stops the first occurrence. One class of mistake — an agent
sweeping a whole shared file it did not own — has recurred repeatedly, including
a concurrently running agent restoring `docs/reference/api.md` to `HEAD` and
destroying four separate pieces of uncommitted reference documentation, which
nothing noticed until two checkers went red naming symbols that no longer had
entries. That is a process and isolation problem — multiple agents in one working
tree — not a tooling defect, and no checker fixes it.

Two residual weaknesses:

- A fuzzer that asserts only "does not throw / stays finite / is deterministic"
  can pass over a real behavioural bug. The historical `ScrollView`
  horizontal-axis defect is the named example.
- **The checkers reconcile documentation against the export *table*, not against
  behaviour.** A document can describe a guard that does not exist and every
  checker stays green, because the *symbol* is documented. Nothing in the gate
  machinery reads a paragraph and asks whether it is true.

---
## 12. Reference-app validation

The question underneath this whole document — *can a developer build the
in-experience parts of Apple's own reference apps from one declarative
description?* — was answered by building five of them clean-room: written from a
spec by an author who did not read framework internals, which is what makes them
evidence rather than demos. Ledgers and evidence:
`artifacts/swiftui-reference-app-validation/`.

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
demo-shaped. Their specs (`tests/reference/*_spec.luau`) run in the suite, and
the five places are built by `tools/build_places.sh`.

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

*One caveat on that ledger:* its swipe-actions row still reads "no
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
| Materials / translucency; Apple's Liquid Glass | **Missing, and widening** | §6 |
| `*Style` protocols — no way to substitute a control's rendering | **Missing, by decision** — the mapping is in §6.1 | §6 |
| Screen navigation (`NavigationStack`, `NavigationSplitView`), presentation detents, alert item-binding | **Missing / Partial** — surface stacking only | §9 |
| `phaseAnimator`, `.scrollTransition`, `.animation(_:value:)` | **Missing** | §8 |
| `matchedGeometryEffect` | **Partial since 2026-08-16.** The selection case ships as `newPicker`'s `indicator` property (one tree, rect-to-rect, two skins, both axes); cross-tree hero transitions are still missing | §8 |
| Animating a colour — `tint` is written straight to the adapter, so no commit diff can reach it | **Missing** | §8.1 |
| Alignment guides (`.alignmentGuide` / custom `AlignmentID`) and baseline alignment | **Missing** | §4.4 |
| Lazy grids (`LazyVGrid` / `LazyHGrid`) | **Closed 2026-08-15.** `LazyVGrid` ships as `newVirtualGrid` — the consumer this row said the substrate did not have — and it needed no new windowing and no new column arithmetic (§4.2.2). `LazyHGrid` followed in the same week, and the order is the point: its blocker was named in the vertical grid's own `axis = "x"` refusal, so the prerequisite (`UI.Grid { flow = "column" }`) was built FIRST as a mode of the one grid arithmetic, and the control then gained an axis without gaining any arithmetic | §4.2.2 |
| Measured (self-sizing) item extents in a virtualized collection — `itemExtent` takes a number, a `Readable`, a per-item function, or `"measured"` | **Covered** (built 2026-08-15, `0fed5ff`) — `itemExtent = "measured"` with `estimatedItemExtent`; the row measures itself through one control-owned `Content` wrapper, so convergence is ONE step, not a loop. A measured list files no lying-`itemExtent` finding because it makes no prediction | §4.2 |
| Row actions on a **virtualized** `Table` — `Table` wraps a composite per row, so a windowed row would strand its engine | **Missing** — refused at construction, naming the reason | §4.2.1, §5.1 |
| Multi-selection on `newVirtualList` — the mirror of the hole `Table` closed | **Missing** | §4.2.1 |
| `Toggle` cannot compose a `Label` (it is a leaf, not a container) | **Missing** — named non-delivery | §5.3 |
| Cell recycling for `newVirtualList` rows | **Missing**, and no longer load-bearing | §10, §5.1 |
| `.disabled()` as a subtree **cascade**. Per-control `enabled` ships on every interactive control and is consistent on each; there is no inherited channel, and the classes with no disabled look (`Box`, `Text`, `Image`) would need a theme vocabulary before one would be honest | **Missing** — examined and deferred | §7 |
| Per-row capability opt-outs — SwiftUI's `selectionDisabled(_:)` / `deleteDisabled(_:)` / `moveDisabled(_:)` family | **Covered** — `rowSelectable` / `rowMovable` / `rowDeletable` on both collection controls, one implementation with two wirings | §5, §4 |
| The other 36 of the completeness audit's 39 unexamined capabilities — rich text runs, 2-D transforms, scoped environment, programmatic scroll position, scroll snapping, `Section` headers, localization, `Form`, empty-state, pull-to-refresh, scroll observation, and the rest | **Unexamined**, enumerated and ranked rather than silently absent | [`the audit`](../plans/parity-completeness-audit-2026-08-13.md) §5 |
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

Three more are owed by the haptics adapter (§7.1). Source:
`artifacts/swiftui-parity-round2/phase-3-haptics-evidence.md`.

| Check | What to do | Why it cannot close here |
|---|---|---|
| `haptics-gamepad-felt` | Confirm a mapped verb produces a **perceptible** rumble on a PlayStation/Xbox/Quest pad | Roblox documents controllers on macOS 15+ as unsupported; a silent run on this machine is not evidence that haptics do not work |
| `haptics-phone-felt` | The same on a haptic-capable iOS/Android phone | No device in the loop, and the platform docs say only "most" modern phones have haptics — which is also why touch is permanently `unknown` rather than `supported` |
| `haptics-player-preference-honored` | Confirm the player's own Roblox haptics setting silences or scales what the adapter plays | `UserGameSettings.HapticStrength` is script-security-locked on read *and* write, so the question is unanswerable from inside the process |

One more is owed by the input model (§7.2): a place with
`Workspace.PlayerScriptsUseInputActionSystem` **enabled**, confirming that
arrow-key focus navigation and a control's own Left/Right claim both work against
a live default camera. Every measurement on record was taken with the flag off.

Three older riders also remain open and are not repeated in full here: physical
confirmation of the Dynamic Type equivalent at the Largest preference, a
subjective feel pass on the same, and physical confirmation of the engine
selection bridge. See `artifacts/large-text-accessibility/acceptance.md` and
`artifacts/native-substrate/acceptance-ledger.md`.

---

## 15. Verification appendix

| | |
|---|---|
| LuauUI version | `0.9.0` (`src/init.luau`) |
| Audit date | 2026-08-15 |
| Method | Every verdict in §§3–11 was checked against current source or a named test. Where a claim could not be verified from here, it says so |
| SwiftUI baseline | The shipping surface as documented on developer.apple.com on **2026-08-13**, including Apple's **June 2026** update — the one that pairs with Xcode 27 and the 27.0 OS releases ([SW-129]). Three items in that update touch this comparison directly and are reflected above: drag reordering generalised to stacks, grids and custom layouts (`reorderable()` / `reorderContainer`, [SW-35], [SW-36]), swipe actions generalised out of `List` (§5), and item- and error-driven alerts (§9) |
| Roblox baseline | `UIListLayout` / `UIFlexItem` / `UIFlexAlignment` / `ItemLineAlignment` / `UIFlexMode` documentation re-read on create.roblox.com, 2026-08-13 (§4.1). Engine behaviours that documentation does not state — wrapped-line cross-axis placement, `Path2D`'s property surface, `TextBox.TextInputType` writability, `ContextActionService`-vs-`InputContext` arbitration — were measured live in Studio and each measurement is described where it is used |
| LuauUI baseline | Source only: `src/blueprint.luau`, `src/blueprint_schema.luau`, `src/init.luau`, `src/row_capability.luau`, `src/virtual_extents.luau`, `src/controls/`, `src/layout/`, `src/render/`, `src/present/`, `src/client/`, `src/motion/`, `src/themes/`, `src/tokens/`, `src/input/`, `src/focus/`, `src/env/`, plus `tests/conformance/controls_registry.luau` |
| **The SwiftUI-side denominator** | **365** scored capability groups, being the `groupMarker` headings across Apple's 49 SwiftUI collection landing pages, pulled from the DocC symbol index (`developer.apple.com/tutorials/data/index/swiftui`, 10,988 nodes) on 2026-08-13; 392 groups found, 27 dropped as navigation scaffolding. Of the 365: **127 examined by this document**, 120 with no Roblox substrate, 54 applicable but deliberately out of scope, and **64 unexamined** (deduplicating to 39 named capabilities). Method, reproduction script and the full ranked list: [`../plans/parity-completeness-audit-2026-08-13.md`](../plans/parity-completeness-audit-2026-08-13.md). **This is a bounded catalog, not a percentage score for all of SwiftUI** — §1 says what that means for a reader |

**On line numbers.** Evidence cells name files and tests, not line numbers.
Line references in a document that is re-read months later rot faster than
anything else in it — a sample of the previous set was found pointing into
`src/present/presenter.luau` past the end of the file — and a stale pointer is
worse than none, because it looks precise. Where a number is genuinely
load-bearing it is given as a value (`OVERSCAN = 2`, `MAX_LAYERS = 8`) rather
than as a location.

**Things this document could NOT verify, recorded rather than assumed.**

- **No physical-device evidence exists for anything.** Every four-input, haptics
  and performance claim is E1/E3 (§14).
- **The Input Action System resolution is reasoned, not measured** for the
  arrow-key case (§7.2). The contention itself is measured; the fix is inferred
  from the same mechanism.
- **No citation in §16 proves a behaviour, only a sentence.** Every quote was
  checked as a literal substring of the page it names, on the date given. That
  catches a claim nobody sourced and a page that has since changed; it does not
  catch a claim that misreads a sentence it quotes correctly, and it says
  nothing about what SwiftUI does at runtime beyond what Apple wrote down.
- Prose paragraphs are cited where they make a SwiftUI claim, but the mechanical
  check covers **table rows only** (§16).
- Items in Apple's catalog not named in §5 were not independently examined; §1
  says what that silence means.

Every check below was run live for this revision:

```bash
cd GameStudio/ui/LuauUI
lune run tools/lune/check_docs_cli            # PASS — 9 documents, 81 surface anchors,
                                              #   137 SwiftUI citations, 64 local links
lune run tools/lune/check_prop_parity_cli     # PASS — 26 classes, 643 properties, 680 typed fields
lune run tools/lune/check_registration_cli    # PASS — 25 controls, 91 exports documented,
                                              #   201 specs registered, 16/16 four-input + paradigm
lune run tools/lune/check_boundary            # PASS — 122 src files, 398 consumer files
lune run tools/lune/check_surface_ledger      # PASS — every public export and nested member classified
python3 tools/check_manifest_integrity.py     # exit 0 — 846 suite greps, all anchored to the pass marker
```

Counts quoted in §§5, 10 and 11, reproducible:

```bash
grep -c '^\t\["' tools/lune/gate_manifest.luau                        # 28 gates
grep -rc '^export type.*Spec' src/ | awk -F: '{s+=$2} END {print s}'  # 57 exported Spec types
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
- **Two rows are knowingly uncited, and the checker names both.** The
  `Table.onPrimaryAction` row in §5 quotes Apple's context-menu discussion
  inline but does not link it; the per-row-opt-out row in §13 names Apple's
  three modifiers without asserting anything about them. They are the citation
  debt this document carries, listed as named exemptions in
  `tools/lune/check_docs.luau` — which complains both when an exemption stops
  matching a row and when the row it excuses starts carrying a citation, so
  neither can rot unnoticed.

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
| **SW-20** | [`gridCellUnsizedAxes(_:)`](https://developer.apple.com/documentation/swiftui/view/gridcellunsizedaxes(_:)) | “Asks grid layouts not to offer the view extra size in the specified axes.” | iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+. Plural, and it takes an `Axis.Set` — there is no singular `gridCellUnsizedAxis` | 2026-08-13 |
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
| **SW-112** | [`alert(item:content:)`](https://developer.apple.com/documentation/swiftui/view/alert(item:content:)) | “Presents an alert to the user.” | iOS 13+ — **deprecated in the 27.0 releases** — the live item-driven spelling is [SW-111]'s | 2026-08-13 |
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
| **SW-143** | [`withAnimation(_:_:)`](https://developer.apple.com/documentation/swiftui/withanimation(_:_:)) | “Returns the result of recomputing the view’s body with the provided animation.” Its Discussion is one sentence and is purely mechanical: “This function sets the given `Animation` as the `animation` property of the thread’s current `Transaction`.” **Apple documents no behaviour here** on *which* properties animate — the page never says “size”, “frame”, “geometry”, “state change” or “interpolate” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-14 |
| **SW-144** | [`Animatable`](https://developer.apple.com/documentation/swiftui/animatable) | “A type that describes how to animate a property of a view.” “When an animatable value changes inside a `withAnimation(_:_:)` block (or is affected by an `animation(_:value:)` modifier), SwiftUI reads the old and new `animatableData` values, then interpolates between them over successive frames using `VectorArithmetic` operations.” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-14 |
| **SW-145** | [`frame(width:height:alignment:)`](https://developer.apple.com/documentation/swiftui/view/frame(width:height:alignment:)) | “Positions this view within an invisible frame with the specified size.” “Use this method to specify a fixed size for a view’s width, height, or both.” **Apple documents no behaviour here** on animating a frame size — the string “animat” does not occur anywhere on the page | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-14 |
| **SW-146** | [`rotationEffect(_:anchor:)`](https://developer.apple.com/documentation/swiftui/view/rotationeffect(_:anchor:)) | “Rotates a view’s rendered output in two dimensions around the specified point.” “This modifier rotates the view’s content around the axis that points out of the xy-plane. **It has no effect on the view’s frame.**” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-14 |
| **SW-147** | [`scaleEffect(_:anchor:)`](https://developer.apple.com/documentation/swiftui/view/scaleeffect(_:anchor:)) | “Scales this view uniformly by the specified factor, relative to an anchor point.” “The original dimensions of the view are considered to be unchanged by scaling the contents. To change the dimensions of the view, use a modifier like `frame()` instead.” | **visionOS 1+ only** at this exact URL — it resolves to the `UnitPoint3D` overload. The cross-platform form is [`scaleEffect(_:anchor:)-pmi7`](https://developer.apple.com/documentation/swiftui/view/scaleeffect(_:anchor:)-pmi7) (iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+), whose page does **not** carry the “dimensions unchanged” sentence | 2026-08-14 |
| **SW-148** | [`animation(_:value:)`](https://developer.apple.com/documentation/swiftui/view/animation(_:value:)) | “Applies the given animation to this view when the specified value changes.” “A view that applies `animation` to this view whenever `value` changes.” “The animation to apply. If `animation` is `nil`, the view doesn’t animate.” | iOS 13+, iPadOS 13+, Mac Catalyst 13+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+ | 2026-08-14 |
