# LuauUI Guide

LuauUI is a Roblox user-interface library written entirely in Luau. It has two
properties that shape everything else in this guide:

1. **Its decisions are headlessly testable; its live mechanisms are Roblox-native.**
   Reactive data, layout math, navigation, and other deterministic policy do not
   need a Roblox `Instance`. The adapter edge creates real Roblox UI and should use
   Roblox's scrolling, styling, input, path, and other native mechanisms where they
   fit. The separation exists for deterministic tests and clear ownership, not to
   make LuauUI a portable framework for other engines. The decision layer runs
   headlessly under [Lune](https://lune-lang.com/), a standalone Luau runtime.

2. **You describe the interface; you do not build it.** You hand LuauUI a
   plain-data description of the screen you want. LuauUI figures out which real
   objects to create, when to change them, and when to throw them away. You never
   write `Instance.new("Frame")` or set a `Position` by hand.

This guide is written for a Roblox developer who has never seen this codebase.
Read it in order.

## The principles, in plain words

Everything in LuauUI follows a small set of ideas. If a rule ever seems strange,
one of these is usually the reason. (The full rulebook, with every pattern and
every approved exception, is [`the constitution`](../reference/constitution.md).)

**How it's designed:**

- **You say what, it does how.** You describe the screen. The library builds it,
  updates it, and cleans it up. You never touch an `Instance` yourself.
- **The brain works without Roblox.** Every decision (layout math, focus,
  state, adaptation) runs in plain Luau, so tests can check it exactly. Only the
  thin adapter edge touches the real engine — and there it uses Roblox's own
  native mechanisms (real scrolling, real stylesheets) instead of faking them.
- **The server owns the truth.** Your game's real state lives on the server.
  The client only shows it, and every change request is validated.

**How the system stays sane:**

- **Every engine property has exactly one owner.** Layout owns geometry, style
  owns paint, bindings own data, presentation owns motion. Two writers on one
  property is a bug the framework refuses to allow.
- **Everything cleaned up, exactly once.** Every subscription and resource
  belongs to a scope. Close the screen, the scope dies, everything under it is
  freed. No leaks, no double-frees.
- **Change means re-solve, never rebuild.** Rotating the phone, swapping a
  theme, or growing the text re-computes positions. It never throws your screen
  away — so focus, scrolling, and typing survive.
- **One broken piece can't take down the screen.** Your callbacks are allowed
  to fail; the framework contains the error, records it, and keeps running.

**How the API behaves:**

- **Mistakes fail loudly, right away, with the fix in the message.** A typo'd
  property is an error that says what you meant — never a thing that silently
  does nothing. Silent is the one thing the API is never allowed to be.
- **Your data stays yours.** A control never keeps the important state (the
  chosen value, the sort order). You own the signal; the control reads it and
  writes it. Throw the control away and your data is still there.
- **Learn one, know them all.** Controls are built one way
  (`build(LuauUI, core, spec)` → `{ blueprint, dump, dispose }`), callbacks are
  named one way (`onChange` while it moves, `onCommit` when it lands), teardown
  works one way. Where something deliberately breaks the pattern, the
  constitution names it and says why.
- **Promises are kept on a schedule.** The version number means something
  (ADR-0011): nothing public disappears without a ledger entry, a replacement,
  and at least one minor version of notice.

## Reading order

| File | What it covers |
|---|---|
| [`01-concepts.md`](01-concepts.md) | The ideas you need before any code makes sense: declarative UI, the two kinds of state, why everything visual runs on each player's own machine, the server's role, design tokens, the input system, focus — and adapting a whole screen by declaring ranked content instead of writing a per-device layout ladder. |
| [`02-architecture.md`](02-architecture.md) | The module map, how data flows from a replicated value all the way to a pixel on screen, the extension points, and *why* each internal boundary exists. |
| [`03-getting-started.md`](03-getting-started.md) | The smallest possible working screen, wired two ways: as a headless test and inside Roblox Studio. |
| [`04-tutorial-examples.md`](04-tutorial-examples.md) | A guided tour of eight learning stages across seven example files, each adding a new idea. |
| [`05-styling.md`](05-styling.md) | Colors, spacing, the built-in look, drop shadows, rounded corners, why styling is data, the native StyleSheet paint path, and what a theme package adds on top. |
| [`06-client-server.md`](06-client-server.md) | Talking to the server: receiving replicated state, sending validated changes, showing a change instantly and reconciling when the answer comes back. |
| [`07-input.md`](07-input.md) | The input story. Starts with the one thing you must do by hand — tick `Workspace.PlayerScriptsUseInputActionSystem` (LuauUI requires IAS) — then the concepts: semantic actions, control-declared input contributions, layout-derived navigation, per-class idioms, modal dismissal on every input, hints; the responder chain for UI in avatar games (passive/engaged/exclusive); troubleshooting (dead gamepad A, `gamepad_contention` probe) and the hard limits. |
| [`08-without-rojo.md`](08-without-rojo.md) | Using LuauUI with no external toolchain: the instance-tree rule that makes require-by-string work, four ways to get the library into a place (the prebuilt `build/LuauUI.rbxm`, an example place, a published model or Package, by hand), the client script typed straight into Studio, and what a no-Rojo workflow does and does not cost you. |
| [`09-custom-themes.md`](09-custom-themes.md) | Building a theme package: deriving from Studio Neutral, editing paint/font/metric tokens in the Style Editor, nine-slice panel and Button chrome, insets and fallbacks, previewing every control across device profiles, validating/exporting with `theme_sync_cli`, installing at an application root, swapping live, upgrades, and profiling ornate cost — worked end to end as Fantasy Parchment. |
| [`10-rich-skinning.md`](10-rich-skinning.md) | When the art IS the interface: layered decoration slots, per-state art instead of tints, image bars and toggles and stepper plates, semantic icons with safe fallback glyphs, pixel-art mode, `selectBy` for a phone skin that becomes a desktop skin on dock — and the three-rung customization ladder walked end to end, finishing with a custom control that ships its own art. |
| [`11-device-verification.md`](11-device-verification.md) | Instruments, and reading numbers honestly: the five evidence classes and why a headless number never becomes a phone result; the two budgets (measured trend, one-directional frame ceiling) and how to break the perf gate on purpose; the five-view Studio device matrix, its role-based selection policy, and the catalog traps it exists for; why touch and gamepad need their own Play session; calibrating injected input per row; and the exact list of rows no emulator can ever close. |

## The public surface at a glance

Everything you use lives on the single table returned by `require`-ing the
library (`src/init.luau`). This is an **abridged** tour of it — the pieces you
reach for first. [`../reference/api.md`](../reference/api.md) is the complete
list, mechanically checked against the exports in both directions:

```lua
local LuauUI = require(ReplicatedStorage.LuauUI)

LuauUI.VERSION            -- "0.8.0"
LuauUI.newCore()          -- create a reactive runtime
LuauUI.UI                 -- the screen-description constructors (UI.Screen, UI.Text, ...)
LuauUI.mount(...)         -- turn a description into a live node graph
LuauUI.newEnvironment(..) -- per-device facts (screen size, input type, ...)
LuauUI.newActionSystem(.) -- the input pipeline
LuauUI.newPresenter(...)  -- owns screens and modals on screen
LuauUI.newFocusGraph(...) -- keyboard/gamepad focus and navigation
LuauUI.newTable(...)      -- a data-table control
LuauUI.newVirtualList(..) -- a large scrolling list that only builds visible rows
LuauUI.newPopupButton(..) -- a button that opens a popup of selectable options
LuauUI.newTextInput(...)  -- a single-line text-entry control
LuauUI.newChip(...)       -- a selectable filter/action pill
LuauUI.inputHint(...)     -- a reactive “Tap / Enter / A” affordance label
LuauUI.newResourceProvider(.) -- async loading (images, remote data)
LuauUI.adaptive           -- size/height/orientation facts as pure functions + Readables
LuauUI.composition        -- the pure declared-content arrangement decision (UI.Composition)
LuauUI.replication        -- adapters for server-owned state
LuauUI.tokens             -- the design-token compiler
LuauUI.themes             -- theme packages + the effective metric snapshot
LuauUI.renderer           -- the low-level render driver (rarely called directly)
LuauUI.DEPRECATIONS       -- the retiring-surface ledger: what is on its way out,
                          --   what replaces it, and the earliest version it may go
```

Not shown above: the rest of the composite controls (slider, stepper, rating,
picker, disclosure group, progress view, label, async image), the pure decision
modules (`motion`, `text`, `spatial`, `valueModel`, `interactionTokens`,
`touchGestures`, `contribution`, `pathShapes`) and the drag primitives. Read
`LuauUI.DEPRECATIONS` rather than assuming it is empty — it is generated plus
declared, so it grows as surfaces retire, and every entry names its replacement.

The Roblox-specific pieces (the code that actually makes `Instance`s, reads the
real input device, and reads the real screen size) are **deliberately not on
this table**. A client script requires them directly from `src/client/*` — the
theme controller (`client.theme_controller`) is one of them. This is what keeps
the main library safe to `require` from server or shared code — see
[`02-architecture.md`](02-architecture.md).

## Agent-friendly extension and current evidence limits

LuauUI is designed so an agent or a new maintainer can change it without relying on
unstated repository history. There are **six** extension playbooks, one per kind of
change, each with scaffolds, deliberately failing tests, registration checks,
deterministic state dumps, four-input proofs, lifecycle checks and documentation
gates:

- [`new-control`](../extending/new-control.md) — a new composite control.
- [`skinned-control`](../extending/skinned-control.md) — making an existing control
  take image-driven paint from a theme package.
- [`new-theme`](../extending/new-theme.md) — a new theme package.
- [`new-engine-feature`](../extending/new-engine-feature.md) — adopting a new Roblox
  instance class or property without letting engine specifics leak past the adapter.
- [`new-render-target`](../extending/new-render-target.md) — a new place the solved
  tree materializes (a new RenderTargetAdapter).
- [`new-platform-mode`](../extending/new-platform-mode.md) — extending the same model
  toward future spatial UI without adding device-specific screen branches or claiming
  untested support.

Two current facts are important when judging generated work:

- Since the strict-authoring milestone (0.5.0), every public constructor rejects
  unknown properties, wrong types, and unrecognised enum values at build time with
  a "did you mean" diagnostic — a misspelled property is an error, never silently
  ignored. [`../reference/api.md`](../reference/api.md) remains the property
  reference.
- The repository has named headless performance scenes with percentile and regression
  budgets, but their fake render target is trend screening only. The checked-in device
  measurement slots are still empty. Do not describe LuauUI as low-end-phone,
  console, or VR performance-proven until the real-device gates in the roadmap pass.

The same honesty applies to input: registered controls have strong headless and Studio
evidence across pointer, touch, keyboard, gamepad, and hybrid changes, while the
standing physical-device confirmation gate is still open.

Agents implementing roadmap or extension work must follow the
[`LuauUI execution contract`](../plans/agent-execution-contract.md). It defines which
claims require headless, live Studio, physical-device, or human evidence and prevents
“the suite is green” from standing in for a running Roblox UI check.

## Verifying the library works

The full test suite is pure Luau and runs headless:

```sh
./run-tests.sh      # runs `lune run tests/run`
```
