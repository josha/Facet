# 2. Architecture

This chapter maps the modules and traces one value from the network to the
screen. It lists the places you are meant to extend, and explains *why* each
internal boundary exists. Understand the boundaries and the rest of the code
reads itself.

## 2.1 Module map

All source lives under `src/`. Grouped by responsibility:

| Area | Files | Responsibility |
|---|---|---|
| **application** | `client/application.luau`, `client/host.luau` | `Facet.new` connects the Compose runtime to Facet's environment, presenter, input system and render target. Mounted components own their resources through Compose. |
| **UI domain** | `render/compose_controls.luau`, `render/compose_scene.luau` | Controls construct native Compose domain nodes. The host validates properties, propagates inherited style and records changes for the renderer. Compose owns bindings, node lifetime and structural operations. |
| **schema** | `blueprint_schema.luau`, `blueprint.luau`, `class_contract.luau` | Property types, normalization, dirty classifications and primitive input contracts. Control builders and the native host share these rules. |
| **core services** | `core/services.luau`, `core/on_change.luau`, `render/settle_pass.luau` | The per-application service bag: the scene runtime, the root owner, the reactor, the error boundary and the layout settle pass. `render/settle_pass.luau` runs a fixed point inside the flush that opened it, calls its callbacks in registration order, and caps the run at 100 passes. The bag holds no reactive API — state, derivation, observation, lifetime and batching are all Compose's. |
| **dependency** | `vendor/compose/UPSTREAM.lock`, `tools/sync_compose.py` | The exact upstream commit and hash inventory, plus a generated read-only snapshot of that commit. The check fails when any file differs from the lock. There are no patches. |
| **layout** | `layout/solver.luau`, `layout/text_metrics.luau`, `layout/dump.luau` | Pure two-pass geometry math. Given a snapshot of the tree and a viewport size, it produces a rectangle for every node. It never reads a reactive value or an `Instance`. |
| **render** | `render/renderer.luau`, `render/layout_node.luau`, `render/hit_lift.luau`, `render/presentation_channel.luau`, `render/presentation.luau`, `render/region_transitions.luau`, `render/authority.luau`, `render/style_lint.luau`, `render/target_contract.luau` | Walks the mounted graph, runs the solver, and drives a **render-target adapter** to create/update/remove real objects. Also enforces the property-authority rule (below). Several of these are seams of the renderer, kept as separate modules so each file stays under Roblox's 200,000-char `Script.Source` write cap: `layout_node` is the **measure seam** (a mounted node becomes a `solver.Node`, plus the button-text grammar it shares with the paint seam), `presentation_channel` is the per-surface **motion write surface** (`transform`/`transparency`, the authored `opacity`/`scale`/`rotation` triple and the `withAnimation` records, composed through one write site), `presentation` is that channel's pure arithmetic, `region_transitions` is the **enter/exit coordinator** for `UI.When` and `UI.ForEach` (including `transform` from a shared-element `transition.source`), and `hit_lift` is the **overhang rule**: which branches a sub-floor control's touch floor has to be walked after for the band it advertises to be the band the engine delivers. The public contracts live on `renderer`: `renderer.attach`'s controller, `renderer.compactForm` and `drawnButtonText`. |
| **present** | `present/presenter.luau` | Owns whole screens and modals: their lifetimes, focus scopes, and input contexts. The application uses this service to present and dismiss surfaces. |
| **input** | `input/actions.luau` | The engine-free action/binding/context model. |
| **focus** | `focus/focus_graph.luau` | Logical focus identity and navigation (flat rings and navigation groups). |
| **replication** | `replication/adapters.luau` | Receiving server-owned state (snapshots, collections) and sending validated mutations. |
| **tokens** | `tokens/tokens.luau`, `tokens/default_style.luau`, `tokens/styling.luau`, `tokens/sheet_model.luau`, `tokens/chrome_slots.luau` | Design-token compilation, the built-in Facet Neutral look, shadow/corner normalization, the native StyleSheet rule model, and the decoration-slot vocabulary — including the layer ladder's pure geometry and the bar clip boxes, which are plain math a headless test can assert. |
| **themes** | `themes/package.luau`, `themes/snapshot.luau`, `themes/token_sync.luau` | Theme **packages**: the pure compiler for the versioned `ThemePackage` schema, the frozen `ThemeSnapshot` that is the single metric authority (it rides the environment as `themeMetrics`), and the typed token codec the Style Editor sync round-trips through. The compiler also owns the rich-skinning vocabulary: layer stacks, the one per-state asset-variant normalizer both customization rungs share, the value-display and toggle slots, the semantic icon map with its ASCII fallback glyphs, and pixel mode. Engine-free, so it is safe in a shared require graph; the client-side controller that materializes sheets, runs the swap transaction and resolves `selectBy` lives in **client**. See [`05-styling.md §5.8`](05-styling.md), [`09-custom-themes.md`](09-custom-themes.md) and [`10-rich-skinning.md`](10-rich-skinning.md). |
| **env** | `env/environment.luau` | Per-device facts (screen size, safe areas, input capabilities and preference, display class, accessibility preferences) as observable values, plus derived policy — notably `interactionClasses` (the live set of input idioms the device offers right now) and `distanceProfile` (`near` vs `ten-foot` for TV-class displays). |
| **async** | `async/resources.luau` | Bounded, cancellable async loading with a cache and stale-response rejection. |
| **controls** | `controls/table.luau`, `controls/virtual_list.luau`, `class_contract.luau` | UI behavior composed from primitives: values, menus, navigation and virtual collections. |
| **client** | `client/host.luau`, `client/screen_target.luau`, `client/roblox_env.luau`, `client/roblox_input.luau`, `client/roblox_resources.luau`, `client/billboard_target.luau`, `client/theme_controller.luau`, `client/edit_preview.luau`, `client/motion_driver.luau`, `client/haptics.luau`, `client/gamepad_contention.luau`, `client/responder_effects.luau` | The **only** code that touches Roblox `Instance`s, real input, and real device facts. Client-only, and these are the blessed entry points a consumer may require directly — see [`../reference/api.md` §Client entry points](../reference/api.md#client-entry-points). The list in code is `tools/lune/check_boundary.luau`'s `BLESSED_CLIENT_MODULES`, and it is the authority; no document restates its size, because a restated count is a second list to keep. |

Image framing follows the same boundary: `render/image_framing.luau` computes
source crop and destination paint rectangles without changing layout;
`client/screen_image.luau` owns the optional managed picture and its lifetime.
Both ordinary `UI.Image` and the image form of `UI.Button` use this path.

Everything except the **client** group is engine-free and runs headless.

This chapter explains the boundaries.
[`../MAINTAINERS.md`](../MAINTAINERS.md) is the operational side of the same
picture. For each area it names the seam other code may reach, the covering
specs, the Studio scenario, the gate row, and the playbook to follow when you
extend it.

## 2.2 Data flow: from a replicated value to a rendered instance

The server owns game state. After validating an incoming snapshot, the client
updates a Compose model cell. A property binding reads that cell:

```luau
local coins = Compose.cell(0)

local function Balance()
    return UI.Text {
        text = function(use) return `{use(coins)} coins` end,
    }
end

-- The game's validated snapshot handler updates the model.
coins:set(250)
```

Compose runs the affected binding and writes the text property into the Facet
domain node. The host records the property's dirty classes. Text affects both
paint and measurement, so the next renderer refresh measures the new text and
updates any changed rectangles. A paint-only property does not require a layout
solve.

The render-target adapter applies the resulting changes to Roblox objects.
Headless tests use the same path with a fake adapter that records those writes.
The application host drives refresh from its frame connection. Callers do not
need their own render loop, subscription registry or dirty queue.

### UI and embedded 3D

The UI runtime and Roblox scene runtime use the same pinned Compose module.
`client.scene` exposes Compose's Roblox runtime for game-owned 3D objects.
Facet's viewport and stage controls host embedded 3D; screen, billboard and
surface targets place the UI itself.

This division keeps scene composition in Compose and UI policy in Facet. A
spatial monitor is a two-dimensional Facet surface placed in a three-dimensional
scene. Its controls, model and theme can also serve a conventional screen.

## 2.3 Extension points

You extend Facet at four seams. Each one is a documented contract rather than a
place to edit library internals. Whatever you add through a seam follows
[`the constitution`](../reference/constitution.md), the rule set that says how a
Facet public surface is shaped. The playbooks and the registration checkers
enforce it.

### Composite controls

Controls are ordinary functions that assemble UI primitives and attach reusable
input behavior. A collection row, for example, can layer a hit target and its
content while Compose manages which rows exist. NavigationStack supplies route
identity and Back behavior; Compose `LayerStack` with top retention owns which
page is mounted. Returning to a page creates a new page owner. Durable form
state belongs in the application model.

Application components use `app.controls` and Compose. Library implementations
share the same schema, layout and input services. Follow the
[control playbook](../extending/new-control.md) when a reusable behavior is
missing; do not implement a separate input or layout system in an example.

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

The layout solver never reads a reactive value, never reads an `Instance`, and never
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

#### Feeding a solved rect back

The presenter's `onGeometry` broadcast hands a screen the rects the solve just
produced, which is how a list windows itself against the box it was actually
given. It is also the one place a screen can write a loop: a consumer that feeds
a rect into a prop that *moves that rect* never settles, and the renderer says so
— *"a solve's geometry feedback did not converge in N rounds (a consumer
publishing a layout prop derived from the rect that prop moves?)"*.

