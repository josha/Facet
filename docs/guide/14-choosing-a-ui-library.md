# 14. Choosing a UI library

This chapter is optional, and it is not a rulebook. It is one way to think about
a choice that has more than one good answer. You are reading it inside Facet's
own repository, so weigh the Facet column accordingly, and read the linked
sources yourself before you commit a game to anything.

**How the labels work.** Every non-trivial claim below carries one of two marks:

- `[FACT]` — stated by a source pinned in [§14.6](#146-sources), or by a file in
  this repository, cited where it is used.
- `[INFERENCE]` — a conclusion drawn from those facts. It may be wrong, and it
  is marked so you can check it.

There are no measured comparisons on this page. [§14.5](#145-performance)
explains why, and what to measure instead.

## 14.1 What a UI library does for you

Roblox draws its interface from instances: a `Frame`, a `TextLabel`, a
`TextButton`, and so on. With no library you create each one yourself, set every
property by hand, remember to update the right property when your data changes,
and remember to destroy the whole thing when the screen closes. That works. It
stops working well at about the size of a settings menu.

A library takes over three jobs:

- **Description.** You write what the screen should contain, instead of the
  steps that build it.
- **Keeping it in step.** When your data changes, something updates the screen
  for you.
- **Cleanup.** When the screen closes, the instances, the event connections and
  the timers go with it.

These words are used throughout this chapter, so here they are once:

- **Reactive** means a value that other things watch. Change it, and whatever
  depends on it is brought up to date without you calling anything.
- **Re-render** means running your component function again to produce a fresh
  description of the screen, which the library then compares against the old one.
- **Reconciliation** is that comparison: working out the smallest set of
  instance changes that turns the old description into the new one.
- **Granularity** is how small the updated piece is. Coarse means a component or
  a subtree is re-run. Fine means one property on one instance is written.
- **Signal** is a value you can read and set that other things are allowed to
  watch; Fusion spells it `Value`, Vide spells it `source`, Facet spells it
  `core:signal`.
- **Memo** is a value worked out from other values, which recalculates itself
  only when one of those values changes.
- **Dirty entry** is a note that one piece of the screen is out of date, held
  until the library next brings the screen up to date.
- **Scope** is a bag that owns things and destroys them together — but the word
  names three different constructs on this page. Facet's is an ownership scope,
  Fusion's is a cleanup scope, and Vide's reactive scope is a computation that
  re-runs, not only a bag.
- **Token** is a named design value, such as a spacing step or a text colour,
  that you set in one place and every screen reads.
- **Solver** is the part of a library that turns a description into the position
  and size of every box, before anything is drawn.

The one-sentence version of each library:

- **Facet** — a Roblox UI library whose decisions (state, layout, focus,
  adaptation) are plain Luau you can test without an engine, with a thin adapter
  edge that turns the result into real Roblox UI ([the root `README.md`](../../README.md),
  [the guide index](README.md)). `[FACT]`
- **React Luau** — "a comprehensive, but not exhaustive, translation of ReactJS
  17.x into Luau", giving you React's component model on Roblox instances (React
  Luau README). `[FACT]`
- **Fusion** — a Luau library for reactive state and for creating or adopting
  Roblox instances from it, organised around scopes that clean themselves up
  (Fusion documentation, version 0.3). `[FACT]`
- **Vide** — "a reactive Luau library for creating UI", "inspired by Solid",
  built on a source and effect pair, where each reactive property gets its own
  effect (Vide repository description, README, and reactivity documentation).
  `[FACT]`

## 14.2 The comparison

Every cell is `[FACT]` from the source pinned in [§14.6](#146-sources), unless
the cell begins with `[INFERENCE]`. "Yours to write" means the library does not
describe the feature, so the work is yours — not that the work is impossible.

One row needs background first. Roblox has its own styling system, and it is
worth knowing about whichever library you pick. A `StyleSheet` holds
`StyleRule`s that "apply to every instance that matches the rule's Selector",
and a `StyleLink` "links a StyleSheet and its associated rules to a parent
ScreenGui and all of the GuiObjects within it. Only one StyleSheet can apply to
a given tree." Tokens are attributes on a token sheet, themes are token sets you
swap, and Studio ships a Style Editor for editing them (Roblox styling
documentation) `[FACT]`.

That last rule raises a fair question: can your game keep its own `StyleSheet`?
Yes — Facet links one sheet and one `StyleLink` at its own target root, which
the reference calls "per-target isolation", so a sheet your game links to its
own `ScreenGui` is a different tree and is left alone `[FACT]`. The one place
Facet's sheet reaches further is an instance you adopt into a Facet box, because
a `StyleLink` is "ambient in the DataModel and selects by class" `[FACT]`
([`05-styling.md`](05-styling.md) is the authority, and
[`api.md`](../reference/api.md) carries the adopted-instance case).

| | Facet | React Luau | Fusion | Vide |
|---|---|---|---|---|
| **Mental model** | Describe the screen as plain data; a solver decides the geometry; an adapter writes the instances ([`02-architecture.md`](02-architecture.md)) | Components return an element tree, and the library will "efficiently update and render just the right components when your data changes" (React Luau README) | Scopes hold state objects and the instances built from them | Sources hold values; effects created at build time keep single properties current |
| **How much it supplies** | A full UI layer: layout, controls, styling, input, focus, adaptation, motion, render targets ([the guide index](README.md) catalog) | The component model, hooks, refs, bindings, portals, and a root that renders into an instance | Reactive state, instance creation and adoption, collection helpers, tween and spring | Reactive state, instance creation, control flow helpers, spring |
| **Normal state/update path** | A changed value marks its spot. Once a frame, Facet re-lays-out only what moved and writes only what changed ([`02-architecture.md`](02-architecture.md) §2.2) | `[INFERENCE]` `useState` or props change → the component re-renders → reconciliation writes what differs | `Value:set` → dependent `Computed` objects recompute → `New`/`Hydrate` re-assign the bound property | Set a source → the effects that read it re-run → each writes its one property |
| **Reactivity granularity** | Fine. A paint-only change writes that property and does not re-run layout ([`02-architecture.md`](02-architecture.md) §2.2) | Coarse by default (component re-render), plus a fine route: Bindings are "a form of signals-based state that doesn't re-render" (React Luau README) | Fine. A property bound to a state object "is re-assigned every time the value of the state object changes" | Fine. A non-event property given a function makes an effect "to update property" |
| **Cleanup model** | Scopes. Disposing a scope disposes everything it owns, in reverse order, exactly once ([`01-concepts.md`](01-concepts.md) §1.3) | `useEffect` returns a cleanup function; unmounting a root tears its tree down | `doCleanup()` on a scope destroys its contents in reverse order; `innerScope` nests | `root()` returns a destructor; a parent scope's destruction destroys its children |
| **Layout** | A pure two-pass solver produces a rectangle per node, with no instance and no signal reads ([`02-architecture.md`](02-architecture.md) §2.1) | `[INFERENCE]` Roblox's own: you set `UDim2` values or add layout instances, as you would by hand | `[INFERENCE]` Roblox's own, in the property table you pass to `New` | `[INFERENCE]` Roblox's own, in the property table you pass to `create` |
| **Built-in controls** | Nineteen composite controls, including table, virtual list, slider, picker, tabs and text input ([the guide index](README.md) catalog) | `[INFERENCE]` None documented; you compose Roblox classes yourself | `[INFERENCE]` None documented; you compose Roblox classes yourself | `[INFERENCE]` None documented; you compose Roblox classes yourself |
| **Native StyleSheets and Studio theme editing** | The default paint path is a generated Roblox `StyleSheet` named `FacetStyle`, one `StyleLink` per screen, with Style Editor token edits taking effect immediately ([`05-styling.md`](05-styling.md) §5.7) | `[INFERENCE]` Yours to write; `StyleSheet` and `StyleRule` are ordinary instances you can create | `[INFERENCE]` Yours to write, same as the column to the left | `[INFERENCE]` Yours to write, same as the column to the left |
| **Input, focus, device adaptation** | Semantic actions over Roblox's Input Action System, navigation derived from the solved layout, per-device idioms ([`07-input.md`](07-input.md)) | `[INFERENCE]` Yours to write; the library gives you events and refs on the instances | `[INFERENCE]` Yours to write; `OnEvent` connects a callback | `[INFERENCE]` Yours to write; a function on an event property is connected as a callback |
| **Accessibility** | The player's preferred text size adds space to every text box; reduced motion turns the travel off and keeps the result; the dialog backdrop follows the player's own transparency setting ([`api.md`](../reference/api.md) Environment) | `[INFERENCE]` Yours to write | `[INFERENCE]` Yours to write | `[INFERENCE]` Yours to write |
| **Motion** | A motion clock with springs, counters, timers, tweens and timelines, plus a reduced-motion form for each ([`api.md`](../reference/api.md) Motion) | `[INFERENCE]` Bindings are offered for animation; the animation itself is yours to drive | `Tween` and `Spring` are documented animation members | `spring()` returns a source that moves towards its input |
| **Screen, billboard, world surface** | Three shipped render targets: `ScreenGui`, `BillboardGui`, and a flat two-dimensional `SurfaceGui` ([`api.md`](../reference/api.md)) | `[INFERENCE]` Any of them: a root renders into whatever instance container you give it | `[INFERENCE]` Any of them: you name the class you want | `[INFERENCE]` Any of them: you name the class you want |
| **Adoption and interoperability** | `UI.Foreign` reserves a box for a Roblox `GuiObject` Facet does not wrap; four install routes with no external toolchain ([`08-without-rojo.md`](08-without-rojo.md)) | Creator Store and Wally packages; `createPortal` renders into a container outside the parent tree; a migration guide from Roact 1.x exists | `Hydrate` binds extra behavior to an instance you already have | The documentation calls the library "instance independent" |
| **Performance model** | Changes coalesce into one refresh per frame; paint-only changes skip layout ([`02-architecture.md`](02-architecture.md) §2.2) | `[INFERENCE]` Cost follows re-render and reconciliation. Bindings are the documented route that avoids the re-render | `[INFERENCE]` Cost follows the dependency graph: what a changed `Value` feeds is what recomputes | `[INFERENCE]` Cost follows the effects that read a changed source. The documentation says `indexes` and `values` differ in "less property updates and less re-renders" |
| **Evidence you can check** | Headless performance scenes with budgets, five named evidence classes, and empty device slots ([the guide index](README.md), [`12-performance-lab.md`](12-performance-lab.md)) | A benchmarks section exists in the documentation | `[INFERENCE]` None found in the pinned documentation | `[INFERENCE]` None found in the pinned documentation |

## 14.3 Use this when

### React Luau

Reach for it when you want the React model itself: components that own state,
hooks, and a reconciler that works out the instance changes for you `[INFERENCE]`.
A migration guide from Roact 1.x is documented `[FACT]`, so it is also the
route forward for an older codebase. How much learning material you can find for
a model is worth checking for yourself before you pick one; this page does not
measure it `[INFERENCE]`.

Do not read "components re-render" as "there is no fine-grained route". Bindings
are that route: the README calls them "a form of signals-based state that
doesn't re-render, for highly-efficient animations driven by React" `[FACT]`, and
the deviations page describes them as "a unidirectional data binding that can be
updated outside of the render cycle" `[FACT]`. `createBinding` makes one and
`useBinding` is the hook form `[FACT]`. `joinBindings` "combines a map or array
of bindings into a single binding" `[FACT]`, and a bound host property follows
the binding without the component running again `[FACT]`. Where this page quotes
a project calling something efficient — here, and in the table above — that is
the project's own description of itself and not a measurement, so read it beside
[§14.5](#145-performance). Reach for a binding for a health bar, a countdown, or
a value that moves every frame `[INFERENCE]`.

### Fusion

Reach for it when you want reactive state and instance creation in one small
vocabulary, and you want cleanup to be structural rather than remembered
`[INFERENCE]`. A scope is an array that objects add their own destructor to;
`doCleanup()` destroys the contents in reverse order; `innerScope` gives a
nested lifetime that cannot outlive its parent `[FACT]`. `Value` is "a state
object that you can set manually", `Computed` "determines its own value
automatically", and `Observer` runs code when a watched object changes `[FACT]`.

`New` takes a class name and returns a component that builds instances of it;
string keys are assigned as properties, and a property given a state object "is
re-assigned every time the value of the state object changes" `[FACT]`. `Hydrate`
takes an instance you already have and returns a component that applies a
property table to it, "binding extra functionality to that instance" `[FACT]`.
That makes it a way into interface somebody else built `[INFERENCE]`.
`ForKeys`, `ForPairs` and `ForValues` handle collections, and `Tween` and
`Spring` handle animation `[FACT]`.

### Vide

Reach for it when you want the smallest reactive vocabulary that still covers a
real screen, and you like the idea that a property, not a component, is the unit
of update `[INFERENCE]`. A `source` is a getter and a setter in one function;
`effect` re-runs when anything it read changes; `derive` caches a computed value;
`root` runs a function in a stable scope and returns a destructor `[FACT]`.

`create` is the whole authoring story: a string key whose value is a function
becomes either an event connection or "an effect to update property" `[FACT]`.
Control flow is four helpers — `show`, `switch`, `indexes` and `values` — and the
documentation is direct that choosing between the last two is a performance
decision, because it "can result in less property updates and less re-renders"
`[FACT]`. `spring()` returns a source "always moving torwards the input source
value" `[FACT]`. A strict mode runs reactive scopes twice to catch impure
computations during development, and is off under the optimisation level Roblox
uses for production `[FACT]`.

Its own documentation names the cost honestly: "Vide's reactivity operates with
the concept of scopes which carries a learning curve" `[FACT]`.

### Facet

Reach for it when the interface is a large part of the product, and you want the
parts a test can check to be checkable without an engine `[INFERENCE]`. Layout,
focus, adaptation and state are plain Luau; only the adapter edge touches an
`Instance` `[FACT]` ([`02-architecture.md`](02-architecture.md)). It ships the
things you would otherwise write: nineteen composite controls, native
`StyleSheet` paint with Studio Style Editor token editing, input across pointer,
touch, keyboard and gamepad, layout that adapts from a phone to a console, and
three render targets `[FACT]` ([the guide index](README.md) catalog). One of
those controls is worth a line on its own: a virtual list mounts only the rows
in view plus a bounded overscan margin, scrolling inside that window writes
rectangles only, and sliding the window adds and removes just the rows that
entered and left `[FACT]` ([`api.md`](../reference/api.md)).

The cost is the same fact from the other side. It is the largest of the four, it
decides more on your behalf, and its way of doing things is the way you will do
things `[INFERENCE]`. Two limits are worth reading before you commit. Its input
layer requires `Workspace.PlayerScriptsUseInputActionSystem` to be enabled in
every place, and that property cannot be read or set from code `[FACT]`
([`07-input.md`](07-input.md)). And its own guide index states that the
checked-in device measurement slots are still empty, so it asks you not to
describe it as proven on low-end phones, consoles or headsets `[FACT]`
([the guide index](README.md)).

The world-surface target is worth stating precisely, because it is easy to
over-read: it is flat, two-dimensional Facet on a `SurfaceGui`, on a part a
player can walk up to and use `[FACT]`. It is not virtual reality, ray, hand or
gaze support `[FACT]` ([`api.md`](../reference/api.md),
[`../extending/new-platform-mode.md`](../extending/new-platform-mode.md)).

## 14.4 How each one updates the screen

**React Luau.** The default path is render and reconcile. Something changes
state, and your component function runs again and returns a fresh element tree.
The README says the library "will efficiently update and render just the right
components when your data changes" `[FACT]`; working out which instance writes
that means is the reconciliation step `[INFERENCE]`. `ReactRoblox.createRoot` is
what holds that tree against a Roblox instance container `[FACT]`. The second
path is narrower and deliberate: a binding is updated outside the render cycle
and re-assigns the host property it is bound to, with no component re-run
`[FACT]`. Both paths are the library's, and
a real screen usually uses both `[INFERENCE]`.

**Fusion.** There is no component re-run at all. You build the instance once, and
each property you bound to a state object is re-assigned when that object's value
changes `[FACT]`. `Computed` objects sit between your `Value` objects and the
properties, so a change travels the dependency graph and stops where nothing
depends on it `[INFERENCE]`. The scope is the other half: everything the build
created is registered for destruction, and `doCleanup()` runs those destructors
in reverse `[FACT]`.

**Vide.** Also no component re-run. `create` walks the property table once, and
every non-event property whose value is a function becomes its own effect
`[FACT]`. Updating a source re-runs exactly the effects that read it, and each
one writes its single property `[FACT]`. Control flow is where structure changes:
`show` and `switch` swap a subtree, and `indexes` and `values` build one child
per entry, differing in whether an element is bound to a position or to an object
`[FACT]`.

**Facet has its own fine-grained reactive core; it does not use Fusion, React, or
Vide.** That core is `src/core/custom.luau`, and `src/init.luau` binds
`Facet.newCore` to it `[FACT]`. It gives you signals, memos, observers and effects,
plus transactions that batch several writes so dependents recompute and observers
fire once, and scopes that own everything and dispose it exactly once `[FACT]`
([`01-concepts.md`](01-concepts.md) §1.3). Structure changes only through
`UI.When` and `UI.ForEach`, which mount and unmount branches and rows, each with
its own scope `[FACT]` ([`api.md`](../reference/api.md)). Geometry is a separate
pure step: a two-pass solver reads a snapshot of the tree and a viewport size and
returns a rectangle per node, reading no signal and no `Instance` `[FACT]`. Only
then does the adapter edge write engine properties, and a change reaching a
signal does not repaint immediately — it records a dirty entry that one refresh
per frame drains, so many changes in a frame collapse into one layout pass and a
minimal set of writes `[FACT]` ([`02-architecture.md`](02-architecture.md) §2.2).
Paint, by default, is not written by the adapter at all: the adapter classifies
each instance with tags, and a generated Roblox `StyleSheet` owns the paint
`[FACT]` ([`05-styling.md`](05-styling.md) §5.7).

## 14.5 Performance

Each model has a different shape of cost, and the shape is the useful thing to
know `[INFERENCE]`:

- Render and reconcile pays per component re-run and per tree comparison, and
  gives you an escape hatch for the hot property `[INFERENCE]`.
- A dependency graph pays per changed value times what depends on it, and pays
  nothing for the parts of the screen that did not change `[INFERENCE]`.
- A per-property effect pays the same way, at the smallest unit the engine will
  accept `[INFERENCE]`.
- A frame-coalesced solver pays for one layout pass per frame in which geometry
  changed, and for nothing when only paint changed `[INFERENCE]`.

**This page makes no relative speed claim, in either direction.** No matched,
fair, checked-in benchmark of these four libraries exists in this repository
`[FACT]`. A comparison that would earn a claim needs equivalent, idiomatic
workloads for all four, written by someone fluent in each, run on the same host
with the same settings, with raw results and stated limits. Nothing on this page
is that, and a number produced any other way measures the author, not the
library `[INFERENCE]`.

Measure your own workload instead. Six workloads are enough to tell these models
apart, because each stresses a different part of the shape above `[INFERENCE]`:

1. Mount: build the screen from nothing and record the time.
2. Fine update: change one value that one visible property depends on.
3. Bulk update: change many values at once, in one frame.
4. Large-list scroll: fling a long collection and record frame times.
5. Idle: leave the screen open and untouched.
6. Teardown: close the screen and check that memory returns.

Then hold the conditions still:

1. Use the same host machine, the same settings and the same place.
2. Run each workload several times and report a percentile, not one run.
3. Use the engine's own profiler, so the number attributes to something.
4. Test on the weakest device you intend to support.

That last step is the one people skip. Facet's own performance chapter is blunt
about it: a Studio device emulator can close layout and operability rows, and it
can never close a claim about that device's speed — only the shipped client on
named hardware does `[FACT]` ([`12-performance-lab.md`](12-performance-lab.md)).

## 14.6 Sources

Fetched 2026-08-30. Each project is pinned to the version, tag or commit that was
current on that date.

| Project | Pinned to | Source |
|---|---|---|
| Facet | commit `bb9944bddef80c32913fcfdca7d1699e021fd988` (the repository state this chapter was written against), `Facet.VERSION` `0.10.0` | this repository: [the root `README.md`](../../README.md), [`01-concepts.md`](01-concepts.md), [`02-architecture.md`](02-architecture.md), [`05-styling.md`](05-styling.md), [`07-input.md`](07-input.md), [`12-performance-lab.md`](12-performance-lab.md), [`api.md`](../reference/api.md), `src/core/custom.luau`, `src/init.luau`, `src/client/native_style.luau`, `src/client/surface_target.luau` |
| React Luau | newest tag `v17.1.3` (commit `7455fb005c68ec63326fcfb6b311da99800980b6`); newest published release `v17.0.1`; branch `main` at `9351444c2db37caa08b38ad5de90f438db9221ea` | <https://github.com/Roblox/react-luau> · <https://roblox.github.io/roact-alignment/> · <https://roblox.github.io/roact-alignment/api-reference/react/> · <https://roblox.github.io/roact-alignment/api-reference/react-roblox/> · <https://roblox.github.io/roact-alignment/deviations/> |
| Fusion | release `v0.3-beta` ("Fusion 0.3"); branch `main` at `2790f7b6272bdf7cd0bbfee259a2f9d79ea20810` | <https://github.com/dphfox/Fusion> · <https://elttob.uk/Fusion/0.3/> · <https://elttob.uk/Fusion/0.3/tutorials/fundamentals/scopes/> · <https://elttob.uk/Fusion/0.3/api-reference/> · <https://elttob.uk/Fusion/0.3/api-reference/roblox/members/new/> · <https://elttob.uk/Fusion/0.3/api-reference/roblox/members/hydrate/> |
| Vide | release `0.4.1` (commit `5ed4c01940e6bd578fb83253cfbeda0a6c05177c`); branch `main` at `f3bfc65607834370ce84a6e16722282c4d30316c` | <https://github.com/centau/vide> · <https://centau.github.io/vide/> · <https://centau.github.io/vide/tut/crash-course/1-introduction> · <https://centau.github.io/vide/api/reactivity-core.html> · <https://centau.github.io/vide/api/reactivity-dynamic.html> · <https://centau.github.io/vide/api/creation.html> · <https://centau.github.io/vide/api/animation.html> · <https://centau.github.io/vide/api/strict-mode.html> |
| Roblox styling | the live page as read on 2026-08-30; Roblox publishes it unversioned, so it can change under this citation with no version to compare against | <https://create.roblox.com/docs/ui/styling> |

Two notes on the pins. React Luau's newest tag is ahead of its newest published
release, so both are recorded `[FACT]`. Vide publishes releases without a
leading `v`, so `0.4.1` is the tag as it appears `[FACT]`.

If you are reading this long after the fetch date, re-check each source before
you rely on a row. Any of them may have changed since the fetch date, and a
page like this one goes stale quietly `[INFERENCE]`.
