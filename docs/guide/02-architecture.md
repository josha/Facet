# 2. Architecture

This chapter maps the modules and traces one value from the network to the
screen. It lists the places you are meant to extend, and explains *why* each
internal boundary exists. Understand the boundaries and the rest of the code
reads itself.

## 2.1 Module map

All source lives under `src/`. Grouped by responsibility:

| Area | Files | Responsibility |
|---|---|---|
| **core** | `core/custom.luau`, `core/contract.luau`, `core/scope_impl.luau` | The reactive runtime: signals, memos, observers, effects, transactions, and scopes. No engine, no layout — just reactive values and their dependencies. |
| **blueprint** | `blueprint.luau` | The declarative constructors (`UI.Screen`, `UI.Text`, `UI.Button`, `UI.When`, `UI.ForEach`, `UI.ErrorBoundary`, the style modifiers). Produces frozen data tables only. |
| **mount** | `mount.luau` | Turns a blueprint into a live **mounted node graph**: runs each node's setup exactly once, subscribes changing props, and records what changed in a *dirty queue*. Only structural nodes (`When`/`ForEach`) may add or remove nodes later. |
| **layout** | `layout/solver.luau`, `layout/text_metrics.luau`, `layout/dump.luau` | Pure two-pass geometry math. Given a snapshot of the tree and a viewport size, it produces a rectangle for every node. It never reads a signal or an `Instance`. |
| **render** | `render/renderer.luau`, `render/layout_node.luau`, `render/hit_lift.luau`, `render/presentation_channel.luau`, `render/presentation.luau`, `render/authority.luau`, `render/style_lint.luau`, `render/target_contract.luau` | Walks the mounted graph, runs the solver, and drives a **render-target adapter** to create/update/remove real objects. Also enforces the property-authority rule (below). Four of these are seams of the renderer, split out when `renderer.luau` reached Roblox's 200,000-char `Script.Source` write cap: `layout_node` is the **measure seam** (a mounted node becomes a `solver.Node`, plus the button-text grammar it shares with the paint seam), `presentation_channel` is the per-surface **motion write surface** (`transform`/`transparency`, the authored `opacity`/`scale`/`rotation` triple and the `withAnimation` records, composed through one write site), `presentation` is that channel's pure arithmetic, and `hit_lift` is the **overhang rule**: which branches a sub-floor control's touch floor has to be walked after for the band it advertises to be the band the engine delivers. The public contracts did not move: `renderer.attach`'s controller and `renderer.compactForm`/`drawnButtonText` are still on `renderer`. |
| **present** | `present/presenter.luau` | Owns whole screens and modals: their lifetimes, focus scopes, and input contexts. The layer you talk to most. |
| **input** | `input/actions.luau` | The engine-free action/binding/context model. |
| **focus** | `focus/focus_graph.luau` | Logical focus identity and navigation (flat rings and navigation groups). |
| **replication** | `replication/adapters.luau` | Receiving server-owned state (snapshots, collections) and sending validated mutations. |
| **tokens** | `tokens/tokens.luau`, `tokens/default_style.luau`, `tokens/styling.luau`, `tokens/sheet_model.luau`, `tokens/chrome_slots.luau` | Design-token compilation, the built-in Studio Neutral look, shadow/corner normalization, the native StyleSheet rule model, and the decoration-slot vocabulary — including the layer ladder's pure geometry and the bar clip boxes, which are plain math a headless test can assert. |
| **themes** | `themes/package.luau`, `themes/snapshot.luau`, `themes/token_sync.luau` | Theme **packages**: the pure compiler for the versioned `ThemePackage` schema, the frozen `ThemeSnapshot` that is the single metric authority (it rides the environment as `themeMetrics`), and the typed token codec the Style Editor sync round-trips through. The compiler also owns the rich-skinning vocabulary: layer stacks, the one per-state asset-variant normalizer both customization rungs share, the value-display and toggle slots, the semantic icon map with its ASCII fallback glyphs, and pixel mode. Engine-free, so it is safe in a shared require graph; the client-side controller that materializes sheets, runs the swap transaction and resolves `selectBy` lives in **client**. See [`05-styling.md §5.8`](05-styling.md), [`09-custom-themes.md`](09-custom-themes.md) and [`10-rich-skinning.md`](10-rich-skinning.md). |
| **env** | `env/environment.luau` | Per-device facts (screen size, safe areas, input capabilities and preference, display class, accessibility preferences) as observable values, plus derived policy — notably `interactionClasses` (the live set of input idioms the device offers right now) and `distanceProfile` (`near` vs `ten-foot` for TV-class displays). |
| **async** | `async/resources.luau` | Bounded, cancellable async loading with a cache and stale-response rejection. |
| **controls** | `controls/table.luau`, `controls/virtual_list.luau`, `class_contract.luau` | Composite controls built *out of* the primitive blueprints. |
| **client** | `client/host.luau`, `client/screen_target.luau`, `client/roblox_env.luau`, `client/roblox_input.luau`, `client/roblox_resources.luau`, `client/billboard_target.luau`, `client/theme_controller.luau`, `client/edit_preview.luau`, `client/motion_driver.luau`, `client/haptics.luau`, `client/gamepad_contention.luau`, `client/responder_effects.luau` | The **only** code that touches Roblox `Instance`s, real input, and real device facts. Client-only, and these are the blessed entry points a consumer may require directly — see [`../reference/api.md` §Client entry points](../reference/api.md#client-entry-points). The list in code is `tools/lune/check_boundary.luau`'s `BLESSED_CLIENT_MODULES`, and it is the authority; no document restates its size, because a restated count is a second list to keep. |

Everything except the **client** group is engine-free and runs headless.

This chapter explains the boundaries.
[`../MAINTAINERS.md`](../MAINTAINERS.md) is the operational side of the same
picture. For each area it names the seam other code may reach, the covering
specs, the Studio scenario, the gate row, and the playbook to follow when you
extend it.

## 2.2 Data flow: from a replicated value to a rendered instance

Here is the full path a single value travels. Suppose the server sends the client
a new "coins = 250" fact.

```
   SERVER (owns the truth)
        │  sends semantic state over the game's own network transport
        ▼
┌───────────────────────────────────────────────────────────────┐
│ CLIENT (everything below runs on the player's machine)          │
│                                                                 │
│  replication adapter        core signal          memo/derived   │
│  (snapshot.ingest)   ───►   coins:set(250)  ───► "250 coins"    │
│                                                     │           │
│                                                     ▼           │
│                                            mounted node graph   │
│                                            (mount.luau):        │
│                                            the Text node's      │
│                                            `text` prop is       │
│                                            subscribed to that   │
│                                            memo, so the change  │
│                                            enqueues a "paint"   │
│                                            entry in the DIRTY   │
│                                            QUEUE                 │
│                                                     │           │
│              presenter.refresh() (once per frame)   ▼           │
│                                            renderer.refresh():  │
│                                            drains the dirty     │
│                                            queue                │
│                                              │                  │
│                    paint-only? ──────────────┤                 │
│                    write the changed prop     │                 │
│                                               │ measure/arrange/│
│                                               │ structure?      │
│                                               ▼                 │
│                                     layout solver runs on a     │
│                                     snapshot → rectangles       │
│                                               │                 │
│                                               ▼                 │
│                              RENDER-TARGET ADAPTER              │
│                       ScreenTarget (real Instances) OR          │
│                       FakeTarget (records calls, for tests)     │
│                                               │                 │
│                                               ▼                 │
│                                    pixels on the player's       │
│                                    screen                       │
└───────────────────────────────────────────────────────────────┘
```

The key beat to notice: **a change reaching a signal does not immediately repaint
the screen.** It updates the reactive graph and records a *dirty* entry. The
renderer only acts when `presenter.refresh()` is called, which a client does once
per frame. This coalescing is deliberate — many changes in one frame collapse
into one layout pass and a minimal set of writes.

The renderer is also **minimal-write**. A paint-only change — new text, a new
colour — writes just that property and does not re-run layout. Only
size-affecting or structural changes trigger a fresh solve, and even then the
renderer writes back only the rectangles that changed.

## 2.3 Extension points

You extend Facet at four seams. Each one is a documented contract rather than a
place to edit library internals. Whatever you add through a seam follows
[`the constitution`](../reference/constitution.md), the rule set that says how a
Facet public surface is shaped. The playbooks and the registration checkers
enforce it.

### Composite controls

`controls/table.luau` and `controls/virtual_list.luau` are not special engine
code — they are ordinary functions that *assemble the primitive blueprints* into
something bigger. A table row, for instance, is a `ZStack` layering a full-row
`Button` under an `HStack` of cells. You build your own composite controls the
same way: a function that returns a blueprint (and, if it holds reactive state,
owns a scope for it). Nothing about a composite control reaches past the public
blueprint constructors.

### Render-target adapter

The renderer talks to the screen only through a small adapter interface (create a
root, create a node, set its rectangle, set a property, remove it, destroy the
root). `client/screen_target.luau` implements it with real Roblox `Instance`s;
`tests/lib/fake_target.luau` implements it by recording calls into a table. Any
target that satisfies the same interface drops straight in.
`client/billboard_target.luau` is exactly that: it renders a Facet screen onto an
in-world billboard by swapping only the *root*, and reuses all the flat node
rendering below it.

### Engine-feature adoption via the property-authority path

Roblox ships new visual capabilities from time to time; drop shadows and
per-corner rounding are two. Facet adopts each one as **normalized style data**.
That data rides a single declared *authority* to the adapter, which materializes
it — and only if the running engine supports it. You do not scatter
`Instance.new("UIShadow")` calls through your UI; you set a style modifier, and
the one adapter that owns visual output decides how (or whether) to realize it.
The next section explains the authority rule.

### Platform adapters

The three environment-facing seams — reading device facts
(`client/roblox_env.luau`), reading real input (`client/roblox_input.luau`), and
rendering (`client/screen_target.luau`) — are each swappable. Tests replace all
three with fakes; a different host (Studio's edit-mode preview) replaces the ones
it needs. Your game code never depends on the real ones being present.

## 2.4 Why the boundaries exist

Four rules explain most of the structure.

### Pure layout

The layout solver never reads a signal, never reads an `Instance`, and never
yields. It is a pure function from *(tree snapshot, viewport)* to *rectangles*.
That purity is what makes layout testable to the pixel, headless, and
reproducible. It also removes a whole class of timing bug: layout runs on a
frozen snapshot, so no value can change mid-layout.

Text is where that purity has to earn its keep, because only the engine knows
how wide a string is. The solver measures text through `layout/text_metrics`, which is pure data and
never yields. It holds exact per-word widths the engine has already reported. For
a word it has not seen, it falls back to a deliberately conservative average-glyph
bound. A solve records the words it
could not size exactly; the render-target adapter measures those off the render
path and feeds them back, which costs exactly one re-solve.

Two properties make this safe rather than clever. **Words, not laid-out
strings.** Wrapping is greedy over words, so exact word widths plus an exact
space width reproduce the engine's own break points at any width. The cache is
keyed `(font, size, word)`, so it survives every resize and every device
profile.
And **the fallback is never removed** — the first frame is always painted from
the conservative bound, so exactness is layered on top of safety and never
substituted for it.

### One property authority

Every engine render property (a node's size, its background color, its text, its
corner radius) has **exactly one** owner, declared in `render/authority.luau`:

- **layout** owns geometry (position, size, z-order);
- **style** owns token-driven paint (colors, radii, shadows, strokes);
- **binding** owns data-driven values (a label's text, a toggle's value, whether
  a button is enabled);
- **presentation** owns transient transforms and opacity;
- **host** answers a different question from the other four. They say *which
  Facet writer owns this property of a Facet instance*. `host` says *what the
  framework claims over an instance it does NOT own*. It went live with
  `UI.Foreign` and owns exactly one entry — `Foreign.Parent`, the
  single write that puts a caller-created GuiObject into a Facet box. One entry
  is the point of a bounded escape hatch, and all **five** authorities are live.

The renderer calls `authority.assertWrite(class, prop, writer)` before *every*
write, and a writer touching a property it does not own is a hard error. A measured engine fact is behind this rule. Writing a property directly defeats
the engine's own style rules and fires no change signal. So if two parts of Facet
both wrote one property, the bug would be invisible. One authority
per property makes that class of bug impossible.

### Scope ownership

Every reactive subscription and resource is owned by a scope, and scopes nest
along the tree (a screen owns a mount scope; a list row owns an item scope). When
a screen closes or a row leaves a list, its scope is disposed. That cleans up
*everything* under it — observers, effects, async requests, child scopes —
exactly once, in reverse order. This is why Facet does not leak observers as
screens come and go, and why a list can churn thousands of rows without
accumulating dead subscriptions.

### Quarantined errors

User callbacks are hostile territory: an equality function, an observer, a list's
row factory can all throw. The core wraps them so a throw records an error and is
contained rather than unwinding the update loop or wedging the framework. The blueprint layer adds an **error boundary** (`UI.ErrorBoundary`). If the
function that builds a subtree throws, at first build or during a later rebuild,
the boundary swaps that subtree for a fallback view. The rest of the screen keeps
running. The presenter offers the same protection at screen
granularity via `presentCritical`. The guiding principle: one broken corner of
the interface must not black out the player's screen.

Next: [chapter 3](03-getting-started.md) builds the smallest working screen.
