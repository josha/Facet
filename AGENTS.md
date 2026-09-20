# AGENTS.md — building with Facet

Facet is a Roblox user-interface library written in Luau. You hand it a plain-data
description of a screen; it decides which Roblox objects to create, when to change
them, and when to destroy them.

This page is a routing table, not a manual. Every claim about Facet's behavior
lives in one of the documents below, and this file points at it. When the two
disagree, the linked document wins. Nothing here needs private context, a
conversation history, or any repository other than this one.

## 1. Where the answers are

| You need | Read |
|---|---|
| the current authoring model, state, ownership, collections and animation | [`docs/guide/15-components.md`](docs/guide/15-components.md) |
| the smallest working screen, headless and in Studio | [`docs/guide/03-getting-started.md`](docs/guide/03-getting-started.md) |
| every public capability, one line each | the capability catalog in [`docs/guide/README.md`](docs/guide/README.md) |
| a property, default, callback, or return value | [`docs/reference/api.md`](docs/reference/api.md) |
| choosing a radial menu, linear menu, toolbar, or navigation flow | [`docs/guide/14-choosing-controls.md`](docs/guide/14-choosing-controls.md) |
| worked examples, smallest first | [`docs/guide/04-tutorial-examples.md`](docs/guide/04-tutorial-examples.md) and `examples/` |
| a runnable standalone project | [`examples/consumer/`](examples/consumer/) |
| the module map and why each boundary exists | [`docs/guide/02-architecture.md`](docs/guide/02-architecture.md) |
| colors, spacing, shadows, and the style path | [`docs/guide/05-styling.md`](docs/guide/05-styling.md) |
| server-owned state and validated changes | [`docs/guide/06-client-server.md`](docs/guide/06-client-server.md) |
| input, focus, navigation, and the hard limits | [`docs/guide/07-input.md`](docs/guide/07-input.md) |
| installing with no Rojo, and the Roblox Package | [`docs/guide/08-without-rojo.md`](docs/guide/08-without-rojo.md) |
| building a theme package | [`docs/guide/09-custom-themes.md`](docs/guide/09-custom-themes.md) |
| art-driven controls | [`docs/guide/10-rich-skinning.md`](docs/guide/10-rich-skinning.md) |
| what the evidence covers, and what it does not | [`docs/guide/11-device-verification.md`](docs/guide/11-device-verification.md) |
| performance work | [`docs/guide/12-performance-lab.md`](docs/guide/12-performance-lab.md) |
| choosing virtualized versus fully mounted collections | [Collection size and lifetime](docs/guide/14-choosing-controls.md#collection-size-and-lifetime) |
| the ready-made looks | [`docs/guide/13-theme-catalog.md`](docs/guide/13-theme-catalog.md) |
| where a change goes and what proves it | [`docs/MAINTAINERS.md`](docs/MAINTAINERS.md) |
| how to add a control, primitive, theme, target, or mode | [`docs/extending/`](docs/extending/) |
| the rules anything added here follows | [`docs/reference/constitution.md`](docs/reference/constitution.md) |
| what changed in each version | [`CHANGELOG.md`](CHANGELOG.md) |
| the contributor workflow | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| the maintainer's package interface | [`package/README.md`](package/README.md) |

## 2. How to build a screen

Before selecting controls for a new screen, apply
[`Choosing controls`](docs/guide/14-choosing-controls.md). Use its task and input
criteria to decide whether contextual radial actions are appropriate, then choose
the documented geometry, content-fit, navigation, and completion options. For
brief confirmations, declare `UI.Alert` with an `isPresented` cell and an
`actions` list; the control owns responsive sizing, actions, focus and
cancellation. Use
`app.presentModal` directly for substantial custom modal tasks. For
proximity actions around world objects, use the public `client.world_anchor`
binding and the chooser’s world-object guidance. Prefer a direct prompt for one
primary action and a corner menu for global commands; do not duplicate projection
in game UI.

For peer destinations organizing a screen, including a demo browser's top-level
categories, use the chooser's [two-level navigation recipe](docs/guide/14-choosing-controls.md#two-level-navigation):
adaptable outer TabView, ordinary nested page tabs. Choose by navigation role;
calling a screen a game or demo does not make its outer navigation a local tab strip.

Follow this order for every UI requirement, including whole-screen layouts and responsive composition:

First inspect the host screen as well as the control catalog. Reuse its existing
toolbar, settings, and navigation composition: a new action usually needs a
`UI.Button` in that surface, not another piece of chrome. Before adding a
control, wrapper, or alternative presentation, identify the concrete requirement
the closest existing control and host composition cannot express. Follow the
[composition guidance](docs/guide/14-choosing-controls.md#compose-in-the-existing-screen).

1. Attempt the needed UI with Facet's existing public controls and layouts: stacks, grids, Composition,
   scrolling, layout modifiers and adaptive conditions.
2. Use Facet's supported customization: game themes/StyleSheets, tokens, skins,
   image backgrounds, control presentations, layout constraints/spacing/alignment,
   adaptive composition, and public content/contribution seams.
3. If a reusable behavior is missing, attempt to extend Facet through the relevant
   playbook, including its tests and guidance. Fix a framework gap in Facet.
4. Only when all three approaches fail may you build custom UI. Record the
   concrete limitation and attempted approaches, keep the fallback as small as
   possible, and preserve Facet's input, focus, lifecycle and theme integration
   through supported seams. Convenience or unfamiliarity is not a failure.

The ordinary implementation rules below apply unless that documented last-resort
fallback is necessary. Do not start with native Roblox controls or a separate
custom input/layout system and then attempt to wrap Facet around it.

1. **Compose from the public surface.** Create an application with `Facet.new()`
   and use `app.controls`. A component is an ordinary function returning a view;
   `app.mount(Component)` gives it Compose ownership. Use numeric children and
   optional constructor names. See [component authoring](docs/guide/15-components.md).
2. **Keep local state in the component.** Use `Facet.Compose.cell` and property
   functions that read through `use`. Event callbacks command the model with
   `:set` or `:update`; `:peek()` reads without subscribing. Use `Compose.formula`
   for shared calculations, `Compose.watch` for external effects, and
   `Compose.cleanup` for external resources. Create shared model cells outside
   the component when their values must survive its removal.
3. **Customize the theme first.** A game may use an out-of-the-box theme as-is.
   When its look and feel needs customization, first derive or customize a
   game-owned theme package before adding screen-specific styling or changing
   controls. Install it with `app.installTheme(package)`. Include real
   image/vector icons rather than text substitutes.
   See [Custom themes](docs/guide/09-custom-themes.md) for backgrounds, icon
   coverage, contrast and border insets. Use semantic roles, spacing
   steps, and type roles. Paint reaches the engine through Roblox's own
   `StyleSheet` mechanism, and a theme package can replace the whole look without
   touching a screen. See [`docs/guide/05-styling.md`](docs/guide/05-styling.md)
   and [api.md `themes`](docs/reference/api.md#themes).
4. **Let Facet adapt.** Size class, orientation, column counts, safe areas,
   interaction class, and the player's preferred text size are facts published by
   `app.environment` and read by the controls themselves. Do not branch
   on a device name. [api.md `adaptive`](docs/reference/api.md#adaptive) is the
   policy surface.
5. **Let Facet own the mechanisms.** Focus and navigation come from the solved
   layout ([`newFocusGraph`](docs/reference/api.md#newfocusgraph)), input from the
   semantic action system
   ([`newActionSystem`](docs/reference/api.md#newactionsystem)), motion from the
   Compose animation runtime, scrolling from a real Roblox scrolling container,
   and lifetime from Compose owners.
6. **Stand the surface up once.** `Facet.new()` creates the environment, render
   target, input system, presenter and Compose runtime. It drives the frame.
   Use `app.mount` to present a component and `app.dispose` when the application
   ends. See the [application API](docs/reference/api.md#new).
7. **Choose collection lifetime deliberately.** Apply the chooser's
   [virtualization guidance](docs/guide/14-choosing-controls.md#collection-size-and-lifetime)
   to inventories, catalogs and feeds. Use the existing virtual controls for
   large scrolling collections; document a reason when keeping them fully
   mounted. Keep durable row state in the model and let the control own
   windowing, scrolling and focus.

**Examples are part of the API.** Maintained examples, guide snippets and new
feature scenarios must teach the same current authoring vocabulary. Prefer dense
numeric children, `Compose.show`, stable collection keys (`key = "id"`),
current-item readables and row components. Keep durable row
state in the model. Never introduce a second state or ownership facade.

Use the application's Compose runtime for animation. Bind its animated readables
in view properties. Declare a region's enter and exit motion as `transition` on
`UI.When` or `UI.ForEach`, and name a shared element with `transition.source`.
Controls can expose motion options for their own behavior. Native StyleRule paint
transitions and reduced-motion handling come from the host. See the current
[motion recipe](docs/guide/15-components.md).

A low-level constructor in an example needs a concrete reason: implementing a
control, testing primitive contracts, inspecting an imperative handle, or owning
state outside a mounted view. Name that reason beside the code and link the
ordinary component recipe. Do not copy low-level verification fixtures into new
application UI. Keep historical change descriptions in the changelog. When a
feature changes, update its example and teaching
snippet in the same change and exercise the mounted example.

## 3. Choosing where the interface lives

Facet materializes a solved screen through one render target. Three exist:

- **A screen.** `client.screen_target` — a `ScreenGui` on the player's display.
  This is the default and the one every guide chapter assumes.
- **A billboard.** `client.billboard_target` — the same flat screen following an
  object in the world.
- **A world-fixed surface.** `client.surface_target` — the same flat,
  two-dimensional screen on a `SurfaceGui` attached to a part, which a player
  walks up to and uses. The worked recipe is the outpost terminal in
  `examples/gallery/examples/outpost_terminal/`.

**Say what this is and nothing more.** A world-fixed surface is a flat
two-dimensional screen placed in the world. Facet has no declarative
three-dimensional layout, no virtual-reality mode, and no ray, hand, or gaze input
path. Do not describe one, and do not build a screen that assumes one.

## 4. What belongs to the game and what belongs to Facet

Keep the game's **domain state and content** in the game: balances, inventories,
match results, copy, and the rules that decide any of them. The server owns that
truth and validates every change; the client only shows it.

Put a **reusable mechanism** in Facet: a layout rule, a control, a focus or input
behavior, a theme capability, a render target. The test is whether a second,
unrelated game would want the same thing. If it would, it is framework work and
belongs behind a public Facet surface with a spec and a documentation entry.

A game-local workaround for something the framework promises is a defect report in
disguise. Fix it in Facet.

## 5. The workflow

```sh
rokit install                        # the pinned toolchain
tools/verify.sh affected             # while you work
tools/verify.sh fast                 # the inner-loop tier
tools/verify.sh full                 # before you propose the change
lune run tests/run_one <spec-name>   # one spec, and how you watch a check fail first
stylua --check src tests tools bench examples
```

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) for what each tier means and which one a
reviewer expects. Four rules matter to an agent:

- **Choose the tier by what the change can be seen to do**, not by how many lines
  it is. Affected and fast are working tiers; full is the tier a proposal is
  judged on; release belongs to the maintainer.
- **Understand the run's own report.** `--explain` prints which producers were
  selected and why, and why a reused result was allowed to stand. Read that
  before rerunning everything.
- **Rerun the smallest trustworthy thing.** `--rerun <id>` ignores the stored
  result for one producer and runs only that. Use it while you fix, then rerun
  the tier once the fix is in.
- **Documentation and Studio evidence are part of the change.** A new public
  property belongs in `docs/reference/api.md`; a new capability belongs in the
  guide index catalog; a change a player can look at or press owes the live Roblox
  check named in the relevant playbook.

**Package and release.** A change to runtime source, required assets, versioning,
or the model builder should rebuild and check the distributable package locally:
`tools/package.sh build` and `tools/package.sh status`, documented in
[`package/README.md`](package/README.md). Both are offline. Publishing to the cloud happens only in an
approved release, run by the maintainer with credentials that are not in this
repository. Never publish from a pull request.

**Downstream lockstep.** Facet has one production consumer game that moves with
it. Keeping that game current is the maintainer's job. Propose the framework
change on its own merits.

## 6. Forbidden shortcuts

Outside the documented last-resort fallback in §2, each of these is a defect:

- **Requiring a Facet internal.** The public surface is the `Facet` table plus the
  blessed client modules listed in [api.md client entry
  points](docs/reference/api.md#client-entry-points). Requiring anything else
  under the Facet tree fails the boundary check.
- **Creating Roblox interface objects yourself.** No `Instance.new("Frame")`, no
  hand-set `Position`, no writing an engine property Facet already owns. If Facet
  cannot express the thing, add the capability through
  [`docs/extending/`](docs/extending/); do not reach around it.
- **A screen-local input, focus, or layout system.** One action system, one focus
  graph, one solver. A second one on top of a screen is how a control becomes
  unreachable on some device nobody tested.
- **Branching on a device name.** Read the published facts — size class, display
  class, interaction classes, safe areas, preferred text size — and let the same
  description adapt. A device-name branch is wrong the day the next device ships.
- **Working around a framework promise inside a game.** If adaptation, focus,
  input, motion, or teardown does not do what the documentation says, that is the
  bug to fix.
- **Reporting a fast or affected run as full evidence.** The tiers mean different
  things and the tool says which one ran.

## 7. Two standing facts

- **Compose owns the reactive graph, scheduler and ownership.** Facet sits directly on it:
  `Compose.cell`, `Compose.formula`, `Compose.watch` and Compose owners, with no Facet signal,
  memo or scope type. `src/core/services.luau` adds only the error boundary and the layout
  settle pass (`src/render/settle_pass.luau`). The commit and file hashes are recorded in `src/vendor/compose/UPSTREAM.lock`;
  `src/vendor/compose` is a generated, read-only snapshot of that commit with its MIT notice;
  `tools/sync_compose.py --check` fails when any file differs from the lock. Do not edit the snapshot.
  There is no local patch, and no other vendor is allowed. See `src/core/README.md` for the native scheduling contract.
- **`Facet.VERSION` is the version, and it lives in one place**, `src/init.luau`.
  See the [versioning policy](CONTRIBUTING.md#6-versioning-and-deprecation).
