# Facet Guide

Facet is a Roblox user-interface library written entirely in Luau. Two
properties shape everything else in this guide:

1. **Its decisions are headlessly testable; its live mechanisms are
   Roblox-native.** Reactive data, layout math, navigation, and other
   deterministic policy do not need a Roblox `Instance`. The adapter edge
   creates real Roblox UI. It uses Roblox's own scrolling, styling, input, and
   path mechanisms where they fit. The separation exists for deterministic tests
   and clear ownership. It does not make Facet a portable framework for other
   engines. The decision layer runs headlessly under
   [Lune](https://lune-lang.com/), a standalone Luau runtime.

2. **You describe the interface; you do not build it.** You hand Facet a
   plain-data description of the screen you want. Facet decides which real
   objects to create, when to change them, and when to destroy them. You never
   write `Instance.new("Frame")` or set a `Position` by hand.

This guide is written for a Roblox developer who has never seen this codebase.
Read it in order.

## The principles, in plain words

Everything in Facet follows a small set of ideas. If a rule ever seems strange,
one of these is usually the reason. The full rulebook, with every pattern and
every approved exception, is [`the constitution`](../reference/constitution.md).

**How it is designed:**

- **You say what, it decides how.** You describe the screen. The library builds
  it, updates it, and cleans it up. You never touch an `Instance` yourself.
- **The decision layer works without Roblox.** Layout math, focus, state, and
  adaptation all run in plain Luau, so tests can check them exactly. Only the
  thin adapter edge touches the engine, and there it uses Roblox's own
  mechanisms — real scrolling, real stylesheets — instead of imitating them.
- **The server owns the truth.** Your game's real state lives on the server. The
  client only shows it, and the server validates every change request.

**How the system stays predictable:**

- **Every engine property has exactly one owner.** Layout owns geometry, style
  owns paint, bindings own data, presentation owns motion. Two writers on one
  property is a defect the framework refuses to allow.
- **Everything is cleaned up exactly once.** Every subscription and resource
  belongs to a scope. Close the screen and the scope dies, which frees
  everything under it. No leaks, no double-frees.
- **A change re-solves; it never rebuilds.** Rotating the phone, swapping a
  theme, or growing the text recomputes positions. It never throws your screen
  away, so focus, scrolling, and typing survive.
- **One broken piece cannot take down the screen.** Your callbacks are allowed
  to fail. The framework contains the error, records it, and keeps running.

**How the API behaves:**

- **Mistakes fail immediately, with the fix in the message.** A misspelled
  property raises an error that names what you probably meant. It never
  silently does nothing.
- **Your data stays yours.** A control never keeps the important state, such as
  the chosen value or the sort order. You own the signal; the control reads it
  and writes it. Discard the control and your data is still there.
- **Learn one, know them all.** Controls are built one way
  (`build(Facet, core, spec)` returns `{ blueprint, dump, dispose }`). Callbacks
  are named one way (`onChange` while a value moves, `onCommit` when it lands).
  Teardown works one way. Where something deliberately breaks the pattern, the
  constitution names it and says why.
- **Retirement runs on a schedule.** The version number means something. Nothing public disappears without a ledger entry, a replacement,
  and at least one minor version of notice.

## Reading order

| File | What it covers |
|---|---|
| [`01-concepts.md`](01-concepts.md) | The ideas you need before any code makes sense: declarative UI, the two kinds of state, per-player rendering, the server's role, design tokens, input, focus, and ranked adaptive content. |
| [`02-architecture.md`](02-architecture.md) | The module map, how data flows from a replicated value to a pixel, the extension points, and why each internal boundary exists. |
| [`03-getting-started.md`](03-getting-started.md) | The smallest working screen, wired two ways: as a headless test, and inside Roblox Studio. |
| [`04-tutorial-examples.md`](04-tutorial-examples.md) | A guided tour of eight learning stages across seven example files. Each stage adds one idea. |
| [`05-styling.md`](05-styling.md) | Colors, spacing, the built-in look, shadows, rounded corners, why styling is data, the native StyleSheet paint path, and what a theme package adds. |
| [`06-client-server.md`](06-client-server.md) | Talking to the server: receiving replicated state, sending validated changes, and showing a change instantly while the answer travels. |
| [`07-input.md`](07-input.md) | Semantic actions, control-declared input contributions, layout-derived navigation, per-class idioms, modal dismissal, hints, the responder chain, and the hard limits. |
| [`08-without-rojo.md`](08-without-rojo.md) | Using Facet with no external toolchain: the instance-tree rule, the official Roblox Package, five ways to get the library into a place, and what a no-Rojo workflow costs. |
| [`09-custom-themes.md`](09-custom-themes.md) | Building a theme package end to end: derive, edit tokens, design chrome, preview, validate, export, install, swap live, and profile the cost. |
| [`10-rich-skinning.md`](10-rich-skinning.md) | When the art is the interface: layered decoration slots, per-state art, image bars and toggles, semantic icons, pixel-art mode, and the three-rung customization ladder. |
| [`11-device-verification.md`](11-device-verification.md) | Reading numbers honestly: the five evidence classes, the two budgets, the five-view Studio device matrix, and the rows no emulator can close. |
| [`12-performance-lab.md`](12-performance-lab.md) | The performance-lab place: its nine workloads, its nine profiler scopes, capturing on a low-end Android device, and when two captures are comparable. |
| [`13-theme-catalog.md`](13-theme-catalog.md) | The shelf of ready-made looks: what each of the eight packages does to spacing, rows, and type, the two install routes, and an honest cost line. |
| [`14-choosing-a-ui-library.md`](14-choosing-a-ui-library.md) | Optional: how Facet compares with React Luau, Fusion and Vide, and how to choose between them. |
| [`15-adaptive-recipes.md`](15-adaptive-recipes.md) | Ten short recipes for problems a screen hits once it works on more than one device. Dip into these when a screen needs them. They are recipes, not required reading. |

Two things worth knowing before you start, neither of which is a chapter:

- **A runnable starting point.** [`examples/consumer/`](../../examples/consumer/)
  is chapter 3's screen as a complete, standalone Rojo project — a project file, a
  client script, and the screen itself as one module. Build it, press Play, then
  edit it. `tests/consumer_standalone.spec.luau` mounts that same screen headlessly
  and proves it, so the example cannot rot quietly.
- **The install that needs no toolchain.** Facet is published as one Roblox
  Package, which is the recommended route if you build in Studio without a file
  sync. [Chapter 8](08-without-rojo.md) covers it: how to insert it, how to take a
  new version with *Get Latest Package*, how to check which version you have, and
  why automatic updating is worth leaving off in a production game.

## The capability catalog

This catalog lists every public capability the current library ships. It is
derived from the exported surface, the control registrations, and the shipped
examples, and a checker fails when the two drift apart
(`lune run tools/lune/check_docs_cli`).

Everything below lives on the single table returned by requiring the library:

```lua
local Facet = require(ReplicatedStorage.Facet)

Facet.VERSION -- "0.10.0"
local core = Facet.newCore()
local list = Facet.Controls.VirtualList(core, { … })
```

[`../reference/api.md`](../reference/api.md) is the exhaustive reference for
properties, defaults, callbacks, and return values. Each row below links to it.
The guide chapters explain when and why to reach for a capability.

Composite controls are all created the same way:
`Facet.Controls.<Name>(core, spec)`. The older `Facet.new<Name>(Facet, core,
spec)` forms still work and are listed in `Facet.DEPRECATIONS` with their
replacement and their earliest removal version.

### 1. Layout and composition primitives

| Capability | What it does | Reference |
|---|---|---|
| `UI.Screen` | The root of one surface. Everything else is a descendant. | [api](../reference/api.md#screen) |
| `UI.VStack` / `UI.HStack` | Lays children out in one column or one row. | [api](../reference/api.md#vstack--hstack) |
| `UI.ZStack` | Stacks children on top of each other in one box. | [api](../reference/api.md#zstack) |
| `UI.Grid` / `UI.GridRow` | Column-aligned rows whose widths agree across the grid. | [api](../reference/api.md#grid) |
| `UI.Box` | A painted rectangle. The plain building block. | [api](../reference/api.md#box--spacer) |
| `UI.Spacer` | Absorbs leftover space inside a stack. | [api](../reference/api.md#box--spacer) |
| `UI.Divider` | A one-pixel rule between sections. | [api](../reference/api.md#divider) |
| `UI.Anchor` | Free positioning: each child names a corner and an offset. | [api](../reference/api.md#anchor) |
| `UI.AdaptiveStack` | A stack whose axis flips with the size class. | [api](../reference/api.md#adaptivestack) |
| `UI.ViewThatFits` | Shows the first candidate form that fits the space. | [api](../reference/api.md#viewthatfits) |
| `UI.Composition` | Arranges ranked content instead of a per-device layout ladder. | [api](../reference/api.md#composition) |
| `UI.Region` | One ranked thing a `Composition` must place, richest form first. | [api](../reference/api.md#region) |
| `UI.frame`, `UI.padding`, `UI.offset`, `UI.aspectRatio`, `UI.alignment`, `UI.overlay`, `UI.background` | The layout modifiers you wrap around a blueprint. | [api](../reference/api.md#layout-modifiers-frame-padding-offset-aspectratio-alignment-overlay-background) |
| `UI.containerRelativeFrame` | Sizes an element as a fraction of its container. | [api](../reference/api.md#containerrelativeframe) |
| `UI.fill`, `UI.hug` | Shorthand for the `fill`/`hug` dimension tables you'd otherwise write by hand. | [api](../reference/api.md#shared-properties) |
| `UI.Stage` | Reserves a box for content the engine draws, such as a rig preview. | [api](../reference/api.md#stage) |
| `UI.Foreign` | Reserves a box for a Roblox `GuiObject` that Facet does not wrap. | [api](../reference/api.md#foreign) |

### 2. Display, input, and value controls

| Capability | What it does | Reference |
|---|---|---|
| `UI.Text` | Draws a string, with fitting, wrapping, and reveal options. | [api](../reference/api.md#text) |
| `UI.Image` | Draws one image asset. | [api](../reference/api.md#image) |
| `UI.Button` | The pressable primitive every input class can reach. | [api](../reference/api.md#button) |
| `UI.Toggle` | A two-state switch primitive. | [api](../reference/api.md#toggle) |
| `UI.TextField` | The raw single-line text-entry primitive. | [api](../reference/api.md#textfield) |
| `UI.Path` | Draws a stroked path from points or from `pathShapes`. | [api](../reference/api.md#path) |
| `Controls.Label` | An icon-and-text pair that compacts when space runs out. | [api](../reference/api.md#newlabel) |
| `Controls.Chip` | A selectable filter or action pill. | [api](../reference/api.md#newchip) |
| `Controls.Slider` | A continuous value you drag, step, or adjust. | [api](../reference/api.md#newslider) |
| `Controls.Stepper` | A value with minus and plus buttons. | [api](../reference/api.md#newstepper) |
| `Controls.Rating` | A star-style rating input. | [api](../reference/api.md#newrating) |
| `Controls.Picker` | A segmented or inline chooser over a small option set. | [api](../reference/api.md#newpicker) |
| `Controls.PopupButton` | A button that opens a popup of selectable options. | [api](../reference/api.md#newpopupbutton) |
| `Controls.Menu` | A verb menu, with icons, anchored to what opened it. | [api](../reference/api.md#newmenu) |
| `Controls.TextInput` | A single-line text-entry control with commit and cancel. | [api](../reference/api.md#newtextinput) |
| `Controls.ProgressView` | A determinate or indeterminate bar or ring. | [api](../reference/api.md#newprogressview) |
| `Controls.DisclosureGroup` | A header that expands and collapses its content. | [api](../reference/api.md#newdisclosuregroup) |
| `Controls.LevelPicker` | A ranked level chooser with locked and cleared states. | [api](../reference/api.md#newlevelpicker) |
| `Controls.AsyncImage` | An image with placeholder, failure, and retry states. | [api](../reference/api.md#newasyncimage) |
| `Controls.Callout` | A short attention surface, queued so two never collide. | [api](../reference/api.md#newcallout) |
| `Controls.TabView` | Tabs with a placement that adapts to the device. | [api](../reference/api.md#newtabview) |
| `valueModel` | Formats, clamps, and steps a numeric value for those controls. | [api](../reference/api.md#valuemodel) |
| `pathShapes` | Builds arc, ring, and needle point lists for `UI.Path`. | [api](../reference/api.md#pathshapes) |

### 3. Collections, scrolling, selection, reorder, and drag/drop

| Capability | What it does | Reference |
|---|---|---|
| `UI.ScrollView` | A native Roblox scrolling container. | [api](../reference/api.md#scrollview) |
| `UI.ForEach` | Builds one child per item, keyed so identity survives a re-solve. | [api](../reference/api.md#foreach) |
| `UI.sortedEntries` | Flattens a dictionary into the deterministic array `ForEach` takes. | [api](../reference/api.md#sortedentries) |
| `Controls.VirtualList` | A long collection on either axis that builds only visible items. | [api](../reference/api.md#newvirtuallist) |
| `Controls.VirtualGrid` | The same windowing for a two-dimensional grid. | [api](../reference/api.md#newvirtualgrid) |
| `Controls.Table` | Columns, sorting, selection, header, and per-row disclosure. | [api](../reference/api.md#newtable) |
| `Controls.RowActions` | Swipe or menu verbs attached to a row, including reorder. | [api](../reference/api.md#newrowactions) |
| `newRowActionsCoordinator` | Keeps one open row at a time across a whole collection. | [api](../reference/api.md#newrowactionscoordinator) |
| `UI.draggable` / `UI.dropTarget` | Marks what can be picked up and where it can land. | [api](../reference/api.md#draggable--droptarget) |
| `UI.Grip` | A non-button pointer zone, such as a column-resize handle. | [api](../reference/api.md#grip) |
| `newDragSession` | The one live drag a surface is running. | [api](../reference/api.md#newdragsession) |
| `newDragRegistry` | The live set of drag sources and drop targets on a surface. | [api](../reference/api.md#newdragregistry) |
| `newDragVelocity` | Turns pointer samples into a flick velocity. | [api](../reference/api.md#newdragvelocity) |
| `newAutoscroll` | Answers how far to scroll when a drag reaches an edge. | [api](../reference/api.md#newautoscroll) |
| `interactionTokens` | The shared per-input-class thresholds that promote a press to a drag. | [api](../reference/api.md#interactiontokens) |
| `touchGestures` | Normalizes the engine's own touch gestures into one shape. | [api](../reference/api.md#touchgestures) |

### 4. Presentation, navigation, focus, input, adaptation, and accessibility

| Capability | What it does | Reference |
|---|---|---|
| `newPresenter` | Owns which screens and modals are on screen, and their motion. | [api](../reference/api.md#newpresenter) |
| `navBar` | The back+title+trailing chrome bar a presented surface draws at its own top. | [api](../reference/api.md#navbar) |
| `newFocusGraph` | Derives keyboard and gamepad navigation from the solved layout. | [api](../reference/api.md#newfocusgraph) |
| `newActionSystem` | The semantic input pipeline over Roblox's Input Action System. | [api](../reference/api.md#newactionsystem) |
| `contribution` | The seam a composite uses to declare its whole input story. | [api](../reference/api.md#contribution) |
| `inputHint` | A reactive affordance label that follows the active input class. | [api](../reference/api.md#inputhint) |
| `newEnvironment` | The per-device facts: viewport, safe area, input class, text size. | [api](../reference/api.md#newenvironment) |
| `adaptive` | Size class, height class, orientation, columns, and card counts. | [api](../reference/api.md#adaptive) |
| `composition` | The pure arrangement decision behind `UI.Composition`. | [api](../reference/api.md#composition-1) |
| `layout` | Pure layout geometry not owned by a control — `transformFootprint(w, h, scale, deg)`, the reserved-box math for a scaled/rotated node; `anchorPlacement(request)`, the edge/flip/shift/tail placement solver shared by every surface that points at something. | [api](../reference/api.md#shared-properties) |
| `text` | Measures strings, fits them, and reports line boxes. | [api](../reference/api.md#text-1) |
| `spatial` | The contract for spatial pointer data. A seam, with no adapter today. | [api](../reference/api.md#spatial) |

### 5. Styling, theme packages, rich skinning, animation, and feedback

| Capability | What it does | Reference |
|---|---|---|
| `tokens` | Compiles a design-token set and checks contrast pairs. | [api](../reference/api.md#tokens) |
| `themes` | Defines, resolves, and validates theme packages and their metrics. | [api](../reference/api.md#themes) |
| `motion` | Registers motion classes and curves and runs the motion clock. | [api](../reference/api.md#motion-1) |
| `UI.shadow`, `UI.gradient`, `UI.corners`, `UI.stroke` | The four paint modifiers. | [api](../reference/api.md#shadow) |
| `UI.shadowData`, `UI.gradientData`, `UI.cornersData`, `UI.strokeData` | The same four as plain data, for a theme or a control to pass around. | [api](../reference/api.md#shadowdata--gradientdata--cornersdata) |
| `UI.styleGroup` | Applies one modifier set to every element of a collection. | [api](../reference/api.md#stylegroup) |
| `UI.isReadable` | The one public predicate for "is this value already resolved". | [api](../reference/api.md#tooling-surface-uischema-uiisreadable-uiprop_dirty) |
| `UI.sensoryFeedback` | Declares a haptic and audio cue for an interaction. | [api](../reference/api.md#sensoryfeedback) |
| `renderer` | The low-level render driver, plus the property-authority tables. | [api](../reference/api.md#renderer) |

### 6. Reactive state, lifecycle, async, replication, render targets, and tools

| Capability | What it does | Reference |
|---|---|---|
| `newCore` | Creates the reactive runtime: signals, memos, effects, scopes. | [api](../reference/api.md#newcore) |
| `preload` | Force-loads the four controls Facet defers, for the loading-screen moment. | [api](../reference/api.md#preload) |
| `mount` | Turns a blueprint description into a live node graph. | [api](../reference/api.md#mount) |
| `UI.When` | Shows one branch or the other, and disposes the branch it drops. | [api](../reference/api.md#when) |
| `UI.ErrorBoundary` | Contains a failing subtree instead of losing the screen. | [api](../reference/api.md#errorboundary) |
| `newResourceProvider` | Loads images and remote data with retry and failure states. | [api](../reference/api.md#newresourceprovider) |
| `replication` | Adapters that turn server-owned state into readable values. | [api](../reference/api.md#replication-1) |
| `client.screen_target` | The render target that materializes a surface as a `ScreenGui`. | [api](../reference/api.md#clientscreen_target) |
| `client.billboard_target` | The render target that materializes a surface in the 3-D world. | [api](../reference/api.md#clientbillboard_target) |
| `client.host` | The taught client bootstrap: environment, input, theme, and mount. | [api](../reference/api.md#clienthost) |
| `client.theme_controller` | Installs a theme package at an application root and swaps it live. | [api](../reference/api.md#clienttheme_controller) |
| `UI.schema` | The machine-readable blueprint schema, for tools and generators. | [api](../reference/api.md#tooling-surface-uischema-uiisreadable-uiprop_dirty) |
| `UI.PROP_DIRTY` | The frozen map from property to the work a change to it dirties. | [api](../reference/api.md#tooling-surface-uischema-uiisreadable-uiprop_dirty) |
| `specGuard` | The closed-key-set guard, exported so an out-of-repo control can reuse it. | [api](../reference/api.md#specguard) |
| `VERSION` | The library's semantic version string. | [api](../reference/api.md#version) |
| `EXIT_CAP_SECONDS` | The flat, non-overridable cap on how long a dismissed surface's exit may defer teardown. | [api](../reference/api.md#exit_cap_seconds) |
| `DEPRECATIONS` | The retiring-surface ledger: what is going, what replaces it, and when. | [api](../reference/api.md#deprecations) |

The Roblox-specific modules that create `Instance`s, read the real input device,
and read the real viewport are deliberately **not** on the `Facet` table. A
client script requires them from `src/client/*`. That is what keeps the main
library safe to require from server or shared code. See
[`02-architecture.md`](02-architecture.md).

## Extension playbooks

Facet is designed so a new maintainer can extend it without relying on unstated
repository history. There are seven playbooks, one per kind of change. Each ships
scaffolds, deliberately failing tests, registration checks, deterministic state
dumps, four-input proofs, lifecycle checks, and documentation gates.

- [`new-control`](../extending/new-control.md) — a new composite control.
- [`new-primitive`](../extending/new-primitive.md) — a new leaf element class.
- [`skinned-control`](../extending/skinned-control.md) — letting an existing
  control take image-driven paint from a theme package.
- [`new-theme`](../extending/new-theme.md) — a new theme package.
- [`new-engine-feature`](../extending/new-engine-feature.md) — adopting a Roblox
  class or property without letting engine specifics leak past the adapter.
- [`new-render-target`](../extending/new-render-target.md) — a new place the
  solved tree materializes.
- [`new-platform-mode`](../extending/new-platform-mode.md) — extending the same
  model toward spatial UI, without device-specific screen branches and without
  claiming untested support.

## What the evidence does and does not cover

Two facts matter when you judge this library or work generated against it.

- Since version 0.5.0 every public constructor rejects unknown properties, wrong
  types, and unrecognised enum values when you build the blueprint. The error
  names the property you probably meant.
  [`../reference/api.md`](../reference/api.md) stays the property reference.
- The repository has named headless performance scenes with percentile and
  regression budgets. Their fake render target screens for trends only, and the
  checked-in device measurement slots are still empty. Do not describe Facet as
  proven on low-end phones, consoles, or headsets until the real-device gates
  pass.

The same honesty applies to input. Registered controls have strong headless and
Studio evidence across pointer, touch, keyboard, gamepad, and hybrid changes.
The standing physical-device confirmation gate is still open.

The rule behind both paragraphs is that a claim names the instrument that
produced it. A headless number is not a device number, and "the suite is green"
is not a substitute for watching a screen run in Roblox.

**A small fix does not owe a large change's evidence.** Here is the whole bar for
one. **The covering spec first**, written to fail, and seen to fail for the reason
you expect — `lune run tests/run_one` is that loop. **Then a full verification
run**, green, with a case total no smaller than before: `tools/verify.sh full`.
**Then `stylua --check src tests tools bench examples`.** **Then the checks that
name your area**: `tools/doctor.sh`, plus the `tools/check_*` script that owns
the file you touched, plus `python3 tools/check_source_size.py` for any source
edit. That is four things, and it is enough.
[`../../CONTRIBUTING.md`](../../CONTRIBUTING.md) says which verification tier to
run when.

What is owed BEYOND that is decided by what your change can be SEEN to do, never
by how many lines it is. A change a player can look at or press owes the live
Roblox check in the relevant playbook's §6, however small it is. A change to
arithmetic that no pixel depends on owes none of it, however large.

## Verifying the library works

Verification runs in four named tiers through one command:

- **affected** — the smallest safe set for the files you changed;
- **fast** — the inner-loop tier;
- **full** — every deterministic check, exactly once; and
- **release** — full, plus the build, package and evidence producers a release
  needs.

```sh
tools/verify.sh affected               # while you work
tools/verify.sh fast                   # the inner loop
tools/verify.sh full                   # before you propose a change
tools/verify.sh release                # the maintainer's release run
```

Underneath them, the suite runs the way it always has, and one spec file is the
loop to work in:

```sh
./run-tests.sh                        # THE SUITE — every spec file.
./run-tests.sh --fast                 # inner loop: the same list minus the eleven
                                      # measured-slowest files.
lune run tests/run_one <spec-name>    # ONE spec file, for the edit-and-run loop.
```

**Only the argument-free run counts as green.** The fast tier
(`tests/run_fast.luau`, exclusions in `tests/lib/tiers.luau`) prints a
`FACET-FAST-TIER` banner at both ends, and `tools/test.sh` fails on that
transcript rather than recording it as a suite result. Nothing is skipped or
deleted: every excluded file runs in full on `./run-tests.sh`.

**`run_one` is the loop to work in.** It takes a spec name without its suffix,
so `lune run tests/run_one table` runs `tests/table.spec.luau` and nothing else.
It is also how you watch a new check FAIL before you trust it. This repository
asks for that every time, because a check never seen to fail is decoration.
Proving it through the whole suite is expensive enough that it gets skipped.
Like the fast tier, it cannot produce a suite verdict — nothing reads its output
but you.

Sizes, measured on one developer machine: the suite takes about three and a half
minutes, the fast tier about forty seconds, and a single spec file a few seconds.
Read the ratios rather than the seconds. The absolute numbers move with the
machine and with every change that adds cases, and the command below re-measures
them where you are.

To re-measure which files are the expensive ones:

```sh
lune run tools/lune/time_specs artifacts/spec-timings.json > /dev/null
```

It times every spec file, load plus cases, and the thirty slowest individual
cases.