**A decoration whose presence depends on its own solved size is exactly that
shape.** A skin's `contentInsets` are spent as the node's padding, so turning a
plate on can push that node's own minimum past its fill share and hand it back a
*smaller* box than it had without the plate — which is not a rounding wobble but
a genuine two-state flip. It is measured: `examples/gallery/scenarios/
row_actions.luau`'s list card behaves that way under Fantasy Ornate (a 30px frame
a side) at eight of the swept viewport/preference cells.

The way out is not a cleverer comparison; it is to **cache the reading and key it
only on facts the decoration's own presence cannot move** — the viewport, the
player's text preference, the distance profile, and the installed theme. A new
shape takes one fresh reading and the answer settles after a single flip. All
four matter: the theme decides the carved frame, and a package swapped *in place*
(which the showcase's own theme picker does, on a persistent owner with no
remount) would otherwise be judged against a band measured under the package
before it.

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
the engine's own style rules and fires no engine change event. So if two parts of Facet
both wrote one property, the bug would be invisible. One authority
per property makes that class of bug impossible.

### Compose ownership

Compose owns every reactive subscription and resource. There is no Facet scope
type. Owners nest along the tree: `app.mount` runs a component under an owner, a
branch created by `Compose.show` owns its content, and each row of a keyed or
virtual collection owns its own. Closing a screen or dropping a row disposes that
owner. Disposal releases *everything* under it — watches, formulas, child owners,
async handles and anything registered with `Compose.cleanup` — exactly once, in
reverse order. This is why Facet does not leak watches as screens come and go,
and why a list can churn thousands of rows without accumulating dead
subscriptions.

Register an external resource with `Compose.cleanup(disconnect)` to tie it to the
current owner.

### Quarantined errors

User callbacks are hostile territory: an equality function, an observer, a list's
row factory can all throw. `core/services.luau` wraps them, so a throw keeps the
last valid value painted, reports through the services' reporter, and is
contained rather than unwinding the update loop or wedging the framework. Read
the last contained failure with `core.lastError()`. The blueprint layer adds an
**error boundary** (`UI.ErrorBoundary`). If the
function that builds a subtree throws, at first build or during a later rebuild,
the boundary swaps that subtree for a fallback view. The rest of the screen keeps
running. The presenter offers the same protection at screen
granularity via `presentCritical`. The guiding principle: one broken corner of
the interface must not black out the player's screen.

Next: [chapter 3](03-getting-started.md) builds the smallest working screen.

## Navigation lifetime

`controls/navigation_stack.luau` composes `UI.ForEach` for the current page and
`present/nav_bar.luau` for its chrome. The caller owns the path; each mounted page
runs under its own Compose owner. Input contributions reuse presenter Cancel routing and the
existing focus graph. Theme and environment changes only re-solve the current
page; they do not create another navigation or rendering system.

The renderer validates bound paint and style enum values through the internal
`render/bound_enum.luau` helper. It depends only on the blueprint schema and
holds no surface state. Binding and style writes share this check.
