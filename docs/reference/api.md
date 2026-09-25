# Facet API reference

Every public surface of the library, mechanically checked against the source
by `lune run tools/lune/check_registration_cli` (an export without a heading
here — or a heading without an export — fails the check). Format per entry:
signature, parameters, return value, invariants, and a short example.

The library is required as one module (`require(path.to.Facet)`); everything
below hangs off that table unless noted. Client-only entry points live under
`src/client/` and are required directly by client scripts, never from shared
or server code — the blessed list is [Client entry points](#client-entry-points).

**The patterns behind these entries** — how a constructor is shaped, who owns
what, which deviations are approved and why — are the
[constitution](constitution.md). Two conventions worth knowing before you read
anything below, because they decide how a call is written:

- **Colon vs dot** (constitution §16, E-7). Reactive-graph objects and pure
  stepped models take `self`: `clock:step()`, `value:set()`,
  `model:step()`, `session:drop()`. Services, controllers and namespaces do not:
  `presenter.present()`, `controller.refresh()`, `registry.pointerDown()`,
  `adaptive.sizeClass()`. Each entry below is written in the form it takes.
- **Who disposes it** (constitution §8). In order of preference: pass
  `opts.scope` for helpers that accept it (`inputHint`); Compose formulas use the
  active owner (`adaptive.conditions`); else register the teardown yourself with
  `Compose.cleanup(function() handle:dispose() end)` (`motion.newClock`); else the
  return IS an unsubscribe you own (`presenter.onTick`, `app.onFrame`). Where an
  entry says nothing, there is nothing to own.

---

## Library metadata

### `VERSION`

`Facet.VERSION: string` — the semantic version (`MAJOR.MINOR.PATCH`),
currently `0.11.0`. Governed by the versioning and deprecation policy in
[`CONTRIBUTING.md` §6](../../CONTRIBUTING.md#6-versioning-and-deprecation):
pre-1.0, a minor bump may change behavior with notice; a patch bump never does. The version lives only here; docs and tests read it from the source.

### `EXIT_CAP_SECONDS`

`Facet.EXIT_CAP_SECONDS: number` — `0.5`. The flat, non-overridable cap (ui-
designer spec §2.1 / disposition F8) on how long a dismissed surface's exit
transition may defer its teardown, in **clock time** (a stopped clock stops the
cap too). `src/render/transitions.luau` is the authority and enforces it; this
is that same number, published (framework-gaps-phase2 item 41) for a consumer
that must advance a stepped clock past a dismissed surface's own teardown — a
presenter's final `tick(Facet.EXIT_CAP_SECONDS)` on the way out, the way
RascalRally's `FacetSponsor/init.luau:destroy()` does — instead of copying the
literal out of this paragraph by hand.

### `DEPRECATIONS`

`Facet.DEPRECATIONS: { { surface, since, removeNoEarlierThan, replacement, note? } }`
— the machine-readable deprecation ledger, and it is **frozen**: authority, not
a scratch table. It is the UNION of two halves in one record shape, so every
consumer reads one list — the entries generated from the property schema
(`src/blueprint_schema.luau`), then the declared entries for surfaces that are
not blueprint properties (an opts field, a derived condition). A deprecated
surface keeps working for at least one minor version after `since`, and every
entry names its `replacement`.

The ledger lists properties and options that have not yet been removed. It does
not retain deleted constructor aliases.

One important exception to "keeps working": a property that **never** reached a
render target was never working surface to preserve. Keeping it silently
accepted would preserve the silent failure, not the compatibility. Those
properties stay in the ledger for the record but are **diagnosed at
construction** — you get an error naming the replacement instead of a screen
that quietly omits behavior. `UI.Text.color` and `UI.Text.font` are the current
entries.

---

## Reactive core

### `new`

`Facet.new(opts?) -> app` creates a client application using Facet's host services
and Compose's UI runtime. Options are the same host options described under
[client entry points](#client-entry-points). Client modules load when `new` is
called, so requiring Facet in shared code does not initialize a client host.

| Application member | Contract |
|---|---|
| `app.installTheme(package, options?)` | Installs the existing theme controller for this application and releases it on disposal. Returns that controller for `swap` and `swapPackage`. Options are the theme-controller options except `env` and `core`, which the application supplies. Install once per application. |
| `app.controls` | Facet constructors for this Compose runtime. Use a property table with ordered numeric children. Constructors accept an optional name: `UI.Button("Save") { ... }`; anonymous controls need no ID. |
| `app.presentModal(component, opts?)` | Mounts a component in its own Compose lifetime and presents it as a modal. Returns `close, node, handle`. Uses the presenter's modal options, focus trap and cancellation policy. Dismissal releases the component; application disposal closes all remaining surfaces. |
| `app.presentAnchored(component, opts)` | Builds a panel under Compose ownership and places it beside a source path or rect. Returns `close, node` for the generated surface. The builder receives `app.controls`, the same vocabulary `app.mount` components close over; most builders ignore the argument and close over `UI` instead. Uses the [anchored options](#anchored-surfaces) for placement, tails, modality and noninteractive chrome. Moving sources reposition the panel; dismissal releases its content. |
| `app.mount(component, options?)` | Runs an ordinary component function under Compose ownership and presents its one root. Accepts the standard presentation options, including `rootPolicy = "edgeToEdge"` for a full-window background. Returns `close, node, handle`. Invalid roots and presentation failures release the mounted resources before propagating the error. |
| `app.dispose()` | Immediately removes all surfaces, pending exits, toasts and auxiliary layers before releasing their state, the runtime, frame connection, input, adapter and environment. Queued components are discarded without mounting. Every release step runs even if a cleanup throws; the first error is then raised. Repeated disposal is harmless. |
| `app.runtime` | The actual Compose runtime for this domain; its constructors, bindings, structural operations and animation APIs follow Compose's contract. |
| `app.environment` | The host environment. Read facts such as `use(app.environment:get("viewportRect"))` in a property binding. |
| `app.onFrame(callback)` | Subscribes to the host frame driver and returns a disconnect function. Own it with `Compose.cleanup(app.onFrame(callback))` inside a component. |

The third return from `app.mount` and `app.presentModal` is the presentation
handle. Its `controller`, responder and focus operations last for that surface;
use `close()` or `app.dispose()` to end its lifetime. `app.presentAnchored` returns
only `close, node`.

Calling `close()` is idempotent. It removes that surface and releases its component
resources; it does not dispose the whole application. Model cells created outside
the component can outlive a presentation. See the [standalone consumer](../../examples/consumer/README.md)
for a mounted screen using local cells, adaptive facts and frame cleanup.

`UI.DisclosureGroup` takes a label, an `expanded` boolean Compose cell, and a
`content` component function. It mounts content only while expanded. The header
toggles the cell; optional `onToggle(expanded)` receives the new value. Collapsing
returns focus to the header before removing focused content. Its caret uses
Compose motion and respects reduced motion.

Native `TabView` takes the same transition declaration `UI.When` takes, and
plays exactly one form: a 160 ms page crossfade, spelled
`transition = { enter = "fade" }` (or the older `{ fade = true }`, which means
the same thing here). Its pages occupy the **same box**, so there is nothing for
a slide to slide against and no origin for a transform — any other form is
**refused at construction**, with the reason and the line that works, rather
than accepted and dropped. `{ enter = "instant" }` is the explicit hard cut, and
omitting `transition` is the same thing said by saying nothing.
Compose retains the departing page until its fade completes and
reclaims it if selection returns during the fade. Departing content does not
accept input. Reduced motion switches pages immediately. Picker and TabView
selection indicators use Compose springs. Changing selection retargets the
spring without a jump; layout changes place the indicator at its measured
bounds. Reduced motion places it immediately.

#### Menus, navigation and presented controls

`UI.Menu { label = "Actions", items = ... }` builds a standard trigger. Use
`trigger` for custom trigger content; provide either `label` or `trigger`.
`UI.SplitButton` combines a primary action with the same menu mechanism.
`UI.ComboBox` accepts separate writable Compose cells for `value` and `text`.
`acceptCustom(text)` validates an edited value before it becomes the selection.

`UI.PageView` uses a writable `selection` cell shared by its page buttons and
scrolling. `UI.NavigationStack` uses a writable route `path` cell. Destination
`content(owner, entry)` functions run under a Compose owner. Use `Compose.cell`,
`Compose.formula` and `Compose.cleanup` inside those functions.

`UI.Alert` and `UI.Sheet` accept an `isPresented` boolean cell. They present through
the application's surface services and clear the cell on dismissal. Supply a
`content` function to construct fresh content each time the surface opens. Sheet
also requires a writable `detent` cell. Its native height motion uses Compose
springs; dragging follows the pointer directly, and reduced motion settles at once.

`UI.Callout` decorates an `anchor` node. Its `content` function runs when the shared
callout queue presents it. Optional `isPresented` controls whether it requests a
place in the queue. `seen` and `featureUsed` prevent a retired tip from returning;
`onRetire(reason)` lets the application persist that decision. Omitting
`isPresented` requests an eligible native callout after its anchor is mounted.

`UI.AsyncImage { provider = provider, key = contentId }` needs no explicit scope.
Its mounted Compose owner holds the resource lease and reactive bindings. Removing
the image releases the lease and makes an unfinished request's completion stale.

#### Modifiers in `app.controls`

The native vocabulary includes `frame`, `padding`, `offset`, `aspectRatio`,
`alignment`, `corners`, `shadow`, `gradient` and `stroke`. These functions keep
Facet's property validation and update the existing Compose node. They return
that same node, so its children, event connections and other bindings remain intact.
Apply modifiers during component construction.

`background(base, decoration)` and `overlay(base, content, alignment?)` create a
stack around the original nodes. Apply them before attaching either node. The
stack follows the base width and height, including bound changes. Setting a
dimension on the stack overrides that axis. A background with no explicit size
fills the stack. Children keep their Compose identity and ownership.

`frame` accepts pixel dimensions and min/max constraints. Use
`{ maxWidth = "infinity" }` to fill the available width. `alignment` accepts
`"start"`, `"center"` or `"end"`. Other arguments follow the corresponding
[layout](#layout-modifiers-frame-padding-offset-aspectratio-alignment-overlay-background) and styling modifier contracts.

```luau
UI.corners(
    UI.padding(
        UI.frame(UI.VStack { UI.Text { text = "Account" } }, { maxWidth = "infinity" }),
        "m"
    ),
    "control"
)
```

For property tables, `UI.fill()` and `UI.hug(bounds?)` return dimensions.
`cornersData`, `shadowData`, `gradientData` and `strokeData` return normalized
styling data. These helpers create no nodes or subscriptions.

#### Virtual collections in `app.controls`

`UI.VirtualList { ... }` and `UI.VirtualGrid { ... }` use Compose's
`OrderedCollection`. Compose owns item identity, row lifetime, windowing and
placement. Facet connects the collection to its scroll container and focus graph.

| Property | Contract |
|---|---|
| `rows` (list) / `items` (grid) | A Compose readable or source function returning an array. Each control accepts only its own spelling. |
| `key` | A field name, or a function returning a unique, stable item key. |
| `cell(item, ctx)` | A component function. `item` is the record as it stands. `ctx.current` is a `function(use)` that follows later edits to that item; wrap it in `Compose.formula` when the cell must track them. `ctx.scope` is the row's own Compose owner. The grid also passes `index`, `line` and `lane`. |
| `ref(record)` | Optional. Called once while the control is built, with the frozen `{ api, dump }` record. `api` carries the collection's verbs. |
| `itemExtent` | A positive pixel extent, a readable, or a source function. Use `"measured"` to size rows from their rendered content. |
| `estimatedItemExtent` | Required when `itemExtent = "measured"`, and refused otherwise: the pixel seed an unmeasured row windows at. |
| `viewportExtent` | Pixel extent along the scroll axis, including a reactive source. Use `"auto"` to fill the available extent. |
| `axis` | `"y"` (default) or `"x"`. Construction-only. |
| `overscan` | Nonnegative integer: extra rows retained around the visible window. |
| `onActivate(item, meta)` | Optional row action. Omit it and the collection adds no row button and no row focus stop; controls inside the row keep their own input. |
| `follow` | `"none"` (default) or `"end"`, as a value, a readable, or a `function(use)`. Following continues while the reader stays near the end, and **yields the moment a reported offset moves away from it** — including from inside `followThreshold` — so content growth cannot snap a panning player back. It resumes on a return to the end, or when `follow` is re-asserted. |
| `followThreshold` | Pixel distance from the end that still counts as near it. |
| `scrollNavigation` | `{ position, active? }`: scroll state shared across presentations. See [scroll navigation](#scrollview). |
| `snap` | `"none"` (default) or `"item"`: where the collection may come to rest on its scroll axis. |
| `width` | Cross-axis dimension for a vertical collection. A horizontal collection fills its available height. |
| `columns`, `gap` | Grid only. `columns` is a positive integer, a readable or a source function; `gap` separates columns. |
| `rowGap` | Space between lines, on both controls. |

The list carries the row-level surface the grid does not: `selection`,
`selectionPaint`, `reorderable`, `onReorder`, `rowActions`, `focusPolicy`,
`crossExtent`, `cards` and the per-row opt-outs `rowFocusable`,
`rowSelectable`, `rowMovable`, `rowDeletable` and `rowDropTarget`. Both closed
key sets are listed in full under [`UI.VirtualList`](#uivirtuallist)
and [`UI.VirtualGrid`](#uivirtualgrid).

A measured grid gives each line its largest item's extent. A change above the
viewport preserves the visible item and its relative position. Keep durable row
state in the application model, because a row outside the window can unmount.

```luau
local inbox
UI.VirtualList("Inbox")({
    rows = messages,
    key = "id",
    itemExtent = 64,
    follow = atTail,                 -- a readable is accepted here
    cell = function(message, ctx)
        local current = Compose.formula(ctx.current)
        return UI.Text { text = function(use) return use(current).text end }
    end,
    ref = function(record) inbox = record.api end,
})
```

#### Embedded 3D in `app.controls`

`UI.Stage { width, height, content = function(stage) ... end }` creates a
ViewportFrame through Facet. Its `content` callback runs when the render target is
ready and receives the documented Stage handle: `setCamera`, `setLighting`, and
`contentRoot`. Use a Compose Roblox runtime to mount scene content into that root.
Return its cleanup function. The callback runs under a Compose owner, so watchers
and other owned resources are released when the Stage unmounts. A setup error also
releases those resources. Resizing does not rerun the callback.

An adapter without Stage support does not invoke `content`. The Stage still reserves
its declared layout space.

#### Collapsible content in `app.controls`

`UI.CollapsibleView` accepts an `expanded` Compose boolean cell and a `content`
factory. The factory builds the expanded surface under its Compose owner. Closing
that surface disposes its resources. Keep persistent content state outside the
factory. Compose owns the control’s local measurements, derived layout, and
conditional image and icon content. The bound `label`, `icon` or `image` describes
the collapsed button.

```luau
UI.CollapsibleView {
    label = "Appearance",
    expanded = Compose.cell(false),
    content = function()
        return UI.Toggle { label = "Reduced motion", value = reducedMotion }
    end,
}
```

#### Tab navigation in `app.controls`

`UI.TabView` accepts a Compose selection cell and page factories. Compose's
`LayerStack` owns the selected page. Switching tabs disposes that page's local
resources; returning builds it again. Keep state that must survive a switch in
cells owned by the screen or application.

```luau
local selected = Compose.cell("games")
UI.TabView {
    selection = selected,
    tabs = {
        { id = "games", label = "Games", content = GamesPage },
        { id = "avatar", label = "Avatar", content = AvatarPage },
    },
}
```

The tab IDs are selection values. The control itself needs no ID. Each page
factory returns a native Facet node and can use `Compose.cleanup` for external
resources. Facet supplies adaptive navigation placement, input and focus.

### Types

Every constructor on `app.controls` is typed, so a wrong value in a spec is an
analyzer error on the line where you wrote it. Nothing has to run. Both
spellings are checked: `UI.Button({ … })` and `UI.Button("Name")({ … })`.

```luau
--!strict
local Facet = require(path.to.Facet)
local app = Facet.new()              -- app: Facet.App
local UI = app.controls              -- UI: Facet.Controls

UI.VStack({ gap = true })            -- error: `gap` is a number or a spacing name
UI.Slider("Volume")({ value = "5" }) -- error: `value` is a cell of number
UI.Text({ text = function(use)       -- fine: a binding that reads a cell
    return `{use(score)} points`
end })
```

| Type | What it is |
|---|---|
| `Facet.App` | What `Facet.new` returns. `controls` is typed; the rest of the handle is described in the table above. |
| `Facet.Controls` | The constructor table. Each control and each layout, text and paint primitive is a `Constructor<Spec>`; regions and modifiers are not yet typed. |
| `Facet.ButtonSpec`, `ToggleSpec`, `ComboBoxSpec`, `SplitButtonSpec`, `ChipSpec`, `AsyncImageSpec`, `VirtualListSpec<T>`, `VirtualGridSpec<T>` | Spec types for the controls that do not export one from their own module. |
| `<control>.Spec` | Every other control's spec type, declared in `src/spec_types/<control>.luau` and re-exported by the control. Reading a type loads no control. |

**A live value is a `Bound<T>`**: a plain `T`, a `Compose.cell` or
`Compose.formula` holding a `T`, or a function `(use) -> T`. A prop that takes
two kinds of value, such as `gap` (a number or a spacing name), accepts a cell of
either.

Two limits to know about. A cell is invariant in what it holds, so a field that
wants `Cell<{ Entry }>` needs the literal annotated:
`Compose.cell({ … } :: { NavigationStack.Entry })`. And a misspelled key is
caught when the control is built (with a suggestion), not by the analyzer.

### `Compose`

`Facet.Compose` is the pinned Compose core module itself. Facet does not rename its
operations or wrap its cells and components in another public authoring context.
The exact dependency revision is recorded in
[`UPSTREAM.lock`](../../src/vendor/compose/UPSTREAM.lock). The
[vendored Compose reference](../../skills/compose/references/api.md)
is authoritative for signatures, options, ownership and error contracts.

The re-exported capabilities are grouped below. They operate on Facet's runtime
where a host is needed; native Roblox constructors use the separate client scene
runtime.

| Purpose | Compose operations |
|---|---|
| Reactive values and reads | `Compose.cell`, `Compose.sharedCell`, `Compose.formula`, `Compose.accumulator`, `Compose.watch`, `Compose.sample`, `Compose.isReadable`, `Compose.reactor` |
| Ownership and external cleanup | `Compose.createOwner`, `Compose.createRootOwner`, `Compose.withOwner`, `Compose.withRootOwner`, `Compose.bindOwner`, `Compose.currentOwner`, `Compose.cleanup`, `Compose.custodyOf`, `Compose.labelOf` |
| Host construction and property classification | `Compose.createRuntime`, `Compose.event`, `Compose.group`, `Compose.property`, `Compose.static` |
| Conditional and collection lifetime | `Compose.presence`, `Compose.show`, `Compose.switch`, `Compose.keyed`, `Compose.indexes`, `Compose.OrderedCollection`, `Compose.SpatialCollection`, `Compose.LayerStack`, `Compose.MountBudget`, `Compose.fragment`, `Compose.portal` |
| Focus and resource reuse | `Compose.createFocusScope`, `Compose.createPool`, `Compose.createKeyedCache` |
| Async resources | `Compose.createSharedResource`, `Compose.boundary` |
| Animation codecs and spring state | `Compose.registerCodec`, `Compose.registeredCodecs`, `Compose.createSpringState`, `Compose.stepSpring`, `Compose.springAtRest`, `Compose.springCoefficients` |
| Diagnostics and work counters | `Compose.formatDiagnostic`, `Compose.parseDiagnostic`, `Compose.setWorkCounters`, `Compose.readWorkCounters`, `Compose.resetWorkCounters`, `Compose.setYieldChecking`, `Compose.outstandingMounts` |
| Easing curves | `Compose.easing`, `Compose.easing.inBack`, `Compose.easing.inBounce`, `Compose.easing.inCirc`, `Compose.easing.inCubic`, `Compose.easing.inElastic`, `Compose.easing.inExpo`, `Compose.easing.inOutBack`, `Compose.easing.inOutBounce`, `Compose.easing.inOutCirc`, `Compose.easing.inOutCubic`, `Compose.easing.inOutElastic`, `Compose.easing.inOutExpo`, `Compose.easing.inOutQuad`, `Compose.easing.inOutQuart`, `Compose.easing.inOutQuint`, `Compose.easing.inOutSine`, `Compose.easing.inQuad`, `Compose.easing.inQuart`, `Compose.easing.inQuint`, `Compose.easing.inSine`, `Compose.easing.linear`, `Compose.easing.outBack`, `Compose.easing.outBounce`, `Compose.easing.outCirc`, `Compose.easing.outCubic`, `Compose.easing.outElastic`, `Compose.easing.outExpo`, `Compose.easing.outQuad`, `Compose.easing.outQuart`, `Compose.easing.outQuint`, `Compose.easing.outSine` |
| Reactive profiling | `Compose.profile`, `Compose.profile.active`, `Compose.profile.data`, `Compose.profile.format`, `Compose.profile.label`, `Compose.profile.start`, `Compose.profile.stop` |
| Ownership inspection | `Compose.inspect`, `Compose.inspect.active`, `Compose.inspect.data`, `Compose.inspect.format`, `Compose.inspect.label`, `Compose.inspect.node`, `Compose.inspect.owned`, `Compose.inspect.owner`, `Compose.inspect.snapshot`, `Compose.inspect.start`, `Compose.inspect.stop` |

## Blueprints

### `schema`

`Facet.schema` is the frozen property-schema facade used by constructors and
modifiers. It exposes read-only class facts and pure inspection/validation
functions; see [the property schema](#the-property-schema) for each member.

### `UI.*` constructors

`app.controls` (conventionally `local UI = app.controls`) constructs nodes owned
by the current Compose lifetime. A node is a mutable runtime object, not an
immutable template to reuse across mounts. Reactive properties accept Compose
readables or `function(use) ... end` bindings. Build fresh nodes inside each
component factory. Every constructor takes a property table; the optional named
form `UI.Text("Title") { text = "Hello" }` gives a stable path for focus, tests
and diagnostics.

**Construction is strict.** Every spec is validated against the public schema
(`src/blueprint_schema.luau`) at build time, and each of these is an immediate
error naming the control, the property, and the valid alternatives:

| Mistake | What you get |
|---|---|
| unknown property | `UI.Button: unknown property 'lable'. Did you mean 'label'? Valid properties: …` |
| wrong value type | `UI.VStack.gap expects number, got string. (spacing between children along the stack axis)` |
| a bare number where a dimension belongs | `UI.Box.width expects dim, got number — a dimension table such as { type = "fixed", px = 120 }` |
| a readable on a prop read once at mount | `UI.Box.canvasGroup does not accept a Signal/Memo (it is read once at mount) …` |
| a missing required property | `UI.Text.text is required (the displayed string)` |
| children on a leaf | `UI.Text does not take children (it is a leaf). Containers: Anchor, Grid, HStack, …` |
| a property that never reached the renderer | `UI.Text.color is not supported (deprecated 0.5.0 …). Use UI.Text{ role = … }.` |

A **modifier's** refusals name the modifier you called, not the internal
property it chose: `UI.alignment(bp, "center")` on a class with no `alignH`
reports `Facet UI.alignment on UI.When: UI.When has no property 'alignH'`. A
direct constructor error is unchanged (`Facet UI.When: …`).

Each constructor also has an exported spec type (`UI.ButtonSpec`,
`UI.ScrollViewSpec`, …) built from the same schema, so an editor completes the
same field set the runtime accepts.

#### Shared box properties a CONTAINER PARENT reads

These four are declared once and carried by every rendered class, because each is
a placement fact a parent reads off its child rather than a size the child has of
its own — the same shape `anchor`, `alignH`, `alignV`, `offsetX` and `offsetY`
already have.

| Property | Type | Meaning |
|---|---|---|
| `lineAlign` | `start \| center \| end \| stretch \| firstTextBaseline \| lastTextBaseline` | this child's own cross-axis alignment inside its **stack** parent's line; it outranks both the child's own `align` and the container's `align` |
| `layoutPriority` | number (default 0) | shrink-order **tier** when a stack's main axis is short: the deficit is consumed tier by tier, LOWEST priority first, so a higher number is protected for longer |
| `shrinkWeight` | number (default 0 = never) | how readily this child gives up main-axis pixels **within** its tier. Inside a tier the deficit is split proportionally to weight × the child's natural size, down to its floor (`minMax.min`, else a text node's longest word, else 0). The default matches Roblox's `UIFlexMode.None` |
| `gridSpan` | number (default 1) | how many of its row's columns this cell covers inside a `UI.GridRow`. A spanning cell never widens a single column on its own; it is fitted to the columns it covers plus the gaps between them |

`lineAlign` exists because `align` is a CONTAINER-only prop, so before it the only
child that could align itself in its parent's line was one that was itself a
stack — and there the one word did two jobs at once. `stretch` is included so a
child that wants to fill the line's cross extent does not have to reach for a
`fill` dim, which would also claim the main axis.

**Each of the four is read by exactly one kind of parent, and using one under the
wrong parent is CAUGHT rather than ignored.** A `lineAlign`, `shrinkWeight` or
`layoutPriority` under a `ZStack`, `Anchor`, `Grid` or `ScrollView`, or a
`gridSpan` under anything but a `UI.GridRow`, is reported on
`controller.diagnostics()` naming the node, the reason and the working spelling
for that parent — a property that is accepted must do something.

**...and in Studio it also `warn`s**, once per site for the session, so the
finding reaches you without your having to call `diagnostics()` first. It is off
in a running game and costs a shipped build nothing; a host that wants it
elsewhere (a soak run, a QA build) turns it on for itself. `UI.offset(bp, x, y)`
is one of the props this catches most often, and the reason is a name collision
worth knowing about: it writes the LAYOUT pair `offsetX`/`offsetY`, which only a
`UI.Anchor` parent (and a `ScrollView`, as a scroll-time nudge) reads, while the
separate `offset` PROP is a paint-only translation that applies under any parent
at all.

#### The property schema

`local schema = Facet.schema` provides read-only inspection and validation for
extensions and contract tooling, without creating an application.

The schema is the authority every constructor and modifier rules against. Its
members are named here because an extension author reads them to make an
out-of-repo control refuse a bad property exactly the way an in-repo one does.
`Facet.specGuard` is the public helper for that: `assertKnownKeys(where, tbl,
known, kind)` and `keySet(names)`. Use `Facet.Compose.isReadable(value)` to ask
whether a value is a Compose readable instead of duck-typing `.get`.

The schema answers these questions:

| Member | Answers |
|---|---|
| `schema.forClass(name) -> ClassSpec?` | one class's declaration (`props`, `container`, `structural`) |
| `schema.all() -> { [name]: ClassSpec }` | every class, keyed by name |
| `schema.classNames() -> { string }` | the class names, sorted |
| `schema.propNames(class) -> { string }` | one class's property names, sorted |
| `schema.sharedPropNames() -> { string }` | the properties declared `shared` (the table above) |
| `schema.checkValue(propSpec, value) -> (ok, problem?)` | the single value ruling every constructor and modifier runs |
| `schema.checkOpacity(value) -> (ok, problem?)` | the 0…1 opacity ruling, shared by the authored `opacity` prop and `withAnimation` |
| `schema.checkScaleFactor(value) -> (ok, problem?)` | the finite, non-negative scale ruling |
| `schema.checkDegrees(value) -> (ok, problem?)` | the finite-rotation ruling (degrees, unbounded by design — 720° is a legal spin) |
| `schema.checkPresentationOffset(value) -> (ok, problem?)` | the authored `offset` ruling: a table `{ x = <number>, y = <number> }`, both finite (framework-gaps-phase2 gap 16) |
| `schema.refusal(class, prop, value, problem) -> string` | the ONE refusal wording every constructor, modifier and adapter raises, so a bad value reads the same wherever it is caught |
| `schema.suggest(class, badKey) -> { string }` | the did-you-mean candidates for an unknown key |
| `schema.propDirty() -> { [prop]: { [class]: { dirtyClass } } }` | which update classes a reactive prop schedules (a fresh table per call) |
| `schema.deprecations() -> { Deprecation }` | the schema-generated half of `Facet.DEPRECATIONS` (a fresh table per call) |
| `schema.TRANSITION_MIRROR` | each structural-transition form paired with its mirror |
| `schema.TRANSITION_FADES` | the forms that drive transparency (and therefore need a fade group) |
| `schema.TRANSITION_PIVOTS` | where a scaling form may grow from (`center`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight`) |
| `schema.TRANSITION_PLATES` | the values `transition.plate` takes (`fades` — this surface's plate fades with its content) |
| `schema.INHERITED_TINT_CLASSES` | the classes whose `tint` is INHERITED — declared on a container, painted by its subtree — as a frozen set derived from the class rows themselves |
| `schema.INHERITED_TINT_ALPHA_REFUSAL` | the ONE sentence both refusals of a `transparency` on an inherited `tint` raise: the construction-time one and the read-time one a reactive tint needs |

The three `check*` value rulings and `refusal` are the pieces an out-of-repo
control needs to refuse a bad prop the way the framework does — the same
functions `UI.*` constructors run, not copies of them.

**Stability.** The schema tables are **deeply frozen**. `all()` and `forClass()`
hand back the live authority, so a writable copy would be a way to disable
framework validation process-wide. Read them; to annotate one, clone it. The
shape of a `ClassSpec`/`PropSpec` is internal detail that may change in a minor;
the names above and what they answer are the contract.

Framework metadata does **not** travel in the prop bag: an input-contribution
bundle rides the blueprint's internal `meta` channel (see `contribution`), so
strict prop validation has no exemptions to work around.

#### Shared properties

These are accepted by every class the note names, so the per-class entries
below list only what is specific to that control. **"Accepted on" is exact** —
the schema is the source, and a property this table does not list for a class is
a construction error on it, not a no-op.

Three groups recur in the column below and are worth naming once:

- **every rendered class** — the twenty-two classes that produce a box:
  `AdaptiveStack`, `Anchor`, `Box`, `Button`, `Composition`, `Divider`, `Foreign`,
  `Grid`, `Grip`, `HStack`, `Image`, `Path`, `Screen`, `ScrollView`, `Spacer`,
  `Stage`, `Text`, `TextField`, `Toggle`, `VStack`, `ViewThatFits`, `ZStack`. **Two
  containers are the exceptions**, for the same kind of reason: `Region` takes
  **no** box properties at all (constitution E-5 — a Region *is* its ranked
  forms, and a width on it would be a second authority against the composition's
  own resolution), and `GridRow` takes none either, because the grid it belongs
  to owns the column widths and the row pitch (see `GridRow`). A `GridRow` does
  carry the paint properties, and its own entry lists the exact set. The
  structural regions (`When`, `ForEach`, `ErrorBoundary`) take none of these
  either — they answer presence, not paint.
- **layout containers** — the nine that inset, clip and declare overflow:
  `AdaptiveStack`, `Anchor`, `Composition`, `Grid`, `HStack`, `Screen`,
  `ScrollView`, `VStack`, `ZStack`. (`Button`, `Region` and `ViewThatFits` take
  `children` but are not in this group — see the container list below.)
- **the text-bearing controls** — `Text`, `Button`, `Toggle`, `TextField`.

| Property | Accepted on | Meaning |
|---|---|---|
| `animation` | every rendered class | Static named presets for `layout`, `scale`, `opacity`, `rotation`, `offset`; each property must be supported by the node. `false` disables that animation. Layout declarations coordinate surviving descendants at the next refresh; property declarations animate paint without layout work. See [component motion](../guide/15-components.md#animate-values-with-the-compose-runtime). |
| `id` | every class | stable node identity; required to address the node later (focus, tests, dumps) |
| `width`, `height` | every rendered class | dimension tables: `{type="fixed",px=}`, `{type="content"}`, `{type="hug",min=,max=}`, `{type="fill",weight=,min=}`, `{type="percent",fraction=,offset=,min=,max=}`, `{type="minMax",min=,preferred=,max=}`, `{type="aspect",ratio=}`, `{type="content",lines=,role=}` **or** `{type="content",rows=,of=}` (content-terms sizing — see below). The `px`/`min`/`preferred`/`max`/`of` fields take a number **or a theme metric name** (see below); `UI.fill(weight?)` and `UI.hug({min?,max?})` are the shorthand for the two most common raw tables |
| `margin` | every rendered class | outer spacing the parent reserves around this node; a number, a spacing-step name, or `{top?,right?,bottom?,left?}` of either. A **`fill` child spends its own margin out of its fill**, on every container — a `ZStack` layer with `margin = { top = 56 }` is 56 px shorter, not 56 px lower — and a filled axis therefore ignores `alignH`/`alignV`, because there is nothing left to align. A non-fill child keeps its size and is displaced, so alignment still applies to it |
| `anchor`, `offsetX`, `offsetY` | children of an `Anchor` (a `ScrollView` also reads the offsets as scroll-time nudges); a stack, grid or wrap parent places by flow and ignores all three | placement corner plus offset; offsets update in the arrange pass only (no re-measure). An offset takes a number, a theme metric name (`"-s"` negates one), or a **fraction of the parent's inner extent**: `{ scale = 0.5 }`, `{ scale = 0.5, offset = -4 }` (the marker-overlay shape — see `Anchor`) |
| `alignH`, `alignV` | children of a `ZStack` | per-child cross-alignment (`start`/`center`/`end`) |
| `padding` | layout containers, `Button`, and the text-bearing leaves `Text`, `Toggle`, `TextField` | inner spacing; on a control it is the text inset the adapter must match, and on a `Text` the measure adds it. A number, a spacing-step name (`"xs"`, `"tight"`, `"s"`…`"xl"`), or per-side values of either |
| `gap` | `Screen`, `VStack`, `HStack`, `AdaptiveStack`, `ScrollView`, `Grid`, `Button` | spacing between children along the stack axis; a number or a spacing-step name (`"xs"`, `"tight"`, `"s"`…`"xl"`). On a `Button` it spaces the button's own content |
| `align` | `Screen`, `VStack`, `HStack`, `AdaptiveStack`, `Button` | cross-axis alignment of children (`start`/`center`/`end`/`stretch`/`firstTextBaseline`/`lastTextBaseline`). A `Button`'s content stack — and any horizontal stack inside one — centres its children on the cross axis unless you declare `align` yourself; everywhere else the default is `start`. |
| `wrap` | `VStack`, `HStack` | let the children run onto more than one line when they do not fit the main axis (Roblox `UIListLayout.Wraps`). See `VStack` / `HStack` below — it adds no new alignment words, and `align = "stretch"` is refused beside it |
| `overflow` | layout containers | declared overflow handling (`clip`/`scroll`/`visible`/`intentionalOverlap`). **`"clip"` makes the node a clip host** — it sets `clipChildren` at construction unless you authored that flag yourself, so the word does the thing it names. The other three values are declared intent, read by the solver's overflow diagnostic and by the layout dump, and drive no engine property |
| `clipChildren` | layout containers | make this container an engine clip host; `ScrollView` defaults it to true |
| `active` | layout containers, `Box` | engine `Active` flag — an input-sinking panel (modal backdrops) |
| `surface` | layout containers, `Box`, `Button`, `GridRow`, `Image`, `Stage`, `TextField`, `Text` (only `"badge"`/`"chip"` — see `Text`) | surface style role painted behind the node; `"pane"` is the raised fill flush (no corner, no edge) — a sidebar or split pane beside the page |
| `enabled` | layout containers, `Button`, `Toggle`, `TextField` | `false` disables the node **and its whole subtree**: every descendant leaves focus order — both derivations (linear and directional), and every group, including the ones a control contributes for itself and a `navigationGroups` map you declare (a **static array** is filtered when the surface is presented; use the **function** form for a map that must follow a reactive `enabled`, which is the same rule `hidden` has always had) — refuses activation on every input class, and takes no pointer, touch or drag. The themed disabled state reaches the **text** of that subtree. **Inherited** — see [Inherited properties](#inherited-properties-enabled-and-tint) for the precedence rule, what is painted, and what is not |
| `tint` | layout containers (subtree only), `Box`, `Text`, `Image`, `Path`, `Stage` | the one continuous colour channel. On a painting class it paints that class's own channel; on a layout container it paints nothing and is **inherited** by the subtree. See [Continuous colour](#continuous-colour-tint) for the value forms and [Inherited properties](#inherited-properties-enabled-and-tint) for the precedence rule |
| `shadow`, `gradient`, `corners`, `stroke` | every rendered class, **and `GridRow`** | normalized style-modifier data — produce them with `UI.shadow` / `UI.gradient` / `UI.corners` / `UI.stroke`, never by hand |
| `zIndex` | every rendered class, **and `GridRow`** | paint-order override **within the parent's stacking scope**: siblings paint in `(zIndex or 0, declaration order)` order and a node's whole subtree travels with it. A child is always above its own parent, whatever its `zIndex`, so lifting across surfaces stays structural (`presentModal`'s display order). Read once at mount — a lift is what a node *is* (a drag ghost, a toast), not a state it passes through |
| `hidden` | every rendered class | `true` **keeps its layout space** (siblings do not move); use `UI.When` to remove it from layout. It stops painting the node — and takes its whole subtree out of focus order and off the tap path with it. It is the one thing neither of the other two answers gives you: `UI.When` *removes* the node so the siblings close up, and Roblox's own `Visible = false` frees the layout slot inside a `UIListLayout` (Facet arranges absolutely and materializes none of those, which is why one prop is enough). Reactive — bind it to a signal to reserve a slot until the value arrives. Reach for `UI.When` instead whenever the space *should* close up |
| `opacity` | `Box`, `ZStack` | fade this node **and its whole subtree**: `1` is opaque (the default), `0` is invisible while still laid out, focusable and tappable — reach for `hidden` when you want all three gone. Declaring it **makes the node a fade group** (you never write `canvasGroup = true` beside it), because a fade in this framework is one `CanvasGroup.GroupTransparency` write and that is the one alpha property no style rule owns — a per-node transparency write would permanently defeat the theme's own rules, which is why a leaf like `Text` refuses it. The spelling for a leaf is one wrap: `UI.ZStack { opacity = 0.4, children = { theText } }`, and reaching for it on any other class is a **construction error that says so and spells the wrap out** — `opacity` and `canvasGroup` are refused by name, never silently missing. A leaf cannot fade itself, because reading the sheet's value returns the node's own write from the first write onward, so a per-node fade has no stable base to compose against. It **multiplies** with any fade the framework is running on the same node (a transition, a toast retiring), by design, so an authored `0.5` inside a transition at half-way paints `0.25`. Reactive, and animatable through `presenter.withAnimation` |
| `scale` | every rendered class | paint-only uniform scale about the node's centre; `1` is unscaled. **It changes nothing the solver sees** — the layout box, the tap target and the focus order are all the unscaled ones — because a paint term never moves a measured box; to change a box, change `width`/`height`. It **multiplies** with any scale the framework is applying (a motion pop, an enter transition). Reactive and animatable. It **survives a press**: a `Button`'s dip shares the engine's single `UIScale` per object, so the dip is relative — it goes down to `resting x pressedScale` and comes back to `resting`, never to an absolute `1`. **Why this is on 21 classes and `opacity` on two**: a term is offerable where ONE engine property that no style rule owns expresses it for the class's whole painted output. `UIScale.Scale` is that property on every `GuiObject`, and it carries the node's descendants and its rule-created phantom modifiers with it; alpha's only such property is `CanvasGroup.GroupTransparency`, and only `Box`/`ZStack` can BE a `CanvasGroup`. **And unlike `opacity`, that reach costs nothing to switch on**: authoring `scale` (or `rotation`) on a container that actually has children makes that container a real engine parent for them — a plain `Frame`, never a `CanvasGroup`, because `UIScale.Scale` is not the alpha property and needs no buffer. Measured through the real framework: a `UI.ZStack{ scale = 1.5, rotation = 30 }` around an 80×40 `UI.Box` re-parents the box inside it, and the box comes out **120×60 at `AbsoluteRotation = 30`** — exactly 1.5× — while its own `Rotation` stays `0.0` and it grows **no `UIScale` of its own**: the engine composed both terms, no framework code did. Before this, the same container left its contents at `80×40, Rotation = 0` — a rotated plate with its contents sitting bolt upright beside it, which is why this shipped before 1.0 rather than after. A childless container or a rotated leaf earns no parent and no extra instance; declaring the prop is what registers the host, so an ordinary container with neither prop is untouched and stays elidable exactly as before. **SO RESERVE THE SPACE YOURSELF, and note that the amount grew.** Because the solver sees the unscaled box, a scaled node paints OUTSIDE its own slot and the parent has to leave room — and since Decision 4 the thing that paints outside is the whole SUBTREE, not just the one node. Found on a device (2026-08-17) on this framework's own showcase: a `100x70` container at `scale = 1.5, rotation = 30` draws a **182.40 x 165.93** footprint, and the demo had reserved `100x70` for it — so the pair spilled over the caption above it and past the panel's edge. The fix is a plain sibling box of the drawn size with the transformed node centred inside it; it must be OUTSIDE the node that scales, because a wrapper that scales with its contents reserves nothing. The footprint of a `w x h` box at scale `s` and angle `d` is `(w*s*|cos d| + h*s*|sin d|)` by `(w*s*|sin d| + h*s*|cos d|)` — compute it from the same constants that produce it rather than pinning a number, and round UP: the exact height above is `165.93`, and centring that inside a `166` reservation leaves 0.03px a side. **`Facet.layout.transformFootprint(w, h, scale, deg) -> width, height`** (gap 33, framework-gaps-phase2) is that exact formula, published, so a consumer computes the reservation instead of hand-transcribing the trigonometry |
| `rotation` | every rendered class | paint-only rotation in **degrees** about the node's centre; `0` is upright, positive is clockwise. Like `scale` it moves no layout and no hit geometry — a rotated button's tap target is its unrotated box — and it **adds** to any rotation the framework is applying. It is on every rendered class for the same reason `scale` is (above): `GuiObject.Rotation` is one property no generated rule writes. Reactive and animatable. **Reaches a container's children the same way `scale` does** — see the `scale` row above; the two terms are registered by the same rule and compose together on the same host |
| `offset` | every rendered class | paint-only translation in px from the node's SOLVED position (`{x=,y=}`; `0,0` = unmoved; gap 16, framework-gaps-phase2). It changes nothing the solver sees — the box, the hit target and the focus order stay at the solved position; to change WHERE a node is, change its layout (`margin`, `Anchor` offsets, position in the tree) — and it **adds** to any offset the framework is applying (a slide transition, a keyboard shift), the same composition rule `rotation` uses. Reactive and animatable through `presenter.withAnimation`'s steady state (it does not itself participate in a flight's interpolation) |
| `onAppear`, `onDisappear` | every rendered class | view-lifetime hooks, both called with the node's path. `onAppear(path)` runs **once**, on the frame the node is first rendered and **after that frame's layout solve**, so it can read its own rect (`controller.rectOf`) and nothing has reached the screen yet. `onDisappear(path)` runs **once**, **after** the node's render instance has been released — the path is already unmounted, so `rectOf` on it is `nil` — and it also runs for everything still mounted when the surface is torn down, so a cleanup is never silently dropped. The lifetime measured is the *rendered* one: a virtualized row that scrolls out of the window disappears, and a subtree still playing its exit transition has not disappeared yet. Not reactive (a lifetime is not a value that changes), and an error thrown inside a hook is loud rather than swallowed |
| `textSize` | `Text`, `Button`, `Toggle`, `TextField` | an explicit px number, a typography role name (`"caption"` \| `"label"` \| `"body"` \| `"heading"` \| `"title"` \| `"control"` \| `"strong"` \| `"numeral"`) resolved from the active theme, or **`"fit"`** — the largest size that fits the box this node lands in, chosen by the SOLVER (option form `{ fit = { cap = <role or px>, floor = <role or px> } }`; see below). A role supplies the **font descriptor and line height** as well as the size, and both travel to the measure seam AND the paint seam — so `"strong"` (emphasis at reading size) and `"numeral"` (a rank or score figure) are how a node asks for **weight**; there is no `weight` prop, because a face that reached only one seam is what `Text.font` was deprecated for. A px or role size is scaled at both seams; a `"fit"` size is already the painted one |

A fill dimension may declare `min` as a finite nonnegative pixel value, theme metric,
or additive list of those values. Stack shares keep their weighted integer sizes
when those meet the floors; constrained shares take their floors and the remaining
room is shared by the remaining weights. Margins are paid outside a positive floor.
An impossible offer keeps the minimum and reports overflow; explicit grid tracks
are not expanded. Spacer `minLength` retains its separate base-plus-remainder rule.
Omitting `min` preserves the existing fill behavior. Minimum-bearing fills require
finite positive weights. `UI.frame`'s infinity form remains a plain fill.

**`{ type = "content", lines = n }` / `{ type = "content", rows = n, of = metric }`**
 is how a box declares its extent in CONTENT TERMS — "about N lines/rows",
never measured from an actual child — which is what a scroller or panel viewport
needs when it must show *less* than all of its own content: a bare `{ type =
"content" }` measures everything and cannot express that, and a `{ type = "fixed",
px = 150 }` next to it is a number that tracks neither the player's accessibility
text preference nor the ten-foot ladder. `UI.Composition`'s Region floors have always
had this vocabulary (`{ lines = n }` / `{ targets = n }`); this publishes it for
every class.

`lines = n` (optionally `role`, default `"body"`) reserves `n` lines of a
typography role — the SAME two calls `Facet.text.lineBox` makes
(`ceil(n * (roleSize * scale + offset) * lineHeight)`), so it grows with a raised
text preference and the ten-foot ladder exactly as the text it holds does:

```lua
UI.ScrollView({
  id = "Notes",
  height = { type = "content", lines = 6 }, -- ~six lines of body text, then scroll
  children = notes,
})
```

`rows = n, of = metric` reserves `n` rows of a NAMED THEME METRIC — a metric path,
a space step, or a literal px (the same `px`/`min`/`max`/`preferred` escape hatch):

```lua
UI.ScrollView({
  id = "List",
  height = { type = "content", rows = 4, of = "controlSizes.compact.height" },
  children = rows,
})
```

The two shapes track **different** axes, and the split is deliberate rather than a
gap: `rows`+`of` reads only a theme metric, so it grows at the ten-foot ladder
(`metricScale` already scales `controlSizes`/space steps) but **not** at a raised
`preferredTextOffset` — a theme metric never has. `lines` goes through the text
seam, so it tracks both. Pick `lines` when the box holds text whose growth you must
follow; pick `rows` when it holds a repeated control-sized item and the metric that
sizes one is the metric you want N of. Neither adds a gap term between
lines/rows — the same limitation `composition.floorPx`'s two existing forms
already have.

**`textSize = "fit"`** is the declarative face of `Facet.text.fit`, and it exists because
the imperative one kept losing: a character count times a guessed constant is one line,
while `text.fit` costs a memo, a `use`, an env read and a font name — *per site*. A survey
run in 2026-08 found seven near-duplicates of that formula in this repository and exactly
one of them correct — a dated finding, re-run 2026-08-22 and now **zero** outside
`text_metrics` itself, which this prop is the second half of closing. The prop is shorter
than the character count, and it is resolved
**inside the solver**, which is the only place the box, the face, the typography scale and
the paint offset are all already in hand — so it is scale-correct and offset-correct by
construction rather than by care.

```lua
UI.Text({ id = "Cta", text = label, lineLimit = 1,
          width = dims.fixed(240), height = dims.fixed(52), textSize = "fit" })

-- ...and with an explicit band:
textSize = { fit = { cap = "title", floor = 12 } }
```

- **`cap`** — the largest size this node may paint at, a typography role name or a px
  number. Absent it is the class's own intrinsic role, i.e. exactly the size the node
  would have painted without the prop: adding `"fit"` can only ever make text *smaller*.
- **`floor`** — the smallest. Absent it is the theme's `caption` role, which every package
  is required to carry. A theme-owned floor is the point: "never below this theme's
  smallest type role" survives a package swap and the ten-foot ladder, where a literal
  would not, and where `text.fit`'s own raw default of 1 would let a label paint
  unreadably rather than let the layout decide.
- **the box is the node's own**, not its parent's offer — the same width and height rule
  the compact ladder and `ViewThatFits` each had to be fixed for. `lineLimit` is the line
  budget; with no `lineLimit` wrapping is free and only the HEIGHT can refuse a size.
- **an unknown option key is refused at construction** (`{ fit = { max = 24 } }` names no
  ceiling), because an accepted-and-ignored key is the §4 violation the placement audit
  exists to end.

Reach for a px or role size whenever the box can grow instead: `"fit"` shrinks TEXT to fit
a box, and a screen that should grow its box for a larger preference wants the size as a
*value* (`Facet.text.fit`) so the box can be derived from it.

| `textAlign` | `Text` | horizontal alignment of the node's own text in its box (`start` \| `center` \| `end`); default `start`. Vertical alignment stays adapter-owned and is always centred, because the headless measurer over-reserves and centring splits that error evenly |
| `focusable` | `Button`, `Toggle`, `TextField` (opt **out**), `Grip` (opt **in**) | membership in focus order |
| `traversalPriority` | `Button`, `Toggle`, `TextField`, `Grip` | linear-traversal (Tab/Shift+Tab) sort **tier**, default `0`. The sort key is `(traversalPriority, document position)`, so a negative value traverses earlier and a positive one later, and **within a tier document order always wins** — the `tabindex` model. Affects Tab only; the directional arrows never read it. Construction-only: a traversal position is what a node *is*, so binding a Readable here is refused with the rebuild idiom |
| `onActivate` | `Button`, `Toggle` | `onActivate(path, meta)` — the presenter auto-dispatches tap / Return / ButtonA to it |

**Theme metric names.** Anywhere the table above accepts a theme-owned number
it also accepts a NAME for it, resolved from the active `ThemeSnapshot` on every
solve — which is why installing or swapping a theme changes geometry without
rebuilding a blueprint. A name is either a spacing step (`"xs"`, `"tight"`,
`"s"`, `"m"`, `"l"`, `"xl"`, or the derived screen-edge step `"gutter"`) or a
dotted path into the snapshot
(`"targetSizes.minimum"`, `"targetSizes.hit"` — the live hit floor, which a
theme's optional `targetSizes.pointer` lowers while the input is pointer-only —
`"controlSizes.large.height"`,
`"controls.slider.thumbSize"`, `"strokes.hairline"`, `"radii.panel"`,
`"controls.decorative.minimum"` — the theme-owned floor for a non-text decorative
box with nothing of its own to measure, `"controls.focusRing.thickness"` — the
focus ring's own painted weight, mirrored from `style.extra.focusRingThickness`/
`tenFootFocusRingThickness` so a layout computation can read the same number
`screen_target` paints); a leading
`-` negates it (`"-s"`). `textSize` instead takes a typography ROLE name.
An unknown name is a construction error that lists the vocabulary. A literal
number stays legal everywhere and thereby marks that value explicitly
theme-independent.

**Containers** (take `children`) — thirteen, and this is the list the runtime's
own "does not take children" error prints: `AdaptiveStack`, `Anchor`, `Button`,
`Composition`, `Grid`, `GridRow`, `HStack`, `Region`, `Screen`, `ScrollView`,
`VStack`, `ViewThatFits`, `ZStack`. **A `Button` is a container**: it takes `children`,
which render inside its one activation surface (see `Button` § Custom content).
`Region` and `ViewThatFits` are containers whose children mean something
specific — ranked forms and candidate layouts — which is why they carry none of
the layout-container properties above.

**Leaves**: `Text`, `Image`, `Toggle`, `TextField`, `Box`, `Spacer`, `Divider`,
`Path`, `Stage`, `Foreign`, `Grip`. **Structural regions**: `When`, `ForEach`, `ErrorBoundary`.
**Style modifiers**: `shadow`, `gradient`, `corners`, `stroke`, `styleGroup`.

#### Continuous colour: `tint`

`Box`, `Text`, `Image`, `Path` and `Stage` accept a **`tint`** — the one
continuous colour channel, on the **binding** authority, for values a finite
selector cannot express. Two value forms:

| Form | Meaning |
|---|---|
| `{ role = "accent", blend = 0..1, from? }` | **themable, preferred.** Blends from `from` to `role` — both names from the closed palette vocabulary (`surface`, `surfaceStrong`, `content`, `contentStrong`, `contentSecondary`, `accent`, `onAccent`, `control`, `controlSelected`, `onSelected` — the label colour the theme itself chose to read on `controlSelected`, gated at 4.5:1 — `danger`, `onDanger`, `hairline`, `selection`, `onSelection` — the ink an on or chosen indicator paints and its partner, the accent pair unless the theme authors them), resolved against the **active theme**. `from` defaults to the class's identity paint: the page colour for a `Box`, `content` for `Text`/`Path`, white (the picture as authored) for an `Image` — and white for a `Stage` too, for the same reason: white multiplies to the scene the engine already drew. `blend = 0` is the base, `1` is the role. **A theme commit re-resolves it**, so a tint that nothing ever re-writes still follows a runtime package swap (fixed 2026-08-14). |
| `{ direct = { r, g, b } \| "#rrggbb" }` | a **declared theming-exempt** identity hue — the loud word is in the value, so every use greps. Use it when the colour IS game data (a racer's hue), never for a state. |

**`transparency` (0..1, either form, default `0` = opaque).** The tint's own
alpha, engine-true and the same word and polarity as [`UI.stroke`](#stroke).
It exists for the one thing a composite cannot express: a translucent plate over
a backdrop the author cannot know — a scrim over a live 3D scene, a label pill
over a canvas that draws its own content. Where the backdrop *is* known, prefer
stating the composite colour: one paint per node stays themable and
contrast-checkable, and an alpha does not.

It rides the tint's existing claim on a `Box` (a tinted Box has always owned
`BackgroundTransparency`); on `Text`, `Image` and `Stage` it claims one more
property (`TextTransparency` / `ImageTransparency`) and only when it is declared,
so a tint without it is byte-identical to before. A `Path` carries this alpha
through a uniform child `UIGradient.Transparency`, which requires the upgraded-gradient
engine feature (initially a Studio beta). Do not use that channel as evidence of
an ordinary-client fade. Path2D itself has no publicly writable transparency
property. A direct Path2D modifier is not a reliable CanvasGroup fade; RadialMenu
places its Path host Frame inside a bounded compositor with its label, and does
not depend on gradient alpha. The gradient is reused across updates and removed
with the Path. Ordinary-client pixel verification remains separate from inspecting
these numeric properties.

**A value from a closed set is a state, not a tint.** Hover, selected, disabled,
verdict, phase — those stay `surface`/`role`/`selected` + tags + native-sheet
rules, which is what keeps them themable and contrast-checkable.
Reaching for the continuous channel to express one is a defect, and the schema
cannot catch it for you.

**What a tint claims.** Each class hands the adapter exactly one paint channel:
`Box` → `BackgroundColor3` **and** `BackgroundTransparency` (the pair the
declared alpha rides; the *default* fill is a tag rule instead — see below),
`Text` → `TextColor3`, `Image` → `ImageColor3`,
`Stage` → `ImageColor3` as well (a stage's "picture" is the scene it renders and
the engine multiplies it through the same pair, so the tint hues the *content*,
not the plate), `Path` → the `Path2D`'s colour. In native-stylesheet mode those properties are
sheet-owned, so a tinted node **claims** them: the write is an intentional,
recorded defeat of the rule, published on the instance as the
`Facet_PaintClaims` attribute so the `GetStyled` authority audit reads a declared
hand-off instead of tripping on an accident. Two consequences, both by design — a
claim is permanent for the instance's lifetime (releasing a tint restores the
value recorded when the claim was taken; the engine has no operation that gives
ownership back), and a claimed property does not follow a theme swap. That is
the price of a continuous channel, and the reason finite states must stay on tags.
The node's other properties are untouched: its tags stay, so its radius, its
hairline and its hover/press rules keep working.

**...and the FILL a tinted `Box` needs is a tag, not a claim** (director report
2026-08-15). A bare `Frame` is transparent until something says otherwise —
that is the sheet's own `Frame default` rule — so a tinted Box must also become
*filled*, and for two years it tried to do that by writing
`BackgroundTransparency = 0`. **The engine decides "explicit" by VALUE, and `0`
is `Frame.BackgroundTransparency`'s class default**, so that write claimed
nothing at all: the rule kept ownership and every tinted Box with no `surface`
and no declared `tint.transparency` painted *nothing*. Measured live —
raw `0` / `GetStyled` `1`; write `0.001` → `GetStyled` `0.001`; write `0` again →
`GetStyled` `1` back. So
the fill now rides the `facet-tint-fill` tag and one `Tint fill` rule, emitted by
both sheet builders in the `base` group — **above** the class defaults it exists
to beat and **below** every surface, value slot and scrim, whose own alphas still
win. A declared `tint.transparency` is a real value the engine accepts as
explicit and still rides the claim, so it out-ranks all of it. The colour stays a
claim, because a rule cannot carry per-node data; the fill is a finite state, and
finite states stay on tags.

#### Inherited properties: `enabled` and `tint`

Two properties are declared on a node and apply to its **whole subtree**. They are
the only two: everything else in the tables above describes the node it is written
on. Both are reactive, and a change to either re-solves in place — mount identity,
focus, scroll and in-flight state all survive, exactly as an axis flip or a theme
swap does.

**`enabled = false` disables the subtree, and disabled is a conjunction.** A node
is disabled when it declares `enabled = false` or when *any* ancestor does. There
is no re-enable, in either direction:

| You wrote | What happens |
|---|---|
| `enabled = false` on a container | every descendant is disabled |
| `enabled = true` on a descendant of a disabled container | nothing; it stays disabled |
| `enabled = true` on an ancestor of a node that declares `false` | nothing; that node stays disabled |

A disabled node leaves focus order (so Tab, the arrows and the gamepad all skip
it), refuses Activate from every input class, is not hit by a pointer or a touch,
acquires no drag, and offers no secondary action — a row's swipe tray and a
long-press menu are routed through the same paths and stop with them. Focus that
was sitting inside a subtree when it is switched off falls to the nearest
surviving focusable outside it, the same way focus behaves when a focused node is
removed. And the resolved state reaches the engine, so an ancestor-disabled
`Button` is genuinely non-interactable rather than merely skipped.

**`tint` cascades, and the nearest declaration wins.** A node paints the `tint` it
declares itself; failing that, the one declared by its nearest ancestor; failing
that, none. A nested container's `tint` replaces the outer one for its own
subtree. An inherited tint lands on every descendant whose class has a channel to
paint it into — `Box`, `Text`, `Image`, `Path`, `Stage` — and paints exactly what
the same value written on that node would paint, theme role and all. On a layout
container the property paints nothing at all: a container has no paint channel,
its plate is `surface`.

```lua
UI.VStack({ id = "Team", tint = { role = "accent", blend = heat }, children = {
    UI.Text({ id = "Name", text = racer }),            -- accent
    UI.Image({ id = "Crest", image = crest }),         -- accent
    UI.Text({ id = "Note", text = "?", tint = muted }), -- its own
} })
```

**The cascade stops at a control.** `Button`, `Toggle` and `TextField` do not
accept a `tint` and do not pass one into their own content: inside a control,
paint belongs to the role and the state machine, and a continuous colour there
would be a second authority over the affordance ([above](#continuous-colour-tint)).
A control *beside* tinted nodes is unaffected either way.

**What the disabled state looks like, exactly.** It is themed, through the sheet,
never a literal. A disabled control keeps the engine `:NonInteractable` rules it
always had. Beyond that, **one rule ships**: every theme — Facet Neutral and
every package — emits `Disabled subtree text`, which selects a `TextLabel`
carrying the `facet-state-disabled` tag and dims it to that theme's own
`disabledContentOpacity`.

A theme that sets `extra.dimDisabledPlates = true` also fades the **plate**: every
Button fill (standard, selected, accent, emphasis, soft, destructive, a selected
chip) and a disabled checkbox box blend toward the page by the same
`disabledContentOpacity`, so the whole control reads disabled. Unset (every shipped
theme), only the label dims.

Three consequences, all deliberate, none of them a bug to report:

- **Authored pictures keep their own paint.** Give a picture a `tint` if it
  should dim with the panel. The framework's generated primary control icons
  are managed chrome: their image opacity follows the same disabled decision
  as the label, while their hidden fallback glyph stays suppressed.
- **The tag reaches the classes that consume it** — `Button`, `Toggle`,
  `TextField` and `Text` — and not every node in the subtree. Writing a property
  to a container the renderer had elided materializes it permanently, and the
  framework will not buy a real `Frame` per container to carry a tag no rule
  selects. A theme that wants to key a disabled rule on another class needs that
  set widened, which is a framework change and not a package one.
- **A claim outranks the disabled dim, and only a LEAF may make one.** A `tint`
  that declares its own `transparency` *claims* `TextTransparency` on that node —
  an intentional, recorded defeat of the sheet, permanent for the instance's
  lifetime (see [Continuous colour](#continuous-colour-tint)). A rule never beats
  a claim, so a label whose tint declares an alpha stays at the alpha it declared,
  disabled or not; a tint with no `transparency` claims nothing there and dims
  normally. **A container's `tint` refuses `transparency` at construction**: the
  claim is per-node and permanent, so one container declaration would take
  `TextTransparency` from every `Text` beneath it for the life of the surface,
  including long after the tint itself was cleared. Write the alpha on the leaf
  that needs it — the error says so.

**The arrows cannot cross a `Grid` row whose every cell is disabled.** A grid
names each row group's `up`/`down` exit by index, so a row with no members left is
still the named neighbour and the move lands nowhere: everything below it is
unreachable by the arrows and the pad. `hidden` behaves the same way and always
has — what is new is that `enabled` is inheritable, which puts the shape on an
ordinary screen. **Lay the same content out as stacked `HStack` rows and it is
crossed cleanly**, which is the way around; `UI.When` is the other, and it closes
the space up as well. Tab is unaffected either way: linear traversal walks the
order, not the exits.

**A presented surface is its own root.** A modal, a toast, a menu, a popover or
an anchored sheet is mounted as a fresh tree, so it does **not** inherit the
disabled state or the tint of whatever presented it. Opening one from inside a
disabled subtree cannot happen — the trigger is dead — but one that was already
open when the panel was switched off stays live and stays interactive. Dismiss
it yourself if that is not what the screen means.

### `Screen`

`UI.Screen{ id?, padding?, gap?, distribute?, surface?, children? }` — root container of a
presented screen; fills the presenter-resolved content rect (safe-area aware).
`distribute` is the shared main-axis distribution documented under `VStack` /
`HStack` below.

### `VStack` / `HStack`

`UI.VStack{ id?, gap?, padding?, align?, distribute?, wrap?, width?, height?, offsetX?, offsetY?, surface?, children? }`
— vertical / horizontal stacks. Children with `fill` dims share leftover
main-axis space by weight; `align` = `start | center | end | stretch | firstTextBaseline | lastTextBaseline` on the
cross axis. Stack children never overlap along the stack axis. A stack that hugs
its main axis reserves what its `fill` children measured (weighted so each gets at
least that), so a fill `Text` in a hugging row keeps its natural width and wraps
at the offer rather than being arranged at zero and painting outside its box.

**`wrap = true` lets the children run onto more than one line** — Roblox's
`UIListLayout.Wraps`, and a stack that does not fit its main axis wraps instead of
painting past its own box. It is a **prop, not a class**: a wrapping stack is the
same stack in a second mode, so it keeps every other word it had, and it is
reactive — `wrap = adaptive.conditions(…).compact` re-solves in place and never
remounts a child. No comparable declarative flow layout exists to copy
(checked 2026-08-13), so this shape follows Roblox's own wrapping behaviour.

It adds **no new alignment vocabulary**, because the engine's own rule was
measured rather than guessed (Studio, 2026-08-13): the lines are packed with no
extra space between them, and the whole *block* of lines is placed on the cross
axis by the alignment the container already had. So

| where | the word |
|---|---|
| the block of lines, on the cross axis | `align` (`start`/`center`/`end`) |
| one item inside its own line | `lineAlign`, on the child |
| each line's leftover, on the main axis | `distribute`, per line |

and a line is as tall as its tallest item. One `gap` spaces both the items and the
lines, exactly as `UIListLayout.Padding` does.

Four rules worth knowing before you reach them:

- **`align = "stretch"` is refused** on a wrapping stack — it would mean both "each
  child fills its line" and "the lines grow to fill the container". Put
  `lineAlign = "stretch"` on the children that should fill their line. A literal
  one is a construction error; a bound one is reported on `controller.diagnostics()`
  and treated as `start`.
- **an item wider than the line** gets a line of its own, is clamped to the line,
  and says so on `controller.diagnostics()`.
- **the lines can overflow the CROSS axis** — that is the direction a wrapping
  stack runs out of room — and that is reported too.
- **a `fill` main-axis child takes a whole line to itself**, since a wrapping stack
  has no single leftover to share; that is reported rather than left to surprise
  you. The shrink pair (`layoutPriority`/`shrinkWeight`) is not read at all here:
  wrapping *is* what this stack does with a deficit.

**It does not compose with `UI.VirtualList`** — that is a deliberate non-goal. The
virtualizer windows by `index × pitch` and needs a uniform item extent; a wrapped
line has ragged extents and a variable items-per-line, so `index × pitch` cannot
window it. `UI.VirtualList`'s spec is closed, so `wrap` there is a construction
error.

**`distribute` spreads the LEFTOVER main-axis space**: `start` (the default, and
byte-identical to the packing every stack did before it existed) | `center` |
`end` | `spaceBetween` | `spaceAround` | `spaceEvenly`. It is Roblox's
`UIFlexAlignment` plus whole-group centring, and it lives on the CONTAINER. It is
arrange-only — it moves the cursor and never resizes a child — and the same prop
is on `Screen` and `AdaptiveStack`.

Hand-placed `Spacer`s could already reproduce SpaceBetween/Around/Evenly
pixel-exactly, but only for a STATIC child list: a variable-count list goes
through `UI.ForEach`, whose `row` returns exactly one blueprint, so separators
cannot be interleaved on the parent's main axis at all. A tab bar whose tab count
varies was inexpressible; that is why this is a prop.

**It acts on what `fill` children did not take**, so a `fill` child leaves it
nothing — and a non-`start` `distribute` on a stack that has one is reported on
`controller.diagnostics()` naming the conflict rather than silently doing nothing.
The fractional part of the lead and the per-gap step is carried rather than
dropped per gap, so the whole leftover lands as whole pixels and the arrangement
stays symmetric instead of drifting left.

### `ZStack`

`UI.ZStack{ id?, alignH?, alignV?, width?, height?, surface?, shape?, canvasGroup?, opacity?, virtualSlot?, children? }` —
layered container; children align independently (`alignH`/`alignV`), `fill`
children stretch to the stack (scrims, backdrops).

**`shape = "circle"`** — the circle Button's guarantee (below), generalized to
this class: a true 1:1 box, the missing axis derived by the solver,
authoring both refused at construction. Not reactive, for the same reason it
isn't on a Button. Use it for a ring/disc **composite** you build yourself out
of `UI.Path`/`UI.Box` layers (a progress ring's track + sweep + a centered
identity mark is the shipped example, `examples/reference/p1_glade`'s
`SupplyRing`) — a circle Button is still the right primitive for a single
interactive disc. Paint costs a flat theme nothing here either: it is the
identical `facet-shape-circle` phantom `::UICorner`/`::UIStroke` rule, which
only matters if this stack (or a descendant) is filled — a stack of pure
strokes has nothing for the corner to round.

`virtualSlot = { list, extent, axis?, contentFrom? }` declares that this stack is
**one slot of a fixed-pitch windowed list** — a list that places item *i* at
`i × extent` and therefore depends on `extent` being the item's TRUE size.
`UI.VirtualList` declares it on every row it builds, so ordinary callers never
write it; declare it yourself only on a hand-rolled surface that windows the same
way. It changes no geometry. Per solve, the solver measures the slot's content
(children from `contentFrom`, default 1) along `axis` (`"y"` default) and, when
that measure is **taller than `extent`**, files a finding through
`controller.diagnostics()` naming *both* numbers and the row — see
[a lying `itemExtent`](#a-lying-itemextent). Content SHORTER than its slot is
legitimate over-reservation and says nothing, and a cell that scrolls or clips its
own overflow is skipped. The finding is worded in `UI.VirtualList`'s vocabulary
(it quotes `list` and calls `extent` "itemExtent"), which is what a hand-rolled
declarer will read back.

`canvasGroup = true` makes this stack a **fade group**: the adapter materializes
it as a `CanvasGroup`, it becomes its subtree's real instance parent, and
`controller.setPresentationTransparency` fades the whole subtree through one
`GroupTransparency` write that no style rule owns. It is the container form of
`UI.Box{ canvasGroup = true }` (which fades a single plate), and it is what a
fading `transition` needs — a leaf has no subtree to fade. Not reactive: it
decides which engine class the node IS, at creation, and it costs a render
buffer, so declare it only where a group fade is wanted. It is not the only way
to become a subtree's real instance parent any more: an authored `scale` or
`rotation` on children this stack actually has does the same thing for those two
terms, at the cost of a plain `Frame` rather than a buffer — see the `scale`/
`rotation` rows in the shared-property table above: a container that authors
either term becomes a real engine parent, so the engine carries both down its
whole subtree.

**`opacity`** is the AUTHORED half of the same thing, and declaring it implies
`canvasGroup` — see the shared-property table above. `UI.ZStack{ opacity = 0.4 }`
fades the whole subtree, reactively and animatably, and is the wrap you reach for
when the thing you want to fade is a leaf.

<a id="canvasgroup-costs"></a>
**What a group costs — three engine facts, and they apply to both forms** (the
`ZStack` one is what the presenter's surface transitions wrap a whole screen in,
so read them before declaring one there):

- **Descendants are always clipped to the group's bounds.** A `CanvasGroup`
  renders its subtree into its own buffer, so decoration that overflows the box —
  a shadow, an outside stroke, a ten-foot focus glow — is cut, whatever the node's
  own `clipChildren` says. Size the group to include what must be visible.
- **Past the client's texture-memory cap a `CanvasGroup` renders as a blank
  texture**, and its quality follows the client's `QualityLevel`. On a weakest
  device that is a whole subtree gone, not a degraded one, so groups are declared
  where a fade is wanted and nowhere else.
- **Resizing recreates the texture**, and Facet writes `Size` on every re-solve
  that changes the box. A group belongs on a subtree whose box is stable (a card,
  a toast, a screen), not on one that re-measures every frame.

### `ScrollView`

Horizontal scroll views support mouse click-drag scrolling automatically, including
card rails and pages. Child controls get first refusal: text selection, sliders,
and declared drag gestures keep their input. A drag must cross a horizontal
movement threshold before it scrolls or suppresses the originating click.

`navigation` optionally names descendant targets and exposes target selection,
normalized progress, threshold visibility callbacks, and gesture snap; see
[Adaptive navigation continuity](#adaptive-navigation-continuity). Framework
keep-visible and bookmark writes take precedence over gesture snapping.


`UI.ScrollView{ id?, axis? ("y" default | "x" | "xy"), scrollEnabled?, extent?, padding?, gap?, autoscroll?, indicators? ("auto" default | "none" — a peeking carousel's affordance is the half-visible next tile, so it may declare its indicator off; layout is untouched), chromeReserve? ("auto" default | "none" — the lane a scroller keeps for content chrome that reaches past its box: `max(0, chromeBleed − the slot's own carve)`, because a carved frame already holds content that far from the clip edge (`chrome_slots.bleedLane`, netted per solve). A scroller whose rows are plain and whose only art draws inside its box, such as a menu card's list, declares "none" and its content runs to its edges), onScrollWheel?, children? }`
— scrolling container. `onScrollWheel(path, delta, rectOf)` receives
hover-wheel input routed by the adapter (the composite scrolling controls use
it; a plain `ScrollView` relies on the native host instead). the scroll axis measures children unbounded and reports
`contentSize` to the renderer. On the Roblox adapter it mounts as a native
`ScrollingFrame` (native-substrate NS-A2): the solver owns every content rect
and the canvas extent (`contentSize` + the padding the solve actually spent + the
chrome lane it kept, published together by `layout/scroll_arrange.luau`), while the ENGINE owns live
scrolling — wheel, touch momentum, elastic overscroll, and scroll bars. It is
always a clip host (`clipChildren` defaults true), so the fallback path (an
adapter without the scroll seam, e.g. billboards) still crops overflow.
**The axis accepts a string or readable string.** Changing it retains the native
host and child identities, updates directional navigation, and clamps the scroll
position to the new canvas. In-flight named travel retargets on the new axis; a
player-cancelled focus handoff stays cancelled. VirtualList and VirtualGrid axes
remain construction-only.

**Both axes work.** `axis = "x"` lays children out along x, accumulates the
canvas extent along x, and stretches cross-axis `fill` children to the viewport
height (before this the solver stacked horizontal children in a column and
reported a canvas the engine could not scroll to).

**…and both at once.** `axis = "xy"` is the engine's own `ScrollingDirection.XY`:
children stack down it exactly as they do on `"y"`, and the difference is that
neither axis clamps its canvas to the viewport — so content past the box on
*either* axis is reachable. Reach for it for a map, a wide table, a pinboard.

An `xy` host is treated as a `"y"` host everywhere a single axis is assumed, and
the chrome lane, leading-edge bleed reserve, drag-to-edge autoscroll band, and
`scrollIndicatorPolicy = "auto"` bar compensation all take their vertical branch.
An xy board that overflows only horizontally therefore keeps no bottom lane and
still widens for the vertical bar. These are the current single-axis chrome
policies; they do not infer the overflowing axis.
Nested-scroller arbitration follows the same chain rule as any other pair: an
`xy` host already at the end of the band the drag is asking for is transparent and
the page behind it wins. **Wheel and touch momentum between nested plain
scrollers is the ENGINE's arbitration, not Facet's, exactly as it is for two
nested `y` hosts.**

**`scrollEnabled`** (`Bound<boolean>`, default true) freezes **player** scrolling
through the engine's own `ScrollingEnabled`, and Facet's own drag-to-edge
autoscroll respects it too. Nothing else changes: the offset it was at is the
offset it stays at, every child keeps its rect, and **framework keep-visible and
`controller.scrollTo` may still move the canvas** — focus reaching a node the
player cannot see is the one thing a freeze must not cause. Bindable, because a
screen freezes a list while a sheet owns the gesture and thaws it afterwards. A
freeze re-places; it never re-measures.

**`extent = { width?, height? }`** states the canvas directly, in pixels or as a
theme metric name, for a host whose canvas is a *coordinate space* rather than a
content sum — a map with three markers on it has a canvas the size of the map and
content of three pins. At least one axis is required, and **only on an axis this
host scrolls**: a `y` host takes `height`, an `x` host `width`, an `xy` host
either or both. A cross-axis `extent` is a spec error, because the adapter clamps
a canvas back to the window on an axis the engine cannot scroll (it must, or the
engine draws a bar nothing can move) — so accepting one would be a declaration the
live target discards and a headless one honours. The axis left out keeps the
derived canvas (content + the padding the solve spent + the chrome lane it kept).
An extent smaller than the content is honoured as written: the content past it
cannot be scrolled to, and nothing warns.
Construction-only, and it needs a static `axis` for the same reason a tile mode
needs a static `scaleMode`. Each authored extent must be positive and finite, or
name a known non-negated metric that resolves to positive finite pixels. Zero,
negative, infinite, NaN and unknown values refuse; a bad live metric answer keeps
the last published canvas until the metric recovers.

**`indicators` is one word for both axes.** *Engine limit, recorded rather than
worked around:* a `ScrollingFrame` carries ONE `ScrollBarThickness` for both bars,
so there is no per-axis suppression to expose — a per-axis table whose axes
disagreed would be a declaration that does nothing, and one whose axes agreed
would be this word. A table is refused at construction.

**Scroll indicators (director ruling 2026-08-28, the latest of three).** The
environment derives `scrollIndicatorPolicy` from `interactionClasses.primary`
— `"always"` on pointer sessions (the desktop convention: a persistent bar),
`"auto"` on touch and gamepad sessions (the platform convention: an overlay
indicator, hidden at rest, that FLASHES once when a scrollable region first
mounts — so a page that continues below never reads as cut off — shows while
scrolling, and fades when idle). Reduced motion never fades: `auto` degrades
to visible-whenever-scrollable.

Changing input also reflows the content for the new scrollbar reservation,
even when the page content and viewport are unchanged. Screens do not need to
remount or manually refresh their scroll layouts.

**Persistent holds space; auto does not — and neither clips.** `"always"`
reserves the bar's thickness *plus one pixel* off the scrolling region's cross
axis (director report 2026-08-30: reserving the bar exactly is correct and still
lands every card edge on the bar's outermost pixel, which reads as an overlap —
so the reserve carries a one-pixel gutter, and the bar itself is unchanged. It
comes off whichever edge the cross axis is, so a horizontal scroller gets the
same clearance along its bottom). `"auto"` reserves NOTHING (content is measured to the full width) —
but Roblox's engine still narrows a `ScrollingFrame`'s own visible window by
the bar's thickness whenever the scroll axis overflows, regardless of paint
policy (measured directly: even a fully transparent bar image still narrows
the window). A bare zero reserve would therefore clip exactly the content a
zero reserve was meant to save — the 2026-08-09 defect the 2026-08-12 ruling
reverted to fix. The 2026-08-28 ruling gets both: the target widens the
scroll host's own frame by the bar's thickness on the cross axis whenever
"auto" overflows, which cancels the engine's narrowing one-for-one, so the
full-width content lands on a full-width window. The extra thickness the
frame now occupies sits beyond the box the solver gave it — typically the
padding/gap that already follows a scroller — which is where the indicator
ends up: genuinely overlapping whatever is there, not a permanently reserved
gutter. A scroller authored with less than the bar's thickness of trailing
room has nothing safe to widen into (no viewport-bounds clamp exists yet).

The presenter pushes the policy through the declared optional target method
`setScrollIndicatorPolicy(policy, reduced)`; an adapter without the seam keeps
the constant persistent bar. `scrollBarInsetOf(path)` reports the gutter a
host reserved on its last solve — bar plus the one-pixel clearance, on `right`
for a `y` scroller and `bottom` for an `x` one; non-nil only for an overflowing
`"always"` host, always nil for `"auto"` (nothing was reserved to report). The
indicator's COLOR stays the theme's `Scroll bar` rule; its visibility is
behavior, not paint. Known limit, recorded: the engine bar is a single
tintable image, so a theme-colored thumb can vanish over live WORLD content
behind a transparent surface — outline indicator art is the follow-on
(framework-fixes.md).

**`autoscroll` — drag-to-edge, and it belongs to the SCROLLER.** While a pointer
drag is in flight, a `ScrollView` whose edge band the drag point is inside scrolls
itself, so a drag can reach content below the fold. It is **on by default and
inert**: nothing happens unless a drag is announced, so a screen with no draggable
content behaves identically. Pass `false` to opt a scroller out entirely, or an
options table to tune the model (`bandH`, `dwellS`, `rampS`, `exitEaseS`, `vMin`,
`vMax` — see `Facet.newAutoscroll` for what each one means). The band defaults
to the HOST's own shape, not the screen's: **40 px** when the host is wider than
it is tall, **44 px** when it is taller (a portrait box has less vertical room to
aim at). The framework picks between the two per host; there is no call to make.

The policy lives here rather than in the draggable content for two reasons: the
thing that has to move is usually *not* the control being dragged (a block `Table`
inside a scrolling page is the common shape), and only the scroller chain can
answer the nested question. **Nested scrollers resolve innermost-outward**: of the
scrollers whose painted rect contains the drag point, the nearest one that has the
point in one of its own edge bands *and* can still travel that way wins. A host
already pinned at that end is transparent and the drag falls through to its parent
— which is what lets a short inner list hand off to the page once its tail is
reached. `autoscroll = false` is a real refusal, not a lower priority: the chain
skips that host and keeps walking outward.

A drag announces itself with `controller.setPointerDrag({ pos, refresh? })` and
retracts it with `setPointerDrag(nil)`; `refresh` is called after a scroll lands so
the drag owner re-resolves its verdict in the **same frame** (a tick-late
re-resolve lags about two rows at the top speed). `Table`'s reorder does this for
you. The presenter drives one `controller.stepAutoscroll(dt)` per surface on its
own tick — a finger parked in the band emits no further pointer events, so nothing
input-driven could ever start the scroll.

The offset is readable and settable, and scroll-to-visible is a framework
service rather than a per-control recipe:

| Call | Meaning |
|---|---|
| `controller.scrollTo(path, {x,y})` | programmatic position; the engine clamps it |
| `controller.scrollPosition(path)` | the LIVE offset, read from the engine (it co-authors the value, so a user fling the framework never saw is still reflected) |
| `controller.scrollToVisible(path, localRect?)` | scroll containing `ScrollView` **ancestors**, inner to outer, the minimum distance that brings the node into view, or the supplied `{x,y,w,h}` rectangle relative to it; uses each host's canvas limits and returns `false` when no host moves, there is no scroll ancestor, or the adapter has no scroll seam |
| `controller.observeScroll(path, fn)` | engine-driven offset changes (virtualization consumes this) |

`scrollToVisible` is the ONE keep-visible substrate: the presenter calls it on
every focus move, so any focusable inside any `ScrollView` scrolls into view on
keyboard and gamepad navigation with no control wiring, no `present()` opts, and
no per-control scroll arithmetic. A control with its own windowing still gets
its `focusMoved` contribution call afterwards.

### `Anchor`

`UI.Anchor{ id?, width?, height?, overflow?, children? }` — free-position
container: each child declares `anchor` ("topLeft" … "bottomRight"),
`offsetX`, `offsetY`. Offsets may be reactive (arrange-only updates — this is
how `VirtualList` scrolls with rect writes only).

**Fractional offsets — the marker-overlay shape.** An offset may be a share of
this anchor's inner box instead of a pixel count: `offsetX = { scale = 0.35 }`
places the child 35 % across, and `{ scale = 0.35, offset = -6 }` adds a pixel
adjustment (its `offset` may itself be a theme metric name). The fraction is spent
at **arrange**, against the anchor's inner extent, so a keyed `ForEach` of
anchored children whose `u`/`v` signals move is the minimap-dot / name-tag idiom:
a dot update is an arrange pass and a rect write — never a re-measure, never a
remount, so nothing blinks. Fractional offsets re-resolve on a viewport change
like every other layout input. Marker layers are **display-only by contract**:
they sit below the effective-target floor on purpose, so a tappable marker needs
its own floored control.

### `AdaptiveStack`

`UI.AdaptiveStack{ id?, axis, gap?, align?, distribute?, padding?, surface?, children? }` — a
stack whose **`axis` is a reactive prop**. Bind it and a viewport, orientation, or
display-class change re-solves the stack in place:

```luau
-- `conditions` builds eighteen formulas. Build it inside the component so the
-- component's Compose owner releases them with the screen.
local conditions = Facet.adaptive.conditions(app.environment)
UI.AdaptiveStack { id = "Toolbar", axis = conditions.axis, gap = 8, UI.Text { text = "Tools" } }
```

Why this is a distinct class rather than a recipe: swapping `UI.VStack` for
`UI.HStack` through a `UI.When` is a STRUCTURAL change, so every child unmounts and
remounts and loses its state, focus, and scroll position on a phone rotation. One
class with a bound axis makes the flip a re-solve — the specs assert zero factory
reruns, zero creates, and zero removes across an axis change. `gap` is reactive for
the same reason, so spacing can adapt without a rebuild.

`axis` is `"y"` or `"x"` and is **required**; anything else fails at construction.
A class named for adapting must not be able to not adapt, so an absent `axis` is a
construction refusal that names the fact, the host that publishes it, and the way
out. An unconditional column is `UI.VStack`; an unconditional row is `UI.HStack`.
`distribute` is the same main-axis distribution `VStack` / `HStack` carry, and it
follows the axis: the leftover it spreads is always the leftover on whichever
axis is live.

### `ViewThatFits`

`UI.ViewThatFits{ id?, children (required) }` — tries its children as candidate
layouts in **declared preference order** and shows the first that fits, using the
real measurement contract against the space *this container* actually received.
The last candidate is the fallback when none fits.

```lua
UI.ViewThatFits{ id = "Actions", children = {
    UI.HStack{ id = "Row", gap = 8, children = { save, cancel, help } },  -- preferred
    UI.VStack{ id = "Column", gap = 4, children = { save, cancel, help } }, -- fallback
} }
```

There is deliberately **no** prop to configure the choice: a declared minimum width
is a second source of truth the author has to keep in sync with the content, and the
solver already knows what each candidate measures.

**A candidate is judged at the size it would like, not at the size it could be
squeezed into.** The choice reads each candidate's IDEAL size — what it
measures when nothing is proposed to it — so shrink terms are invisible to the
choice. Facet's members of that family are `shrinkWeight` **and `hug`**: a
candidate that only fits *after* being squeezed does not fit. Once a candidate has
won it is laid out against the real offer and shrinks normally. Picking is
unshrunk; showing is not: a candidate is judged at its ideal size.

**`hug` on a candidate is legal and honest** (2026-08-22). `hug`
means "the content size, capped at the offer", and that cap is a squeezing term
like any other: it made a hug candidate's measured width equal the offer at every
width, so `w <= availW` was always true, the first rung won forever, and the labels
the ladder exists to protect truncated anyway. `hug` is the instinctive spelling —
four consumer files independently learned this and defended against it in prose,
one of them naming it *"the p4_foyer trap"* — so it is fixed rather than refused:
the probe resolves `hug` as `content`, the author's own `min`/`max` still bind
(a declaration is not a shortage), and the WINNER is capped by its offer exactly as
before. `hug` and `content` now choose the same rung at every width
(`tests/fits_ideal_size.spec.luau` sweeps both side by side).

Two properties make it safe:

- **Every candidate stays mounted.** A resize re-chooses without rebuilding, so a
  live rotation does not throw away scroll positions or in-flight state.
- **Losing candidates are excluded from focus order.** They keep their mount but get
  a zero rect and are marked hidden, and the presenter filters them out — so keyboard
  and gamepad navigation can never land on a control the player cannot see. This is
  the reachability half; a hidden-but-focusable node would be exactly the silent
  wrong result the strict-authoring work removed. The exclusion holds on **both**
  focus paths — the flat ring and every grouped scope (a contribution's
  `focusGroups`, the auto/layout derivations, and an explicit `navigationGroups`
  opt), for bare-path and live-predicate order entries alike. Candidates that are
  *stacks* (the row-vs-column action band) derive a grouped scope, and until
  2026-07-30 that path skipped the filter: a pad walked onto the hidden column and
  could not reach the visible row.

This is also the **container-relative** condition: `Facet.adaptive.conditions` is
viewport-relative, while this measures the container. When the answer you need is
a **value** rather than a subtree — reserve space in a sibling, place or skip a
minimap, choose between two *surfaces* before either is built — reach for
`Facet.adaptive.fitsIn` / `.fits`, which make the same comparison this ladder does.

### `Composition`

`UI.Composition{ id?, arrangements (required), groups (required), laneGap?, groupGap?, maxMeasure?, exclusions?, padding?, surface?, width?, height?, children (UI.Region…) }`
— the **screen-level** sibling of `AdaptiveStack` (which resolves one axis) and
`ViewThatFits` (which resolves one container's candidate). You declare *what the
screen has to say*, ranked, with a richest→minimum form list per region; the
framework decides *where*, from the box this container actually received, **on
both axes**.

```lua
UI.Composition{
    id = "Results",
    arrangements = { "threeLane", "twoLane", "column" }, -- richest first; last = fallback
    laneGap = "m", groupGap = "s",
    groups = {
        { id = "caption",  span = "above" },   -- its own full-width row, every arrangement
        { id = "ceremony", lane = "lead",  sizing = "hug",  place = "center" },
        { id = "field",    lane = "main",  sizing = "fill", minWidth = "metrics.results.fieldLaneMin" },
        { id = "next",     lane = "trail", sizing = "hug",  place = 0.66 },
    },
    children = {
        UI.Region{ id = "Recap", group = "caption", rank = 5, floor = { lines = 1 },
                   recover = "overflow", children = { twoLineTally, oneLineTally } },
        UI.Region{ id = "Hero",  group = "ceremony", rank = 3, floor = { lines = 1 },
                   recover = "none", children = { fullPlate, oneLineChip } },
        UI.Region{ id = "Field", group = "field", rank = 2, sizing = "fill",
                   mayScroll = true, floor = { lines = 1 }, children = { theList } },
        UI.Region{ id = "Ctas",  group = "next", rank = 1, floor = { targets = 2 },
                   recover = "none", children = { ctaRow, ctaColumn } },
        UI.Region{ id = "Tease", group = "next", rank = 9, mayDrop = true,
                   recover = "overflow", children = { twoLine, oneLine } },
    },
}
```

- **`exclusions`** — `Readable<{ Rect }>` (or a plain list): the rects the
  **host's own chrome** occupies, in **WINDOW space** — the space
  `platformChrome.rects` and the solver's own output rects are stated in, so a
  caller never converts and never needs to know where its composition landed. A
  solved lane starts **below** any of them its own regions share an x range with;
  a lane whose content clears them stays **level** with the chrome. This is what
  makes the lane band stop being one rectangle: a chrome row covering some
  columns and not others can be reserved around per column. The decision reads
  the **richest** forms' measured widths and is taken once per resolve — the
  reservation is the lane's own starting edge, not a region the ladder can drop —
  so a settled tree equals a fresh mount by construction. Declaring none is
  byte-identical to a composition that never heard of them.

  A lane that gives way is **shorter by exactly what it gave, at both ends**, and
  the precise statement is that it **places its groups exactly as an unshortened
  lane of the same height would** — every `place`, every `sizing`, offset by where
  the lane starts and by nothing else. So the last `place = "end"` group in a lane
  (`bottomLeft` · `bottom` · `bottomRight`) sits against the **shortened** lane's
  bottom edge, a `sizing = "fill"` group divides the **shortened** lane's height,
  and the composition's partition still holds with a chrome row declared.

- **`arrangements`** — ordered candidates, richest first. A preset name
  (`"threeLane"` · `"twoLane"` · `"column"`) or a table
  `{ name = "…", lanes = { { "lead" }, { "main", "trail" } } }`. An *arrangement*
  is an ordered list of **lanes**; a lane is an ordered list of the lane
  affinities it absorbs, sits beside its neighbours, and stacks its groups down.
  The **last** candidate is the declared fallback when none is legal (the same
  contract `ViewThatFits` makes about its last candidate) and the resolution
  reports `fallback = true` plus a solver finding marked `designed = true` —
  the composition saying which rung it landed on, not a defect
  (see [Findings that are not defects](#findings-that-are-not-defects)).
- **`groups`** — `{ id, lane | span, sizing = "hug"|"fill", weight?, place, minWidth?, maxWidth?, gap? }`.
  `lane` is the affinity an arrangement's lanes absorb; `place` is `"start"` ·
  `"center"` · `"end"` or a fraction (the thumb-arc idiom is `0.66`); `minWidth`
  is a px number **or a theme metric name**, resolved every solve, and a `fill`
  lane below it makes that arrangement illegal.
  **`maxWidth`** is `minWidth`'s twin and applies to a `fill` group only: a fill
  lane's width is a SHARE of the slack, so on a very wide offer it is simply
  whatever is left. `maxWidth` caps that share — the MEASURE, as distinct from
  `maxMeasure`, which caps the whole box and lets every lane divide what is left.
  What the cap frees is offered to the other fill lanes, and what none of them
  takes centres the band rather than being spent on width.
  **It defaults at ten-foot**, and the default is derived rather than chosen:
  `adaptive.LANE_MEASURE x metricScale` = **600 x 1.5 = 900**, the regular-touch
  tablet measure times the ten-foot ladder's one distance factor. Before it, a television
  resolved the DESKTOP answer with more pixels — the same arrangement with the
  content lane simply wider (1316px measured), which at three metres is a reading
  line nobody can track back to its own start (B-6e, controller ruling R14).
  Authored wins in both spellings: declare `maxWidth` here, or `maxMeasure` on the
  composition, and no default is set beside it.
- **`span = "above" | "below"`** — the group is **not in the lane vocabulary at
  all**: it is its own row, the composition's **full width**, in that position
  relative to the band of lanes, **in every arrangement**. That is what a
  masthead, a caption or a footer band is, and it is why a span has no affinity —
  requiring every arrangement to find it a lane is exactly how a spanning band
  ends up in a column on the one device you did not test. Declaration order
  orders the rows on each side; the vertical gap between rows is `groupGap`. A
  span row **hugs its content** and takes no slack (rule 6 keeps that for the
  lane band), so `sizing = "fill"`, `place`, `weight` and `minWidth` are refused
  on one — a span is already full width and already its content's own height.
  Everything else about it is a group: its regions stack, step down and drop by
  rank, and an **empty span row is absent and costs nothing**. Height comes out
  of the *same* budget the lanes share, so a spanning region is a step-down/drop
  candidate whenever a lane overflows (it relieves every lane at once) and never
  on a width failure (it cannot narrow anything).
- **`laneGap`** / **`groupGap`** — spacing between lanes, and between the groups
  stacked inside one lane. **`maxMeasure`** caps *both* axes of the box the
  composition resolves in and centres the result.

**The nine rules, in the order they apply.** (1) arrangements are tried in
declared order; (2) an arrangement whose hug lanes overflow the width, or whose
`fill` lane falls under its `minWidth`, is illegal; (3) inside an arrangement,
regions **step down** to their next form before anything is **dropped**, both in
**descending rank** (least important first, ties by declaration order) and only
among regions that can actually relieve the failure — a region that is not what
its lane's width is made of gives up nothing, and neither does anything in a lane
whose width is **pinned** by a region that cannot narrow (its last form, and not
droppable) or by a group `minWidth`, because that lane cannot come down at all;
(4) nothing is squeezed — a
region is dropped, never shrunk past its floor; (5) an arrangement that still
does not fit after every step-down and every legal drop is illegal and the next
is tried — which is also how "exactly one scroll" holds, since no region ever
becomes a scroller implicitly; (6) slack flows to `fill`, on both axes; (7) a
`reserved` region holds its box **while its schedule is running** — the guarantee
is mid-sequence stability (nothing jumps between two pieces of one sequence), not
a permanent claim, so a `reserved` that reads `false` leaves the region as empty
as any other; (8) no legal candidate ⇒ the last one, declared; (9) **empty-lane
release** — a lane whose every region resolves to nothing paintable (empty,
at-rest-invisible, or dropped) **collapses**: it takes no width and no lane gap,
and what it would have held goes to the `fill` lanes by rule 6's weights (with no
`fill` lane the composition simply measures narrower). The lane is still reported,
with `collapsed = true` and a zero-width rect at the x it would have started at.

**Re-solve, never rebuild.** An arrangement change is an arrange pass: every form
of every region stays mounted, so a rotation, a resize, a preferred-text change
and a theme swap all keep scroll offsets, focus and in-flight transitions. Forms
that lost, and regions that dropped, keep their mount but get a zero rect and the
`hidden` mark — which is what removes them from focus order, on both the flat ring
and every grouped scope. **Focus order is the declaration's own order**, and is
therefore identical in every arrangement.

**Diagnosability.** The resolution is published on the solved node and carried by
the layout dump as `facet-composition-dump/1`: which arrangement won, which form
and rect every region resolved to, which regions dropped, the **spanning rows**
(`spans = { { id, side, rect } }`, empty when none is declared), every lane's
**`collapsed`** flag (rule 9 — an omitted lane is reported with
`collapsed = true`, a drawn one with `collapsed = false`) and — for every richer
candidate — the **rule it broke** and the measured detail (`laneWidth`,
`overflow`). Read it live with `controller.compositionAt(path)`. In the mounted
dump a region is addressed by its **node path** (`/Screen/Results/Field`), exactly
like every rect key and every hidden root; the declared id is its last segment.
The same decision is callable with no tree at all through `Facet.composition`,
where a region id is simply whatever the caller passed.

### `Region`

`UI.Region{ id (required), group (required), rank (required), recover (required with 2+ forms), expand?, dismissButton?, floor?, sizing?, weight?, mayScroll?, mayDrop?, reserved?, children (required) }`
— one ranked thing a `Composition` has to say. **Its children are its forms**,
richest first; the last is its minimum-viable form. Exactly one is shown.

| Prop | Meaning |
|---|---|
| `group` | the group it travels with (a group is the unit a lane holds) |
| `rank` | adaptation priority, 1 = most important. Step-down and drop go **descending** rank; ties break by declaration order, so every device is predictable from the table alone. `rank` is *not* reading order — regions are declared in reading order |
| `floor` | the minimum content it must be able to show: `{ lines = n, role? }` and/or `{ targets = n }`, resolved against the live theme so a bigger type scale raises the floor by itself. **Never a pixel count.** Absent, the floor is the minimum-viable form's own measure |
| `sizing` | `"hug"` (default) or `"fill"` — a `fill` region takes the slack above its floor. The one region that grows |
| `weight` | share of that slack when several regions in a group fill (default 1) |
| `mayScroll` | this is *the* scroll region. **At most one per composition**; a second is refused at construction |
| `mayDrop` | it may be removed entirely when stepping down is not enough (default `false`) |
| `recover` | **where the content a reduced form stops showing went.** `"none"` (every form below the richest still shows everything — a poorer *layout*, not less content) \| `"self"` (the reduced form **is** the route: the player taps what is left to get the rest) \| `"overflow"` (the screen's overflow surface is the route, and it reads `resolution.unshown`). **Required** with more than one form and **refused** with one: a one-form region can only stop showing content by being *dropped*, and a dropped region has no form left to be its own route, so the sink is the only possible answer — `mayDrop` is already that declaration. `"none"` together with `mayDrop` is refused for the same reason: dropping shows nothing |
| `expand` | **how a stepped-down region discloses its richest form.** `"auto"` (default) — the framework presents form 1 in a transient plate at this region's own anchor, opened by the **whole compact form** when that form carries no control of its own, or by a **chevron beside it** when it does (see the note below) \| `"none"` — the authored escape (nothing to disclose, or you are disclosing it yourself) \| a **function**, which replaces the presentation entirely. **Refused on a one-form region**: a region with one form never simplifies, and that is also the answer to "how do I stop this region collapsing" — give it one form. Silence means `"auto"` except under `recover = "none"`, which has already stated that nothing is missing |
| `reserved` | hold its box while its content rests **between pieces**, so a finishing transient never moves its neighbours. `true` reserves for the surface's whole life; **a `Readable<boolean>`** — the only reactive prop on a `Region` — reserves only while it reads true ("this schedule can still produce a piece") and releases the box, and with it the lane (rule 9), when it reads false. Mutually exclusive with `mayDrop` |

`dismissButton = "always"` (default) retains the corner Close button.
`"automatic"` uses the same inline Collapse affordance as CollapsibleView, shown
only during keyboard/gamepad navigation. Pointer/touch users dismiss outside;
switching to navigation reveals a reachable exit. This preference requires an
expandable region. Region disclosures overlap the compact region and clamp to
the safe area instead of opening below it.

**The expand, in one paragraph.** A region standing on a form below its richest is
showing less than it has, and `expand` is how the player asks for the rest without
leaving the screen. The framework appends **one** button to such a region — the last
child, so its focus stop lands after the form's own stops in document order — and
the solver stands it up only while a reduced form is standing. Its shape is decided
at construction, from what the forms CONTAIN:

* **cover** — no form below the richest carries a focus stop or a semantic action,
  so the whole compact form is the target: one focusable, a tap or `A` anywhere on
  it, the standard target floor over the whole of it, and **no painted mark at
  all**. A passive pill is not an affordance wearing an arrow; it is the
  affordance.
* **chevron** — some form below the richest does carry one. Its meanings are left
  alone and the affordance becomes a mark BESIDE it, in width the form's own
  measure reserves. The arrow exists exactly for that disambiguation: something
  actionable by itself must not also be the thing you action to expand. Mixed
  ladders take the chevron.

**The framework puts nothing of its own above your content**, and the cover obeys
that rule rather than being an exception to it: it is declared with `zIndex = -1`,
so it and the hit expander banded below it paint UNDER every form. A device round
bought that rule (2026-08-21: a cover laid OVER the compact form rendered three
stepped-down zones as empty pills, with every headless instrument green), and a
cover is only ever synthesized where nothing above it is interactive — so the
gesture still arrives at it. `formInteractive` is reported beside the role, because
whether the player has two things to press in that box is worth knowing. The plate's width is the composition's
own (`plate.w` on the resolution), and it is measured against the allowance MINUS the
plate's own chrome rather than against the allowance itself: the panel you get is the
form plus two uniform insets plus the corner disc's straddle, so the cap the form is
offered has all three taken out of it first (`plate.max` reports the widest the plate
BOX may be, which is the viewport minus its gutters minus that straddle). **There are
therefore TWO ways to land on the full-width sheet**, and the second one is easy to
miss when you are tuning a form against a viewport: the richest form cannot meet its
floor in a plate, OR the richest form is wider than the allowance once the plate's
chrome is reserved — a form that would just fit the raw allowance is a sheet, because
the panel wrapping it would not. Before 2026-08-21 that second case mounted an anchored
panel wider than the allowance it had just been chosen against. Dismissal is the
presented surface's: a tap outside, the plate's own **Close** control (the corner disc
described below, whose accessibility name stays the word "Close"), and gamepad B —
and the plate closes itself when the rect it was opened against moves, resizes or goes
(a rotation, a viewport change, a theme-metric change, or a re-solve that put the region
back on its richest form). **Escape is not one of the routes and cannot be**: it is
permanently bound to the Roblox CoreGui menu and the engine refuses the binding, which is exactly why the framework puts a Close control
in the panel — the plate is a modal, so its own ring is the whole keyboard story. It is a
**circular icon button CENTRED ON the plate's top-right corner, half on and half off it**.
The plate's padding is uniform — one spacing token on all four sides, so your content sits
centred in its own frame and nothing in its flow is reserved for the close — and the disc's
straddle is derived from the disc itself (its own inset plus half the disc), which puts its
centre exactly on the corner at every theme ladder. **The inset is `controls.focusRing.inset`**
— `max(space.xs, controls.focusRing.thickness)`, resolved from the theme snapshot at both
display classes, not a bare `space.xs`: the room the close's own ring draws in always clears
the ring's actual thickness (`controls.focusRing.thickness`, a live theme-metric mirror of
`style.extra.focusRingThickness`/`tenFootFocusRingThickness` — the same number
`screen_target` paints, so a metric-vocabulary reader and the engine's own paint always
agree), even on a package whose own `space.xs` would otherwise fall short at ten-foot.
Framework chrome therefore sits on the plate's padding
and never over your content: the disc reaches `disc/2` inward from the corner while your
content box's nearest point is `padding x sqrt(2)` away, so the guarantee a theme package has
to keep is `controlSizes.compact.height <= 2 x sqrt(2) x space.m` (36 <= 45.2 by default), and
the build asserts it for every shipped package. The straddle is a margin on the plate rather
than an offset on the disc — the panel's box therefore CONTAINS the disc, which is what keeps
the anchored placement's safe-area clamp able to see it, and the plate itself is capped at the
allowance the composition measured it against, so the panel can never paint past the gutter. It is the panel's LAST
child, so the presenter's existing rule (a modal focuses its first focusable) lands on the
content's own control when form 1 has one and on the way out when it does not.

**A form's minimum must carry the region's essential value.** The expand is for the
REST. A ladder whose last rung drops the number the player actually needs has moved
a defect behind a tap, and no disclosure repairs that — the value-text sweep polices
the painted half, and this is the authoring half of the same rule.

A region whose chosen form measures nothing is **not mounted** and costs no gap —
"empty ⇒ absent" is mechanical, so a composition cannot have a dead band. A
`reserved` region is the exception *while it is reserving*: its box never falls
below its floor. Releasing the flag is only half of it — **a form that paints a
fixed box unconditionally is never empty**, so a slot that must be able to
disappear puts its box behind the same `When` its flag reads.

Every other `Region` prop is deliberately **not** reactive: they answer *what this
region is*, a fact about the screen the solver would otherwise have two sources
for. `reserved` answers *is its schedule still running* — a fact about time that
only the caller holds — which is why it is the one exception.

**Adaptation may change how much of something is shown, and what it costs to
reach it. It may not change whether it can be reached at all.** That is what
`recover` exists for, and why silence is not consent: the rank ladder steps a
region down and then drops it exactly as told, and before this contract it had no
notion of where the content went — so "step down" and "delete" were the same
operation from the player's side. A `recover = "self"` route is checked at
construction against **every** form below the richest (the ladder can stop at any
rung): a form with nothing focusable in it is an authoring error, because a route
nobody can reach is the defect wearing the fix's clothes. **That check now fires only
under `expand = "none"`** — with an expand, the framework's own affordance is the
route, and it is a Button standing exactly while a reduced form is.

Declaration errors are refused at **construction**: an unknown field, a second
`mayScroll`, `reserved` with `mayDrop`, a missing or refused `recover`, a
`"self"` route whose reduced form holds nothing focusable, a rank that is not a
positive integer, a
region with no forms, a duplicate id, a group with no home in some arrangement, an
unknown arrangement name, a `floor` that states neither `lines` nor `targets`.

### `Divider`

`UI.Divider{ id?, axis?, thickness?, appearance?, width?, height? }` — an axis-aware hairline.
It **infers its orientation from the enclosing stack**, so one declaration reads
correctly in both: inside a `VStack` it is a horizontal line spanning the cross
axis, and inside an `HStack` a vertical one. Inside an `AdaptiveStack` it follows
the axis flip with no rebuild.

`axis` names the stack axis the divider separates ALONG (`"y"` → horizontal line,
`"x"` → vertical), and overrides the inference when given. Explicit `width`/`height`
win over both.

**`thickness` defaults to the theme's own hairline weight** —
`strokes.hairline` from the live snapshot, not a literal 1 px — so a package with
a heavier rule line moves every divider with nothing to update. Authored, it
takes a px number **or a theme metric name** (`"strokes.hairline"`, `"s"`, any
dotted snapshot path): it is a theme-owned number, so it accepts the theme's own
vocabulary, resolved on every solve.

The hairline is **style-owned**: under native styling it carries the `facet-divider`
tag and the sheet's "Divider" rule paints it, so a designer can restyle every
separator in the place from one rule. On the fallback path the adapter writes the
hairline colour directly. It is never an unpainted `Frame` — an invisible divider is
exactly the accepted-and-ignored failure the strict-authoring work removed.

Both paths paint it **at the theme's `hairlineOpacity`**, the same wash every
`UIStroke` hairline in the sheet spends — so a divider reads as a rule over the
surface it sits on rather than as a bar of the raw hairline colour, and a package
that wants a bolder separator authors one number for its strokes and its dividers
together. The player's background-transparency preference does not move it: a
divider is a border, and borders are outside that preference's scope.

**`appearance = "strong"`** (bindable; default `"standard"`) paints a heavier rule —
a pane edge rather than a row separator — at the theme's `extra.strongHairlineOpacity`
(unset: three times as visible as the hairline). It is a style tag like the rest of
the divider's paint, so it needs native styling to show.

### `Grid`

`UI.Grid{ id?, flow?, columns? | minColumnWidth?, itemSizing?, gap?, rowGap?, padding?, surface?, children? }`
— a wrapping grid: children fill a fixed `columns` count, or a count derived
from `minColumnWidth` against the available extent. `gap` spaces cells on both
axes. Use it for uniform tiled layouts (icon grids, match-3 boards) where a
stack's single axis is not enough.

**Declaring neither is `minColumnWidth = "intrinsic"`**: a grid told nothing lanes
itself from the box it was actually offered, using the widest child's own measured
extent as the lane minimum. The default reaches `adaptive.columnsFor` through the same line
the declared route reaches it through, so the ten-foot cap rides along and a
1920px television gets FEWER lanes than a 1600px desktop. Authored always wins,
both keys. A grid of only `fill` children has no intrinsic minimum to take and
still gets one lane.

`flow` is `"row"` (the default: cells wrap across the WIDTH and the lines advance
DOWN — what this grid has always done) or `"column"` (cells wrap down the HEIGHT
and the lines advance RIGHTWARD). It is CSS's `grid-auto-flow`, and it is one
mode of one arithmetic rather than a second layout: a column-flow grid is the
exact transpose of the row-flow grid it mirrors — turn the box on its side,
exchange each child's two axes, and every rect comes back with x/y and w/h
swapped (`tests/grid_column_flow.spec.luau`). It is also what a horizontal lazy
grid's mounted band is built from (`UI.VirtualGrid { axis = "x" }`).

`columns` and `minColumnWidth` keep their names in both directions, because the
grid has ONE lane count and ONE lane minimum — under `flow = "column"` they are
read against the HEIGHT (`columns = 3` is three rows; `minColumnWidth = 60` is
"no lane shorter than 60px"). Two symmetric spellings would double this prop set
to describe the same two numbers. `flow` is refused on a **row grid** (one whose
children are `UI.GridRow`) with a diagnostic: there the columns are derived from
every row at once and have no transposed reading.

`rowGap` overrides the VERTICAL spacing alone and defaults to `gap`, so a grid
that does not ask for it is unchanged. Reach for it when the two axes are not
comparable: a grid's column pitch is `innerWidth / columns`, so raising `gap` to
open the rows also moves the cells inside their columns and — through
`minColumnWidth` — can re-column the whole grid. `rowGap` never enters the column
arithmetic. Like `gap` it takes a px number or a spacing-step name, so it moves
with the installed theme package.

`minColumnWidth` takes a px number **or the string `"intrinsic"`**, which means
"no column narrower than the widest child measures". Prefer `"intrinsic"` for a
grid of LABELS: a px literal is a guess about a font, so the same declaration
over-wraps under a small type ladder and clips under a wide display face. The
intrinsic width is re-measured on every solve, so a theme swap re-columns the
grid with nothing to update.

Inside a CONTENT-SIZED parent, a `minColumnWidth` grid reports at least the width
its columns need — `columns × minColumnWidth` plus the gaps between them — even
when the cells themselves are narrower. That is what keeps the column count
stable: a hug parent hands the reported width straight back as the layout width,
and a narrower report would re-column the grid into more rows than it measured.

`itemSizing` is `"natural"` (the default: every cell sizes to its own content)
or `"uniform"`. `"uniform"` measures every child, takes the **max** measured cell
size across all of them and gives that size to every cell — a set of ragged
variable-width plates becomes a clean grid, and a wider theme font grows all of
them together on the next solve. It is opt-in: nothing changes for a grid that
does not ask, and `natural` is what every existing layout was authored against.
Pair it with `minColumnWidth = "intrinsic"` when the cells are labels.

A cell that declares `fill` on the grid's **flow** axis (the height under
`flow = "row"`, the width under `flow = "column"`) takes its whole line, and the
line takes the grid's own spare extent on that axis — the space the grid was
*given* over the space its content *asked for*, split evenly across the lines
that contain such a cell. So a run of `fill`-on-both-axes marks inside a grid
that has been handed a height paints at that height, exactly as the same
declaration does under a stack; a line with no such cell keeps its content
extent, and nothing here moves what a grid REPORTS (a `fill` cell contributes its
content at measure, so a content-sized parent still hugs). Without this, a line
whose every cell fills has no content to be derived from and every cell in it is
zero-height — a rectangle with a width and no area, which paints nothing at all.

On a D-pad, a grid navigates as rows and columns, and Up from its first row or
Down from its last row leaves for the focus group beside it in document order.
That neighbour can be a derived row, the last or first row of an adjacent grid,
or a control's own focus group when that control contributes exactly one (a
TextInput, a range Slider, a VirtualList, a Chip row, a DateTimePicker's time
fields). The exit names that particular control, so two fields that share an
id on one page are never confused. A control that contributes several groups
is not linked, and an authored `exit` is never overwritten.

### `GridRow`

`UI.GridRow{ id?, surface?, shadow?, gradient?, corners?, stroke?, zIndex?, children? }`
— one row of a **row grid**. A `UI.Grid` whose children are all `UI.GridRow`
switches to row mode: column *n* is as wide as the widest natural cell in column
*n* across every row, rather than the one shared width the flow grid gives every
column. A `Grid` with no `GridRow` child is the flow grid it has always been, so
nothing an existing caller wrote changes.

**The mode is decided by the children, never by a prop.** A grid whose children
are a MIX of rows and loose cells has no reading that is not a guess, so it stays
the flow grid it was and files a diagnostic on `controller.diagnostics()` naming
both ways out.

**Its prop set is deliberately tiny, and the omissions are the design.** A
`width` or `height` on a row would be a second authority against the grid that
owns the column widths and the row pitch, and `padding` would inset one row's
cells out of the columns every other row is aligned to — which is the whole point
of a row grid. So they are not accepted and quietly ignored; they are
construction errors naming the fix. What is here is the set that is meaningful on
a full-width band: its identity, its children, and the paint a striped or carded
row wants.

**`gridSpan` on a cell**: how many of its row's columns that cell covers (default
1). A spanning cell contributes to **no** single column's maximum, so a span
cannot widen one column on its own — and is then fitted to the
sum of the columns it covers plus the gaps between them. Naturals that do not fit
are reduced **proportionally** rather than overflowing, because the flow grid
cannot overflow (its column width is derived from the offer) and a row grid under
the same name must not either.

A row grid also feeds the focus map: the D-pad walks the rows you declared. (A
grid without `GridRow` children keeps inferring its rows from `columns`.)

### `Text`

`UI.Text{ id?, text (required), textSize?, textAlign?, lineLimit?, truncate?, rich?, direction?, disclose?, reveal?, help?, role?, surface?, over?, tint?, width?, height? }`
— text label. `text`/`textSize` changes invalidate measurement; text metrics come
from a non-yielding provider with conservative fallbacks for unknown
fonts/scripts. `textSize` takes a px number or a typography role name, which
also supplies the font descriptor and line height the measurer uses — and the
same descriptor the ADAPTER paints, which is why weight is a role
(`"strong"`, `"numeral"`) and not a prop. `role`
selects the text style role (color and weight resolve from the active style /
native StyleSheet): `"secondary"` is the receded treatment and `"content"` the
resting default. **`"content"` exists so a REACTIVE `role` can return.** A label
that recedes and comes back — a list row leaving a disabled state — binds `role`,
and a binding can only resolve to a *value*: `nil` drops the prop rather than
writing the default, so without a word for "resting" the round trip was one-way
(both adapters now write both directions).

**`lineLimit`** caps how many lines this label may occupy (a px number or a
theme metric name, minimum 1). Beyond the cap the
engine ellipsizes — `TextTruncate.AtEnd` is set on every text node — instead of
the box growing. Absent, a label is uncapped and takes as many lines as its
string needs.

Reach for it whenever a label sits in a box of a **known, fixed height**: a table
row, a list cell, a badge. Without it the measurer reserves the label's natural
wrapped height, the renderer paints a box that tall, and nothing clips — so a
three-line name inside a two-line row paints straight through its neighbours
(the defect a device pass found in the playlist table, 2026-07-27). `UI.Table`
now derives this for its own cells from the row height, so a table consumer never
sets it by hand.

This is a different question from the framework's internal word/phrase rule: that
one is derived from the **string** (a single word has no legal break, so it is
measured and drawn on one line), while `lineLimit` is the **owner's** knowledge of
the space available. They compose — a capped phrase still wraps, up to the cap.

**`disclose`** (boolean, construction-only) declares this label as **bounded
secondary or identity text whose full value must stay reachable**. Truncation is
only permitted for such text, and only with a way back to the whole string: set
`disclose = true` and, when the label actually truncates, engaging it presents the
full value — hover dwell on pointer, focus on the containing focusable for
keyboard/gamepad, long-press on touch — through the presenter's static plate (see
**Full-value disclosure** under [`app.presenter`](#apppresenter)). It does nothing while the text fits,
so declaring it costs nothing; **omitting** it on text that truncates is what the
text audit reports as a clipped-essential finding. Binding a Readable here is
refused with the rebuild idiom, exactly like `traversalPriority`.

**`help`** (a string, or the table `{ title?, body, shortcut?, edge?, align? }`;
construction-only) is one sentence about what this view DOES, **pulled by the
player**: a pointer resting on it for
a dwell, or the keyboard/gamepad ring landing on it. See **Help** under
[`app.presenter`](#apppresenter) for the whole contract — including the part that is easy to get
wrong. **On touch, nothing appears, and that is the specification.** No
gesture is bound to help on any input class: touch long-press
belongs to the full-value disclosure plate, which is the only touch route to a
truncated label's own value. The consequence is a rule — `help` is never the only
route to something a player needs — and `text_audit.helpRoutes` is the check that
enforces it. The plate points at the view it describes with D1's **arrow tail**
(director, device review 2026-08-16), suppressed when the placement carried the
plate off its source. For an app-PUSHED plate that DOES appear on every input
class and retires permanently, see [`UI.Callout`](#uicallout).

**`reveal`** (`"auto"`, construction-only; director ruling 2026-08-04, superseding
LTN-2's "no marquee" for surfaces that declare it) makes a truncated **one-line**
label auto-scroll its whole value instead of resting behind the ellipsis alone.
The presenter owns the cycle (see **The auto reveal** under [`app.presenter`](#apppresenter)): a
quiet delay in the engine's own ellipsis, then the full string slides through the
box as one strip — out to the tail, a pause, and back to rest. A reveal node is
**also a disclosure source** (the static plate is its declared full-value
alternative), reduced motion disables the travel entirely, at most one strip runs
across the whole presentation (`presenter.movingText()` feeds
`text_audit.movingText`, allowance 1), and the facts channel reports
`policy = "truncate+reveal"` plus `naturalWidth` (the travel distance's other
half). `"auto"` is the only value today — it names the *unengaged* variant the
ruling ordered, for a non-interactive span nothing can hover or focus
deliberately; an engaged variant remains a possible future value. Inert while the
text fits, exactly like `disclose`.

**`surface` on a Text is `"badge"` or `"chip"` — and only those two.** Box and
Image take the full nine-surface vocabulary; a Text takes the two that are
read-only by nature:

| Value | What it is |
|---|---|
| `"badge"` | the counter seal — a circular plate behind a short value. This is the public authoring path for the `badge` decoration slot, so an ornate theme's seal art lands here and the count is lifted above it and centred ([guide §9.4](../guide/09-custom-themes.md)). |
| `"chip"` | a read-only tag / pill / status label. |

The other six are **rejected at construction**, naming the allowed set. A Text is
not interactive: `control` and `accent` are affordances (`accent` is the
primary-action treatment), so wearing one makes a label look pressable when it is
not; `raised` is the panel treatment, and a label on a card is a `UI.Box` *with* a
Text inside it, so the panel's content insets have somewhere to go; `base` and
`scrim` are backdrops; `plain` is already what a Text with no surface is. Wrap the
label in a `UI.Box` when you genuinely want one of those.

Set `textAlign = "center"` alongside `surface = "badge"`: the *skinned* lift
centres a badge's value for you, but a flat theme draws the label's own text with
the alignment you asked for, which defaults to start.

**A `badge` (on `Text`, `Image`, or a `Box`/`ZStack` wearing it) has an intrinsic
minimum** when you declare neither `width` nor `height`: it floors to the theme's
`controls.badge.minimum` (20px at Facet Neutral, ten-foot-scaling like every
other `controls.*` metric) on both axes, so a one-digit count never draws as a
bare glyph hugging its own pixels. Declare either dim yourself and it wins — the
floor only reaches an undimensioned badge.

**`over = "media"`** is a construction-only contrast treatment for text on an image
or video. It uses the existing native style classification and the theme's
strong surface/content pair. Other words and bound values are refused.

**`tint`** is the continuous-colour channel (see [above](#continuous-colour-tint));
on a Text it claims `TextColor3`. `role` remains the way to say "secondary" — a
tint is for a colour a role cannot name, and it leaves `TextTransparency` alone so
the disabled state still dims.

**`truncate`** decides *where* an over-long value is cut: `"end"` (the default,
the engine's own end ellipsis, which is what every label has always done) or
`"middle"`, which keeps the head **and** the tail — `"Coastal circui…lap 14"`.
Reach for middle truncation when the ending is what identifies the value: a track
name with a variant suffix, a file path, an id. The engine has no such mode, so
this is a fit policy: the solver knows the width the label ended up with, the
library sizes a head + `…` + tail to exactly that width, and the result is
painted through the one text seam. The width it fits is the **drawable** one —
the box minus the label's own padding, which is what the glyphs actually get. It
is re-derived only when the string, the face, the size, that drawable width or
**the measurer's own answers** move (the last is the engine's boot window: a cut
taken before the text metrics settle is taken again once they do) — never per
frame.

Pair it with **`disclose`**: the node paints a shortened string, so the full value
has to stay reachable, and `disclose` is that route. `truncate = "middle"` needs
`lineLimit = 1` (a head-plus-tail form is one line by definition) and cannot be
combined with `rich = true` — a cut through the middle of markup falls inside a
tag. Both are spec errors.

The disclosure plate and the `reveal = "auto"` strip render a `rich` label's value
**as rich**, so the escape hatch shows the reader what the label showed rather than
its tags.

**`rich`** (construction-only, default false) parses the text as the engine's own
markup — `<b> <i> <u> <s> <font> <stroke> <br> <uc>/<uppercase> <sc>/<smallcaps>
<mark>` plus the five escapes `&lt; &gt; &amp; &quot; &apos;` and `<!-- -->`
comments. A `<font weight="…">` is understood in every spelling the engine
accepts — `heavy`, `Heavy` and `900` all name the same face.

Facet caps authored `<font size>` values at 100 before publishing rich text to
layout, native targets and disclosure/reveal surfaces. The bounds service caps
its measurements there even though native rich text can paint larger values.
The caller's string stays unchanged; plain text, sizes at or below 100, comments
and quoted non-size attributes retain their bytes. Malformed markup retains the
existing literal fallback. Text and runs share one layout parse; normalization
is a separate bounded pass when the authored text changes.

**The box is reserved for what the player SEES.** With `rich` on, the measurer
takes the *displayed* text — every well-formed tag removed, escapes decoded,
`<br/>` counted as a line break, `<uc>` content upper-cased — so a heavily
marked-up label reserves the same box as its plain equivalent instead of one wide
enough for the tags. Truncation, wrapping and the disclosure value all follow the
displayed form.

A tag Facet does not name is **removed too**, because the engine removes it:
measured live, `<blink>Lap record</blink>` renders as `Lap record`. **Malformed**
markup — a `<` that does not open a tag — is measured as the RAW string, because a
failed parse is what the engine draws.

**A face-changing span is measured at its own face**, which is the difference
between a correct box and a clipped label: measured live at 24 px, a rendered
`<b>` run is 3.5% wider than plain, `<font weight="heavy">` 6.6% and `<uc>` 16%,
and the engine's own bounds call reports the *plain* width for bold even with rich
text on. So the span's weight, face and size travel with the string to the
per-word measurement key.

**What is still approximate, and it can CLIP.** `<sc>`/`<smallcaps>` is measured
upper-cased, which is *wider* than the small capitals drawn (the box
over-reserves); a `<font>` that changes face and weight together takes the face's
regular weight; and nested spans take the innermost declaration only. Every
residual but the last over-reserves; a nested face-changing span inside another
one can under-reserve, and an under-reserved label is end-ellipsized by the engine
(`TextTruncate.AtEnd` is on for every text node). Keep spans flat in a box that is
tight.

**Escape anything you did not author.** `Facet.richText.escape(s)` escapes the
five characters the parser reads; call it on player names, server strings and
anything else composed into markup, or a value containing `<` either paints as a
tag or breaks the parse for the whole label. It is *not* a text filter — whether
a player may say a thing is the game's and the platform's decision.

```lua
UI.Text("Result")({
    rich = true,
    text = "Finished <b>1st</b> as " .. Facet.richText.escape(racerName),
})
```

**`direction`** maps to the engine's `TextDirection`: `"auto"` (derive it from
the characters), `"ltr"` or `"rtl"`. Absent leaves the engine's class default
standing, which is **not** the same as authoring `"auto"` — absent writes
nothing. Construction-only.

`color` and `font` are **diagnosed, not accepted** (see `DEPRECATIONS`).
Neither ever reached a render target: `color` was dropped entirely, and `font`
reached only the measure seam, so an authored font silently made measured and
painted bounds disagree. Both are style authority — use `role`.

### `Image`

`UI.Image{ id?, image?, surface?, tint?, shape?, scaleMode?, tileSize?, sliceCenter?, sliceScale?, resample?, imageFraming?, width?, height? }` — image
node; `image` is an asset string (pair with `newResourceProvider` for async
ready/pending/failed handling). `image` is optional so a node can mount empty and
receive content later — that is exactly what `UI.AsyncImage` binds.

**`shape`** defaults to `"rect"`. `"circle"` uses the shared 1:1 layout guarantee:
author at most one axis and the other follows, including bound, fill, and percent
dimensions. A second axis binding counts as authored even while its value is nil. With neither axis it uses the control height metric. The direct image
gets a true circular native corner, independent of the theme's pill radius, with
no implicit border or extra render buffer. `shape` is construction-only. The new
circle form refuses `imageFraming`, including a late bound value; the last valid
direct image remains until the binding recovers. Direct circles also refuse
`scaleMode = "slice"`: the engine fragments the nine-slice picture under that
corner. Use fit/crop/stretch/tile, or deliberately place a rectangular slice Image
inside a `shape = "circle", canvasGroup = true` ZStack, paying one render buffer
for the circular mask. Rectangular framing and nine-slice images are unchanged.

**`scaleMode`** decides how the picture fills the box the solver already sized —
`"fit"` (contain: the whole picture, letterboxed), `"fill"` / `"crop"` (cover:
aspect preserved, overflow cropped), `"stretch"` (ignore the aspect ratio, the
engine's own default), `"tile"` (repeat it) and `"slice"` (nine-slice it).
`fill` and `crop` are deliberate synonyms: Roblox's `Crop`
*is* the cover behaviour other vocabularies call fill, and neither audience should
have to look it up. `scaleMode` is style
authority and it claims `ScaleType` in native mode, exactly as `tint` claims a
colour.

**`tile` and `slice` carry their geometry in a companion key, and the pair is
checked both ways.** `"tile"` requires `tileSize = { width, height }` in **whole**
pixels greater than zero — the size one repeat is drawn at; whole, because the
engine's tile offset is an integer and truncates a fraction silently. `"slice"`
requires `sliceCenter = { x0, y0, x1, y1 }`, the stretchable centre **rectangle in
SOURCE pixels** — the engine's own `SliceCenter`, and the same name and shape a
theme package's own art declares. A 64×64 source with an 8px border is
`{ x0 = 8, y0 = 8, x1 = 56, y1 = 56 }`. These are rectangle **edges, never
insets**: turning "an 8px border" into a rectangle needs the source's pixel size,
which the engine resolves asynchronously after the content loads. `sliceScale`
(default 1, `> 0`) is how much the border run is scaled by, and is legal only with
the slice mode.

Declaring a geometry key without its mode, or a mode without its geometry, is a
spec error: a `tileSize` with no tile mode paints nothing, and a tile mode with no
`tileSize` falls back to one repeat across the whole box, which is `stretch`
wearing another name. The geometry keys are **construction-only**, so `"tile"` and
`"slice"` are authored as static words — a bound `scaleMode` that resolves to
either is refused at the binding write, with the reason, rather than painting a
mode with no geometry.

A **theme's** own nine-slice frames are unaffected and unrelated: those are the
adapter's chrome images, driven by a package's `sliceCenter`/`sliceScale`, and
they never meet a node's own `Image`. This key exists for CONTENT art — a
repeating background, a stretchable panel picture a screen supplies.

**`resample`** is `"default"` (the engine's smooth filter) or `"pixelated"`
(nearest neighbour). Reach for `"pixelated"` for pixel art, which otherwise
blurs at any size but 1:1. Reactive, like `scaleMode`.

```lua
UI.Image("Backdrop")({
    image = "rbxassetid://YOUR_GAME_ART",
    scaleMode = "tile",
    tileSize = { width = 32, height = 32 },
    resample = "pixelated",
})
```

`UI.AsyncImage` forwards all five picture keys verbatim.

**`imageFraming`** optionally replaces `scaleMode` with explicit source framing:
`{ width, height, mode?, focusX?, focusY?, scale? }`. `width` and `height` are
positive finite **decoded source image pixels**, independent of the view's layout
size. Use the served texture's dimensions, including any upload resizing.
`mode` defaults to `"crop"`; `"fill"` is its synonym, `"fit"` contains the image,
`"stretch"` fills both axes, and `"none"` preserves source pixel size.
`scale` is a positive multiplier (default 1) applied after that sizing policy.
`focusX`/`focusY` are normalized source coordinates in 0..1, default 0.5. The crop
centers on that point and clamps to image edges. If the picture is smaller than
the view, it is centered with space around it; it is never tiled. A whole framing
record may be a Readable; updates are paint-only. Setting it to nil restores the
ordinary image and its `scaleMode`. Unknown fields and invalid values are errors.

Use the existing background modifier for any view:

```lua
UI.background(content, UI.Image({
    id = "Landscape",
    image = "rbxassetid://YOUR_GAME_ART",
    imageFraming = { width = 1920, height = 1080, mode = "crop", focusX = 0.72, focusY = 0.4 },
}))
```

The content needs an explicit id. The background fills its view and adds no
activation target. Use `mode = "none"` for an unscaled crop, or `scale = 2` for an
explicit 2x image. Foreground content still owns safe-area padding, contrast
plates, and theme border insets. An opaque foreground surface hides its backing;
put background art behind a plain content container when it should show through.
The screen, billboard and surface targets share this rendering path. Framing
uses one managed image child and four local property observers only when opted
in; it does no per-frame polling or layout work. Authored gradient/corner
modifiers are mirrored onto the picture; live native paint verification remains
pending in the image-framing decision record.

**`tint`** multiplies the picture (`ImageColor3`; see
[above](#continuous-colour-tint)). It leaves `ImageTransparency` alone, so a dim
treatment composes with it rather than fighting it.

### `Button`

`UI.Button.focusVisual` accepts `"default"` (the normal focus outline) or `"none"`
when a composed control paints its own focus treatment, as RadialMenu does on
its outer surfaces. It does not change focus order or activation.


`UI.Button{ id?, label (required), compactLabel?, disclose?, enabled?, selected?,
role?, shape?, icon?, controlSize?, appearance?, underline?, over?, gap?, align?, help?, surface?, textSize?, padding?,
focusable?, focusVisual?, traversalPriority?, onActivate?, children?,
onPointerDown?, onPointerMove?, onPointerUp?, onPointerCancel? }` — activatable
control.

**`controlSize`** (`"xsmall" | "compact" | "regular" | "large"`, bindable) and
**`appearance`** (`"standard" | "emphasis" | "soft" | "utility" | "link" | "inverse"`,
bindable) are the **paint half** of the shared local vocabulary — each becomes one
style tag (`facet-size-<rung>`, `facet-appearance-<word>`) that the theme's rules
key on, exactly as `role` does. Neither moves geometry: the *measurements* of a
rung are the theme ladder metrics `controlSizes.<rung>.{height,paddingX,iconSize}`,
which a composite authors as ordinary `height`/`padding` props. `appearance` is
emphasis only and composes with `role`, which stays the semantic channel:
`role = "destructive", appearance = "utility"` is a quiet delete. `"standard"` is
the paint an untagged button already has and earns no tag. Absent on both means
today's paint, unchanged. `"inverse"` is a light plate on a dark theme (and the
reverse): the theme's `extra.inverseSurface` / `onInverse` pair, unset
`contentStrong` lettered in `surface`. **`underline`** (`"always" | "hover"`,
construction-only, text buttons only) draws the label underlined — always, or while
the pointer is over it or it holds painted focus; it is the usual cue on an
`appearance = "link"` button. **`over = "media"`** (construction-only) is the one tag
for a control drawn on top of artwork: it takes the theme's strong opaque surface
and the content colour gated against it, instead of the caller painting a scrim.

All three reach the engine as **tags and nothing else**, so their paint is the
theme's. On a target whose engine has no native StyleSheet support Facet has no
rule to key on and will not open a second colour authority for one: the words are
accepted and paint nothing there, while the *measurements* a rung drives work on
every target. See `UI.Button` for the composite that authors these three
plus `corners` from one spec.

**`disclose`** (boolean, construction-only) gives a one-line label the same
full-value path a `Text` carries: where the label truncates, hovering or
long-pressing it presents the large-text plate with the whole string. A sliding
picker strip declares it on every segment.

**`help`** (string, construction-only) is the one sentence a pointer hover or a
focus ring gets about what this button does; it shows **nothing on touch** by
specification. See `Text`'s `help` above and **Help** under `app.presenter`.

**`expandTarget`** (`{ role = "cover" | "chevron" }`, construction-only) is
**framework-declared**: `UI.Region` sets it on the one button it synthesizes for a
collapsing region, and nothing else ever should. Authors write `UI.Region{ expand }`.
It is public for the reason `virtualSlot` is — a prop nothing can see is a prop
nothing can audit — and it is carried rather than inferred because a region's forms
can splice themselves out from under an index (`UI.When`), so counting children would
name the wrong node. `role` is a closed set of two, decided from the forms' own
contents: `"cover"` (the whole compact form is the target, declared under it with
`zIndex = -1`) and `"chevron"` (a mark beside it, in width the form reserves).

**Custom content.** A Button takes `children`, which render inside the ONE
activation surface. `label` stays **required** even for an icon-only button — it is
the semantic label — and when content is present the button paints no text of its
own, so the label never shows through beneath the content.

> **Know what "semantic label" reaches, and what it does not.** For a button with
> children the renderer writes `label = ""` to the adapter, and for an icon button
> it writes the drawn glyph; the string you typed is consumed by the solver's
> measurement and by the focus story, and Facet has **no accessibility channel
> behind it** — no assistive-technology name is published to the engine from this
> prop, on any target this library ships. So a `label` is not a substitute for
> drawing the word. **If a player has to know what a button does, draw it**: give
> the content its own text, or put a `UI.Label` in `children`. The `label`
> stays required and stays worth writing — it is what a dump, a bug report and a
> focus trace call the node — but it is not a route to the player. This is a
> framework gap, recorded here rather than papered over.

A focusable in the
content (`Button`, `Toggle`, `TextField`, or a focusable `Grip`) is **rejected at
construction**, naming the offending node: it would create a second focus site and
double-fire Activate, which only misbehaves under keyboard and gamepad navigation
and is therefore exactly the kind of defect that escapes a pointer-only test.

**Saying less when there is less room.** `compactLabel` declares what this button
draws when its full label does not fit. The ladder is:

```
full label fits            -> the full label
full label does not fit    -> the compact form
no compact form declared   -> a word ellipsizes, a phrase wraps
```

Four spellings, one closed grammar — a table carries **exactly one** FORM key, and
anything else is refused at construction naming the set:

```lua
UI.Button({ id = "E", label = "Edit item", compactLabel = "Ed" })
UI.Button({ id = "E", label = "Edit item", compactLabel = { text = "Ed" } })
UI.Button({ id = "E", label = "Edit item", compactLabel = { icon = "edit" } })
UI.Button({ id = "E", label = "Edit item", compactLabel = { image = "rbxassetid://…" } })
```

Plus one **modifier**, which names no content and so does not collide with the
exactly-one-form rule:

```lua
UI.Button({ id = "D", label = "Delete", compactLabel = { icon = "trash", prefer = true } })
```

- **`prefer = true` inverts the ladder from a degrade into a default.** The button
  wears its compact form at *every* width — measured for it as well as painted with
  it, so the box is reserved for exactly what lands in it — and `label` stays the
  semantic name (announced, never drawn). Reach for it when the icon *is* the
  control's content and the word is its name: `UI.RowActions`' tray buttons are the
  framework's own caller. It is not expressible through the fit test, because that
  test is per button — at a width that fits `Flag` and not `Delete`, one plate in a
  tray would wear a glyph and its neighbour a word.
- `prefer` alone is still an empty form: a table must name `text`/`icon`/`image`.

- **The framework never ellipsizes when a compact form exists.** The `…` is what a
  button falls back to when it has nothing better to say; one that *does* has to
  use it instead. This holds by construction rather than by a flag: the compact
  form is chosen exactly when the full label does not fit, and a compact form is
  one word or one mark, so it always does. `TextTruncate` stays on underneath as
  the floor for the ±1 px disagreement between the framework's measurement and the
  engine's own, which is a different problem and one `compactLabel` cannot see.
- **A control pinned on BOTH axes still runs the ladder.** The verdict lives inside
  the content measure, and a node whose width *and* height are both fixed does not
  normally ask for its content size. The measure is forced for any node that
  declared a compact form, so the icon-button shape every spec writes for a 44 px
  control (`width = height = { type = "fixed", px = "targetSizes.minimum" }`) still
  reaches it.
- **A compact string must be ONE word** — no whitespace, refused at construction.
  A phrase has a legal break point, so the engine would wrap it and the button
  would be exactly as tall as the case the compact form exists to avoid.
- **`{ icon = … }` is the form to reach for.** It is a semantic NAME, so a theme
  can repaint it and the framework's own art can draw it, and it **degrades**: the
  ASCII glyph for that name is in the tree from the first frame, so a package with
  no art — or art that has not been uploaded — still renders something legible.
- **`{ image = … }` is the escape hatch and does NOT degrade.** A raw content id
  has no semantic name, so nothing can resolve a tint role, a package override or a
  fallback character for it. If the asset fails, the button draws nothing. Prefer
  `icon` unless you are deliberately shipping your own picture.
- **The decision is the solver's, per solve.** It is made against the width the
  button will actually occupy, not its parent's offer, and it is re-decided on
  every re-solve — so a window that widens brings the full label back with no
  remount. It is **not reactive**: a compact representation is what the control
  *has*. The `label` it stands in for is still free to be a binding.
- **Not on a content button.** A button with `children` draws no text of its own,
  so there is nothing to shorten; declaring one is refused at construction. Use
  `UI.ViewThatFits` inside the content instead.

**Semantic roles.** `role` is `"default"`, `"cancel"`, `"destructive"`, or
`"onIndicator"`. It drives a style **tag** and its sheet rule (`Destructive
button`, `Cancel button`, `Indicator label`), never a bespoke fill, so a designer
retheming those rules restyles every such button. The destructive palette is a
gated `$Danger`/`$OnDanger` token pair, and the role is not colour-only — it
carries the tag and semantics too. A style that predates the pair keeps working:
the library default fills in and the contrast gate runs on the effective pair.

- **`"onIndicator"` is the label-only role, and the only one that brings no
  fill.** The other three name a plate *and* the colour that reads on it. This one
  names the colour alone, because the plate is painted by something else: an
  **accent** surface sitting **behind** the button. That is what Facet's own
  sliding selection indicator is — the chip a segmented `Picker` and a `TabView`
  strip slide between their options — and the option it covers declares
  `surface = "plain"` so it paints no plate of its own. Without this role that
  label kept `$Content`, the colour chosen to read on `$Surface`; on a package
  whose accent is a saturated navy it measured **1.55:1**. The role's rule is
  `TextColor3 = $OnAccent`, the theme contract's one **gated** partner for
  `$Accent`, so the pairing is readable in every theme of every package. Facet's
  segmented `Picker` applies it for you, reactively, so the colour travels with
  the selection; declare it yourself on any plain Button you have painted an
  accent plate behind. It never applies to the `underline` indicator, which paints
  a thin tint rule on the segment's far edge rather than a plate under the label.

- **The sliding fill wears the silhouette of the strip that holds it.** It asks
  for `radii.selection:<container>` — the highlight's radius *inside* a named
  container. An **authored `radii.selection` wins** over every container, so a
  square-art package that sets `selection = 0` gets a square highlight
  everywhere; a **pill** container gives a pill, by the pill rule rather than by
  subtracting from a sentinel; anything else is the container's own radius less
  one `space.xs`, the inset the fill floats by — two concentric rounded rects.
  A segmented picker's container is its own track (`radii.control`); a
  `TabView`'s adaptable app bar in its BAND form also uses `radii.control`,
  so square themes keep square navigation and rounded themes keep rounded navigation. A strip with no plate at all names no container and the
  fill keeps plain `radii.selection` — and so does the same bar's SIDEBAR RAIL,
  because a selected row sits in the middle of a column rather than concentric
  with the rail's outer corner. `corner = "pill"` stays the caller's opt-in, and the
  resolution is a **token**, so a ten-foot display's scaled radii reach it.
  The fill is an inset rounded rect on all four corners,
  floating inside a track that rounds only its two outer ends with
  `radii.control` and keeps its inner segments square and touching, with a
  hairline seam between each pair. A menu card's chosen-row shade and the focus
  ring on that row wear the same token, in one of two forms the package picks
  with `controls.popup.shadeInset`: `0` (default) is flush — edge to edge,
  clipped to the row's place in the card; a positive inset floats the shade
  that far inside the card's edges on all four rounded corners (Glossy Touch: 4).
  On a ten-foot row list every row keeps one silhouette, chosen or not, and the
  FOCUSED row lifts by a paint-only 1.05 on the presenter's spring — the solved
  box, the hit target and the focus order never move.

**Circle buttons.** `shape = "circle"` turns the button into a true 1:1 disc — the
floating round "…" action. It is **not reactive**: a shape is what the control *is*.

- **Geometry is solver-enforced; you never do the math.** The diameter comes from
  the control metric `controls.button.height`, resolved from the live theme
  snapshot, so a metric package resizes every disc and a pixel package snaps it
  onto its grid. Author one axis (`width` *or* `height`) and the other follows 1:1;
  author neither and both are the metric. Authoring **both** is refused at
  construction — that is the author doing the math the solver already does.
  A stretching stack preserves the measured aspect pair unless its driving
  dimension explicitly fills the available space; the disc cannot grow after
  its parent has reserved its height.
- **Content is one mark.** Either a semantic `icon` or a short `label` of at most
  **3 characters with no spaces**. A longer or multi-word drawn label is refused at
  construction, naming the field, the rule and the fix. The default padding is `0`
  (the diameter *is* the box); an explicit `padding` still wins.
- **`icon` is a semantic NAME, never an asset id** — `"more"`, `"close"`, `"menu"`,
  `"chevron.trailing"`, or a package's namespaced `"ns:name"`. The framework draws
  its own ASCII-safe glyph for that name immediately, so the affordance is legible
  under *every* theme, and a package that ships art for the name has the adapter
  paint the picture over it, tinted by that asset's `tintRole`. A plain name outside
  the vocabulary (`"search"` for `"facet:search"`) draws a dot and warns once per
  name in the output, naming the near miss when there is one. With an `icon` the
  `label` stays the **semantic name** and is not drawn — which names the node for a
  dump, a bug report and a focus trace, and reaches the player through nothing (see
  the accessibility note under **Custom content** above). `icon` is circle-only; a
  glyph a player must be able to identify needs a word drawn beside it, not only a
  `label`. For an icon *beside* a title,
  put a `UI.Label` in the button's `children`.
- **Paint costs a flat theme nothing.** The pill radius and the rim are phantom
  `::UICorner` / `::UIStroke` rules on the `facet-shape-circle` tag (the same radii
  machinery the slider thumb uses) — no extra instances. The rim carries
  `ApplyStrokeMode = Border`, so it outlines the disc instead of haloing the glyph.
- **Skinning needs no new slot.** A circle Button classifies to the ordinary
  `control` decoration slot, so a package dresses it with the same recipe it
  already writes — whole-image round art works exactly like the ornate stepper
  plate. Once art covers the node the image *is* the silhouette: the
  node's own circle and rim are suppressed, so a package whose `control` art is a
  rectangle draws a rectangle. Ship round art if you want a round skinned disc.
- **Under a skin, prefer the icon.** A rectangle *grows* to absorb its skin's
  `contentInsets`; a fixed-diameter disc cannot, so those insets come straight out
  of the middle — a package reserving 14 px per side leaves 16 px of text room in a
  44 px disc (measured under Fantasy Ornate and Glossy Touch:
  `artifacts/rich-skinning-v2/rs-circle.json` O2). The icon is unaffected: the
  managed picture is anchored centre at the theme's `iconSizes` and never reads the
  insets. Use `icon` for a skinned disc, or give the button an explicit larger
  `width`.
- **`UI.corners` / `UI.shadow` / `UI.gradient` compose as on any Button** — the
  per-view modifier wins on that node, exactly as documented under Modifiers.

```lua
UI.Button({ id = "More", label = "More actions", shape = "circle", icon = "more" })
UI.Button({ id = "Count", label = "3", shape = "circle" })
```

**Hit target.** Every focusable control's effective target is floored at 44 px in
**hit** geometry — see "Hit-target floor" below. The visual rect is untouched. A
circle's hit geometry is its **full square**, corners included: the engine rounds
the *paint*, never the input rect, so a 44 px disc is honestly a 44 px target and
the floor is measured against the square, not the inscribed circle.

Other behaviour: participates in focus order; taps and the
semantic Activate action share one code path. `onActivate(path, meta)` is an
optional per-node effect: when set, the presenter auto-dispatches Activate (tap /
Return / ButtonA) to it with no surface wiring at all. An explicit `onActivate`
in the options passed to `app.mount` / `app.presentModal` overrides it.

#### Hit-target floor

`Button`, `Toggle`, `TextField` and `Grip` declare a 44 px minimum effective target
(`src/class_contract.luau`). The renderer **enforces** it: after each solve,
any such control whose solved rect is below the floor on either axis gets an
expanded **hit rect**, centred on its visual, pushed to the adapter through
`setHitRect`. The engine adapter realises that as a transparent expander behind the
control which forwards activation to it.

The visual rect is deliberately **not** grown. Enforcing the floor by resizing
controls would silently rewrite shipped visual design — a 22 px icon button would
double — so the framework separates *what the player sees* from *what the player can
hit*. The trade-off is that two sub-floor controls placed closer than 44 px apart
have overlapping hit areas; the expander sits behind the control, so the control's
own rect always wins where they overlap.

Only one axis expands when only one is short, the expander is removed as soon as a
re-solve brings the control up to the floor, and a non-interactive node never gets
one.

### `Toggle`

`UI.Toggle{ id?, label (required), value?, enabled?, disclose?, help?, padding?,
textSize?, focusable?, traversalPriority?, onActivate? }` —
boolean control. When `value` is a writable Compose cell the presenter AUTO-FLIPS
it on Activate (tap / Return / ButtonA) with no surface wiring (contract "Activate
flips value"). Supply `onActivate(path, meta)` to take over the effect, or an
explicit `onActivate` in the options passed to `app.mount` to override the whole
auto path.
The label draws ONE line with an end ellipsis: a wrapped label plus the
press-scale affordance produces mid-word breaks.
`disclose` (construction-only) is the label's full-value path: where
a compact width truncates it, engaging the toggle (hover dwell / focus /
long-press) presents the full label through the presenter's static disclosure
plate, exactly as a `Text` with `disclose` does. **`help`** (construction-only)
is the separate, player-pulled sentence about what the toggle DOES — pointer
hover and focus only, nothing on touch (see `Text`'s `help`).

### `TextField`

`UI.TextField{ id?, text?, placeholder?, editing?, enabled?, editable?, focusable?,
selectOnFocus?, maxLength?, keyboardType?, multiline?, surface?, help?, padding?, textSize?,
traversalPriority?, onTextChanged?, onFocusGained?, onFocusLost?, onScrub? }` —
the text-entry leaf primitive the renderer maps to an engine `TextBox`. All of
`text`/`placeholder`/`editing`/`enabled`/`maxLength`/`keyboardType` ride the
binding authority (the engine adapter maps `editing` to CaptureFocus/
ReleaseFocus, `text`/`placeholder` to `.Text`/`.PlaceholderText`); layout/style
props inherit `common`. **`help`** (construction-only) is the player-pulled
sentence about what this field is for — pointer hover and focus only, nothing on
touch (see `Text`'s `help`). The three handler props are functions the adapter wires
through the optional `setTextInputHandlers(handle, handlers)` seam
(`handlers = { onTextChanged(text), onFocusGained(path), onFocusLost(reason), onScrub?(phase, arg), onCaretRect?(rect) }`,
`reason ∈ "enter" | "focusLost" | "cancel"`; `path` is the focused node's full
path — engine-initiated focus must deliver it so occlusion keep-visible works
without a prior activate). `onScrub` reports a horizontal drag across the editor: `"press"` with the pressing class (`"pointer"` or `"touch"`) answers whether to follow it, `"begin"` past the shared slop answers whether to take it (the adapter then releases focus), then `"move"` with the total horizontal travel in pixels and one `"end"` or `"cancel"`. The renderer supplies `onCaretRect` for multiline fields; adapters report the native caret's line rectangle relative to the field so the existing scroll authority can reveal it. Prefer the `UI.TextInput`
composite over building on the raw primitive. `multiline = true` is construction-only and maps to public `TextBox.MultiLine` and `TextWrapped`; Enter inserts a newline. `keyboardType` is intent metadata with no native keyboard effect. `editable = false` is the engine's own read-only mode (`TextEditable`), default true: the field stays focusable, selectable and at full contrast but refuses every edit; the adapter composes it with `enabled`, so a field is editable only when both allow it. `selectOnFocus` (`"none"` default, `"all"`, `"end"`; bound words apply live, an illegal one is refused and the last legal policy stays) is read once at the start of each native focus session: a focus made by a pointer press applies it at that pointer's release, after the engine has placed its own caret; any other focus applies it at once. Offsets are the engine's byte offsets; `none` writes nothing, and text writes never select. `surface = "plain"` provides a transparent native editor when a containing control owns the frame, as in `TextInput`. The frame stays visible during native focus and editing.

### `UI.NavigationStack`

`UI.NavigationStack { ... }` — or `UI.NavigationStack("Id") { ... }` — builds a
root-and-destination flow and returns the flow's node. Put that node in your
screen and keep its `path` cell in your model.

| Field | Contract |
|---|---|
| `id` | Optional nonempty node ID, default `"NavigationStack"`. |
| `path` | Required caller-owned writable Compose cell of `{ { id: string, value: any? } }`; empty means root. Write a new array to restore or replace a path. |
| `root` | `{ title?, content(pageOwner, entry?) -> Blueprint }`; `entry` is nil at root. |
| `destinations` | Required map from route ID to the same `{ title?, content }` page specification. Each entry's `value` carries your domain data. |
| `backLabel` | Required localized, nonempty Back label. |
| `env` | Optional environment; live size class adapts chrome spacing/type through existing theme metrics. |
| `transition` | Optional static structural transition specification — a table, never a readable. Omit for immediate replacement. Pure horizontal slide/mirror pairs use the navigation policy described below; other forms retain their authored behavior. Reduced motion follows the shared motion authority. |
| `ref` | Optional `function(record)`, called once while the control is built. |

Titles accept strings or readable strings. An untitled root adds no chrome or
page padding, so an existing full-screen shell can be its content. Destinations
retain Back chrome even without a title.

**`ref` hands back the control's record**, frozen, as `{ api, dump }`. `api` is
frozen too and carries `push(entry)`, `pop()`, `back()` (an alias for `pop`) and
`popToRoot()`; each returns whether the operation changed the path, and pop/back
at root returns false. Multiple operations in one Compose batch compose against
the caller's current path. After disposal every operation returns false.
`dump()` carries `schema = "facet-navigation-stack-dump/1"`, the accepted path,
depth, the current route/key/value, `canGoBack`, the live page count, disposal
state, quarantine state and a sticky `lastError`.

Pages occupy one clipped viewport throughout replacement; an outgoing page never
reserves a second layout slot. With `transition = { enter = "slide-left" }` (and
an omitted or mirrored `exit`), push moves both pages left, and Back/pop-to-root
moves them right. `slide-right` reverses that convention. Travel defaults to the
stack's own solved width, including nested stacks; an explicit positive finite
`distance` overrides it. The initial page appears in place. Depth orders the
opaque pages so Back reveals the prior page underneath. Interrupted pure slides
preserve their current painted position and velocity. Size changes re-solve the
page box; travel distance is sampled for each navigation operation. Fades,
slide-plus-fade, vertical slides and explicitly non-mirrored pairs keep their
authored transition semantics.

Only the current page accepts input. An outgoing page may remain painted until
its declared exit transition finishes. Each content builder runs under the page's
own Compose owner and receives it as its first argument; use it for page-local
controls, subscriptions and async work. Removing a
page disposes that work after its exit. Returning after teardown rebuilds it;
returning during its exit revives the existing page and owner. Both restore its last
legal focus path, falling back to a legal entry when the old control is gone. Keep form values
and any scroll offset that must survive in your model, outside the page owner.
Repeated route IDs are allowed: occurrences have distinct framework keys. Hot
changes to viewport, input, theme and text preferences re-solve the same page.

Nested controls receive Cancel before their enclosing stack; a stack at root
returns Cancel to its containing stack or modal. The presenter remains the only
hardware/input/focus owner. Construction rejects invalid specs and initial paths.
An invalid external path write keeps the last accepted page and records an error;
a later valid write recovers. A failing content builder is contained in its page,
retaining Back chrome so the rest of the flow remains usable.

```luau
local path = Compose.cell({})
local flow
app.mount(function()
    return UI.Screen {
        UI.NavigationStack("Orders") {
            path = path, backLabel = "Back", env = app.environment,
            ref = function(record) flow = record.api end,
            root = { title = "Orders", content = function()
                return UI.Button { label = "Order 42", onActivate = function()
                    flow.push({ id = "order", value = 42 })
                end }
            end },
            destinations = { order = { title = "Order details", content = function(_, entry)
                return UI.Text { text = `Order {entry.value}` }
            end } },
        },
    }
end)
```

The control owns its presentation state. It never disposes the caller's path
cell or domain values, and it releases its own pages when its node unmounts.

### Text baseline alignment

Use `align = "firstTextBaseline"` or `"lastTextBaseline"` on a horizontal
stack, or `lineAlign` on an individual child. First aligns the first line of
text; last aligns the final line, including wrapped text. Each row reserves the
largest distance above and below its guide before arranging children. Wrapped
stacks do this separately for each line. A child override takes priority over
the container alignment.

Nested layouts forward their first or last arranged text guide, including
padding, gaps, and text wrapping. Hidden text still occupies layout and contributes;
unselected `ViewThatFits` candidates do not. A child without text uses its bottom
edge. Vertical stacks fall back to start and report a diagnostic, since their
cross axis cannot align horizontal text guides.

These are **theme-defined semantic guides**, not measured font glyph baselines.
`metrics.typography.<role>.baseline` is an optional fraction of the text size in
`[0, 1]`, default `0.8`; half the line's extra leading is added. The same text size,
line height, preferred text size and theme snapshot used by measurement determine
the guide. Theme packages can calibrate the ratio to their font. A baseline
alignment change invalidates measurement as well as arrangement. Existing
alignment values retain their geometry and stay on the normal solver path.

```lua
UI.HStack({
    align = "firstTextBaseline",
    children = {
        UI.Text({ text = "Score", textSize = "body" }),
        UI.Text({ text = score, textSize = "title" }),
    },
})
```

### `Box` / `Spacer`

`UI.Box{ id?, width?, height?, surface?, tint?, shape?, canvasGroup?, opacity?, offsetX?, offsetY? }`
— a painted rect by default. Its construction-only `shape = "circle"` follows the
same one-axis/square rule as Image and preserves Box tint paint. The circular
corner follows the shape rather than the theme's pill radius, adds no implicit
border, and does not allocate a render buffer. `UI.Spacer{}` consumes available
main-axis space in a stack.

| Property | Type | Meaning |
|---|---|---|
| `minLength` | `Bound<number \| Metric>` | Optional nonnegative main-axis floor, default `0`. A number is pixels; a metric such as `"m"` follows the live theme. |

The stack reserves spacer minima before sharing remaining space by fill weight.
On a deficit the minima remain and ordinary overflow diagnostics report the
shortage. An explicit main-axis width or height takes precedence and reports a
conflict diagnostic; omit it to use `minLength`. Wrapping stacks reserve the
minimum without stretching the spacer across a line. Outside a stack the minimum
has no effect and is diagnosed. Changing the bound minimum or theme remeasures
without replacing the mounted spacer. `UI.Spacer({ minLength = "m" })` is a themed
minimum gap that can grow.

**`tint`** paints the box's fill continuously (see
[above](#continuous-colour-tint)); on a Box it claims both the colour and the
opacity, so a tinted Box paints whether or not it also names a `surface`.

**`canvasGroup = true`** makes this Box its subtree's **fade group**: the adapter
materializes it as a `CanvasGroup`, and `controller.setPresentationTransparency`
then fades everything inside it through one `GroupTransparency` write. It is opt-in
because it costs a render buffer and changes the shape of the tree — the Box
becomes its descendants' real instance parent, so the group renders (and clips) as
a unit and nothing outside it can interleave in paint order. It is also the only
way to fade a subtree: a per-node transparency write would fade one node's own
fill or glyphs and would contest native-sheet paint ownership permanently. The
three costs — always-clipped descendants, the blank texture past the client's
texture-memory cap, and the texture recreated on every resize — are the same in
both forms; they are written out under
[`ZStack`](#canvasgroup-costs).

### `Path`

`UI.Path{ id?, points, thickness?, closed?, role?, tint?, width?, height? }` —
stroked-path leaf backed by the engine's `Path2D` (native-substrate NS-A7):
progress rings, arcs, gauge needles. `points` is a (reactive) array of
NORMALIZED control points from `Facet.pathShapes` — a points change is a
paint-only prop write (never a re-solve), and the adapter re-scales the same
normalized points when the solved rect changes. `role` picks the stroke color
from the **active theme's** palette (`"accent"`, `"secondary"`, default content)
— never a raw color, and re-resolved on every theme commit, since a `Path2D` is
not a `GuiObject` and no stylesheet rule can reach one — or, for a value no role
can name, `tint` (see
[above](#continuous-colour-tint)), which writes the same stroke colour from the
continuous channel and needs no claim (nothing can style a `Path2D`).
`thickness` takes a px number **or a theme metric name**, resolved against the
live snapshot at the write seam, exactly as `Divider.thickness` does; absent, the
framework writes nothing and the `Path2D` keeps its engine default. Engine limits
(measured): at most 100 control points; stroke only (no fill); no per-path
transparency.

**Clipping is the framework's, not the engine's** (RS-PATHCLIP). A stroke is not
a box in the widget tree, so no ancestor's clip crops it and there is no
half-crop operation for one. The renderer therefore CULLS a path that is not
fully inside every clip host (`clipChildren`, and every `ScrollView`) above it:
it stops painting entirely rather than escaping the viewport. The rule follows
the LIVE scroll offset — a same-window scroll writes no rects, and the cull
re-runs from the host's own offset change without forcing a re-solve — so a
windowed row scrolled out of a list takes its ring with it. Consequence to
design for: a path meant to overhang a clipping container (a glow ring wider
than its plate) must live OUTSIDE that container, exactly as a shadow does.

### `Stage`

`UI.Stage{ id?, width?, height?, surface?, tint? }` — the **engine-content box**:
a leaf that reserves a rectangle for content the *engine* draws (a kart preview, a
character turnaround, a hero rig) instead of content Facet lays out. The adapter
materializes it as a `ViewportFrame` and creates and owns two instances inside it:
one `WorldModel` (the content root) and one `Camera` assigned to the frame's
`CurrentCamera`. Both die with the node.

**It measures 0×0 without explicit dimensions**, exactly like `UI.Box`: the
framework cannot ask a 3D scene how large it would like to be, so a Stage with no
`width`/`height` reserves nothing and you will see nothing. Always give it a box:

```lua
UI.Stage({
    id = "Preview",
    width = { type = "fixed", px = 240 },
    height = { type = "fixed", px = 240 },
    surface = "raised",
})
```

`surface` is the standard nine-surface vocabulary (`base`, `raised`, `pane`, `control`,
`chip`, `badge`, `accent`, `scrim`, `plain`) and paints the plate *behind* the
scene. **`tint`** (see [above](#continuous-colour-tint)) claims the frame's own
`ImageColor3` — a stage's "picture" is the scene it renders, and the engine
multiplies it exactly as it multiplies an `Image`'s asset — so a tint dims or hues
the *content*, not the plate. Layout, focus, and paint are otherwise an ordinary
leaf's: a Stage is not focusable and owns no input.

#### The content seam: `controller.stageHost(path)`

Content is engine Instances by nature, so it never travels through a blueprint.
`renderer.attach(...)`'s controller answers a **per-node handle**, cached, with an
engine-type-free boundary — plain tables in, engine writes out:

| Call | Shape | What it does |
|---|---|---|
| `setCamera(spec)` | `{ position = { x, y, z }, lookAt = { x, y, z }, fov? }` | aims the owned camera (`CFrame.lookAt`; `fov` in degrees, clamped 1–120, absent = unchanged) |
| `setLighting(spec)` | `{ ambient? = { r, g, b }, lightColor? = { r, g, b }, lightDirection? = { x, y, z } }` | writes the frame's `Ambient` / `LightColor` / `LightDirection`. Colours are 0–1 floats, the same shape the theme tokens use; every field is optional and independent, but an empty spec is refused |
| `contentRoot()` | — | the owned `WorldModel`. Parent your models here |

```lua
local stage = controller.stageHost("/Garage/Preview")
if stage == nil then
    -- this adapter has no stage seam: show a fallback plate
else
    kartModel.Parent = stage.contentRoot()
    stage.setCamera({ position = { x = 0, y = 4, z = 9 }, lookAt = { x = 0, y = 1, z = 0 }, fov = 45 })
    stage.setLighting({ ambient = { r = 0.35, g = 0.35, b = 0.4 } })
end
```

**Who owns what.** Facet owns the frame, the `WorldModel`, the `Camera`, the box,
the lifecycle, and *every* write to `Ambient`, `LightColor`, `LightDirection` and
`CurrentCamera` — those four are declared seam-owned in
`src/render/authority.luau`, so a bespoke write to one is an error, not a silent
second authority. **You own whatever you parent into `contentRoot()`**: the
framework never enumerates, moves, or re-parents it, and it is destroyed with the
frame when the node unmounts. A handle whose node has died refuses every call by
name — ask `controller.stageHost(path)` again after a remount.

Malformed specs are refused at the call (constitution §4): an unknown key, a
missing `lookAt`, a non-numeric channel, or a camera whose `position` and `lookAt`
are the same point all error naming the field.

<a id="stage-costs"></a>
**What a stage costs.** Each one is a **separate scene render** every frame it is
visible — the same class of cost a `CanvasGroup`'s buffer is, and larger. A stage
is for a *small number of stable boxes*: a preview pane, a hero, a garage
turnaround. It is not a list cell: a scrolling roster of live 3D thumbnails is N
scene renders per frame and will not hold frame rate on a phone. Render one stage
and change what is in it, or fall back to pre-rendered images.

**The fallback contract.** `stageHost` is an OPTIONAL render-target method
(`render/target_contract.luau`). A controller whose adapter does not implement it —
or whose engine lacks `ViewportFrame`/`WorldModel`/`Camera`, or a node that is not
a live Stage — returns **nil**, and the node is simply an empty reserved box that
still paints its `surface`. Gate on the nil or present a fallback plate; never
assume the handle. `billboard_target` deliberately does **not** implement the seam:
a scene rendered inside a camera-projected world canvas is unproven, so it degrades
by name rather than shipping an unmeasured render.

### `Foreign`

`UI.Foreign{ id?, width?, height?, surface? }` — the **bounded escape hatch**:
a leaf that reserves a rectangle for a Roblox `GuiObject` **Facet does not wrap**.
A `VideoFrame`, an `EditableImage` surface, a vendored widget, a first-party class
Roblox ships next month. It is `UI.Stage`'s 2-D sibling — same "the framework owns
the box, somebody else owns the content" shape.

**It takes no engine properties, and that is the whole design.** There is no
`class`, no `props`, no `instance` — typing one is refused at construction with the
reason and the line that works, not a did-you-mean. The framework claims exactly
*one* thing about the instance you adopt (its `Parent`) and disclaims the rest **by
construction**: it never creates your instance, never sizes it, never paints it,
and keeps no reference to it, so there is no second writer to arbitrate. That
matters on this engine specifically, because a second writer is **silent** — an
explicit write defeats a StyleSheet rule and fires no signal.

**It measures 0×0 without explicit dimensions**, exactly like `UI.Box` and
`UI.Stage`, and here the reason is sharper: an engine instance with `AutomaticSize`
measures *itself*, which the solver cannot see. The box is **declared**, never
inferred — and the container **clips**, so nothing you adopt can paint one pixel
outside the rect the solver reserved.

```lua
UI.Foreign({
    id = "Trailer",
    width = { type = "fixed", px = 320 },
    height = { type = "fixed", px = 180 },
    surface = "raised", -- the plate BEHIND your content (a fallback while it loads)
})
```

`surface` is the standard nine-surface vocabulary and paints the container, which
Facet owns. There is deliberately **no `tint`**: a tint multiplies the node's own
picture, and this node's picture is *your* instance — painting it would be the
framework writing the content it exists to disclaim.

#### The content seam: `controller.foreignHost(path)`

One verb, because the caller already owns everything else:

| Call | Shape | What it does |
|---|---|---|
| `adopt(instance)` | a live `GuiObject` | parents it into the box. This is the single `Parent` write, declared in the authority manifest as `Foreign.Parent = "host"` and made through the same gate every other engine write goes through |

```lua
local host = controller.foreignHost("/Watch/Trailer")
if host == nil then
    -- this adapter has no foreign seam: the box still paints its `surface`
else
    local video = Instance.new("VideoFrame")
    video.Video = "rbxassetid://…"
    video.Size = UDim2.fromScale(1, 1) -- YOUR coordinate space is the box
    host.adopt(video)
    video.Playing = true               -- ...and every property stays yours
end
```

#### `onHost` — the same seam, delivered instead of polled

Only a **controller** can be asked for `foreignHost`, and a component builds
before its own `app.mount` returns one. So a component that wants to fill its own
box has no controller at the moment it declares the box, and the workaround every
consumer reached for was the same: smuggle the controller out through a mutable
box the host fills in later, then ask for the handle on **every frame** until it
stops answering `nil`. That is a busy-wait for a structural event the renderer
knows the exact moment of.

`onHost` **is** that moment, declared where the box is:

```lua
UI.Foreign({
    id = "Trailer",
    width = { type = "fixed", px = 320 },
    height = { type = "fixed", px = 180 },
    onHost = function(host)
        if host == nil then
            return -- this target has no foreign seam; the box still paints `surface`
        end
        local video = Instance.new("VideoFrame")
        video.Size = UDim2.fromScale(1, 1)
        host.adopt(video)
        return function()
            video:Destroy() -- run when the node is removed, or the surface torn down
        end
    end,
})
```

It is called **once**, after the node is rendered, with exactly what
`controller.foreignHost(path)` answers — the `{ adopt }` handle, never the
container, because the container is Facet's and handing it out is the
writable-handle hole above. `nil` means this render target has no foreign seam,
which is the same fallback `foreignHost` already documents. What you **return**
is run once when the node goes away — on removal and on teardown, never twice —
and returning nothing is fine. Both halves are contained: your engine code
throwing is reported through the surface's boundary and never unwinds the render
pass. `onHost` composes with `onAppear`/`onDisappear` rather than replacing them.

**Who owns what.** Facet owns the container, its rect, its plate, its clip and its
lifecycle. **You own the instance**: its class, every one of its properties, its own
children, and its lifetime. Position and size it in the container's own space
(`UDim2.fromScale(1, 1)` fills the box and tracks it with no per-frame work).

**It dies with the box.** The container is destroyed on unmount and engine `Destroy`
propagates, so adopted content goes with it. If you need it to outlive the node,
re-parent it out yourself in `onDisappear`. A handle whose node has died refuses by
name — ask `controller.foreignHost(path)` again after a remount.

**There is no `contentRoot()` here**, unlike `stageHost`, and the asymmetry is
deliberate: handing back the container would hand back a framework-owned
`GuiObject` that the renderer writes a rect and a plate onto every solve, which is
exactly the writable-handle hole that defers `Ref`-shaped APIs. Adopting *into* the
container hands back nothing at all.

**One thing the framework does not write but does still reach: the theme sheet.**
Facet writes exactly one property on your instance. A *native-mode* surface,
however, links a theme `StyleSheet` at its root, and a `StyleLink` is **ambient in
the DataModel and selects by class** — so a rule can style an instance the
framework has never heard of, simply because it is now a descendant. Facet's own
sheet carries class-default rules for the seven GuiObject classes it renders
(`Frame`, `TextLabel`, `TextButton`, `ImageLabel`, `TextBox`, `ScrollingFrame`,
`CanvasGroup`), including `BackgroundTransparency = 1`.

**And it has a sharp edge.** A rule loses to an explicit
write — but the engine decides "explicit" **by value, not by assignment**. An
adopted `Frame` is born at `BackgroundTransparency = 0`, which *is* the class
default, so writing `0` changes nothing the engine can see and the rule keeps
winning: `GetStyled("BackgroundTransparency")` reads **1** while the raw property
reads **0**, and the box renders empty. Writing `0.5` gave `styled = 0.5`; writing
`0` again went straight back to `styled = 1`.

So: **a class-default value cannot be held against a style rule at all.** Give any
property you care about a non-default value (`0.02` instead of `0`). Note that the
classes you most likely came here for — `VideoFrame`, `EditableImage` surfaces, a
vendored widget's own class — are **not** selected by that sheet and are
unaffected; the collision is specifically with the classes Facet itself renders.

**What it is outside of.** A Foreign box takes **no focus stop** and consumes no
semantic action. The framework has never seen your instance, so Facet's
Tab/gamepad traversal cannot stop on it; its own engine input still works normally.
Compose a focus stop *around* the box (a `Button` overlay, a focusable `Grip`
sibling) exactly as you would around a `Stage`. It is also **never recycled** into
the instance pool (a new identity must never inherit somebody else's content) and
**never wears a theme package's decoration slot** (a whole-art recipe would paint
its plate over your content); a theme still reaches its *edge* through the authored
`UI.stroke` / `UI.corners` modifiers.

**Refusals name the alternative.** `adopt` refuses nothing-passed, a
`LayerCollector` (a `ScreenGui` cannot be a child of a `GuiObject`), a
non-`GuiObject` — for a `Part`/`Model`/`Beam`, the message points at `UI.Stage`,
which is the 3-D case — and an
instance the engine has already destroyed.

**The fallback contract.** `foreignHost` is an OPTIONAL render-target method
(`render/target_contract.luau`). A controller whose adapter does not implement it,
or a path that is not a live `Foreign`, returns **nil**, and the node is simply an
empty reserved box that still paints its `surface`. `billboard_target` deliberately
does **not** implement it, for the same unmeasured-canvas reason it withholds
`stageHost`.

### `Grip`

`UI.Grip{ id?, cursorHint?, focusable?, focusVisual?, traversalPriority?,
onPointerDown?, onPointerMove?, onPointerUp?, onPointerCancel? }` — non-button pointer zone with
capture-based drag routing (used by Table column resize). Opt-in focusable for
gamepad reachability, where the focus-gated `Adjust` verb replaces the drag (a
virtual cursor cannot see a `MouseIcon` hint).

**`focusVisual`** (construction-only) is `"default"` or `"none"`, and it answers
*who draws the focused state*. A focused Grip fills with the accent colour,
because a thin sliver wearing a hairline ring reads as "focus went nowhere".
That is right for a resize handle and wrong for a control
whose grip spans its whole width: `UI.Slider`'s track is exactly that, and filling
it paints a solid bar over the value the player is trying to read. `"none"` says
this control paints its own focused treatment, so the adapter paints none — the
decision is made in the renderer, where the node is visible, and a control that
declares it owes a focused treatment of its own. Handlers receive `(path, pos, rectOf)`;
`onPointerDown` may return `false` to decline the capture so a sibling zone
under the same point can take it, and `onPointerCancel(path, reason)` may
return `true` to keep a capture alive when its origin node unmounts mid-drag.

`rectOf` here is the renderer's **`screenRectOf`** — the rect where the node is
painted, not the solved one (see "Two rect reads" under [`renderer`](#renderer)).
`pos` always arrives in window space, so the lookup a pointer handler is given
answers in window space too: a node inside a scrolled container solves in canvas
space, and mixing the two puts drag arithmetic off by the container's scroll
offset. Ask it again on every move rather than caching the answer from
`onPointerDown` — a scroll host above the node can move it under a live capture.

### `When`

`UI.When("Id"){ condition, thenView, elseView?, transition? }` — structural
region: it mounts and unmounts its branch when `condition` changes. Only
structural regions may mount or unmount nodes. `transition` declares how the
branch comes and goes — see **Structural transitions** below.

| Field | Contract |
|---|---|
| `condition` | Required. A Compose readable of a boolean, or a `function(use) -> boolean`. |
| `thenView` | Required `() -> Blueprint`, built while the condition reads true. |
| `elseView` | Optional `() -> Blueprint`, built while the condition reads false. |
| `transition` | Optional transition table, or a Compose readable of one. |
| `id` | The constructor name: `UI.When("Expand") { … }`. A region may also be anonymous. |

**`UI.When` is public on `app.controls`.** The SPEC SHAPE selects the form, not
the name: a table carrying `condition` is built by the structural dispatch —
so a declared `transition` reaches the transition coordinator — whether the
region is named (`UI.When("Expand") { … }`) or anonymous (`UI.When { … }`). A
table of numeric children, plus the class's own props, builds the plain
structural node instead, which is the form for a region you drive with your own
`Compose.show`. Any other key is an error that names both shapes.

Each branch builds under its own Compose owner, created when the branch opens
and disposed when it closes, so a panel owns its motion values, timers and async
handles on the panel's own lifetime instead of on the enclosing owner. Every
re-entry gets a fresh owner, so nothing a closed branch owned survives into the
next opening. Declare cleanup with `Compose.cleanup` inside the factory.

```luau
local isOpen = Compose.cell(false)
UI.When("Panel") {
    condition = isOpen,
    thenView = function()
        local ticks = Compose.cell(0)
        Compose.cleanup(function() print("panel closed") end)  -- dies with the panel
        return Panel(ticks)
    end,
    elseView = function() return UI.Text { text = "Closed" } end,
}
```

`When.transition` and `ForEach.transition` also accept a readable of a
transition table. The shared transition authority samples and validates it on
each enter and exit; changing the value alone does not restart a flight.
A motion record keeps the spring class chosen when it began; a newly created
record reads the latest class. This lets a control choose travel from its state
without owning another animation system.

### `ForEach`

`UI.ForEach("Id"){ items, key, row, transition? }` — keyed structural region:
add, remove and move only. Surviving keys keep their mounted identity and their
owners; duplicate keys are hard errors.

| Field | Contract |
|---|---|
| `items` | Required. A Compose readable of an array, or a `function(use) -> array`. |
| `key` | Required. A `(item) -> string`, or the NAME of the field that holds the identity (`key = "id"`, read as `tostring(item[field])`). Duplicate keys are hard errors. |
| `row` | Required `(item) -> Blueprint`, built once per key under that row's own Compose owner. |
| `transition` | Optional transition table, or a Compose readable of one; it applies per keyed row. |
| `id` | The constructor name: `UI.ForEach("Rows") { … }`. On `app.controls` the name is what selects this spec form — see below. |

**`UI.ForEach` is public on `app.controls`.** The SPEC SHAPE selects the form,
not the name: a table carrying `items` reaches the structural dispatch and the
transition coordinator whether the region is named (`UI.ForEach("Rows") { … }`)
or anonymous (`UI.ForEach { … }`). A table of numeric children, plus the class's
own props, builds the plain structural node instead — that is the form for a
region you drive with your own `Compose.keyed`. Any other key is an error that
names both shapes.

Each row builds under its own Compose owner, so a cell can own item-lifetime
resources (an async handle, a per-row formula) and release them with
`Compose.cleanup` when its key leaves. `row` is also handed the row's live
Compose readable as a third argument, for a cell that must track the item value
in place rather than rebuild.

```luau
local rows = Compose.cell({ { id = "a", label = "Alpha" } })
UI.ForEach("Rows") {
    items = rows,
    key = function(item) return item.id end,
    row = function(item) return UI.Text { text = item.label } end,
    transition = { enter = "slide-up", stagger = 0.04 },
}
```

`transition` is described under **Structural transitions** below.

### `sortedEntries`

`UI.sortedEntries(dict, compare?) -> { { key, value } }` — flattens a dictionary
into the array `UI.ForEach` takes, in a **deterministic** order. Pure; it reads
the table and returns a fresh array, mutating nothing.

**Why this exists rather than the three-line flatten.** Luau's `pairs` order is a
function of the table's hash layout, and the hash layout is a function of the
table's *construction history*. Four constructions of the same twelve-key map can
iterate four different ways, so a leaderboard flattened with `pairs` orders itself
by the order players happened to join. Repeating the flatten does **not** expose
this: the hash has no per-process seed, so an identical construction iterates
identically forever, and the naive "build it twice and compare" check passes with
the bug in place (`tests/sorted_entries.spec.luau` keeps that as a named case).
The same order-by-construction behaviour holds in Roblox's own Luau VM, not only
headless.

```luau
local rows = Compose.formula(function(use)
    return UI.sortedEntries(use(scores))        -- { {key="player_1007", value=150}, … }
end)
UI.ForEach {
    items = rows,
    key = function(entry) return entry.key end,
    row = function(entry) return UI.Text { text = `{entry.key}: {entry.value}` } end,
}
```

- **Default order:** numbers before strings, then each type's natural order.
  (`1 < "a"` is an *error* in Luau rather than an order, so a bare `<` would throw
  on a mixed map instead of ordering it.)
- **`compare` orders KEYS, not entries** — `(a, b) -> boolean`. Keys are unique,
  so any strict order over them is a *total* order and the result stays
  deterministic whatever comparator arrives. Had it ordered entries, ranking a
  leaderboard by score would hit ties, `table.sort` is not stable, and the tie
  order would fall back to the `pairs` order this helper exists to remove. **To
  rank by value, sort the returned array yourself with an explicit key tiebreak.**
- **A key type with no natural order is refused at construction**, naming
  `compare`. Ordering tables by `tostring` would be ordering them by address —
  a silent wrong answer where a loud refusal belongs.
- It is deliberately **not** a `UI.ForPairs` class (that would be a second
  structural region with the first one's semantics) and deliberately **not** a
  `Readable`: the reactive half is the `Compose.formula` above, which a consumer
  already writes for every derived value.

#### Structural transitions

`transition = { enter, exit?, class?, exitClass?, fade?, distance?, scale?, pivot?, plate?, stagger?, fromRect?, source?, content? }`
on `UI.When`, `UI.ForEach`, a `presentToast` and `PresentOpts`. The key set is
closed: an unknown field is refused where it is written. A named `UI.When("Id")`
or `UI.ForEach("Id")` on `app.controls` reads it natively, so a transition
declared in app code reaches the same coordinator a framework control's does.

- **Forms:** `"fade"`, `"slide-up"`, `"slide-down"`, `"slide-left"`,
  `"slide-right"`, `"materialize"` (scale 0.96 → 1 with a fade), `"transform"`, `"reveal"`, `"instant"`.
  A form names the direction of **travel** — an enter travels toward rest, an
  exit away from it.
- **`exit` defaults to the mirror of `enter`** (`slide-up` ⇄ `slide-down`,
  `slide-left` ⇄ `slide-right`): *if it disappears one way, it emerges from
  where it came*. An asymmetric exit is legal but must be **declared**
  (`exit = "instant"` is the common one) — undeclared asymmetry does not exist.
  Because a mirror pair displaces the node to the *same* absent place, a
  re-entry mid-exit reverses through one continuous motion.
- **`reveal`** opens a vertical clip from zero height to its solved height and
  closes it in reverse. Requires `clipChildren = true` on the transition root.
  Children keep their layout and native text rendering; no CanvasGroup is needed.
  The clip stays within its endpoints, including when the motion class overshoots.
- **`transform`** grows a clipping plate from a source rectangle in window
  coordinates and shrinks back to it on exit. Use a `canvasGroup` with
  `clipChildren = true`; text keeps its final layout and size. Optional
  `content` names a relative descendant CanvasGroup path to crossfade the
  contents separately from the plate. Motion is clamped to avoid overshoot.
  `UI.CollapsibleView` supplies source geometry, safe placement and focus.
- **`fromRect = { x, y, w, h }`** is a transform origin that cannot move: one
  rectangle, read when the transition starts.
- **`source = { path = "…" } | { rect = … }`** is a transform origin that
  **moves** — the shared-element form. `path` names a mounted node and Facet
  reads its painted rect; `rect` is a rect or a `Readable` of one. Either may be
  a `Readable`, and both are re-read on **every painted frame**, so the
  expansion follows a card that scrolls and collapses back onto wherever that
  card has reached. A source that stops painting keeps the last rectangle it
  gave rather than snapping. Declare `fromRect` or `source`, never both.
  The branch is laid out at its own full size throughout: the motion is
  paint-only, nothing reflows, and a reversal continues from the painted
  rectangle with its velocity intact. Under reduced motion it lands on the
  frame it starts.

```luau
local selected = Compose.cell(nil)
UI.When("Expand") {
    condition = function(use) return use(selected) ~= nil end,
    transition = { enter = "transform", source = { path = cardPath }, content = "Body" },
    thenView = Detail,
}
```
- **`pivot`** is where a scaling form (`materialize`) grows from: `"center"`
  (default) or `"topLeft"` | `"topRight"` | `"bottomLeft"` | `"bottomRight"`.
  An anchored surface with a scaling enter and no pivot of its own grows from
  the corner it hangs at, so a menu emerges from the control that opened it.
- **`class`** names a motion class (default `"container"`); **`fade = true`**
  pairs a slide with a transparency fade.
- **`exitClass`** names the motion class the *exit* runs on (default
  `"dismiss"`, the exit twin of `container`): closes read faster than opens by
  default — `dismiss` is ζ1.0 at a 0.2s response against `container`'s 0.35s,
  about 1.7x quicker, the transitions.dev 250/150ms pairing. Declare
  `exitClass = class` for a symmetric open/close feel, or a third class for a
  different one; the enter always spends `class` regardless.
- **`distance`** (px, slide forms only) overrides the
  themed travel default (`space.l`, a decorative nudge — right for a toast
  easing in from its own edge) with the surface's own full extent, for a slide
  that IS the surface leaving/entering the screen (a full-viewport push/pop).
  Omitted, every caller keeps the themed default unchanged.
- **`scale`** (`materialize` only) is `distance`'s twin for the
  scaling form: the scale the node starts from, default `0.96`. It exists
  because of a measured engine fact, not a taste — **Roblox rasterizes text at
  `floor(TextSize × effectiveScale)`**, so *any* `UIScale` below 1 paints every
  string under it one whole pixel smaller (20 px type renders at 19 for the
  whole of a `0.96 → 1` flight, at 0.9999999 exactly as at 0.96) and snaps ~5%
  larger the instant the scale reaches exactly 1 — a visible re-flow, and one
  that lands *after* the motion has stopped, because the channel holds its
  `UIScale` until the spring settles. A surface whose content is mostly type
  therefore declares a scale just **above** 1 and settles *down* into place:
  every value in `[1, 1 + 1/TextSize)` floors to the same pixel, so the text
  lands at its final size on the first painted frame and never moves.
  `UI.Alert` ships `1.015` for this reason: 1/0.015 = 66.7 px, above every
  size the framework paints **at the engine's four measured preferred-text steps
  (0/4/10/14 px) with `preferredTextSize = 1`** — the domain every shipped path
  takes, swept per package and per display class in `tests/transitions.spec.luau`,
  where the widest rung in the library is Glossy Mobile's `title` at a ten-foot
  display, 59 px. The FACTS are clamped wider than that (`preferredTextOffset` to
  `[0, 32]`, `preferredTextSize` to `[0.5, 3]`), and a fixture or device profile
  that drives either to its ceiling outgrows the fixed band; a surface in that
  position derives its own from the largest rung it paints. The second sweep in
  that file records the number such a derivation has to beat. `1` is refused — a
  form that starts at rest does not move. **It is the ENTER's band only**: an exit
  is the opposite instant — the plate is leaving and already fading — so the exit
  keeps the ratified `0.96` dip whatever the enter declared.
- **`stagger`** (a nonnegative number of **SECONDS**, enter only) is the beat
  between one entering row and the next, for a region whose children arrive
  together — a list that lands as one slab reads as a redraw, the same rows a
  beat apart read as a list. It is **inert outside a keyed `UI.ForEach`**: a
  `UI.When` branch is always alone in its own batch (there is nothing else
  entering beside it to wait for), so declaring `stagger` there costs nothing
  and does nothing. The batch is the rows of ONE `ForEach` entering in ONE
  frame, in list order; the accumulated **wait** stops growing after eight
  beats, so a 600-row list's last row enters with its ninth rather than half a
  minute later — that cap bounds the WAIT, **not the timer count**: every row
  past the eighth still books its own hold, the rows past the cap simply all
  book the *same* duration, so the cost stays the one a 600-row enter already
  pays in springs and nodes.
  **Exits never stagger** (a list leaving one row at a time is a stall), a
  re-entry mid-exit reverses immediately rather than waiting, and reduced motion
  lands every row on the first frame. **The unit is seconds, not milliseconds**
  — a spec written as if it were ms, such as `stagger = 500`, does not clamp or
  warn; it holds a row absent for minutes rather than the intended half-beat
  rhythm.
- **A fading form needs a fade group.** `fade`, `materialize` and
  `fade = true` drive transparency, so the region's child must EITHER be
  declared `UI.ZStack{ canvasGroup = true }` (or `UI.Box{ canvasGroup = true }`
  for a single plate) itself, OR contain exactly ONE such node in its own
  subtree (task POP). The second shape is how a backdrop plate stays
  OUTSIDE the fade: give the region's child an opaque background — a
  `surface` role, OR a `UI.Box`'s own `tint` (the same `BackgroundColor3`
  channel; a `tint` on any OTHER class colours a glyph/picture/stroke, never a
  plate, and is not covered by this rule at all) — and put its content one
  level in, inside its own `canvasGroup`. Position/scale still ride the whole
  card as one rigid unit (a plain `UIScale`/offset needs no group at all),
  while `GroupTransparency` is written to the inner group only, so the plate
  paints at its own, immediate opacity from the first frame instead of fading
  in lockstep with the text on it. Zero or more than one `canvasGroup`
  candidate in the subtree is an authoring error that names the fix, exactly
  as a bare non-group child always has been. **This is a construction rule,
  not an automatic repair**: a node that is ALREADY `canvasGroup = true`
  itself, with the opaque plate as its OWN direct child (rather than nested
  one level down inside a separate plate node), is a self-case Facet resolves
  to itself unchanged — the plate must be moved to a sibling and the content
  re-nested by hand; nothing in the framework rewrites an existing tree for
  you. `tests/backdrop_fade.spec.luau` is the headless gate that catches
  either shape (self-case or not) the moment its push transition first runs.
- **`presenter.surfaceIdNotes()`** returns the diagnostics for two surfaces that
  are **both up at once** under ONE blueprint id — every node path is rooted at
  that id, so the second surface takes over the first's paths in the adapter and
  the first can no longer be torn down by path. It is the COLLISION that is
  noted, never a repeat: dismiss a surface and present another under the same id
  and nothing is said, because only one of them is ever on the stack. A note,
  not a refusal, once per id per session; a copy, like every other diagnostic
  read.
- **`plate = "fades"`** is the one acknowledgement that rule takes: *this
  surface's plate is meant to fade with its content* — the modal/popover shape,
  whose backdrop is the **scrim behind the whole surface** rather than the
  card's own face. The rule in one line: **the plate IS the surface, and
  whatever is behind it is a scrim or nothing at all (a toast) — never
  separately-fading content.** `UI.Alert`, `UI.Menu`'s floating
  popover, the menu-style `Picker` and the presenter's own **toast layer**
  declare it (a toast body is its own plate with the live app behind it, which
  it never claimed to hide); nothing else needs to. Do NOT write it to
  silence a backdrop finding on a plate that sits behind separately-fading
  content: it is honoured only for a fade group whose **sole** child is the
  plate, so a plate with a sibling still reports exactly as before, and the
  acknowledged shape is still *recorded* (under its own kind) so a reader can
  see which surfaces made the claim.
- **A departing subtree RETIRES, it does not vanish.** It stays mounted in its
  slot (a `ForEach` row exits in place, clamped to its old index), turns
  **non-interactive** — focus order and tap routing both skip it and everything
  beneath it — and disposes when the exit completes. Re-entry mid-exit reuses
  the same mounted subtree: same node identity, same owners, same instances,
  no factory re-run.
- **Hard cap: 500 ms.** No exit may defer disposal beyond it, flat and
  non-overridable. It is measured in *clock* time, so it needs the clock
  stepped (`presenter.tick(dt)`).
- **Reduced motion** places instantly and fires the same events on the same
  frame — nothing is dropped, because the motion authority's own reduced-motion
  contract does the substituting.

### `ErrorBoundary`

`UI.ErrorBoundary{ id?, view (() -> Blueprint), fallback (err) -> Blueprint }`
— quarantines factory errors inside its subtree, at mount and during later
structural rebuilds, swapping to `fallback(err)` instead of taking the screen
down. Errors inside the fallback stay hard. See also
`presenter.presentCritical` for whole-screen fallbacks.

### `shadow`

`UI.shadow(blueprint, presetOrParams, style?) -> Blueprint` — modifier-style
modifier returning a NEW blueprint with an engine-true drop-shadow
declaration (backed by the engine's `UIShadow` instance on capable clients;
kept as pure style data headlessly). `presetOrParams` is a preset name from
the style's `shadows` table (`"raised"`, `"overlay"` in the default style) or
`{ blurRadius = {scale, offset}, color?, transparency?, offset?, spread?, zIndex?, enabled? }`.
Invariants: `blurRadius` is a UDim shape (scale = fraction of the parent's
shortest dimension, offset = px, both non-negative); `zIndex` must be
negative; shadows are purely visual and never affect layout. Applied to a
container it styles the container's own surface.

### `gradient`

`UI.gradient(blueprint, spec, style?) -> Blueprint` — a per-view colour wash,
rung 2 of the customization ladder
([guide §10.10](../guide/10-rich-skinning.md)). `spec` is
`{ colors, rotation?, transparency?, enabled? }`:

| Field | Meaning |
|---|---|
| `colors` | **2–3 stops**, required. Each is a colour token name resolved against the active style (`"accent"`, `"surfaceStrong"`, `"control"` — `colors` first, then `extra`) or an `{ r, g, b }` table. Positions are evenly spaced unless a stop says `{ t = …, color = … }`; the first must land on 0 and the last on 1, and they must ascend. |
| `rotation` | degrees, default **90** (top → bottom). `0` is left → right. |
| `transparency` | optional alpha ramp, same 2–3-stop shape. Every stop is capped at **0.9** — `UIGradient.Transparency` fades the parent's *entire* rendering, so a near-1 stop ghosts the node instead of softening the wash. A subtle ramp is 0.1–0.35. |
| `enabled` | default `true`. |

It follows `UI.shadow`'s architecture exactly: bounded normalized data under the
STYLE authority, materialized by the adapter as **one** bespoke `UIGradient`
child named `FacetGradient` — never a sheet rule, because a rule matches a
*class* of nodes and this one must win on exactly one. The child is reused, not
re-created, so a reactive gradient or a theme swap can never stack two ramps on
one node, and **the view's gradient survives a package swap** while the theme's
own gradients (phantom `::UIGradient` rules on `chromeGradient` slots) continue
to paint everywhere else.

Two refusals, both at construction:

- **a value control's own chrome** (`sliderTrack`, `sliderThumb`, `barTrack`,
  `barFill`) — the same ruling `themes.define` enforces on a theme's
  `chromeGradient`: a wash's alpha makes the node see-through and whatever the
  control draws behind it reads straight through the glass;
- **a text-bearing node** (`Text`, `Button`, `Toggle`, `TextField`) —
  `UIGradient` multiplies the node's own rendering including its engine-drawn
  glyphs, so the wash would darken the label with the fill. Put the gradient on
  the `UI.Box` behind the label; the error says so.

Gradients are purely visual and never affect layout.

**Composition with a skinned slot.** `UIGradient` multiplies the node's own
rendering and does not reach children, so a wash needs a fill to act on. Under a
package that skins that slot with art the node's own plate is already suppressed
(the image-is-the-element posture) and the decoration is a child — so the art
wins and the wash paints nothing. The child itself is unaffected: measured live
across three packages the same `FacetGradient` survived with identical stops and
was never duplicated. See [guide §10.10](../guide/10-rich-skinning.md).

### `corners`

`UI.corners(blueprint, spec, style?) -> Blueprint` — per-corner rounding
modifier. `spec` is a number (px), a radius token name (e.g. `"control"`),
`{ radius = n }`, or `{ topLeft?, topRight?, bottomLeft?, bottomRight? }`
(unset corners become explicit zeros). Exactly ONE form is emitted per node —
mixing `radius` with individual corners is a build error (the engine
misbehaves when the alias and per-corner properties mix).

### `stroke`

`UI.stroke(blueprint, { thickness?, color?, transparency? }, style?) -> Blueprint`
— an authored border, under the STYLE authority. Defaults are the theme's
hairline, so `UI.stroke(bp, {})` is exactly the hairline the adapter already draws
on a raised panel.

Every border Facet paints, authored or a theme's own hairline (raised, chip, a
field, the `utility` appearance), sits inside its node's box
(`BorderStrokePosition = Inner`), so a scroller's clip never cuts it. The node's
padding on each side is at least the stroke's thickness, so its content never
lies under the band; padding that is already wider is unchanged. Only a resting
stroke pays for padding: a bound `stroke` (a formula, such as a focus or hover
ring) is paint-only, so toggling it never re-solves layout.

| Field | Meaning |
|---|---|
| `thickness` | px, or a stroke token name (`"hairline"`). Default: the style's hairline weight. |
| `color` | a colour token name resolved against the active style (`colors` first, then `extra`), an `{ r, g, b }` table, or a `"#rrggbb"` literal. Default: the `hairline` role. |
| `transparency` | 0..1. Default: the style's hairline opacity. |

Architecture follows `UI.gradient` exactly: bounded normalized data, materialized
by the adapter as **one** bespoke `UIStroke` child named `FacetStroke` and
**reused**, never re-created — so a reactive pulse or a theme swap can never stack
two borders on one node — and destroyed when the declaration goes away.
`ApplyStrokeMode` is always `Border`, because the engine default (`Contextual`)
strokes a text node's *glyphs* instead of its box.

**It is additive, not a replacement.** A theme's own chrome stroke is a phantom
`::UIStroke` **rule**, and the engine renders a real `UIStroke` child alongside it
(measured live) — so an authored stroke composes with a panel's
hairline rather than suppressing it. A node that must show exactly one border
should name a surface that carries none (`plain`).

### `strokeData`

`UI.strokeData(spec, style?) -> StrokeData` — the same normalization as
`UI.stroke`, without a blueprint. It takes the identical
`{ thickness?, color?, transparency? }` spec (same defaults, same closed key set,
same refusals) and returns the normalized data table, so it is what you build a
**reactive** stroke out of.

Normalized style data is read once at construction, so a Compose readable *inside*
the spec is refused there and the error names this fix: bind the whole `stroke`
prop instead.

**A token survives normalization.** A radius or thickness written as a **name**
(`"pill"`, `"panel"`, `"hairline"`, or the absent thickness, whose default *is*
`strokes.hairline`) is resolved to a number here — against the style you passed,
or the library's own if you passed none — and the name is kept beside it under
`tokens`. The painter re-resolves it against the style the render target was
built with, which at the ten-foot display class is the derived one, so a capsule
authored in a control factory rounds by the same factor as everything else on a
television. A **literal** carries no token and never moves: 6 px is 6 px at every
distance. Consumers that only read the number (a lint, a dump, a test target)
keep reading exactly what they read before.

```luau
UI.Box {
    id = "Row",
    surface = "control",
    stroke = Compose.formula(function(use)
        return UI.strokeData({ thickness = 2, color = "accent", transparency = use(pulse) })
    end),
}
```

### `shadowData` / `gradientData` / `cornersData`

`UI.shadowData(spec, style?)`, `UI.gradientData(spec, style?)` and
`UI.cornersData(spec, style?)` complete the family: each is the normalizer its
modifier already uses (`UI.shadow` / `UI.gradient` / `UI.corners`), without a
blueprint, returning the normalized data table. Same specs, same defaults, same
closed key sets, same refusals — and the same reactive idiom as `strokeData`
above, so an animated blur, wash or radius is a **pulsing prop** rather than a
rebuilt blueprint:

```luau
UI.Box {
    id = "Card",
    surface = "raised",
    shadow = Compose.formula(function(use)
        return UI.shadowData({ blurRadius = { scale = 0, offset = use(lift) }, color = "shadow" })
    end),
}
```

`UI.gradientData` does not run `UI.gradient`'s text-bearing wall, because there
is no blueprint here to judge; the wall still applies wherever the data is bound.

### `draggable` / `dropTarget`

`UI.draggable(blueprint, spec) -> Blueprint` and
`UI.dropTarget(blueprint, spec) -> Blueprint` — the public drag/drop contract
(rows SF-D1/SF-D5). They are **declarations**, not wiring:
each returns a new frozen blueprint carrying a validated declaration on the
metadata channel, and the renderer builds the acquisition when the node mounts.
The same declaration therefore works on a node an author wrote and a row a
control generated.

A declaration on a **layout-only container** (`VStack`, `HStack`, `ZStack`,
`Grid`, `Anchor`, `Spacer`) is honoured. Such a node is normally *elided* — it
gets a render handle and no engine object, because most of them paint nothing —
and a drag declaration, pointer handlers or a hit rect materialize it on demand.
There is no need to wrap a draggable stack in a `Box` to give it something to
acquire.

Both **refuse a structural region** (`When`, `ForEach`, `ErrorBoundary`) at
attach time, naming the fix: a structural node never reaches the renderer's
per-instance registration, so the declaration would have been accepted and inert
— the plausible mistake being to wrap a conditional card rather than the card.

```lua
local card = UI.draggable(UI.Box({ id = "Card", surface = "control" }), {
    payload = { kind = "sponsor", id = 7 },
})

local slot = UI.dropTarget(UI.Box({ id = "Slot", surface = "surface" }), {
    accepts = function(payload)
        if payload.kind ~= "sponsor" then return false, "WRONG_KIND" end
        return true
    end,
    onDrop = function(payload, info) place(payload, info.targetId) end,
})
```

**`UI.draggable` spec**

| Field | Meaning |
|---|---|
| `payload` | required. The opaque value every drop target is handed. A **function** is called once at pickup with the source path, so one authored row template gives every mounted row its own payload. |
| `dragMotion` | motion class name for the pickup scale and the return flight. Default `"object"`; resolved (and refused if unknown) at **declaration** time, never mid-gesture. |
| `proxy` | `() -> Blueprint` — the ghost. Absent = the presentation layer's default ghost of the source. |
| `onCommitProxy` | `"destroy"` (default) or `"flyToTarget"` (an `object`-class flight chasing the live target, `land` on arrival). |
| `grabAnchor` | `"center"` (default — the ghost rides **centered under the pointer**, the RascalRally-ratified feel) or `"preserve"` (keep the grab-point offset; for large surfaces where a snap-to-center would visibly jump). |
| `armStaging` | `() -> { x, y }?` — **park the armed ghost.** By default an armed ghost *rides the aim*: `armTo` springs it onto the target being aimed at, so a pad/keyboard pickup is visibly different from no pickup. Declare this and the ghost springs once, at the **pickup**, to the window-space point returned and stays there while the aim moves — a fixed staging spot, with the aim carried by the target's own paint (the shape a card game wants: the held card must never sit on the name it is about to be played on). Aim, verdict and the commit flight are untouched either way; `nil` for a frame keeps the current spot. |
| `armOnTap` | a **tap on this source IS the pickup**: the framework arms an `"armed"`-mode session instead of dispatching Activate — the touch answer to gamepad's arm-on-A. One-thumb mobile flow: tap a card, scroll the list freely (a swipe is past the tap threshold, so it can never read as a drop), tap a row to place it; a tap while something is already held flows to `onActivate` unchanged (put-back and row commits keep their meaning). Press-and-slide still starts a real drag. Default `false`: what a tap *means* is the consumer's call. |
| `declineTouch` | touch presses **decline the capture** so a native scroll host under this node keeps the pan — and, on an engine with its own drag acquisition, decline that too. Pointer/pen acquisition is unaffected. **Reach for it rarely.** It is no longer the posture a draggable thing inside a scroller needs: a finger now arms a drag by *holding still* (`interactionTokens.touchDragArm`), so a flick reaches the scroller and a hold reaches the drag without either being declared away. Declare it when this node must *never* be dragged by a finger, not merely when something scrolls underneath it. |
| `promotionPx` | per-class overrides for the promotion gate (`{ pointer = 8 }`); absent keys fall through to `interactionTokens`. |
| `enabled` | a boolean, or a Compose readable of one, gating **acquisition only**. While it reads false this source arms nothing and promotes nothing, and the node stays enabled, hit-testable and activatable — which is what a control that must *explain* why it cannot be picked up needs ("disabled stays inspectable"). Setting `enabled = false` on the node itself also refuses acquisition, and additionally kills the tap, so it cannot serve that case. |

**The held source empties — a framework guarantee.** While a live session
carries a node's payload (pointer drag or the armed paradigm alike), the
framework stamps that node with the `dragHeld` state: the registry publishes it,
the renderer writes it, and every theme's sheet empties the node's label through
the `facet-drag-held` rule ("the slot sits empty until it lands or returns").
It clears when the drop **lands** or when the return flight **arrives** — the
arrival, not the release frame — and the return flight's arrival is itself
announced on the feedback bus as `arrive` with `context.returned = true`. No
consumer writes any of this; it cannot be authored, which is what makes it
universal.

**`UI.dropTarget` spec** — `accepts(payload) -> (legal, reason?)` (absent =
accepts everything), `onDrop(payload, info)` (required; `info` carries
`targetId`, `source`, `mode`, `velocity`), and the optional `onEnter(payload)` /
`onLeave(payload)`, which fire **exactly once per boundary**.

**Legality is always the game's.** `accepts` is the only place a rule enters, and
its `reason` code comes back out through the `reject` event — a refusal is never
silent. Facet never invents legality, and there is exactly one legality path for
pointer, touch, keyboard and gamepad.

**Reachability.** Pointer and touch acquire by press-and-travel (the shared
promotion tokens below); keyboard and gamepad drive the identical session through
`arm → navigate → commit/cancel` on the surface's drag registry. Release under
the promotion gate stays a **tap** — Activate fires normally, taps are never
eaten.

### `sensoryFeedback`

`UI.sensoryFeedback(blueprint, spec) -> Blueprint` — one modifier, **two spec
forms**, discriminated by key set and never mixed. Both name a **semantic verb**
from one closed vocabulary, and neither plays anything.

**Form 1 — the change form**, `{ trigger, event }`. When the `trigger`
Readable **changes**, the
framework emits `{ type = event, path = <this node's mounted path>, surface =
<the surface> }` on the presenter's feedback bus, synchronously, inside the write
that moved it.

**Form 2 — the control form**, `{ activation }`. It names
what **this control's own press** means, and the presenter emits that verb in
place of the `activate` it would otherwise emit, stamped `reason = "activation"`.

| Field | Meaning |
|---|---|
| `trigger` | change form, required. A Compose readable. Its **transitions** are the cause; the value itself never reaches the event. A plain value is refused — it can never change, so the declaration would be accepted and inert. |
| `event` | change form, required. One of the closed twelve: `activate`, `select`, `adjust`, `pickup`, `commit`, `reject`, `cancel`, `arrive`, `land`, `dismiss`, `supersede`, `celebrate`. Anything else is an authoring error at the call site that lists the vocabulary. |
| `activation` | control form, required. One of the same twelve, **plus `"none"`** for a control that is deliberately unfelt (it emits nothing at all rather than a verb every subscriber must know to ignore). |

Passing keys from both forms in one spec is refused: two causes and one verb has
no honest reading. Declaring `activation` twice on one node is refused too — a
control has one activation sensation, and a silent last-writer-wins would make
the two orderings of the same two modifiers produce different results.

**Facet plays nothing.** This modifier names a verb, not a device effect, and
whether that verb becomes a rumble, a sound, a particle or nothing at all is
the subscriber's ruling (`presenter.onFeedback` / `handle.onFeedback`).
`src/client/haptics.luau` is one opt-in, default-off subscriber — see
[Client entry points](#client-entry-points).

**The control form CASCADES.** It is resolved down the mounted tree, nearest
declaration winning, which is what lets it reach the composite controls
(`UI.Chip`, `UI.Stepper`, `Table` rows, `UI.PopupButton` …) that build their own
inner `Button`. Declare it on a container and every control inside inherits it,
however deeply nested and however late the row was mounted:

```lua
-- one button
UI.sensoryFeedback(UI.Button({ id = "Buy", label = "Buy" }), { activation = "commit" })

-- ...or a whole panel, including every composite inside it
UI.sensoryFeedback(UI.VStack({ id = "Filters", children = chips }), { activation = "select" })

-- ...and a control that must be felt as nothing
UI.sensoryFeedback(UI.Button({ id = "Info", label = "?" }), { activation = "none" })
```

```lua
local hearts = Compose.cell(3)

local heart = UI.sensoryFeedback(
    UI.Text({ id = "Hearts", text = Compose.formula(function(use) return `{use(hearts)} ♥` end) }),
    { trigger = hearts, event = "adjust" }
)
```

Like the drag declarations it rides the metadata channel rather than the prop
bag, it returns a **new frozen blueprint**, and it **refuses a structural region**
(`When`, `ForEach`, `ErrorBoundary`) — those mount no node of their own, so the
declaration would have been accepted and never emitted. It **composes**: applying
it twice to one node declares two triggers, and both fire.

The change form's observer is owned by the mounted node's Compose owner, so it
stops the frame the node unmounts, and it is built **only** when a presentation
layer is wired — a surface with no feedback sink buys no observer at all. The
control form buys **no observer**: its cause is a press, which the presenter
already owns, and a tree that declares nothing carries no extra field on any node.

The control form also reaches the **engine**: the renderer publishes each
activatable control's resolved verb to the adapter, which the Roblox target
realizes as a `Facet_ActivationFeedback` attribute, and the opt-in haptics
adapter hands that button the effect its verb maps to. So a Buy button and a
Cancel button feel different — and Facet still never calls `Play()` for a press.

### Layout modifiers: `frame`, `padding`, `offset`, `aspectRatio`, `alignment`, `overlay`, `background`

Composable modifiers (A-LV2). Each returns a **new** blueprint — blueprints are
frozen, so nothing is mutated — and writes only properties the schema already
declares, which means construction validation, dirty classification and the
property-authority manifest all still apply. A modifier can never silently claim a
value another subsystem owns.

**Order is the reading order**, because each is a function call, and the **last
writer of a property wins**: `UI.frame(UI.frame(bp, { width = 50 }), { width = 90 })`
is 90 px wide.

| Modifier | Signature | Effect |
|---|---|---|
| `frame` | `UI.frame(bp, spec)` | exact `width`/`height`, or a `minWidth`/`idealWidth`/`maxWidth` band (same for height). `maxWidth = "infinity"` is the fill idiom. An unknown field in `spec` is an error, not a no-op. |
| `padding` | `UI.padding(bp, sides)` | inner spacing; `sides` is a number or `{top?,right?,bottom?,left?}`. Valid on containers, `Button`/`Toggle`/`TextField`, and `Text` (whose measure adds it). On any other class it errors and tells you to wrap the node — it never silently does nothing. |
| `offset` | `UI.offset(bp, x?, y?)` | arrange-only placement offset (no re-measure); meaningful for a child of `UI.Anchor` |
| `aspectRatio` | `UI.aspectRatio(bp, ratio)` | derives the height from the resolved width (16:9 media). A non-positive ratio is an error. |
| `alignment` | `UI.alignment(bp, horizontal?, vertical?)` | placement inside a `ZStack` parent |
| `overlay` | `UI.overlay(bp, content, align?)` | layers `content` **above** `bp` |
| `background` | `UI.background(bp, content, align?)` | layers `content` **behind** `bp` |
| `badged` | `UI.badged(bp, value, direction?)` | a count or dot seal on `bp`'s top corner (see `UI.Badge`) |

`overlay` and `background` are the only two that change **structure** — a layered
pair is a `ZStack` — so they need the base to carry an explicit `id`. The wrapper
takes a derived id and the base keeps its own, so the base stays addressable by
focus, tests and dumps at `<parent>/<id>+overlay/<id>`.

### Dim-shape shorthands: `fill`, `hug`

Not blueprint modifiers like the family above — no `bp` argument, and no
frozen-blueprint rewrite. Both are plain **value producers**: they return the
same dim table a `width`/`height` prop already accepted written by hand,
because that raw table (`{ type = "fill", weight = 1 }` above all — written
326 times across the reference corpus with no name for it, framework-gaps-
phase2 audit in-brief item 14) is authored on ONE axis at a time, exactly
where these go: `width = UI.fill()`.

| Shorthand | Signature | Equivalent to |
|---|---|---|
| `fill` | `UI.fill(weight?)` | `{ type = "fill", weight = weight or 1 }`. `weight` must be a positive number when given |
| `hug` | `UI.hug(bounds?)` | `{ type = "hug", min = bounds?.min, max = bounds?.max }`. `UI.hug()` alone is the bare, unbounded form |

### `containerRelativeFrame`

`UI.containerRelativeFrame(bp, spec) -> Blueprint` — size one axis against the
nearest **container**, not against the parent.

```lua
UI.containerRelativeFrame(card, { axis = "horizontal", fraction = 0.5 })
UI.containerRelativeFrame(page, { axis = "horizontal", count = 3, span = 1, spacing = 8 })
```

**The whole distinction is the ruler.** `percent` already means "a fraction of
what my parent offered me", and that is the wrong number for the two shapes this
exists for: a card that should be half the SCROLLER's viewport however many
wrappers sit between it and the scroller, and a carousel whose pages are exactly a
third of the viewport each. The container is the nearest ancestor that owns a
viewport — a `UI.ScrollView`'s content viewport, else the surface root — so
inserting a padded `VStack` between the page and the scroller does not resize the
page, which with `percent` it would.

Two forms, and exactly one of them per call:

| Form | Fields | Size |
|---|---|---|
| fractional | `{ axis, fraction }` | `fraction × container` |
| paging | `{ axis, count, span? = 1, spacing? = 0 }` | `(viewport − spacing × (count − 1)) / count × span + spacing × (span − 1)` |

`axis` is `"horizontal"` or `"vertical"`. `count` and `span` must be whole
positive numbers and `span` may not exceed `count`; `spacing` is a px number (it
is the gutter between PAGES — the author's own paging arithmetic, not a
theme-owned space step) and may be zero or negative. Declaring both forms, or
neither, is an error at the call site, and the key set is closed, so a misspelled
`fractoin` is an error rather than a silent full-width box.

It writes the `containerRelative` **dimension type** onto the mapped axis prop, so
it inherits dim validation and every layout rule a dimension already has. Authored
by hand the dim is legal; the modifier is what carries the closed-key refusals.

**An unbounded container** — a scroller nested inside another scroller's own axis,
where the inner one never received a viewport offer — files a diagnostic on
`controller.diagnostics()` and falls back to content, which is exactly what
`percent` does on an unbounded axis.

### `styleGroup`

`UI.styleGroup({ shadow?, gradient?, corners?, stroke? }, blueprints, style?) -> { Blueprint }` —
applies the modifier set to EVERY element of a collection; returns the new
array (use as a `children` list). All four style
modifiers are members, and the spec's key set is closed: an unknown key is a
construction error naming the four, rather than a style that silently never
appears. Spec-first is deliberate — the collection is the thing being produced
(constitution E-3).

---

### `UI.AsyncImage`

`UI.AsyncImage { provider, key, id?, width?, height?, failureLabel?, retry?,
dimmed?, scaleMode?, tileSize?, sliceCenter?, sliceScale?, resample?, ref? }` — or `UI.AsyncImage("Id") { … }` — an image whose content
arrives through the async resource provider (native-substrate NS-A14). It
returns the control's node: a `ZStack` that shows a placeholder surface while
`pending`, the fetched content when `ready`, and a visible failure mark when
`failed`. `provider` and `key` are required; `key` is a content string.
`width` and `height` default to the `controls.image.defaultSize` theme metric,
so an icon-scale change reaches every async image with no consumer edit.

**`ref` hands back the control's record**, frozen, as `{ api, dump }`. This
control publishes no verbs, so `api` is its own record — `api.state` is the
provider's readable and `api.handle` is the lease — and `dump` is nil.

```luau
local provider, release = app.newResourceProvider()
app.mount(function()
    return UI.Screen {
        UI.AsyncImage("Face") {
            provider = provider,
            key = "rbxthumb://type=AvatarHeadShot&id=156&w=48&h=48",
        },
    }
end)
```

`retry` passes a per-call-site retry policy (`{ count, delaySeconds?, giveUp? }`)
straight through to `provider.acquire` — an avatar in a results list can afford
two spaced attempts where a decorative badge cannot. **Failure stays silent**
either way: the placeholder persists, and there is never a spinner or a
broken-image glyph.

`dimmed` (a boolean, or a Compose readable of one) applies the dim treatment: the image blends 35 %
toward the `surface` role through the authored `tint` channel — themable,
contrast-checkable at both ends, and no contest with native-sheet paint. The
undimmed value is the same tint at blend 0, so toggling the state never adds or
removes a paint claim mid-life; an image that declares no `dimmed` carries no
`tint` at all.
The provider handle is owned by the control's own Compose owner and released
when the node unmounts. Releasing it makes any late completion STALE (never
applied) and prevents queued-unstarted work — it does NOT stop an in-flight
engine fetch, because Roblox exposes no cancellation. The Roblox transport is
`src/client/roblox_resources.luau` (`bind(provider) -> unbind`), which fulfils
requests via `ContentProvider:PreloadAsync` per-asset statuses.

### `specGuard`

`Facet.specGuard` — the closed-key-set guard the framework's own controls use
(`src/spec_guard.luau`), exported so an out-of-repo control can meet the
[constitution](constitution.md) §4 strictness rule with the same implementation
rather than its own. It requires nothing, so it is safe from any layer.

- `specGuard.keySet(names: { string }) -> KeySet` — a frozen `{ [name]: true }`
  set from an array. Build it once at module level; the sorted list an error
  prints is derived from it.
- `specGuard.assertKnownKeys(where: string, tbl: any, known: KeySet, kind: string)`
  — throws on the first key not in `known`. `where` is the PUBLIC name of your
  boundary as the author typed it (`"UI.Gauge"`, not an internal module path), so
  the error is greppable from the call site; `kind` is `"spec"` or `"opts"`, so
  the sentence reads the way your API does. A close miss gets a "Did you mean"
  (distance ≤ 2, case-sensitive) and the error always names the whole legal set —
  a closed set is only useful if the error tells you what it is.
- `specGuard.keyFunction(where: string, key: any) -> (item) -> string` — the one
  `key` rule every keyed collection uses. A function passes through; a string is
  the NAME of the field holding the identity, read as `tostring(item[field])`,
  because a key is a path segment. Anything else throws, naming `where` and both
  accepted spellings.

```luau
local SPEC_KEYS = Facet.specGuard.keySet({ "id", "value", "onChange" })

function gauge.build(library, core, spec)
    Facet.specGuard.assertKnownKeys("UI.Gauge", spec, SPEC_KEYS, "spec")
    -- ...
end
```

`docs/extending/new-control.md` walks the rest of the playbook.

`UI.AsyncImage` forwards `scaleMode`, `tileSize`, `sliceCenter`, `sliceScale`
and `resample` to its owned Image. The same mode/geometry pairing and binding
rules apply; provider lifetime and the ready/pending/failed states are unchanged.

### `pathShapes`

`Facet.pathShapes` — pure, headlessly-tested shape math for `UI.Path`
(`src/controls/path_shapes.luau`). Three generators and one limit:

- `pathShapes.arc(startDeg, sweepDeg, { segments?, radius? })` — a circular arc.
- `pathShapes.ring({ radius? })` — the closed circle, as four exact quadrants.
- `pathShapes.needle(angleDeg, { innerRadius?, radius? })` — the gauge pointer:
  a single radial segment from `innerRadius` to `radius` at `angleDeg`.
- `pathShapes.MAX_CONTROL_POINTS` — the engine's own `Path2D` ceiling (100).
  Every generator asserts against it rather than letting the engine truncate, so
  a segment count that cannot be drawn is refused where it is authored.

All three return normalized control points (unit box; tangents relative to each
point; exact circular-arc bezier handles). Angles are screen-clockwise with 0°
at 12 o'clock.

### `richText`

`Facet.richText.escape(s) -> string` escapes `< > & " '` before composing text
into `UI.Text { rich = true }` markup. Escape player names and server strings at
the composition site; ordinary text is unchanged. This is not player-text
filtering: the game still uses the platform's filtering rules.

```lua
UI.Text { rich = true, text = "<b>" .. Facet.richText.escape(playerName) .. "</b> wins" }
```

### `recipes`

`Facet.recipes` holds compositions a caller opts into in one line rather than
keys every control carries. `Facet.recipes.arithmetic.parse(text) -> number?`
is a pure four-operator parser for a `UI.NumberInput`'s `parse`, so `3 + 5`
commits as 8. It reads `+ - * /`, parentheses, the typographic `×`, `÷` and
`−`, and the numeric field's strict decimal grammar; it answers `nil` for
malformed text, division by zero, a non-finite result, more than 256 bytes or
more than 32 levels of nesting (a run of signs counts). It parses and never
compiles or runs the text. Whether a field accepts arithmetic is a product
decision, which is why this is a recipe and not a key.

```lua
UI.NumberInput("Fee")({ value = draft, numericValue = fee, parse = Facet.recipes.arithmetic.parse })
```

### Engine-selection bridge (a presentModal opt)

`app.presentModal(component, { engineSelectionBridge = true })` — opt-in mirror
of Facet's logical focus to `GuiService.SelectedObject` while the modal owns UI
input (native-substrate NS-A12). Modal-only: `app.mount` ignores the opt, so
passive/gameplay surfaces always keep `SelectedObject = nil` (NS-A11). The
mirrored instance is made `Selectable` only while selected (the engine warns
and reassigns selection set on a non-selectable object — measured); expect
native autoscroll inside scroll hosts; the bridge clears on dismiss/teardown.
EXPERIMENT until the physical-gamepad row (ledger NS-P1) closes — Facet's
focus graph remains the authority and every surface works with the bridge off.

## Mounting and rendering

### Mounting (internal)

Mounting is internal. The public seam is the application:

```lua
local app = Facet.new()
local UI = app.controls

local close, node, handle = app.mount(function()
	return UI.Screen("S")({ padding = "m", UI.Text({ text = "Hello" }) })
end)
```

| Application call | What it mounts |
|---|---|
| `app.mount(component, options?)` | a base screen; returns `close, node, handle` |
| `app.presentModal(component, options?)` | the same tree as a modal; returns `close, node, handle` |
| `app.presentAnchored(component, options)` | a panel placed against a source rect; returns `close, node`. The builder receives `app.controls` |
| `app.presentToast(component, options)` | a toast body inside the toast layer's own row; returns `{ id, dismiss() }` |
| `app.presentSnackbar(spec)` | the `UI.Snackbar` spec without a component, on the same service; returns an idempotent release function |

`close()` is idempotent: it dismisses that surface and releases the component's
resources. `app.dispose()` closes every surface that is still open.

**What happens underneath.** Facet has no mount module of its own. Compose's
runtime does the mounting, into a Facet *domain target*
(`src/render/compose_scene.luau`): `runtime.mount(component, target)` runs the
component once, Compose owns the node lifetime, the bindings and every
structural operation, and Facet's render host owns validation, identity,
inherited styling and renderer invalidation. A surface needs **exactly one**
root node; a target holding none or more than one is refused.

`domain.root(target, stop)` wraps the target as the **mounted root** the
presenter and the renderer read:

| Member | Answers |
|---|---|
| `.node` | the root domain node |
| `.takeDirty()` | drain the pending update queue |
| `.dirtySeq()` / `.dirtySince(seq)` | the journal's sequence, and the entries since one |
| `.counters()` | `{ mounted, factoryRuns }` |
| `.setFeedback(sink, observe?)` | where this surface's sensory declarations report |
| `.dispose()` | release the mount |

Properties reach a node through the blueprint schema, never around it: an
unknown property, a refused one, or a value the schema rejects errors at the
node, naming the mounted path.

**Structural transitions are bound, not passed.** Every presented surface builds
its own coordinator (`src/render/transitions.luau`), and
`transitions.bind(rootNode, coordinator)` hangs it on the mounted tree's
journal, so a region that mounts later still reaches it. The coordinator's verbs
are `shouldRetire(path, node) -> spec?` (nil = dispose now),
`beginExit(path, node, spec, done)`, `cancelExit(path)` (an exit that is no
longer wanted — the enter that follows reverses from the value *and* velocity it
parks at), `beginEnter(path, node, spec)` and `release(path)` (the region is
being torn down; drop any motion for that path). `src/render/region_transitions.luau`
is what calls them for a `UI.When` / `UI.ForEach` region. The mount layer owns
lifetime and identity; the coordinator owns time — which is why the 0.5 s exit
cap (`Facet.EXIT_CAP_SECONDS`) lives in the coordinator and not here.

**The per-application services** (`src/core/services.luau`) are what the mount
sits on: the Compose runtime, a root owner, an error boundary, and the layout
settle pass.

- **Error containment.** A binding or a watch body that throws is caught by the
  boundary, the last valid value stays painted, and the failure is reported
  through the services' reporter — a `warn()` by default. `core.lastError()`
  reads it back. It is **sticky**: nil until the first contained failure and
  never cleared, so it says "something was contained in this application's
  life", not "this application is unhealthy now".
- **The layout settle pass** (`src/render/settle_pass.luau`) drives geometry
  feedback to a fixed point **inside the flush that opened it**, so a top-level
  `env:set` returns with the surface solved rather than one frame behind. After
  a drain it runs every registered callback in **registration order**; a
  callback that writes ends that pass, propagation drains, and the pass restarts
  from the first callback, so every callback observes every other one's
  publication. Passes repeat until one writes nothing. A callback must therefore
  be cheap and idempotent when it has nothing to do. At **100** passes the pass
  stops, the repeat offender is quarantined until it is re-registered, and the
  failure goes to the reporter — a cycle that will not converge is a loud error,
  never a hang and never a silent frame.

### `renderer`

`Facet.renderer` is a namespace, not a factory: it carries the attach verb
**and** the adapter-conformance data an adapter author writes against
(constitution E-10 — `attach` is not `newRenderer` because the controller's
lifetime is the mount's, not the module's).

**Module exports**

| Export | What it is |
|---|---|
| `renderer.attach(core, mountedRoot, env, adapter, opts?) -> Controller` | bind a controller to a mounted root (below). `core` is the per-application service bag from `src/core/services.luau`; `client.host.new()` hands it back as `host.core` |
| `renderer.EMITTED_PROPS` | frozen set of **every** prop name this module can hand to `adapter.setProp`. This is the conformance list a render target implements against, and `tests/render_target_contract.spec.luau` fails when the live and fake adapters disagree with it |
| `renderer.DIRECT_PROPS` | frozen `prop -> which seam writes it`, for the writes that do not ride the style or binding channel (`clipChildren`, `textSize`, `padding`, `transform`, `transparency`) |
| `renderer.STYLE_PROPS` / `renderer.BINDING_PROPS` | the two channel sets, keyed by prop name: which writes are style authority and which are binding authority |
| `renderer.compactForm(props) -> form?` | pure: the normalized compact representation of a `Button`'s `compactLabel` (`{ kind = "text" \| "icon" \| "image", … }`, `nil` when none). The one place the authored grammar becomes a shape, shared by the measure seam, the paint seam and the adapter |
| `renderer.drawnButtonText(props, compact?) -> string` | pure: what a `Button`'s own engine text node actually shows (empty for a content button; the framework's ASCII-safe glyph for an icon button) |

**`attach` options** — `{ rootPolicy?, reserveAppChrome?, edgeFloor?, onNodeTap?,
engineSelectionBridge?, onDiscloseHover?, onDiscloseLongPress?, recycleInstances?,
incrementalLayout?, measureReuse?, layoutNodeReuse?, commitScope?, structuralReuse?,
translateHosts?, clock? }`
(`recycleInstances` and `incrementalLayout` are the two performance opts described
under the presentation options below, both on by default; a presented surface
forwards its own).
`clock` is the motion clock used by declarative `animation` policies. The presenter
passes its shared clock automatically; a bare renderer consumer supplies one.

The last five are **test seams rather than tuning knobs**, all five default **true**,
and none is forwarded by a presentation — a presented surface always gets the default.
Each turns off exactly one cross-solve mechanism and leaves the other three intact,
which is what lets a differential oracle attribute a divergence to ONE of them instead
of to "the reuse machinery"; that attribution is the standing requirement on this
family (`tests/measure_reuse.spec.luau` and its sibling files each run their cases
against these arms). Off is always the older, slower, more conservative path — every
one of them can only avoid work, never change what is on screen — so setting one in
production code buys nothing but a slower frame.

- **`measureReuse`** — the cross-solve MEASURE store (`src/layout/measure_reuse.luau`):
  a per-node slate of measured sizes that outlives the solve, so a subtree nothing
  dirtied is not re-measured. Off, every solve measures the whole tree again.
- **`layoutNodeReuse`** — the cross-solve LAYOUT-NODE store
  (`src/render/layout_node.luau`): the solver's node tree is patched rather than
  rebuilt from the mounted tree. Off, every solve rebuilds every node. It is also the
  store whose identity keeps `measureReuse`'s slate meaningful, so the two are usually
  turned off together in a differential.
- **`commitScope`** — the COMMIT-side prune (`src/render/commit_walks.luau`): the
  post-solve walks (visibility, hit rects, z-order, transforms, text verdicts) visit
  the nodes the solve touched instead of the whole tree. Off, every walk visits every
  node, which is what the pruned counts are measured against.
- **`structuralReuse`** — BOUNDARY-ROOTED STRUCTURAL SOLVES
  (`src/render/structural_scope.luau`): an add, a remove or a reorder re-solves from
  the nearest absorbing ancestor instead of throwing the whole solve away. Off,
  a structural change takes a full solve — the arm the boundary-rooted one is
  compared against.
- **`translateHosts`** — the COORDINATE-SPACE HOST trigger
  (`src/render/instance_boundary.luau`): a container whose `offsetX`/`offsetY`/`anchor`
  is reactive and that has children becomes a real engine parent AND the origin its
  subtree's rects are stored against, so moving it costs one stored rect and one engine
  write instead of one per descendant. Off, no such host is registered, every rect is
  stored in window space and the tree is what it was before the trigger existed — which
  is the arm `tests/host_space_oracle.spec.luau` compares every public read against.
`rootPolicy` is the surface's content-rect policy (`"coreSafeContent"` default,
`"deviceSafeContent"`, `"bandSafeContent"`, `"edgeToEdge"`; an unknown value
errors and lists the set). `reserveAppChrome` (default **true**) is whether this
surface sits inside the host app's own chrome: a content policy adds
`appChromeInsets` to whatever it already reserved, and the presenter sets this
false for `presentModal`/`presentCritical` — a modal takes the screen, so it
honours the device safe area alone. It is meaningless under `edgeToEdge` (no
insets at all) and under `bandSafeContent` (which consumes the app's chrome per
column, through `platformChrome.rects`). `edgeFloor` is the opt-in edge-padding
knob (a number or a theme metric name) described under the presentation options'
own `rootPolicy` section — illegal together with `rootPolicy = "edgeToEdge"`.
**`onNodeTap(path, meta)` takes two arguments** — `meta` carries the tap
geometry (`x`/`y`) the outside-tap policy reads, and `via` for a
detector-driven tap. **`engineSelectionBridge`** is the same opt-in mirror
`presentModal` exposes, available here for a hand-attached surface.
**`onDiscloseHover(path?)` / `onDiscloseLongPress(path?)`** (Step 8.5) receive
the live adapter's disclosure engagement zones on `disclose` text nodes —
`path` on engage, `nil` on disengage; the presenter routes them to its
`_discloseHover`/`_discloseLongPress` seams. Omit both on a hand-attached
surface and no zones are wired (focus-driven disclosure still works).

**Controller** — every member is dot-called:

| Group | Members |
|---|---|
| Render cycle | `initialRender()`, `refresh()`, `dispose()` |
| Geometry reads | `rectOf(path)` (solved), `screenRectOf(path, relativeTo?)` (painted — see "Two rect reads"), `hiddenRoots()`, `compositionAt(path?)`, `textAt(path?)` (the per-text-node facts of the last solve: font, size, lines, naturalLines, truncated, disclose, reveal, naturalWidth, policy — the channel the disclosure plate and the auto reveal both read), `structureEpoch()` (a monotonic counter bumped by exactly the two things that change what a tree derives to — a structural sync, and a change in which roots are hidden — so a caller can cache a derivation on it instead of redoing it every frame, which is what the presenter's focus map does), `mountedPathOf(declaredPath)` (a node's own LIVE mounted path — see "A node hands back its own mounted path") |
| Focus | `setFocusPath(path?, visible?)` |
| Scrolling | `scrollTo(path, {x,y})`, `scrollPosition(path)`, `scrollToVisible(path, localRect?)`, `scrollHostFor(path, includeSelf?)` (the nearest `ScrollView` ancestor's handle — reach for this instead of re-deriving the host), `scrollBarInsetOf(path)` (the scrollbar gutter that host reserved on its last solve — `{ right, bottom }`, `right` for a Y scroller and `bottom` for an X one, or **nil** when it reserved none; for a node that must line up ACROSS a scroll boundary while living outside the subtree, which is the case `UI.Table`'s header is — do NOT derive it from `adapter.scrollBarThickness`, that is what a bar *would* take, not what this host took), `observeScroll(path, fn) -> unsubscribe`, `stepAutoscroll(dt?)`, `setPointerDrag(info?)` |
| Drag | `dragRegistry()` (builds one on demand), `peekDragRegistry()` (nil when none exists yet), `setDragCollaborators(collaborators)`, `attachDragDetector(path, handlers) -> detach?` |
| Presentation channel | `setPresentationTransform(path, t?)`, `setPresentationTransparency(path, alpha?)`, `setPresentationOffset(dy)`, `setPaintHeld(path, held)` (hold a node's own paint while something is painted over it — the auto reveal's strip is the framework's only caller; the solve, the rects and the truncation facts are untouched, and the hold survives a re-solve and a remount of that path) |
| Engine content | `stageHost(path)` — the `UI.Stage` seam, nil on an adapter without it (see [The content seam](#the-content-seam-controllerstagehostpath)) |
| Foreign content | `foreignHost(path)` — the `UI.Foreign` seam, nil on an adapter without it (see [The content seam](#the-content-seam-controllerforeignhostpath)) |
| `withAnimation` seams | `armAnimation(session)`, `disarmAnimation()` — armed by `presenter.withAnimation` for exactly one commit, which is why an ordinary refresh installs no records — and `animationRecordCount()`, the diagnostic behind `presenter.animationRecordCount()` |
| Surface | `setDisplayOrder(n)`, `setRootVisible(visible) -> boolean`, `coverRect()` (what this surface actually PAINTS — the union of every painted box below its root, or `nil` when it paints nothing; the root's own rect is excluded because a `Screen`'s rect is the content rect its `rootPolicy` resolved, the same box for every base screen on the device), `retireSurface()` (this stops being a surface NOW, whatever is still on screen — `presenter.dismiss` calls it, because a dismissed surface keeps painting until its exit transition finishes) |
| Diagnostics | `stats()`, `diagnostics()`, `textPending()`, `analyzeBoundaries()` (re-solves the last tree with boundary detection on and reports how much a boundary-aware layout would have had to redo; it changes nothing and runs only when called) |

#### Findings that are not defects

`controller.diagnostics()` returns a list of `{ node, issue }`. Almost every
entry describes something nobody asked for — content painting outside its box, a
child covering its neighbour, a row taller than the slot it was windowed into —
and the right response is to go and fix it.

One class of entry is not about this surface's own tree at all: **two surfaces
covering each other**. Two independently mounted surfaces — a HUD and a debug
overlay, a screen and a modal that never dismissed — that overlap while *neither*
declared it means to cover the other are reported on both of them. It is a defect like any other, and the three ways to say you meant it
are the three the framework already had: put one in a display band above the
other (`setDisplayOrder`, `presenter.SURFACE_LAYER`), present it
`rootPolicy = "edgeToEdge"` if it is a decoration layer, or stop it covering
anything (`hidden`, `opacity = 0`, a fade, `setRootVisible(false)` — a surface
that paints nothing is in no pair). A modal over a HUD is silent, because a band
difference is a declaration.

A few entries are the opposite: they describe the framework doing exactly what
the author told it to, and saying so. Those carry **`designed = true`**. Today
there is exactly one: a `UI.Composition` reports when none of the arrangements
you declared is legal at the current size and it is therefore showing the last
one — which is the fallback you declared *for that case*. Nothing is clipped,
nothing is lost, nothing is wrong. The composition is telling you which rung it
landed on, because on a small phone at the largest text size that is worth
knowing even though it is not a bug.

So the rule for anything that checks a screen is clean:

```lua
for _, finding in controller.diagnostics() do
    if finding.designed ~= true then
        -- a real defect: fail, log, or fix
    end
end
```

Read the field, never the wording. This is one decision, made in one place
(`src/layout/solver.luau`, the composition arrange branch), and both Facet's
always-on overflow sweep and a consumer's own screen checks read the field. A
designed report added later is handled correctly by every consumer on the day it
is written.

Two conventions worth knowing. **The read methods hand back copies** —
`stats()`, `diagnostics()`, `hiddenRoots()` and `compositionAt(nil)` all return
a snapshot, so caching one is safe and mutating one cannot corrupt the renderer.
And **`attachDragDetector` answers `nil`** when the adapter has no detector seam,
where `observeScroll` answers a no-op unsubscribe — nil-guard the first.

Adapters implement `createRoot/create/setRect/setProp/remove/destroyRoot` plus
the optional and theme sets (see `src/render/target_contract.luau`; `FakeTarget`
headless, `ScreenTarget` on the client).

**`adapter.driveActivate(path, meta?) -> boolean`** (both targets) — invokes the
EXACT closure `setActivateHandler` registered for that node: the one the engine's
`GuiButton.Activated` calls. It is a second CALLER of the single activation path,
never a second path, which is what makes a scripted drive (a Studio dev surface,
a headless row) real evidence of everything downstream of the engine edge —
policy, dispatch, state, motion. It is evidence of NOTHING upstream of that edge:
whether the engine delivers a touch to that instance at all is a device
question, and that is precisely where in-scroll-host activation defects live.
Answers `false` when the path has no handler, so "nothing there" and "did
nothing" stay distinguishable.

#### The presentation channel

Two controller methods are the framework's entire **motion write surface**, on the
`presentation` authority declared in `src/render/authority.luau`:

- `controller.setPresentationTransform(path, { x, y, scale?, rotation? } | nil)` —
  the offset **composes onto the solver's last rect** and is re-applied on every
  rect write, so a re-solve can never drop a running motion and a motion never
  touches solver geometry (no `Size`, no re-solve per frame; layout-affecting
  animation is deliberately out of scope). `scale` materializes a transient
  `FacetMotionScale` `UIScale`, released when the transform clears. An explicit
  settled scale of `1` retains the same pivot to avoid engine pixel-rounding jumps.
  On a pressable control it
  *shares* that control's own `UIScale`, because the engine honours one per object.
  `rotation` maps to `GuiObject.Rotation`, which is paint-only in Roblox. `nil`
  clears. Values are compared before writing, so a settled motion costs nothing.
- `controller.setPresentationTransparency(path, alpha | nil)` — fades a **fade
  group**: the node must have been declared `UI.Box{ canvasGroup = true }`, and the
  refusal for any other node is loud and names that fix. One `GroupTransparency`
  write, which no style rule owns, so a fade never contests native-sheet paint.

`setPresentationOffset(dy)` — the keyboard keep-visible shift the presenter
drives — is this channel's first consumer rather than its own special case.

**On the real client the instance tree is flat by default.** Every node parents
under the ScreenGui unless a real parent claimed it (a `ScrollView`,
`clipChildren`, a fade group, or an authored `scale`/`rotation` container), so an
offset accumulates down the subtree: a node pays its own transform plus every
ancestor's, stopping at its real parent, whose own move already carries it. That
is what makes a transform on the root move the whole surface instead of one
transparent frame. `FakeTarget` mirrors the composition
(`node.presentedPosition`) and both adapters declare which props they handle, so
`tests/render_target_contract.spec.luau` fails if they diverge.

Scale and rotation reach the node's own instance (and whatever is really parented
under it) — to scale a subtree with this channel, put the transform on a node that
is already a real parent. A `canvasGroup` works and is required if you also want
`setPresentationTransparency` on the same node, but it is not the only door: a
`ScrollView`, a `clipChildren` container, or a container that authored its own
`scale`/`rotation` blueprint prop on children it has is a real parent too, at the
cost of a plain `Frame` rather than a render buffer.

**Two rect reads, and which one a pointer question takes.** `controller.rectOf(path)`
answers the **solved** rect — layout space, composed from its host chain, and what a
consumer computing layout facts wants. (Under a **coordinate-space host** the solver
STORES the rect host-relative and the engine's own parenting carries the rest, so
"what the solver wrote" is not the whole answer and `rectOf` composes the chain
back to layout space for you.) `controller.screenRectOf(path)` answers the
same rect **where it is painted**: nested scroll offsets and every live presentation
offset (the node's own and every ancestor's) compose into it. Anything comparing a
rect against a POINTER — drop hit-tests, autoscroll bands, authored
`onPointerDown/Move/Up` handlers — takes `screenRectOf`, or it is asking about a
place the player is not looking:
inside a scrolled list the solved rect is canvas-space, and while the keyboard
keep-visible shift or an enter/exit slide is live the whole subtree is drawn
somewhere else (the framework's own drag registry reads `screenRectOf` for exactly
this reason). Hit geometry stays axis-aligned: a transform's `scale`/`rotation` are
**not** composed into it, so a scaled node still hit-tests at its solved size.

**`screenRectOf(path, relativeTo)`** (framework-gaps-phase2 gap 37) — the same
painted rect, translated into `relativeTo`'s own WINDOW-space origin, in one call.
Answers "where is `path` inside `relativeTo`" without a caller reading both rects
and subtracting them by hand. `nil` when either path is not live; a node relative
to itself is `{x=0,y=0,w,h}`.

#### A node hands back its own mounted path (`controller.mountedPathOf`)

A node's LIVE mounted path can differ from the DECLARED id chain an author
wrote: a `UI.When` ancestor names its taken branch `then`, which splices a
`/then` segment into the chain at whatever depth that `When` happens to sit. So
`"/S/PaneZ/Pane"` as authored might mount at `"/S/PaneZ/then/Pane"`.

`controller.mountedPathOf(declaredPath) -> string?` resolves it directly: an exact
match first, then the live path whose `/then`-stripped form equals the declared
one. `nil` when no live path matches. Pair it with `stageHost`/`foreignHost`/
`screenRectOf` when a declared path might sit behind a `UI.When`:

```lua
local realPath = controller.mountedPathOf(declaredPath) or declaredPath
local host = controller.stageHost(realPath)
```

One consumer still reads the solved rect: the presenter's `syncGeometry` /
`onGeometry` feed, which Slider's track math and the presenter's zone-A
outside-tap test use. A slider inside a scrolled container or under a live
enter/exit slide therefore scrubs against layout space.

**A DECORATION WHOSE PRESENCE DEPENDS ON ITS OWN SOLVED SIZE CANNOT CONVERGE.**
`onGeometry` hands back a rect the next solve can move, so a consumer that feeds
it into a layout-affecting prop — a `surface`, a dim, a padding — is a loop, and
the renderer says so after **8** rounds: *"a solve's geometry feedback did not
converge in 8 rounds (a consumer publishing a layout prop derived from the rect
that prop moves?)"*.
It is not enough for the rule to look self-consistent. A skin's `contentInsets`
are spent as the node's padding, so turning a plate ON can push that node's own
minimum past its fill share and leave it with a **smaller** box than it had
without the plate.

The way out is to **cache the reading and key it only on facts the decoration's
own presence cannot move** — the viewport, the player's text preference, the
distance profile, and the installed theme. A fresh shape takes one fresh reading
and the answer settles after a single flip. Leaving any of those four out is its
own defect rather than a smaller version of the same one: the theme decides the
carved frame, and a package swapped in place (which the showcase's own theme
picker does, without remounting) would otherwise answer with a band measured
under the package before it.

### `app.presenter`

`app.presenter` is the application's one presenter. `Facet.new()` builds it —
there is no public presenter constructor — and it owns screen and modal
lifetimes, focus scopes, and input contexts. A consumer standing a surface up by
hand gets the same object as `host.presenter` from
[`client.host`](#clienthost).

The application's own calls — `app.mount`, `app.presentModal`,
`app.presentAnchored`, `app.presentToast` — are the ones to write. Reach for
`app.presenter` for the verbs the application does not re-export: `dismiss`,
`back`, `raise`, `refresh`, `tick`, `onTick`, feedback, HUD reservations and the
inspection dumps.

#### `presenter.withAnimation(class, fn)`

```lua
local presenter = app.presenter

presenter.withAnimation("container", function()
	open:set(true)
end)
```

Runs `fn` in its own transaction, forces its own commit, and paints every node
whose box **changed** travelling from where it used to be to where it now is,
over ONE spring named by a motion **class**. The layout itself lands exactly and
instantly, as it always did: only the paint travels, so hit-testing and focus
never chase a moving pixel.

It is a presenter method rather than a `UI.` modifier because it needs all three
of the things only the presenter has — the motion clock it builds, the controller
scopes that own the records, and `refresh` itself.

**What it animates, and what it deliberately does not.**

- **Position and size — the whole of what a commit produces.** A commit produces
  one thing this can diff: the solver's rect, `x`/`y`/`w`/`h`. All four travel,
  on the same spring, so a panel finishes growing on the very frame the rows it
  displaced finish sliding. There is nothing else in the set: every other
  property a presentation channel could otherwise animate (opacity, rotation,
  scale, colour) is an *authored paint* value, and Facet has no authored prop in
  the presentation channel for one to be diffed from. Paint authority has to be
  decided first.
- **A size delta does NOT reach into the subtree**, and this is the one rule to
  carry away. A position offset accumulates downward: Facet's instance tree is
  flat by default, so an ordinary container's move carries nothing inside it and
  every descendant re-adds its ancestors' offsets, stopping only at the nearest
  node that is a real engine parent — a `ScrollView`, a `clipChildren` host, a
  fade group, or a container with its own authored `scale`/`rotation`. Every host
  registered shortens that walk, because that host's own move already carries
  its children; a size delta is the node's own regardless and stops
  there. A label pinned to the top of a growing card stays exactly where it is
  while the box opens underneath it — it neither drifts nor stretches.
- **The box's interior relayouts while it travels**, because it is a real engine
  `Size`: a wrapped label re-wraps at the intermediate width, a clip host crops
  at the intermediate height, a `canvasGroup` re-buffers each frame. That is what
  animating a size means, but
  the `canvasGroup`/`Stage` case is the one with a real per-frame cost — the
  performance lab's `motion-flight` workload is where it gets measured.
- **Hit geometry follows the painted position and the SOLVED size.** A shifted
  control is pressable where it looks; a node mid-growth hit-tests at the box it
  will have, the same rule a scaled node already followed.
- **Surviving paths only.** Structural insert and remove stay the transition
  system's job (`transition` on a region). A path another writer already owns — a
  structural transition, keep-visible — is excluded.
- **Only `fn`'s consequences.** The presenter drains pending work *before* arming,
  so the armed commit carries what `fn` changed and nothing else. Env-driven
  relayouts (a theme swap, a viewport resize, a preferred-text change) are never
  armed.

**Reduced motion is an explicit branch that installs no records at all.** `fn`
still runs, the transaction still commits, the layout is still exact; there is
simply no flight, and a size lands instantly for the same reason a position
does. That is legal here precisely because this motion is
DECORATIVE — the instant layout already carries every fact and the travel was
pure continuity. (Contrast `UI.ProgressView`'s indeterminate indicator, which is
INFORMATIONAL and therefore keeps running.)

**Interruption re-targets; it never restarts.** A second call while records are
live re-bases each record from its current painted offset **and its current
painted extent**, re-aims the spring and carries velocity over — so a card
interrupted half-grown continues from the height on screen. One spring per call
means a subtree provably cannot tear.

**Three refusals, and one of them is late.** Calling it from inside another
`withAnimation` is an error (arming is presenter-wide and the inner call would
disarm the outer one). An unknown motion-class name, or inline spring params, is
an error — a motion class is a NAME here as it is everywhere else. And if nothing
flushed — an outer `app.runtime:batch` is still open, or this ran during a
commit — it raises **after `fn` has already been applied**: the change landed
instantly with no flight, so a caller catching it must **not** retry the mutation
or it lands twice.

**There is no cap on how many records one frame may install.** The roots-only
rule keeps the count near the number of things that actually started moving.
`presenter.animationRecordCount()` reports the live count if you want to assert
a bound yourself.

`presenter.animationRecordCount()` and `presenter.commitCount()` are diagnostics
for tests, not features.

**`keyboardNavigation`** is a `Facet.new(opts)` host option (default
**`false`**). It opts every surface of that application's presenter into the
desktop keyboard conventions: **Tab / Shift+Tab** traverse the focus chain and
**Space** joins Return as Activate.

```lua
local app = Facet.new({ keyboardNavigation = true })
```

It is **off by default because the keys it claims are keys an avatar is already
using**: with it implicitly on, Space jumps the character while the UI holds
focus. Turn it on for a UI-driven place or a keyboard-first surface; leave it
off for a HUD over live gameplay.

Even when on, the bindings exist only while **keyboard capability is live** and
the surface's **responder is engaged**, so a phone binds nothing and a passive HUD
binds nothing until it engages. All three conditions are reactive: a keyboard
plugged in mid-session adds real bindings and unplugging removes them, with no
dead sink left behind.

Per-surface override: `app.mount(Screen, { keyboardNavigation = … })`, below.

**The arrow keys are a different story, and the default camera owns two of them.**
Up/Down/Left/Right move focus whenever a surface has a focus graph — they are not
gated on `keyboardNavigation`. But Roblox's **default `CameraModule` binds `Left`,
`Right`, `I` and `O`** through ContextActionService under the action name
**`RbxCameraKeypress`**, and it *sinks* them: the key arrives at
`UserInputService.InputBegan` with `gameProcessed = true` and never reaches the UI.
So **horizontal arrow navigation does nothing in a place running the default
camera** — measured 2026-08-06: one identical `Right` press read `gameProcessed =
true` with the binding up and `false` after
`ContextActionService:UnbindAction("RbxCameraKeypress")`, after which focus stepped
across a row and `Down`/`Left` moved as designed.

**The fix is `Workspace.PlayerScriptsUseInputActionSystem`, and it is a stated
requirement — see [Input](#input) below.** With that property enabled, Roblox's
player scripts (camera included) run on the Input Action System, so the camera's
keys become an `InputContext` that ordinary priority arbitration can outrank, and
Left/Right reach the UI like every other key.

There is no in-framework alternative, and specifically **no priority number**.
Measured 2026-08-14: a sinking `ContextActionService` binding consumes a key
before *any* `InputContext` is offered it, at any priority — a CAS sink at
priority **100** beat a Facet `InputContext` at **10000** with `Sink = true`. CAS
priority and `InputContext.Priority` are not one arbitration space, so a claim
built at 10000 was measured inert and removed rather than shipped
(`the-camera-still-owns-the-arrow-keys`).
Facet does not reach into `ContextActionService` at all, and
silently unbinding a consumer's camera would be worse than the symptom. Note that
disabling the PlayerModule's **controls** module does *not* free the key either —
the camera module is a separate binding, and measured live 2026-08-15 the arrows
were still held in a session where the controls module had already been disabled.

Until the property is on, a place that keeps the default camera should not rely on
Left/Right for UI; `client.gamepad_contention.cameraKeysContended()` answers
whether any CAS binding is holding an arrow on this client right now.

**Holding a navigation direction repeats.** Keyboard arrows, the D-pad and a
held thumbstick move once immediately, then repeat after **0.4s**, every **0.1s**.
Each step uses the same navigation path as a fresh press, including wrapping,
intercepts and focus boundaries. Release, dismissal, an input-owning control,
or a higher-priority modal stops the hold. Value adjustment remains a separate,
explicit gamepad-repeat capability of the control.

**Lifetime, stated.** A presenter has **no `dispose()`**. It owns a feedback
bus, a focus graph, a motion clock (its own, unless `Facet.new({ clock = … })`
passed one) and up to four private surfaces, and nothing releases them — so
building a second application to replace the first leaks all of it. Build one
application per client, present and dismiss surfaces on its one presenter, and
call `app.dispose()` when the client is finished with it.

**The three presentation verbs take a MOUNTED ROOT**, which is what the
`app.*` calls build for you. Write `app.mount` / `app.presentModal` /
`app.presentAnchored`; reach for these three directly only when you own the
mount yourself.

Methods:

- `presenter.present(root, opts?) -> handle` — base screen. `app.mount` is this.
- `presenter.presentModal(root, opts?) -> handle` — focus trap +
  higher-priority sinking input context; Cancel (gamepad B) dismisses.
  `app.presentModal` is this.
- `presenter.presentAnchored(panel, opts) -> handle` — a surface placed against
  a **source view's screen rect** instead of a parent corner. `panel` is a node
  or a builder function, never a `UI.Screen`. See **Anchored surfaces** below.
  `app.presentAnchored` is this, with the builder handed `app.controls`.
- `presenter.expand(regionPath) -> "anchored" | "sheet" | "custom" | nil` — open a
  `UI.Region`'s expand from somewhere else. A stepped-down region carries its own
  affordance and needs nothing from any caller; this is for the SECOND route to
  the same disclosure — a screen's overflow census listing what it stopped showing
  and offering a row for each SIMPLIFIED region. The argument is the path the
  composition resolution already names every region by
  (`resolution.regions[i].id`), and the lookup is the shipped longest-prefix
  contribution dispatch, so it opens the plate the region already has rather than
  a second one beside it. `nil` means there was nothing to open — a region at its
  richest form has nothing more to show.
- `presenter.anchoredSurfaces() -> { schema, count, surfaces, text }` — every
  live anchored surface with its resolved edge, whether it flipped, how far it
  shifted along that edge and what became of its tail (schema
  `facet-anchored-dump/1`). Deterministic; the shape a bug report needs.
- `presenter.help() -> { schema, present, sourcePath, source, helpText, declarations, text }`
  — the player-pulled help plate's state (schema `facet-help-dump/1`). See
  **Help** below.
- `presenter.helpDeclarations() -> { [path] = { text, hover, focus } }` — every
  live `help` declaration and the routes that actually reach it, read off the
  mounted tree and the LIVE interaction classes. The input
  `text_audit.helpRoutes` is written against.
- `presenter.presentCallout(spec) -> id` / `presenter.releaseCallout(id, reason?)`
  — a turn on screen for an app-pushed coach mark. At most one is ever visible; a
  second request waits. Callers reach this through
  [`UI.Callout`](#uicallout) rather than directly.
- `presenter.callouts() -> { schema, showing, visible, queued, waiting, text }` —
  what is on screen and what is waiting (schema
  `facet-callout-queue-dump/1`).
- `presenter.presentCritical(component, opts) -> handle` — mounts the component
  and presents it under protection; on error presents
  `opts.fallbackScreen(err)` instead (critical-screen fallback). **The fallback
  is presented with the caller's own opts** — `rootPolicy`, `navigationGroups`,
  `transition`, `keepVisibleOffset` and the rest all still apply, because
  everything you declared about this screen is still true of the screen standing
  in for it. `fallbackScreen` itself does not ride along: the fallback presents
  as an ordinary screen and its own errors stay hard.
- `presenter.dismiss(handle)` — removes THAT handle's screen, focus scope
  (wherever it sits in the stack), input context, and mounted tree.
- `presenter.back() -> boolean` — dismisses the top modal.
- `presenter.raise(handle)` — re-bands a LIVE presented surface (a screen or a
  modal, whatever is still on `presenter`'s stack) above whatever was freshly
  presented over it, **without dismiss+re-present**: the handle's tree, scope,
  focus scope and transition state are untouched, so nothing remounts, no enter
  transition replays, and focus never moves. It costs exactly the SAME thing a
  fresh `present` costs — one more slot in the handle's own band (`base` or
  `modal`) — because bands only grow forward; what it removes is the mount/
  scope/transition/focus cost of the dismiss+re-present a caller would
  otherwise need to fake this with. **Refuses silently, like `dismiss`,** for a
  handle that is not currently presented (`nil`, or already dismissed) — a
  defensive caller must not be punished for raising a surface that already
  closed. See `examples/gallery/client/showcase_chrome.luau`'s `raisePanel`
  for the shape a real consumer takes (framework-gaps-phase2 item 23, task W3-D).
- `presenter.refresh()` — re-renders all presented screens, **re-discovers each
  surface's input contributions from its live mounted tree**, and re-derives
  focus rings from those trees. The contribution walk matters as much as the
  focus one: a control whose `contribution.attach` bundle mounts LATER (inside a
  `UI.When` that opens on a role, a phase, a load) is wired the frame it appears
  — `handleActivate`, `handleCancel`, `focusGroups`, `focusMoved`,
  `navigateIntercept`, `bindController` and `bindActionSystem` all start
  working then, and a bundle whose region CLOSES stops receiving dispatch.
  One-time bindings are keyed on bundle identity, so a surviving contribution is
  never bound twice.
- `presenter.depth() -> number`, `presenter.focus` (the focus graph).
- **Focus identity vs the focus RING** (`presenter.focus.focusVisible`,
  `presenter.focus.setFocusOrigin(kind)`). At presenter creation, entry focus is
  visible for effective Gamepad input and hidden for mouse/keyboard or touch
  until a navigation verb occurs. This is a one-time initialization; subsequent
  environment changes do not overwrite the last interaction's origin.
  Focus always moves — a tap moves it
  wherever it lands, and every consumer that follows focus (a drag's aim,
  keep-visible, the engine-selection bridge) keeps working on touch. The RING is
  a different question — "where does the next Navigate go" — and a finger never
  asked it. So the graph records the ORIGIN of the last focus move: `"pointer"`
  (a tap/click, and any programmatic `focusOn` that follows one) hides the ring,
  `"navigation"` (a key, a d-pad, an explicit call) shows it, and the first
  navigation verb after a tap brings it straight back onto the node the finger
  left it on. `focusVisible` is the readable the presenter feeds to
  `controller.setFocusPath(path, visible)`; hybrid input switches need no
  consumer branching. Consumers only call `setFocusOrigin` when they synthesize input.
- `presenter.tick(dt?)` — **one frame of presenter time**: steps the motion
  clock every surface and toast transition rides, then advances the toast
  schedule. The client binds it to `RunService.PreRender`; the headless suite
  passes a scripted `dt`. Nothing animates and no deferred teardown completes
  without it — including the exit cap, which is clock time, not wall time. A
  region whose exit finishes during a tick disposes then; its instances leave on
  the next `presenter.refresh()`, as every structural change does (they are
  already faded out or off the edge, so nothing is visible in between).
  **An application drives this for you.** `Facet.new()` stands up a host that
  connects one `RunService.PreRender` calling `presenter.tick(dt)` and then
  `presenter.refresh()`, and `app.dispose()` disconnects it. A consumer driving a
  presenter by hand claims the frame first — `presenter.claimFrameDriver(name)`
  returns the release, and a second driver on the same presenter is refused
  loudly rather than allowed to double-tick the clock. And because `PreRender`
  handlers **block the rendering pipeline until they return**, everything inside
  one tick — every motion write, every
  transition, the toast schedule — spends the frame's *render-thread* budget, which
  is the budget the SF-M8 frame numbers are about.
- `presenter.onTick(fn) -> unsubscribe` — register **per-frame work that is not a
  motion value** on the presenter's own clock: a list's autoscroll step, a
  world-anchored render target's `controller.refresh()`, a fixture probe. Hooks
  run inside `presenter.tick`, **after** the motion step (so they read this
  frame's settled values) and in registration order; each is quarantined, so a
  throwing hook cannot starve its siblings or escape into the render thread. This
  is the one sanctioned frame source outside the motion clock — a second
  `RunService` connection in a consumer is the bug class it prevents. The
  unsubscribe is yours to own; inside a component, hand it to Compose
  (`Compose.cleanup(presenter.onTick(fn))`). `app.onFrame(fn)` is this same
  registration under the application's own name.
- `presenter.motionClock` — the clock itself. `Facet.new(opts)` takes
  `opts.clock` to share one with the rest of the application, and `opts.now` to
  inject time.
- `presenter.reserveHud({ id, edge, scope? }) -> { update(rect?), dispose() }` —
  reserve measured window-space HUD content on `top`, `bottom`, `left`, or `right`.
  IDs must be unique for this presenter. `update(nil)` clears the rectangle;
  disposal releases the reservation and is idempotent. `scope` takes a live
  Compose owner and disposes the reservation with it; without one, own the
  handle yourself (`Compose.cleanup(reservation.dispose)` inside a component).
  `presenter.hudReservations` is a read-only reactive array of `{ id, edge, rect }`,
  sorted by ID; entries appear only after an update. Toasts automatically reserve
  their occupied strip until the last exit completes. Reservations do not move
  anything by themselves: feed their rects into `Composition.exclusions` for top
  lanes, `layout.hudInsets` for other edges, or `layout.worldMarkers` exclusions.
  Do not reserve a region against the layout that positions that same region.
- `presenter.presentToast(component, opts?) -> { id, dismiss() }` — see
  **Toasts** below. `app.presentToast` is this.
- `presenter.onFeedback(fn) -> unsubscribe`, `presenter.emitFeedback(event)`,
  `handle.onFeedback(fn)` — see **Semantic feedback** below.
- `presenter.onModalPresented(fn) -> unsubscribe` — fires when a modal takes the
  screen. A focus trap and a live drag proxy cannot coexist, so a drag session
  subscribes here and cancels itself; the presenter states the fact and never
  reaches into a session it does not own.
- `presenter.SURFACE_LAYER` — the four-layer surface order as display-order
  BANDS: `base` < `toast` < `dragProxy` < `modal`. Bands rather than one running
  counter, so a toast sits above every base screen and below every modal
  whatever order they were presented in; within a band, creation order decides.
- `presenter.APP_CHROME_PRIORITY` — the reserved **input-priority** band (not a
  display-order band — see `SURFACE_LAYER` above for that axis) for
  session-lifetime, app-level global chrome: a settings toggle, a demo picker,
  anything a game binds ONCE at boot and means to keep winning input
  arbitration against any live modal/engaged surface for the rest of the
  session. Sits strictly above `presenter`'s own ENGAGED-EXCLUSIVE band and
  above every live modal depth this framework's own suite exercises (twenty
  simultaneously-open nested modals of headroom — the same "far past anything
  real" doctrine `displayLayer`'s cross-surface z counter already claims). Use
  it as `opts.actionSystem.createContext({ priority = presenter.APP_CHROME_PRIORITY, sink = true })`
  for a context that must never contend with a modal's own priority
  (`topModalPriority() + 500` per depth) the way a hand-picked literal would.
  See `examples/gallery/client/showcase_chrome.luau`'s toggle context for the
  real consumer this replaced a hand-picked `3500` in (framework-gaps-phase2
  item 24; W3-D).
- `presenter.exclusiveSurfaceActive` — a readable boolean, true while any
  presented surface is EXCLUSIVE (a modal, or an engaged-from-passive HUD — both
  sink, becoming first responder over gameplay). A client adapter observes this
  to hide the mobile touch controls (`src/client/responder_effects`).
- `presenter.disclosure() -> { schema, present, path?, labelPath?, sourcePath?,
  source?, text? }` — the live **full-value disclosure** plate (below), frozen
  and deterministic; `present = false` when none is up. `presenter._discloseHover(path?)`
  and `presenter._discloseLongPress(path?)` are the two engine-adapter seams that
  feed it (`nil` = disengaged); the leading underscore means an adapter drives
  them, exactly as for `action._deliver`.
- `presenter.topScrimPath() -> string?` — the path of the synthesized
  scrim/catcher beneath the top exclusive surface, or nil when none is up (see
  Modal outside-tap dismissal below). Handle fields: `.root`, `.controller`,
  `.blueprint`, `.actions`, `.displayOrder` (cross-surface z),
  `.responder` (a readable of `"passive"` / `"engaged"`), `.engage()`,
  `.resign()`, `.focusOrder()` (the focus-map inspection dump, below).

**Presentation options.** These are the `options` argument to `app.mount`,
`app.presentModal` and `app.presentAnchored`, and to
`presenter.present`/`presentModal`/`presentCritical`. The key set is closed, and
an unknown one is refused at present time:
`onActivate(path, meta)`, `onAdjust`, `onFocusNav`, `onReorderNav`,
`onNavigateIntercept`, `navigationGroups`, `onGeometry`, `keepVisibleOffset`,
`sinkNavigation`, `responder`, `gameplayGuard`, `rootPolicy`, `edgeFloor`, `outsideTapCancel`,
`cancelPolicy`, `scrim`, `revealWhenTextExact`, `revealTimeout`, `transition`,
`traversalWrap`, `keyboardNavigation`, `initialFocus`, `focusChrome`,
`engineSelectionBridge` (the `presentModal` mirror described above),
`fallbackScreen` (read by `presentCritical`), and the performance opts the
surface hands straight to `renderer.attach`:

- **`recycleInstances`** (default **on**) — park a retiring node and reuse it for
  the next create of the same kind instead of destroying and re-creating it. It
  is feature-detected on the adapter (`park`/`adopt`/`discardParked`) and `park`
  refuses any node it cannot take intact, and a refusal falls straight through to
  the ordinary remove — so it can only ever avoid work, never change what is on
  screen. Pass `false` to opt out.
- **`incrementalLayout`** (default **on**) — let one solve from the root SKIP a
  subtree it can prove cannot have changed (no dirty node inside it, same offer
  and same rect as last time), replaying that subtree's published verdicts and
  diagnostics. Same traversal, same context, same policies as a full solve. Pass
  `false` to opt out.

Four additional comparison switches also default **on**: `measureReuse` reuses
measurements between solves, `commitScope` prunes unchanged commit subtrees,
`structuralReuse` limits structural solves to a valid boundary, and
`translateHosts` uses coordinate-space hosts for translations. Pass `false` to
compare with the corresponding baseline path while keeping the same mounted
component and application lifetime. These are diagnostic options; they do not
change authored layout semantics.

The four string-enum opts — `rootPolicy`, `responder`, `cancelPolicy`, `scrim` —
are validated at present time and an unknown value errors naming the legal set.

**`sinkNavigation` does nothing on a passive surface.** A `responder = "passive"`
screen exists precisely so navigation reaches the gameplay contexts beneath it,
so it never sinks while passive whatever this opt says; engagement is what turns
sinking on. Set it on an ordinary `app.mount` (a modal always sinks).

**`traversalWrap`** (default `true`) declares whether **Tab / Shift+Tab** wrap at
the ends of this surface's focus scope. It is declared per surface and never by a
control, so one screen has one answer wherever the ring is standing. `true` is the
default because it matches the ring the arrows have always walked and because a
modal has nowhere else for Tab to go; set `false` where running off the end should
read as an end. It governs Tab only — a `NavigationGroup`'s own `wrap` still
governs the directional arrows along that group's axis.

**`focusChrome`** — `"top" | "bottom" | "leading" | "trailing"`, screens only —
declares this surface to be the app's persistent **frame** rather than a screen of
its own, sitting on the named edge. Its focusables are then **adopted** into
whatever scope is active: one composed focus map, the chrome's own navigation
groups placed at that edge of the active scope's group array, with `exitFrom`,
`enterGroup` and `traverse` all reading it as they read any other group.

Without it a second presented surface is in **neither** ring — the top scope owns
every navigation verb, so a strip presented under a screen is reachable by pointer
and by nothing else. That is correct for a HUD that appears unasked and wrong for
chrome, which is why this is opt-in. Adoption is not a takeover: `activeScopeName`
and **entry focus** still belong to the screen on top (a first Tab or arrow lands
in the content, never on the frame), and a **modal suspends it** — a trap's ring
must not leak into a strip the player can no longer reach. Activate on an adopted
node is dispatched against the chrome's **own** handle, so a passive strip's chips
still run their own handlers.

One ordering requirement: **present the chrome before the screens that adopt it.**
A screen decides at present time whether it binds the horizontal arrows at all, so
a chrome that arrives after a flat screen is reachable from it but not walkable
along its own axis. Chrome is the app frame — it goes down at boot.

```lua
app.mount(Strip, { responder = "passive", rootPolicy = "edgeToEdge", focusChrome = "top" })
app.mount(Screen) -- owns Tab and the arrows; UP off its first row reaches the strip
```

**`keyboardNavigation`** overrides the application default (the `Facet.new(opts)`
host option above) for this one surface: `true` gives a keyboard-driven modal Tab
and Space over a gameplay HUD that does not want them, `false` keeps one HUD out
of the way in a keyboard-navigable application. The capability and responder
conditions still apply.

> **If your surface sits over a live world, pair it with `responder = "passive"`.**
> `keyboardNavigation = true` makes an ordinary `app.mount` screen **sink** — it has
> to, or the avatar hears Space and the arrows while the UI has focus. But an
> ordinary screen is *engaged-open*: it is never the exclusive surface, so it is
> never given an outside-tap catcher, and `resign()` is a no-op for it. The result
> is a surface that takes the keyboard when it mounts and **never gives it back**.
>
> That is correct for a full-screen menu, where there is nothing else to click. It
> is wrong for anything with a world behind it. `responder = "passive"` is the
> click-to-focus / click-away-to-blur convention and is what you want there:
>
> ```lua
> app.mount(Hud, { keyboardNavigation = true, responder = "passive" })
> ```
>
> | | binds Tab/Space | sinks | gives it back |
> |---|---|---|---|
> | `app.mount` (engaged-open) | on mount, forever | yes | **no** |
> | `responder = "passive"` | on first tap on the UI | while engaged | on a tap outside, Cancel, or `resign()` |
> | `app.presentModal` | while open | yes | on dismiss |

### `navBar`

A surface's own top bar: a leading Back verb, a one-line title, a spacer, then
trailing nodes. Inside a component build it from the application's constructors:

```lua
UI.navBar({
	id = "TopBar",          -- default "NavBar"
	onBack = close,         -- nil = no Back button
	backLabel = "Back",     -- travels with onBack (a Button needs a label)
	title = title,          -- a string or a Compose readable; nil = no Title node
	titleSize = "title",    -- default "title"
	titleWidth = UI.hug(),  -- nil leaves Title unbounded and hugging
	trailing = { favouriteButton }, -- placed after the spacer, in order
	gap = "s",              -- default "s"
	padding = "m",          -- default none
})
```

`UI.navBar` is `app.controls.navBar`. `Facet.navBar(spec, app.controls)` is the
same call for code that holds the `Facet` table instead; `Facet.navBar(spec)`
with no constructors builds plain blueprint nodes and is refused inside a
component, naming the two spellings above.

The bar is an `HStack`: `width = UI.fill()`, `align = "center"`, the `gap` you
gave it, and a `Spacer` between the title and the trailing nodes. The Title is
`lineLimit = 1` with `disclose = true`, so a title that does not fit truncates
into its disclosure plate rather than widening the pane.

**Pure**: no core, no owner, no presenter reference of its own, so it composes
with whatever placement you already decided — pinned above a `ScrollView`,
inside a compact-only `UI.When`, or scrolling with the body.

**`onBack` is refuse-don't-guess, not auto-wired.** This construct never reaches
into a presenter or a handle to decide "is there something to go back to" — the
caller already knows (a modal stack, an app router, a compact/regular split), and
hands over exactly the verb it wants or `nil` for none. A `Back` button always
draws the framework's own `chevron.leading` icon through `compactLabel`, and it
declares `prefer = true`, so the icon is never traded back for a text label by
the shrink ladder.

**The slot form.** Pass `leading` (a node that follows Back) or `center` (a
node that replaces the default title) and the bar becomes an `AdaptiveStack`
with a `Primary` row — Back, `Leading`, then a `Center` that fills what is
left — and a `Trailing` group. When the measured sides would leave the center
under `controls.popup.panelWidth`, the trailing content moves to a second row
while Back, leading and the center stay first; it is an axis change, so no slot
is rebuilt and a focused search field in the center keeps its text and focus.
Trailing controls degrade through their own `compactLabel` first. Without
`leading` or `center` the lowercase form keeps its exact legacy shape.

### `UI.NavBar`

`UI.NavBar { … }` -> the bar's node. `ref` receives `{ api, dump }`.

The typed, named form, **always** the slot form: `{ id?, onBack?, backLabel?,
title?, titleSize?, leading?, center?, trailing?, gap?, padding? }`. `trailing` is
**one** node — author a cluster as an `HStack` — and every slot is a caller-owned
node (a Button, a search `TextInput`, a title-and-subtitle stack). `dump()`
reports `{ schema = "facet-navbar-dump/1", id, back, leading, center =
"custom" | "title" | "none", trailing }`.

```lua
UI.NavBar("Top")({
    onBack = close, backLabel = "Back",
    center = UI.TextInput("Search")({ value = query, placeholder = "Search tracks" }),
    trailing = UI.HStack("Tools")({ UI.Button("Filter")({ label = "Filter", compactLabel = { icon = "menu" } }) }),
})
```

### The standing rule: a transient opens OVER the live screen, and the live screen stays visible

A menu, a popup, a picker panel, a callout, an expand plate — the whole
transient family — opens **on top of** the screen that is already there, and
that screen **stays visible behind it**. A full-screen opaque fill behind a
transient is banned. Framework-side this is guarded for every construct that
synthesizes one (`tests/transient_over_live.spec.luau`); an app that presents its
own transients owes the same rule, and two mechanics decide whether it keeps it:

- **Cross-surface z is PRESENT ORDER within a band.** `displayLayer` goes up 100
  per present (or `raise`) and back to zero only when the stack EMPTIES. So a
  base screen that is dismissed and re-presented — a screen swap, a re-mount —
  climbs **above** a transient that was presented before it, and the player
  ends up reading a panel that is now underneath the screen they opened it
  over. An app whose live screen re-presents under a live transient calls
  **`presenter.raise(transientHandle)`** afterwards to put it back on top —
  see `presenter.raise` above (framework-gaps-phase2 item 23; W3-D)
  — and can tell whether it needs to by comparing the two handles'
  `.displayOrder`. `raise` never dismisses or remounts the transient, so its
  scroll position, focus ring and any live animation survive the re-band
  untouched; before this landed, the only available fix was a full
  dismiss+re-present, which lost all three.
- **Every present (or raise) spends a slot.** Restoring ordering this way
  therefore still costs a second slot per swap — `raise` removes the
  mount/scope/transition/focus COST of a re-present, not the band-slot cost,
  which no re-banding scheme in this framework can avoid paying. `SURFACE_LAYER
  .toast` is +10000 above the base band, so a long-lived session that swaps
  screens under an open transient reaches it in roughly half as many swaps as
  one that does not. Prefer closing the transient to raising it in a loop.

### `handle.focusOrder()`

Returns this surface's focus map **as data**, for debugging and for tests. Frozen,
and deterministic — two calls with nothing changed in between return equal data.

```lua
{
  schema = "facet-focus-order/1",
  scope = "SettingsScreen",
  present = true,          -- false after the surface is dismissed/disposed
  trap = false,            -- is this a trapping (modal) scope?
  traversalWrap = true,
  ranked = true,           -- false when you supplied `navigationGroups` yourself
  traversal = {            -- the LINEAR (Tab / Shift+Tab) reading, in order
    { path = "/S/Name", priority = 0, eligible = true },
    { path = "/S/Volume/TrackHost/Track", priority = 0, eligible = true },
  },
  navigation = {           -- the DIRECTIONAL (arrow) reading
    { name = "auto-v-1", axis = "vertical", order = { "/S/Name" } },
    { name = "auto-grips", axis = "vertical", order = { "/S/Volume/TrackHost/Track" } },
    -- a TWO-DIMENSIONAL group carries its lane count as well
    { name = "VirtualGridCells-VG", axis = "horizontal", columns = 4, order = { --[[ 16 cells ]] } },
  },
}
```

**`columns` is present only on a two-dimensional group**, and it is the one thing
the order cannot tell you: a 4-lane grid and a 16-button row are the same sixteen
paths. `axis` names the direction ±1 walks (the grid's **lane** axis); `columns`
says where the lines break, so the perpendicular arrow moves a whole line rather
than falling straight out of the group. A group without it is a plain ring.

**The two lists are meant to differ, and meant to cover the same set.** A focusable
`Grip` — a Slider's track, a Rating's strip — traverses in its
**document position** and arrows to the **end**, because Tab means document order
while arrowing down a table should reach rows before handles. Seeing both readings
at once is the point: if a control is in one list and not the other, that is a bug
in the framework, not in your screen. A flat scope reports its single ring as a
group named `(flat)`.

**What is absent versus what is ineligible.** A node excluded upstream — hidden,
`enabled = false`, `focusable = false`, mid-exit-transition, or a losing
`ViewThatFits` candidate — never reaches the focus graph and does not appear here
at all; its absence is the answer to "why does Tab skip it". `eligible = false`
means something narrower: the node is in the map, and a live focus-skip predicate
is refusing it *right now*.

`priority` is the **authored** `traversalPriority` tier, not the resolved position
— the resolved position is the entry's index in `traversal`.

Safe to call after the surface is gone: a dismissed or disposed surface returns
`present = false` with empty lists rather than throwing, so a debug overlay that
outlives what it inspects cannot crash the client.

**`initialFocus`** decides where focus is when the surface appears.

| Value | Focus on mount |
|---|---|
| absent, on an engaged-open screen or a modal | the first focusable in traversal order |
| absent, on `responder = "passive"` | **nothing** — a surface that owns no input until it is touched claims no focus either |
| `"first"` | the first focusable, explicitly |
| `"none"` | **nothing.** Focus arrives on the first Tab, tap, or `engage()` |
| a node id (`"Save"`) | that control |
| `{ id = "Save" }` | that control, said unambiguously |

An id is matched by its **final path segment or full path**, so `"Save"` finds
`/Settings/Actions/Save` without you knowing the tree above it. An id that names no
focusable on the surface is **refused at present time**, listing what is available —
a typo'd control name must not silently become "first".

`"first"` and `"none"` are reserved words. If your surface genuinely contains a
focusable with one of those ids, `initialFocus = "first"` is ambiguous and is
**refused**; use the `{ id = … }` form to mean the control.

`"none"` is a standing property, not a one-shot: a surface that asked for no initial
focus is not given one by later structural churn either. Once focus does land there,
it behaves like any other scope — including keeping the nearest survivor when a
focused node unmounts.

> **A control that paints its own focused state follows the same rule.** A `Slider`
> declares `focusVisual = "none"` and draws its own thumb ring; the presenter hands
> it the same permission the adapter's ring obeys (through `bindFocusGraph`), so it
> releases that ring when the surface resigns. Focus **identity** is deliberately
> kept — keep-visible, the drag aim and the selection bridge all follow it, and
> re-engaging resumes where the player left off. Only the paint goes.

> **Focus is released when the surface goes away.** `dismiss()` (and Cancel, and an
> outside tap on a modal) pops the focus scope, destroys the input context, and
> clears the surface's focus ring **immediately** — including while an exit
> transition is still playing, when the tree is still mounted. A surface on its way
> out neither takes input nor looks like it does.

**`rootPolicy`** resolves the surface's content rect from the viewport and the
safe insets: `coreSafeContent` (the default — inset by the CoreGui reservation),
`deviceSafeContent` (per-edge max of CoreGui and device insets), `bandSafeContent`
(the same three edges, with the TOP brought up to where the platform's free topbar
strip starts — content that means to ride the band), and `edgeToEdge` (the whole
window — a scrim or a backdrop).

**`bandSafeContent` floors its other three edges at `themeMetrics.space.gutter`**,
so the inset it applies is the per-edge **max** of what the platform says must be
cleared and what the theme calls a gap. The platform's safe inset answers "what
must be cleared"; it does not answer "may content touch the glass", and on a
device whose engine pre-excludes the notch from the camera the lateral inset is
zero. Its TOP is exempt, because a gutter there would stop a topbar row sitting
level with the engine's own buttons. `coreSafeContent` and `deviceSafeContent`
are unchanged — widening the floor to them is deferred with its measurement.

**`edgeFloor`** is the opt-in version of that same floor, for a consumer who
wants one on `coreSafeContent`/`deviceSafeContent`/`bandSafeContent` without
waiting on the default (director ruling, 2026-08-23: *"if the user truly
specifies edge-to-edge we should do so with no padding. Ensure the user can
specify padding"*). A number (a
literal pixel count, every distance) or a theme metric name (`"l"`,
`"space.xl"` — resolved the same way `Table.cellPadding`/`anchor.gap` already
resolve theirs, so it rides the ten-foot ladder for free: a literal number
does not, a metric name does, exactly like those two). Floors bottom/left/right
at the **max** of what the policy already reserves and this — never top, never
a second addition. **Illegal together with `rootPolicy = "edgeToEdge"`**:
`renderer.attach` refuses the combination at the call site
rather than picking a winner, because edge-to-edge means zero padding by
definition. Omitted = today's behavior on every policy, unchanged; whether the
default ever floors `coreSafeContent`/`deviceSafeContent` the way `edgeFloor`
lets a caller ask for by hand is a separate, unshipped call.

```lua
app.mount(Screen, { edgeFloor = "l" }) -- a consumer-declared floor
app.mount(Screen, { edgeFloor = 16 }) -- or a literal pixel count
```

**Placing a surface in the platform's TOPBAR band.** Present it
`rootPolicy = "bandSafeContent"` and give it a `UI.Composition` with a region in
the **`topbar`** group. The solver lays that row into `platformChrome.band` — the
free strip's own x and width, reaching the band's bottom edge — so its content is
level with the platform's controls and cannot be over them, and the lanes start
below the platform's whole top reservation:

```lua
app.mount(Screen, { rootPolicy = "bandSafeContent" })

UI.Composition("Hud")({
	width = UI.fill(),
	height = UI.fill(),
	groups = Facet.composition.HUD_GROUPS,
	arrangements = { Facet.composition.HUD },
	-- `sizing = "fill"` takes the strip, so the content centres IN it
	UI.Region("Strip")({ group = "topbar", rank = 1, sizing = "fill", chip }),
	-- ...the nine anchored zones, which start below the band
})
```

A composition that declares **no** `topbar` region resolves exactly as
`deviceSafeContent` would have resolved it, so asking for the policy does not put
anything in the band — declaring a region does. And a surface whose root is not a
Composition gets the band as its own content rect: `bandSafeContent` is for a
surface that *means* to ride it.

The fact itself is still readable, for a caller that needs the numbers rather
than the placement:

```lua
local chrome = env:get("platformChrome"):peek()
if chrome.band ~= nil then
	-- chrome.band is { x, y, w, h } in WINDOW space: the strip the platform
	-- leaves free beside its own control cluster
end
```

`band` is **`nil`** when the platform reports no strip (a desktop engine without
`GetInsetArea`, or any headless environment) — never a zero rect at the origin,
because "no strip" and "a strip at (0,0)" are the same table and opposite
instructions. `chrome.rects` is what the platform's own controls occupy, as a
**list** of window-space rects, because the top band minus a free strip is an L
rather than a rectangle. `chrome.insets` is what a surface must inset to clear
everything — byte-identical to what `rootPolicy = "deviceSafeContent"` applies —
and `chrome.bandInsets` is the same four edges with the top brought up to where
the band starts, which is what `rootPolicy = "bandSafeContent"` applies. When
there is no band the two are equal, so a consumer needs no branch and the policy
is byte-identical to `deviceSafeContent` there.

Do not add `topbarSafeInsets.left` to `topbarInset.x`. They are two encodings of
one rect — measured on the live engine 2026-08-14 at 735x413, `TopbarInset` reads
`(164,0)+571x58` and the topbar-safe area reads x 164..735 / y 0..58 — and
`platformChrome` intersects them. (An earlier version of this page said to add
them; that was wrong, and adding them pushes content a cluster-width too far
right.)

Anything a player can *act* on still belongs in the content rect — the band is
narrow, the platform owns most of it, and a control there competes with the
engine's own.

**Surface transitions (`transition`).** A `{ enter, exit?, class?, fade? }`
declaration (the vocabulary is documented under **Structural transitions**) that
runs on the surface itself: the enter plays on the first painted frame, and
`dismiss` then defers the teardown until the exit completes or the flat 500 ms
cap fires. The surface leaves the stack **immediately** either way — its input
context is destroyed, its focus scope popped, its exclusivity dropped — because
a screen on its way out must never still take input; only the pixels linger.

A fading form needs a fade group and a `Screen` is not one, so the transition
targets the root's single declared `canvasGroup` child when it has one
(`UI.ZStack{ canvasGroup = true }` around the screen's content is the shape) and
the root itself otherwise. **Position/scale always ride that target as
declared; alpha alone may resolve one level further in** (task
POP) — when the target is not itself a `canvasGroup`, the transparency write
looks for the ONE such descendant in its subtree instead, so an opaque plate
can sit OUTSIDE the fade (a direct, non-`canvasGroup` child of the target)
while its content, one level in, is what actually fades. See **Structural
transitions** above for the full shape.

#### Full-value disclosure

A `UI.Text{ disclose = true }` that **truncated** owes the reader the whole
string, and the presenter pays that debt with one **static** plate — no marquee,
no travel, no per-frame work while nothing is engaged (decision LTN-2 chose the
static form so reduced-motion parity is structural rather than a branch).

Three engagements, one per applicable input class, and **at most one plate is
live at a time** across every surface:

| Input class | Engages | Disengages |
|---|---|---|
| pointer | `presenter._discloseHover(path)`, after a 0.45 s dwell | `_discloseHover(nil)`, or hovering a different label |
| keyboard / gamepad | focus entering the containing focusable | focus leaving it |
| touch | `presenter._discloseLongPress(path)` | `_discloseLongPress(nil)` |

A tap anywhere, the source node unmounting, a re-solve that makes room for the
label, and the owning surface being dismissed all remove it too. A pointer-driven
focus move does **not** engage it — the finger asked to press the row, not to
read its name, which is the same rule the focus ring reads.

The plate is presentation chrome: a presenter-private surface (not in the stack,
no focus scope, no input context), never focusable and never in any focus order,
painted just above its owner inside its owner's band, anchored near the source
node and clamped into the safe viewport, themed by the active ThemeSnapshot's
`raised` surface. The truncation verdict comes from the solve
(`controller.textAt(path)`), never from a second measurement, so the plate exists
exactly while the engine is ellipsizing.

`presenter.disclosure()` reports the live plate for inspection and tests.

#### The auto reveal

A `UI.Text{ reveal = "auto" }` that **truncated** auto-scrolls its whole value
(director ruling 2026-08-04, superseding LTN-2's "no marquee shipped" for
surfaces that declare it; the plan's rung-4 constraint list binds). The presenter
owns the whole cycle on its **one tick** — no per-label frame loops, and an idle
presentation pays only a timer-gated rescan behind the `hasReveal` stamp:

- **rest** — the label sits in the engine's own ellipsis for the quiet delay
  (1.2 s), so nothing moves the moment a surface presents;
- **out** — a presenter-private strip (a `clipChildren` window fixed at the
  source label's own rect, the full string inside it at the solve's own
  `naturalWidth`) slides LEFT at a glyph-rate speed (bigger preference text
  moves slower in px, same reading rate), while the source's own paint is held
  through `controller.setPaintHeld` — the solve, the rects and the truncation
  facts are untouched;
- **end** — the tail holds for the same pause, fully shown;
- **back** — the strip returns and unmounts; the source's ellipsis paint comes
  back, and the cycle rests again.

The string is never re-segmented (grapheme safety is structural: one strip, one
translation); a re-solve that makes room, a swapped bound value, a dismissed
surface or a reduced-motion flip all retire the strip on the next tick, releasing
the held paint. A live **disclosure plate for the same label outranks the strip**
(the reader asked for the static answer), and a reveal node is itself a
disclosure source — the plate is its static full-value alternative, which is also
the whole reduced-motion story. At most **one** strip runs across every surface:
`presenter.movingText()` is the count `text_audit.movingText` audits (allowance
1). `presenter.reveal()` reports the live strip — `{ present, sourcePath, phase,
travel, distance, text }`, frozen and safe when nothing is up — for inspection
and tests.

#### Anchored surfaces

`app.presentAnchored(component, options) -> close, node` — a surface positioned
against a **source view's screen rect** rather than a parent corner. The builder
receives `app.controls`, the same vocabulary an `app.mount` component closes
over. `presenter.presentAnchored(panel, opts) -> handle` is the presenter-level
form. This is what
a popover, a floating menu, a coach mark or a help plate needs and what
`UI.Anchor` deliberately does not do: `UI.Anchor` places a child at one of nine
corners **inside its parent** and never clamps (an off-screen drawer is a legal
thing to build).

The panel is **any node, never a `UI.Screen`**. The Screen root, the
full-viewport anchor layer, the window-space offsets and the arrow tail are
synthesized for you; the panel is mounted at `/<id>/Layer/Surface` and the tail,
when there is one, at `/<id>/Layer/Tail`.

```
options = {
  id?,      -- the surface's root id, default "Anchored"
  modal?,   -- true routes through presentModal (focus trap); default a screen
  anchor = {
    source = { path = "/Screen/Row/More" }  -- a MOUNTED node, followed as it moves
           | { rect = { x, y, w, h } },     -- or a fixed window-space box
    edge?     = "bottom",  -- "top" | "bottom" | "leading" | "trailing" | "overlap"
    align?    = "center",  -- "start" | "center" | "end", along that edge
    crossOffset? = 0,      -- px ALONG the alignment axis, before the safe clamp; a
                           -- flip changes the edge only, never the alignment or this
    gap?      = "s",       -- a theme metric name or a number
    maxWidth?, maxHeight?, -- px caps on the SURFACE (panel and chrome), kept inside the
                           -- LIVE safe box as insets change; absent = the plain hug
    margin?   = nil,       -- a floor on the safe box's side and bottom insets (a metric
                           -- name or px): a popover from a control passes "m" so it never
                           -- sits closer to the edge than the content it came from
    tail?     = false,     -- true, or { size?, surface?, cornerInset? }
    overflow? = "clamp",   -- "clamp" | "keep" — see below
  },
  chrome? = false, -- true = a LAYER, not a surface: no stack, no focus scope,
                   -- no input context (see below). Refused with `modal`.
  -- ...plus every presentation option above, which all work unchanged
}
```

**It reuses, it does not fork.** The stack, the focus scope, the input context,
the layering band, the tap-away catcher and the dismissal outcome are the
presenter's own — an anchored surface delegates to `present`/`presentModal`, so
`scrim`, `cancelPolicy`, `outsideTapCancel`, `initialFocus`, `transition`,
`navigationGroups` and the rest apply exactly as they do to any other surface.
`presenter.dismiss(handle)` retires it. A **tap-away** is the ordinary
contribution seam too: `Facet.contribution.attach(panel, { outsideDismiss = {
active, dismiss, consume } })` and the presenter synthesizes its own popup
catcher for this surface exactly as it does for a PopupButton, `consume = false`
included — the mode that dismisses without swallowing, so the control the panel
points at stays operable. `rootPolicy` is the one option it
constrains: an anchored surface is placed in **window space** (the coordinates
`controller.screenRectOf` answers in), so anything other than `"edgeToEdge"` is
refused rather than silently re-based by the safe-area inset. The safe area is
honoured by the placement itself.

**The placement rules**, in order — all four are
`src/layout/anchor_placement.luau`'s, a pure function of plain numbers that the
presenter's disclosure plate and `UI.RowActions`' floating menu also ask:

1. **Place** on the preferred edge, `gap` px off the source.
2. **Flip** to the opposite edge when the preferred placement crosses the safe
   box **and** the opposite one fits entirely. Both halves matter: it never flips
   into a worse place. When neither side holds it, it goes **beside** the source
   (the perpendicular edges, trailing or below first) if one holds it entirely;
   only a panel that fits nowhere is left to `overflow`.
3. **Shift** along the edge until the surface is inside the safe box.
4. **Tail**: centre it on the *source*, keep it clear of the panel's own rounded
   corners, and **suppress it** when the shift has carried it off the source —
   an arrow pointing at nothing is worse than no arrow.

`overflow` decides only what happens when the surface fits on **neither** edge:
`"clamp"` (default) pulls it back inside the safe box, which is right for a plate
nobody can read under a notch; `"keep"` leaves it clipped where the preferred
edge put it, which is right for a menu that must never cover its own trigger.

**A moving source is followed for free.** The placement re-runs on the presenter's
existing `refresh` and `tick` cadences — the same ones a real scroll and a late
text measure already drive — so a menu anchored to a row tracks that row frame by
frame with no watcher, no per-frame consumer call, and no writes at all while
nothing has moved.

**The tail is a rotated `UI.Box`, not a `UI.Path`.** `UI.Path` materializes as a
Roblox `Path2D`, which **strokes only** — there is no fill — so a solid wedge
cannot be drawn with it. A 45°-rotated square declared *before* the panel paints
behind it (document order becomes z order), so the overlapping half is covered
and the protruding half is the arrow. It wears the panel's own `surface` role, so
a theme swap moves both together.

**`chrome = true` makes it a LAYER instead of a surface.** A presented surface
pushes a focus scope even when it holds nothing focusable, and a scope with no
members is still the *top* one — so an ordinary anchored plate that is pure
decoration silently took the next arrow press away from the control it was
annotating (measured, 2026-08-16). A chrome layer hand-mounts its own controller
the way the disclosure plate and the toast strip already do: no stack, no focus
scope, no input context, no catcher — and the same solver, the same tail, the
same safe box and the same moving-source cadence. It is what `help` presents
through, and `chrome` and `modal` are refused together because they are
opposites. `presenter.dismiss(handle)` retires either shape.

`presenter.anchoredSurfaces()` reports every live one for inspection and tests.

#### Help

`UI.Button{ help = "…" }` (also legal on `Text`, `Toggle` and `TextField`) is one
sentence about what a view DOES, and the player pulls it:

| Input class | Show | Hide |
|---|---|---|
| mouse / pointer | hover, after a 0.45 s dwell | the pointer leaves, or the view is activated |
| keyboard / gamepad | on focus, immediately | on blur |
| **touch** | **nothing** | — |

**Nothing on touch is the specification, not a gap.** Help is a hover and a
focus-ring affordance: a pointer resting on a view, or a keyboard or gamepad ring
landing on it. No input class binds it to a long press, and neither does Facet,
because touch long-press is the disclosure plate's, and that
plate is the only touch route to a truncated label's own value. Two constructs
competing for one gesture on the only class where neither has an alternative is
the defect this restraint avoids.

The consequence is a **rule**: `help` is never the only route to something a
player needs. `text_audit.helpRoutes(presenter.helpDeclarations(), rects, opts?)`
enforces it, and it asks two separate questions:

- **`helpNoRoute`** — nothing engages this help on any live input class. **No
  waiver applies**: a declaration cannot answer whether a gesture exists, which
  is precisely the gap `clippedEssential` has (it accepts `disclose = true` and
  never asks whether the plate is still reachable).
- **`helpOnlyRoute`** — the screen paints this sentence nowhere else, so a player
  who never hovers cannot read it. `opts.convenience` (path prefixes or a
  predicate) waives this one, and only this one.

**The table form** adds a heading and placement: `body` is required (empty only
when `title` carries the words), `title` paints above it, and `shortcut` is a
display-only list of alternative chords in `UI.ShortcutHint`'s `keys` spelling
(`{ { "Ctrl", "K" }, { "F1" } }`) — it registers no action and no context.
`edge`/`align` place the plate (default `bottom`/`start`). `text_audit.helpRoutes`
checks `title` and `body` **separately**: a title the screen repeats never vouches
for a body it does not. For a touch player, say the words visibly or put an info
`UI.Button` beside the control that opens a [`UI.Popover`](#uipopover).

A live plate follows its source: a same-path node rebuilt with other help
re-presents, and its width stays inside the live safe box as insets change.

The plate is **chrome, not a surface**: it takes no focus, adds no focus stop and
binds no key. A truncated `disclose` label on the same engagement **outranks** it
— a player who cannot read the label needs the value before the convenience — and
the two are never on screen together. It carries D1's **arrow tail**, pointing at
the control the sentence is about. For an app-PUSHED plate that appears on
**every** input class, see [`UI.Callout`](#uicallout).

#### Toasts

`app.presentToast(component, options) -> { id, dismiss() }` — a transient,
**input-transparent**, self-retiring surface.
`presenter.presentToast(component, opts?)` is the same call.

**`component` is a function that returns the toast's node**, and it is called
with no arguments — close over `UI` (`local UI = app.controls`). A non-function
is refused at the call. The component runs inside the toast's own row, which
owns it: the row releases the component's resources when it retires.

```lua
app.presentToast(function()
	return UI.Text({ text = "Saved" })
end, { key = "save", duration = 3 })
```

```
options = {
  key?,        -- same-subject supersede
  priority?,   -- default 0; higher runs first in the queue
  duration?,   -- seconds visible, default 4
  readFloor?,  -- minimum dwell before anything may replace it, default 2.5
  position?,   -- "top" (default) | "bottom" — the edge it docks to
  width?,      -- normal Dim: UI.fill() (default), UI.hug({ max = 560 }), etc.
  transition?, -- default: slide from its own edge; fading is explicit
  context?,    -- carried untouched on the toast's dismiss event
}
```

- **Input-transparent is structural, not polite.** The toast layer is
  presenter-private: not in the stack, no focus scope, no input context, no tap
  handler, never `SelectedObject`. There is nothing for it to intercept input
  *with*, so a control beneath a toast activates normally and the focus graph
  reads identically before, during and after.
- **Scheduling** (`src/present/toast_schedule.luau`, pure and headless): max 3
  visible, queue cap 8, priority-ordered with FIFO inside a priority. A showing
  toast's **read floor is never truncated by priority** — an urgent message
  waits for the sentence to become readable, then preempts the weakest showing
  toast. At the cap the lowest-priority **queued** toast is dropped (never a
  showing one). Nothing vanishes untraceably: every retirement emits an event on
  the feedback bus, and it is a `dismiss` carrying one of four reasons —
  `timeout`, `capacity`, `preempt`, `manual`.
- **Supersede** replaces a same-`key` predecessor: immediately while it is
  queued, and at the read floor while it is showing (a same-subject toast never
  appears beside the one it replaces). **Replacement is its own verb**: the
  superseded toast emits `type = "supersede"` with **`reason = nil`**, never a
  `dismiss` — one causal moment, one event. Match on the type; a subscriber
  wired to `type == "dismiss" and reason == "supersede"` fires never.
- **Sizing and continuity.** Width is per toast: `UI.fill()` spans the safe
  content width, while `UI.hug({ max = 560 })` centers a content-fit toast and
  wraps longer text within the cap. The body must also permit content sizing.
  Surviving rows automatically slide into a vacated slot on either edge.
  Repeated changes retarget that motion; reduced motion places rows immediately.
- **Text rendering.** The default slide uses ordinary native text, without a
  CanvasGroup's quality-dependent texture. Request `fade = true` explicitly
  when that visual treatment is wanted; a fade requires compositing.
- `width` must be a **static** dimension — `UI.fill()` or `UI.hug({ max = … })`,
  never a readable or a function. A bound dimension is refused at the call.
- **Layering** puts it above every base screen and below every modal.
- **Reduced motion** changes the pixels and nothing else: the same toasts appear
  for the same durations in the same order, placed instantly (SF-T3).
- The first toast fixes the layer's edge and transition for the layer's
  lifetime, and the layer retires once nothing is showing, nothing is queued and
  no row is still playing its exit. Toasts are **display-only** in v1: an
  interactive toast is an explicit non-goal.

#### Semantic feedback

`presenter.onFeedback(fn) -> unsubscribe` (every surface — the primary seam) and
`handle.onFeedback(fn)` (filtered to that surface) subscribe to one per-presenter
bus. An event is `{ type, path?, surface?, reason?, context? }`.

**Facet plays nothing.** It never triggers a sound, a haptic or a particle — it
says what happened, on the frame it happened, with enough context for a game to
map it to its own assets and policy.

- **The v1 taxonomy is CLOSED:** `activate`, `select`, `adjust`, `pickup`,
  `commit`, `reject`, `cancel`, `arrive`, `land`, `dismiss`, `supersede`,
  `celebrate`. An unknown verb is an authoring error that lists the vocabulary;
  growing the set is a contract amendment with a gate. Carry your own meaning in
  `reason`/`context` instead of inventing one.
- `arrive` is any motion reaching its target (a transition's enter landing);
  `land` is a drag/commit payload reaching its resolved drop. Distinct verbs so
  their causal frames cannot merge.
- **Framework seams emit; raw motion tools do not.** Controls, sessions, surface
  transitions and commit flights publish their own events. A `clock:chase` you
  build yourself emits **nothing** — its `onArrive` is a callback, not a bus
  event — so the caller is what turns an arrival into `arrive` through
  `presenter.emitFeedback`. That split is deliberate (the raw tool has no idea
  what the flight MEANS), and it is the boundary at which causal-frame
  responsibility moves to you: emit inside the `onArrive` call, not a tick later.
- **Causal-frame exactness is the contract.** An event fires synchronously in
  the call that caused it, exactly once — `activate` after the effect, so a
  subscriber reading state sees the state the press produced; `dismiss` when the
  dismissal was *decided*, not when the pixels finish moving.
- `presenter.emitFeedback(event)` is the registration point for session events
  (`commit`/`land`/`reject`/`cancel`/`pickup`), so every semantic event a game
  hears — control, motion, toast, session — arrives on one bus with one
  taxonomy.

**No-pop text (`revealWhenTextExact = true`).** Text boxes start at a
conservative bound the engine's own measurements then tighten, one re-solve
later — so an ordinary screen appears with slightly wide boxes and visibly
shrinks. The shrink is always safe (the bound can only over-reserve; nothing
ever clips), but a screen can opt out of showing it at all: it mounts and solves
with its root hidden and reveals itself already exact.

Bounded by `revealTimeout` (default 2s) — on timeout it reveals with the safe
boxes, because a UI that never appears is a worse failure than one that jumps.
Needs an adapter with `setRootVisible`; without one the surface reveals
immediately rather than hiding forever.

Most screens do not need this. The Roblox adapter settles the engine's text
pipeline once at construction, during loading, so a UI presented after loading
measures correctly on its first read and has nothing to pop from. Reach for the
flag when a screen appears with text the session has never measured and the jump
would be noticeable.

**Modal outside-tap dismissal (two-zone spec).** While a
modal is up the presenter synthesizes a full-viewport **scrim/catcher** beneath
it, so every tap hits something. **Zone A** (the modal's *painted* panel ⊕ a 24 px
forgiveness ring ∪ each focusable's 44 px hit rect) never dismisses; **Zone B**
(everywhere else) dismisses. Only *painted* surface counts, so an invisible
`fill` root can't swallow taps while a visible fullscreen takeover has no outside.
Outside-tap, `ButtonB`/Cancel, and the Close button all resolve to the same
non-destructive outcome.
- `outsideTapCancel` (modal, default `true`) — `false` **swallows** the outside
  tap (a true barrier: no dismiss, no clickthrough).
- `cancelPolicy` (any surface, default `"dismiss"`) — what the **Cancel verb**
  (gamepad `ButtonB`) does to this surface once nothing else consumed it.
  `"dismiss"` is today's contract unchanged: a modal dismisses, an
  engaged-from-passive surface resigns. `"none"` makes Cancel a **no-op on this
  surface** — the mechanism for a **mandatory** surface, one whose choice has no
  legal "not now" (a role pick that parks the player until they choose), where
  dismiss-on-B would strand them behind a decision they never made. An unknown
  value is refused at present time, naming the set.
  It is deliberately **orthogonal** to `outsideTapCancel`, which governs the
  pointer path: a mandatory modal sets both. Cancel is still offered to the
  focused contribution's `handleCancel` **first**, so a popup open inside a
  mandatory modal still closes on B. `presenter.dismiss(handle)` and
  `presenter.back()` are explicit programmatic calls and are not gated by it —
  the surface's owner is always allowed to take it down.
- `scrim` — `"scrim"` (default for modals; dims at the `scrimOpacity` token) or
  `"none"` (transparent but still catching — a popover, or the default for an
  engaged HUD). Gamepad/keyboard are untouched; the scrim is never focusable.

**First responder.** `present()` default is today's engaged-open
surface (context enabled, non-sinking — correct for a UI-only place). `present()`
gains two options for real avatar games running the IAS player-script stack:

- `responder = "passive"` — a HUD that binds nothing gameplay-contended: its nav
  context is created DISABLED, so `deviceKey` navigation reaches the lower
  (gameplay) contexts and never moves the HUD's focus. The surface becomes first
  responder — raising itself into the engaged band (priority 3000, strictly above
  the doc-sanctioned gameplay sink at 2000, mirroring `ContextActionPriority.High`)
  with `Sink` — when the player taps one of its focusables or you call
  `handle.engage()`. It drops back to passive on Cancel (gamepad B), an outside
  tap, or `handle.resign()`. `handle.responder` reads `"passive"`/`"engaged"`.
- `gameplayGuard` (default `true`) — governs who owns `Space` while this surface
  is first responder. With a keyboard live, `Space` is bound to **Activate** in
  the surface's own context; with no keyboard capability it falls back to a no-op
  `GameplayGuard` action. **Whether that also takes the key from the game depends
  on whether this surface sinks**, and the two cases were measured live:
  · an **engaged-exclusive** surface (a modal, or a passive surface once engaged)
    sinks, so the focused control activates and the avatar's jump is sunk by the
    same binding;
  · a **plain `present()`** screen does not sink and sits at priority 1500, so a
    game context above it that sinks (the doc-sanctioned 2000 band) takes `Space`
    first and this surface's Activate never fires — while a bare non-sinking
    context below it shares the press instead.
  Set `false` for a surface that wants `Space` to reach the game (a word-game
  modal): it then binds neither the guard nor the Activate key. `ButtonA` is
  already sunk via Activate and arrows/D-pad via Navigate; WASD is not sunk in
  v1.

### Desktop keyboard conventions

With **keyboard capability live** (`env` `interactionClasses.keyboard`) and this
surface's responder **engaged**, the presenter binds two more keys, and removes
them again the moment either condition stops holding — so a phone with no keyboard
binds neither, a tablet that gains one starts behaving like a desktop with no
device branch anywhere, and a `responder = "passive"` HUD binds nothing at all
until `engage()`:

- **`Tab` / `Shift+Tab`** drive a `Traverse` action that walks the active focus
  scope linearly. **Platform limit:** Roblox documents `Tab` as reserved while the
  CoreGui **players list** is enabled (the default), and no `InputContext`
  priority is documented to outrank CoreGui — so assume the binding is inert
  until the consuming place runs
  `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)`. It is bound
  rather than refused because Tab is *not* in Roblox's hard-reserved set
  (`Esc`/`F9`/`F11`/`F12`/`PrintScreen`), so a UI-only place gets the convention
  for free. `gamepad_contention.traversalKeyContended()` probes the condition;
  Facet never disables a consumer's leaderboard. Everything else here — Space,
  the focused-value arrows, keep-visible, the modal trap — is uncontended.

  Traversal is a *second reading* of the same mounted focus graph the arrows
  walk, never a second focus system. Order is the scope's own order (a flat
  scope's `focusOrder`, or every navigation group's order concatenated in group
  order); hidden, disabled, non-focusable, retiring and losing-adaptive nodes are
  skipped because they never entered the graph, and live focus-skip predicates are
  evaluated at press time. Unlike the arrows, traversal crosses group boundaries
  unconditionally — containment exists to stop the arrows leaving, and leaving is
  Tab's whole job. A trapped scope (a modal, an open popup's transient scope) traps
  Tab too and restores the prior focus on dismiss, and every move runs through the
  same keep-visible service (`controller.scrollToVisible`) a directional move does.
  Wrap is `traversalWrap`, above. A focused `UI.TextInput` sees the press first
  through `handleTraverse` and commits before the ring moves — subject to the
  engine limit recorded on `handleTraverse` below.
- **`Space`** joins `Return` as **Activate**, subject to `gameplayGuard` — whose
  entry above records which surface kinds actually take the key from a game and
  which only share it.

**Activate `meta.pointer`** is a closed four-value enum naming the input class the
engine attributed the press to: `"mouse"`, `"touch"`, `"gamepad"`, and — since this
stage — `"keyboard"`, for the `Activated` the engine fires on a *selected*
`GuiButton`. The last two are not pointers: the field is named for its first and
commonest use and its vocabulary is now wider than its name (renaming it is a
breaking change, recorded rather than taken). An `InputObject` the engine reports
without a `UserInputType` falls back to `"mouse"`, so a consumer branching on this
should treat it as a hint about provenance, not an authority.

**Exactly one Activate per press.** When a surface opts into
`engineSelectionBridge` — the only thing that ever sets
`GuiService.SelectedObject` — the engine fires the selected `GuiButton`'s own
`Activated` for the *same* key press IAS already delivered as Activate. The
presenter collapses that pair, and it identifies it by **input class rather than
by which surface it is on**: an Activate whose native half reports a non-pointer
class (`meta.pointer == "keyboard"` or `"gamepad"`) within 50 ms of the action is
the same press echoing. The window is a chosen bound rather than a measured one —
far below any human double-press, and far above one frame — and the pair is spent
when it collapses, so a fast third press opens a new window rather than falling
inside the echo's. The rule is deliberately not scoped to the bridge opt-in,
because the class test is the stricter of the two and needs no per-surface state.
Two pointer taps, two key presses, and a real click beside a key press all remain
two presses.

**Two plain `present()` screens share one focus graph.** Base screens sit at the
same priority and do not sink, so both would receive `Tab` (and the arrows) and
both would step the one focus ring. That is unchanged by this stage and the
guidance is unchanged with it: present the second surface as a modal, or as a
passive HUD that engages.

`presentModal` is always engaged-exclusive (`responder` has no effect on it).

**Input auto-wiring.** Composite controls attach an input-contribution
bundle to their root node; the presenter walks the mounted tree, discovers the
bundles, and AUTO-COMPOSES each screen's four-input story — navigation groups,
Activate dispatch, grab-mode intercept, focus-move reporting, geometry feed,
keep-visible offset, and action-system binding — so mounting a control yields its
full input story with no consumer wiring. Every option above OVERRIDES its auto
counterpart, per-option, so hand-wired screens are unaffected. Specifics:
`navigationGroups` — absent auto-derives grouped nav when any contribution
advertises focus groups (else the flat ring), an array/function pins explicit
groups, and `false` forces the flat ring (a legacy flat-list consumer opting out
of auto-grouping); `keepVisibleOffset` absent observes every contribution's offset
and applies the max; the presenter always binds `actionSystem` into every
contribution at present time (idempotent).

**Contribution bundle (`src/input/contribution.luau`).** The bundle a composite
attaches to its root (`contribution.attach(rootBlueprint, bundle)`; every field
optional): `focusGroups(rootNode)`, `handleActivate(path, meta)`,
`navigateIntercept(direction)`, `focusMoved(path)`, `syncGeometry(rectOf)`,
`keepVisibleOffset` (a readable number), `bindActionSystem(actionSystem, surfaceContextOf?)`,
`bindFocusGraph(focusGraph)`, and the **paradigm-axis seams** (UI-PARADIGM-001):
- `bindActionSystem(system, surfaceContextOf?)` receives an optional getter for
  this surface's own context. It initially returns nil: contributions bind before
  the context exists. The getter starts answering before the surface publishes
  its actions. Existing one-argument contributions work unchanged; binding may
  repeat during structural refresh, so keep it idempotent.

- `bindFocusGraph(focusGraph)` — the presenter hands over the screen's focus graph
  at the same moment it binds the action system and the controller, for the one
  case a control has to **move** focus rather than follow it: the data under a
  focused row changed and the control's own policy says the ring belongs
  somewhere else now (`UI.VirtualList.focusPolicy = "index"`). It is the canonical
  route — a control handed the graph by its *consumer* leaves the consumer owning
  half the focus story. Absent, the control degrades to logical focus only.
- `adjustTargets(rootNode) -> { [path]: true }` + `handleAdjust(path, direction)`
  — the Adjust verb (grip resize, value stepper). The presenter binds the Adjust
  keys DYNAMICALLY — only while the focused path is a declared target — so a bare
  screen never shadows gameplay arrow/bumper keys off-target. `direction` is −1 /
  +1; `handleAdjust` returns true when consumed; longest-path-prefix wins.
  `opts.onAdjust` still overrides both per-opt.
- `adjustAxis = "horizontal" | "vertical" | "none"` — which **arrow keys** the
  control's declared targets consume while one of them holds focus.
  `"horizontal"` takes Left/Right + DPadLeft/DPadRight; `"vertical"` takes
  Up/Down + DPadUp/DPadDown; `"none"` takes neither and leaves the shoulders.
  The *other* axis keeps navigating. Comma/Period and L1/R1 are axis-independent
  and are bound for a declared target either way. Any other value is refused at
  `contribution.attach`, naming the three legal ones.

  **Choose the axis your screen does not navigate on.** On a *grouped* screen both
  axes navigate, so either choice leaves the ring a way out on the arrows plus Tab.
  On a *flat* screen only the vertical axis navigates — so `"vertical"` there takes
  the only arrows that could move focus, and **Tab becomes the only way off the
  control**. Every shipped value control declares `"horizontal"` for this reason;
  `"vertical"` exists for a genuinely vertical value (a level meter, a
  bottom-anchored slider) and is the author's call to make knowingly.

  Omitting it is a real choice, not an oversight: an undeclared target takes
  Comma/Period and L1/R1 always, plus the horizontal arrows only on a *flat*
  screen where nothing else wants them. `UI.Slider`, `UI.Stepper` and
  `UI.Rating` declare `"horizontal"` because their value **is** that axis;
  `UI.Table` deliberately does not, because its resizable headers are navigation
  stops and adjust targets at once and it resolves the contention with a mode
  (Activate selects the column, then the arrows resize it, Cancel releases).
- `handleTraverse(path, direction) -> boolean` — a chance to consume Tab /
  Shift+Tab *before* the focus ring moves. `direction` is +1 (Tab) or −1
  (Shift+Tab); return true to keep focus where it is, false/nil to let the
  presenter traverse. Longest-path-prefix wins, like `handleActivate`. It exists
  for controls that must finish something first: `UI.TextInput` commits through
  its own validation path and then returns false, so Tab out of a field never
  types a tab character and never advances out of an unfinished edit. **Engine
  limit:** while a `TextBox` holds keyboard focus, Roblox marks keyboard input
  `gameProcessed` and fires no developer Input Action binding, so this seam is not
  reached on today's engine and Tab inside a focused field does nothing at all
  (measured; `artifacts/desktop-keyboard-navigation/decisions.md` DKN-2). The
  contract is headlessly proven and engages unchanged when the engine delivers the
  key; `Return` commits today.
- `handleCancel(focusedPath) -> boolean` — Cancel (gamepad ButtonB) is offered to
  the focused contribution BEFORE the presenter's modal-dismiss / passive-resign
  branches (first true consumes; false falls through, so a modal containing the
  control still dismisses on a second ButtonB).
- `outsideDismiss = { active, dismiss }`, where `active` is a readable boolean — while `active`, a
  tap outside the contribution's subtree dismisses it (non-destructive) and the
  presenter synthesizes a transparent full-viewport catcher so a tap on empty
  space dismisses too (the two-zone model without making the control a modal).
  Optional `passThroughRect`, a readable `{ x, y, w, h }` or nil, cuts a window-space native
  rectangular aperture out of that catcher and excludes taps there from sibling
  dismissal. The declaring control must leave the same aperture in its own input
  geometry; RadialMenu does so. `consume` defaults true.
- `transientScope = { active, rootPath? }`, where `active` is a readable boolean — while `active`,
  focus is trapped within `rootPath` (default: the control root) and restored to
  the pre-activation path on deactivation. **It flattens navigation inside the
  trap**, and that is worth knowing before you design the surface: the trap is a
  FLAT focus scope over `rootPath`'s subtree, so while it is up the trapped
  nodes walk in document order on one axis. A `UI.Grid` inside a transient
  surface therefore does not get the per-lane navigation the same grid gets on
  an ordinary screen. Everything stays reachable; the lane movement does not
  exist while the trap is up. There is a second reason a late grid gets no lanes
  and it compounds this one: `presenter.present` chooses its navigation
  derivation ONCE, from the tree as it stands at present time, and only a late
  `focusGroups` CONTRIBUTION upgrades it afterwards — so a `UI.When` that opens
  a grid cannot acquire grid navigation later either. Decide between the trap
  and two-dimensional movement deliberately; you cannot have both today.

PopupButton is the worked example (outside-tap dismiss, ButtonB close, focus
trap-and-restore) without engaging the modal machinery.

---

## Environment

### `newEnvironment`

`Facet.newEnvironment(core) -> Env` — per-client observable platform facts plus
derived policy. `core` is a per-application service bag
(`src/core/services.luau`); `Facet.new()` and `client.host.new()` both build one
environment for you and hand it back as `app.environment` / `host.env`, so most
code reads an environment rather than constructing one.

`env:get(key)` answers a Compose readable (any key, fact or
derived; an unknown key errors), `env:set(key, value)` (**facts only** — setting
a derived key errors), `env:batch(body)` (below), and `env:keys() -> { string }`
(every key, sorted, facts and derived merged with no marker distinguishing them —
the split is the table below). The client adapter
(`src/client/roblox_env.luau`) pushes the real engine facts; tests set fakes.
Read facts inside a Compose recipe with `use(env:get(key))`, or use
`env:get(key):peek()` for an untracked read. `env:dispose()` releases the
environment’s Compose owner and registration. The application host calls it
automatically; standalone environments must be disposed by their owner.

**`env:batch(body)` — one real change is one fact-group.** An adapter almost
never learns a single fact at a time: one device rotation teaches SIX at once
(the viewport, three inset shapes, the topbar rect and the size class). Written
loose, each is its own flush, and everything downstream — the renderer's
re-solve above all — pays once per *write* for a change the player made once.
`env:batch` runs `body` inside one reactor batch: writes are invisible to
observers until the outermost batch closes, nested batches collapse into it, and
formulas stay glitch-free throughout.

```lua
env:batch(function()
    env:set("viewportRect", rect)
    env:set("coreSafeInsets", insets)
    env:set("displaySize", "Medium")
end)
```

Two things `env:batch` is NOT. It is a **grouping, not a rollback**: if `body`
throws, the writes made before the throw have landed and observers fire once for
them — the error is re-raised, but the group is partial. And **`body` must not
yield**: the transaction stays open across the yield, so every observer in the
session — not only this environment's — waits, and any unrelated `env:set` made
meanwhile is held with it.

Measured on a 40-row tree (`tests/geometry_solve_coalescing.spec.luau`,
optimization-log L-29): those six writes loose cost **5 solves**; batched, **1**.
On the 2026-08-13 device capture a solve was 8.270 ms of arrange + 3.057 ms of
measure, so the difference is ~45 ms of a ~200 ms frame. Group whatever ONE
platform event taught you; do not group across events, or a surface will paint a
mixture of two moments.

**The keys are the API.** Settable facts:

| Fact | Value |
|---|---|
| `viewportRect` | `{ x, y, w, h }` of the window |
| `deviceSafeInsets` | per-edge `{ top, bottom, left, right }` device (notch) insets |
| `coreSafeInsets` | per-edge CoreGui reservation — the DEVICE safe area, the platform adapter's to write |
| `appChromeInsets` | per-edge reservation for the HOST APP's own persistent chrome (a showcase's chip strip, a game's always-on top bar), zero by default. Device safe area vs host reservation; modals honour the device only — a content policy adds this to `coreSafeInsets`/`deviceSafeInsets`, and `presentModal`/`presentCritical` do not, so an alert centres on the whole screen instead of on the space under your chrome. The four-edge sibling of `appChromeRects` (which says WHERE that chrome is, for per-column reservation); `bandSafeContent` consumes the rects rather than this box |
| `appChromeRects` | the host app's own chrome as a LIST of window-space rects, `{}` by default — merged into `platformChrome.rects` beside the engine's own cluster |
| `topbarInset` | the platform's FREE topbar rect `{ x, y, w, h }`, in WINDOW space (`GuiService.TopbarInset`) |
| `topbarSafeInsets` | per-edge topbar-safe area — the SAME band as `topbarInset`, stated as edges. Read `platformChrome` rather than either of these; it is the one place that knows what a zero means |
| `keyboardOcclusionRect` | `{ x, y, w, h }` the soft keyboard covers, or `nil` |
| `preferredInput` | `"Touch" \| "Gamepad" \| "KeyboardAndMouse"` — what was used LAST (see below) |
| `capabilities` | `{ keyboard, mouse, touch, gamepad }` booleans |
| `reducedMotion` | boolean |
| `preferredTextSize` | multiplicative text-scale seam (tests and device profiles); the engine leaves it at 1 |
| `preferredTextOffset` | the engine's ADDITIVE preferred-text reservation, in px. The Roblox adapter maps the live `PreferredTextSize` enum through measured per-preference constants (Medium 0 / Large 4 / Larger 10 / Largest 14 — uniform across font, weight, and size; confirmed per session via `GetTextSizeOffsetAsync`, cached, failure-safe) and subscribes to changes, so a mid-session preference step is one atomic re-solve of every mounted surface — never a remount. Tests inject this fact directly; the live adapter and the injected path never both apply (Step 8.5, decision LTN-1) |
| `preferredTransparency` | 0..1 |
| `locale` | e.g. `"en-us"` |
| `displaySize` | `"Small" \| "Medium" \| "Large"` (the engine's viewport display class) |
| `overscanInsets` | authored TV overscan margins, or the string `"none"` to opt out |
| `presentationSpace` | `"screen" \| "billboard" \| "world"` — where this surface is presented |
| `viewingDistance` | `"automatic"` (default) \| `"near"` \| `"ten-foot"` — the authored viewing context. An unknown value is refused |
| `themeMetrics` | the frozen `ThemeSnapshot`; the single atomic metric commit point. **What you SET is the authored ladder; what you READ is that ladder with the display class's distance policy applied** — the same key, one seam, and the identity on every near display (the very table you committed, not a copy). On a `Large` display the read carries `density = "ten-foot"`, `metricScale = 1.5` and the scaled ladder. See "The ten-foot metric ladder" below |

Derived policy (memoized, read-only):

| Derived | Answers |
|---|---|
| `typographyScale` | the MEASURE-seam text scale: `preferredTextSize` clamped to 0.5–3, times 1.5 at ten-foot (`effectiveDisplaySize == "Large"`) |
| `typographyPaintScale` | the PAINT-seam scale: the ten-foot factor only (1.5 at ten-foot, else 1). The engine applies the player's preference itself, so paint must not multiply it in again |
| `themeMetrics` (derived half) | the metric authority as PRESENTED at this display class — `themes.forDisplay(<the committed snapshot>, effectiveDisplaySize)`. Listed under the facts above because it is the same key; listed here because reading it is a derived read. It is the ONE place the ten-foot metric ladder is applied |
| `effectiveTransparency` | `preferredTransparency` clamped to 0–1 — the player's **Background Transparency** setting. The framework paints with it: the one see-through background it owns (the `scrim` surface, which is the modal backdrop and anything a consumer declares `surface = "scrim"`) is composed `themeDim × effectiveTransparency`, in both paint modes. An authored `opacity`, the disabled dim, hairlines and shadows are deliberately untouched |
| `sizeClass` | `"compact" \| "regular" \| "wide"` from `viewportRect.w`, capped at `regular` at ten-foot (`effectiveDisplaySize == "Large"`) |
| `motionPolicy` | `"reduced"` when `reducedMotion` is true, else `"full"` |
| `distanceProfile` | `"ten-foot"` when `effectiveDisplaySize == "Large"`, else `"near"` |
| `effectiveOverscanInsets` | authored `overscanInsets` when any edge is non-zero; `"none"` means all zero; otherwise, at ten-foot, the console profile as a **fraction of the viewport** — `60/1080` of its height and `90/1920` of its width, rounded to whole pixels, so a 1920×1080 display reserves exactly 60/60/90/90 and a smaller window reserves the same *proportion* rather than the same pixels. Zeros on a near display. |
| `platformChrome` | WHERE THE PLATFORM'S OWN CONTROLS ARE: `{ band, rects, insets, bandInsets }`. `band` is the free topbar strip in window space or `nil`; `rects` is what the engine's own controls occupy (a list — the top band minus a free strip is an L); `insets` clears everything (what `deviceSafeContent` applies); `bandInsets` clears everything except the free band |
| `presentationProfile` | `{ space, flat, world }`; an unrecognised `presentationSpace` resolves to `"screen"` |
| `scrollIndicatorPolicy` | `"always"` when the primary interaction class is `pointer`, else `"auto"` |
| `distanceProfileSource` | `"inferred"` while `viewingDistance` is `"automatic"`, else `"authored"` |
| `interactionClasses` | the LIVE set of input idioms plus `primary`: capabilities and preference together, never the preference alone |
| `effectiveInput` | `interactionClasses.primary` in the platform fact's own vocabulary |
| `effectiveDisplaySize` | `displaySize`, corrected: `"Large"` downgrades to `"Medium"` when `capabilities.touch` is also true, else passes through unchanged. Read by every ten-foot-sensitive derivation above (`typographyScale`, `typographyPaintScale`, `themeMetrics`, `sizeClass`, `distanceProfile`, `effectiveOverscanInsets`, `platformChrome`) instead of the raw fact — see below |

**Where the clamping actually happens.** `env:set` validates only that the key
exists and is settable — it does **not** check the value, so a fact reads back
exactly what the adapter pushed. It is the **derived** memos that clamp garbage
into a legal domain (a NaN text preference resolves to 1, an out-of-range
transparency clamps to 0..1, an unknown presentation space falls back to
`"screen"`). Read the derived key when you want the guarantee; a consumer that
reads `viewportRect` straight is reading the adapter, unfiltered.

**`preferredInput` is a REPORT, `effectiveInput` is the ANSWER.** The platform
fact says which input was used *last*, so a phone nobody has touched yet reports
`KeyboardAndMouse` — the engine's default, not a fact about the device. Anything
choosing an affordance or a layout density from it gets a touchscreen wrong until
the first tap. `interactionClasses.primary` therefore resolves the primary class
from **capability** when no preference has been expressed (a mouse still wins
outright, so desktops and hybrid touch-laptops are unchanged), and
`effectiveInput` is that same answer in the platform fact's own vocabulary
(`"Touch" | "Gamepad" | "KeyboardAndMouse"`). **Read `effectiveInput`, not
`preferredInput`,** unless you specifically want "what did they touch last".

This was one defect with two faces (2026-07-29): a touch-only device installed the
compact *pointer* theme package, and a phone took the Table's dense pointer row
height and reflowed the whole page — canvas and scrollbar with it — on the
player's first touch.

**Viewing context and input are independent.** `viewingDistance` is an authored
fact: `"automatic"` (default), `"near"`, or `"ten-foot"`. An explicit distant
setting resolves `effectiveDisplaySize` to `"Large"`; explicit near changes a raw
`"Large"` to `"Medium"` and preserves `"Small"`. Automatic retains the existing
inference (raw Large plus touch capability resolves to Medium). This inference
cannot determine where a player sits. `distanceProfileSource` reports `"authored"`
or `"inferred"`; `distanceProfile` remains `"near"` or `"ten-foot"`.

The resolved display drives typography, theme metrics, density, focus treatment,
and default safe margins together. Raw `displaySize` remains the engine report.
Input/capability changes cannot override an explicit viewing distance. Hosts may
persist the player's setting; Facet does not create a preference store.

---

## Input

### Requirement: `Workspace.PlayerScriptsUseInputActionSystem`

**Facet's input layer is the Input Action System and nothing else.** The client
adapter (`src/client/roblox_input.luau`) drives `InputContext` / `InputAction` /
`InputBinding` and deliberately never touches `ContextActionService` — arbitration
is the engine's job, and a UI framework that outbid a consumer's own bindings
would be a worse problem than the one it solved.

**An experience embedding Facet must therefore enable
`Workspace.PlayerScriptsUseInputActionSystem`.** Roblox documents it as
controlling "whether the built-in player scripts are updated to use the Input
Action System"
([`Workspace` API reference](https://create.roblox.com/docs/reference/engine/classes/Workspace)).
With it off, Roblox's own scripts hold keys through `ContextActionService`, where
no `InputContext` can reach them, and any Facet surface that binds those keys
silently does nothing:

| what holds it | keys | what goes dead in Facet |
|---|---|---|
| `RbxCameraKeypress` (default camera, CAS priority 2000, sinks) | `Left` `Right` `I` `O` | horizontal focus navigation; a Table's selected-column resize |
| `jumpAction` (legacy control scripts, CAS priority 2000, sinks) | gamepad `ButtonA` | gamepad Activate on every control (D-pad still works, masking it) |

**A higher priority does not work, and this is the part worth reading twice.** CAS
priority and `InputContext.Priority` are **not one arbitration space**: a sinking
CAS binding consumes the key before any `InputContext` is offered it, at any
priority. Measured live 2026-08-14, four readings in one session — a CAS sink at
priority **100** beat a Facet `InputContext` at **10000** with `Sink = true`; a
claim built at 10000 was measured inert and removed rather than shipped
(`the-camera-still-owns-the-arrow-keys`).
Enabling the property is what moves those bindings *into* the space where priority
means something.

**It is a human checkbox — Studio's Properties panel, Workspace, category
Behavior, once per place.** The property is present in the engine's reflection
database but is **not scriptable** (re-probed on `0.734.0.7340915`, 2026-08-15:
a plain read answers "is not a valid member", `GetPropertyChangedSignal` answers
"is not a **scriptable** property", and a made-up name answers "is not a valid
property **name**" — three distinguishable sentences). It is also not
Rojo-syncable. So no Facet version on any build can read it, set it, or verify
it, and every diagnostic below is necessarily *behavioural* — it observes the
symptom, never the setting.

**The three probes** on `client.gamepad_contention`, all guarded (they return
`false` headless, off the live client, and never throw):

- `cameraKeysContended()` — is any CAS binding holding `Left`/`Right`/`Up`/`Down`?
- `legacyStackActive()` — is `jumpAction` bound (gamepad `ButtonA` contended)?
- `traversalKeyContended()` — is the CoreGui players list holding `Tab`?

The first two read **different bindings and neither substitutes for the other**:
measured 2026-08-15, the camera held the arrows in a session where `jumpAction`
was not bound at all, so `legacyStackActive()` answered `false` while horizontal
navigation was dead.

**None of them warns on its own.** They are asked, never announced. In any place
that has not enabled the property all three are true — today that is every default
Studio session — and a warning that always fires is noise. Call them from a doctor
check or when something looks dead; `describeContention()` returns the whole engine
truth set as one string for a log line.

### `newActionSystem`

`Facet.newActionSystem(core) -> ActionSystem` — the headless semantic-action
pipeline (the client swaps in `src/client/roblox_input.luau`, which drives
the same interface from the engine's Input Action System). Contexts own
priority/sinking/lifetime: `system.createContext{ name, priority, sink }`,
`context.createAction(name, type)`, `action.bind(binding)`,
`action.onPressed(fn)`, `action.state` (Readable). Test input goes through
`system.deviceKey(keyCode, isDown)` — the same path real bindings use; no
direct callback bypass. Controls never bind hardware key codes themselves.

The rest of the surface: `system.deviceAxis(axis, x, y)` and
`action.bindAxis(spec)` (the analog path the presenter binds unconditionally),
`system.modifiers() -> { shift, toggle }` (live modifier state the presenter
reads for shift/toggle Activate semantics), `action.onReleased(fn)`,
`action.preferredBinding(kind)`, `binding.remove()`, `context.setEnabled(on)`,
`context.setSink(on)`, and `context.destroy()` (the grandfathered teardown verb
for input contexts — constitution E-17). Prefer the setters over writing
`context.enabled`/`.sink` directly: a bare field write works headlessly and is
dead on the real engine adapter.

**One key edge, one delivery.** A `Bool` action that becomes armed while one of
its keys is already held (its context is enabled, or the binding is added,
mid-press) treats that hold as an arrival. Its state follows the key, but
neither the press nor its release reaches `onPressed` or `onReleased`, and the
key's release ends the arrival. So a Delete that removes the focused tag cannot
also remove the tag that focus moves to, and a context enabled by a ButtonA
press does not receive that same press. The engine adapter keeps the same rule.

`system.actionNamed(name, preferredContext?)` resolves a non-destroyed preferred
context first, even if disabled; otherwise it uses enabled contexts by descending
priority, with creation order breaking ties. This names a binding; it does not
change input arbitration. `system.revision` is a Compose cell advanced after
context/action/binding changes that affect lookup, and native engine preferred
binding changes. `preferredBinding(kind)` chooses a live binding from that
resolved device class first; an engine preference breaks ties only within it.
Non-touch callers can fall back to the first real key; touch has no key fallback.

**Lifecycle.** The system is a **session object**: it holds every context it
created, every action on them, and the action state/revision Compose cells. It lives as long
as the surface it serves, and it is put down explicitly.

- `system.contextCount() -> number` — how many contexts it is still holding.
  A destroyed context removes itself, so a nonzero count at teardown means
  something is still held.
- `system.dispose()` — destroys every context it still holds, releasing their
  signals. **Idempotent**, and safe after you destroyed some contexts by hand.
  A disposed system is **inert, not broken**: `deviceKey` and `deviceAxis` return
  immediately rather than throwing, because the engine's input stream does not
  stop the instant you call this and an event already in flight lands afterwards
  on the render thread, where a throw is a crash in somebody else's frame.

`Facet.new()` and `client.host.new()` build the system for you, and
`host.dispose()` disposes it: the host tears down every collaborator it holds
that carries a `dispose`, in reverse construction order. That applies to a
system handed in through `opts.newInputSystem` too, so a system you mean to
share across surfaces is one to keep out of the host.

**`action.bind{ ..., modifiers = { shift: boolean? } }` (Task 8b, additive).**
A keyCode binding may declare a held-modifier requirement; only `shift` is
wired (`ctrl`/`alt` are not accepted — `system.modifiers()` only tracks
`shift` distinctly from a single merged `toggle` group, so they could
type-check but never match anything real). A binding with no `modifiers`
matches exactly as before this field existed. A binding WITH `modifiers`
matches only while every declared flag is held; a key-UP additionally
matches whichever specific binding actually received the matching key-DOWN
(a binding-scoped stamp, not a shared read of its action's own state — an
action-scoped read let one binding's key-up rob a DIFFERENT binding's own
release when they shared an action, fix round 2 / platform review
MAJOR-1). Headlessly, this — through the EXISTING priority/Sink
arbitration, not a new rule — preempts an unmodified sibling binding on the
same key the instant it becomes an eligible candidate (the row-actions
Shift+Return menu, `UI.RowActions` above, is the shipped example: it wins
over the base screen's own unmodified `Return` Activate binding only while
shift is held, and is not a candidate at all otherwise, so plain Return is
unaffected). Gamepad bindings never declare `modifiers` and so are
unaffected by any held keyboard modifier.

On the real engine adapter, a modifier-gated binding is realized as TWO
ordinary `InputBinding`s (one `PrimaryModifier = LeftShift`, one
`PrimaryModifier = RightShift` — `PrimaryModifier` is a single
`Enum.KeyCode` and there is no combined "Shift" enum) under the SAME
action/context as any other binding — no second mechanism, no separate
event wiring: real `InputBinding` DOES carry a modifier concept
(`PrimaryModifier`/`SecondaryModifier`, official engine class reference:
"will only trigger the parent InputAction if this input is pressed prior
to KeyCode... If set to Enum.KeyCode.Unknown, no [...] modifier is
required"), so both bindings inherit their context's live
Enabled/Sink/Priority for free, through the identical engine arbitration
every other binding already goes through. (An earlier round of this
feature assumed real `InputBinding` had no modifier concept at all and
built a hand-rolled companion-`InputContext` toggle instead; that premise
was never checked against the engine's own reference and was wrong — the
companion mechanism is gone.)

**`system.resetModifiers()`** clears tracked held-modifier state (the
headless adapter's `modifierKeysDown`, e.g. `LeftShift`/`LeftControl`). A
defensive escape hatch, not wired to any automatic call site: headless
`deviceKey` is a test/scenario-authority surface only (no production code
path drives it — the client always runs the real adapter, whose
`system.modifiers()` live-polls engine key state instead of caching it, so
it cannot get stuck the same way). A scenario simulating an interrupted
chord (a modifier key down with no matching up) can call this between steps
rather than leave a phantom `true` for the rest of the run.

**`action._deliver(value, sourceGamepad?, sourceBinding?)` and
`binding._sample(x, y)` are the engine-adapter seam.** The leading underscore
means exactly that (constitution §2): they are how an alternate action-system
adapter — `src/client/roblox_input.luau` is the first-party one — delivers
state into the headless model. They are not private, and they are not for
consumer code: a control or a screen drives an action through
`bind`/`deviceKey`, never through these. `sourceGamepad` (d-pad
auto-repeat) records whether the BINDING that produced this value is
gamepad-classed — every `ButtonX`/`DPad*` keyCode and every axis binding
(`Thumbstick*` is gamepad-exclusive in this vocabulary) is; a keyboard keyCode
or a scriptable binding is not. Read back as `action.lastGamepad`, a plain
(non-reactive) field correct exactly at the moment a real change fires — a
deduped re-delivery of the same value never reaches the line that would update
it. `sourceBinding` (director item 4 review) is that same
binding object, read back as `action.lastBinding` for `system.wouldWinArbitration`
below.

**`system.wouldWinArbitration(context, binding) -> boolean`** (director item 4
review, C1: the d-pad repeat leak). A pure query — never a delivery — that
answers "if a real event arrived on this binding's keyCode/axis right now,
would it still reach this context": the same priority/enabled/sink arbitration
`deviceKey`/`deviceAxis` apply for a real event, replayed over the CURRENT set
of contexts. A HELD `Direction1D` value can go stale with nothing left to ever
correct it — a context disabling itself no longer zeros the value on its own
(see `context.setEnabled` below), and a NEW higher-priority sinking context
created after a hold began (a modal opening on top) permanently outranks a
lower-priority context for any keyCode/axis they share, with no future engine
event ever re-arbitrating an already-held key to notice. A per-frame consumer
of a held value (the presenter's d-pad auto-repeat) calls this every tick,
alongside `action.lastBinding`, to notice the moment ownership is lost and
correct `action.state` itself rather than trusting a value nothing will ever
update again. Does not replicate Task 8b's `modifierMatch` filtering — every
caller today drives it from a gamepad-classed binding, and gamepad bindings
never declare `modifiers`.

**`context.setEnabled(false)` zeros every `Direction1D` action's state to `0`,
not only `Bool` actions to `false`** (director item 4 review, C1). A disabled
context can never win arbitration again until re-enabled, so the key-up that
would otherwise zero a HELD `Navigate`/`Adjust` value never arrives —
`handle.resign()` disables a surface's context exactly this way while a
direction can still be physically held. Reading a stale nonzero value off a
disabled context's action was a live hazard independent of the d-pad
auto-repeat finding that surfaced it.

### `inputHint`

`Facet.inputHint(core, env, action, opts?)` — a reactive input-affordance label
for an action, answered as a Compose readable string. It tracks the
environment's `effectiveInput` fact and resolves the action's
`preferredBinding(...)`. Labels prefer the binding's explicit `displayName`, then
UserInputService's native name, a shared readable name, and the raw key/uiButton.
Whitespace-only or unchanged enum answers do not replace the readable fallback.
No binding yields `""`; non-touch classes may fall back to another actual key. Bind the readable to a `UI.Text` `text` prop and the label
re-flips with no remount when the player switches input device:

```lua
local env = app.environment
local hint = Facet.inputHint(core, env, activateAction) -- "Enter" | "A" | "Tap"
return UI.Text("Hint")({ text = hint })
```

The returned formula belongs to the Compose owner that is active when you call
it, so calling it inside a component ties its lifetime to that component.

**`opts.style`** is `"key"` (default, the bare label) or `"phrase"`, which answers
the whole affordance — `"Press Enter"`, `"Press A"`, `"Tap"` — so a consumer can
write one template instead of branching on input class to author copy:

```lua
local how = Facet.inputHint(core, env, activateAction, { style = "phrase" })
local line = Compose.formula(function(use) return `{use(how)} to apply` end)
```

A key label alone cannot remove that branch, because touch does not differ by
KEY, it differs by VERB: you tap, you do not press Enter.

An unknown `style` is refused at the call, naming the two legal values — the
same rule `rootPolicy` and `cancelPolicy` follow. So is an unknown `opts` key.

This helper tracks input-class changes for the action object it was given;
it does not subscribe to same-class binding mutations. Use `UI.ShortcutHint`
when the affordance must follow a live semantic action lookup and rebinding.

**`opts.scope`** takes an owner and disposes the returned formula with it. Omit
it and the active Compose owner has the memo; outside any owner, disposing it is
yours.

Invariants: it never injects visible UI on its own (the consumer decides where
the label appears). It reads `env:get("effectiveInput")` — a change re-labels the
same node, with no factory rerun.

### `adaptive`

`Facet.adaptive` — the adaptive-layout decisions. Two halves, both usable
independently.

**Pure functions** (no core, no environment, no DataModel — deterministic and
headlessly testable):

| Call | Result |
|---|---|
| `adaptive.sizeClass(width, opts?)` | `"compact"` (< 600) / `"regular"` (< 1000) / `"wide"`. `opts.distanceProfile = "ten-foot"` caps the result at `regular`, because a TV at 3 m must not resolve the densest arrangement however wide it is. A nil or NaN width degrades to `"compact"` rather than to a nonsense class. |
| `adaptive.axisFor(width, opts?)` | `"y"` below `opts.stackAbove` (default 600), `"x"` at or above it |
| `adaptive.columnsFor(available, minColumnWidth, gap?, opts?)` | the column count a `UI.Grid` with that `minColumnWidth` will derive — **literally** the same arithmetic, since the solver's grid calls this function. `opts.distanceProfile = "ten-foot"` takes the count against `BREAKPOINTS.wide` rather than the raw extent, the same cap `sizeClass`/`heightClass` apply and for the same reason (ADAPT-23: uncapped, the documented adaptive-grid route gave a television ELEVEN columns against a desktop's nine). The lanes still divide the whole extent, so a TV gets fewer, larger cards. `UI.Grid` passes the fact itself, from the theme snapshot's `density` |
| `adaptive.heightClass(height, opts?)` | `"short"` (< 600) / `"medium"` (< 1000) / `"tall"`. `opts.distanceProfile = "ten-foot"` caps at `"medium"`, for the same reason the width cap exists: `tall` is the densest vertical arrangement. Degrades to `"short"` on nil/NaN |
| `adaptive.orientationFor(width, height)` | `"landscape"` / `"portrait"` / `"square"` — a **shape** fact, not a device fact: a windowed pane on a desktop is portrait and must be treated as one |
| `adaptive.navPlacement(facts)` | `"bottomBar"` / `"bottomBarCompact"` / `"topBar"` / `"sidebar"` — THE app-level tab/sidebar placement policy: ten-foot → a centered top bar regardless of input or viewport shape; otherwise compact width → a full-width bottom tab bar in the thumb zone; short height → the same bar in its reduced INLINE form (CENTERED and hugging its tabs rather than dividing the width — a landscape phone. The band's HEIGHT is the same 46px and the labels are the same words: a terser thumb-zone name is the author's, through `Option.label` as a Readable — the reference shells carry a second localized string for exactly this — or the shrink ladder's own `compactLabel` when the words stop fitting. ADAPT-30: this line used to promise "short labels, tighter band", which never shipped); pointer-primary → a sidebar (desktop shape); touch-primary with a roomy SHORT SIDE (both classes above their 600px breakpoint) → the same centered top bar (tablet shape, either orientation — ADAPT-2); touch-primary with a short side under it → bottom tabs (a phone, whichever way it is held); gamepad-primary with a `Medium`/`Large` DisplaySize → the top bar, with a `Small` or unknown display → bottom tabs (the near-distance handheld — when we cannot differentiate, bottom tabs). `facts = { sizeClass, heightClass, distanceProfile?, primary?, displaySize? }` — shape, input and display facts only, never a device idiom (touch ALONE is not the top-bar indicator: a touch phone and a touch tablet share the class, and the SHORT SIDE is what separates them — the engine's DisplaySize cannot, because it calls every tablet `Small`). Every placement must remain gamepad-traversable — enter, through, away, and ButtonA activation — which the reference proofs pin per home. Pure, so the `conditions` memo and tests share one implementation |
| `adaptive.cardsPerView(available, opts?)` | how many whole cards belong in view across `available` px. One rung is not arithmetic: `opts.touchPrimary` on a `compact` width answers **1** — the swipeable one-up carousel — even where two would fit; everything else is `columnsFor(available, opts.minWidth or CARD_MIN_WIDTH, opts.gap)`, so a rail and a `UI.Grid` at the same width with the same floor never disagree. `opts = { touchPrimary?, gap?, minWidth?, distanceProfile? }`. `UI.VirtualList{ itemExtent = "cards" }` is the consumer, and `cards.perView` overrides it outright |
| `adaptive.cardPeek(available, perView)` | the sliver of the NEXT card a one-up rail shows — the affordance that there *is* more. `0` for any `perView > 1` (a multi-up rail is already showing the next card), otherwise a tenth of `available` clamped into `CARD_PEEK` |
| `adaptive.CARD_MIN_WIDTH` | `200` — the narrowest a card may be squeezed to before a rail drops a lane, as data |
| `adaptive.CARD_PEEK` | `{ fraction = 0.1, min = 24, max = 56 }` as data. Proportional so the peek scales with the rail, floored so a thumb reads it as a card edge rather than a border, capped before it looks like a second column that got cut off. These are **arrangement** facts and deliberately not theme metrics: a package decides how a card is painted, never how many of them a phone shows |
| `adaptive.LANE_MEASURE` | `600` — the reading width of a `UI.Composition`'s content lane at regular-touch distance, as data. It is the tablet measure the layout paradigm matrix verified RIGHT (cell B-6c, 1024x768), and it is the BASE the ten-foot cap is derived from rather than a second number beside it |
| `adaptive.laneMeasureFor(metricScale)` | the measure cap a display class asks for, or **nil** where distance asks for none. `metricScale` is `themes.snapshot.metricScale(displaySize)` — 1 near, 1.5 at ten-foot (the one `tenFootFloor`), so the ruled ten-foot measure is `600 x 1.5 = 900` with neither number written twice. `UI.Composition` defaults every `fill` group's `maxWidth` from it, and a group that declares its own — or a composition that declares `maxMeasure` — wins outright. Nil at near distance is the whole reason a 1600px desktop keeps the measure it had: this is a DISTANCE rule, and a cap that also fired on a wide desktop would be a width rule wearing a distance rule's name (B-6e, controller ruling R14) |
| `adaptive.BREAKPOINTS` | `{ regular = 600, wide = 1000 }` as data |
| `adaptive.DEFAULT_STACK_ABOVE` | `600` — the default `axisFor` threshold, as data. It is the compact/regular boundary on purpose, so a screen that adapts its stack and a screen that adapts its density flip at the same width |
| `adaptive.HEIGHT_BREAKPOINTS` | **the same table**. The question is identical on both axes ("how much content fits along this one"), and a second set of literals would be a second thing to justify and a second thing to drift. A rotation therefore maps a class pair onto its mirror: 733×313 is `regular`×`short`, 313×733 is `compact`×`medium` |
| `adaptive.sizeClassAtLeast(value, target)` | `boolean` — ranks `compact < regular < wide` and answers whether `value` is at least `target`'s rank. The general pure form `conditions.atLeast`/`isRegularOrWider` bind (framework-gaps-phase2 gap 7b): `isRegular` names the MIDDLE class only, so it reads "at least regular" and behaves "regular and nothing else" — false on `wide`, the widest screen there is. `sizeClassAtLeast(sizeClass, "regular")` is the question a caller actually means by "not compact" |
| `adaptive.effectiveDisplaySize(displaySize, touchCapable, mouseCapable)` | director item 5 — the physical-size-aware ten-foot gate. `displaySize == "Large"` downgrades to `"Medium"` when `touchCapable` **or** `mouseCapable` is also true (the third argument is additive; a caller that passes two is unchanged). A console plugged into a television has neither, so it keeps the treatment; a 4K desk monitor the engine buckets as `"Large"` has a mouse, and a big pixel count is not a long viewing distance. `client/roblox_env` spends this on the raw `GuiService.ViewportDisplaySize` before publishing the `displaySize` fact, so the correction reaches every derivation from it; a headless world, a device-matrix row and `client/edit_preview` set the fact directly and are untouched, and `viewingDistance = "ten-foot"` still outranks everything, else passes every value through unchanged. This is the pure half `env:get("effectiveDisplaySize")` (above, under "Derived policy") wraps with the live `capabilities.touch` fact — read that key for anything reactive; call this directly only outside the environment (tooling, a solver-side caller with no `env`) |

**Reactive conditions:** `adaptive.conditions(env, opts?)` returns Readables
the caller owns — `sizeClass`, `isCompact`, `isRegular`, `isWide`, `isTenFoot`,
`viewportWidth`, and `axis` (ready to bind to `UI.AdaptiveStack`), plus the
height half: `heightClass`, `isShort`, `isTall` (medium height is neither),
`viewportHeight`, `orientation` and `isLandscape` — and `navPlacement`, the
reactive form of `adaptive.navPlacement` (it additionally reads the
environment's `interactionClasses.primary`, so a tab bar moves home when the
primary input class changes, not when a device name does). They are memos
over the environment, so they cost nothing until read and re-resolve in place when a
fact changes. `sizeClass` delegates to the environment's own memo, so the
breakpoints have exactly one implementation.

**The four nav homes, promoted (gap 7a):** `navSidebar`, `navTopBar`,
`navBottomBar` and `navBottomBarCompact` are readable booleans over
`navPlacement`'s four values — the same equality-check idiom
`src/controls/tab_view.luau` already computed privately for itself
(`isPlacement(name)`), published so a call site never hand-rolls a
`use(navPlacement) == "sidebar"` memo again. Two reference apps did exactly
that before this round (`p1_glade`'s four-memo wordmark ladder, `p3_sipworks`'s
`app.navSidebar`); both now bind these fields directly.

**The `isRegular` trap, named around.** `isRegular` names the MIDDLE class only,
so it reads "at least regular" and behaves "regular and nothing else" — false on
`wide`, the widest screen there is. `isCompactOnly` is `isCompact` itself, under
the name that pairs with `isRegularOrWider` — not a second fact, not a second
memo. `isRegularOrWider` is `atLeast("regular")`, and `atLeast(target)` is the
general form both spellings name: it takes `"compact"`, `"regular"` or `"wide"`
and answers a readable boolean, backed by the pure `adaptive.sizeClassAtLeast`.
Write `isRegularOrWider` for "not compact".

The height half is **additive**: every key that existed before it keeps its exact
meaning and its exact value, including the ten-foot demotion. It exists so no
screen re-derives a private viewport-height threshold in its own code — which is
how the results surface ended up with a `vpH < 520` guess it got wrong twice. For
an adaptation that must depend on the box one *container* received rather than on
the viewport, these classes are still the wrong tool: use `UI.Composition` (whole
screen, both axes) or `ViewThatFits` (one container).

**Compose owns the conditions.** Call `adaptive.conditions(env, opts?)` inside a
component or `Compose.withOwner`. Derived formulas use the active owner; later
`atLeast(target)` calls use that same owner. Environment facts are borrowed and
keep the environment's lifetime. `opts.stackAbove` overrides the axis breakpoint.

```lua
local conditions = Facet.adaptive.conditions(env)
```

`isTenFoot` follows the **viewing distance** (`displaySize == "Large"`), not the
input class: a console is Large and gamepad, but Large alone earns the distance
treatment.

These conditions are **viewport-relative**, and `viewportWidth` is the RAW viewport
width: it does not subtract safe insets or overscan. On a console row it reads 1920
while overscan removes 106 px per side, so near a breakpoint a screen can resolve for
space it does not have. For a decision that must depend on the space one particular
container actually received, use the real measurement contract instead — see
`ViewThatFits` for the subtree form and the pair below for the value form.

**`adaptive.fitsIn(needs, container, clearance?) -> boolean`** and
**`adaptive.fits(core, spec)`**, which answers a readable boolean, are the
container-relative half. `fitsIn` is the pure one and it is *the ladder's own predicate*:
`ViewThatFits` tests `availW == math.huge or w <= availW`, and so does this — an
unbounded container fits everything, exactly as it does in the solver. A screen
that reserved room for an arrangement the solver then refused to use is worse than
one that never reserved, so there is one comparison rather than two.

```lua
local ridesTheTopbar = Facet.adaptive.fits(core, {
    needs = { lapPillWidth, dramaDialWidth },  -- the PARTS, never a pre-computed sum
    gap = rowGap,
    container = bandWidth,                     -- a number or a Compose readable
    clearance = 24,                            -- room that must remain BEYOND them
    scope = owner,                             -- optional: an owner that disposes the formula
})
```

`needs` takes a **list** on purpose. Naming the parts is what lets them be the same
theme reads the content is built from, so the sum moves when they move; a sum
computed once cannot ride the ten-foot metric ladder, and — the failure that
matters — a part that goes missing makes a sum *smaller* and the verdict *more
permissive*. A static part that is not a number, and a list with a hole in it, are
refused at construction; a live part that resolves to `nil` reaches
`core.lastError()` and the decision holds its last good answer rather than
inventing a new, wrong, confident one.

**`contentWidth` is deprecated (since 0.8.0; replacement `viewportWidth`).** It
is the same value under a second name, and the name is a lie: it states an inset
subtraction that never happens. It keeps working — it is in `Facet.DEPRECATIONS`
with at least one minor of notice — but new code reads `viewportWidth`.

### `composition`

`Facet.composition` — the **pure** half of declared-content adaptive composition. `UI.Composition` / `UI.Region` are the declaration face; this is the
decision itself, callable with **no mount, no engine and no theme**, which is what
makes a whole device matrix a headless sweep rather than a screenshot review.

| Call | Result |
|---|---|
| `composition.resolve(decl, offer, ctx)` | the full `Resolution`: `arrangement`, `legal`, `fallback`, per-region `{ form, mounted, dropped, floor, rect, lane }` (plus `regionById`), lane rects with each lane's `collapsed` flag (rule 9), group rects, `scroller`, `used`, and `rejected` — one entry per losing candidate with the **rule** it broke and the measured detail. `offer` is `{ w, h }`; `ctx.measure(regionId, formIndex, availW, availH) -> (w, h)` supplies the measurements and `ctx.floorOf(region) -> number?` the authored floors |
| `composition.normalize(decl)` | validate and default a declaration — the ONE ruling on what a declaration may say, run both at construction and on every solve. Idempotent |
| `composition.dump(resolution)` | the deterministic diagnostic table (`{ schema = "facet-composition-dump/1", … }`); two calls are equal. This is what the solver publishes and the layout dump carries |
| `composition.floorPx(floor, metrics)` | a CONTENT floor (`{ lines = n, role? }`, `{ targets = n }`) resolved to pixels against a theme snapshot; `nil` when nothing was declared |
| `composition.arrangementOf(value)` | a preset name or a custom table, validated to `{ name, lanes }` |
| `composition.ARRANGEMENTS` | the four presets as data: `column` = one lane holding every affinity, `twoLane` = `{ main } { lead, trail }`, `leadFirst` = `{ lead } { main, trail }` — the mirror of `twoLane`, for an app shell whose nav sits on the `lead` side (framework-gaps-phase2 item 12) — `threeLane` = `{ lead } { main } { trail }` |
| `composition.HUD` | the **screen-anchored HUD** arrangement as data: three lanes, `{ left } { center } { right }` — the three screen columns |
| `composition.HUD_GROUPS` | the thirteen groups that go with it: one `fill` **column** group per lane (it holds the lane's third of the band, and `holdsLane` keeps that third on a round where the column is empty), the nine **zone** groups `topLeft … bottomRight`, and the `topbar` **span** row |
| `composition.ZONES` | the ten zone ids in that table, in order. Nine are the same nine words the `anchor` box prop uses; the tenth, `topbar`, is not an anchor at all — it is the `span = "above"` row LEVEL WITH the platform's own controls, so the lanes start below it. It is inert until a region declares it: a HUD that never mentions `topbar` resolves and dumps byte-identically. Its geometry comes from the `platformChrome` env fact and the SOLVER applies it under `rootPolicy = "bandSafeContent"`: the row is laid into the free strip's own x and width rather than across the composition, and a `sizing = "fill"` region in it takes the strip so its content centres there. Under any other policy it is an ordinary full-width span row, as it always was — see **Placing a surface in the platform's TOPBAR band** |

A declaration is `{ id?, groups, regions, arrangements, laneGap?, groupGap?, maxMeasure? }`,
where each region carries `{ id, group, rank, forms = <count>, recover, sizing?, weight?, floor?, mayScroll?, mayDrop?, reserved? }`.
Note `forms` here is a **count** — the pure decision never sees a view, only how
many representations a region has and what each one measures.

A group carries `{ id, lane | span, sizing?, weight?, place?, align?, holdsLane?, minWidth?, gap? }`.
`place` puts the group **down** its lane (`start` / `center` / `end`, or a
fraction); `align` puts its regions **across** the lane, and stating it is what
asks for the content width instead of the whole lane (aligning a box that already
fills its lane would mean nothing). `holdsLane` is rule 9's counterpart: rule 9
releases a lane whose every region resolves to nothing paintable and gives its
width away, which is right for a page and wrong for a layout whose lane
**positions** are the coordinate system — a HUD's right-hand column has to stay on
the right edge on the round when the middle column has nothing to say.

**A HUD is a composition, not a second mechanism.** The three screen columns are
three lanes (lanes sit side by side and never overlap — that is the partition),
the three vertical bands are the `place` a lane already distributes its groups by,
and the nine zone names are the nine anchors. So the rank / step-down-before-drop
ladder is reused literally: when a phone loses 200px of height to a browser URL
bar, the HUD **degrades by rank** instead of collapsing into itself.

```lua
UI.Composition("Hud")({
  width = UI.fill(), height = UI.fill(),
  groups = Facet.composition.HUD_GROUPS,
  arrangements = { Facet.composition.HUD },
  -- a region's children are its forms, richest first
  UI.Region("Rail")({ group = "topRight", rank = 3, recover = "overflow", rich, compact }),
  UI.Region("Tasks")({ group = "left", rank = 7, mayDrop = true, recover = "self",
                       panel, tappableChip }),
})
```

**...and it says where the degraded content went.** `RegionResolution.elided` sits
beside `dropped` — a form below the richest was chosen — and the resolution
carries `unshown`, one entry per thing the screen has stopped showing, in
declaration order:

```lua
resolution.unshown --> { { id = "Clock", reason = "elided",  route = "overflow" },
                   --     { id = "Feed",  reason = "dropped", route = "overflow" } }
```

That list is the **seam** an overflow surface is populated from. Without it every
consumer re-derives elision by hand out of `dropped` and `form`, and gets it
subtly wrong three ways: a dropped region is not `form > 1`; a region whose every
form is lossless (`recover = "none"`) is not missing anything; and a one-form
region can only be missing by being dropped. A DROPPED region's route is always
`"overflow"` whatever its `recover` said — there is no standing form left to be
its own route, which is the half `mayDrop` has always implied and now states.

**...and, beside it, whether this screen is simplified at all** (framework-gaps-
phase2 item 28). `resolution.simplified` answers a different question than
`unshown`: not "what is missing" but "what is on screen showing less than its
richest form" — which includes a `recover = "none"` region (nothing missing, by
the author's own word, but still not showing its richest form) and excludes a
dropped one (`activeForm = 0` there; it is showing nothing, not showing less):

```lua
resolution.simplified --> { { id = "Rail", form = 2 } }
```

One entry per on-screen region with `activeForm > 1`, in declaration order,
`form` restating that region's `activeForm` so a reader never has to cross back
to `regionById` for it. `composition.dump(resolution)` carries the same list.

`resolution.collisions` is the alarm for the one failure a partition cannot
remove: a region whose chosen form **measures** bigger than the box it was
allotted paints outside it, and if a neighbour is there it is painting on that
neighbour. Every unordered pair, offender first, with the overlap in px — and the
solver files one finding per pair, so the always-on overflow sweep sees it at
every viewport. The scroll region and a `fill` region's height are excluded: those
extents are granted by the mechanism rather than claimed by the author.

### `layout`

`Facet.layout` — pure layout geometry not owned by any one control. **No core,
no engine, no theme, no node** — deterministic and headlessly testable, same
shape as `adaptive`/`composition` above.

| Call | Result |
|---|---|
| `layout.transformFootprint(w, h, scale, deg)` | the axis-aligned bounding box of a `w x h` rectangle scaled uniformly by `scale` and rotated `deg` degrees about its own centre, ROUNDED UP: `width, height` (two numbers). `scale`/`rotation` are paint-only (see the `scale` row above), so the solver reserves a node's UNSCALED box and the engine draws the transformed one — a scaled/rotated container's PARENT has to reserve the painted footprint itself, as a plain sibling box outside the node that scales. This is that formula, published (framework-gaps-phase2 gap 33, audit-marked "teaches-wrong 12") so a consumer computes the reservation instead of hand-transcribing the trigonometry the `scale` row documents in prose. Reproduces the exact device measurement recorded there: `transformFootprint(100, 70, 1.5, 30)` returns `183, 166` |
| `layout.anchorPlacement(request)` | the pure placement decision behind every Facet surface that points at something — the SAME edge/flip/shift/tail rules `presenter.presentAnchored`, the disclosure plate and `UI.RowActions`' floating menu already share (§"The placement rules" under `presentAnchored` above). `request = { source, size, safe, edge?, align?, gap?, crossOffset?, tail?, tailInset?, overflow? }` (window-space rects; `crossOffset` px along the alignment axis before the safe clamp, default 0; `edge` `"top"`\|`"bottom"`\|`"leading"`\|`"trailing"`\|`"overlap"`, default `"bottom"`; `align` `"start"`\|`"center"`\|`"end"`, default `"center"`; `overflow` `"clamp"`\|`"keep"`, default `"clamp"`) returns `{ x, y, w, h, edge, flipped, shift, fits, tailX?, tailY?, tailSuppressed }`. Published (framework-gaps-phase2 gap 39: `armStaging` "as a declaration rather than a coordinate") so a consumer DECLARES a placement — "above the source, centred, gapped by N" — instead of hand-computing the point. RascalRally's `HandDock` staging spot (`FacetSponsor/init.luau`'s `slotStagingPoint`, read by both the framework's `armStaging` seam and `PlayFlow:heldOrigin`) now calls this instead of the hand-rolled `source.x + source.w/2 - slot/2` / `source.y - slot - gap` arithmetic it used to reimplement |

#### HUD insets and world markers

`layout.hudInsets({ bounds, reservations }) -> { top, bottom, left, right }`
converts `{ edge, rect }` reservations into nonnegative edge depths inside
`bounds`. Rectangles use `{ x, y, w, h }` in one shared coordinate space. Outside
rectangles are ignored; each edge takes the greatest overlapping depth, not a
sum. Opposing edges never consume more than the available axis (top/left win).

`layout.worldMarkers({ bounds, markers, exclusions?, gap? = 8 }) -> rows`
places screen labels from projected targets. Each marker has a unique `id`,
finite `x/y`, positive pixel `width/height`, optional finite `priority` (default
0), and `visible` (default true). Invisible inputs may omit coordinates. Supply
sizes and gap resolved from your theme and preferred text facts. Exclusions are
plain rectangles in the same coordinate space as bounds and target points.

Rows are sorted by decreasing priority, ties preserving input order. Each has
`id`, `visible`, and, when placed, `rect`, `edge` (boolean) and `angle` (clockwise
from up, degrees). Offscreen targets clamp to an edge; labels try nine bounded
positions, avoiding exclusions and previously placed labels by `gap`. A label
that cannot fit reports `reason = "crowded" | "tooLarge" | "unavailable"` and
has no rect. This deliberately bounded layout can hide a low-priority label
rather than search every free pixel. Key rendering by ID, and show unavailable
objectives through an appropriate existing list if the game requires them.

Use `client.world_anchor` with `offscreen = "retain"` for projected directions;
copy `anchor.x/y/visible` into marker inputs. The solver creates no UI, focus,
input routes, scene objects, or motion. Render rows with themed public UI nodes;
use the usual Button/Menu controls if markers need actions. The Showcase's
Motion and layout → Layout → World markers page uses synthetic target positions
to exercise placement, crowding, resizing, and visibility deterministically.

### `contribution`

`Facet.contribution` — the input-contribution seam. A composite
control advertises its whole four-input story by attaching one bundle to its
blueprint root; the presenter discovers it on mount and composes navigation
groups, Activate dispatch, grab intercept, focus reporting, geometry feed,
keep-visible offset, action binding, the Adjust verb, and transient-surface
cancel/dismiss/trap — with **no** `present()` opts from the consumer.

```lua
local root = UI.VStack{ id = "MyControl", children = { … } }
root = Facet.contribution.attach(root, {
    focusGroups = function(rootNode) … end,
    handleActivate = function(path, meta) … return true end,
    adjustTargets = function(rootNode) … end,
    handleAdjust = function(path, direction) … end,
})
```

`contribution.attach(rootNode, bundle) -> node` decorates an owned Compose node
in place and returns the same node. The bundle lives on its internal `meta`
channel, never in the public prop bag. For an internal immutable blueprint it
returns a new frozen blueprint instead. `contribution.read(mountedNode) -> Bundle?` is the presenter's
side and type-guards a non-table value to `nil`. `contribution.PROP` is the
`meta` key the two share — exported so a tool that inspects a blueprint or a
dump can find the bundle without hard-coding the string; a control author uses
`attach`/`read` and never needs it. Every field is optional; fill only what your
control needs. See `docs/extending/new-control.md` step 3 and `Bundle` in
`src/input/contribution.luau` for the full field list.

`contribution.alive(bundle) -> boolean` answers whether the bundle's attaching
Compose owner is still live. A bundle's callbacks close over the state of
whatever built it, and that state dies with its owner, while the presenter's
contribution array is refreshed only when the structure epoch moves. So `read`
refuses a dead bundle, and the presenter asks `alive` on the one path that can
run against a stale array. A bundle attached with no owner — a bare mount in a
unit test — is always alive.

Invariant: when the bundle declares `handleActivate`, the inner focusable
primitives must carry **no** `onActivate` prop — the presenter dispatches to
the node's own handler first and then to the longest-prefix contribution, so
declaring both double-fires the verb.

---

## Text measurement

### `text`

`Facet.text` — the library's own measurement engine, reachable. Three pure
functions over one non-yielding measurer: per-font calibration, per-role line
height, real greedy wrapping, and the CJK/emoji full-em path. It exists because
the alternative is what consumers were writing instead — a character count times
a guessed average glyph width, which is the measurer's own *conservative
fallback* for a font it has never seen.

| Call | Answers |
|---|---|
| `text.measure(spec) -> Metrics` | how big is this string, at this size, in this box |
| `text.fit(spec) -> Fit` | what size makes it fit, and does it |
| `text.size(spec) -> number` | the same answer, when all you want is the size |
| `text.facts(spec) -> TextFacts` | the live text facts a prediction needs, read once |
| `text.lineBox(spec) -> number` | how tall `lines` lines of this text will be |
| `text.AVG_GLYPH_FRACTION` | `0.62` — the fallback fraction itself, as data (framework-gaps-phase2 gap 11). For a caller that already holds `Facet` and wants to pass the SAME number a hand-rolled estimate elsewhere used to guess at — source it here rather than copying it. See `measure` below for the same constant with no `Facet` table at all |

**`text.measure`** takes a spec table — the canonical form, and the one that
matches its two siblings:

```lua
local m = Facet.text.measure({
    text = "Rally Points",
    font = "GothamSSm",
    size = 18,          -- the size to measure AT
    width = 240,        -- the box the string must live in
    lineHeight = 1.2,   -- optional: the typography role's factor
    maxLines = 2,       -- optional: the caller's own lineLimit
})
```

The spec is construction-strict — an unknown key is an error naming the shape,
because the likeliest mistake is writing the positional parameter's name
(`fontSize`) and silently measuring at nil. `Metrics` is
`{ width, height, lines, naturalLines, truncated, state, exact, requestKey?,
error? }`: `naturalLines` is what the string wraps to uncapped, so
`truncated` (`naturalLines > lines`) tells you the engine will ellipsize without
a second measure; `state` is `"ready" | "pending" | "failed"`; `exact` is true
only when every word came from a real engine measurement.

`text.measure` also keeps its **six-positional form**
(`measure(text, font, size, width, lineHeight?, maxLines?)`), detected by a
string first argument. That is a grandfathered exception (constitution
**E-15**): it is the solver's own hot seam, called thousands of times per solve,
so the positional form stays for the solver while the spec form is the public
idiom. New code writes the spec.

**`text.fit(spec) -> Fit`** answers the derivation every caller was building on
top: the largest integer size in `[floor, cap]` at which the string draws inside
the box. `FitSpec` is
`{ text, font, cap, width, height?, lines?, lineHeight?, floor?, offset? }` —
`cap` is the largest size you will ever paint at (a type role's own cap),
`lines` defaults to 1, `height` is optional, and `floor` is the size below which
you would rather change the layout than keep shrinking. `offset` (Step 8.5) is
the paint-time additive preferred-text offset — pass the environment's
`preferredTextOffset` fact, read inside a memo so the answer re-derives on a
live preference change. The engine paints at `TextSize + offset`, so the search
fits the PAINTED form while returning the authored size: without it a size
chosen to fill a box at Medium ellipsizes at Largest (the production role-pick
CTA did exactly that). Absent = 0, byte-identical to the pre-8.5 behavior.
`Fit` is `{ size, fits, lines, height, exact, state }`:

- `fits = false` means even `floor` overflows — a layout decision (drop it, step
  it down), not something to solve by painting unreadably.
- with a non-zero `offset`, `lines`/`height` describe the PAINTED form (measured
  at `size + offset`) while `size` stays the authored value — and the effective
  painted floor is `floor + offset`, so read `.fits`, not just `.size`, when the
  box is tight.
- `state` is carried straight through from the measure the chosen size came
  from, so `exact = false` never conflates "this font is not calibrated yet"
  with "an engine measurement failed". Wait on `pending`; give up on `failed`.

The search is exact rather than iterative-until-close: fit is monotone in size,
so a binary search over `[floor, cap]` lands on the true answer in ~log2(cap)
measures, each of them memoized per `(text, font, size, width)`.

A size fits when the wrapped form stays inside `lines`, **the widest line stays
inside `width`**, and (when given) the box stays inside `height`. The width half
was added 2026-08-22: a WORD has no legal break, so the wrapper reports one line
at every size however far past the box the glyphs run, and the line count alone
therefore said "yes" for a string that does not fit at all. For a multi-word
phrase it changes nothing — a wrapped line is bounded by the width it wrapped
into — except for the one case where it should not be, a phrase whose longest
word is wider than the box, which the engine breaks mid-word and paints outside
the column. It is the same rule the solver's `ViewThatFits` candidate test had to
be given, one seam over.

**`text.size(spec) -> number`** is `fit(spec).size` — the convenience, for the
common case where the box is known to be big enough.

**The premeasure budget** is the one interaction worth planning around. Every
`measure` of a word the engine has not sized yet enqueues a measurement request
while the solver's collect window is open, and that queue is capped (1024
words per round) and shared with the solve itself. `text.fit` measures at
~log2(cap) different sizes, so calling it from inside a `presenter.onTick` hook
during a solve can spend the surface's premeasure budget on words at sizes
nothing will ever paint. Call it where you build a screen, not inside the frame
that is solving one.

Measurement state is process-wide: the calibration table and the measured-word
store belong to the module, not to a core or an owner, and there is nothing to
own or dispose.

### `text.facts` and `text.lineBox` — the line box

**Reach for `UI.VirtualList { itemExtent = "measured" }` first.** If the row can
measure itself, let it: that removes the prediction instead of making it easier,
and it is the right answer for any cell that is wrapping text at a live size.
These two are for the consumer that genuinely *must* predict — a perf-harness
baseline whose whole point is a uniform declared extent, a `Composition` region's
content floor, a list whose O(1) windowing depends on one declared number.

For those, "how tall is `lines` lines going to be?" has exactly one correct
answer and it is not obvious:

```
px = ceil(lines * (authoredSize * max(typographyScale, typographyPaintScale)
                   + preferredTextOffset) * theRole'sLineHeight)
```

Three live env facts, one theme number, one `max` that exists only because a
sub-1 accessibility preference makes the *paint* seam the larger of the two, and
a `ceil` that lands **once on the whole product** (ceiling per line
over-reserves by up to `lines - 1` px). A survey run in 2026-08 found seven
near-duplicates of that formula in this repository and exactly one of them
correct — a dated finding, re-run 2026-08-22 and now **zero** outside
`text_metrics` itself (see the `textSize = "fit"` section, which is the other half
of closing it). `text.lineBox` is that one implementation, and it spends the solver's
own two seams rather than a copy of them, so it moves when they move.

```lua
local extent = Compose.formula(function(use)
    local facts = Facet.text.facts({ env = env, use = use })
    return PADDING * 2
        + Facet.text.lineBox({ facts = facts, size = "title", lines = 1 })
        + GAP
        + Facet.text.lineBox({ facts = facts, size = 13, lines = 3 })
end)
```

**`text.facts(spec) -> TextFacts`** reads the facts once for a whole extent pass.
`TextFacts` is `{ scale, offset, metrics }`: `scale` is
`max(typographyScale, typographyPaintScale)`, `offset` is `preferredTextOffset`
clamped to the same legal domain the renderer's measure seam clamps it to, and
`metrics` is the live `ThemeSnapshot`. Pass **either**:

- `{ env, use }` — the live environment plus **the enclosing memo's own `use`**.
  `use` is required, not optional: a fact read with `:get()` is right once and
  registers no dependency, so the extent goes silently stale the moment the
  player raises their text size, swaps the theme, or the screen lands on a
  ten-foot display. If you really want a one-shot read, write it out
  (`use = function(r) return r:get() end`) and be seen to mean it.
- `{ metrics }` — a `ThemeSnapshot` on its own, for a caller with no env. The
  snapshot carries the three platform facts it was resolved from, so the same
  numbers come back out. This is the form `composition.floorPx` uses.

**`text.lineBox(spec) -> number`** takes
`{ facts, size, lines?, role? }`. `size` is the AUTHORED size — a number, or the
name of a typography role whose `size` is then used; either way it is scaled,
because an authored size reaches paint and both seams scale it. `lines` defaults
to 1. `role` names the typography role whose LINE HEIGHT applies; it defaults to
`size` when `size` names a role, else `body` — which is the solver's own answer,
since a literal px size on a `UI.Text` resolves to the class's intrinsic role.
A `size` or `role` naming a role the live theme does not carry is refused; so is
a `lines` below 1 and an unknown key.

The number it returns is the box a **wrapping** text node of that many lines
occupies. It does not include padding, gaps or any sibling — a row's extent is
its own arithmetic over one or more line boxes, and keeping those separate is
what lets a cell with a title above a body ceil each of them once rather than
ceiling their sum.

### `measure` — the headless entry point (framework-gaps-phase2 gap 11)

`Facet.text` above is reached through `src/init.luau`, which requires dozens of
sibling modules and transitively pulls `src/client/*` — `GetService` and all. A
model that has to run **headless** (Lune, a benchmark, a shared game module with
no DataModel) cannot take that dependency, even though the measurement engine
itself needs none of it. `src/measure.luau` is a SIBLING module beside
`src/init.luau`, not a member of the table `Facet` returns — reaching it never
runs `init.luau`'s module function, so none of those requires pay. Two shapes,
depending on the caller:

- **live engine, no Lune:** `require(ReplicatedStorage.Facet.measure)` — an
  instance path, exactly as `src/client/host.luau` is reached directly by client
  code as `ReplicatedStorage.Facet.client.host` with no `require(Facet)` first.
- **headless (Lune, a shared game module):** `require("<path-to-Facet>/src/measure")`
  — the plain relative-string form.

Either route lands on the SAME underlying module `Facet.text.measure`/`.fit`/
`.size` are built on — a plain republish of `src/layout/text_metrics.luau`
(zero requires, zero `GetService`), so there is exactly one implementation and
the live path and the headless path cannot disagree.

| Call | Answers |
|---|---|
| `measure.measure(spec)` / the six-positional form | identical to `text.measure` above |
| `measure.minWidth(text, font, fontSize) -> number` | the narrowest a string can be laid out at that size without splitting a word (or an ideographic run) |
| `measure.AVG_GLYPH_FRACTION` | `0.62` — the conservative per-glyph-width fallback fraction every measurement here falls back to for an uncalibrated font. The SAME value `text.AVG_GLYPH_FRACTION` above is, for the consumer that has no `Facet` table to read it off |

This is for the consumer with no core, no environment and no engine to mount one
on — not a second measurement API. Every mounted surface still reaches
measurement through `Facet.text`.

**A relative-string `require` into this module is only safe when the consumer's
mount depth matches its disk depth.** Such a require resolves by file-system
depth under Lune and by Rojo instance-tree depth live, and the two disagree
whenever a consumer's `$path` mapping does not mirror the source tree's nesting
— measured with two modules that are Rojo siblings, one hop apart live and five
apart on disk, where no string satisfies both. A consumer in that position takes
`text.AVG_GLYPH_FRACTION` by INJECTION from a caller that already holds the live
`Facet` table. This entry point remains the right tool for a consumer with no
such table to inject from, or one whose mount depth genuinely does match its
disk depth in both runtimes.

---

## Focus

### `newFocusGraph`

`Facet.newFocusGraph(core) -> FocusGraph` — the logical focus graph (engine
selection is a render output). Every presenter builds one and publishes it as
`app.presenter.focus`; call this directly only for a graph of your own. Scopes
stack; the top scope owns navigation;
modal scopes trap and restore the previous focus on pop.

- `graph.pushScope{ name, trap, order }` — FLAT scope: one ring,
  `graph.navigate(±1)` wraps.
- `graph.pushScope{ name, trap, groups }` — GROUPED scope: each
  NavigationGroup declares `name`, `axis` ("vertical"/"horizontal"),
  `order`, `wrap?`, `containment?`, `entry?` ("first" | "restore" |
  "nearest"), `exit?` (`{ up/down/left/right = targetGroupName }`), and
  `columns?` (below), and optional `rectOf(path)` returning resting `{x,y,w,h}` geometry.
- `graph.navigateDirection("up"|"down"|"left"|"right")` — axis-aware
  movement: within the active group along its axis; at edges wraps (if
  `wrap`), follows a declared `exit`, or (uncontained) falls through to the
  neighboring group in array order; orthogonal directions only move via
  declared exits — **unless the group declared `columns`** (below).
  `containment = true` blocks implicit exits.
- `graph.focusOn(path)`, `graph.setOrder(name, order)`,
  `graph.setGroupOrder(scopeName, groupName, order, columns?)`,
  `graph.remove(id)` — structural updates keep focus when it survives, else
  the nearest surviving neighbor (preferring the following item).

`graph.navigationTarget()` is the destination of the last real navigate,
navigateDirection or traverse movement, published before focus subscribers run.
Accepted explicit `focusOn` clears it, even if focus paint remains visible. TabView
uses this authority for bookmark restoration; shoulder entry consumes its pending
handoff after restoring the eligible target.

**Geometry for automatically derived navigation.** Inferred layout groups receive
`rectOf` from the renderer. For these groups, directions search visible eligible
mounted candidates within that group in the requested half-plane. Overlapping perpendicular spans
win over diagonals, then center distance along travel plus twice the perpendicular
center distance; document order breaks ties. Geometry is read on each press, so
resize and bound stack-axis changes do not need a new focus tree. Animation scale
is excluded. At a group edge, the existing declared/adjacent-group policy takes
over; a scan never skips a contributed control or crosses surface coordinate
systems. Explicit groups without `rectOf`, grid `columns`, authored `wrap`,
containment, and declared exits keep their topology;
Tab traversal retains document order. This is one linear scan of mounted
candidates per press, with no per-frame neighbor graph.

**A group can be a RECTANGLE: `columns`**. An integer ≥ 1 declaring
that this group's `order` is **LINES of `columns` LANES**, row-major, in document
order — which is exactly what a lazy grid's mounted band is. `axis` then names the
**lane** direction (a vertical grid's lanes run across, so it declares
`"horizontal"`; a sideways grid's run down, so `"vertical"`), and the direction
perpendicular to it moves **±`columns`** — one whole line, keeping the lane —
instead of falling straight out of the group. Anything that is not an integer ≥ 1
is ignored and the group stays one-dimensional.

- **Document order is unaffected.** `columns` adds no ordering opinion; it only
  says where the lines break in the one order the group already has. Tab still
  walks lanes then lines.
- **Perpendicular ENTRY** is the near LINE at the ordinal lane: entering downward
  lands in the first line, upward in the last, and the incoming ordinal is the
  lane, so a column survives the crossing. Entry along the lane axis is the near
  END, unchanged.
- **A ragged last line** clamps forward (the lane does not reach it, so the move
  lands on the last cell that exists) and needs no case backward, since only the
  last line may be short. Clamping is not wrapping: from the last line itself the
  move exits.
- **`wrap` still governs the declared axis only.** The bottom of a column is an
  exit, which is what lets a grid hand focus to whatever sits under it.
- **The order must stay a complete rectangle.** Make a cell unreachable with a
  focus-skip predicate, never with a hole. Anything that *splices* an order —
  `graph.remove`, and the framework's own hidden-subtree filter — drops `columns`
  and falls back to the 1-D reading rather than navigating a rectangle that is no
  longer there; `setGroupOrder` takes the lane count alongside the order it
  describes (omitting it clears the field), and `replaceGroups` re-declares it with
  the group.
- `graph.popScope()`, `graph.removeScope(name)` (used by
  `presenter.dismiss` so dismissing a covered screen removes ITS scope, not
  the top one), `graph.activeScopeName()`, `graph.focused` (Readable).

**Focus-skip by live predicate** (row SF-L3). Any order
entry — flat scope or group — may be written as `{ id = path, focusable = () ->
boolean }` instead of a bare path string. The predicate is evaluated **at
navigation time**, never cached, so a row that becomes ineligible while a card is
armed drops out of the ring on the very next press with nobody rebuilding the
order. Bare strings are always eligible, so every pre-existing caller is
unchanged.

- Skipping is **navigation-only**. An ineligible node is still mounted, still
  hit-testable and still activates on a tap — "skipped for navigation" must never
  mean "dead to inspection", or the player loses the one affordance that could
  explain why it is ineligible. `graph.focusOn(path)` does refuse an ineligible
  node (it is a focus move, not an activation).
- A group with **no** eligible entries is skipped whole: entry falls through to
  the next group in the direction of travel rather than parking focus somewhere
  unusable. `entry = "nearest"` lands on the nearest *eligible* index.
- `graph.beginInteraction(id)` / `graph.endInteraction()` — the
  **active-interaction exemption**, and it is binding: the node an in-progress
  interaction is aiming at keeps its focusability for as long as the interaction
  lives, whatever its own predicate says. Yanking the row out from under a gesture
  aimed at it is the defect the exemption exists to prevent; the flip takes
  effect when the interaction ends, and an illegal commit on such a node
  **rejects** rather than the node vanishing mid-gesture. Calling it again moves
  the exemption (a drag's hovered target changes as the player navigates); the
  graph holds exactly one, because exactly one gesture is live.
- `graph.interactionTarget()`, `graph.isFocusable(id)` — the reads.

---

## Composite controls

Every composite control is a member of `app.controls` (`UI.Table`, `UI.Menu`,
`UI.VirtualList`, and the rest), reached through `local app = Facet.new(opts)`
and `local UI = app.controls`.

A composite call — `UI.Table { ... }`, or `UI.Table("Id") { ... }` for a stable
path — **returns the control's node**. Its record arrives through the spec key
`ref`:

```luau
local api
UI.VirtualList("Inbox")({
    rows = messages, key = "id", itemExtent = 64,
    cell = function(item) return UI.Text { text = item.label } end,
    ref = function(record) api = record.api end,
})
```

`ref` must be a function. It is called once, while the control is built, with a
frozen `{ api, dump }`: `api` is the control's imperative surface and `dump()`
its deterministic diagnostic tree. A control that publishes its verbs on its own
record — `UI.VirtualList` and `UI.VirtualGrid` — is its own `api`.

### `UI.Table`

The table's state and lifetime belong to Compose. `selectedKeys` optionally
borrows a writable Compose cell containing `{ [rowKey]: boolean }`; without it,
the table owns its selection. Removed rows are removed from that set.
`columns[].value` receives the current item and formats the default text cell.
`columns[].cell` and `cellFor` receive a Compose readable for the current item,
so bindings update without rebuilding the cell. Column resizing preserves row
identity, focus and cell-local state.

```luau
local rows = Compose.cell({ { id = "first", name = "First record" } })
local selected = Compose.cell({})
local tableApi
return UI.Table("Records")({
    rows = rows,
    key = function(item) return item.id end,
    selection = "single",
    selectedKeys = selected,
    columns = {
        { id = "name", title = "Name", width = UI.fill(),
          value = function(item) return item.name end },
    },
    ref = function(record) tableApi = record.api end,
})
```

`UI.Table { ... }` returns the table's node: a multi-column list where columns
own their cells, `sortOrder` is owner state, `selection` is `"none"`, `"single"`
or `"multi"` (a click both moves focus and selects), column resize rides
focusable grips, and a pointer drag reorders rows with a ghost and a drop
indicator. The spec's keys are `rows`, `key`, `columns`, `cellFor`,
`cellPadding`, `dragLabel`, `editing`, `env`, `gap`, `header`, `height`, `id`,
`onPrimaryAction`, `onReorder`, `reorderable`, `rowActions`, `rowDeletable`,
`rowGap`, `rowHeight`, `rowMovable`, `rowSelectable`, `scrolls`, `selection`,
`selectedKeys`, `sortOrder` and `virtualized`; an unknown key is refused at
construction. See `src/controls/table.luau` for the full spec shape.

`key` identifies a row, and takes either spelling every keyed collection takes:
a `(item) -> string`, or the NAME of the field that holds the identity
(`key = "id"`, read as `tostring(item[field])`).

`ref = function(record) ... end` is called once while the table is built, with a
frozen `{ api, dump }`. `api` publishes `selectedKeys`, `select(rowKey, opts?)`,
`clearSelection()`, `editing`, `grabbedKey`, `selectedColumn`,
`columnWidthOverrides`, `hiddenColumns`, `setColumnWidth(columnId, px)`,
`moveRow(rowKey, delta)`, `revealRow(rowKey)`, `rowKeyForPath(path)`,
`bindNativeScroll(controller, scrollPath?)` and `scrollPath()`.

`dump()` is the deterministic diagnostic summary, and it carries the live
interaction state a bug report actually needs, not only the construction:
`{ schema, id, columns, rowCount, selection, sortOrder, selectedKeys (sorted),
grabbedKey, editing, scrollTop, dragging, reorderable, rootPath }`, plus
`hiddenColumns` and `columnPlate` on a table that can collapse a column (see
**Column priority-collapse** below).

A column's `alignment` applies to its **header title** as well as its cells, so a
numeric column's heading sits over its numbers rather than left of them.

**`minWidth` is a floor on every dim kind, `fill` included.** The table pins any
`fill` column whose share would fall under its floor and re-divides the rest
among the others, which is the ordinary flex-with-minimum negotiation. A
`content`/`hug` column's appetite is a measurement and is deliberately not part
of it: those columns consume nothing in this arithmetic and the fills go on
dividing what is left.

**Row height adapts by itself, on two axes.** Leave `rowHeight` out (the
recommended shape) and the table derives it from the theme's own per-paradigm row
description plus the live text facts. It asks the surface for the facts rather
than waiting to be handed them — `spec.env` when an author declares one,
otherwise the environment published against the surface the control was built on.
A table with neither degrades to the neutral package at authored size. It does
not refuse, because unlike a picker's presentation there is an honest default.

The ladder has **three** rungs: `pointer` (one line, floored at the theme's
compact control height), `touch` (two lines, floored at `targetSizes.minimum`)
and `tenFoot` (one line, floored at the theme's LARGE control height). The rung
is chosen by touch first and then by DISTANCE — `distanceProfile`, derived
straight off the display class, not by the presence of a gamepad. A controller
sixty centimetres from a monitor is a near session; what makes a row unreadable
is three metres.

**A focused row discloses its own truncated cell.** The framework's plate rule is
"the first truncated, disclosed Text at or under the FOCUSED path", and a table's
focus stop is the row's `Hit` — a full-bleed Button with no children — while the
disclosed value is its sibling at `Row/Cells/Cell-<id>/Value`. So the control
answers a `discloseScope` contribution: a row hit (or its edit-mode grab handle)
maps to that ROW, a heading's `Column` maps to that HEADING, and every other path
answers nil and keeps the framework's default. It is a SCOPE and not a target —
the presenter still runs its own walk inside it, so the hidden-candidate gate,
the truncation test, the `disclose` declaration and the document order all still
decide, and a control cannot nominate a label that is not truncated.

**Edit mode says so** — where the table can reach edit mode at all. The whole
edit-mode presentation, the gutter AND its contents, is gated on that being true:
the consumer holds `editing`, or the control auto-shows its Edit/Done toggle. A
table that declares neither can still be driven through the public `api.editing`,
and gets a mode that is visually inert — no gutter, no mark — rather than a 32px
inset with nothing in it. While `editing` is true on a table that CAN reach it, a
SELECTABLE table paints a leading selection mark in the gutter its cells are
inset into — a filled or hollow circle reading off the same formula the row's
`selected` prop reads, so the mark and the row's own treatment cannot disagree.
It is decoration, not a focus stop: the row's own `Hit` is the tap surface and its
Activate is the verb. A **reorderable** table's gutter belongs to the ≡ handle
instead — reorder is the capability edit mode exists for on touch and the handle
is its only touch route — so a table that is both selectable and reorderable
still shows only the row's painted selection. Two marks do not fit one 32px
gutter, and moving the ≡ to the trailing edge is a layout change carried to the
director rather than taken here.

**The auto Edit/Done toggle.** It appears when edit mode is the ONLY route to a
capability the table declares and the consumer has not taken `editing` over, and
it is gated on the live interaction classes: touch, gamepad, **or a keyboard with
no mouse on a reorderable table**. A keyboard-only session cannot drag a row with
a pointer it does not have, and grab mode refuses outside edit mode. The keyboard
clause is narrow on purpose — reorder only, because a keyboard reaches selection
by plain Return and multi-selection by Shift; and mouse-less only, because a
keyboard beside a mouse is a desktop session that drags rows directly.

**Selection, and what moves it.** A plain arrow or d-pad press moves the ring
and REPLACES the selection — the Finder's model. Held modifiers
change that on a keyboard: **Ctrl/Cmd** moves the ring and selects nothing (a
focus cursor), **Shift** extends the range from the anchor. A gamepad has no
modifiers, so its route is the finger's route — **edit mode is the selection
mode**: while `editing` is true on a `multi` table, a device Activate TOGGLES the
focused row and moving the ring leaves the selection alone, which is what lets a
pad hold two rows at once. The auto Edit/Done toggle already shows for a live
gamepad class, so the mode is one press away.

*The one narrowing, stated:* a `multi` table that ALSO declares
`onPrimaryAction` keeps the opening behaviour on devices — Return and ButtonA
open the row in edit mode rather than toggling it — because a device Activate
must not be eaten by edit mode. On such a table a pad cannot build a
multi-selection; a keyboard can, with Shift.

**Column priority-collapse — `priority`.** When the visible columns cannot all
meet their own floors, the table drops the lowest-priority column WHOLE instead
of squeezing every column past its minimum, one at a time until the remainder
fits.

| field | type | meaning |
|---|---|---|
| `priority` | `number?` | `1` is the most important. Absent, a column's priority **is its declaration order**, so a table that never sets this collapses right-to-left — the ordering the author already wrote down. |
| `priority` | `"always"` | a refusal, not a very high number: this column never collapses at any width. |

Two more rules, neither of them a priority: **the first declared column never
collapses** (it is the row's identity, and it is what the disclosure names each
hidden value against), and **collapse triggers on a FLOOR, wherever the floor
comes from**. A column declaring `minWidth`, a `fixed` width or a `percent` has
one; so does any column the player has RESIZED, because a committed override
resolves to a `fixed` dim and a fixed dim is a floor (with an undeclared 24px
minimum under it). A table that declares nothing and has never been resized has a
demand of zero, and zero always fits — but "declares nothing" is not the whole
sentence, and a resizable table is one committed width away from having a floor
it never wrote.

**The disclosure and the collapse read ONE state**, which is what makes the
sentence above safe to depend on: `hidden` is the whole predicate, and the `N
more` band, the plate and `dump().hiddenColumns` are all conditioned on it.
There is no second, build-time answer to "can this table collapse" that could
disagree with the rule at solve time.

A collapsed column keeps its node at zero width and takes the framework's own
space-reserving hide (`hidden`): it leaves paint, focus order and hit-testing
together with its whole subtree, including a resize grip's 44px hit expander. It
is deliberately **not** a `UI.When` — nothing remounts, so a collapse and its
reversal on the next rotation cost no selection, no focus ring and no live
in-cell control, and the row/header path grammar is unchanged.

**The disclosure.** The moment anything is collapsed the table grows one band
carrying an `N more` chip: its own focus stop, a 44px band, and a plate listing
each collapsed column with the value every mounted row has for it — identified by
the first column, which is why the first column never goes. A collapsed column's
**sort** is still selectable from that plate. The plate is
`src/region_expand.luau`'s, whole — the same anchored panel, sheet fallback and
four dismissal routes `UI.Region`'s own disclosure uses (outside tap, gamepad B,
the panel's own Close for the keyboard, and the epoch check when the anchor moves
or goes). `api.hiddenColumns` is a Compose readable of the collapsed ids in
declaration order, for a screen that wants to say so in its own chrome.

**`rowSelectable(item)` / `rowMovable(item)` / `rowDeletable(item)` — per-row
capability opt-outs.** The same three predicates `UI.VirtualList` takes, from the
same module (`src/row_capability.luau`), with the same rules: positive polarity
(true = this row may take part), a construction error if you declare one without
the container capability it narrows (`rowSelectable` needs `selection`,
`rowMovable` needs `reorderable` **and** `onReorder`, `rowDeletable` needs a
destructive row action), absent means every row participates, and a predicate
that throws **fails closed** — the row refuses, and the refusal is visible rather
than a silently deleted row. Use them for "this list reorders, but the pinned row
at the top stays put" and "these rows can be deleted, that one cannot". The
family is spelled POSITIVELY here: `true` means the row may take part.

**`onPrimaryAction(item, key)` — "open this row", the verb that is not
selection.** Optional; absent, every gesture below behaves exactly as it does
without it. Reachable on all four inputs with no invented gesture:

| Input | Gesture |
|---|---|
| Pointer | double-click (500 ms window, the common desktop default) |
| Keyboard | `Return` on the focused row |
| Gamepad | **A** / Cross on the focused row |
| Touch | a plain **single tap** on any row; **edit mode** is where touch selection lives instead |

**The rule, in one paragraph.** On a desktop pointer a single click on a row
selects it and a double click performs the primary action. On compact touch a
plain tap performs the primary action, and selecting without acting means
entering edit mode or holding a modifier on an attached keyboard. `Return` on the
focused row is Facet's own keyboard convention; it follows desktop list practice
and is not derived from any other framework.

**Edit mode is the touch selection mode**, and it is the half that makes the
first half affordable. Without an attached keyboard and pointer, multi-selection
in a list needs an explicit mode, so while `api.editing` is `true` a tap
**toggles selection and never opens** — which hands back `multi`'s
tap-to-**deselect** gesture in exactly the mode a player enters to manage
selection.

**Reaching edit mode is not left to the consumer.** The built-in Edit/Done toggle
auto-shows whenever edit mode is the **only route to a capability the table
declares** — today that means a `reorderable` table, **or a selectable table that
declares `onPrimaryAction`**, whose touch selection lives nowhere else. It is
gated to a non-mouse session when `env` is supplied (a mouse click already
selects), and suppressed entirely when the consumer passes `spec.editing`, which
makes the affordance theirs. `spec.editing` / `api.editing` is the seam for a
consumer who wants to own the toggle.

Auto-showing the toggle is **Facet's own rule**. The common convention is that
declared capabilities decide the *content* of edit mode — a list that declares
delete or move offers those controls once the mode is on — while the button that
enters the mode is placed by hand. Facet's four-input reachability rule needs the
button to appear on its own, because a capability no input class can reach is not
a shipped capability.

**The cost is real, deliberate, and yours to weigh.** With a primary action
declared, touch loses tap-to-select in **normal mode entirely**, including the
single selection a tap would otherwise make. Declaring the action is precisely
what makes a list retreat into edit mode for selection. **The corollary:** if a
table's dominant touch use is *selecting* rather than *opening*, the right call
is to not declare `onPrimaryAction` on that table at all.

A double-*tap* was never a candidate: the touch double tap is widely reserved for
zoom, and it collides with list navigation on small screens.

Two more consequences worth stating. A **modified** click (Shift / Cmd / Ctrl) is
a selection gesture and never opens, on any input. And a touch tap that opens
does **not** touch the selection at all — it neither adds, replaces nor clears,
so a selection made in edit mode survives every row you open afterwards;
`api.clearSelection()` remains exact.

**Input is auto-composed** by the presenter, with nothing to pass at mount: row
select, sort, focus-nav and grab-mode reorder wire themselves from the mounted
control. Every
interactive surface has a focus + Activate story on all four inputs — sortable
column headers form a leading horizontal navigation group (focus + Return /
ButtonA cycles that column's `sortOrder`), and a keyboard/gamepad focus move
that leaves the body's clip band scrolls the focused row into view (minimal
scroll, both directions; wheel/touch-pan unchanged). 

**Column resize, on every input (per-column `resizable = true`).** The column's
handle is its **header**, and it is that column's single focus stop:

| Input | Resize | Sort |
|---|---|---|
| Mouse / touch | drag the divider at the column's trailing edge | tap the header |
| Keyboard | Activate the header, then **Left/Right** (or Comma/Period on the focused header) | Activate, then **Up/Down** |
| Gamepad | **A** selects the column, then **Left/Right** (or L1/R1 on the focused header) | **A**, then **Up/Down** |

A device Activate **selects the column** (`api.selectedColumn`, a Compose
readable of the column id or `nil`) rather than sorting it, because a stick has
nowhere else to put "resize this" — and a selected column is the handle the rest
of the column-wide verbs hang off. A **pointer tap sorts directly**: that
convention is older than this table. While a column is selected it owns the
stick — Left/Right resizes, Up/Down cycles its sort, Activate or Cancel releases
it, and moving focus off the header releases it too, so a selection can never be
left behind swallowing input.

The presenter binds the Adjust keys only while a **resizable** column's header
holds focus, so a non-modal screen never shadows gameplay bumper bindings on a
fixed-width column (UI-PARADIGM-001; affordance-matrix Amendments). An
`onAdjust` in `app.mount`'s options overrides that per surface.

**Reading the widths back.** `api.columnWidthOverrides` is a **Compose readable**
of `{ [columnId]: px }` — the map the resize model commits into, empty until
something resizes. Read it with `use(...)` or `:get()` to show, persist or mirror
a player's column widths; it moves for a pointer drag, a keyboard step and a
gamepad bumper alike. It is a readable rather than a getter because **a pointer
drag commits inside the control and calls nothing back**, so polling would be the
only alternative.

**Two things this reaches on a real device and one it does not:**

- the divider drag and the `,` / `.` Adjust keys both work;
- **Left/Right do not, in a place that has not enabled
  `Workspace.PlayerScriptsUseInputActionSystem`** — Roblox's own
  `RbxCameraKeypress` binds them at ContextActionService priority 2000 and sinks
  them before any Facet handler is offered the key. The rows above describe
  Facet's routing, which is correct; the key does not arrive. Enabling the
  property puts the camera on IAS and the arrows resolve by ordinary priority —
  it is a stated requirement, see [Input](#input); no priority number is an
  alternative. See
  `the-camera-still-owns-the-arrow-keys`;
- the divider's 44px hit floor lands **on top of** its own header button and
  creates a 26px dead band down the trailing edge of every resizable header cell —
  `a-forty-four-pixel-floor-under-an-eight-pixel-divider`.
  On touch there is no working resize route at all.

**`rowHeight` is OPTIONAL, and leaving it out is the recommended shape.** Given
`env`, the table derives the row from the theme's own per-paradigm row
description (`controls.table.rowLines` / `.rowHeight` / `.rowPadding`, derived in
the snapshot from the package's cell text size, body line height, target-size
floor and space ladder) plus the live typography scale and accessibility text
offset. In practice: a pointer session gets the dense one-line row every desktop
table has, a touch session gets a two-line row that clears the 44px target floor,
and raising the player's text preference makes rows *taller* rather than making
their contents spill.

Whatever the height ends up being — derived, a pinned number, or a per-item
function — the table caps its own default `value` cells to the lines that fit it
(`Text.lineLimit`), so **cell text can never paint outside its row**. A
`cell`/`cellFor` blueprint is the consumer's and is left alone.

One limit is worth stating: a pinned `rowHeight` is honoured but never below one
line of its own cell text. A row cannot be shorter than the single line it must
draw, so a pin below that would not make a shorter row — it would reproduce the
overflow. It only binds at raised text preferences.

**A pinned `rowHeight` is preference-blind by contract (Step 8.5 authoring
rule).** The default (unpinned) row box composes the player's preferred-text
offset automatically; a pinned px value is honoured verbatim, so pin only a
height that clears `(textSize + the Largest offset, 14px) * lineHeight` for
every cell it holds — otherwise cell text that fits at Medium is cut at
Largest. An undisclosed clip from a too-short pin is exactly what the
`clippedEssential` authoring check fires on. A column may declare
`disclose = true`, which stamps the full-value disclosure contract on the
table-authored value cells and the header title it caps (a custom `cell`
blueprint declares `disclose` on its own Text instead).

**`rowActions`** wraps individual rows in a swipeable
[`UI.RowActions`](#uirowactions)
tray without a second construct: `rowActions: (item) -> { leading?, trailing?,
fullSwipe? }?`, a per-item callback returning the same three fields
`UI.RowActions` itself takes minus `content`/`coordinator`/`env`/`editing` —
Table supplies all four automatically (the wrapped row content, ONE shared
`newRowActionsCoordinator` instance for the whole table so at most one tray is
open at a time, its own `env`, and its own `editing` cell, so the edit-mode
leading minus and the reorder handle can both show at once). Returning `nil`
for an item (the common case, and the only legal value besides the closed
three-key table above) leaves that row completely unwrapped — no extra
`Instance`, no extra subscription, the same true-inert-passthrough guarantee
`UI.RowActions` itself ships. An unknown key in a returned table is a
build-time error naming the offending row, not a silently ignored option.

*Gesture arbitration with `reorderable`.* A row that is both `reorderable` and
carries `rowActions` composes the two through
`row_actions.composeWithReorder` rather than picking one: a **mouse** press
accumulates until the axis lock resolves, then replays onto whichever handler
won — a **vertical** drag drives the existing reorder session, a
**horizontal** drag drives the tray (open/close/full-swipe), so the same
press can reorder a row moved mostly up/down and reveal actions on the same
row dragged mostly left/right. **Touch** always drives the tray directly (this
control's own axis lock decides scroll-vs-reveal without a reorder branch —
Table's touch reorder already rides the grab verbs, independent of this
pointer path, the same split `UI.VirtualList` documents above). Keyboard and
gamepad Delete/menu bind per row through the wrapper itself, with no separate
Table wiring — and that is true only because the ROW is a focus stop at all.
`rowActions` joins `selection` and `reorderable` in the union that decides
whether a row is a focus stop. A table with none of the three has no focus stop
per row, deliberately: a read-only grid of text has no verb for a ring to reach.

*The tap-to-close rule.* A tap that lands on a row's own content while
THAT row's own tray is open closes the tray and does **not** select or
activate the row (a second, deliberate tap is what proceeds) — a tap
elsewhere (another row, off the list) is unaffected.
`tests/table.spec.luau`'s "tap-to-close" case pins it.

*A swipe survives its own release.* A row's hit surface is a real engine
`GuiButton`, so the pointer sequence that swipes it **also** fires that button's
`Activated`, on either side of `InputEnded`. Both hosts (`UI.Table`'s wrapped
rows and `UI.VirtualList`'s hosted rows) therefore swallow exactly one Activate
on the origin row, armed the moment the gesture crosses the axis lock sideways —
so a swipe never selects the row, never fires `onPrimaryAction`/`onActivate`, and
never closes the tray it just opened, on either edge, either pointer kind, and
either ordering. The suppression is **one pointer Activate wide**: the next tap
on the row is genuine, and a **device** Activate (gamepad A / keyboard Return) is
never consumed by it — it carries no pointer and so can never be a pointer
gesture's artifact. A gesture that ends in a cancel disarms it outright. Pinned
by `tests/row_actions_scenario.spec.luau`'s four release-Activate cases and
`tests/virtual_list_row_actions.spec.luau`'s twelve-combination hosted matrix.

### `UI.VirtualList`

`UI.VirtualList { ... }` / `UI.VirtualList("Id") { ... }` returns the list's
node. Keyed-row virtualization: only visible rows plus a bounded overscan mount,
same-window scrolls are rect-writes-only, and a window slide adds or removes only
the entering and leaving keys.

The spec is a closed key set: `id`, `rows` (a Compose readable of the array, or
a `function(use)` answering one), `key` (a field name, or `(item) -> string`), `axis` (`"y"` default | `"x"`),
`itemExtent` (px, a Compose readable of px, `(item, index, use) -> px`,
`"measured"`, or `"cards"`), `estimatedItemExtent` (px or a readable — required
with `"measured"`, refused otherwise), `cards` (`{ perView?, minWidth?, peek? }`
— the card paradigm's options, refused without `itemExtent = "cards"`), `snap`
(`"none"` default | `"item"`, or a readable of one), `rowGap` (px, a theme metric
name, or a readable of either), `viewportExtent` (px, a readable, or `"auto"`),
`crossExtent` (`"hug"` | `"measured"`), `overscan`, `cell (item, ctx) ->
Blueprint`, `width`, `focusPolicy` (`"key"` | `"index"`), `onActivate
((item, meta) -> ())`, `follow`, `followThreshold`, `scrollNavigation`, `env`,
`motionClock`, `navigation`, plus the collection fields tabled below
(`selection`, `selectionPaint`, `onSelect`, `reorderable`, `onReorder`,
`reorderMotion`, `dropSurface`, `rowDropTarget`, `rowActions`, `rowFocusable`,
`rowSelectable`, `rowMovable`, `rowDeletable`, `autoscroll`, `grabOnActivate`)
and the two deprecated aliases `rowHeight` / `viewportHeight`. An unknown key is
refused at construction.

`cell` receives `(item, ctx)`, where `ctx.scope` is the row's own Compose owner
and `ctx.current` is a getter that follows the item's live edits
(`Compose.formula(ctx.current)`). Item state lives in that scope and dies when a
row leaves the window — durable state belongs in your data model, so async work
owned through `ctx.scope` is cancelled on window exit.

`ref = function(record) ... end` is called once while the list is built with a
frozen `{ api, dump }`. This control publishes its verbs on its own record, so
`record.api` is that record: `blueprint`, `focusGroupName`, `scrollTop`,
`focusedKey`, `selectedKey`, `armedKey`, `dropIndex`, `autoscroll`,
`engagedKey`, `engagedOffset`, `pathOf(key)`, `focusKey(key)` (scrolls into view
and materializes, then answers the hit path), `positionOf(key)` (the key's
current 1-based index in `rows`, `nil` for a key that is not there),
`select(key)`, `clearSelection()`, `toggleGrab()`, `stepAutoscroll(now)`,
`bindNativeScroll(controller, scrollPath?)`, `scrollTo`, `scrollPath()`,
`debugWindow()`, `dump()` and `dispose()`. `viewportExtent` and `crossExtent`
appear on it as Compose readables **only when the list was asked to measure
them** (see "Self-measuring extents" below); a list that declared its own numbers
publishes neither, because it already has them.

```luau
local list
UI.VirtualList("Feed")({
    rows = posts, key = "id", itemExtent = 64, viewportExtent = "auto",
    cell = function(item) return UI.Text { text = item.title } end,
    ref = function(record) list = record.api end,
})
```

**`UI.VirtualList` refuses when it needs the environment and none is found or
given**: `viewportExtent = "auto"` and a theme-metric-name `rowGap` both read the
live environment snapshot, and a headless or otherwise ambiguous host makes the
control name the fix instead of guessing.

**`follow` holds the tail in view while the player is reading it.** It is `"end"`
or `"none"` (the default), **and it may be a Compose readable or a
`function(use)` rather than a constant** — a live flip needs no rebuild, because
the same two observers decide on every change. "Reading the tail" is decided only
when the engine reports an offset within `followThreshold` px of the end;
`followThreshold` is a finite non-negative number, default `4`, and it means
something only alongside `follow = "end"`. Growth — a new row, a measured row
settling, a taller viewport — then re-pins the end through the one programmatic
scroll write, as a rest rather than a gesture, so a player who scrolled away
stays exactly where they are.

**Following yields the instant the player takes the scroll, and while it is
yielded, growth moves the view by nothing at all.** A reported offset that moves
*away* from the end — a touch pan, the wheel, a keyboard or gamepad scroll, or
your own `scrollTo` — yields, even when that offset is still inside
`followThreshold`. That last clause is the whole of it: one frame of a pan moves
only a few px, so a threshold test alone re-pins the player faster than they can
travel, and a thread that is growing (a streaming reply) reads as completely
stuck. Following resumes when a reported offset arrives back within
`followThreshold` of the end, **or when you re-assert `follow`** — writing
`"end"` to a `follow` readable that already reads `"end"` does not count, so a
chat that wants send to jump to the bottom flips it through `"none"` or asserts
it from a cell it owns. Your own follow-writes are not mistaken for the player's:
the one programmatic write is matched against its own echo.

```luau
local followReplies = Compose.cell(true)
UI.VirtualList("History")({
    rows = conversation.messages, key = "id",
    itemExtent = "measured", estimatedItemExtent = 100, viewportExtent = "auto",
    follow = function(use) return if use(followReplies) then "end" else "none" end,
    followThreshold = 48,
    cell = function(item) return UI.Text { text = item.body } end,
})
```

**`scrollNavigation = { position, active? }`** shares one scroll offset across
presentations: `position` is a writable Compose cell of the pixel offset the list
restores from and writes back to, and `active` is a boolean source that suspends
both halves while it reads false.

**`axis` is the direction the list runs**, `"y"` (a vertical list of rows, the
default) or `"x"` (a sideways strip of items), and it is **construction-only** for
its axis-specific windowing and input configuration (constitution §16, E-6).
Unlike an ordinary reactive `ScrollView`, changing this axis requires rebuilding
the virtual collection. Every other field is
written in the vertical vocabulary and reads on both axes — `itemExtent` is one
item's size *along the list's own axis*, `viewportExtent` is the host's size along
it, and the list's one navigation group takes that axis too. Two fields are
axis-restricted, and each says so at construction: **`width` is an `axis = "y"`
field** (there it is the CROSS axis; on `axis = "x"` the width *is*
`viewportExtent`), and **`rowActions` is vertical-only**, because a tray's reveal
and a horizontal list's own scroll would be the same sideways swipe.

**`snap` says where the list may come to REST.** `"none"` (the default) lands wherever the engine's momentum left it;
`"item"` settles the offset onto an item boundary after the gesture stops. Roblox
has no native snapping and reports no gesture release, so the framework watches the
`CanvasPosition` mirror it already keeps: an offset that has held still for one
quiet window is a release, and the peak speed across the travel is what separates a
flick — which always advances at least one item in the direction it went — from a
nudge, which rounds back to the nearest boundary. The boundaries are the ones the
window itself divides by, so a variable-extent list snaps to its *measured* rows.
Three rules bound it: the end of the list is a resting place of its own (the last
page shows the tail flush and never oscillates), an item taller than the viewport
disables snapping for that settle (content access beats alignment), and
keep-visible, `scrollTo` and focus traversal all land on a boundary rather than
near one. Under reduced motion the offset is *placed* rather than travelled, with
zero flight. A snapping list that nobody is touching does no per-frame work at all.

**`itemExtent = "cards"` is the compact card paradigm**, and it is the one form
that answers "how big is one item" with an *arrangement* instead of a number. The
rail asks the space it actually got and the live interaction class: a compact,
touch-driven surface resolves **one card per view with a peek of the next** — the
affordance that there is more — and turns `snap` on, because a one-card view is a
page; anything larger resolves a **multi-up rail** with snapping off. Nothing you
write mentions a width, a breakpoint or a device, and the same control changes
paradigm in place when the space does.

`cards` is that paradigm's options table and is **refused without it** (a field
that drives nothing is not accepted and ignored): `perView` pins the count,
`minWidth` moves the floor at which a lane is dropped, `peek` overrides the peek
(`0` removes it). An explicit peek also applies to multi-card shelves, exposing
part of the following card as a continuation cue. An authored `perView` — or an authored `snap` — always wins.

A rail that leaves `perView` to the facts is adapting, so it needs an environment,
and it **refuses to construct** without one rather than silently taking the
large-screen arrangement (the same rule and the same message `UI.TabView` and
`UI.Picker` use). An application built with `Facet.new()` publishes its
environment for free; a headless caller builds one with `Facet.newEnvironment`
or passes `env`; and a rail that must *not* adapt says
so by declaring `cards.perView`, which asks the environment nothing.

<a id="self-measuring-extents"></a>
**A collection can measure the box it was given, on either axis.** Handing in a
number is the fast path when you already know it; predicting one you do not know
is the defect family the variable-extents mission was about, and it has a
signature: a memo that subtracts safe insets, a Screen's padding and a scrollbar
guess from the raw viewport rect, or a `math.clamp(math.floor(h * 0.5), 160, 420)`
standing in for a layout the caller does not own.

* **`viewportExtent = "auto"`** — the collection takes `fill` along its own axis
  and windows against what the solver gave it, reported through the presenter's
  per-refresh geometry pass. It **converges in one step and stops**: the host's
  size is decided by what CONTAINS it and never by what is inside it, so
  measuring cannot change what was measured, and an equality guard means a
  settled tree writes nothing. The frame before a measurement exists is seeded
  from the **screen**, which is an upper bound on any box inside it — so the
  first frame over-fills (a strict superset of what the viewport touches) rather
  than mounting three rows and popping. Available on `UI.VirtualList` and
  `UI.VirtualGrid`.
  **The one requirement**: an ancestor that hands the collection a DEFINITE
  extent along that axis. Put the collection in a pane whose extent the layout
  decides, which is what you were doing by hand anyway. **The two ways to get it
  wrong fail differently, and only one of them is loud**:
  * an ancestor that **HUGS** on that axis has no extent to give, so the
    collection measures **0** and mounts nothing. Obvious the moment you look at
    it;
  * an ancestor that is **UNBOUNDED** on that axis — which is exactly what
    another scroller's own scroll axis is — hands the collection its **whole
    canvas**. A `fill` dim offered an unbounded limit answers with its *content*
    contribution, and a scroll node's content measure sums its children, so the
    "viewport" comes back the size of every row there is and the window covers
    all of them. **Virtualization is silently off**: the layout looks perfect,
    every row is present and correctly placed, and nothing about correctness can
    tell you. Measured: 400 rows of 40px inside a y-scrolling page reported a
    16,000px viewport and mounted all 400.
  The collection detects the second one and says so, on the seed's own argument
  turned around — *a box is never bigger than the surface that contains it*, so a
  measurement that **exceeds the screen** is a canvas rather than a viewport. It
  lands in **`dump().diagnostics`** naming both numbers and the fix. It is
  reported and deliberately **not** clamped: clamping the window while the solver
  still paints the host at canvas height would leave the bottom of the painted box
  empty of rows, which trades an invisible defect for a visible one.
* **`crossExtent = "hug"`** (list only) — the axis the list does not scroll sizes
  to its CONTENT instead of filling: the host, its canvas and every row take
  `content` across, so a sideways rail is exactly as tall as its card. This is
  the answer when `fill` is a promise the box will be big enough and it is not —
  a rail whose page is short clips its cards rather than growing, and the caller
  ends up summing the card's padding, its line boxes, the theme's chrome inset
  and outset, and a slack constant for the scrollbar, every one of which the
  solver already knows.
* **`crossExtent = "measured"`** (list only) — it still fills, and the solved
  extent is reported. Use it when you need the number rather than a different
  size.

**`crossExtent = "hug"` and `width` are refused together** on a vertical list,
because there `width` *is* the cross axis and `"hug"` replaces that dim: keeping
both would silently discard the authored width, which is the accepted-property-
that-drives-nothing rule (constitution §4) this control already refuses `cards`
and `estimatedItemExtent` for. Drop `width` to hug the content, or take
`"measured"`, which changes no dim and therefore composes with an authored width.
On `axis = "x"` there is nothing to refuse: `width` *is* the scroll axis there and
is already refused on its own.

**`itemExtent = "cards"` does not take the screen seed**, and the exception is
the rule stated precisely: the seed's over-fill argument is about *windowing*,
where an over-estimate mounts more rows than the box touches and is bounded and
invisible. The card paradigm makes the same number decide how many whole cards
belong in view, which is a **paradigm** answer and not a size — measured, a 300px
rail on an 800px screen resolved a three-up arrangement of 261px cards on its
first painted frame and a one-up 270px carousel on its second. So a card rail
seeds **0**, which windows to nothing: one frame painting nothing, then the right
arrangement. Every other list keeps the screen seed.

Both forms publish their number on the returned table as a
a Compose readable of a number — `list.viewportExtent`, `list.crossExtent`,
`grid.viewportExtent` — so a consumer reads the box the collection was actually
given instead of re-deriving it. **A collection that declared its own numbers
publishes neither**, because it already has them and a second copy would be the
same number twice.

**`rowHeight` and `viewportHeight` are DEPRECATED aliases** of `itemExtent` and
`viewportExtent` (since 0.9.0, removed no earlier than 0.10.0 — see
`Facet.DEPRECATIONS`). Both still work and are identical on `axis = "y"`, so a
vertical list needs no edit at all; they were renamed because a `rowHeight` on
`axis = "x"` names a height that is really a width, and the alias would have to
lie to somebody. Passing the new name and the old one together is refused at
construction: it is one field. (This is `UI.VirtualList`'s `rowHeight` only —
`UI.Table.rowHeight` is a different control's current API and is **not**
deprecated.)

<a id="variable-item-extents"></a>
**`itemExtent` may be ONE number or a PER-ITEM function**, and which one you pass
decides the arithmetic.

* A **number** or a **Compose readable of a number** is *uniform*: every row is that tall
  and the window is `index × pitch`, O(1) and exact. Derive it from the
  theme-metrics snapshot and the list re-derives on a swap.
* A **function `(item, index, use) -> px`** is a *variable* extent: each item
  declares its own size and the list windows by a **running-offset index** — a
  prefix sum, searched rather than divided (`src/virtual_extents.luau`). Building
  it is O(N) *arithmetic* once per data change; **no item is built and nothing is
  measured**, so the list is exactly as lazy as it was. Every query after it is
  O(log N).

**Read every live fact through the third argument, `use`.** It is the extents
memo's own `use`, so `use(preferredTextOffset)` inside the function re-derives
the whole table when the player changes their text size. Calling `:get()` on a
readable with `:get()` instead gives the right number *once* and registers no dependency — the
extents then go stale silently, which is the failure mode this form exists to
end. An extent that is not a positive number is refused at construction, naming
the row's key.

**A variable list anchors its scroll.** `scrollTop` is a pixel offset, so when
every row grows at once — a text preference, a ~1.4× localization, a theme swap —
that pixel would land on a different item. The list holds the item under the
viewport's leading edge, and the offset into it, and re-applies it through the
bound controller whenever the extents change. A uniform list does not anchor:
its pixel offset already lands on the same row.

<a id="measured-item-extents"></a>
**...or stop declaring it: `itemExtent = "measured"`.** All three forms above are
*predictions* — you promise a number only the solver knows. The fourth form makes
the row's extent **what its own cell measured**:

```luau
itemExtent = "measured",
estimatedItemExtent = 76,   -- REQUIRED here, refused on every other form
```

* The cell rides one control-owned `Content` wrapper — `content` on the scroll
  axis, `fill` across it — so its arranged rect *is* the cell's own measure. It
  cannot see the slot it decides, which is why converging is **one step** rather
  than a loop.
* The measurement arrives on the presenter's per-solve geometry broadcast, so
  there is **nothing to wire**. It is equality-guarded: feeding the same rects
  moves nothing.
* **Only windowed rows are measured.** Everything else is
  `estimatedItemExtent` — which is what keeps the list lazy, and is also the one
  cost: the *total* canvas is an estimate until every row has been on screen once,
  so the scroll **thumb's** proportion moves even though the content under the eye
  does not. `dump().measuredRows` reports how converged the list is.
* **`estimatedItemExtent` should over-reserve slightly.** It never decides how tall
  a row is *painted*, only how long the canvas claims to be before a row has been
  seen — but the first solve of a newly windowed row is the one frame where the box
  is still the estimate, so an estimate that is too small lets a row paint over its
  neighbour for that frame.
* **A cell declaring `fill` on the SCROLL axis is refused**, naming the row: a fill
  child inside a content wrapper measures 0, and the intent is circular anyway — a
  measured row is exactly as tall as its cell.
* There is **no lying-`itemExtent` finding** on a measured list, because there is no
  declaration left to lie. The class is structurally closed rather than checked.

**It is not the default, and the reason is measured.** A measured row mounts one
extra node and every solve walks the window reading rects back, which prices at
roughly **+30% per scroll frame** in steady state and about **+100%** while a
region is still converging, against a declared list painting the identical rows.
Reach for it when the row's height genuinely cannot be predicted — text that wraps
with no `lineLimit`, user content, a localization you do not control — and keep
declaring the ones you can.

<a id="a-lying-itemextent"></a>
**A lying `itemExtent` is caught and named — on either form.** The window is
exact *only* while the declared extent is the row's true size — and
you, not the list, are the one who has to predict it, for every live fact your
cell reads: the viewport width, `typographyScale`, the theme's `chromeInsets`, and
the player's accessibility text preference. Predict it low and every row paints
over the one below it, on somebody's device and not on yours. **The per-item
form does not retire this guard**: a declared per-item extent is still a
prediction, and the finding simply names *that row's own* declaration instead of
one list-wide number.

So the list hands its declaration to the solver (each row carries
[`virtualSlot`](#zstack)), and every solve compares your cell's own measure
against it. When the cell is **taller than the slot**, `controller.diagnostics()`
carries a finding under that row's path naming *both* numbers:

> `/Screen/Racers/Canvas/W/[r7]/Row/Cell` :: UI.VirtualList 'Racers' declares
> itemExtent = 56, but this row's content measures 74px on the list's y axis —
> 18px taller than the slot it is windowed into…

It is a diagnostic, not a refusal, because the true extent is not knowable at
construction — the viewport and the type scale are not decided until a solve.
It is not thereby optional: the device sweep and the performance lab both fail on
a solver finding. A row **shorter** than its slot is fine (over-reserving is the
safe direction), a cell that scrolls or clips its own overflow is skipped, and a
cross-axis overflow is still reported by the ordinary layered-overflow finding.
The repair is to recompute `itemExtent` from the same facts the cell reads — never
to widen the slot into a `minMax`, which a fixed-pitch window cannot use.

Cells own async
resources through `ctx.scope`, so window exit cancels them. **Input is
auto-composed** by the presenter, with nothing to pass at mount:
mouse wheel and one-finger touch pan scroll the window; each row is
a focusable hit whose tap / Return / ButtonA activation calls `onActivate(item,
meta)`; Up/Down and D-pad step the windowed rows, scrolling a row into view
when focus crosses the window edge. The viewport is a real engine clip host so
partial rows crop.

**It does reorder, and it does intercept Navigate.** A `reorderable` list adds
`navigateIntercept` to its contribution — that is how arrow/D-pad keys move the
predicted slot while a row is armed instead of moving focus — and a list that is
either reorderable *or* a drop surface adds `handleCancel`, so Cancel ends an
armed session rather than falling through to the surface. Neither is contributed
by a plain read-only list. See **The unified collection** below.

Native canvas (native-substrate NS-A4): the list rides a `ScrollingFrame`
whose `CanvasSize` is the FULL virtual height while only the window mounts.
Engine `CanvasPosition` drives `scrollTop` (wheel/touch/momentum/bars are
native), and `focusKey`/keep-visible compute a canvas target written through
`controller.scrollTo`.

**You do not wire the mirror. The framework does.** A mounted `UI.VirtualList`,
`UI.VirtualGrid` (either axis) or `UI.Table` binds its own `CanvasPosition`
mirror through the contribution seams every mounted control already gets, so the
collection follows the player's finger with nothing to call afterwards.

`bindNativeScroll(controller, scrollPath?)` is public and returns an unbind, for
the two cases that need it: a **standalone mount** that never runs a presenter
(there is no contribution walk, so nothing auto-binds, and the call refuses by
name if you pass no path), and **turning the mirror off** — the unbind sticks for
the life of that mount rather than being re-asserted next frame. It is
idempotent: calling it for the (controller, path) already mirroring hands back
the same unbind instead of opening a second engine observer. `UI.VirtualList`
publishes the seam flat on its own record; `UI.Table` publishes it as
`api.bindNativeScroll`.

There is **no opt-out key**, because there is only one collection whose scrolling
is genuinely owned elsewhere and it already publishes that fact: a
`UI.Table { scrolls = false }` block table owns no `ScrollingFrame`, so
`api.scrollPath()` is `nil`, and the automatic path reads the same answer — it
mirrors nothing and still binds the row-actions tray-close to the real scrolling
ancestor. A `UI.VirtualList`/`UI.VirtualGrid` always mounts its own `ScrollView`
and has no such state to be in.

**The unified collection.** One construct windows, **selects**, **reorders** and
**accepts drops** at the same time, because a second list construct would have to
re-derive windowing, keyed identity and keep-visible to get there. Reorder and drop ride the public `UI.draggable` / `UI.dropTarget`
contract rather than a private path, so an internal row move and a card dropped
in from another container are literally the same session, the same legality seam
and the same terminals.

| Spec field | Meaning |
|---|---|
| `itemExtent` | a number, a **Compose readable of a number**, a **function `(item, index, use) -> px`**, or the word **`"measured"`**: one item's size along the list's own axis. The first two are UNIFORM (windowed by index×pitch); the function is a DECLARED per-item extent (windowed by a running-offset prefix sum) and must read live facts through its `use` argument; `"measured"` declares nothing and windows each row at what its own cell measured. See [variable item extents](#variable-item-extents) and [measured item extents](#measured-item-extents) above. (`rowHeight` is its deprecated alias, above — and it reaches the same four forms.) |
| `estimatedItemExtent` | a number or a **Compose readable of a number** — the size an UNSEEN row is windowed at until it has been on screen once. **Required** with `itemExtent = "measured"` and **refused** on every other form, where every row in the data already has an answer and this field would be accepted and then ignored. Over-reserve slightly; see [measured item extents](#measured-item-extents). |
| `rowGap` | the gutter **between item slots**, a non-negative number, a **theme metric name** (`"xs"`, `"tight"`, `"s"`..`"xl"`, or a dotted path such as `"controls.table.rowGap"`), **or a Compose readable of either**, default `0` (the name is not axis-specific on purpose: a gap is a gap on either axis). A name resolves against the **live snapshot on every read**, so a theme swap moves the gutter with no rebuild — the same contract [`UI.Table.rowGap`](#uitable) carries. A name that resolves **nowhere** is REFUSED at construction, by name: `rowGap = "6"` is a number somebody quoted, and a gutter of zero looks exactly like a gutter nobody asked for. (`UI.Table` falls back to `0` there instead; the collections deliberately do not.) The **pitch** is `itemExtent + rowGap` and every windowing number rides it — canvas extent, the scroll clamp, window membership, keep-visible, the insertion slot, the reorder slide. The item's own node stays **`itemExtent`** along the axis, so the gutter is **dead space**: a pointer in it hits neither neighbour. The content extent carries no trailing gutter — N rows span `N*itemExtent + (N-1)*rowGap`, exactly like a `UIListLayout.Padding`. Uniform per list — unlike `itemExtent`, the gutter has no per-item form, because a gap that differs per row is a property of the ROWS and belongs in their extents. Do **not** hand in the pitch as the extent and inset the cell: that inflates the row's hit into the gutter, so a press between two plates activates one of them. |
| `viewportExtent` | a number, a **Compose readable of a number**, or the word **`"auto"`** — the host's size along the list's own axis. A readable is for a consumer that already knows the number and wants both readers of it to track: the painted host box and the windowing arithmetic. `"auto"` is for one that does not: see [Self-measuring extents](#self-measuring-extents) below. A build-time pixel goes stale the moment the device rotates. (`viewportHeight` is its deprecated alias, above.) |
| `crossExtent` | absent (the default), `"hug"` or `"measured"` — where the axis the list does **not** scroll gets its extent. Absent it FILLS. See [Self-measuring extents](#self-measuring-extents). It is a **list** field and not a grid one: a grid's lane width is derived FROM its cross extent, so a hugging grid would be asking its lanes how wide they are in order to know how wide its lanes are. |
| `selection` | `"none"` (default) or `"single"`. Activate selects the row from **every** paradigm (tap / Return / ButtonA). `selectedKey` is a Compose cell; `list.select(key)` / `list.clearSelection()` drive it; `onSelect(item, key)` reports it. Selection **prunes with the data** and survives a re-sort that keeps the row. The selected row also carries the **native `selected` state** on its own hit node (Table parity), so the theme paints it (`controlSelected`) and a cell never has to spend an elevation role saying "chosen". |
| `selectionPaint` | `"native"` (default) or `"none"`. `"none"` keeps the selection — `selectedKey`, `onSelect` and the ring all stay — and drops only the row's native `selected` state, for a list whose "chosen" is carried somewhere that is not the row (the standings list whose selected racer is the one the camera is watching). `selection = "none"` cannot express that: it deletes the selection itself. |
| `reorderable` + `onReorder(key, toIndex)` | rows become draggable. `toIndex` is the **1-based index the row will occupy in the resulting order**; a drop that reproduces the current order emits nothing. Order is owner state: the list renders what it is handed. |
| `reorderMotion` | motion class for the slide to a new slot (default `"object"`, `"instant"` to opt out — finding F6). Needs `motionClock`; the slide rides the presentation channel, so it never re-solves. |
| `dropSurface` / `rowDropTarget(item)` | each row becomes a drop target. `rowDropTarget` returns `{ accepts, onDrop }` for that row; `onDrop(payload, info)` gets `info.key`, `info.item`, `info.index`. |
| `rowActions(item)` | `(item) -> { leading?, trailing?, fullSwipe? }?` — **hosted row actions** (see below). Returning `nil` for an item leaves that row completely unwrapped. Refused together with `reorderable` (v1). |
| `rowFocusable(item)` | the focus-skip predicate, evaluated at navigation time. A row answering `false` is stepped over by the ring. |
| `rowSelectable(item)` / `rowMovable(item)` / `rowDeletable(item)` | **per-row capability opt-outs**, spelled **positively** (true = the row may take part) so they read the same way as `rowFocusable` beside them. Each answers "may THIS row do it?", never "can this container do it at all?" — so declaring one without the capability it narrows is a **construction error**: `rowSelectable` needs `selection`, `rowMovable` needs `reorderable` **and** `onReorder`, `rowDeletable` needs a destructive row action. Absent = every row participates, and the check is one `~= nil`, so adopting the family costs nothing. They **fail closed**: a predicate that throws refuses the capability, because a consumer bug that stubbornly refuses to move a row is visible and harmless while one that silently deletes a protected row is not. Only an explicit `false` refuses — returning `nil` from a forgotten branch keeps the permissive default, matching `rowFocusable`'s shipped reading. One implementation (`src/row_capability.luau`), two callers. |
| `focusPolicy` | `"key"` (default) or `"index"` — **when the ORDER changes under the player, does the cursor follow the ITEM or stay on the SLOT?** `"key"` lets focus follow the item, so a list re-sorting every 250 ms walks the pad cursor up and down the rows on its own. `"index"` pins the slot: when a data update moves the focused item off the slot it was focused at, focus **retargets to whoever occupies that slot now**, clamped to the last slot if the list shrank. This is the answer a live standings list needs ("selection riding a racer's button visibly JUMPS slots on every overtake"). The retarget drives BOTH halves of focus — the logical `focusedKey` *and* the screen's focus graph, which the presenter hands the control through the contribution's `bindFocusGraph` — so there is one focus authority and no consumer-side re-pin loop. It is an **ordinary focus move**: keep-visible applies, and it never summons a focus ring the player put away (the ring-visibility origin is left alone). It **declines** in exactly two situations: while a drag session is live (a policy that re-aimed a gesture mid-flight would fight the player's hand), and when the slot's new occupant fails `rowFocusable` — parking the ring where Activate can do nothing is worse than the jump the policy prevents, so focus falls through to the item. Construction-only, and an illegal value is refused naming both. `dump()` reports `focusPolicy` and the live `pinnedSlot`. |
| `navigation` | `{ name?, wrap?, containment?, entry?, exit? }` — overrides for the ONE navigation group this list contributes. Absent, the group is `vl:<id>`, vertical, `entry = "nearest"`, unwrapped and with no declared exits. An unknown field is refused at construction. `list.focusGroupName` reports the resolved name so a **sibling** group can declare `exit = { down = list.focusGroupName }` without hardcoding the `vl:` convention. |
| `autoscroll` | `false` to disable, or an options table. Defaults on whenever the list is reorderable or a drop surface. |
| `grabOnActivate` | whether a non-pointer Activate **arms** the row. Defaults true when the list is reorderable and declares no `onActivate` (so the two verbs never shadow each other); bind `list.toggleGrab()` to a key when it declares both. |
| `follow` | `"end"` or `"none"` (default), **or a Compose readable / `function(use)` answering one of them**. `"end"` holds the tail in view while the player is reading it, and leaves a player who scrolled away where they are. A live flip needs no rebuild. |
| `followThreshold` | a finite, non-negative px distance from the end inside which the player still counts as reading the tail, and within which following RESUMES after a yield. Default `4`. It is not what decides a yield — direction is. It means something only with `follow = "end"`, and is refused on a list whose `follow` is a constant that is not `"end"`. |
| `scrollNavigation` | `{ position, active? }` — one scroll offset shared across presentations. `position` is a writable Compose cell of the pixel offset; `active` is a boolean source that suspends restore and publish while it reads false. |
| `env` | the surface environment (Table's own `env` key, and read for the identical reason). Only consulted by `rowActions`: a hosted tray's `buttonPad`/`buttonMinWidth` are theme facts with no font component, so measuring a tray's natural width needs the live `themeMetrics`. Absent degrades to the neutral snapshot — right until a theme package moves those two metrics, and silently wrong from then on. Accepted (and unread) on a list without `rowActions`. |

The collection reads and verbs on the record: `selectedKey`, `armedKey`, `dropIndex` (the 1-based slot a
live reorder would commit to), `autoscroll` (a Compose cell of `{ state, band }` for
the edge affordance), `focusGroupName`, `select`, `clearSelection`, `toggleGrab`,
`stepAutoscroll(now)`, `engagedKey` (a readable: which row is currently revealing
a hosted row-actions tray, nil when none), `engagedOffset` (a readable: that
row's signed reveal offset in px). Both are nil on a list without
`rowActions`.

**Naming the list to its neighbours.** A screen that puts this list beside an
authored row of controls has to state how focus crosses between them ("left from
any row returns to the hand"; "the hand's up/down enters the list"). Both halves
are declarations: the neighbour attaches its own group through
`Facet.contribution.attach`, and the list's own `wrap`/`exit` come from
`navigation`. Rebuilding the list's group consumer-side is never the answer — its
order entries carry the live focus-skip predicates *and* the active-interaction
exemption, so a hand-written copy silently loses both.

**Reachability of reorder, per input class.** Mouse: press and travel past the
pointer promotion token. Keyboard/gamepad: `arm → navigate → commit/cancel` —
Activate arms, Navigate moves the predicted slot (and keep-visible-scrolls, so
rows past the window are reachable), Activate commits, Cancel cancels. **Touch**:
a press on the row body **declines the capture** so the native `ScrollingFrame`
keeps the pan — fighting engine momentum scroll is never winnable — so touch
reorder rides the grab verbs, which is the split `UI.Table` shipped for the same
reason.

**Edge autoscroll** is wired but not self-driving: call
`list.stepAutoscroll(now)` once per frame (the client's `PreRender` shim,
alongside `clock:step`). It applies the scroll through `controller.scrollTo` and
re-runs the drop hit-test **in the same frame**, which is what keeps the drop
legal. Non-pointer sessions never autoscroll: focus-follows-navigation already
scrolls the host.

**Hosted row actions (`rowActions`).**
Table's own `rowActions` wraps every actionable row in a `UI.RowActions`
COMPOSITE — five extra `Instance`s per row, mounted whether the row is ever
touched or not (~+45% steady / ~+82% fling per refresh, measured). A
virtualized list cannot pay that on rows nobody ever swipes, so VirtualList
**hosts** the feature instead of delegating it: `rowActions: (item) -> {
leading?, trailing?, fullSwipe? }?`, a per-item callback returning the same
three fields `UI.RowActions` itself takes minus
`content`/`coordinator`/`env`/`editing` (VirtualList supplies the row's own
content, one shared `newRowActionsCoordinator` for the whole list, and its own
`env` automatically; there is no per-row edit-mode minus in v1 — that is
Table-only). Returning `nil` for an item — the common case — leaves that row
completely unwrapped: no extra `Instance`, no extra subscription, the same
true-inert-passthrough guarantee `UI.RowActions` itself ships. An unknown key
in a returned table is a build-time error naming the offending row.

*The closed-row cost story.* A closed row's entire marginal cost is **four
static handler props** on the row's `Hit` Button, which already mounts for
every list whether or not it declares `rowActions` — no wrapper node, no
per-row closure, no subscription, and the four prop VALUES are the same four
shared dispatcher functions for every row on the list. The gesture/state
engine (axis lock, velocity, commit ladder, one-open coordinator — the same
machinery the standalone composite runs) is built **lazily**, on the first
gesture that resolves HORIZONTAL past the axis lock on that row: a vertical
pan, a fling that merely began on the row, and a tap all build nothing.
Scrolling a thousand closed rows builds zero engines. `rowActions` +
`reorderable` on one list is refused at construction in v1
(`"newVirtualList: rowActions + reorderable is unsupported (v1)"`) — reorder
rides the declarative `UI.draggable` contract, and composing that with the raw
pointer-handler funnel this feature rides is its own future task.

*Behaviour worth knowing, beyond parity with Table and the standalone composite:*

- **Keyboard/pad Delete reaches a hosted row only once that row has an
  engine — i.e. after a swipe.** Standalone's `UI.RowActions` binds Delete
  the moment the composite mounts; hosted mode's engine is lazy (see above),
  so an unswiped hosted row has no engine and therefore no Delete binding
  yet. A list-level Delete binding that reaches every row without a prior
  swipe is a booked follow-up, not shipped here.
- **A row refuses a new gesture until it is home.** After a full-swipe
  commit fires, the row's own persistent spring carries it the rest of the
  way closed (or, for a destructive action, collapses its height first) — and
  a press landing anywhere in that return flight is refused, for roughly
  0.3–1.1s depending on how far the row has to travel. This is shared
  `row_actions.luau` behaviour, not hosted-only: standalone and Table rows have
  the identical window.
- **`rowActions(item)` re-runs only on item table-identity change.** The
  per-row answer (and any engine already built from it) is cached against the
  specific item table a key was last asked with, not merely the key. A row
  that returns different actions when its item changes — locked/unlocked,
  ownership transferred, a racer finished — picks that up the moment a NEW
  item table lands at that key; a row re-rendering with the same item table
  costs nothing extra.
- **A committed row's slot does not close up.** A destructive commit
  collapses that row's own box height, but the canvas geometry is index ×
  pitch, so the rows below it do not slide up to fill the gap the way a stack
  layout's would. Removing the item from `rows` — typically inside the
  destructive action's own `onAction` — is what closes the gap; that is
  correct virtual-list geometry, not a bug to work around.
- **Tab reaches a revealed tray, but after the windowed rows.** The tray
  lives in the list's own shared overlay, a sibling of the rows region rather
  than a child of the row that opened it, so the presenter's document-order
  Tab rank visits it last, not beside its row. The d-pad has the better
  experience — Left/Right enters and leaves the tray directly from the row,
  because that ride is the focus GROUP `buildFocusGroups` splices in for the
  revealed tray, not raw document order. That group also **wins its own edge
  over an author's `navigation.exit`** for the one direction it is revealed
  on, for as long as it is up: a tray is transient and player-invoked, so a
  player who just swiped a row open must be able to reach what they revealed
  even if the list declares that same edge as its own exit. The author's exit
  is never overwritten — only suspended until the tray closes, at which point
  the very next refresh restores it.
- **A dev-drive Activate does not dismiss a revealed tray.** A real finger
  tap and a real keyboard/gamepad Activate both close the engaged row when
  they land elsewhere (armed by the true pointer-up sequence, or by
  `meta.source == "action"`), but an Activate delivered with no meta at all —
  or one merely TAGGED `source = "action"` without going through a real
  pointer sequence — bypasses that suppression and activates the row instead,
  leaving its tray open — `adapter.tap` and a bare `driveActivate(path)` are
  both this case, dev-drive shortcuts that were never armed by a real pointer
  sequence. Exercise dismissal instead with a real tap (down/move/up), a
  device key, or `driveActivate(path, { source = "action" })` — the explicit
  tag routes it through the keyboard/gamepad branch, which closes the row.

---

### `UI.VirtualGrid`

`UI.VirtualGrid { ... }` / `UI.VirtualGrid("Id") { ... }` returns the grid's
node. Its spec keys are `id`, `items`, `key`, `cell`, `axis`, `columns`,
`itemExtent`, `viewportExtent`, `gap`, `rowGap`, `snap`, `overscan`, `width`,
`onActivate`, `scrollNavigation` and `env`; an unknown key is refused at
construction.

`ref = function(record) ... end` is called once while the grid is built with a
frozen `{ api, dump }`. This control is its own `api`: `blueprint`,
`focusGroupName`, `scrollTop`, `pathOf(key)`, `focusKey(key)`,
`revealItem(key)`, `bindNativeScroll(controller, scrollPath?)`,
`scrollTo(controller, offset)`, `scrollPath()`, `debugWindow()`, `dump()` and
`dispose()`, plus `viewportExtent` as a Compose readable when
`viewportExtent = "auto"` asked the grid to measure it.

**The lazy grid.** A collection laid out in `columns` lanes that builds and
mounts only the **lines of cells the viewport touches**. `UI.Grid` is the eager
half: it measures and arranges every cell it is given. Reach for `UI.Grid` when
the whole grid is meant to be measured together, and for `UI.VirtualGrid` when
the collection is longer than the viewport.

```luau
local grid
UI.VirtualGrid("Wardrobe")({
    items = catalog,                      -- a Compose readable of the array
    key = "id",                           -- a field name, or (item) -> string
    axis = "y",                           -- "y" (default, vertical grid) | "x" (sideways grid)
    columns = 4,                          -- integer >= 1, or a readable of one
    itemExtent = 96,                      -- ONE LINE OF CELLS' extent
    viewportExtent = 480,
    gap = 8,                              -- between cells ACROSS a line
    rowGap = 8,                           -- between LINES
    snap = "item",                        -- optional: settle on a LINE boundary
    cell = function(item, ctx)            -- ctx = { current, scope, index, line, lane, focused, stopScale }
        return UI.Text("Name")({ text = item.name })
    end,
    onActivate = function(item) open(item) end,
    ref = function(record) grid = record.api end,
})
-- nothing to wire: a mounted grid binds its own CanvasPosition mirror.
-- `grid.bindNativeScroll(controller)` is public for a standalone mount and for
-- switching the mirror off; see UI.VirtualList's Native canvas.
```

**`UI.VirtualGrid` refuses when it needs the environment and none is found or
given**: `viewportExtent = "auto"` and a theme-metric-name `rowGap`/`gap` both
read the live environment snapshot, and a headless or otherwise ambiguous host
makes the control name the fix instead of guessing.

**A grid REFUSES to construct on an AMBIGUOUS surface**, and only then. It adapts
nothing, so unlike `UI.TabView` or an adaptive card rail it normally asks the
environment for nothing at all — but two of its fields are facts *about* a
surface: a gutter spelled as a theme metric name resolves against the live theme
snapshot, and `viewportExtent = "auto"` seeds its first window from the screen. If
the application carries **more than one** live environment the framework will not
guess which surface this grid belongs to, so it refuses by name and tells you to
pass `env` explicitly or build the second surface on its own application. A
surface with **no** environment is a headless mount and is legal: a metric name
resolves against the neutral package and the seed is 0. A grid whose gutters are
numbers and whose viewport is a number never asks, and builds anywhere.

**`itemExtent` is one LINE's size, not one cell's.** It takes a number, a
Compose readable of a number, or a per-line function `(line, use) -> px`. The function
form is resolved inside a memo and is handed the memo's own `use`, so an extent
derived from the accessibility text offset, the theme metrics or the viewport
re-derives when they move. Reading a readable with `:get()` instead is right
once and registers no dependency.

**The windowing is `virtual_extents`, in line units.** The grid does
not carry a second windowing arithmetic: it builds the same running-offset index
`UI.VirtualList` and `UI.Table` use, with `count = ceil(#items / columns)`,
`extents` = the per-line extents and `gap = rowGap`. The cell↔line mapping is
plain division (`line = floor((index - 1) / columns) + 1`), which is an index
transform rather than windowing. And the mounted band **is a real `UI.Grid`**,
so the column width is `floor((innerW − gap × (columns − 1)) / columns)` because
that is the flow grid's own formula executing — not a copy of it. A short last
line keeps its column width and stays left-aligned for the same reason.

**`snap` is the same option `UI.VirtualList` documents**, in line units: `"none"`
(default) or `"item"`, which here means *settle on a line boundary* — the lane axis
is perpendicular to the scroll and has nothing to rest on. The machinery, the flick
rule, the end-of-list rule and the reduced-motion placement are all shared; see
`UI.VirtualList`'s `snap`. A grid's lane count stays `columns`, declared: the
adaptive card paradigm (`itemExtent = "cards"`) lives on the horizontal list,
because a card rail is a list.

**`axis` is `"y"` (default) or `"x"`, and it is construction-only** because the
virtual grid builds axis-specific windowing and input configuration. Ordinary
`ScrollView.axis` can change without rebuilding its host. On `"y"` the lanes divide the WIDTH and
the lines advance DOWN; on `"x"` the lanes divide the HEIGHT and the lines advance
RIGHTWARD. `columns` is the lane count in both directions and needs no
translation. Everything else in this entry is written in the vertical vocabulary
and turns a quarter turn:

| | `axis = "y"` | `axis = "x"` |
|---|---|---|
| `itemExtent` | one line's HEIGHT | one line's WIDTH |
| `viewportExtent` | the host's height | the host's width |
| `viewportExtent = "auto"` | measured off the solved host, both axes — see [Self-measuring extents](#self-measuring-extents) | same |
| `rowGap` / `gap` | px, a theme metric name, or a Compose readable of either — same contract as [`UI.VirtualList.rowGap`](#uivirtuallist) | same |
| `width` | the cross-axis Dim | **refused** — there the width IS the scroll axis; the cross axis is the height and it FILLS, so wrap the strip in a box of the height you want |
| the mounted band | `UI.Grid` | `UI.Grid { flow = "column" }` |
| the focus group's axis | `horizontal` | `vertical` |
| a whole-line step | Up/Down | Left/Right |

**`dump()` reports the mounted band's cross extent and its solved per-lane
width** (`crossExtent`, `laneWidth`), on
whichever axis is this grid's OWN cross axis (the width on `axis = "y"`, the
height on `axis = "x"`). `laneWidth` is the same formula the column-width
paragraph above names as *executing* — `floor((crossExtent − gap × (columns −
1)) / columns)`, clamped at 0 — read here instead of re-derived by a probe
reaching around `dump()` for a mounted cell's own rect. Both are `nil`/`0`
before the grid's first geometry sync (nothing measured yet, honestly, rather
than a guess).

The band being a real `UI.Grid` on both axes is what made `axis = "x"` possible:
hand-rolling a column-major band inside this control would have been the second
lane arithmetic the design exists to avoid. `flow = "column"` is the same
arithmetic read the other way rather than a parallel path.

**Scroll position is anchored on the ITEM.** A grid has two ways to move the
ground under the player — the line extents re-deriving, and the **lane count
changing**, which moves every item to a different line — and one item-keyed
anchor covers both. It is unconditional here, where `UI.VirtualList` scopes
anchoring to variable extents.

**Four inputs.** Pointer and touch scroll natively (the engine ScrollingFrame
owns wheel, pan and momentum; a scroll never activates a cell) and a tap
activates. Keyboard and gamepad get a windowed focus ring over the cells:
**±1 in the ring is always a step ACROSS a line** — the mounted band's document
order walks a line's lanes before it moves on — and **the perpendicular key steps
a WHOLE LINE**, which the focus graph has no group axis for and which therefore
arrives through the control's `navigateIntercept`. So on `axis = "y"` Left/Right
step a cell and Up/Down step a line; on `axis = "x"` those swap. (A virtual LIST
transposes the other way, because its line holds one item and its document order
IS its scroll axis.) Return / ButtonA activate, and a step past the window edge
scrolls the next line into view.

**A cell's own state dies when the cell leaves the window** — the same honesty
`UI.Table { virtualized = true }` owes. Keep anything that must survive a scroll
in the consumer's model; async work owned through `ctx.scope` is cancelled on
window exit, which is the point. Unlike a virtualized `Table`, there is nothing
to refuse here: Table wraps each actionable row in a composite whose lifecycle
is pruned by the DATA, while this control's only wrapper is the `Cell` node and
its lifecycle *is* the window's.

**Named non-deliveries**, each refused at construction with a route:

| | |
|---|---|
| `itemExtent = "measured"` | Not offered, unlike `UI.VirtualList`. A grid's line extent is a fact about `columns` cells rather than one, so "measure the cell and window at that" has no single cell to measure. A consumer whose cells cannot predict their own extent should say so with the per-line function form, or use a list |
| `minColumnWidth` | Refused. It needs the cross-axis size in px — a second measured seam beside `viewportExtent`. Bind `columns` to a memo over `Facet.adaptive.columnsFor(availableWidth, minColumnWidth, gap)`, which is the flow grid's own arithmetic, already exported |
| selection / reorder / `rowActions` | Not offered. A cell is the consumer's blueprint and carries its own interaction beyond the hit's Activate |

---

## Async resources

### `newResourceProvider`

`Facet.newResourceProvider(core, opts?) -> Provider` — the bounded async
resource provider (images and friends), built directly against a surface's core.
`opts`: `maxConcurrent` (default 4), `cacheBudget` (LRU entries, default 16),
`retry = { count, delaySeconds?, giveUp? }`, `now` (injected clock, default
`os.clock`), and the deprecated `retryAttempts` (below).

**`app.newResourceProvider(options?) -> provider, release` is the form an
application author uses.** It builds the same provider against the application's
own surface, binds a transport for it, and hands back a `release` the application
also calls for you on `app.dispose()`. `options` takes every key
`Facet.newResourceProvider`'s `opts` takes, plus **`bind`**:

- **absent** — the provider is bound to the Roblox transport
  (`ContentProvider:PreloadAsync`), which is what a live client wants;
- **`false`** — no transport at all. A headless caller then drains
  `provider.pendingRequests()` and answers `provider.complete` / `provider.fail`
  itself, which is what makes the provider testable off a Roblox client;
- **a function `(provider) -> unbind?`** — your own transport. `release` calls
  the `unbind` you return.

```luau
local function Gallery()
    -- headless: this caller completes its own requests
    local images, release = app.newResourceProvider({ bind = false, maxConcurrent = 8 })
    Compose.cleanup(release)
    local handle = images.acquire(Compose.currentOwner(), "rbxassetid://123")
    for _, request in images.pendingRequests() do
        images.complete(request.key, request.generation, request.key)
    end
    return UI.Text { text = function(use) return use(handle.state) end }
end
```

`opts` is **construction-strict**: `maxConcurrent` must be an integer ≥ 1,
`cacheBudget` an integer ≥ 0, and a declared `retry`'s `count`/`delaySeconds`
non-negative numbers. An unknown option key is refused. Each refusal names the
option and the rule.

**`retryAttempts` is deprecated (since 0.8.0; replacement
`retry = { count, delaySeconds?, giveUp? }`).** Two words for one concept, with
different semantics: `retryAttempts` means immediate attempts and a failed key
that re-requests on the next `acquire`, while `retry` means spaced attempts
against the injected clock and, by default, a give-up that lasts the session.
`retryAttempts` keeps its promise until removal.

- `provider.acquire(owner, key, opts?) -> handle` — `handle.state`
  (a readable of `"pending" | "ready" | "failed"`), `handle.value`,
  `handle.error`, `handle.release()` (also released by the Compose owner).
  Cached keys are ready immediately. `opts.retry` overrides the provider's
  policy for that key alone (retry counts and spacing are a call-site decision).
- **Bounded retry (`retry`).** `count` extra attempts after the first failure,
  spaced by `delaySeconds` of *injected* time — the provider is pure and
  non-yielding, so a delay is a due time `provider.tick()` crosses, never a
  `task.delay`. A spaced retry is **not** in `pendingRequests()` until it is
  due, so a transport that drains everything it sees cannot burn the spacing.
  When the budget is spent the key is **given up for the session**
  (`giveUp`, default `true` for a declared `retry`): it reads `failed`, a later
  `acquire` inherits that state instead of re-opening the transport, and
  `provider.invalidate(key)` is the explicit reset.
- **`provider.preload(keys, opts?) -> { keys, release }`** — warm a declared
  imminent set so a debuting badge skips the placeholder flash. It is an
  acquire without a view: the same requests, the same concurrency window, the
  same generations, so `release()` prevents work that has not started and a
  completion after it is stale. Never a global sweep — it fetches exactly the
  keys it was handed, and skips cached or given-up ones. **The returned handle is
  yours to release.** `acquire` takes a Compose owner and registers its release there;
  `preload` takes no owner, so a forgotten `release()` keeps the warm wave alive
  for the session and holds its concurrency slot.
- `provider.tick()` — cross the injected clock so due spaced retries join the
  queue. Call it from the same loop that steps the motion clock; a provider
  with no spaced retry has nothing to do.
- `provider.gaveUp(key) -> boolean` — has this key spent its budget for the
  session? (the honest read behind a placeholder that will never fill).
- Transport side (your loader or the platform adapter):
  `provider.pendingRequests() -> { { key, generation, attempt } }` (the
  active window, capped at `maxConcurrent`),
  `provider.complete(key, generation, value) -> "applied" | "stale"`,
  `provider.fail(key, generation, err) -> "retrying" | "failed" | "stale"`.
  Generations make cancelled/superseded completions stale by construction —
  a late completion can never resurrect a released request.
- `provider.invalidate(key)` — drops the cached value AND any session give-up.
  It does not reach a handle already holding that key: an existing handle keeps
  reading `ready` with the value it was given, and a fresh `acquire` is what
  re-opens the transport.
- `provider.counters() -> { handles, active, queued, cached, staleRejected, dropped }`
  — live counts for leak and behaviour assertions: outstanding handles, requests
  in the active window, requests waiting for a slot, cached keys, completions
  rejected as stale, and requests dropped before they started.
- Handles are scope-owned, and releasing the last handle for a key disposes that
  key's shared `state`/`value`/`error` Readables — so a blueprint prop that
  captured `handle.state` outlives the signal behind it and will read its last
  value forever. Bind the handle, not a copy of its field.

**Lifecycle.** The provider is a **session object**, and it holds the most state
of anything on this surface: an LRU cache, the in-flight request table, the
queue, the spaced-retry list, the session's give-up ledger, and one signal
triple per live key.

- `provider.dispose()` — drops all of it. **Idempotent.** After it, `acquire`
  returns a real handle that opens `"failed"` (the honest state: this key will
  never fill, and a nil would nil-index the caller's binding), while `tick`,
  `complete` and `fail` are inert — `complete`/`fail` answer `"stale"`, the same
  word they already use for a superseded generation, so a caller that checks the
  return needs no new branch.
- **It does not cancel your fetches**, and cannot: this module is the engine-free
  model, and the actual work is your coroutine calling `complete`/`fail` back
  into it. What `dispose` guarantees is that the landing is harmless. Teardown is
  a window, not a moment, and everything already in flight arrives inside it.

---

## Replication

### `replication`

`Facet.replication` — the client-side replicated-state adapters. Transport
is game-owned; you feed these from your remotes.

**Three ingest verbs, not one overloaded one** (constitution E-16): the name
says *what arrived* — a whole state, a delta, a recovery — because that is what
call sites branch on.

- `replication.snapshot(core, initialRevision, initialData)` — full-state
  snapshots: `.binding` (a writable Compose cell), `.ingest(revision, data) -> "applied" |
  "stale" | "duplicate"`, `.revision()`. Revisions are monotonic; stale and
  duplicate ingests are refused.
- `replication.collection(core, initialRevision, initialItems, requestResnapshot)`
  — keyed items with patch streams: `.binding`, `.revision()`,
  `.ingestPatch(revision, { set?, remove? }) -> "applied" | "stale" |
  "duplicate" | "gap"`, `.ingestResnapshot(revision, items) -> "applied" |
  "stale"`, and `.gapDiagnostics() -> { awaiting, attempts, exhausted }`.

  **`remove` is an ARRAY of keys**, `{ "a", "b" }` — never a set
  (`{ a = true }`). A set-shaped `remove` is a hard error naming the shape,
  because it cannot be told apart from an array on a numeric-keyed collection
  and silently removing nothing while answering `"applied"` leaves the client
  confidently wrong.

  A patch beyond the next revision is a **gap**: patching freezes and
  `requestResnapshot(fromRevision)` is called with the client's CURRENT
  revision. A throwing `requestResnapshot` does not latch the gap — the next
  patch asks again, so a transient remote error cannot kill the collection.

  **A LOST reply is retried, bounded.** The request is asked once per wait, and
  the wait is measured in refused patches (this module has no scheduler — the
  transport is yours) doubling between attempts: 4, 8, 16, 32. After five asks
  it stops, and `gapDiagnostics().exhausted` is `true` — the explicit state to
  surface as "reconnecting…" or "out of date" rather than a silently frozen
  list. A resnapshot arriving at any point still heals it completely and resets
  the diagnostics; the cap bounds the asking, never the recovery.

  `ingestResnapshot`'s acceptance rule depends on whether a gap is outstanding.
  **While awaiting, an equal revision is a legal re-base**: "nothing has changed
  since your gap" is the natural answer to a request made at the current
  revision, it applies, and it clears the gap. Outside a gap the rule is
  unchanged — a resnapshot must be strictly newer, and an equal one is `"stale"`.
  Note the asymmetry with the other two verbs, which call an equal revision
  `"duplicate"`.
- `replication.mutation(core, opts?)` — typed client requests:
  `.send(payload, expectedRevision?) -> envelope` (one in flight; a second
  send errors), `.confirm(requestId, result)` / `.reject(requestId, reason)`
  (idempotent; wrong-id responses ignored), `.reset()`, `.status`
  (a Compose cell of `idle/pending/confirmed/rejected` — pending NEVER implies
  success), `.lastResult`.

  **`reset()` works from any state, including pending.** It is the caller's
  escape from a request the server never answered: it rolls back the optimistic
  presentation (the request may still land server-side, so local state must not
  keep claiming a success nobody confirmed) and clears the active id, which is
  what keeps a late confirm or reject for the abandoned request ignored.

  `opts.optimistic = { apply(payload), restore() }` shows the expected result
  immediately and re-syncs on resolution. **`restore` has two jobs**, and which
  one it is doing depends on the terminal that called it: on **reject** it truly
  restores (put the view back), and on **confirm** it *reconciles from
  authoritative truth as of now*. Write it as "re-read authoritative state", not
  as "undo", or the confirm path is wrong. Both callbacks are quarantined: a
  throwing `apply` degrades the send to an un-optimistic one, the envelope still
  returns, and the request still goes out.

---

## Styling

### `tokens`

`Facet.tokens` — the token compiler. `tokens.compile(schema) -> (compiled?,
report)` validates a game's semantic token schema (surface/content color
pairs with a 4.5:1 contrast gate, type ramp, spacing, radii, strokes, target
sizes, motion durations, optional `shadows` presets) into frozen tables plus
a contrast/completeness report. `tokens.contrastRatio(a, b)` computes the
WCAG-style ratio.

`tokens.dangerPair(colors) -> (danger, onDanger)` answers the **effective**
destructive palette: the `danger`/`onDanger` roles from the table you pass, or
the library's fallback pair where a style predates them. It lives here, free of
dependencies, because both the sheet model and the theme-package compiler gate
on the same answer — so a game overriding the destructive palette can ask what
the contrast gate will actually run against.

`tokens.successPair(colors)` and `tokens.warningPair(colors)` return the effective
plate and readable partner. Without authored values, success uses accent/onAccent
and warning uses content/surface. Authored pairs win; both package and sheet
compilation require contrast ≥4.5:1. A newly authored plate requires its partner.

The public tint roles include `success`, `onSuccess`, `warning`, and `onWarning`.
Managed icon pictures beneath nodes explicitly tinted `onAccent`, `onSuccess`,
`onWarning`, or `onDanger` take that partner color through native sheet rules.
This also applies to selected menu and picker content. Other icon roles remain
package-owned. This semantic lettering does not change disabled alpha or the
hidden fallback glyph, and is not arbitrary per-node RGB inheritance.

The built-in default style ("Facet Neutral",
`src/tokens/default_style.luau`) is the neutral floor every app gets for
free; games override via their own schema. Style-modifier normalization
lives in `src/tokens/styling.luau`; the style lint (jagged corner+shadow
caveat, ~100 on-screen shadow budget) in `src/render/style_lint.luau`.

### `themes`

`Facet.themes` — theme packages and the effective metric snapshot.
Engine-free: this is the pure half of the theme system, safe in a shared or
server require graph.

`themes.define(def) -> (package?, report)` compiles a declarative package
(schema `facet-theme/1`). Sections: `identity` (`id`, `displayName`,
`schemaVersion`, `version`), `style` (ordered per-theme colour variants, gated
by the same 4.5:1 contrast/completeness rules `tokens.compile` applies),
`metrics` (typography roles, spacing steps, control sizes, per-family control
metrics, radii — `control`, `panel`, `pill`, and the optional `selection`, the
highlight shape every selection fill and its focus ring wear, which follows
`control` unless authored (square art sets 0) — strokes, `targetSizes.minimum`, per-slot content insets,
`iconSizes`, motion), `chrome` (a recipe per decoration slot: `{kind="native"}`,
`{kind="nineSlice", asset, contentInsets, fallback="native"}` or
`{kind="layered", layers, contentInsets, fallback="native"}`, any of which may
add `shadow`; plus the reserved non-slot key `focus`), `icons` (semantic icon
name → asset reference), `assets`
(semantic name → `{content, sliceCenter?, sliceScale?, preload?, fallback?,
tintRole?}`; `contentId` is a permanent alias for `content` and declaring both is
an error), and `compatibility`. `base = <package>` derives: values you omit
are inherited key-by-key, so "start from Facet Neutral and change the parts I
mean to" is one line. On success the package is deeply frozen and carries a
deterministic content `stamp`; on failure it returns `nil` plus a report whose
`errors` name the offending field, the problem, and the fix. Rejections cover
missing roles, unknown fields (with a "did you mean"), rule properties Facet
does not allow a theme to write, contrast failures, invalid insets, target
sizes under the 44px accessibility floor, nine-slice recipes without a declared
fallback or naming an undeclared asset, incompatible schema versions, and any
function anywhere in the definition — a theme is inspectable data, never code.

**The rich-skinning fields.** Additive to everything above, and all
of them are package data:

| Field | Where | What it is |
|---|---|---|
| `kind = "layered"` + `layers` | a chrome recipe | a contiguous array of at most 8 layers from the closed set `fill` / `frame` / `corners` / `edges` / `plaque` / `tile`, each with its own fixed geometry vocabulary. Z-order is array order. `scrollbar` and `barFill` refuse a stack (canvas space; clipped whole art) — both are compile errors naming the reason and the fix. |
| a per-state `asset` map | any asset reference, at BOTH customization rungs | `{ default, hover, pressed, selected, disabled, error }` through one normalizer. `default` required; unstated states fall back to it with tint rules still applying; a per-state `contentInsets` difference on any axis is a compile error. |
| `barTrack` / `barFill` / `barCap` / `barCenter` | slots | image value displays. `barFill` takes `direction` (`ltr` default, `rtl`, `ttb`, `btt`); its art is drawn at full track size and revealed through an adapter-owned clip window, so a value change costs no adapter write. `barCap` takes `startAsset` / `endAsset` / `size`. |
| `toggleTrack` / `toggleKnob` / `stepperPlate` | slots | the sliding switch and the stepper's glyph plate. Knob travel stays solver-owned. `stepperPlate` is whole-image by default and falls back to the `control` recipe when a package does not declare it. |
| `spinner` | slots | one dot of an indeterminate `UI.ProgressView`'s ring. Round by default (a dot, like the slider thumb); carries its own solid native paint so an unskinned spinner still reads, and refuses a gradient for the same reason every other value-control slot does. **It is the one slot that refuses ART**: the travelling pulse is the control's `tint`, which paints the node's own plate — and art suppresses that plate (`.facet-skinned-spinner { BackgroundTransparency = 1 }`, the image-is-the-element rule), so a skinned spinner would be five identical pictures that never move. A `kind = "nineSlice"` / `"layered"` recipe on it is a compile error naming the size metric, the radius and the accent colour that *do* retune it; `kind = "native"` stays legal. |
| `icons` | package | semantic name → asset reference (per-state maps legal). Sized from `metrics.iconSizes` through the snapshot, tinted by the asset's `tintRole`. An unknown non-namespaced name is a compile error; a theme with no icon draws the framework's ASCII-safe fallback glyph. |
| `identity.rendering = "pixel"` + `identity.pixelUnit` | package | `ResampleMode = Pixelated` on every image rule (censused), integer `SliceScale` enforced at compile, and snapshot lengths snapped UP to multiples of the unit. |

**`chrome.focus` — the focus treatment.** Focus is not a decoration slot (it
applies to whichever node currently *has* focus, not to a kind of surface), so it
is a reserved key inside `chrome` with its own two-value vocabulary:

```lua
chrome = {
    focus = { kind = "ring" },   -- the default: a hairline stroke in the theme's accent
    -- or
    focus = {
        kind = "glow",           -- a soft halo, materialized as one named UIShadow
        color = "$FocusGlow",    -- a per-THEME token, or an { r, g, b } literal
        blurRadius = { scale = 0, offset = 26 },
        transparency = 0.25,
        zIndex = -1,             -- MUST be negative (a shadow renders below its node)
    },
}
```

`"$Name"` resolves per theme against that theme's `colors` then its `extra`, and
`define` rejects a token that fails to resolve in **any** declared theme. The glow
parameters go through the same `styling.normalizeShadow` contract slot shadows
use, at *both* distance profiles, so an illegal value is a compile error rather
than a throw inside the render path. The ten-foot ("strong") variant is derived —
more blur, less transparency — so one set of numbers covers both distances. A
package asking for a glow on an engine without `UIShadow` falls back to the ring;
focus is never optional. `chromeCensus().focusGlows` / `.actualFocusGlows` report
the live count.

Independently of the recipe, the ring's colour now comes from the **active
theme's** accent rather than a constant captured when the render target was
built, and a live theme swap repaints whatever is focused at the time.

`themes.resolve(package, themeName?, facts?, overrides?) -> snapshot` composes
the frozen `ThemeSnapshot`, exactly once, in the declared order: authored metrics →
display/density policy → preferred-text reservation inputs → accessibility and
hit-target floors (which clamp UP only) → explicit overrides. Overrides are
dotted metric paths; each is recorded in `snapshot.overrides`, marking that
property deliberately theme-independent. The snapshot rides the environment as
the `themeMetrics` fact — one key, one signal — so `env:set("themeMetrics", …)`
is the single atomic metric commit and every mounted screen RE-SOLVES rather
than rebuilding.

**The typography ramp is EIGHT roles.** Six describe a size on the reading
ladder — `caption`, `label`, `body`, `heading`, `title`, `control` — and two
describe a **weight**: `strong` (emphasis at reading size) and `numeral` (a rank
or score figure). A role carries `{ font = { family, weight?, style? }, size,
lineHeight }`, and the *whole* entry reaches both the measure seam and the paint
seam, which is why there is no `weight` prop: an authored face that reaches only
one of the two is precisely the defect `UI.Text.font` was deprecated for.

The six ladder roles are **required** in a package; `strong` and `numeral` are
**optional and derived when absent**, so every package published against the
earlier vocabulary keeps compiling and every snapshot still answers all eight.
The derivation takes the base role's family, style, size and line height and
changes only the weight — `strong` from `body` at SemiBold, `numeral` from
`control` (or `heading`) at Bold — so a package with a display face gets *its*
face in both weights and authors nothing. Author either role to win outright.
The derivation runs in `themes.resolve`, never in a package's authored metrics,
so no package's content `stamp` moved when the roles were added. The same two
sizes are derived by `tokens.compile` for a game's own token schema.

**Art geometry: `chromeInsets`, `chromeOutsets` and `chromeBleed`.** Three
snapshot facts describing what a package's *art* does to a node's box. They exist
because a decorated node is not the rectangle its author declared, and every
consumer that needs to reason about the real box has to be told by how much.

| fact | what it is | who spends it |
|---|---|---|
| `chromeInsets[slot]` | per chrome slot (`panel`, `control`, `selection`, …): `{top, right, bottom, left}` px the slot's art reserves **inside** the node, before anything in it is measured — a nine-slice border, a plate's carved edge. Every slot publishes an entry, zero included | the renderer, added to the node's padding (`render/layout_node.luau`); read directly only when a caller must predict a decorated node's *content* box |
| `chromeOutsets[slot]` | per slot: px the art **bleeds past** the node, realized as a margin, so the node itself is that much smaller inside the box it was given. Fantasy Ornate declares one (20px off the top of `panel`); most packages declare none | the renderer, as the margin; and by anything sizing a box that must sit around the bleed |
| `chromeBleed` | a whole-package **number**, not a map: the deepest any slot's shadow reaches outside its box. It is the paint seam's clip allowance, and the reach an outermost `ScrollView` keeps clear so a child's glow is not cut by the viewport | the paint seam; and the outermost scroll host, as its chrome lane — `chrome_slots.bleedLane`, netted against that node's own carved inset, because a carved frame already holds content that far from the clip edge |

**`hasChromeInsets` is the guard to read first.** Because every slot publishes an
entry, `next(chromeInsets) ~= nil` answers "yes" on every package and tells you
nothing; `snapshot.hasChromeInsets` is the boolean that means "there is something
here to spend".

**They do not scale at ten-foot** — see the ladder below — because they describe
pixels the engine paints at the size the recipe declares.

**Prefer not to read them at all.** They are published because the framework's own
render seam needs them, and because a consumer that must predict a decorated box
has no other route; but a prediction assembled out of them is the defect family
`viewportExtent = "auto"` and `crossExtent = "hug"` exist to remove. A rail that
sums a plate's padding, its line boxes, `chromeInsets.panel` and
`chromeOutsets.panel` to guess its own height is short under some package at some
text preference. `crossExtent = "hug"` asks the solver, which already knows all
of them. Reach for these when you are extending the render seam; reach for a
self-measuring extent when you are building a screen.

#### A themed first frame

`themes.styleFor(package, themeName?, displaySize?) -> style` answers the `style`
a `Facet.new` surface boots with, so the first painted frame already wears the
app's theme. `themes.sheetModelFor(package, displaySize?) -> model` answers the
sheet model for a package. Decorate it (add a paint transition to a rule, for
example) and pass it to `app.installTheme` as `sheetModel`. Both are client-side
reads and resolve on call, so requiring Facet from shared code stays safe.

#### The ten-foot metric ladder

`themes.metricScale(displaySize) -> number` is the ten-foot **metric** factor:
`1.5` on a `Large` display, `1` everywhere else. It is deliberately the *same*
number `typographyPaintScale` returns — one constant, two ladders — because the
acceptance the ladder is held to is a **proportion equality**: every
text-to-control proportion at ten-foot equals its near proportion. A 16 px label
in a 44 px control at arm's length is a 24 px label in a 66 px control across a
room, and nothing outgrows its chrome.

`themes.forDisplay(snapshot, displaySize) -> snapshot` applies it. Pure, total,
idempotent, reversible, and **the identity at every near display** — the same
table, not a copy, so no near-distance geometry moves by a pixel. You rarely call
it: the environment's `themeMetrics` read calls it for you, from the live
`displaySize` fact, which is what makes the ladder reach a television with no
theme controller installed. `themes.baseOf(snapshot)` recovers the authored ladder
a distance-adapted snapshot was derived from (`env:set("themeMetrics", …)` calls
it, so a read-hold-write round trip can never compose the transform onto its own
output).

An adapted snapshot publishes two extra facts: `density` (`"ten-foot"` /
`"near"`, now taken from the live display class rather than from the facts the
snapshot was resolved with) and `metricScale` (the factor that was applied — the
number a consumer predicting its own geometry should spend).

**What scales**: `space`, `targetSizes`, `iconSizes`, `iconRunGap`, `controlSizes`
and every control-family length, plus the authored half of a slot `inset` — and the
**paint family**, `radii` and `strokes` (director ruling 2026-08-21). A corner radius
and a stroke thickness are painted from a second authority — `ctx.style`, and the
StyleSheet rules `sheet_model` bakes them into as literals — so they scale only
because that authority now derives them the same way:
`themes.paintForDisplay(metricsLike, displaySize, pixelUnit?)` is the one derivation,
`sheet_model.build`/`buildPackage` take a `displaySize` and bake what it returns, and
`screen_target` takes one at construction (`client.host` passes the environment's
fact; a consumer building its own target passes it too, or its corners stay near while
its layout goes to distance). **A metric may only scale where the framework owns the
paint** — unchanged as a rule; what changed is that the framework took the paint. A
radius rounds to a **whole pixel** because a `UDim` Offset is an integer (a pixel
package's grid wins where it has one); a stroke keeps its fraction because
`UIStroke.Thickness` is a float, so a 1 px hairline is 1.5 px at three metres. The
capsule sentinel (`radii.pill = 999`) scales like any other radius and paints
identically, because `UICorner` clamps to half the box's shorter side.
**What does not scale**: the type ramp (`typographyPaintScale`
already scales it at the measure and paint seams — scaling it here would be the
double application), `motion` (durations are time-true at every distance; reduced
motion is unaffected), counts and ratios, the player's own `preferredText` inputs,
a pixel package's `pixelUnit`, the overscan margins (a display fact, applied once
and composed with the safe insets rather than multiplied), and **art geometry** —
`chromeInsets`, `chromeOutsets` and `chromeBleed` describe pixels the engine
paints at the size the recipe declares, so reserving 1.5× of an unscaled border
would be a reservation for pixels that do not exist. A control-family metric is
treated as a length unless its name says otherwise (`*TextSize`, `*Lines`,
`*Count`, `*Duration`, `*Seconds`, `*Ratio`, `*Fraction`, `*Scale`, `*Opacity`,
`*Weight`); the `app` namespace below takes the same rule and the same
vocabulary; `themes.densityClassOf(path)` is the published classification, and
the suite fails on a numeric metric it does not classify.

**A package may state its own ladder.** `metrics.tenFoot` is a map of dotted
metric paths to **absolute** pixel values at distance —
`tenFoot = { ["space.m"] = 40, ["targetSizes.minimum"] = 80 }` — the same
vocabulary `themes.resolve`'s `overrides` parameter takes. Authored beats derived,
the rule `space.gutter` already spends: the derived 1.5 fills in wherever a
package is silent. A path that names no metric in that package's own snapshot is
refused at resolve time, and a declaration still may not defeat the accessibility
target floor.

#### The app metric namespace

Your app's own structural numbers — a tile minimum, a chart band, a dock height —
are neither spacing steps nor control metrics, and a metric **name** is validated
against the neutral snapshot. Without a channel of their own they stay literals:
outside every theme, outside a package swap, and outside the ten-foot ladder.

`themes.declareApp(namespace, metrics)` reserves them under **your app's own
group**. Call it **once, at app boot, before the first form is built**:

```lua
Facet.themes.declareApp("cartwheel", {
    tileMin = 96,
    chartH = 160,
    gallery = { rowHeight = { landscape = 56, portrait = 60 } },
})
```

From then on `"app.cartwheel.tileMin"` and
`"app.cartwheel.gallery.rowHeight.landscape"` are metric names like any other:
`px = "app.cartwheel.tileMin"` passes the same construction check
`px = "iconSizes.large"` passes, `themes.resolve` publishes them on **every**
package (so a proof that must mount under Facet Neutral *and* Fantasy Parchment
keeps its geometry either way), and `themes.resolve`'s `overrides` and a
package's `metrics.tenFoot` both reach them.

**The group is not decoration.** The namespace is process-wide, and one place may
host several apps — this repo's own showcase mounts five reference proofs and
switches between them at runtime. A declaration replaces **only its own group**,
so two apps compose instead of the second one silently un-spelling the first
one's names; `declareApp(namespace, nil)` retires a group.

The declaration is **validated, not guessed at**: the namespace and every key
must be an identifier (a `.` would make the dotted path ambiguous) and every leaf
a finite number. An **undeclared** `app.*` name is refused at construction
exactly as `iconSizes.enormous` is — declaring is what makes a name spellable, so
a typo is a build error rather than a nil size on the first solve.
`themes.appMetrics()` reads the whole section back, frozen. The namespace is
process-wide because `isMetricPath` runs at construction with no snapshot in
scope, which is the whole point of it.

**Declaring late is safe**, and it takes three mechanisms rather than the two it
looks like. A snapshot resolved *before* the declaration is refreshed at the
environment's own `themeMetrics` seam (only names the snapshot has never heard of
are added, so a package's `metrics.app`, an override and the pixel snap all keep
their answers), the framework's own default snapshot is re-read live when nobody
has committed a theme — and, decisively, **that memo subscribes to a declaration
edge**. An environment memoizes its metric read, and a memo re-runs only when a
signal it used changed; without the edge, a declaration made after the first read
invalidates nothing and every `px = "app.…"` in that app keeps resolving to
nothing while the band silently measures zero. The edge is internal
(`environment.new` registers a signal `themes.declareApp` publishes to) and it is
load-bearing: it is what makes anyone *ask* for the refreshed answer.

Call `declareApp` at boot or from an explicit application command. It changes
shared theme vocabulary and publishes a Compose cell; keep that work outside
formula evaluation. Existing environments read the new metrics on their next
tracked update or `peek()`. Use `env:batch` to group related declarations.

Publication attempts every registered environment before reporting an error.
A later declaration, including an identical retry, catches up an environment
whose earlier notification failed.

**A theme may move them.** A package's `metrics.app` is its answer for an app
number, exactly as `metrics.space` is its answer for a spacing step:

```lua
themes.define({ base = themes.neutralPackage(), … , metrics = { app = { cartwheel = { tileMin = 128 } } } })
```

Names it does not mention keep the app's own value. A package that names an app
metric the app never declared is **refused at resolve time** — inventing a name
in a namespace you do not own would otherwise be a number that silently never
moves.

**They ride the ten-foot ladder**, with `controls.*`'s rule word for word: an app
metric is a **length** unless one of its name segments says otherwise
(`*TextSize`, `*Lines`, `*Count`, `*Duration`, `*Seconds`, `*Ratio`, `*Fraction`,
`*Scale`, `*Opacity`, `*Weight`). So `app.cartwheel.tileMin` is 144 on a
television while `app.sponsor.mapFraction.landscape` and
`app.sponsor.listRowCount` stay exactly what they are — name a fraction, a count, seconds or a type size accordingly and
the ladder leaves it alone. A pixel package snaps app **lengths** onto its own
grid and leaves the rest untouched. A package's authored `metrics.app` entries
appear in the theme dump (`token_sync.records`) as `app.<path>` and round-trip
back through `metricsFromRecords`.

`themes.neutral()` is the Facet Neutral snapshot (the `themeMetrics` default;
its values are the literals the framework shipped before packages existed).
`themes.neutralPackage()` is the compiled package behind it (themes `Dark` and
`Light`) — pass it as `base`; a derived package inherits only its first theme.
`themes.lintProperty(prop, scope?)` is the legal-property ruling: a theme rule
may write only the native paint set, plus image chrome inside a nine-slice
recipe (`scope = "chrome"`). `themes.SCHEMA` is the schema string this build
speaks (`facet-theme/1`).

`themes.checkCoverage(package, declarations) -> { ok, covered, missing }` is the
pre-play gate for a **contributed control**. `define` deliberately passes
namespaced `ns:role` entries through, so a package that forgot your control is
otherwise indistinguishable from one that covers it. A control declares its needs
— `{ name = "ns:role", kind = "controlSize" | "color" | "number", section,
fields?, authority, capability, fallback }` — and each `missing` entry names the
role, what happens if nothing is done, and the exact line that fixes it. Each
kind has one legal home: `controlSize` → `metrics.controlSizes`, `color` →
`style.themes[].extra` (in every theme), `number` → an open scalar metric section
such as `metrics.radii`. Worked fixtures: `examples/themes/custom_control.luau`
and the fuller rung-3 example `examples/themes/ornate_gauge.luau`, walked in
[`../extending/skinned-control.md`](../extending/skinned-control.md).

#### The client-side theme controller

The engine half is client-only and is required directly, not from the `Facet`
table (the same rule as `screen_target`):

```lua
local theme_controller = require(ReplicatedStorage.Facet.client.theme_controller)
local controller = theme_controller.install(adapter, package, {
    env = env,                -- REQUIRED: the snapshot rides it as `themeMetrics`
    -- rootGui is NOT passed: screen_target reports its own root through
    -- adapter.themeRootGui(). Pass it only when you host roots yourself.
    theme = "Daylight",       -- optional; defaults to style.defaultTheme
    -- profile-conditional selection: map the input paradigm to a
    -- package and the controller installs the right one and swaps live on a
    -- SETTLED profile change (0.25s debounce). An unmapped class falls back to
    -- the package passed positionally; a manual swapPackage wins until the next
    -- profile change and warns once. The view tree never observes it.
    selectBy = { touch = touchPkg, pointer = pointerPkg, gamepad = pointerPkg },
    -- core?, selectBySettleSeconds?, overrides?, host?, transitions?,
    -- forceFallback?, preflightFonts?, fontFiles?
})
```

`install` materializes the package's own sheet (named `FacetTheme <id>`, with a
`Theme <name>` child per theme), links it at the target root, resolves the
snapshot and commits it. Every capability check runs **before** the first
mutation: a schema this build does not speak, an unknown or unprovided capability
(`themeMetrics`, `nativeStyleSheets`, `styleTransitions`), or a missing root
fails with an error naming what is missing, and the target and environment are
left untouched. **The missing-root refusal is native-paint only** — on targets
with Roblox `StyleSheet`s, where a root is what the sheet links at; without them
the install needs no root, commits the metric half, and reports fallback (see
below). **Present before you install** on either: a target has no root until it
has drawn one.

The returned controller instance:

| Member | Meaning |
|---|---|
| `swap(themeName)` | another theme of the same package |
| `swapPackage(package, themeName?)` | a different package entirely |
| `current()` / `snapshot()` | the active theme name / the frozen snapshot |
| `inspect()` | package identity + stamp, theme list, `mode`/`fallback`/`fallbackReason`, sheet `seeded`/`migrated`/`stamp`, link state, effective snapshot, compiled bespoke `style`, applied `overrides`, token attribute names, per-font calibration state, connection and swap counts |
| `dumpTokens()` | the active sheet's tokens as typed records — the `--dump` input for `tools/lune/theme_sync_cli` |
| `onChange(fn) -> unsubscribe` | install/swap/token-edit/uninstall events |
| `uninstall()` | restores the pre-install link and snapshot (the sheet, and the designer's tokens on it, are left alone) |

A swap is one transaction in one invocation — `SetDerives` for paint plus
`env:set("themeMetrics", …)` for geometry — so new paint and new geometry land in
the same engine frame and nothing is rebuilt: mount identity, focus, selection,
scroll position, text entry and resource ownership survive. On a target without
native StyleSheets the install still commits the whole metric half; the palette
applies from construction (`inspect().style` feeds `screen_target.new({ style })`)
and `inspect().fallback` reports the degradation. Full walkthrough:
[`../guide/09-custom-themes.md`](../guide/09-custom-themes.md); the
rich-skinning surface is [`../guide/10-rich-skinning.md`](../guide/10-rich-skinning.md).

**Before writing one, check the shelf.** Facet Neutral is built into the library
and eight ready-made packages ship as separate artifacts — one `.rbxm` each under
`build/themes/`, built by `tools/build_themes.sh` and installed through exactly
the `install` call above.
[`../guide/13-theme-catalog.md`](../guide/13-theme-catalog.md) is the catalog:
what each one looks like, what it does to your metrics, and what it costs. The
library itself names none of them — `build/Facet.rbxm` carries `src/` and the
`facet-neutral` package alone, which `tools/check_library_purity.py` enforces.
### `UI.Toggle`

`UI.Toggle { … }` -> the toggle's node. `ref = function(record) … end` receives a
frozen `{ api, dump }` once, while the control is built; Toggle publishes no
verbs, so `api` is the control's own record and `dump()` is the half worth
reading.

One boolean selection control with `presentation = "switch"` (default),
`"checkbox"`, or `"button"`. Required `value` is a boolean Compose readable or
`function(use)` binding. Optional fields are `id`, `label`, `enabled`, `onChange(value)`,
`row`, `hint`, `indicatorPosition`, `controlSize`, `width`, `appearance`, `textSize`, and `children` (custom button content only).

`appearance = "plain"` makes a switch or checkbox a bare row: no plate and no
selected wash, so the indicator alone carries the state (a toolbar checkbox beside
compact dropdowns). The button presentation refuses it — its plate is the state.
`textSize` is the label's type role (default `"control"`); a hint keeps `"label"`.

Use a Toggle for one setting that is on or off and takes effect at once. For a
compact filter tag in a row of tags, use `UI.Chip`; for one choice from three
or more values, use `UI.Picker`.

Without `onChange`, `value` and any `mixed` binding must be writable cells;
activation updates them directly. With `onChange(wanted)`, activation requests
the proposed boolean exactly once and writes neither binding. The model accepts
by writing its state; declining or delaying that write preserves the displayed
value. The callback's return value is ignored. A readonly binding requires this
callback. Caller writes update the display without calling `onChange`.

`row = { description?, icon?, value? }` turns the control into a settings row:
the label leads, an optional description and semantic icon sit with it, and the
actual switch or checkbox sits beside the copy. Switches default trailing,
checkboxes leading; `indicatorPosition = "leading" | "trailing"` overrides that.
Button presentation keeps its trailing state word and refuses indicatorPosition.
`hint` is bindable secondary text for a standalone setting; use `row.description`
in a row, since `hint` and `row` cannot be combined. `row` and `children` cannot
be combined, and `row.value` is refused because the toggle supplies it.

Bindable `controlSize` uses the shared xsmall/compact/regular/large ladder; nil restores
the default. A checkbox's box is then the rung's `iconSize` plus `xs` (fixed, its mark
fitted inside), so it grows with the ladder and never outgrows a row of controls at the
same rung. Bare switches retain native track padding. A row's internal indicator
has no independent focus or command: the row owns activation and model approval.
Its width resolves `controls.toggle.markWidth`, an optional theme metric defaulting
to `trackInset + trackWidth + trackInset`; an authored value overrides that default.

Bound `width` accepts the ordinary Dim vocabulary. Omission keeps the presentation's
settings-row default. Plain switches and checkboxes accept hug/content/minMax widths;
their label columns measure their own copy, so hugging checkboxes can wrap in a HStack.
Row and button forms refuse content-sized widths by name; fixed/fill remain supported.
Later width changes use the same checked source and recover after an invalid update.

Switches paint their initial value immediately. Later value changes slide the knob
without overshoot; pressing a switch keeps its label size unchanged. Reduced
motion places the knob immediately.

Checkboxes additionally accept `mixed`, a second boolean binding. Mixed
activation proposes true. Without a callback it sets `value` to true and clears
mixed in one transaction; with a callback the model must commit both changes.
There is no automatic three-state cycle. Clicking the label uses the same
activation as the indicator. Checkbox labels wrap; toggle buttons retain selected
styling between presses. Disabled controls preserve state and cannot activate.
Pointer, touch, Return, and ButtonA follow the same semantic activation path.

```lua
local app = Facet.new()
local UI = app.controls
local muted = Facet.Compose.cell(false)
app.mount(function()
    return UI.Toggle("Mute")({ label = "Mute", value = muted })
end)
```

`dump()` reports `{ schema, value, mixed, presentation, enabled }`.

### `UI.Button`

`UI.Button { … }` -> the button's node. `ref` receives `{ api, dump }`; the
button publishes no verbs, and `dump()` reports
`{ schema, id, busy, enabled, repeating, dialogAction, name, controlSize, appearance }`.

Use a Button for one action that the player starts, such as Save or Play. For a
state that stays on or off, use `UI.Toggle`; for a primary action with related
alternatives, use `UI.SplitButton`; for a list of verbs, use `UI.Menu`.

#### Local size, emphasis, silhouette and backdrop

Four optional keys let one screen hold a compact filter beside a large primary
action without swapping the theme. They are shared vocabulary: every control that
adopts them takes the same words with the same meanings.

| key | values | reactive | what it does |
|---|---|---|---|
| `controlSize` | `"xsmall"` / `"compact"` / `"regular"` / `"large"` | yes | resolves to the theme ladder `controlSizes.<rung>.{height,paddingX,iconSize}` as **metric names**, so a theme swap re-sizes the button with no rebuild, and to one style tag for the paint. `xsmall` is optional in a theme: unauthored it is one ladder step below `compact` (28/4/12 at Neutral); its plate paints under the touch floor and the reserved footprint keeps the 44 hit target |
| `appearance` | `"standard"` / `"emphasis"` / `"soft"` / `"utility"` / `"link"` | yes | visual emphasis only, through a style tag |
| `corners` | `"pill"` / `"square"` | no | the corner treatment, through the shipped `UI.corners` modifier. `"square"` is a radius of 0, never a 1:1 box — the disc is `UI.Button{ shape = "circle" }` |
| `over` | `"media"` | no | the control is drawn over artwork: it takes the theme's strong opaque surface and its readable content colour |

Absent means **today**: a button that names none of them retains its existing layout and paint.

**Paint shrinks, the footprint does not.** A control that names a rung is mounted
inside a plain container that reserves the larger of the Button class minimum (44px) and
`targetSizes.minimum` on both axes and
centres the smaller plate inside it, so the solved footprint is never below a
finger and **two sized controls cannot share a target at any gap, including none
at all**. What a rung buys is therefore the plate's density, not the layout's: a
row of `compact` buttons still occupies a 44px band, and still looks like a row of
small buttons. The container takes a derived id (`<id>+target`) and the control
keeps its own, exactly as `UI.overlay`/`UI.background` do, so focus, tests and
dumps still address the control by the name you gave it.

**An authored `height` wins over a rung.** A rung is a default; a caller who
measured their own layout is not overruled by one.

Composed content (`children`, `row` or `image`) keeps the theme's button padding
when a rung is named; the zero-vertical rung inset applies only to simple labels
and icons. Explicit `padding` overrides either default.

**`regular` is the ladder's rung, not the untagged default.** Naming it adopts
`controlSizes.regular.height` (44px at Facet Neutral) with the ladder's horizontal
inset and no vertical one; an untagged button is its content plus the theme's
button padding, which is 46px at Facet Neutral. The difference is small and it is
real — name a rung on all the controls in a row, or on none of them.

`appearance` and `role` are different questions and compose **in paint**, not just
in name. `role` is the semantic channel and `appearance` is emphasis, so the loud
words hand the plate to the role and the quiet ones keep their own plate while the
role colours the content:

| pairing | what it paints |
|---|---|
| `destructive` + `standard` / `emphasis` | the theme's danger plate with its readable partner — the role owns it outright |
| `destructive` + `utility` | the utility plate, danger lettering — a quiet delete |
| `destructive` + `soft` | the soft tint, danger lettering |
| `destructive` + `link` | no plate at all, danger lettering |

Each pairing holds **through hover and press** as well as at rest: the danger
signal moves with the state on whichever channel the appearance leaves free, so a
quiet delete never hovers back into an ordinary control.

A control constructed with `controlSize` mounts at
`<parent>/<id>+target/<id>`. Identity-based focus and keyed updates reach the same
plate, but a stored literal path must include the wrapper. Adding or omitting the
property at construction changes that path; a bound value becoming nil retains it.

`animation` on Button or Chip belongs to the actual primitive plate, including
when a target wrapper is present. The policy is validated against the Button
class; wrapper-only properties such as `opacity` are refused.

#### Icon-only and icon-plus-label buttons

`icon` and `trailingIcon` take a **semantic icon NAME** (a framework name, or a
package's `"ns:name"`) — never an asset id, and **construction-only**: the mark is
drawn once, so a getter is refused rather than silently sampled. The framework
draws its own legible glyph and an installed package paints its art over it. Each
reserves **at least** the rung's `controlSizes.<rung>.iconSize` on both axes
(defaulting to the `regular` rung) — a floor, not a cap, so the framework's own
glyph still grows with the player's text preference instead of being clipped by a
theme metric that does not.

`name` is the **semantic label** for a button with no visible label, and is
**required** for the semantic icon form there (the existing `shape = "circle"` primitive form keeps its contract): it is what a dump, a focus trace and a bug report call the
control. Supplying `name` beside a visible `label` is refused — two answers to one
question. `icon`/`trailingIcon` are the label's neighbours, so they do not combine
with `children`, `image` or `row` (those are whole content forms of their own).
A Button without drawable content refuses even when `name` is supplied. A bound
label may start empty and acquire content later; its value remains caller-owned.

```lua
local close = UI.Button("Close")({ icon = "close", name = "Close", corners = "pill",
    controlSize = "compact", appearance = "utility",
    onActivate = dismiss,
})
```

`controlSize` and `appearance` accept Compose readables and `function(use)` bindings.
They are borrowed from the caller; changing or retracting them updates the mounted
plate without rebuilding it. A bound rung retains its `<id>+target` wrapper when its
value becomes nil. Every update is checked against the control's own vocabulary;
an invalid value keeps the last legal paint and dimensions, and a later legal
value can recover. `corners`, `over`, and semantic icon names are construction-time.

A sized Button reads the mounted surface's environment to reserve the larger of
its class hit minimum and the live theme minimum. Construction is refused without
that environment; `Facet.new()` registers it for ordinary `app.controls` use.
A circle keeps its one authored width or height; a rung supplies the axis only
when neither was authored. Its existing icon-content minimum still applies.
`trailingIcon` is refused with `shape = "circle"`, whose primitive form carries one mark.

Generated primary labels and content-tinted semantic icons follow the Button's
role, appearance, selection and interaction state through native sheet rules.
This includes circle marks and primary text lifted above a theme's decoration.
Managed icon opacity follows the label's disabled decision; art suppression still
hides its fallback glyph. Package icons without a content tint keep their RGB.
Caller-provided children and Chip accessories retain their own roles; image
subtitles stay secondary, and package icons with explicit semantic tint roles
retain those tints. Palette/token edits and theme changes reach this generated
content. Editing only the root's individual StyleRule is not a general inheritance
mechanism for its separately styled content.


Plain text buttons accept `compactLabel`, a short alternate title or icon specification
with the same rules as `UI.Button.compactLabel`. Do not combine it with custom
content, row content, images or a busy indicator. Ordinary labels render directly
on the button; they do not allocate a separate text node.

A button takes required `onActivate(meta)` and optional `id`, `label`, custom
`children`, `enabled`, `busy`, `role`, `surface`, `selected`, `width`, `height`,
`shortcut`, `repeatDelay`, `repeatInterval`, `dialogAction`, `pop`, `help`,
`icon`, `shape`, `textSize`, `padding`, `gap`, `align`, `shrinkWeight`,
`focusable`, `disclose`, `row`, and the ordinary placement, visibility and
lifecycle props (`hidden`, `anchor`, `alignH`, `alignV`, `margin`, `offsetX`,
`offsetY`, `zIndex`, `layoutPriority`, `traversalPriority`, `gridSpan`,
`onAppear`, `onDisappear`, `onPointerDown`, `onPointerUp`, `onPointerCancel`,
`onPointerMove`). Enabled and busy accept booleans or readable booleans. Busy
displays the existing themed progress spinner and rejects activation until the
caller clears it.
Use `surface = "plain"` for custom content or an activation cover that should
preserve the content underneath; the button retains normal focus and activation.
`row = { description?, icon?, value? }` gives the button the shared settings-row
content; it cannot be combined with `children` or `image`.

Set `image` (asset string or readable string) for an image button with a persistent
caption from `label` and optional `subtitle` (string/readable). Optional
`imageFraming` forwards the [Image framing](#image) record/readable to the artwork;
it requires `image`. `imageAspectRatio`
is a positive width/height ratio, default `16/9`. `image` and custom `children`
are alternative forms. Supply a nonempty semantic label. The image form fills
its offered width by default; use a responsive grid or a dimension in `width`.
Captions wrap at the offered width instead of occupying the image's border.

The entire card is one activation/focus target. Keyboard/gamepad focus and mouse
hover highlight its image using the theme's accent focus ring. Only the image
lifts by 5% through the shared interruptible object spring, inside space reserved
during layout; captions and neighboring
controls do not move. Reduced motion keeps the ring and removes lift. Touch has
no hover dependency; busy/disabled, repeat, shortcut and dialog semantics remain
the same as other Buttons. The plain outer surface avoids duplicating a theme's
ornamental control border around the artwork and captions. This is a portable
focus treatment. Native TV specular materials, pointer-driven perspective effects
and background blur are not provided by this form.

```lua
local app = Facet.new()
local UI = app.controls
app.mount(function()
    return UI.Button("TrailCar")({
        label = "Trail car", subtitle = "Ready for mountain races",
        image = carThumbnail, imageAspectRatio = 16 / 9,
        onActivate = function() chooseCar("trail") end,
    })
end)
```

Repeat is opt-in by declaring a delay or interval. Defaults are 0.4 seconds before
repeating and 0.1 seconds between repeats. Keyboard/gamepad activation occurs on
press; a pointer tap activates on release, while a held pointer starts repeating
after the delay. Release after a repeat does not add an extra activation. A slow
frame emits at most one current repeat. Release, pointer exit, cancellation,
focus loss, lost input ownership, disabling, busy state, and disposal stop the hold.

`pop = true` is an opt-in release overshoot: an activate seeds velocity into a
`reward` spring resting on the button's paint-only `scale`, which kicks past 1
and returns rather than easing to a target — the same acknowledgement
`RadialMenu`'s commit uses, on the plain button surface. It changes nothing the
solver sees and costs nothing at rest (the spring detaches once it settles).
**It fires on the initial press only, never on a repeating button's later
pulses**: a pointer held down on a `pop` + `repeatInterval` button pops once on
the first activation and then holds still through every pulse that follows,
because a repeat interval is typically well under the spring's settle time and
an unconditional re-kick would stack. Keyboard/gamepad activation still pops
exactly once, on the press that starts the hold. Under reduced motion
`setVelocity` is a no-op, so the scale stays exactly 1.

`shortcut = { keyCode = "F6", modifiers = { shift = true } }` uses the existing
semantic action system. Only documented modifier bindings are supported. Hidden,
disabled, busy, inactive, or covered controls do not execute. Shortcuts are scoped
to their presented surface, below higher-priority gameplay contexts. During
native text editing all control shortcuts yield. Escape remains engine-owned;
Tab retains traversal. Roblox-reserved keys cannot be promised to intercept.

`dialogAction = "default"` binds Return; `"cancel"` binds ButtonB. These actions
use the same activation and ownership rules, including yielding Enter to an
active multiline editor. The first eligible declared control wins duplicate
shortcut/default keys in document order. A focused repeat button's normal
activation takes precedence over a default. Overlapping bindings on one button
produce one activation. Dismissing the surface releases its key contexts.

### `UI.SplitButton`

Construction refuses a missing or ambiguous environment when adaptation or native editing requires it; pass `env` explicitly when the application serves multiple surfaces.

`UI.SplitButton { … }` -> the control's node. `ref` receives `{ api, dump }`;
SplitButton publishes no verbs, and `dump()` reports the resolved `form` beside
the menu's own dump.

A primary action with a menu of alternatives, in the form the surface's primary
interaction class wants. Required fields are `label`, `onActivate`, and Menu
`items`. Optional fields are `id`, `enabled`, `busy`, `shortcut`, `env`, and
`menuLabel` (default “More options”).

- **Pointer or gamepad:** one plate, two focus stops — the primary Button and a
  chevron segment joined edge to edge across a hairline. Opening the menu never
  runs the primary action. `busy` and `shortcut` ride the primary Button.
- **Touch:** one button with a trailing `chevron.down` hint, so the long-press
  menu is discoverable: one hit target and one focus stop, where a tap runs the
  primary action and a long press opens the menu (the right-click, context-key
  and gamepad triggers stay live for a hybrid). There is no second chevron
  cell. A control whose alternatives must be chosen from on a phone is a
  `Picker` beside a `Button`.

The two forms are `UI.When` branches over the live interaction class; `dump()`
reports `form` (`split` or `single`) beside the menu's own dump. Both forms use
Menu's anchored surfaces, focus restoration, and dismissal policy.

### `UI.PopupButton`

Construction refuses a missing or ambiguous environment when adaptation or native editing requires it; pass `env` explicitly when the application serves multiple surfaces.

**Deprecated:** `UI.PopupButton` is the popup half of what
[`UI.Picker`](#uipicker) owns as `style = "menu"` and
`style = "navigationLink"`. It still builds, on the same engine the Picker's menu
styles run on, with the trigger every popup draws: the value and the up/down
chevron inside one button. Reach for `UI.Picker`.

`UI.PopupButton { … }` -> the control's node. `ref` receives `{ api, dump }`.

| Field | Contract and default |
|---|---|
| `id` | Stable control identity. |
| `options` | Option array or readable array. Options have unique path-safe `id`, `label`, optional `description`, semantic `icon`, and boolean/readable `enabled`. `{divider=true}` separates static groups. Icons are present for every option in a group or none. |
| `value` | Caller-owned writable cell holding one option id. Mutually exclusive with `selectedValues`. |
| `selectedValues` | Caller-owned writable cell of `{ [string]: boolean }`; true entries identify selected options. Each activation clones and updates the set immediately and keeps the panel open. Cancel dismisses; it does not roll back completed changes. |
| `query` | Optional caller-owned writable string cell. Filters supplied labels, case-insensitively, using native text entry and VirtualList for results. Query, focused result, and selected value remain separate. |
| `placeholder` | Summary when nothing is selected. |
| `enabled` | Boolean/readable boolean, default true. Disabling closes the popup without changing selection. |
| `required` | Single selection defaults to required: nil is accepted only when false. Multiple selection permits an empty set unless explicitly true. |
| `onChanging(proposed, current)` | Optional veto before a write. False or an exception rejects the proposal. |
| `onChange(selection)` | Runs once per actual accepted change, receiving an id or a fresh set according to the declared selection contract. |
| `presentation` | `"automatic"`, `"menu"`, `"inline"`, or `"sheet"`. |
| `selected`, `style`, `label`, `valueAlignment`, `sizing`, `textSize` | The picker shape this module also builds; see [`UI.Picker`](#uipicker). |
| `sizeClass`, `interactionClasses`, `env` | Optional adaptive facts. Automatic presentation reads missing facts from the application's environment. |

**Reaching for the Picker instead.** A single `value` is `UI.Picker` with
`{ value, label }` options and a `selected` cell (`style = "menu"`, or leave it
automatic). A searchable list is `style = "navigationLink"` with `query`. A
`selectedValues` set is `UI.Menu` with `checked` items, because a picker holds one
value. `api` carries `open()`, `close()`, `select(id)`, `isOpen`,
`presentation()` and `handleActivate(path, meta?)`.

### `UI.ComboBox`

`UI.ComboBox { … }` -> the control's node. `ref` receives `{ api, dump }`, where
`api = { submit(), cancel() }`.

Editable selection with two separate caller-owned writable string cells: `value`
for the committed value and `text` for the native editor's draft. Required
`options` follow PopupButton's option contract. `acceptCustom(text)` must return
true to accept custom text, or false plus an optional message to reject it.
Supplied labels commit their option ids; custom text commits as its own value.
Disabled supplied options cannot be bypassed by typing their labels.

Optional fields are `id`, `enabled`, `placeholder`, `env`, `onChange(value)`, and
`commitOnFocusLost` (false). Enter or `api.submit()` validates and commits.
Focus loss preserves the uncommitted draft unless explicitly configured to
commit. Cancel or `api.cancel()` restores the current committed label and closes
suggestions. Choosing a suggestion commits its id and updates the draft label.
Invalid custom values retain the draft, display an error, and leave `value`
unchanged. The suggestions use native search entry and virtualized results;
Tab moves between editing and suggestion navigation without taking editing arrows.

**The field and its opener share one row.** The control is a fill-width `VStack`
under its own id holding two children: a `Row` `HStack` carrying the `Editor`
text field and, framed at 56 px, the `Suggestions` opener; and a `Validation`
caption below it, hidden while there is no message. So the editor's mounted path
is `<id>/Row/Editor/Field` and the message's is `<id>/Validation`.

```lua
local app = Facet.new()
local UI = app.controls
local selected, draft = Facet.Compose.cell("alpine"), Facet.Compose.cell("")
local combo
app.mount(function()
    return UI.ComboBox("Choice")({
        value = selected, text = draft,
        options = { { id = "alpine", label = "Alpine" } },
        acceptCustom = function(text) return text == "Coast", "Choose a supported destination." end,
        ref = function(record) combo = record.api end,
    })
end)
```

`dump()` reports `{ schema, editing, value, text, validationError, open }`.

### `UI.Menu`

`UI.Menu { … }` -> the trigger's node, carrying the menu's input contribution.
`ref` receives `{ api, dump }`; the control's record also carries `presentation`,
a function returning the resolved idiom.

A menu combines actions, independently checked filters, exclusive selection
groups, submenus, and dividers. Pointer, touch, context keys, and the focus graph
all use the same anchored presentation.

Under the anchored (`menu`) presentation the panel is one card: the `raised`
panel owns the corner and the stroke, its rows are flat, a hairline separates
every adjacent pair, and a selected row's fill is the row itself — the theme's
`accent` under an `onAccent` label, the one pair every theme guarantees at
4.5:1. Under `sheet` the rows are unchanged.

Each floating row is at least the live hit floor (`targetSizes.hit`) tall, so
two rows' hit rects never overlap. `targetSizes.hit` is `targetSizes.minimum`,
except under a theme that authors `targetSizes.pointer`: while the input is
pointer-only (no touch, no gamepad) it is that dense pitch, the rows drop their
vertical inset, and they grow back the moment touch or a gamepad appears. A plain row's label leads, exactly as a row
with a badge or a shortcut does; its `icon` stays the compact form of its words.

It attaches to **any** node. `spec.trigger` is a node you authored; the
control returns that same node carrying an input contribution, so nothing is
wrapped and no layout moves. Pass `label` instead and the control builds a plain
Button trigger for you; `label` and `trigger` together are refused.
Opening presents the panel through the application's anchored-surface
machinery, so the placement, the edge flip, the along-edge
shift, the safe-area clamp and the follow-a-moving-source behaviour are the
[anchored surface](#anchored-surfaces)'s, and the focus scope, focus trap, focus
restore and tap-away catcher are the presenter's own. Every level materializes —
scale 0.96 → 1 with a fade in, growing from the corner it hangs at
([structural transitions](#structural-transitions)' `pivot` inference) and
dipping out on `dismiss` — with `plate = "fades"` acknowledged for you, since
the popover IS its panel. This is baked into the presentation call, not a
`spec.transition` field: a menu has no caller-facing transition override.

Spec: `{ id?, trigger: Node?, label: string?, items: { Item }, triggers: { string }?,
presentation: (("automatic" | "menu" | "sheet") | readable)?, sizeClass: (string | readable)?,
interactionClasses: (table | readable)?, env: Environment?, backLabel: string?,
edge: string?, align: string?, width: Dim?, maxHeight: number?,
onOpen: (() -> ())?, onClose: (() -> ())? }`. Both adaptive facts arrive by themselves
from the surface's environment when you pass neither, and an automatic menu with no
environment anywhere refuses to construct; `dump().factsFrom` says which
happened.

**`edge`/`align`** place the root panel against its trigger (default
`bottom`/`start`); submenus keep hanging trailing/start off their parent row.
**`width`** is any dimension table for the floating panels, and **`maxHeight`**
bounds each floating panel in px **including its chrome**: the rows scroll inside
one list, and row ids, activation, submenu anchors and focus scroll-into-view keep
working one path level deeper (`…/Panel/List/Rows/Item:<id>`). A floating panel is
always bounded — by `maxHeight` when given, and never taller than the screen less
its safe insets — so its rows always sit at that path; a long list scrolls instead
of running off screen. (An unbounded panel's fade group outgrew the engine's
CanvasGroup budget, which blurs the text of every CanvasGroup on screen.) A sheet's
rows sit at `…/Panel/Item:<id>` unless `maxHeight` bounds it. A level whose `selected` group
holds one of its rows opens with focus on that row, centred in its scrolled list
(a `checked` toggle does not move the landing).

**`backLabel`** labels the sheet's Back row and defaults to "Back". Supply a
localized label when appropriate. Long labels use the shared compact-label
fallback rather than clipping.

**`presentation`** accepts a string or readable `automatic`, `menu`, or `sheet`.
Changing it or the adaptive environment re-presents the menu at its current
open depth. Sheet submenus slide forward on entry and backward on Back, through
the shared motion authority; reduced motion removes the travel. Invalid static values fail construction; invalid reactive values
report through `core.lastError()` and retain the last valid presentation.

An **`Item`** is one of these shapes:

| Shape | Fields | What it is |
|---|---|---|
| action | `{ id, label, icon?, role?, enabled?, onSelect }` | runs `onSelect` and closes the menu |

Every row shape above also takes the shared row words `Picker.Option` uses:
`badge` (a string, number or readable — the count seal), `avatar` (an Avatar
spec, decoration only), `sectionTitle` (a caption heading before the row, never a
stop) and **`shortcutLabel`** (display text such as `"Ctrl+B"` — it binds
nothing; bind the key where the action lives).
| submenu | `{ id, label, icon?, role?, enabled?, children }` | opens a nested level; draws a trailing chevron |
| checked | `{ id, label, checked (writable boolean cell), onChange?, dismiss?, enabled?, description?, icon? }` | toggles independent caller-owned state; stays open by default |
| selection | `{ id, label, selected (writable cell), value, onChange?, dismiss?, enabled?, description?, icon? }` | shares one selected-value cell across exclusive choices; stays open by default |
| divider | `{ divider = true }` | a rule between two groups; carries nothing else |

Declaring **both** `onSelect` and `children` is an authoring error, not a
precedence rule. Items require one action, submenu, checked binding, or selected binding.
State bindings cannot be combined with `onSelect`; use `onChange(value)`.
`dismiss=true` closes the surface before the callback, while `dismiss=false` keeps an action open.
State marks have their own theme slots, distinct from ordinary icons.
Disabled state changes leave caller-owned selections intact. If an open submenu’s parent becomes disabled, that submenu closes back to its available parent level. Disabling the trigger closes the menu.
 `role` is `"default"` (the
fallback) or `"destructive"`; `icon` is a semantic icon **name**, never an asset
id. `enabled` may be a readable boolean — and note that **a menu whose every
item is disabled still opens**, because a trigger that silently does nothing
cannot be told apart from a dead button.

**Triggers.** `triggers` names which gestures open it, defaulting to all five:
`"activate"` (tap / Return / ButtonA), `"secondary"` (a pointer right-click),
`"longPress"` (touch, read off the normalized gesture layer), `"keyboard"` (the
context key, or Shift+F10) and `"gamepad"` (ButtonY). Dropping `"activate"`
without declaring both `"keyboard"` and `"gamepad"` is refused: it would leave
the menu unreachable on two input classes. Keyboard/gamepad context commands
apply only while that menu’s trigger has focus, so several menus can share the
same chord. For right-click-only pointer activation with accessible context
commands, use `{ "secondary", "keyboard", "gamepad" }`.

**Submenus** nest with no structural cap. Past one level `api.diagnostics()`
reports the depth as advice rather than refusing; it also
reports a group of more than about five items and a destructive item that is not
last. Under the `menu` presentation each level is its own panel anchored to its
parent **row** (preferred edge trailing, flipping to leading at the screen edge).
Under `sheet` — the automatic touch/gamepad idiom, and the automatic idiom
at any `sizeClass == "compact"` surface regardless of live input — a submenu
replaces the sheet's contents and grows a Back row. Roomy pointer-primary
surfaces keep side-by-side `menu` expansion. Cancel / gamepad B closes **one** level, a tap outside
closes **all** of them, and Right/Left enter and leave a submenu in document
order — and backing out of a level restores focus to the row that led into
it, not the level's first row.

Icons are a **per-group all-or-nothing** lint — provide icons for every item in
a group, or for none of them; a divider starts a new group. The row
recipe, the row-height tokens and the presentation rule are shared with
`UI.PopupButton` and `UI.RowActions`' action menu, so a theme that retunes the
control-size ladder retunes all three.

`ref` hands back `api =
{ open() -> boolean, close(), closeLevel(), toggle(), select(id) -> boolean,
handleActivate(path, meta?) -> boolean, diagnostics() -> { string },
isOpen (a readable), openPath (a readable), presentation() }`. `dump()` returns
`{ schema, id, open, presentation, openPath, depth, surfaces, triggers, items,
diagnostics, text }`.

```lua
local app = Facet.new()
local UI = app.controls
local avatarMenu
app.mount(function()
    return UI.Screen("S")({
        UI.Menu("AvatarMenu")({
            trigger = UI.Button("More")({ label = "More", shape = "circle", icon = "more" }),
            items = {
                { id = "accessory", label = "Accessory Adjustment", icon = "edit",
                  onSelect = function() openAccessories() end },
                { id = "layering", label = "Layering", icon = "edit", children = {
                    { id = "clothing", label = "Clothing Layering", onSelect = function() end },
                    { id = "makeup", label = "Makeup Layering", onSelect = function() end },
                } },
                { divider = true },
                { id = "reset", label = "Reset Avatar", role = "destructive", onSelect = function() end },
            },
            ref = function(record) avatarMenu = record.api end,
        }),
    })
end)
```

### `UI.Callout`

`UI.Callout { … }` -> the anchor's node, carrying the callout's contribution.
`ref` receives `{ api, dump }`.

This is the **app-pushed coach mark**: a styled plate with an arrow tail that the
application raises from its own rules, pointing at the control it is about. It
is a coach mark, not a tooltip.

**It is not `help`, and the difference is the whole construct.** `help` is a prop,
is PULLED by the player (a pointer dwell, a focus ring), and shows **nothing** on
touch. A Callout is PUSHED by the app, appears on **every** input class, and
retires permanently. Both plates carry the arrow tail — the stem says which
control the words are about and was never what told the two apart. Reach for
`help` to answer "what does this do"; reach for a Callout to say "there is
something here you have not found".

> The standing warning about coach marks, and it is the design constraint
> rather than a footnote — quoted verbatim, on one line, because
> `tests/callout.spec.luau` holds this document to it:
>
> *"Use tips sparingly… Don't use tips to guide people through your app, or for advertising and promotion purposes."*

Spec: `{ id?, anchor: Node, content: (Node | (() -> Node))?, title: Bound<string>?,
media: Media?, steps: { index, count }?, actions: { Action }?, closeButton: boolean?,
isPresented: Bound<boolean>?, dismissLabel: string?, edge: string?, align: string?,
tail: boolean?, priority: number?, seen: Bound<boolean>?, sessions: Bound<number>?,
afterSessions: number?, featureUsed: Bound<boolean>?, onRetire: (reason) -> (),
onShow: (() -> ())?, onHide: ((reason) -> ())? }`. Every `Bound` fact may be a
value, a readable or a `(use) -> T` function; functions are tracked like readables.

**The rich parts are optional.** `title` paints a heading; `media` is
`{ image, aspectRatio | height, scaleMode?, background? }` — exactly one of a
positive finite `aspectRatio` or `height` (px or a metric name), `scaleMode`
`fit | crop | stretch` (absent is the Image default), `background` a `tint` value
painted behind the image; `steps = { index, count }` shows "index of count"
(whole numbers, `1 <= index <= count`); `actions` holds one or two
`{ id, label, role?, enabled?, busy?, onActivate }` and **replaces** the bottom
dismiss; `closeButton = true` adds a top close and keeps the bottom dismiss.
`content` is optional only when title, media, steps or actions draw something; a
plate with nothing to show is refused. An action press retires **its own**
presentation with reason `"action"` — once, even when `onActivate` throws — and
never a newer one the callback rearmed and presented. With none of the new parts
the plate is the legacy content-then-dismiss plate, unchanged.

`anchor` is a node you authored; the control returns **that same node** carrying
an input contribution, so nothing is wrapped and no layout moves — the `UI.Menu`
shape. `content` is a **node**, not a string: the reference plate is styled
and holds more than one line, and a string-only tip could not express it.

`api = { eligible() -> boolean, present() -> boolean, dismiss(reason?),
invalidate(reason?), rearm(), state() -> "waiting" | "queued" | "showing" |
"retired", isShowing (a readable), retired (a readable) }`.

**`isPresented` drives the plate declaratively.** While it reads anything but
false the control presents an eligible callout itself, and a false read releases
a showing one. Leave it out and the callout presents itself as soon as it mounts
and is eligible; pass a readable to gate it on your own state.

**Eligibility** is the coach-mark construct's actual contribution, and every rule is a READ of
something the caller owns: `seen` (show once per player), `sessions` +
`afterSessions` (only after N sessions), `featureUsed` (only until the feature is
used). **Invalidation** is permanent: the tip dies when its feature is used, when
the player dismisses it, or on an explicit `invalidate()`, and a retired callout
cannot be presented again in that session.

**Persistence is the CALLER'S, never the framework's.** Facet has no save layer
and does not grow one here. The construct reads your readables and reports —
exactly once, through the **required** `onRetire(reason)` — that this tip should
never be shown again. Whether anything is written, and where, happens entirely
outside the framework. A callout declared without `onRetire` is an authoring
error, because a coach mark nobody can persist is one that comes back every
session.

**`rearm()` is the caller's word that the session is over**, not a way to argue
with a live retirement. Nothing inside
the construct can un-retire itself and no `present()` can reach past the latch;
only the app, which owns the record, may say the session it persisted for has
ended. **Clear the persisted facts first:** `seen` and `featureUsed` are read and
never written, so a rearm with either still true leaves the callout ineligible. A
showing or queued plate is released on the way out. Rearming in place also keeps
the anchor: rebuilding the construct rebuilds the node it points at, and an
anchor is a **path**, so anything already anchored to the old one is stranded.

**It never blocks.** It is presented, not modalled: no focus trap, no scrim, and
the tap-away catcher runs in the presenter's **non-consuming** mode, so a tap
outside the plate retires the coach mark *and* reaches whatever was underneath —
including the control the arrow points at. Presenting one does not move the focus
ring; one arrow press reaches the plate's own `Dismiss` row, and the ring goes
back afterwards.

**At most one is ever on screen.** A second request WAITS: the callout surface
is a driver over the shipped toast scheduler (`maxVisible = 1`), so priority
ordering, the queue cap and the read floor priority may never truncate are the
same rules toasts already follow. `presenter.callouts()` reports what is showing
and what is waiting.

**Motion.** The plate declares no enter or exit transition: it appears and
leaves at once, so reduced motion changes nothing.

```lua
local app = Facet.new()
local UI = app.controls
local tip
app.mount(function()
    return UI.Screen("S")({
        UI.Callout("PostAvatar")({
            anchor = UI.Button("Plus")({ label = "+", shape = "circle", icon = "add" }),
            content = UI.VStack("Body")({
                gap = "xs",
                UI.Text("Title")({ text = "Post Avatars to Marketplace", textSize = "body" }),
                UI.Text("Sub")({ text = "Anyone can wear it", textSize = "caption", role = "secondary" }),
            }),
            -- the CALLER'S state, read and never written
            seen = save.postAvatarTipSeen,
            featureUsed = save.hasPostedAnAvatar,
            onRetire = function(reason)
                save.postAvatarTipSeen:set(true)   -- ...and the caller persists it
                analytics.tipRetired("PostAvatar", reason)
            end,
            ref = function(record) tip = record.api end,
        }),
    })
end)
```

### `UI.Popover`

`UI.Popover { … }` -> the trigger's node carrying the popover's contribution, or
an empty node for a `source` popover. `ref` receives `{ api, dump }`.

Content presented against a **trigger** or a **source**: an anchored panel, or a
sheet on a compact touch screen. Use it for a short task or details that belong
to one control. For a decision that blocks the screen, use `UI.Dialog`; for a
tip the application pushes once, use `UI.Callout`; for a list of verbs, use
`UI.Menu`. Spec:

```
{
  id?,
  isPresented: Bound<boolean>,          -- required: the CALLER'S accepted fact
  onPresentedChange: ((next) -> ())?,   -- a proposal; required for any interactive open/close
  onDismiss: ((reason) -> ())?,         -- an actual closure, once, after cleanup
  trigger: Node?,                       -- exactly one of trigger or source
  source: { path: string } | { rect: { x, y, w, h } }?,
  content: () -> Node,                  -- each presentation builds and owns its own
  edge?, align?, gap?, crossOffset?,    -- the anchored placement
  tail: boolean?,                       -- never drawn for a rect source
  maxWidth: number?, maxHeight: number?,-- px, the whole panel INCLUDING chrome
  compact: ("sheet" | "popover")?,      -- default "sheet": a compact touch screen gets a sheet
  env?,
}
```

**The fact is yours.** The popover renders `isPresented` and never writes it.
A trigger press, Cancel (ButtonB), a tap outside, and a sheet's Close or drag
each call `onPresentedChange(next)`; the surface changes only when your fact
does. Refuse by not changing it: the same surface, focus and content stay
exactly where they were, and a refused sheet drag springs back to its detent.
Without `onPresentedChange` nothing interactive opens or closes it — your fact
still does. The keyboard has no Cancel key (Escape belongs to the engine's own
menu), so give keyboard players a close action in the content or a click outside.

**`onDismiss(reason)`** reports each actual closure once, after its cleanup:
`"cancel"` (Cancel, a sheet's Close or drag, your own false, owner disposal),
`"outside"` (a tap outside — an open popover is modal, so a press on its own
trigger is one), `"anchorLost"`. `"trigger"` is the reason a trigger press
proposes with.

**A path source is followed through its mounted node.** When that node is
removed or replaced, the presentation is released at once, `false` is proposed
and `"anchorLost"` reported; your fact is left alone, and a still-true fact never
reopens against a replacement until you start a new false → true request. A node
that has not mounted yet is not a loss (one warning says it is awaited).
`source.path` names a node on the same screen as the popover, from that screen's
root, even when the screen is embedded in another (a gallery tab page). A `rect` source is copied once and never draws a tail.

**The panel** is one raised plate with one scrolling body; `maxWidth` and
`maxHeight` cap the whole plate, chrome included, inside the live safe box, and
an overflowing body's scroll bar is paid on the panel's own width. **A live class
or size change** moves between the panel and the sheet silently — no proposal, no
`onDismiss` — with one content owner at a time and the focused content path
restored.

**Motion.** The anchored panel enters with a short fade and a slight scale; the
sheet route moves as `UI.Sheet` does. Under reduced motion both arrive and leave
at once.

`api = { isPresented, route, propose(next) -> accepted }` (the first two are
readables). `dump()` reports `{ schema = "facet-popover-dump/1", id, presented,
route, wanted, anchorLost, source }`.

```lua
local app = Facet.new()
local UI = app.controls
local open = Facet.Compose.cell(false)
app.mount(function()
    return UI.Screen("S")({
        UI.Popover("Info")({
            isPresented = open,
            onPresentedChange = function(next) open:set(next) end,
            trigger = UI.Button("InfoButton")({ label = "About scoring", icon = "info" }),
            maxWidth = 320,
            content = function()
                return UI.Text("Body")({ text = "Laps score by position and clean overtakes." })
            end,
        }),
    })
end)
```

### `UI.Dialog`

`UI.Dialog { … }` -> an empty anchor node; the panel is a modal surface. `ref`
receives `{ api, dump }`.

A modal panel whose presentation the caller owns: an optional `hero`, a `title`
beside the close button, one scrolling `content` body, an optional `actionLabel`
and a pinned group of `actions`. Modal `UI.Alert` is unchanged; reach for Dialog
when the decision needs more than a sentence, a picture or its own body.

`env?` names the environment whose viewport, safe insets, keyboard occlusion and
text size size the panel; omitted, the control reads the environment published
on its core, and construction without either is refused.

```
{
  id?,
  isPresented: Bound<boolean>,          -- required: the CALLER'S accepted fact
  onPresentedChange: ((next) -> ())?,   -- a proposal; required while closeButton is true
  onDismiss: ((reason) -> ())?,         -- "close" | "outside" | "cancel" | "action", once
  title: Bound<string>?,
  content: (() -> Node)?,               -- the one body, scrolled between pinned regions
  hero: { image, aspectRatio | height, scaleMode?, background? }?,
  actionLabel: Bound<string>?,          -- wraps above the actions
  actions: { { id, label, role?, enabled?, busy?, onActivate } }?,
  actionLayout: ("automatic" | "row" | "stacked")?,
  closeButton: boolean?,                -- default true
  width: ("automatic" | "narrow" | "wide")?,
  contentSelectable: boolean?,          -- default true
  env?,
}
```

**The fact is yours.** The dialog renders `isPresented` and never writes it. The
close button, Cancel (ButtonB) and a tap on the backdrop each call
`onPresentedChange(false)`; refuse by not changing your fact and the same
surface keeps its focus. Without a callback, set `closeButton = false`: the
backdrop and Cancel then only swallow. **Actions never close by themselves** —
each runs its `onActivate`, and a false you accept during that callback reports
`"action"`. Cancel goes first to an eligible `role = "cancel"` action (enabled
and not busy); the one `role = "default"` action answers Return. A disabled or
busy action cannot fire by any route. `onDismiss` reports each actual closure
once, after cleanup; your own false and owner disposal report `"cancel"`.

**Composition.** Any one of title, content, hero, actionLabel or actions is
enough; a static dialog with none of them is refused, and the close is not
content. A bound title or label may start empty and fill in later in the same
presentation. `hero` is the shared construction-only media shape (exactly one
of `aspectRatio` or `height`). Action ids are unique and at most one action is
`default`, one `cancel`. `actionLayout = "automatic"` rows two short actions and
stacks three, a distant screen, large text, or labels that do not fit side by
side; an explicit `"row"` that cannot show every full label falls to the same
safe stack. When the pinned regions and a one-line body do not fit the room,
every region scrolls as one column (`Panel/Room/Column`), so no action is out of
reach; `UI.Sheet` does the same.

**Size.** `width` is a theme ceiling — `automatic` is `controls.alert.maxWidth`,
`narrow` `controls.popup.panelWidth`, `wide` `controls.dialog.wideWidth` —
bounded by the safe room. The height is the live room: the viewport less the
platform insets, the outer margin and any keyboard occlusion, and the panel is
centred above the keyboard. Header, hero, action label and actions are pinned;
the body gives height back and scrolls. When the pinned parts alone exceed the
room (a very long title, a tall hero and stacked actions under a keyboard) they
still overrun the panel: keep pinned copy short.

**A plain body that overflows is one pad stop.** With `contentSelectable`
(default true) the body host joins the focus order while it overflows; with the
ring on it, Up and Down scroll it and hand the ring on at either end. Its
interactive children keep their own stops. `false` opts out.

**Motion.** The dialog declares no enter or exit transition: the panel appears
and leaves on the frame your fact changes, so reduced motion changes nothing.

`dump()` reports `{ schema = "facet-dialog-dump/1", id, presented, wanted,
actionCount, width, closeButton }`.

```lua
local app = Facet.new()
local UI = app.controls
local open = Facet.Compose.cell(false)
app.mount(function()
    return UI.Screen("S")({
        UI.Button("Quit")({ label = "Leave race", onActivate = function() open:set(true) end }),
        UI.Dialog("Leave")({
            isPresented = open,
            onPresentedChange = function(next) open:set(next) end,
            title = "Leave the race?",
            content = function()
                return UI.Text("Body")({ text = "Your lap will not count.", width = UI.fill() })
            end,
            actions = {
                { id = "Stay", label = "Stay", role = "cancel", onActivate = function() open:set(false) end },
                { id = "Leave", label = "Leave", role = "destructive", onActivate = leaveRace },
            },
        }),
    })
end)
```

### `UI.Notice`

`UI.Notice { … }` -> the notice's node. `ref` receives `{ api, dump }`.

An informational message in the page — never a modal. Spec: `{ id?, message:
Bound<string>, title: Bound<string>?, severity: ("info" | "success" | "warning" |
"error")?, appearance: ("standard" | "emphasis")?, placement: ("inline" |
"affixed")?, icon: (boolean | string)?, link: { label, onActivate }?, actions: {
Action }? (at most two), onDismiss: (() -> ())?, controlSize?, env? }`.

Use a Notice for a status the page must keep in view, such as a lost
connection or a form problem, until the state changes. For a short message
that confirms an action and goes away, use `UI.Snackbar`; for a decision the
player must make now, use `UI.Dialog` or `UI.Alert`. The notice has no enter or
exit motion: it appears and leaves when you mount and unmount it.

`severity` (default `info`) picks the status icon and paint; `emphasis` fills the
plate in the severity's colour with its readable partner lettering. `icon =
false` drops only the artwork; a string names an icon or image source. The
`link` is a link-appearance Button, and the actions are ordinary Buttons whose
roles only **paint** — a page is not a modal, so there is no default or cancel
key. `onDismiss` draws the close button and reports the press; unmount the notice
yourself. The link and actions sit beside the copy when the measured width holds
both and move below it when it does not. The notice never takes focus; its
controls join the page's own focus order.

**`placement = "affixed"`** is a page-local top recipe, not an automatic host:
put the notice in your safe root's fill `ZStack`, outside the body scroller. It
fills the width, hugs its height, sits at the top and publishes its measured
window rect through `presenter.reserveHud` under a key unique to its mount.
Content that should move out of its way reads the reservations explicitly:

```lua
local UI, C = app.controls, Facet.Compose
local bounds = C.cell({ x = 0, y = 0, w = 0, h = 0 })
local function reserved(use)
    return Facet.layout.hudInsets({ bounds = use(bounds), reservations = use(app.presenter.hudReservations) })
end
app.mount(function()
    return UI.Screen("Page")({ UI.ZStack("Safe")({ width = UI.fill(), height = UI.fill(),
        UI.ZStack("Content")({ width = UI.fill(), height = UI.fill(), padding = reserved,
            UI.ScrollView("Body")({ width = UI.fill(), height = UI.fill(), UI.Text({ text = "Page content" }) }) }),
        UI.Notice("Connection")({ placement = "affixed", severity = "warning", message = "Connection interrupted" }),
    }) })
end, { onGeometry = function(rectOf)
    local r, old = rectOf("/Page/Safe"), bounds:peek()
    if r and (r.x ~= old.x or r.y ~= old.y or r.w ~= old.w or r.h ~= old.h) then bounds:set(table.clone(r)) end
end })
```

The recipe assumes an untransformed, non-scrolling safe root whose `rectOf`
agrees with window coordinates. Several notices stack in an ordinary top
`VStack` in the same ZStack; each reserves its own rect and `hudInsets` takes the
deepest edge. A notice that paints nothing reserves nothing, and its reservation
goes with its owner.

`dump()` reports `{ schema = "facet-notice-dump/1", id, severity, appearance,
placement, accessories = "beside" | "below", actionCount, closable }`.

### `UI.Card`

`UI.Card { … }` -> the card's node. `ref` receives `{ api, dump }`.

Artwork, a title and an optional caption, with a primary action and a More menu
that reveal on engagement. Spec: `{ id?, image: Bound<string>, title:
Bound<string>, caption: Bound<string>?, imageAspectRatio: number?, imageFraming?,
onActivate: (() -> ())?, primaryAction: { label, icon?, onActivate, enabled?,
busy? }?, menu: { items, label? }?, reveal: ("automatic" | "always")?,
browseTarget: (() -> string?)?, enabled: Bound<boolean>?, width?, env? }`.

Use a Card for one item in a browsable collection, such as a game, a track or a
kart, where the picture helps the player choose. For rows of text, use a
`UI.VirtualList` or `UI.Table`; for an informational panel with no item behind
it, give a stack `surface = "raised"`.

`image` and `title` are required and nonempty; `caption` may be empty. A late
empty or wrong-typed value keeps the last legal paint (a warning and a
`api.diagnostics()` line) until a legal one arrives. With `onActivate` the body
is an image `UI.Button` (title as its label, caption as its subtitle, the image
media keys as Button's); without it the body is plain artwork and text. The
primary action is an ordinary Button and `menu` is a `UI.Menu` behind a More
button (`menu.label` is its name, default "More"). Body, primary and More are
**sibling** targets under a noninteractive card, so a press runs exactly one of
them. Structure and callbacks are construction-time; the bound values stay live.
`enabled = false` is inherited by all three.

**Reveal.** `always` keeps the action row in the card's layout. `automatic`
(the default) shows it at rest whenever the session has touch (a finger has no
hover, so hybrid devices keep them too) and otherwise while the card is
**engaged**: the pointer within it, a painted focus ring within it, a press held
on one of its buttons, its menu open, its actions entered, or the
`browseTarget` path focused with a painted ring. A card with neither a body action nor a
`browseTarget` has no stop of its own, so it shows its actions at rest. The card
is one hosted envelope: the body and, directly below it, the action plate. The
plate is always laid out and only hidden at rest, so the card's box never
changes, siblings never move, and a pointer travelling from the body to Play or
More never leaves the envelope it is observed on. `api.revealExtent.body` is
that envelope's **measured** height, before anything reveals. When engagement
ends the plate leaves paint, focus and the tap path at once; entry fades in on
the container class (reduced motion: none).

**Lift.** While engaged, on any input, the card rises to 1.04x on the control
spring and wears the theme's raised shadow (a card with a body action; one
with none has no plate to cast it); it lands when engagement ends. The
scale is paint only: the card's box never changes, so the gutters around it must
hold what a lifted card paints past its box. Size them with
`Facet.layout.transformFootprint(w, h, 1.04, 0)`: a gutter at least the
footprint's growth holds two neighbours lifted toward each other (the Cards
scenario does this for both VirtualGrid gutters), and a `UI.VirtualGrid` keeps
half of each gutter at its outer edges, so a lifted card in a corner cell and
its ring stay inside the grid's clip. Under reduced motion the card
keeps only the shadow. At ten-foot distance the focus visual's own
`tenFootFocusScale` is the lift, so the card does not scale a second time. In a `UI.VirtualGrid`, hand the card's `api.scale`
to the cell's `ctx.stopScale` so the cell's focus stop, and its ring, grow with the card.

**In a `UI.VirtualGrid`.** The grid's cell Hit stays the one browse stop. Point
`browseTarget` at it and keep each card's ref by item key (released by the
cell's owner). The grid's `onActivate` runs the card's body callback when it has
one, and otherwise enters its actions:

```lua
local refs, gridRef = {}, nil
UI.VirtualGrid("Games")({ items = games, key = function(item) return item.id end, columns = 3, gap = "m", rowGap = "m", viewportExtent = "auto",
    itemExtent = 320, -- holds revealExtent.body; the Cards scenario sizes each line from its tallest card
    ref = function(r) gridRef = r end,
    onActivate = function(item) local r = refs[item.id]; if r then r.api.enterActions() end end,
    cell = function(item, ctx)
        local key = item.id
        return UI.Card("Card")({ image = item.art, title = function(use) return ctx.current(use).title end,
            browseTarget = function() local cell = gridRef and gridRef.api.pathOf(key); return cell and cell .. "/Hit" end,
            primaryAction = { label = "Play", onActivate = function() play(key) end },
            menu = { items = { { id = "hide", label = "Not interested", onSelect = function() hide(key) end } } },
            ref = function(r)
                refs[key] = r
                ctx.scope.own(function() if refs[key] == r then refs[key] = nil end end)
            end })
    end })
```

`api.enterActions()` holds the reveal and traps focus in the actions, entering at
the first eligible one; it returns false for a disabled or unmounted card or one
with nothing eligible, and never runs the primary action. Arrows and Tab stay in
the actions; Cancel closes an open menu first, then leaves the actions and focus
returns to the browse stop (which keeps the card revealed). A tap elsewhere also
leaves them. Removing, recycling or replacing the card releases its trap.

`api` also carries `leaveActions()`, `engaged`, `revealed`, `scale` (the painted lift) and `revealExtent`
(readables; `revealExtent` is `{ body }`). `dump()` reports `{ schema = "facet-card-dump/1", id, reveal,
revealed, engaged, hovered, focusWithin, pressing, browsing, entered, menuOpen,
body = "button" | "informational", actions, extent, diagnostics }`.

### `UI.Pagination`

`UI.Pagination { … }` -> the pagination's node. `ref` receives `{ api, dump }`.

Page selection, independent of fetching. Spec: `{ id?, page: Bound<number>,
onChange: (nextPage) -> (), pageCount: Bound<number?>?, hasNext: Bound<boolean>?,
hasPrevious: Bound<boolean>?, siblingCount: number? (0–20, default 1),
boundaryCount: number? (0–20, default 1), showFirstLast: boolean? (default
false), form: ("numbers" | "arrows" | "label")? (default numbers), direction:
("ltr" | "rtl")? (default ltr), controlSize?, enabled: Bound<boolean>?, width?,
env? }`. The last five words are construction-only. `width` defaults to fill;
the window narrows to the width it is offered, so `hug` and `content` are
refused (a late one keeps the last legal width with a diagnostic).

`page` is yours: every press proposes one page through `onChange` and the row
repaints only when your value changes, so a refused proposal leaves it as it
was. Pages and counts are finite whole numbers; a malformed one is refused at
construction and, later, keeps the last legal value with a warning and an
`api.diagnostics()` line. A page outside the range is **shown** clamped (with a
diagnostic) and never written back.

A known `pageCount` decides availability and ignores `hasNext`/`hasPrevious`.
Without one the count is unknown: the two flags (default false) decide, the row
shows "Page n" between its arrows, and there is no Last. The label keeps the
width of the widest label the count can produce (four digits for an unknown
count), so the arrows beside it do not move as the page gains a digit. Each page
number is a small plate centred in a slot of the 44 px target floor. `0` pages shows an inert
"No pages"; `1` page shows it with no enabled navigation. `showFirstLast` adds
First (to page 1, when there is a previous page) and Last (to a known last page).

`form = "numbers"` shows the boundary pages, the current page and
`siblingCount` pages either side, with an ellipsis for a real gap (a gap of one
page shows that page) and a fixed slot count near the edges. The work is bounded
by the two counts, never by `pageCount`. When the measured width cannot hold the
row, the farthest boundary page goes first, then the farthest neighbour (the
higher page on a tie); when not even the current page and its arrows fit, the
row shows "Page n of m". The row scrolls sideways rather than shrink a target.
`label` is always "Page n of m"; `arrows` shows only the arrows, so put your own
result context beside it. Ellipses and disabled arrows are not focus stops. Page
nodes are keyed by page number, and a focused page that leaves the window, or a
focused arrow that disables at an edge, hands focus to the current page. Every
page and arrow is at least the theme's minimum target wide, so no two targets
overlap. `direction = "rtl"` reverses the row and its arrows
once; Left and Right stay physical.

`dump()` reports `{ schema = "facet-pagination-dump/1", id, current, count,
hasPrevious, hasNext, form, direction, items, text, diagnostics }`, where
`items` is the mounted row (`"[5]"` marks the current page).

Use Pagination when results come in numbered pages that you fetch or build one
page at a time, such as a leaderboard or a server list. For one long list the
player scrolls, use `UI.VirtualList`; for swiping between whole screens, use
`UI.PageView`. The row has no motion of its own: a page change repaints it at
once.

```lua
local app = Facet.new()
local UI = app.controls
local page = Facet.Compose.cell(1)
app.mount(function()
    return UI.Pagination("Results")({
        page = page,
        pageCount = 12,
        onChange = function(nextPage) page:set(nextPage) end, -- write to accept; do nothing to refuse
    })
end)
```

### `UI.StepIndicator`

`UI.StepIndicator { … }` -> the indicator's node. `ref` receives `{ api, dump }`.

Where a workflow is — a list of step states, not a numeric Stepper or a Picker.
Spec: `{ id?, steps: Bound<{ Step }>, current: Bound<string?>, onSelect: ((id) ->
())?, sizing: ("fill" | "hug")? (default fill), listLabel: string? (default
"Steps"), controlSize?, enabled: Bound<boolean>?, env? }`, where `Step = { id,
label, description?, state: ("complete" | "current" | "upcoming" | "error")?,
navigable: boolean? (default false), enabled: boolean? (default true) }`.

Step ids are nonempty and unique; labels are nonempty and may repeat.
`current` is the only authority on which step is current: it alone places the
underline and the "Step n of m — Label" summary. A step's `state` sets its
leading cue and its readable state word — a check for complete, an error mark
for error, the step's number in an outlined circle otherwise — so an errored
current step still shows its error. `state = "current"` is accepted only on the
step `current` names. A `current` that names no step is "No current step"; an
empty list is "No steps". A malformed snapshot is refused at construction and,
later, keeps the last legal one with a warning and an `api.diagnostics()` line.

A step is a Button only when it is `navigable`, `enabled` and `onSelect` is
given; every other step is plain content (with disabled paint when
`enabled = false`), never a focus stop. Activating a permitted step proposes
`onSelect(id)` once; nothing here writes `current`, so a refused step changes
nothing. When the measured width cannot hold the labels, the steps become the
summary and a Steps button that opens the whole list in a `UI.Popover`, where
permitted steps select through the same `onSelect`; the list closes when your
`current` changes, so a refused step leaves it open. An empty list has no Steps
button. The indicator always takes the width it is offered (that is what the fit
measures); `sizing` is how its steps share it — `fill` gives each the widest
label's share, `hug` each its own label. The number marker is a circle at every
text size.

`dump()` reports `{ schema = "facet-step-indicator-dump/1", id, current,
summary, form = "row" | "summary", listOpen, steps = { { id, state, button } },
diagnostics }`.

The underline is the shared selection indicator that Picker uses: when
`current` changes it moves to the new step on a spring, and reduced motion
places it at once. The list in summary form opens in a `UI.Popover` and moves
as that does.

```lua
local app = Facet.new()
local UI = app.controls
local current = Facet.Compose.cell("car")
app.mount(function()
    return UI.StepIndicator("Setup")({
        steps = {
            { id = "track", label = "Track", state = "complete", navigable = true },
            { id = "car", label = "Car", state = "current" },
            { id = "crew", label = "Crew" },
        },
        current = current,
        onSelect = function(id) current:set(id) end, -- only navigable steps propose
    })
end)
```

### `UI.Vote`

`UI.Vote { … }` -> the vote's node. `ref` receives `{ api, dump }`.

Up, down or none over your value — a thin wrapper over Picker's segmented,
icon-only strip. Spec: `{ id?, value: Bound<"up" | "down" | "none">, onChange:
((next) -> ())?, summary: Bound<string>?, readOnly: Bound<boolean>?,
controlSize?, enabled: Bound<boolean>?, env? }`.

`value` is yours: a press proposes `onChange(next)` once and the strip repaints
only when your value changes, so a refused vote never flashes and a swap from up
to down is one change. Pressing the chosen side proposes `"none"`. The icons are
`vote.up` / `vote.down` with the names "Upvote" / "Downvote". `summary` is your
own aggregate text ("99% liked"), one line, with the whole value disclosed;
Vote counts nothing. `onChange` is required unless `readOnly` is true.

`readOnly = true` is informational, not disabled: the same icons with your
choice plated, no press, no focus stop. A later `readOnly = false` without an
`onChange` is refused and the vote stays read-only (a warning and an
`api.diagnostics()` line). `enabled = false` is the ordinary disabled strip. A
late value outside the three keeps the last legal one. For a score out of five
use `UI.Rating`; for a number the player adjusts, `UI.Stepper`.

**Input.** Each side of the interactive strip is a Picker segment. Pointer and
touch press a side; keyboard arrows and the D-pad move the focus ring between
the sides through the focus graph, and Return or ButtonA proposes the focused
side. **Motion.** The plate under the chosen side is the shared selection
indicator: it moves on a spring when your value changes, and reduced motion
places it at once.

```lua
local app = Facet.new()
local UI = app.controls
local vote = Facet.Compose.cell("none")
app.mount(function()
    return UI.Vote("TrackVote")({
        value = vote,
        onChange = function(next) vote:set(next) end, -- write to accept
        summary = "92% liked",
    })
end)
```

`dump()` reports `{ schema = "facet-vote-dump/1", id, value, readOnly, summary,
diagnostics }`.

### `UI.ColorPicker`

`UI.ColorPicker { … }` -> the picker's node. `ref` receives `{ api, dump }`.

A colour well that opens a panel, or the panel in place. Spec: `{ id?, value:
Bound<Color3?>, onChange: ((color) -> ())?, onCommit: ((color) -> ())?, alpha:
Bound<number>?, onAlphaChange: ((alpha) -> ())?, allowEmpty?, placeholder?,
modes: { string }?, swatches: Bound<{ Color3 | { color, label? } }>?,
onSaveSwatch: ((color) -> ())?, onRemoveSwatch: ((item) -> ())?, style:
("automatic" | "inline")?, draft?, isPresented: Bound<boolean>?,
onPresentedChange?, onDismiss: ((reason) -> ())?, enabled?, readOnly?, label?,
requiredMark?, hint?, errorText?, controlSize?, appearance?, corners?, env? }`.

Use a ColorPicker when the player chooses any colour, such as a kart's paint.
When the choice is a few named colours, use `UI.Picker` with those options; a
fixed palette also fits the `swatches` mode alone.

**The `Color` type is `any`.** The public types are checked without engine
datatypes, so a wrong value such as a string passes the type checker. The
control checks at run time instead: a value that is not a `Color3` (or `nil`
with `allowEmpty`) is an error at construction, and a later one warns, adds a
line to `api.diagnostics()` and keeps the last legal colour.

```lua
local app = Facet.new()
local UI = app.controls
local paint = Facet.Compose.cell(Color3.fromRGB(230, 57, 70))
app.mount(function()
    return UI.ColorPicker("KartPaint")({
        label = "Kart paint",
        value = paint,
        onChange = function(color) paint:set(color) end, -- each accepted change
        onCommit = function(color) print("save", color) end, -- once per gesture
    })
end)
```

`value` is yours: every accepted change proposes `onChange(color)` and the
picker repaints only from what you then hold, so a refused change never paints.
`onCommit(color)` ends a gesture (a drag's release, a slider's release, a stick
session, a swatch press, a field commit), so every change commits as it happens
and closing the panel any way (B, Escape, a tap outside, the sheet's Close)
keeps it. With `draft = true` nothing commits until **Apply**: the panel adds
Apply and Cancel, and every other way out proposes the colour the panel opened
with (a write of yours while it is open becomes that colour).
`onChange` is required unless `readOnly` is true; `nil` is a value only with
`allowEmpty = true` (the plate is crossed out and the text is `placeholder`).

`alpha` (0 to 1) with `onAlphaChange(alpha)` mounts an opacity slider and makes
the text `#RRGGBBAA`; a translucent swatch sits over a small checker. The well
labelled is a form row (label, swatch, value, chevron); bare it is the swatch
alone, and the value is its name. It opens an anchored panel, a sheet with a
Done button on a compact touch screen, and a centred sheet at ten feet; it owns
its open state unless you bind `isPresented` / `onPresentedChange` (a proposal,
as on `UI.Popover`). `onDismiss` reports `"activate"` (Done), `"apply"`,
`"cancel"`, `"outside"` or `"anchorLost"`. `style = "inline"` puts the panel in
the page.

**Touch.** A finger covers what is below it, so on a touch-primary screen the
preview and its readout lead the panel, above the plane, and while a finger
drags the plane or the hue or opacity strip a bubble of the colour under it
rides above the touch point (inside the panel's room; none for a pointer or a
pad). On a portrait phone the panel is a sheet whose technique scrolls, so the
readout and Apply stay on screen.

**Saved colours.** Facet keeps no colours of its own: `swatches` stays yours.
With `onSaveSwatch(color)` the Swatches tab ends with a "+" cell (named "Save
colour", a stop in the grid walk) that proposes the current colour; a colour
already in the list is not proposed again. With `onRemoveSwatch({ color, label?,
key })` the tab adds an Edit/Done toggle in the Chip's edit-mode pattern: while
editing, activating a swatch (or Delete, Backspace or the pad's remove binding
while it holds the ring) proposes its removal, with no second stop per swatch,
and the ring moves to the cell that takes its place. The Bricks tab has no
favourites (its list is the engine's).

`modes` are the panel's techniques, in tab order: `"swatches"` (your `swatches`,
or a generated grid of 48), `"spectrum"` (a saturation/brightness plane and a hue
slider), `"sliders"` (hue, saturation and brightness) and `"brick"` (the
engine's 128 BrickColors with their names). The default is the first three;
their tabs are a menu on a compact screen when they would not fit as a strip.
The anchored panel fits the larger room above or below the well, scrolling the
technique when it must, so it never covers the well.
Every tab keeps a preview and an RGB / HSV / Hex readout whose fields commit
typed values; switching the readout never changes the colour, and a grey keeps
the hue the player set. Hex accepts `#RGB`, `#RRGGBB` and, with `alpha`,
`#RRGGBBAA`; a refused hex stays in the field with its error and commits
nothing. The plane drags 1:1 and cancels (restoring its start) if pointer and
touch go away mid-drag; on a pad it takes the right stick while it has focus,
with a hint saying so (and sinks it, so a camera below does not turn), and the
D-pad keeps moving focus. There is no
eyedropper: Roblox has no screen-pixel read — put your own Button beside the
well and call `onChange` with what it sampled.

**Motion.** The well's panel opens through `UI.Popover` and moves as that does,
so reduced motion opens and closes it at once. A right-stick session on the
plane is driven by an informational timer: under reduced motion it keeps moving
the colour, in the clock's quantized steps, because that movement is the input.

`dump()` reports `{ schema = "facet-color_picker-dump/1", id, style, value,
alpha, hsv = { h, s, v }, text, name, modes, mode, format, draft, presented,
route, planePath, columns, swatchPaths, hexError, diagnostics, owned }`
(`owned`: what the control's owner holds, for leak checks).

### `UI.DateTimePicker`

`UI.DateTimePicker { … }` -> the picker's node. `ref` receives `{ api, dump }`.

A date field that opens a calendar, or the calendar in place. Spec: `{ id?,
selection: ("single" | "range")?, value: Bound<CivilDate?>?, onChange?,
onCommit?, range: Bound<CivilRange>?, onRangeChange?, onRangeCommit?, time?,
minuteStep?, hourCycle?, min: Bound<CivilDate?>?, max: Bound<CivilDate?>?,
isDateDisabled: ((date) -> boolean)?, weekStart?, locale?, clock: (() ->
CivilDate)?, referenceDate: Bound<CivilDate?>?, presets?, draft?, style:
("automatic" | "inline")?, format: ((value) -> string)?, placeholder?,
isPresented?, onPresentedChange?, onDismiss?, enabled?, readOnly?, label?,
requiredMark?, hint?, errorText?, controlSize?, appearance?, corners?, env? }`.

Use a DateTimePicker when the player chooses a calendar date, a date range or a
date with a time, such as an event day. For a count of days or minutes, use
`UI.Stepper` or `UI.NumberInput`; for a few fixed dates, use `UI.Picker`.

```lua
local app = Facet.new()
local UI = app.controls
local raceDay = Facet.Compose.cell({ year = 2026, month = 10, day = 3 })
app.mount(function()
    return UI.DateTimePicker("RaceDay")({
        label = "Race day",
        value = raceDay,
        onChange = function(date) raceDay:set(date) end, -- write to accept
        min = { year = 2026, month = 1, day = 1 },
    })
end)
```

Values are **civil dates** — `{ year, month, day }`, with `hour` and `minute`
when `time = true` — wall-clock facts in no time zone, so a date never moves a
day because of where it is shown (see [`civilDate`](#civildate) for turning an
instant into one at an offset you name). A single picker uses `value` /
`onChange` / `onCommit`; `selection = "range"` uses `range = { start?, finish?
}` / `onRangeChange` / `onRangeCommit`, and giving the other mode's keys is an
error. Both are yours: a pick proposes, and the calendar repaints only from
what you then hold. Every change commits as it happens — a pick (a single pick
without `time` also closes), a time step, a typed date — and closing the panel
any way (B, Escape, a tap outside, a sheet's drag or scrim) keeps it. In a range the
first pick sets `start`, the second sets `finish` (swapping if it is earlier),
and `onRangeCommit` fires only when both ends are set. A pointer or finger can
also grab a set range's start or end circle and drag it across days and panes
(each move proposes; crossing the other end swaps them; release commits; a
cancelled gesture proposes the range it began from). `draft = true` adds
Reset all, Cancel and Apply, and nothing commits until Apply (typed text
included); every other way out proposes the value the panel opened with (a
write of yours while it is open becomes that value).

"Today" (its ring, the presets, the month an empty picker opens on) comes from
`clock` — default the player's local wall clock — and `referenceDate` chooses the
month an empty picker opens on. `min` and `max` are inclusive; a day outside
them or refused by `isDateDisabled` stays in the grid, focusable, struck
through and inert. `weekStart` is 1 (Sunday) to 7; `locale` supplies `months`,
short `weekdays` (Sunday first), the numeric `order` ("mdy", "dmy", "ymd"),
`separator` and `hourCycle`. `minuteStep` (default 5) must divide 60.
`presets = { { id, label, range = function(today) } }` (range only) are chips:
one wholly outside the bounds is shown disabled, one that overlaps is clamped.

The closed form is field chrome: when a keyboard or pointer is live the value
is an editable field that takes the numeric form back (a text that is not a
date, or not an available one, stays with its error and commits nothing),
otherwise a button that opens the calendar; a calendar icon sits inside the
field at its trailing edge, and a refused entry (or `errorText`) borders the
field in the danger role. With a custom `format` the words are display only. It
opens a panel anchored to the field (below it and start-aligned, flipping only
without room), a sheet with Done on a compact touch screen, and a centred sheet
at ten feet. A single date shows one month; a range shows two consecutive
months when its width fits them. `draft`'s footer is Reset all as a leading
text link and Cancel and Apply (the accent) at the trailing edge. Its day
grid is one Tab stop (focus enters on the chosen day, else today); the arrows
walk the days — a row's end continues to the next day, Left and Right page the
month past either end, and Up and Down move a week across the shown months but
leave the grid (to the header above, the time fields or actions below) from the
first shown month's top row and the last shown month's bottom row — and a
neighbouring month's grey days can be tapped but are never a stop. L1/R1 and
Comma/Period page the month from any day (a hint names LB/RB while a pad is
live), the header's arrows and month and year menus reach every month
without a shoulder button, and paging stops at a month wholly outside `min` /
`max`. The month and year menus open on the shown one (marked, centred); the
year menu lists only years inside `min`/`max` (an open side spans 100 years
from the shown one), months outside the bounds are disabled, and a pick lands
on the nearest open month. A typed year has four digits, and on a 12-hour clock a typed hour from 1 to 12
needs AM or PM (0 and 13-23 read as 24-hour time); a typed range is two dates joined by its
own " – " (or " - "). `time` adds hour
and minute fields with steps on the `minuteStep` grid (AM/PM on a 12-hour
clock) and, on touch, a list of times at `minuteStep` that opens at the held
time (else now).

**Motion.** The calendar has no animation of its own: paging a month repaints
the grid at once. The field's panel opens through `UI.Popover` and moves as
that does, so reduced motion opens and closes it at once.

`dump()` reports `{ schema = "facet-date_time_picker-dump/1", id, selection,
style, value, range, text, typedError, month, dual, today, presented, route,
cellPaths, draft, weekStart, diagnostics }`.

### `UI.Snackbar`

`UI.Snackbar { … }` -> an empty anchor node; the row appears in the
application's bottom snackbar strip. `ref` receives `{ api, dump }`;
`dump()` reports `admitted`, `visible`, `queued` and the readable seconds.
`app.presentSnackbar(spec)` takes the same spec and returns an idempotent
zero-argument release function.

One short message at the bottom of the screen, shown one at a time. Use it to
confirm what the player just did ("Settings saved"), with at most one action
such as Undo. For a status that must stay in the page, use `UI.Notice`; for a
decision, use `UI.Dialog`.

```lua
local app = Facet.new()
local UI = app.controls
local shown = Facet.Compose.cell(false)
app.mount(function()
    return UI.VStack("Page")({
        UI.Button("Save")({ label = "Save", onActivate = function() shown:set(true) end }),
        UI.Snackbar("Saved")({
            isPresented = shown, -- yours: the row shows while it reads true
            message = "Settings saved",
            duration = 4,
            onPresentedChange = function(next) shown:set(next) end, -- accept a close or timeout
            action = { label = "Undo", onActivate = function() shown:set(false) end },
        }),
    })
end)
```

```
{
  id?,
  isPresented: Bound<boolean>,          -- required: the CALLER'S accepted fact
  message: Bound<string>,               -- required
  icon: string?,                        -- a semantic icon name or an image source
  action: { label, onActivate }?,       -- runs once; never closes by itself
  closeButton: boolean?,                -- default true
  onPresentedChange: ((next) -> ())?,   -- required while closeButton or duration is set
  onDismiss: ((reason) -> ())?,         -- "action" | "close" | "timeout" | "superseded" | "cancel"
  duration: number?,                    -- nil: persistent; else seconds of readable time
  priority: number?,                    -- default 0
}
```

The caller's fact is the only visibility authority. Close, Cancel on a focused
row, a timeout and a supersession each propose false through
`onPresentedChange(false)`; the row leaves only when the fact reads false, and a
refusal keeps the same row. A timeout asks once, at `max(duration, 2.5)` seconds
of readable time; a refusal makes the row persistent until you hide it. Readable
time pauses while the row is hovered or focused, while another exclusive
surface covers it, and never runs while queued. `onDismiss` reports each
accepted retirement once. `"close"` is the Close button; a false you write on
your own is `"cancel"`, as it is for `UI.Dialog` and `UI.Popover`. Owner teardown
and the release function release a row without asking and report `"cancel"`
once; application disposal releases every row without asking or reporting. The
teardown report runs while that owner is being disposed, so the callback must
not read or write state the same owner holds (Dialog and Popover behave alike).

One row shows; up to eight wait, by descending priority and then arrival. A
strictly higher priority may ask the showing row to leave once it has been
readable for 2.5 seconds, once per row; equal priority waits. Nine is the total,
counting rows still leaving: past it a new admission is refused (an error at
construction, or through the reactive error boundary on a later false-to-true)
and nothing already admitted moves. A caller that refuses every request can
starve the queue.

Message-only and icon-plus-message rows hug their copy up to the safe width; an
action or a close selects `controls.snackbar.maxWidth` (bounded by the safe
room), and the action moves below long copy. A keyboard or pad reaches the row
after the content (`focusChrome = "bottom"`), arrival never takes focus, and
Cancel on the row returns focus to the content even when refused. A visible row
reserves its bottom rectangle through `presenter.reserveHud` until it has slid
out; content that should avoid it reads `presenter.hudReservations` through
`Facet.layout.hudInsets`. The strip docks bottom-centre and paints above base
screens and toasts; a Callout, a passive Popover and help, disclosure and
reveal plates paint above it, and modals (Menu, modal Popover, Dialog, Sheet)
above all. A throwing `onPresentedChange`, `onDismiss` or action callback is
raised once the service is consistent again. Snackbars are a screen-application service: a SurfaceGui or Billboard
application refuses them, so present global notifications from a screen
application.

**Motion.** The row slides up to enter and down to leave. Under reduced motion
it arrives and leaves at once.

### `UI.Stepper`

`UI.Stepper { … }` -> the stepper's node. `ref` receives `{ api, dump }`, and
the record carries `blueprint`, `model` (the shared [`valueModel`](#valuemodel)),
`semanticText` (a Compose readable), `dump` and `dispose`.

A labelled value with discrete decrement/increment affordances, composed from
shipped primitives over the shared value model. The spec is
`{ id?, label?, value, min, max, step?, format?, enabled?, onChange? }`.

```lua
local app = Facet.new()
local UI = app.controls
local volume = Facet.Compose.cell(5)
app.mount(function()
    return UI.Stepper("Volume")({
        label = "Volume",
        value = volume,              -- a caller-owned writable number cell
        min = 0, max = 10, step = 1, -- step defaults to 1
        format = function(v) return `{v} dB` end,   -- optional
        enabled = true,                             -- boolean | readable boolean
        onChange = function(v) print(v) end,        -- optional
    })
end)
```

`value` must be a **writable cell you own** — the control never creates it,
because the value has to outlive the control. A read-only formula is rejected at
build rather than erroring on the first press.

Reach: pointer and touch press the two Buttons; keyboard (`,`/`.`) and gamepad
(L1/R1) reach the *same* arithmetic through the focus-gated `Adjust` verb, which is
bound **only while focus sits inside the control**, so a screen containing a Stepper
never shadows gameplay bumper keys. At a bound the affordance is `enabled = false` —
disabled, not silently inert. `enabled = false` on the control refuses every input
class, including Adjust.

`dump()` reports `{ schema, id, value, formatted, semanticText, min, max, step,
atMin, atMax, rootPath }`.

### `UI.ProgressView`

`UI.ProgressView { … }` -> the indicator's node. `ref` receives `{ api, dump }`,
and the record carries `blueprint`, `model`, `semanticText`, `phase`, `dump` and
`dispose`.

Use a ProgressView to show how far a task has gone (a bar or circle with a
value) or that work is running with no known end (a spinner). When the shape of
the content that is loading helps more than a value, use `UI.Skeleton`; for a
value the player sets, use `UI.Slider`.

```lua
local app = Facet.new()
local UI = app.controls
local progress = Facet.Compose.cell(0)
app.mount(function()
    return UI.VStack { padding = "m", gap = "s",
        UI.ProgressView {
            value = progress, -- a Compose cell, formula, getter or number
            min = 0, max = 100, showValue = true,
        },
        UI.ProgressView { presentation = "spinner" },
    }
end)
```

`UI.ProgressView` also accepts bound `endLabel`, the caller's trailing phrase
(e.g. "2 of 5"). It follows the indicator and optional formatted value, can
shrink, and requests disclosure. Indeterminate activity can carry this phrase too. With trailing
copy, bar segments reserve the theme's smallest spacing for each painted segment
and its intervening gap, so copy cannot reduce the indicator to zero width.
Bound `controlSize` names the indicator's local space-based ladder: spinner dots
compact/regular/large use space.xs/s/m (4/8/16 at Neutral); circular indicators use
space.m/l/xl (16/24/40). Absent or nil preserves the package's authored progress
metrics. Explicit regular derives its rung from spacing and may differ from those authored metrics. Every rendered dimension checks the rung before publication and recovers
on a legal value. A bar's rung is its track thickness: xsmall/compact use space.xs
(4 at Neutral), regular/large the theme's `controls.progress.trackHeight`; a bar takes
`height` or `controlSize`, not both. Circular views accept either an explicit diameter
or a rung, and `showValue` on a ring needs a `diameter` or `controlSize = "large"`
(the readout centres in the ring when it fits, else stacks under it); smaller rungs
refuse it. `dump.endLabel` and
`dump.controlSize` describe the requested source values.

The native host owns its Compose timeline, and the control's lifetime is the
Compose owner that built it: removing the control releases its animation. With
reduced motion, the indeterminate indicator rests at its initial phase.
A configured `trail` holds the previous value for its delay, then falls to the
current value. A higher value or reduced motion cancels the delayed fall and
settles the trail immediately.

Progress is determinate or indeterminate, linear or circular. `spec = { id?,
label?, value? (number | readable), min? = 0, max? = 1, format?, showValue?,
height?, segments?, trail?, diameter?, presentation? ("bar" | "circular" | "spinner"),
motionClock?, scope? }`. `motionClock` and `scope` are accepted and have no
effect: the timeline and the lifetime both belong to the Compose owner.

**Indeterminate is selected by `value = nil`**: a progress view with no value
has nothing determinate to show. There is deliberately no
second flag: an `indeterminate = true` sitting beside a `value = 0.4` is a
contradiction the framework would have to arbitrate, and the value already
carries the answer. Because `min`, `max`, `format` and `showValue` all describe a
value, declaring one *without* a value is an authoring error rather than a silent
no-op. The mode is construction-fixed: determinate and indeterminate are two
different controls, not two states of one.

`presentation` picks the shape, and **the shape and the mode are two independent
axes** — three shapes, two modes. Which cells are legal is a **capability
registry** in the control (`PRESENTATIONS`), and every refusal below is generated
from it rather than hand-written per shape, so a new shape joins by adding a row:

| `presentation` | indeterminate | determinate | `height` | `showValue` |
|---|---|---|---|---|
| `"bar"` (default) | ✅ | ✅ | ✅ the track's thickness | ✅ beside the track |
| `"circular"` | ✅ | ✅ | ❌ refused | ✅ with an explicit `diameter` |
| `"spinner"` | ✅ | ❌ refused | ❌ refused | ❌ refused |

`"bar"` is the track; indeterminate it grows a segment that sweeps to the far end
and folds back.

**`"circular"` is a ring, and it takes both modes** because both are the same
function of one scalar: determinate binds `arc(0, 360 × fraction)` — a fixed head
with a growing sweep, over a static capacity ring — and indeterminate binds
`arc(360 × phase, 90°)`, a fixed sweep whose *start angle* advances, which is how
it rotates without any rotation existing. The engine has no native radial
primitive — `UIGradient` has no angular mode, `ImageLabel` no fractional fill,
`EditableImage` no arc, and `GuiObject.Rotation` cannot move its pivot and is
documented incompatible with `ClipsDescendants` — so both forms are strokes on
the `UI.Path` primitive, drawn from
`Facet.pathShapes.arc`. `points` is `dirty = { "paint" }`, so a value change and
a frame of rotation are each **one prop write and zero re-solves**. It adds **no
blueprint prop and no decoration slot**: the arc's paint identity is the Path's
own `role` (`accent`, over a `secondary` capacity ring), and its size is the pair
of optional theme metrics `controls.progress.circularSize` /
`circularThickness` — compact by default, with `diameter` available for larger HUD gauges. Two consequences worth knowing before you
reach for one: **it cannot fade** (`Path2D` has no `Transparency` — wrap it in
your own `UI.ZStack({ canvasGroup = true })` if you need to), and a `UI.Path` that
is not *fully* inside every clip host above it **does not paint at all** rather
than being cropped (`tests/path.spec.luau`, RS-PATHCLIP) — a stroke has no
half-crop, so a ring in a scrolling list winks out at the edge instead of being
sliced.

**The circular ring covers two shapes that are usually separate.** Elsewhere a
circular progress view is *indeterminate* and a determinate ring is a gauge, a
control Facet does not otherwise ship. Facet offers both on this one control
because the arithmetic is identical.

`"spinner"` is a ring of five pulsing dots and is **indeterminate only** — a
determinate ring is `presentation = "circular"`, which the refusal names. It is
the fallback if the arc's per-frame paint ever proves too expensive on a device.
The dots
are fixed squares whose PULSE rides the `tint` channel rather than their size: a
loading indicator lives inside a vertical `ScrollView`, and a fraction of an
unbounded axis is not a size — so the ring animates for zero re-solves and can be
dropped into any container. They paint through the `spinner` decoration slot;
the bar paints through `barTrack` / `barFill`.

### What a theme can change about these two shapes

Both shapes are **theme-sized**, and every shipped package authors all three
numbers rather than inheriting them from its spacing scale (which is a gap
between elements and a poor ruler for the diameter of one):

| | classic-desktop | compact-pointer | fantasy-ornate | fantasy-parchment | glossy-mobile | glossy-touch | pixel-quest | scifi-hud |
|---|---|---|---|---|---|---|---|---|
| `circularSize` | 20 | 18 | 44 | 30 | 32 | 40 | 32 | 36 |
| `circularThickness` | 2 | 2 | 8 | 3 | 5 | 6 | 4 | 2 |
| `spinnerDotSize` | 6 | 5 | 12 | 9 | 10 | 12 | 8 | 6 |

A package that authors none of them still resolves — `snapshot.resolve` fills all
three from the theme's own `space` scale, and `circularThickness` is filled
*against* the resolved size, because a stroke wider than the box's inset paints
outside the rect the solver measured.

**The ring** is a stroked `Path2D`, and that fixes exactly what a package can and
cannot reach. A `Path2D`'s entire property surface is `Color3`, `Thickness`,
`Closed`, `Visible`, `ZIndex` — and `IsA("GuiObject")` is **false**:

| what a package might want | can it? | through what |
|---|---|---|
| the arc's colour | ✅ | `colors.accent` — the arc declares `role = "accent"` |
| the track's colour | ✅ | `contentSecondary` — the backing ring declares `role = "secondary"` |
| the diameter | ✅ | `controls.progress.circularSize` |
| the stroke weight | ✅ | `controls.progress.circularThickness` |
| the cap shape (round / butt / square ends) | ❌ | the engine has no cap or join property on `Path2D` at all |
| art along the arc | ❌ | a `Path2D` is not a `GuiObject`, so no stylesheet rule can select one, and the decoration materializer builds `ImageLabel`s, which cannot follow a partial arc. The nearest legal thing is a plate *behind* the ring, which is the caller's own `UI.Box`, not a theme slot |

**The dots** are ordinary `Box` leaves, so they take the whole `facet-slot-spinner`
own-paint ladder — the accent fill, the round corner and the theme's own hairline
— plus `spinnerDotSize`. What they refuse is art; see the `spinner` row in the
recipe table above for why.

**`height` is the bar's track thickness, and only the bar's.** No other shape has
a track, so `presentation = "spinner"` or `"circular"` with a `height` is
**refused** rather than silently reinterpreted as the dot's size or the ring's
diameter. The
dot is the theme metric `controls.progress.spinnerDotSize`, which is where a size
every spinner should agree on belongs. This is the same rule as the `min` / `max` /
`format` / `showValue` refusals above: a field whose meaning does not survive the
mode is an authoring error, never a silent reinterpretation.

**HUD meter options** reuse this control's theme roles and value model:

- `segments`: integer 1–100, determinate bars only. Equal capacity cells with
  fractional fills and theme `space.xs` gaps, inside one `barTrack` skin.
- `trail = { delay? = 0.3, duration? = 0.35 }`: determinate bars only. Damage
  leaves a `contentSecondary` trail before it drains;
  healing cancels the delay and snaps. Delay is nonnegative, duration positive,
  both finite seconds. Reduced motion snaps; a live environment policy change
  cancels pending motion. Removing the control stops it.
- `diameter`: positive pixels or a theme metric path, circular only. With an
  explicit diameter, the label sits above the gauge. `showValue = true` centers the formatted value when it fits
  at the player's preferred text size, otherwise places the full readout below
  the ring. Small default rings still reject `showValue`. The offered container
  must hold the chosen diameter; use an adaptive parent for larger gauges.

All meters are informational and create no focus targets. `dump()` includes
`segments`, `trailFraction`, and `diameter`. The theme owns fill/track art, color,
spacing, typography and ring stroke weight; `format` owns game-specific units.

**Reduced motion, and it is the opposite of the usual decision.** Everything else
this framework animates is decoration, and under reduced motion it snaps (see
`presenter.withAnimation`). A loading indicator is not that — it is the one piece
of motion on the screen that *carries* the information, because a frozen spinner
and a hung process look identical. So the indeterminate cycle registers
`kind = "informational"`: under reduced motion it **keeps running** to the same
wall-clock terminus and merely quantizes its writes onto the motion authority's
250 ms tick. Decorative motion snaps, informational motion steps, and nothing is
ever deleted — the indicator still visibly progresses for a player who asked for
less motion. Both policies are covered in `tests/display_controls.spec.luau`.

The fill is a **percent** dimension, so the bar reflows with its container without
recomputing pixels, and paint is style-owned through the **bar family**: the
track declares the `barTrack` decoration slot and the fill declares `barFill`.

The circular indicator's paint is not a slot at all: a Path stroke has a colour
and a thickness and nothing else, so it takes the ordinary style roles and the two
optional theme metrics named above. Both indeterminate shapes read the **same
single** phase value, so a rotating ring costs nothing the five dots did not
already cost, and the reduced-motion policy above applies to it verbatim.

Retheming those slots — or shipping art for them — restyles every progress bar.
It does **not** borrow the `control` and `accent` surfaces: those are treatments
meant for buttons and panels, and an ornate package would stretch a button plate
across the track while a panel gradient's alpha made the fill see-through. A
theme customizes a bar through
`chrome.barTrack` / `chrome.barFill`, never through the button rules.
Out-of-range values clamp through the shared value model rather than overflowing, and
`semanticText` states the value in its range; an indeterminate view's `semanticText`
is the static string `"Loading"`, because the only true sentence about it is that the
work is running and re-announcing it sixty times a second is exactly what a live
region must not do. **Non-interactive** by declaration — it reports, it does not
accept input, and it deliberately attaches no input contribution.

`dump()` carries `{ schema, id, indeterminate, presentation, … }`; a determinate
view adds `value`, `fraction`, `formatted`, `semanticText`, `min`, `max`,
`showValue`, `trailFraction`, `segments` and `diameter`, and an indeterminate one
adds `phase` (the live 0..1 cycle position) and `animating`.

### `UI.Label`

`UI.Label { … }` returns the label's node. `ref` receives `{ api, dump }`;
`api.semanticText` is a Compose readable, and the mounted owner handles disposal.

An icon + title pair. `spec = { id?, title (required), icon?, presentation?
("titleAndIcon" | "titleOnly" | "iconOnly"), iconSize?, textSize?, gap? }`.

`title` is a string, Compose readable, or tracked function. Its initial value must
be nonempty. Visual text, `semanticText` and `dump()` follow the same title without
rebuilding the control. The caller keeps later values meaningful: `semanticText` is the current title
whatever the presentation. Read it with `use(record.api.semanticText)` in a reactive body or
`record.api.semanticText:peek()` for an untracked value.
`icon` takes a construction-time semantic name (such as `"checkmark"` or `"facet:search"`)
or an asset URL. A semantic name uses the current package's icon art with the
shared readable glyph fallback; its box can grow with the text preference. An
asset URL keeps ordinary Image behavior and the declared icon dimensions.
`iconOnly` **degrades to the title** when there is no icon to show — an empty
square is worse than a word. Non-interactive: put it inside a `Button` (which takes
content) when it must be pressable, which keeps one activation surface.

Use a Label for a title that an icon identifies, such as a section heading or
a row caption. For text alone, use `UI.Text`; for a short status caption on a
plate, use `UI.Badge`.

**Adaptation.** Label has no `controlSize`. The title uses `textSize` (default
`body`) and grows with the player's text preference. A semantic icon's box
starts at `iconSize` (default `controlSizes.regular.iconSize`) and can grow
with the text; `gap` defaults to `controls.label.gap`. It has no motion, no
input and no focus stop; its `semanticText` formula is released with the
control.

```lua
local app = Facet.new()
local UI = app.controls
app.mount(function()
    return UI.Label("Saved")({ title = "Saved", icon = "checkmark", presentation = "titleAndIcon" })
end)
```

`dump()` reports `{ schema, id, title, icon, requestedPresentation,
effectivePresentation, degradedToTitle, semanticText }`.

### `UI.ShortcutHint`

A passive row of keycaps. `UI.ShortcutHint { … }` returns its node; `ref` receives
`{ api, dump }`. It creates no context, binding, focus target or input handler.
Give exactly one of `action = "Activate"` (a static semantic name) or
`keys = {{ "Ctrl", "K" }, { "F1" }}` (static explicit alternatives).

Use a ShortcutHint to show which key does something, next to instruction copy
or in a controls legend. It only shows keys: to make a key press a button, give
that `UI.Button` a `shortcut`. For the same answer as plain words in your own
`UI.Text`, use [`inputHint`](#inputhint).

The action form reads its own mounted surface's action first, even while passive;
otherwise it finds the highest-priority enabled context declaring that name.
Naming a key does not claim the action would win input arbitration. Binding and
context changes update it without rebuilding. The resolved input class selects
the binding; a live engine preference only breaks ties within that class. Touch
hides the action form, including when the action has a touch binding.

Labels prefer the binding's `displayName`, then the machine's key name, then a
shared readable name, then the raw key. A gamepad can show the platform's own
untinted key image. Explicit keys print the supplied words on every device.

| Field | Contract |
| --- | --- |
| `id` | Optional identity; a named constructor is the usual spelling. |
| `action`, `keys` | Exactly one static form, as above; names/chords must be nonempty. |
| `separator` | Bound string between explicit alternatives, default `"or"`; keys-only. |
| `controlSize` | Bound `compact`, `regular`, or `large`; defaults regular. |
| `over` | Construction-only `"media"`; also applies to the joining word. |
| `env` | Optional surface environment; supply it when the app serves ambiguous surfaces. |

Caps use the theme's icon-size ladder plus `space.xs`, with a strong tinted plate,
authored control corner and an outline of `controls.shortcutHint.capStroke` (optional
metric, default the hairline; 0 draws a soft filled cap). A chord's caps sit
`controls.shortcutHint.capGap` apart (optional, default `space.xs`). They have no package decoration slot and
reserve no interactive hit floor. Letters grow with the text preference; native
key images retain the theme-sized square. The mounted Compose owner disposes
the display formulas and borrows the action system and caller values. The hint
has no motion: a device switch repaints the caps at once.

```lua
local app = Facet.new()
local UI = app.controls
app.mount(function()
    return UI.HStack("HintRow")({
        gap = "s",
        UI.Text("Instruction")({ text = "Open the menu" }),
        UI.ShortcutHint("OpenHint")({ action = "Activate" }),
    })
end)
```

`dump()` reports `schema`, `id`, `form`, `action`, `alternatives`, `separator`,
`visible`, `glyph`, `controlSize`, and `over`.

### `UI.Picker`

Construction refuses a missing or ambiguous environment when adaptation or native editing requires it; pass `env` explicitly when the application serves multiple surfaces.

`UI.Picker { … }` -> the picker's node. `ref` receives `{ api, dump }`; the
record also carries `presentation`, a readable of the resolved style.

The one selection control: a single value backed by one caller-owned writable
cell, in the style the task and the surface want. `style` follows the reference
platform's picker styles: `automatic` (the default), `menu`, `segmented`,
`inline`, `radioGroup`, `navigationLink` and `cards`. Use `UI.ComboBox` for
validated custom text, `UI.Menu` for verbs or a set of independent
checks, and `UI.TabView` when choosing a page rather than a value.

| Spec field | Contract / default |
|---|---|
| `id`, `label` | Optional stable control identity and title. A titled `menu` picker is a form row (title leading, value and chevron trailing); a titled `navigationLink` is one row button. |
| `selected` | Required caller-owned writable cell holding the option value. |
| `options` | Static option array or readable array with stable values/identities. |
| `style` | `automatic` (default), `menu`, `segmented`, `inline`, `radioGroup`, `navigationLink`, or `cards` (never chosen by `automatic`). |
| `presentation` | **Deprecated** since 0.11.0 (removal no earlier than 0.12.0): the former spelling of `style`, with the same values. `radio` reads as `radioGroup`; pass one of the two, never both. |
| `query` | Optional caller-owned writable string cell: a searchable list. Its presence makes the automatic style the navigation link; an explicit style must be `navigationLink`. |
| `placeholder` | The trigger's word when nothing is selected (menu styles). |
| `required` | Defaults true. Selection requests cannot clear a required selection; rendering never repairs caller state. |
| `onChanging(proposed,current)` | Optional synchronous veto; returning false rejects the request. |
| `onChange(value)` | Accepted changes only; runs in the selection transaction and must not yield. |
| `enabled` | Boolean/readable boolean, default true; applies to all choices. |
| `axis` | Strip styles: `x` or `y`, optionally readable. Radio defaults to `y`; segmented defaults to `x`; inline is always vertical. |
| `valueAlignment` | `start` or `end` (default), optionally readable. In labeled `menu` rows, `start` places the value immediately after a content-sized label; `end` fills the label lane and keeps the value trailing. `end` at a regular or wider width takes the field form (title above the trigger); `start` keeps the one-line row at every width until the accessibility text sizes stack it, and with `sizing = "hug"` the whole `label [value]` pair hugs its content (a toolbar setting). Other styles and unlabeled pickers are unaffected. |
| `sizing` | `fill` or `hug`, optionally readable. A strip defaults to `fill`; a hugging horizontal strip can live in a ScrollView. A `menu` trigger without a title defaults to `hug` under a pointer (the pop-up button) and `fill` under touch. |
| `textSize` | Optional type role, numeric size, or readable; defaults to the control type role. |
| `iconOnly` | Strip styles; defaults false; requires icons on every option. Radio retains visible labels. |
| `indicator` | Static strips: `automatic`, `none`, `underline`, `pill`. Live lists: `automatic` or `none`, using selected row chrome. |
| `track` | Boolean. `track = false` marks a tab strip inside its own band (what `UI.TabView` passes): no segmented plate, no carved inset, no disclose plate — the band's own ladder owns all three. |
| `stripCorner` | Optional container-radius name (or readable of one) naming what the strip *around* this picker actually wears, so the selected fill can wear the same silhouette (`radii.selection:<container>`). Must be a radius the LIVE style publishes — the base `control | panel | pill` plus any a package adds of its own (`radii.chip`), because `radii.selection:chip` resolves under such a package; anything else refuses at construction, naming the vocabulary it was actually checked against. A **readable `stripCorner`** re-resolves on every read: on a swap AWAY from the package that publishes the container, the fill falls back to plain `radii.selection` rather than losing its corner, and a swap back re-derives the container answer on the next read. A **static `stripCorner`** is resolved once, at build, through that same fallback — so a later swap-away leaves it on the token it took, and neither the fallback nor the counter moves again for it. Requires `track = false`: a tracked strip draws its own plate and already knows its container, so the pair refuses and the message says which of the two to drop. A readable that currently reads `nil` is legal and means "no container right now" (`UI.TabView` passes one: its adaptable app bar's corner in the band form, nothing in the rail form). Absent, the fill keeps plain `radii.selection`. A healed fallback says so once per token per control **while it is falling back**: a swap back to the package clears the note and a second departure warns again, and a reactive `stripCorner` alternating between two names neither of which resolves warns on every change — the cost of a count stated in the present tense. `dump().indicator.cornerFallbacks` is that present-tense count (0 or 1): 1 means the fill is painting a fallback corner right now, and it returns to 0 the instant any token resolves again. |
| `sizeClass`, `env` | Optional environment overrides; the automatic style otherwise reads the application's environment. |
| `requiredMark` | `"required"` or `"optional"`: notation only. Required appends ` *` to the label's own words; optional paints nothing (put localized wording in `hint`). `required` keeps its reselect-policy meaning. |
| `hint` / `errorText` | Strings or readables on one message line under the picker, whatever style is on screen. A non-empty `errorText` replaces the hint in the danger role beside the `status.error` mark and borders the menu trigger in danger; the picker does not move. |
| `controlSize` | `compact`, `regular` or `large`. The menu trigger, the segments of a static strip and radio or inline rows take the rung's height and inset; the trigger and a static strip sit inside a reserved whole target (`<id>+target`). A tracked segmented strip's segments give up the track's frame carve, so the track itself lands on the rung like a Button plate. A live strip reads a bound rung once for its rows. |
| `indicatorPosition` | `radioGroup` only, construction-time `leading` (default) or `trailing`: which edge of each row carries the radio mark. Other styles refuse it. |
| `appearance` | Menu styles: `standard` (default paint), `contrast` (the emphasis plate) or `utility`. Segmented: `filled`, `stroke` or `utility`. Automatic takes all five and maps them onto the family on screen (standard or filled, contrast or stroke, utility); while it resolves to rows the intent is kept and paints nothing. Absent keeps each family's default; `inline`, `radioGroup` and `cards` refuse it. Bound words repaint in place; a word outside the family is refused and the last legal paint stays. |
| `corners` | Construction-time `pill` or `square` for the menu trigger or a static segmented strip's outer ends, track and selected fill (`pill` is the reference `isCircular`). |
| `maxHeight` | Menu styles and automatic: a finite pixel bound above zero on the whole open panel, chrome included, overriding the default two-row floor down to one visible row (and kept by the sheet fallback). Other styles refuse it. |

Opening a menu scrolls the selected row into view: a mounted row through the
shared keep-visible seam, a searchable list through its own window at the row's
estimated offset (the search field keeps focus).

An option has required `value` and nonempty `label`, and optional `id`,
`description`, semantic `icon`, `badge`, boolean/readable `enabled`,
`sectionTitle` (a caption heading drawn above this option — its own keyed
entry, so it can arrive after mount — in menus, searchable lists and stacked
strips) and `avatar` (an `UI.Avatar` spec with `name` and optional `image`,
`userId`, `key`, `provider`, leading the menu row at the compact rung; it adds
no focus stop or press) and `meta` (a secondary label/value, distinct from
`badge`, trailing a menu row's words and shown on a card) and `indicator` (a
`UI.StatusIndicator` spec table: a status mark trailing the option's words; on
a live list its `form`, `status` and `count` follow the record, and setting it
to nil removes it).
Descriptions explain unavailable choices without hiding them. Values and stable
ids must be unique. A live array uses `id`, or the string form of `value`, as
its path-safe key. Replacing or reordering an option keeps the surviving row's
identity and focus; removing a row lets the existing focus graph choose another
available target. Labels, descriptions, icons and badges update with live records.
Provide icons for every option in a group, or none.

Reselecting the current value is a no-op. A selected option becoming disabled,
being removed, or being hidden by another style does not rewrite the cell.
Callers reconcile unavailable selections explicitly and may set nil for an
unselected state. `onChanging` runs before a write; `onChange` may normalize by
writing the cell within the same transaction. Neither callback may yield.
Arrow and D-pad navigation use the mounted focus graph; Activate selects the
focused available choice. Disabling the control rejects every activation route.

**The styles.**

| Style | What it is |
|---|---|
| `menu` | On a touch surface a titled picker is one form row — title, then the value and the up/down chevron (`chevron.up.chevron.down`, a semantic icon a theme may paint) flush trailing on the same line, the whole row the tap target; elsewhere, one pop-up button carrying the value and the chevron. Activating it presents the options anchored to the trigger with a short materialize transition, the current value focused and check-marked, and no Cancel row: an outside tap, re-activating the trigger, or gamepad ButtonB closes it (Escape belongs to the engine). A gamepad, or more than six options on a compact or touch surface, presents a bottom sheet with a Cancel row instead. With a `label` the control is a form row: title leading, the trigger trailing — a plain value under touch and a bordered pop-up button under a pointer, never wider than about half the screen. Under a pointer or a pad at a regular or wider size class, and on a compact screen at the Large text preference or above, it is a field instead: the title above, the bordered trigger under it at the leading edge at its natural width, and its menu hanging from that leading edge. The value is one line and may truncate with disclosure. The popover is the theme's panel width (never narrower than the trigger, never wider than the screen), and its rows scroll inside the height the screen allows. |
| `navigationLink` | A row that leads to the full list: title, value and a trailing chevron in one row button (the value drops beneath the title at large text), presenting a full-width sheet with the rows scrolling inside the height the screen allows, the optional `query` search field and a Cancel row. |
| `segmented` | One plated track (the `control` surface every package skins) holding equal segments side by side (or a vertical rail with `axis = "y"`), always visible, the selected segment raised by the sliding `indicator`. A segment is a label only: an option with a `description` is refused on a declared segmented picker. |
| `inline` | Options stacked as full-width rows. |
| `radioGroup` | The inline rows wearing a radio mark (`indicatorPosition` picks its edge). |
| `cards` | Each option a selectable card: title, optional icon, description, `meta` and badge, a hairline edge at rest and the accent plate when chosen (the shared menu card row). A column by default; `axis = "x"` wraps onto more lines instead of running off the offer, and long copy wraps inside its card. With `required = false`, choosing the chosen card again clears the selection. Cards take no `appearance`. |

**The automatic style** resolves from the live environment — size class,
viewing distance and the primary interaction class — never from a device name.
The control module exposes the rule as the pure `resolveStyle(facts)` for
prediction; `tests/picker_style.spec.luau` pins it:

| First matching condition | Style |
|---|---|
| A `query` | `navigationLink` |
| Ten-foot display: up to four short options | `segmented` |
| Ten-foot display: up to six options | `inline` |
| Ten-foot display: more | `menu` (one focus-navigable sheet) |
| Nearby gamepad: a strip that fits (the segmented rule below) | `segmented` |
| Nearby gamepad, compact width | `menu` |
| Nearby gamepad, up to six options | `inline` |
| Nearby gamepad, more | `menu` |
| Nearby touch or pointer | `menu` |

The segmented rule: more than four options, or a compact width with more than
three options or a label longer than ten characters, is `inline`; so is any
option carrying a `description`, and a band that would not fit its row — the
sum over the options of glyph count × the text size the preference and the
ten-foot scale make × `Facet.text.AVG_GLYPH_FRACTION` plus the theme's control
padding, against the control's own solved width (the viewport less its insets
until it has one); otherwise `segmented`. A flip between the menu family and a
strip is structural (the two
share no node; focus lands on the new trigger); a flip within the strip family
is a re-solve that keeps every option's identity, focus and state.

`presentation` on the record is a readable of the resolved style. `api` carries
`open()`, `close()` and `select(value)`, live while a menu style is on screen
and inert on a strip. An automatic picker requires an environment, which
`Facet.new()` supplies.

For static segmented lists, `indicator="automatic"` uses a sliding pill.
Explicit inline and radio styles use selected row styling. `underline` draws a
bar at the strip's far edge; `pill` fills the selected box with the theme's pill
radius and spacing inset. The indicator follows solved rectangles, places
immediately on first paint or layout changes, and snaps under reduced motion.
It adds no focus target. A bare mount without a motion clock places it
immediately. `indicator="none"` uses ordinary selected chrome.

The vertical pill is not the inline row list: `axis="y"` makes a segmented rail
that hugs its contents, while `style="inline"` fills the available width.

```lua
local app = Facet.new()
local UI = app.controls
local mode = Facet.Compose.cell("open")
local clubEnabled = Facet.Compose.cell(false)
app.mount(function()
    return UI.VStack { gap = "m",
        -- the default: a form-row menu on a phone or a desktop, a strip on a television
        UI.Picker("RaceGroup")({
            label = "Race group", selected = mode,
            options = {
                { value = "open", label = "Open races" },
                { value = "club", label = "Club races", enabled = clubEnabled,
                  description = "Join a club to unlock these races." },
            },
        }),
        -- declared: a strip whatever the surface
        UI.Picker("Group")({
            selected = mode, style = "segmented",
            options = { { value = "open", label = "Open" }, { value = "club", label = "Club" } },
        }),
    }
end)
```

`dump()` reports the requested and resolved style, the presentation (the strip
form, or the menu's `menu`/`sheet` popup), the selection and, for a strip, its
arrangement and indicator.

### `UI.TabView`

`UI.TabView { … }` -> the tab view's node. `ref` receives `{ api, dump }`, where
`api` is the control's own record: `blueprint`, `placement` (a Compose readable),
`expandSidebar()`, `collapseSidebar()`, `moveTab(tabId, position)`,
`setTabHidden(tabId, hidden)`, `dump()` and `dispose()`.

A tab bar and the pages behind it. `spec = { id?, selection (a writable cell),
tabs ({ id, label?, icon?, badge?, indicator?, enabled?, content, section?, required? }[]), sections? ({ id, label }[]),
customization? (a writable cell), placement? ("automatic" | "bottomBar" |
"bottomBarCompact" | "topBar" | "sidebar"), indicator? ("automatic" | "underline" |
"pill" | "none"), sizing? ("automatic" | "fill" | "hug"), iconOnly?, accessories? ({
head?, foot?, trailing?, aboveBar? }), railWidth? (dim), textSize?, transition?,
conditions?, env?, enabled?, onChange?, style? ("automatic" | "sidebarAdaptable" | "collapsible"),
sidebarPreference?, restoreFocus?, restoreScroll?, shoulderNavigation?, controlSize? }`.

**`controlSize`** (`"xsmall" | "compact" | "regular" | "large"`, bindable) is the
tabs' local rung: each tab paints at `controlSizes.<rung>.height` while the strip
still reserves the touch floor.

A tab's **`indicator`** is a [`UI.StatusIndicator`](#uistatusindicator) spec
(`{ form?, status?, count?, max? }`) painted in that tab's own segment, in the lane
the badge seal uses; the whole-control `indicator` (underline/pill) is a
different setting and is unchanged. A tab's **`enabled = false`** keeps it in
the strip and refuses its selection on every input class.

```lua
local app = Facet.new()
local UI = app.controls
local section = Facet.Compose.cell("home")
local tabs
app.mount(function()
    return UI.TabView("App")({
        selection = section,             -- YOUR writable cell, holding a tab id
        tabs = {
            { id = "home",  label = "Home",  icon = "app:home",
              content = function(tabScope) return homeScreen(tabScope) end },
            { id = "inbox", label = "Inbox", icon = "app:inbox", badge = unreadCount,
              content = function(tabScope) return inbox(tabScope) end },
        },
        ref = function(record) tabs = record.api end,
    })
end)
```

**The strip is `UI.Picker`.** Same option row, same icons, same 44 px floor, same
sliding indicator, same authoring lints — a tab is a segment. What makes this a
construct rather than another picker property is the three things a picker never owns:
the content subtree's lifecycle, the placement that restructures the screen, and
nesting. `dump().strip` is the picker's own dump, nested rather than paraphrased.

**Placement is a policy, not a device branch.** `"automatic"` reads
`adaptive.navPlacement` — ten-foot takes `topBar` before size/input rules; nearby
compact width takes the thumb-zone `bottomBar`, a short
height its centered `bottomBarCompact`, a pointer-primary desktop the `sidebar`, a
tablet or a ten-foot screen the `topBar`. **The facts arrive by themselves, and an
automatic placement that cannot find them REFUSES to construct** (ADAPT-1): the
control reads the environment the application published, so on a real surface
neither key below is required.
Pass `conditions` (the table `Facet.adaptive.conditions(env)` returns) so its
formulas are not built twice, or `env` and the control builds and owns them;
with **no environment reachable at all** the construction raises, naming all three
routes, because a tab bar that silently picked one home and kept it is the defect this
refusal replaced. A **declared** `placement` never consults the policy at all — and
therefore never refuses, whatever the surface can or cannot answer. The resolved
answer is published as `api.placement`, so a screen with its own chrome to place — a search field that rides the bar, a wordmark
that only belongs in the rail — reads one answer instead of re-deriving the rule.

**Adaptable app navigation.** `style = "sidebarAdaptable"` opts into a shared
sidebar/tab presentation and requires automatic placement. The default style is
`"automatic"`, preserving ordinary game tabs. Roomy touch screens initially show
top tabs; pointer windows initially show the sidebar. The control does not add a
layout toggle button. `sidebarPreference = "automatic" | "sidebar" | "topBar"`
(default `"automatic"`) selects the nearby roomy home. Pass a plain value or a
readable to bind an application-owned preference. Compact/short screens keep
bottom navigation, distant screens keep top pills, and nested tabs keep their
local top bar. Returning to a nearby roomy viewport reapplies the preference.
Use this field only with `style = "sidebarAdaptable"`.

An application that needs a visible switch adds a `UI.Button` to its
existing toolbar or settings surface and updates its preference cell. The
Showcase toolbar demonstrates this for the active demo. Navigation accessories
remain available for content that belongs beside the navigation itself; they are
not required to expose this preference.
Distant screens show directly accessible top tab pills, including with mouse input. Selecting a tab keeps navigation in its
current home, whether or not the destination contains nested tabs.
`api.placement` is a Compose readable. Use `use(api.placement)` in
a reactive property and `api.placement:peek()` in an event callback.

`expandSidebar()` and `collapseSidebar()` are explicit commands, scoped to the
current viewing distance. Changing a bound `sidebarPreference` clears an earlier
command override. ButtonB while
focus is in an explicitly expanded distant sidebar collapses it; page Back remains
page-owned. Nearby compact/short screens retain bottom tabs. A nearby sidebar
preference returns when space permits, but does not override distant-view policy.
Commands preserve focus when effective placement does not change. A sidebar adds
`space.m` between its chrome and the page by default, including ordinary sidebar
TabViews; page content owns its internal padding. A top or bottom home adds
`space.s` for the same reason — the strip is a plate and the page is not part of
it. Both are metric names, so a package's own spacing moves them. The one
placement that adds nothing is `bottomBarCompact`: the policy picks it when the
screen is too short for an ordinary band, and there the chrome gives way before
the content does. Nested TabViews keep their own top bar. This style defaults to pill indicators
and preserves the normal lazy-build/eviction contract; `indicator` may override it.
No destination content or hero imagery is invented.

Use this style for peer destinations organizing a game, app, or demo browser;
ordinary nested tabs switch pages inside one destination. See the
[two-level navigation recipe](../guide/14-choosing-controls.md#two-level-navigation).

**Sections and customization.** `sections` is an ordered list of
`{ id, label }` headings with unique ids; a tab names one through its own
`section`, and the strip draws that heading above the first tab in it.
`customization` is a caller-owned writable cell holding
`{ order, hidden }`, and it is what `api.moveTab` and `api.setTabHidden` write —
both refuse without it. A tab declaring `required = true` cannot be hidden.
Either key makes the strip a live list rather than a static one.

**Nesting: an inner TabView never claims the app-level placement.** A page's own top
tab bar can live inside a screen that is itself a tab of the app's bar. Because
`content` is a factory this control invokes, a TabView built inside one *is* inner, and
it resolves to `topBar` instead of asking the policy — otherwise a phone would answer
`bottomBar` for both and draw two bars in the thumb zone. `dump().placementSource` says
which authority answered: `"policy"`, `"declared"` or `"nested"`. Neither level pushes a
focus scope, traps focus, or touches `back()`: a TabView is a layout construct, not a
presentation, so two levels simply nest.

**Content is lazy, and switching EVICTS it.** Only the selected tab's subtree exists.
Switching disposes the previous one for real — owners disposed, effects stopped,
Instances pooled — through `UI.When`'s own branch owner, which is the `tabScope` your
factory receives. The accepted cost, so nobody reports it as a bug: **returning to a tab
replays its entry cost.** A spinner comes back, an in-progress text entry is lost
unless the caller owns its state outside the tab.

`restoreFocus: boolean?` defaults to true. Each tab remembers one stable mounted
focus path. Keyboard/gamepad entry restores it when still eligible and reveals
it through the existing scroller. Pointer entry stays on the clicked control.
Missing or disabled targets use the normal entry candidate. Set `restoreFocus =
false` for flows that require a fresh task entry. Bookmarks are cleared on control
disposal; they retain no instances.

`restoreScroll: boolean?` also defaults to true, and remembers each tab's scroll
position across a switch. Set it false to return every tab to the top on entry.
Off-window collection position and drafts still belong in caller-owned cells,
using the collection’s key/reveal APIs.

`shoulderNavigation` binds (or unbinds) the gamepad shoulder paging described
under **Reachability**; declaring it also takes the strip out of the ambient
`Adjust` axis.

> **The escape hatch is ownership, not a flag.** Own it on `tabScope` and it dies with
> the tab; own it on your screen's owner, in a cell *outside* the TabView, and it
> outlives every switch — exactly as `selection` already does. There is deliberately no
> `retain` flag.

**The strip is never evicted.** Only tab *content* is torn down; every tab's label, icon
and `badge` stay live whether or not that tab is selected. Labelled badges reserve
space beside their label and wrap when needed, inside the same focusable button.

**Overflow scrolls.** A `fill` strip divides its offer among the tabs and therefore
cannot overflow, so `sizing = "automatic"` fills only the thumb-zone band and hugs
everywhere else; a hugging strip sits in a horizontal `ScrollView` and a selection change
brings the chosen tab into view through `controller.scrollToVisible`, the one
keep-visible substrate. A keyboard or gamepad move onto a tab is already revealed by the
presenter, which calls the same substrate on every focus move.

**Reachability.** Every tab is a focusable Button at the 44 px floor, read in document
order — the strip reads where it is *painted*, so a leading rail comes before the content
and a bottom bar after it. The gamepad **shoulders** (L1/R1) page between tabs and clamp
rather than wrapping; they are bound only while focus sits on a tab, so a screen carrying
a TabView never shadows gameplay bumpers. An icon-only tab still carries `label` as its
semantic name.

**Accessories: the chrome beside the tabs, homed by the placement**. A nav
bar is rarely only tabs — a wordmark at a rail's head, a search field on a top band's
trailing edge or above the thumb-zone dock. Each slot is a **factory**
`(placement, scope) -> Node?`, invoked only by the homes that host it, inside that
home's own branch: the `scope` it receives is disposed when the placement moves, and a
factory that returns nothing leaves no node at all. Which slot goes where is a fact
about what a home IS, and **this table is the whole of it** — the control quotes the
same rule back in its refusal, so there is nothing to look up at runtime:

| slot | hosted by | where it lands |
|---|---|---|
| `head` | `sidebar` | above the strip, at the top of the rail |
| `foot` | `sidebar` | at the BOTTOM of the rail — the strip's scroller spends the slack, so a three-tab rail still puts the foot on the floor |
| `trailing` | `topBar` | at the band's trailing edge, whose width it **reserves**: the strip centres in the box left over, never under the accessory |
| `aboveBar` | `bottomBar`, `bottomBarCompact` | a strip directly above the tab band, inside the dock |

```lua
accessories = {
    head = function(_placement, _scope)
        return UI.Text("Wordmark")({ text = L("app.title"), textSize = "title" })
    end,
    aboveBar = function(_placement, _scope)
        return UI.When("SearchWhen")({ condition = searchable, thenView = function()
            return searchBar()
        end })
    end,
}
```

**A slot the placement can never host REFUSES at construction**, and only then: a
*declared* `placement` (or nesting, which always resolves `topBar`) narrows the
reachable homes to one, so chrome for a home that cannot exist is a bug whose only
symptom is silence. Under `"automatic"` every home is reachable and nothing is refused
— vary the CONTENT by reading the `placement` argument, and decline a shape by
returning nothing. `dump().accessories` reports `{ declared, mounted }`: a slot in the
first list and not the second is the sentence "this placement does not host it".

**Declaring no accessory changes nothing.** The wrappers exist only when a factory
really returned a node, so the top band is a plain centred stack until a `trailing`
accessory gives it something to reserve for. With one declared, the band becomes a row: the strip
centres in the box beside the accessory rather than on the whole band (a hugging cluster
therefore sits half the accessory's width off the band's centre, by design), and no tab
is ever under it at any tab count.

**`railWidth`** is the sidebar rail's width dim — content-sized by default. A rail
states its band and lets its labels adapt inside it; a hugging rail at a 1.4x locale
and the largest text preference otherwise becomes as wide as its longest tab name and
squeezes the content lane. Refused for a declared placement that has no rail.

**`textSize`** is passed straight through to the strip's segments (see `UI.Picker`). It
defaults to `"fit"`: a tab's words shrink toward the caption role to fit their slot before
the engine truncates one (a filling bottom bar gives each tab a fixed share). It is
reactive so it can be bound against the placement: a thumb-zone tab bar is
caption-sized in tighter chrome and a rail is not. The construct carries the binding and
does not pick the ramp — which home takes which role is a design language.

**`transition`** is `UI.When`'s own transition table, applied to the **content**
branches and to nothing else (the strip is never evicted, so it has nothing to animate).
A `fade` needs a fade group, so make the tab's own top node a `canvasGroup`.

**A declared `sizing = "hug"` in the thumb zone centres and scrolls**, like every other
hugging home. The default `fill` band is deliberately not a scroller because `fill`
segments divide the offer and cannot overflow — that is a statement about the default,
not about the home.

**A segmented picker used as a tab bar IS a TabView**, with `indicator = "pill"`. A picker
chooses a value; a tab view chooses a page.

Ownership: the control's Compose owner owns the strip and its indicator; each tab's
`tabScope` owns whatever that tab's factory put on it. `selection` is yours.

### `UI.DisclosureGroup`

`UI.DisclosureGroup { … }` -> the group's node. `ref` receives `{ api, dump }`,
where `api` is the control's record: `blueprint`, `bindFocus(graph)`, `dump()`
and `dispose()`.

A labelled header that expands and collapses its content. `spec = { id?, label
(required), expanded (a writable boolean cell), content (() -> Node), enabled?,
onToggle?, presenter?, description?, icon?, chevronPosition?, appearance?, controlSize?,
textSize?, indent? }`.

`description` is bindable secondary copy; `icon` is a semantic icon name.
`chevronPosition` is leading (default) or trailing. `appearance` is plain (default),
contained (a raised group), divided (a separator while expanded), or outline — a
tree row: the header paints no plate and no expanded wash (it keeps focus and
activation). `textSize` is the header's type role (label, caret and icon; default
`"control"`); `indent` insets the content's leading edge by a space step or px, so
nested groups read as an outline. Bindable `controlSize` uses the shared rung and
restores the default when nil.

Use a DisclosureGroup to hide optional detail or advanced settings under a
heading, pushing the content below it down. For a summary button that expands
into a view over the page, use `UI.CollapsibleView`; to move to a new page of
content, use `UI.NavigationStack`.

**Input.** The header is an ordinary `UI.Button`: a pointer click, a touch tap,
Return on a keyboard and ButtonA on a gamepad all run the same toggle. With
`enabled = false` the header wears disabled paint and every route refuses the
toggle; `expanded` keeps its value, so open content stays open.

```lua
local app = Facet.new()
local UI = app.controls
local expanded = Facet.Compose.cell(false)
app.mount(function()
    return UI.DisclosureGroup("Advanced")({
        label = "Advanced",
        expanded = expanded,
        content = function() return UI.Text("Body")({ text = "Hidden until asked for" }) end,
    })
end)
```

Content mounts through `UI.When`, so a collapsed group genuinely costs nothing (only
structural regions may mount or unmount). Content reveals in place through a vertical clip on the non-overshooting
`dismiss` motion class for both opening and closing. It does not rasterize the
expanded subtree into a CanvasGroup, so long lists retain native text resolution
on lower graphics settings.
The caret uses the same class, so it does not bounce beyond its final angle.
Reopening mid-exit reverses the existing transition.

The header publishes its expanded selection state to ordinary Button paint.
The caret and optional divider also indicate expansion.

**The caret is one `chevron.trailing` glyph, not two.** Its `rotation` — paint-only,
never seen by the solver — springs 0 → 90 as `expanded` flips, turning to point down
rather than swapping between a mounted `chevron.down`/`chevron.trailing` pair. A
package's `chevron.down` art is not requested by this control.

**`presenter?` buys the sibling glide.** When given (a presenter — anything with
`withAnimation`), the toggle runs inside `presenter.withAnimation("dismiss", …)`, so
every OTHER node whose solved position the flip moves — a section below this one
sliding to make or close room — travels there instead of jumping. Absent (the common
case), the flip is instant; the caret and the content still animate their own paint
either way, off the ambient motion clock every mounted control receives for free.

**Focus is the load-bearing detail.** Collapsing while focus sits inside the content
would leave focus on a node that is about to be unmounted, so the control moves focus
back to its own header **before** the content disappears. Expanding leaves focus on
the header — the player asked to see the content, not to jump into it. Call
`bindFocus(presenter.focus)` through `ref` only for a custom low-level host; the
ordinary application supplies its focus graph through the mounted contribution.

`expanded` is a cell **you** own, so a settings screen remembers which sections were
open across a remount. `dump()` reports `{ schema, id, label, expanded, headerPath,
semanticText }`.

### `UI.Slider`

`UI.Slider { … }` -> the slider's node. `ref` receives `{ api, dump }`, where
`api` exposes `model`, `semanticText`, `fillWidth`, `thumbOffset`,
`onInteractionClassLost(class)` and `diagnostics()` (a copy of a range's
refusal lines), with state through `record.dump()`.
The ref does not expose `blueprint` or `dispose`; the component owner releases
the control.

A continuous or stepped value along a track, sharing the value arithmetic with
`UI.Stepper`. Spec keys are `id`, `label`, `value`, `min`, `max`, `step`,
`format`, `enabled`, `onChange`, `onCommit`, `tapToPosition`, `thumbImage`,
`trackImage`, `row`, `axis`, `range`, `minGap`, `thumb`, `thumbContent`, `trackContent`,
`rotation` and `controlSize`.

Use a Slider when the player sets a value in a range by feel and the exact
number matters less, such as volume or camera sensitivity. For small exact
steps, use `UI.Stepper`; for a typed exact number, use `UI.NumberInput`. The
slider has no animation of its own: the thumb and fill paint each new value at
once, so reduced motion changes nothing.

| Key | Contract and default |
|---|---|
| `axis` | Construction-only `"x"` (default) or `"y"`. A `y` track runs bottom to top and its arrows are Up/Down; the arrows always follow this authored axis, whatever `rotation` paints. |
| `range` | Construction-only, default false. `value` then holds `{ lower, upper }`; each change writes a fresh pair and calls `onChange(pair, { thumb = "lower" \| "upper" })`, and `onCommit` likewise once per gesture. The thumbs never cross. An illegal initial pair (wrong type, non-finite, reversed, narrower than `minGap`) is a build error; one arriving later keeps the last legal pair painted and driveable, is never written back, and records a line in `api.diagnostics()` (once per consecutive distinct reason, at most 16 kept). |
| `minGap` | Construction-only number from 0 (default) to the range width: the least distance between the thumbs, in value units. |
| `thumb` | Construction-only `"always"` (default), `"auto"` or `"none"`. Paint only: `auto` shows the handle on hover, focus and drag and always on a touch-primary surface; `none` never paints it. Targets, focus, readout and adjustment are unchanged. |
| `thumbContent(info)` | Called once per thumb at build; returns the knob node. `info = { thumb = "value" \| "lower" \| "upper", value, fraction, dragging, enabled }`, the last four readables. The knob sits in a handle floored at the theme's thumb size that grows to fit it; it drops only its own `sliderThumb` slot, and travel is measured from what is drawn. Refused with `thumbImage`. |
| `trackContent()` | Called once at build; returns the track's node (a colour ramp), centred in the track and replacing the rail and its accent fill — the strip is the value's scale. Refused with `trackImage`. |
| `rotation` | Bound degrees, default 0: paint-only about the track's centre. Presses are converted by the inverse angle at event time (scroll included); label and readout stay upright and the row keeps its unrotated layout box, so reserve room for the turned paint. Ancestor `scale` is not composed into input. |
| `controlSize` | `"xsmall"`, `"compact"`, `"regular"` or `"large"`: a thinner painted track inside a reserved whole target, and the thumb drawn at the rung's `iconSize` (regular = Neutral's thumb); a vertical track keeps its full travel. |

A range's two handles share one focus group: Tab visits both and then leaves,
and keyboard arrows adjust the focused handle. On a gamepad-primary surface the
arrows first move between the handles; Activate enters adjust mode, and Cancel,
Tab or focus leaving exits it. Coincident thumbs choose by the side a press
approaches from, before quantization (at the minimum the upper moves, at the
maximum the lower); a gesture keeps its thumb and commits once, and losing the
pointer and touch classes mid-drag restores the whole starting value. The range
handles use capture-based dragging; the native detector serves the track. The
label shrinks (its full text disclosed) before the track or readout does. The
track's value axis is floored at `targetSizes.minimum`, so a slider in a hugging
cell (a vertical one above all) keeps a draggable track instead of collapsing to
its thumb.

**There is no separate Knob control.** A handle's size, shadow, stroke, disabled
look and icon come from the theme's `sliderThumb` slot (or `thumbImage`); an
inverted or icon-bearing knob is a `thumbContent` node reading `info.enabled`
and `info.dragging`. A switch's knob is the Toggle's own theme chrome.

```lua
local app = Facet.new()
local UI = app.controls
local volume = Facet.Compose.cell(50)
app.mount(function()
    return UI.VStack { width = UI.fill(),
        UI.Slider {
            label = "Volume",
            value = volume,
            min = 0, max = 100, step = 5,
            tapToPosition = true,
            onChange = function(value) end,
            onCommit = function(value) end,
        },
    }
end)
```

**`step` may be live.** Pass a number for a fixed grid, or a readable or a
`function(use)` for one that changes: the model resolves it at every
quantization, so a setting beside the slider — a "turn step" stepper, a
precision toggle — drives the grid the slider snaps to with no remount. `nil` is
continuous, and a non-positive step is refused where it is read. `dump().step`
reports the step in force.

```lua
local app = Facet.new()
local UI = app.controls
local index, angle = Facet.Compose.cell(1), Facet.Compose.cell(0)
local steps = { 1, 5, 15, 45 }
local turnStep = Facet.Compose.formula(function(use) return steps[use(index)] end)
app.mount(function()
    return UI.VStack { width = UI.fill(),
        UI.Slider("Angle")({ value = angle, min = -180, max = 180, step = turnStep }),
    }
end)
```

**`thumbImage` / `trackImage` are rung 2 of the customization ladder.** Normally a
theme package's `sliderThumb` / `sliderTrack` chrome recipes skin every slider in the
game (rung 1) — see [the custom-theme guide](../guide/09-custom-themes.md). Set one of
these and *this* slider's thumb or rail paints from your value instead. The overridden
node then stops following theme changes, deliberately and visibly: that is the standing
opt-out rule, the same one an explicit numeric size follows. Everything else about the
control — its sizes, its palette, its layout — stays on the theme. The image is painted
whole (a bare URI carries no nine-slice geometry), and `dump().skinRung` reports which
rung is live.

**Both props take the same per-state grammar a recipe's `asset` does**,
normalized by the same function, so the two rungs can never drift into
different vocabularies:

```lua
thumbImage = { default = "rbxassetid://…", hover = "rbxassetid://…", pressed = "rbxassetid://…" }
```

`default` is required in map form. HONEST LIMIT: a slider thumb is a `Frame` and
never leaves `GuiState.Idle`, so `hover` and `pressed` on a *thumb* are
unreachable at both rungs today; those states are reachable on an interactive
node such as a button's `control` slot. See
[`../guide/10-rich-skinning.md`](../guide/10-rich-skinning.md) §10.10.

`row = { description?, icon?, value? }` gives the slider the shared settings-row
header; `row.value` is refused because the slider supplies its own readout.

**Live drag is the native detector.** The track adopts `UIDragDetector` through
`controller.attachDragDetector`. A fallback is required for targets where the
detector is not usable, so
the track is a `UI.Grip` whose capture-based pointer handlers drive the **same**
mutation site — nothing here is a slider-specific recognizer, and `dump().nativeDetector`
reports which route is live.

**Keyboard and gamepad use `Adjust`, not a continuous stick.** Increments are
predictable and the binding is focus-gated, so a screen containing a Slider never
shadows gameplay bumper keys.

**Hot-switch is CANCEL.** Unlike `Stepper`, a Slider holds in-flight state. Losing the
pointer class mid-drag — or the engine cancelling the capture — reverts to the
pre-drag snapshot rather than committing a value the player did not choose. Drive it
from your live interaction-class watcher via `api.onInteractionClassLost(class)`.

**The sub-node paths, because a test has to address them.** A Slider is a small
tree under its own `id`, and these paths are public: a headless spec reads
rectangles off them and drives the drag through them, and they are what
`tests/value_controls.spec.luau` uses.

| Path, under the slider's `id` | What it is |
|---|---|
| `TrackHost` | the row the track lives in; its `rect.w` is the length the value maps along |
| `TrackHost/Track` | the interactive surface — the drag target and the tap-to-position target, carrying the 44 px touch floor |
| `TrackHost/Groove/Rail` | the unfilled groove |
| `TrackHost/Groove/Fill` | the filled portion; its `rect.w` is the value, painted |
| `TrackHost/Groove/Thumb` | the handle |

Drive a drag against `TrackHost/Track` with the render target's three drag verbs,
which go through the same mutation site the native detector does:

```lua
local track = adapter.node("/S/Vol/TrackHost/Track").rect
adapter.driveDragStart("/S/Vol/TrackHost/Track", { x = track.x, y = track.y })
adapter.driveDragContinue("/S/Vol/TrackHost/Track", { x = track.x + track.w, y = track.y }, nil)
adapter.driveDragEnd("/S/Vol/TrackHost/Track", { x = track.x + track.w, y = track.y })
```

`adapter.pointerDown(path, x, y, "touch")` drives the tap-to-position and
capture-fallback route instead. Both are shown in
[guide 3 §3.2b](../guide/03-getting-started.md#32b-testing-your-screen).

The root row is `fill`-width by design: a fill-width track inside a content-sized
parent would resolve to zero and leave nothing to drag along. **So give the stack
you put a Slider in a width**: `UI.VStack { width = UI.fill(), slider }`.
A Slider whose track measures zero is what a hugging parent produces, and it
looks like a Slider that will not move.

### `UI.LevelPicker`

`UI.LevelPicker { … }` -> the run's node. `ref` receives `{ api, dump }`, where
`api` is the control's record: `blueprint`, `semanticText`, `diagnostics()`,
`onInteractionClassLost(class)`, `dump()` and `dispose()`.

`semanticText` is a Compose readable: use `use(api.semanticText)` in a reactive
body or `api.semanticText:peek()` for an untracked read. Rating exposes the same
readable contract.

A run of `count` **discrete segments** that reads as one value: a graphics
preset, a difficulty dial, a capacity meter, a rating. Zero is a real state.

```lua
local app = Facet.new()
local UI = app.controls
local quality = Facet.Compose.cell(2)
app.mount(function()
    return UI.LevelPicker("Balanced")({
        value = quality,           -- a caller-owned writable number cell
        count = 10,                -- the maximum; default 5
        allowZero = true,          -- default; false makes 1 the floor
        segment = "bar",           -- "bar" (default) | "glyph" | "image"
        tint = {                   -- both halves optional; omitting one leaves it to the theme
            filled = { role = "accent", blend = 1 },
            empty = { role = "control", blend = 1 },
        },
        segmentSize = "small",     -- the iconSizes rung a glyph/image segment draws at
        readOnly = false,          -- true paints it and takes it out of the focus ring
        enabled = true,
        onChange = function(v) end,
    })
end)
```

Optional `glyphs` / `images` each supply a `{ filled, empty }` pair, and `env`
spaces the run for the live input class.

**Why this is a control and not `count` buttons.** The argument is the one
`UI.Rating` records below, and it gets stricter as `count` grows: `count` themed
plates instead of `count` marks, `count` focus stops for one number, and `count`
activation handlers all writing one cell. A level picker is instead a uniform
`UI.Grid` of leaves under a **single** `UI.Grip` — one focus stop, one effective
target, one place pointer input lands — and a value change repaints exactly
`count` leaves without remounting anything.

**`segment` picks what one level is painted as.**

| `segment` | the leaf | how the run divides its width | needs assets |
|---|---|---|---|
| `"bar"` (default) | `UI.Box` | the marks **fill** their uniform columns | no |
| `"glyph"` | `UI.Text` | the run **hugs** its glyphs and centres | no |
| `"image"` | `UI.Image` | the run hugs its square marks and centres | yes — `images` is required |

`"bar"` is the default because it is the only one that can draw a level picker
with nothing but a theme: ten thin bars and three wide blocks are the *same*
declaration, because the segments divide whatever width they are given.

**`glyphs` and `images` each describe one segment**, so declaring the wrong one
is a construction error rather than a silent no-op — `glyphs` beside
`segment = "bar"` is a caller who believes they are looking at glyphs.
`segment = "image"` with no `images` is refused too: this control never names an
asset of its own, so there is no default to fall back on.

**`tint` is the continuous-colour channel, one value per half.** Each is an
ordinary Facet tint — `{ role = …, blend = … }` (themable, preferred) or
`{ direct = "#rrggbb" }` (declared theming-exempt) — and each is independently
optional: omitting one leaves that half to the theme. This is how a filled mark
and an unfilled one take different colours.

A `bar` picker has **defaults** for both halves (`accent` filled, `control`
empty) because a bar has no other way to say "filled". A `glyph` or `image`
picker has **none**, because its mark already carries the state — so a `tint`
there is purely additive and a star never silently changes colour.

**Reach.** Pointer and touch tap anywhere on the strip to set, or press and drag
to scrub live (dragging off the leading edge clears to zero when `allowZero`).
Keyboard and gamepad use the focus-gated `Adjust` verb — Comma/Period and L1/R1
— bound **only** while focus is inside the control. Left/Right adjust while the
value can move and **go back to navigation at the limit**, so nothing after a
maxed-out picker is unreachable on a gamepad. The strip declares a 44px
effective target, which is load-bearing for `bar`: its segments have no content
height of their own.

**Hot-switch is CANCEL**, like `UI.Slider` and `UI.Rating`: losing the pointer
class mid-drag reverts to the pre-scrub value. Drive it from your
interaction-class watcher via `api.onInteractionClassLost(class)`.

**The ± buttons are not part of this control.** Compose a `UI.Stepper` beside it
over the *same* cell. A stepper sits NEXT TO the field that shows the current
value, because the stepper does not display one itself. Building the buttons in
would put two more focus stops inside a control whose
whole claim is that it has one. `examples/gallery/scenarios/level_picker.luau`
shows the composition.

**`diagnostics() -> { string }` is a warning channel, never a refusal.** A
`count` above **11** adds one note saying so, and the control still builds. 11 is
measured, not chosen: it is the largest run at which every shipped theme package
still solves each `bar` segment at least as wide as the narrowest mark that
package draws (`iconSizes.small`), at 320x640 with the run spaced for touch. It
is a diagnostic because you may have more room than a phone: a large value range
can make the segments of a discrete capacity indicator too small to be useful,
which is guidance rather than a limit. The notes also ride `dump().diagnostics`.

`dump()` reports `schema = "facet-level-picker-dump/1"`, `segment`, `value`,
`count`, `min`, `readOnly`, `enabled`, `semanticText`, `diagnostics` and
`rootPath`. `segment` and `semanticText` are the pair that make a bar- or
image-only control readable to a consumer that cannot see it: one says what is
being painted, the other says what it means (`"2 of 10"`).

### `UI.Rating`

`UI.Rating { … }` -> the run's node. `ref` receives `{ api, dump }`, with the
same record `UI.LevelPicker` publishes.

A short run of glyphs that reads as **one** value: a star rating, a difficulty
dial, a five-point score. It is a **thin preset over `UI.LevelPicker`**:
`count = 5`, `segment = "glyph"`, the star pair, and no tint. Everything below is
unchanged — including `starSize`, which is this control's spelling of the level
picker's `segmentSize`. Reach for
`UI.LevelPicker` when you want a different maximum, bars or images instead of
glyphs, or a colour per half.

```lua
local app = Facet.new()
local UI = app.controls
local score = Facet.Compose.cell(3)
app.mount(function()
    return UI.Rating("Score")({
        value = score,             -- a caller-owned writable number cell
        count = 5,                 -- how many glyphs; default 5
        allowZero = true,          -- default; false makes 1 the floor
        readOnly = false,          -- true paints it and takes it out of the focus ring
        glyphs = nil,              -- optional { filled = "★", empty = "☆" } override
        starSize = "small",        -- the rung the glyph is DRAWN at; the box is a share
        onChange = function(v) end,
    })
end)
```

**Why this is a control and not N buttons.** One `UI.Button` per star is the
obvious spelling and it is wrong on all three axes at once — a defect found on a
physical phone, not in review:

* **paint** — a Button is a `control` to every theme, so each star wore a plate.
  Under a glossy package a rating was five glossy *pills*; under one whose
  control recipe is a raised **shadow**, five shadows overlapped into a smeared
  band behind the row.
* **input** — five focus stops for one number, and five overlapping 44px hit
  expanders (the Button contract's enforced floor) inside one narrow cell.
* **semantics** — "star 4" is not something a player does; "rate this 4" is.
  Five activation handlers writing one cell is one verb in five costumes, and
  nothing could read the control's value *as* a value.

A Rating is instead an `HStack` of glyph `Text` nodes under a single `UI.Grip`:
one focus stop, one effective target, one place pointer input lands, and a value
change repaints exactly `count` labels without remounting anything.

**Reach.** Pointer and touch tap anywhere on the strip to set, or press and drag
to scrub live (dragging off the leading edge clears to zero when `allowZero`).
Keyboard and gamepad use the focus-gated `Adjust` verb — Comma/Period and L1/R1
— bound **only** while focus is inside the control, so a screen containing a
Rating never shadows gameplay bumper keys.

**Hot-switch is CANCEL**, like `UI.Slider`: a scrub is in-flight state, so losing
the pointer class mid-drag reverts to the pre-scrub value rather than committing
a rating nobody chose. Drive it from your interaction-class watcher via
`api.onInteractionClassLost(class)`.

**The glyphs are the control's own characters, not theme icons.** `★`/`☆` are
chosen the same way `UI.TextInput`'s clear `×` (U+00D7) is — BMP characters
confirmed to draw on a real device in the fonts this library ships against.
`ICON_FALLBACK_GLYPHS` is deliberately plain ASCII because it answers for names
a package declined to draw, and `*`/`-` is not a star rating. A package with an
exotic face (a pixel font, a display face) passes its own pair through `glyphs`
rather than gambling on coverage.

Sizes come from the theme: a star draws on the `iconSizes` ladder and the run's
gap is the package's smallest space step, so a theme swap resizes the control
with no rebuild.

**The glyph is sized; the box is shared.** `starSize` picks the `iconSizes` rung
the star is *drawn* at; its WIDTH is a share of whatever the rating was given.
That split is a measurement, not a taste: with a fixed box per star the strip's
width is the theme's arithmetic (`count` icons plus gaps) while the cell it sits
in is the caller's fixed number, and the two agree only by luck — the same 132px
table column overran by 12px under Glossy Touch and left 28px empty under Pixel
Quest. Taking a share means the strip can neither overflow its cell nor leave a
gap, in any package. In a content-sized parent a `fill` child measures as its own
content, so a standalone rating still hugs its glyphs rather than stretching.

### `civilDate`

`Facet.civilDate` is the calendar `UI.DateTimePicker` keeps its values in. A
`CivilDate` is `{ year, month, day, hour?, minute? }` in no time zone; a
`CivilRange` is `{ start?, finish? }`.

- Arithmetic: `civilDate.isLeap(year)`, `civilDate.daysIn(year, month)`,
  `civilDate.toDays(d)` / `civilDate.fromDays(n)` (days from 1970-01-01),
  `civilDate.dateOf(d)` (the date without its time), `civilDate.addDays(d, n)`,
  `civilDate.addMonths(d, n)` (the day clamps: January 31 plus a month is the
  last of February), `civilDate.compare(a, b)` (by date), `civilDate.same(a,
  b)` (every field), `civilDate.weekday(d)` (1 = Sunday),
  `civilDate.monthGrid(year, month, weekStart)` (six weeks of dates),
  `civilDate.within(d, min?, max?)`, `civilDate.clampRange(range, min?, max?)`
  (nil when the range is wholly outside) and `civilDate.problem(d, withTime?)`
  (why a table is not a date, or nil).
- Words: `civilDate.format(d, locale?)`, `civilDate.formatTime(d, hourCycle)`
  and `civilDate.parse(text, locale?, withTime?)` in the locale's numeric
  order (it answers the date, or nil and a sentence saying why; a year has four
  digits, and a 12-hour locale needs AM or PM on an hour from 1 to 12);
  `civilDate.ENGLISH` is the default locale.
- Instants always name their offset: `civilDate.fromUnix(seconds,
  offsetMinutes)` and `civilDate.toUnix(date, offsetMinutes)`. There is no zone
  database, so a zone with daylight time is your conversion to a fixed offset.
  `civilDate.systemClock(offsetMinutes?)` returns the default `clock`: the
  player's local date and time, or the engine clock at a named offset.

`parse` returns two values, `(date?, why?)`: test the date before you use it.

```lua
local civil = Facet.civilDate
local start = { year = 2026, month = 2, day = 27 }
print(civil.format(civil.addDays(start, 3))) -- "03/02/2026": March 2 in the default month/day/year order
local date, why = civil.parse("02/30/2026")
if date == nil then
    print(why) -- a sentence saying why the text is not a date
end
```

### `valueModel`

`Facet.valueModel.new({ min, max, step?, format? }) -> Model` — the shared,
pure arithmetic behind the value-control family, so `Stepper` and a `Slider` cannot
disagree at the edges: `clamp`, `quantize`, `stepped`, `fraction`, `fromFraction`,
`format`, `semanticText`, `atMin`, `atMax`, `currentStep`.

`step` takes a number, a readable, or a `function(use)`. Every reader resolves it
at the moment it quantizes, so a live step changes the grid with no rebuild;
`model.step` is the declared number (nil for a live source) and
`model.currentStep()` is the step in force right now.

Invariants worth knowing: the step grid is measured **from `min`**, so a range like
5…25 step 5 reaches both bounds; `stepped` always makes progress (a mid-grid value
does not quantize back onto itself and no-op); a NaN or infinite input resolves to
the low bound instead of propagating; and an impossible range or a non-positive step
is a build error naming the field.

`valueModel.defaultFormat(v) -> string` is the namespace's other member: the
library's default number formatting, with integers bare, fractions to at most two
decimals with trailing zeros trimmed, and no negative zero. It is what a model
uses when its spec declares no `format`. **It is not the same function as
`model.format`** — a model's `format` clamps the value into the model's range
first, and this one does not. Reach for it to make a legend or a tick label match
a control's numerals; do not use it expecting bounds.

`spec.format` is a consumer callback like any other: it is quarantined on the
render path, and a throwing formatter falls back to `defaultFormat` rather than
unwinding a solve.

### `UI.TextInput`

Construction refuses a missing or ambiguous environment when adaptation or native editing requires it; pass `env` explicitly when the application serves multiple surfaces.

`UI.TextInput { … }` -> the field's node. `ref` receives `{ api, dump }`.

A native text editor with caller-owned text. Choose `presentation = "plain"`,
`"search"`, or `"number"`; set `multiline = true` on a plain editor for notes and
messages. Roblox owns typing, caret movement, selection, clipboard interaction,
and composition. Facet owns accepted values, validation, focus participation,
geometry, and theme styling.

Use a TextInput when the player types free text, such as a name, a search or a
message. For a number, use `UI.NumberInput`; for text that must match one of
your options or pass your own check, use `UI.ComboBox`; for a fixed list, use
`UI.Picker`.

```lua
local app = Facet.new()
local UI = app.controls
local crewName = Facet.Compose.cell("") -- yours: accepted edits write it
app.mount(function()
    return UI.TextInput("CrewName")({
        value = crewName,
        label = "Crew name",
        placeholder = "Enter a name",
        maxLength = 20,
        onCommit = function(text, reason) print("saved", text, reason) end,
    })
end)
```

| Field | Contract and default |
|---|---|
| `id` | Stable control identity; defaults to `"TextInput"`. |
| `value` | Required caller-owned writable string cell containing the editable text. |
| `presentation` | `"plain"` (default), `"search"`, or `"number"`. |
| `placeholder` | Engine placeholder when text is empty. Search defaults to `"Search"`. |
| `enabled` | Boolean or readable boolean; defaults true. |
| `disabled` | The inverse spelling. Supplying both forms is an error, even if they agree. |
| `multiline` | Construction-time boolean, default false. Native multiline text and wrapping inside a native scroll viewport. Incompatible with numeric presentation. |
| `height` | Dimension; a single line has a minimum of `controls.textInput.fieldHeight` and grows for its text and theme. Multiline defaults to `controls.textInput.multilineHeight`. Long multiline content grows inside the viewport and can be scrolled; native caret movement and line insertion reveal the active line. The default viewport shrinks to the available keyboard-free area while editing; an explicit height stays caller-owned. |
| `onChange(text)` | Called for each accepted user edit or clear, never for caller writes or cancellation. |
| `onCommit(value, reason)` | Called for a valid commit. The text presentations report the accepted string; the number presentation reports the committed **number**. Reasons are `"enter"`, `"focusLost"`, explicit `"submit"` (also a step-button press), and `"clamped"` when a bound moved a typed number. A read-only field reports no commit. |
| `onCancel()` | Called after restoring the text captured at edit entry. No commit fires. |
| `clearButton` | Convenience for `clearButtonMode = "always"`. |
| `clearButtonMode` | `"never"`, `"whileEditing"`, `"unlessEditing"`, or `"always"`. Default is never; search defaults to always. Empty or disabled fields hide the affordance. |
| `maxLength` | Maximum accepted Unicode scalar count. Invalid UTF-8 is rejected. |
| `validate(text)` | Return an accepted, idempotently normalized string, or nil to reject. Applied after length limiting and on commit. Numeric formatting must also pass validation before committed values change. |
| `invalid` | Optional caller-owned readable boolean. While true the plate wears the danger border (as it does while `errorText` or a rejection shows). Each false-to-true edge shakes the field once on the paint-only `offset`: the solved rect, hit target, and focus order never move, and a second edge restarts the shake rather than racing it. The shake is decorative, so a reduced-motion session drops it entirely; show the reason yourself, as number presentation shows its own message. |
| `numericValue` | Required caller-owned writable number cell for number presentation; distinct from the editable string in `value`. |
| `parse(text)` / `format(number)` | Numeric commit functions. The default parser is a strict decimal grammar (optional sign, digits, at most one `.`; no exponent, grouping, hex or surrounding blanks); `Facet.recipes.arithmetic.parse` adds arithmetic. The default format is `tostring`, or exactly `precision` places when declared. Parsing must return a finite number; formatting must return a string. |
| `min` / `max` | Optional inclusive numeric bounds. A typed number outside them is clamped to the bound and committed with reason `"clamped"`; it is not an error. |
| `step` | Number presentation: finite and above zero, default 1. One step-button press; with both bounds it follows the step grid measured from `min`, as Slider and Stepper do. |
| `precision` | Number presentation: whole number of decimal places from 0 to 10. Rounds half away from zero at commit (and on a step press), never while typing. |
| `stepButtons` | Number presentation, construction-time boolean. Two target-sized buttons inside the plate after the clear affordance: ordinary focus stops that claim no arrow keys, disabled at the bound they face, when read-only and when disabled. A press commits. |
| `prefix` / `suffix` | Number presentation: string or readable string standing beside the editor as unit chrome, never part of the draft. They shrink before the editor on a narrow row; a unit, clear affordance and both step buttons can still exhaust a 320 px phone at the largest text preference under heavy themes. |
| `env` | Defaults to the environment the application published; an environment must exist for keyboard occlusion and input-class handling. |
| `actionSystem` | Optional injection; the presenter supplies the existing action system automatically. |
| `keyboardType` | `"default"`, `"numeric"`, `"email"`, or `"phone"`. Intent metadata: the shipping public engine API does not allow Facet to choose the native keyboard. |
| `submitLabel` | `"default"`, `"done"`, `"go"`, `"next"`, `"search"`, or `"send"`. Intent metadata; no public engine property applies it. |
| `label` | String or readable string above the field. A tap or touch on it focuses the editor; it adds no focus stop and reserves the touch floor in its own row, words at the bottom. |
| `requiredMark` | `"required"` or `"optional"`: notation only, never validation. Required appends ` *` to the label's own string (bound labels too). Optional paints nothing, because Facet has no localization table: put localized "optional" wording in `hint`. |
| `hint` | String or readable string on the one message line under the field at rest. Wraps; unbreakable text stays reachable through disclosure. |
| `errorText` | String or readable string. Non-empty replaces the hint and the numeric rejection line, paints the danger role beside the `status.error` mark, keeps the field's position, and does not shake (`invalid` keeps that meaning). |
| `leading` / `trailing` | Blueprints inside the plate. Leading is static decoration and adds no stop; a search field refuses it. Trailing sits after the clear affordance, and its focusables join the field's focus order after the editor and clear. |
| `controlSize` | `"xsmall"`, `"compact"`, `"regular"`, or `"large"`: the theme ladder's height and inset. A named rung reserves the full touch target around the plate; an authored `height` wins, and multiline keeps its line-based height. |
| `appearance` | `"standard"` (default chip plate), `"contrast"` (control plate) or `"utility"` (no plate). Bound words repaint in place; a word outside the set is refused and the last legal paint stays. |
| `corners` | Construction-time `"pill"` or `"square"`; absent keeps the theme radius. |
| `readOnly` | Boolean or readable boolean, default false. True keeps the field focusable, selectable, at full contrast and able to show a caret, but the engine and the model refuse every edit; the clear affordance is not offered and leaving the field commits nothing. Live changes keep the same editor and edit. |
| `selectOnFocus` | `"none"` (default: the native caret where the press put it), `"all"` or `"end"`, or a readable one. Applied once per focus session: a pointer focus applies it at that pointer's release, activation at once. A change while focused applies at the next focus; value, text and theme changes never reselect. A read-only field may select; a disabled one never gains focus. |
| `visibleLines` | Multiline only: a construction-time whole count of at least 1. The viewport is that many lines of the field's `control` typography plus the skin's field inset, still capped to the keyboard-free area while editing; past it the text scrolls inside a box that holds still. An authored `height` wins. |

Single-line Enter commits. Multiline Enter inserts a newline; use `api.submit()`
for explicit submission. Focus loss commits through the same validation path.
Tab finishes editing and traverses the existing focus graph. While editing,
arrows remain with the native editor. ButtonB, engine-reported cancellation,
and `api.cancel()` restore the entry snapshot. Disabling, including through an
ancestor, ends editing, preserves accepted text, and rejects late edits and commits.

Numeric entry keeps strings such as `"-"`, `"."`, and `"1e"` as editable drafts.
Parsing, rounding, bounds, and formatting run on commit, rather than rewriting each
keystroke. Leaving the field on an incomplete draft (empty, a lone sign, a lone
point) restores the last committed number without a message, unless
`requiredMark = "required"`, which reports it. Rejected commits retain the draft, show an error, and shake the field
on the same paint-only `offset` `invalid` shakes on — but **on every rejected
commit, not an edge**: a repeat of the same rejection shakes again, which is
exactly when the nudge is worth the most (`invalid`, by contrast, only shakes on
a false→true transition; setting it to `true` a second time in a row is not a
new rejection). Reduced motion drops the shake on both paths; the message
beneath the field holds still either way, and it is the only account of *why* —
show the reason yourself. Search uses the
same text pipeline with a themeable search mark and clear affordance; bind its
`value` to a filtering formula for an ordinary list or to a Picker's `query`.

Accepted edits do not force programmatic TextBox rewrites on each keystroke.
Rejected or clamped engine text is reconciled when editing ends. Live theme and
layout changes preserve the TextBox instance. Wrapped multiline editing uses a content-sized TextBox and a surrounding ScrollView: Roblox's built-in caret scrolling requires TextWrapped to be off. Facet reads the native cursor and measures its line to reveal it through the existing scroll authority; it does not synthesize caret movement or selection. Keyboard occlusion uses the
presenter's keep-visible transform after revealing a multiline viewport inside its ancestor scroller; physical OS keyboard and IME behavior must
be verified on the target device.

The presenter wires the control automatically. `api` exposes `submit()`,
`cancel()`, `editing`, `keepVisibleOffset`, `handleActivate(path, meta?)`,
`syncGeometry(rectOf, rootNode?)`, `focusGroups(rootNode)`, and
`bindActionSystem(system)` for composed hosts. `editing` and `keepVisibleOffset` are Compose readables: track them with `use` or inspect them with `:peek()`. Native invalid feedback uses a Compose timeline; reduced motion cancels the shake. `dump()` reports value, editing,
disabled, multiline, presentation, numericValue, validationError, clearVisible,
clearButtonMode, placeholderVisible, occlusionOffset, keyboardType, and submitLabel.

The field's mounted editor is at `<id>/Field` and its clear affordance at
`<id>/Clear`. A field wearing a label, hint, error line, accessory or number
presentation mounts its plate at `<id>/Input` inside a vertical stack
(`<id>/Label` above, `<id>/Message` below); accessories put the editor and clear
inside `<plate>/Row`, and a named `controlSize` puts the plate inside
`<plate id>+target`. `dump()` also reports label, requiredMark, hint, errorText,
hasError, controlSize, appearance, corners, leading, trailing, readOnly and
visibleLines. The mounted editor wears `selectOnFocus` only when it is supplied.

### `UI.NumberInput`

`UI.NumberInput { … }` -> the field's node: `UI.TextInput` with
`presentation = "number"` already chosen. It is the same engine (draft, commit,
chrome, focus and input story) under the name a chooser finds; supplying
`presentation` is refused. `value` (the editable string) and `numericValue` (the
committed number) are both caller-owned cells. Every `UI.TextInput` field
applies; `step`, `precision`, `stepButtons`, `prefix` and `suffix` are its own.
Without `precision`, a step button or a scrub rounds to the decimal places of
`step` and `min`, so three presses of `0.1` hold `0.3`, not a floating-point
remainder; typed numbers keep their own digits.
The step buttons mount at `<plate>/Row/Decrement` and `<plate>/Row/Increment`;
their semantic names are not localized. `dump()` adds step, precision,
stepButtons, prefix and suffix.

`scrub` (boolean or readable boolean, default false) lets a horizontal drag
across the editor move the number. Nothing happens before the shared press→drag
slop (6 px pointer, 14 px touch), so a tap still places the caret natively, and a
drag that is mostly vertical stays a scroll. Past it the edit the press opened
ends without a commit: a typed, uncommitted draft is discarded and the text
returns to the committed number's, which is where the drag starts. The number moves by one `step` per 8 px of total
travel from the press, through the step buttons' own rounding and bounds;
`onChange` reports each change and release commits once with reason `"submit"`.
Escape or ButtonB, losing the dragging input class, becoming disabled or
read-only, turning `scrub` off, and disposal cancel: the number and text
return to the press's snapshot and nothing commits. A caller write to
`numericValue` during a drag ends the drag, and the caller's number stands.

**Motion.** A rejected commit shakes the field as on `UI.TextInput`, and
reduced motion drops the shake. Step presses and scrubbing change the number
at once, with no animation.

```lua
local app = Facet.new()
local UI = app.controls
local draft, laps = Facet.Compose.cell("3"), Facet.Compose.cell(3)
local field
app.mount(function()
    return UI.NumberInput("Laps")({
        value = draft, numericValue = laps, min = 1, max = 99,
        stepButtons = true, label = "Laps",
        ref = function(record) field = record.api end,
    })
end)
```

### `UI.Chip`

`UI.Chip { … }` -> the chip's node. `ref` receives `{ api, dump }`; Chip
publishes no verbs, so `api` is its own record.
A sized Chip uses the same surface-environment requirement and hit-floor reservation as Button; an unregistered environment is refused.

A small toggleable tag/filter pill. It renders as a single rounded label (a
Button with
`pill` corners) whose surface reflects a caller-owned selection: activating it
(pointer tap, mouse click, keyboard Return, or gamepad ButtonA) flips the
`selected` cell and calls the optional `onToggle`. Use it for filter rows,
multi-select tags, and any place a compact on/off chip reads better than a
full-width toggle row.

Spec fields:

| field | type | required | meaning |
|---|---|---|---|
| `id` | `string` | no (default `"Chip"`) | the plate id; a supplied `controlSize` adds the `<id>+target` parent. |
| `label` | `string` | no (default `""`) | the text painted on the pill. |
| `enabled` | `boolean` or readable boolean | no (default true) | Disabled chips retain selection, leave the focus ring, and reject activation. |
| `selected` | a writable boolean cell | unless `onRemove` is supplied | caller-held selection, flipped by activation outside edit mode. A remove-only token omits it. Readonly selection is refused. |
| `animation` | animation policy | no | applies to the primitive Button plate and is checked against its supported properties. |
| `onToggle` | `(nextValue: boolean) -> ()` | no | called after each flip; requires selected. |
| `onRemove` | `() -> ()` | no | called when the tag is removed in edit mode; the caller removes the item from its keyed collection. |
| `editing` | boolean or readable boolean | with `onRemove` and `selected` | the caller's edit-mode cell (the `UI.Table`/`UI.RowActions` precedent). While true the tag shows a trailing close mark inside its one plate, and activating it, or Delete/Backspace while it holds the ring, removes it. A remove-only token without it is always editing. Requires `onRemove`. |
| `removeLabel` | `string` | no | the tag's semantic name while editing, default `Remove <label>`. |
| `removeFocusFallback` | bindable `string` | no | destination when no sibling remove target survives. |
| `controlSize` | `"compact" \| "regular" \| "large"` (bindable) | no | the shared local size rung: resolves to the theme ladder `controlSizes.<rung>.{height,paddingX}` as metric names. Absent = the 44px floor this control has always declared. A named rung paints smaller than the floor on purpose — a wrapper reserves the effective hit floor on both axes and centers the smaller pill. |
| `appearance` | `"standard" \| "utility"` (bindable) | no | visual emphasis, through a style tag. A chip's family is two words, not the Button's five: `emphasis`/`soft`/`link` describe an action's weight among actions, which a filter pill is not. |
| `corners` | `"pill" \| "square"` | no | the corner treatment, through the shipped `UI.corners` modifier. Absent = `"pill"`, exactly as before. |
| `leading` / `trailing` | blueprint | no | static content either side of the label (a count, a dot, an avatar). They are content, never a second focus stop — the chip keeps one activation surface, so every input class still reaches the same flip. With neither, the chip is byte-identical to the label-only pill it has always been. |

Removal is edit mode. A tag outside edit mode only selects and shows no close mark.
While `editing` is true the close mark sits inside the tag's one plate, one surface
in every theme, and is not a separate focus stop or target: activating the tag on
any input removes it, and so do Delete and Backspace while it holds the ring.
Removing a focused tag returns focus to the next removable tag, then the previous,
then the supplied fallback after its owner retires. The callback does not mutate
the caller's collection automatically.

The record `ref` hands back carries:

- `blueprint` — the node, which the constructor already returned to you. The
  four-input story is auto-composed by the presenter from the input contribution
  the chip attaches to its root, so no mount options are needed: a bare
  `app.mount` makes the chip reachable and activatable on pointer, touch,
  keyboard, and gamepad.
- `dump()` — a deterministic diagnostic table
  (`{ schema = "facet-chip-dump/1", id, label, selected, enabled, controlSize, appearance, removable, removeLabel }`); two calls with
  unchanged state are byte-identical.
- `dispose()` — releases the control and nothing else.

Invariants:

- **Selection is the caller's data model.** It must outlive the control, so the
  chip only reads and flips the passed-in `selected` cell; it holds no
  persistent state of its own.
- **One Activate site, every input class.** Pointer/touch taps and
  keyboard/gamepad Activate all route to the same flip through the presenter's
  auto dispatch — the chip binds no callbacks directly.
- **Reflect-only, no remount.** `selected` rides the `binding` authority, so
  flipping it repaints the surface with zero factory reruns.
- **Adaptation (three axes).** Touch gets the Button contract's 44px hit floor
  (a real layout minimum); pointer gets the free hover preview layer when the
  pointer class is live; keyboard gets a focus ring with Navigate→Activate; and
  a Large (ten-foot) display strengthens the focus profile. The chip owns no
  in-flight gesture, so there is no hot-switch state to carry or cancel.
- **No motion of its own.** A selection change repaints the plate at once. An
  `animation` policy you supply runs on the Button plate through the shared
  motion clock, where decorative motion snaps under reduced motion.

```lua
local app = Facet.new()
local UI = app.controls
local raining = Facet.Compose.cell(false)
app.mount(function()
    return UI.Screen("S")({
        UI.Chip("Rain")({
            label = "Rain",
            selected = raining,
            onToggle = function(on) print("rain filter:", on) end,
        }),
    })
end)
```

### `UI.RowActions`

`UI.RowActions { … }` -> the row's node. `ref` receives `{ api, dump }`; the
record's underscore-prefixed members (`_open`, `_close`, `_isOpen`,
`_settleTo`, `_closeMenu`, `_commitFirst`, `_handleActivate`,
`_pointerHandlers`) are the internal seams the coordinator and `UI.Table`
drive, not public API.

The control's state, tray formulas and subscriptions belong to the current
Compose owner. Removing the row releases them, closes its menu, and releases its
coordinator entry. Use a constructor name only when the application needs a
stable path:

```lua
local app = Facet.new()
local UI = app.controls
app.mount(function()
    return UI.RowActions("Row")({
        width = UI.fill(),
        content = UI.Text { text = "Saved experience" },
        trailing = {
            { id = "remove", label = "Remove", onAction = removeSavedExperience },
        },
    })
end)
```

A swipeable action tray around an arbitrary row (leading and trailing verbs such
as Delete, Flag, Mark Read): a lazily-mounted
tray on each edge, spring-animated reveal with proportional tray-button
growth, and the full cross-input gesture story — mouse drag, touch, keyboard
Delete/Backspace and Shift+Return, gamepad ButtonX/A/B, and full-swipe commit
— every action reachable on every input device.

A row with **no actions on either edge is a true inert passthrough**: `spec.content`
mounts completely unwrapped (no extra node, no extra `Instance`) — the perf
floor for a list where most rows carry no actions.

Spec fields:

| field | type | required | meaning |
|---|---|---|---|
| `id` | `string` | no (default `"RowActions"`), **required when `coordinator` is set** | the node id when either edge has actions; irrelevant to the inert-passthrough shape, since nothing wraps `content` then. When `coordinator` is present, omitting `id` is a build-time error: every row in a shared-coordinator list defaulting to the same literal `"RowActions"` id would collide. Table's own integration always supplies `"RowActions-" .. rowKey`. |
| `content` | `Node` | **yes** | the wrapped row. Slides horizontally over a revealed tray; otherwise painted exactly as authored. |
| `width` | dim? | no | the root's width. Absent leaves the root content-sized, which is what a standalone caller in a list wants; pass `UI.fill()` for a full-width row. |
| `leading` | `{ ActionSpec }?` | no | actions revealed by swiping right (or opening edge `"leading"`). `nil` = no leading tray; an empty table `{}` is a spec error (use `nil` for "none"). |
| `trailing` | `{ ActionSpec }?` | no | actions revealed by swiping left (edge `"trailing"`). Same `nil`/`{}` rule. |
| `fullSwipe` | `boolean \| { leading: boolean?, trailing: boolean? }` | no (default `true`) | whether a full swipe past the tray commits that edge's FIRST action outright (swipe to delete), per edge. Committing a **`role = "destructive"`** first action runs the slide-off + row-height-collapse sequence, fires `onAction` once, and leaves the row committed (a later gesture/tray-tap on it is a no-op — the owner is expected to remove it from the data model). Committing a **non-destructive** first action fires `onAction` immediately (the identical quarantined call a direct tray-button tap makes) and springs the row back to CLOSED — it never slides off-screen or collapses height, and stays fully interactive: a full swipe on a "Flag", "Archive" or "Mark Read"-shaped action must feel exactly like tapping that button in the revealed tray, never like a deletion. An edge with `fullSwipe = false` still opens/closes on a partial swipe; it can never commit past the tray. |
| `coordinator` | `table?` | no | the value `newRowActionsCoordinator` returns (single-row-open-at-a-time policy for a list of rows). A gesture crossing the axis lock, or an open, claims it — closing whichever other row is open — and this row releases its own claim on every close and on removal. Omitted, an instance only ever manages itself. **When present, `id` becomes required** (see the `id` row above). |
| `deletable` | `(() -> boolean)?` | no | consulted before a **destructive** commit: returning false refuses it, so a row the data model is not ready to lose stays put. |
| `editing` | readable boolean? | no | the caller's own edit-mode cell (`UI.Table`'s own `spec.editing` is the shipped precedent, and Table's `rowActions` integration passes its own straight through). Present AND true, on a row that declares a `role = "destructive"` action anywhere: a leading minus button appears (see below). Absent (the default), the minus never appears and this control costs nothing extra. Must be a readable when present — a plain `true`/`false` literal is a build-time error. |
| `externalGesture` | `boolean?` | no | `true` says a host (Table's own row grip) owns the raw capture, so this control mounts no internal Hit Grip of its own. |
| `env` | `Environment?` | no | live theme reactivity for each tray button's reserved width (`buttonPad`, `buttonMinWidth`), the same `spec.env` precedent `UI.Table` uses; font/size facts arrive fully resolved through `controller.textAt` instead. Absent degrades to `themeSnapshot.neutral()` — the neutral package at authored size. |

`ActionSpec`:

| field | type | required | meaning |
|---|---|---|---|
| `id` | `string?` | no (default: `label`) | must be path-safe (no `/`); becomes the tray button's id, `Action:<id>`. |
| `role` | `"normal" \| "destructive"` | no (default `"normal"`) | `"destructive"` paints the Button's own `role = "destructive"` (the shipped danger/onDanger style rule — no bespoke color). |
| `label` | `string` | **yes** | the action's semantic name, and the string the framework reserves the button's box for. **Drawn** in the tray only when the action declares no `icon` (see below), and always drawn in the action menu's own row. Never truncated by this control; a label-drawing button widens past the theme's `controls.rowActions.buttonMinWidth` floor rather than clip a long (e.g. pseudo-localized) label. **Accessibility rider:** icon-first replaces the tray button's engine `Text` with the icon's glyph, so on an icon action the word itself reaches the player through the action MENU row, not the tray plate — the menu is the reading of the tray, one activation away (`ButtonX` / Shift+Return / the framework's own tap path). |
| `icon` | `string?` | no | a `standard_icons` name. **The tray is icon-first**: an action that declares one wears its icon on the tray button at every width — settled and mid-swipe alike — and `label` becomes the semantic name only. The **menu row keeps the word**, so the reading of the tray is always one activation away. Carried as `compactLabel = { icon = …, prefer = true }` on the tray button and as `compactLabel = { icon = … }` (degrade-only) on the menu row; `Button.icon` itself is circle-only, so this never reaches that prop directly. Omitted is text-only everywhere, unconditionally. |
| `onAction` | `() -> ()` | **yes** | called when the action activates: a tap/click/Return/ButtonA on the revealed tray button, an activation of the action's own row in the menu, or — for a `role = "destructive"` action — keyboard Delete/Backspace. |

The record `ref` hands back carries `blueprint` (the node you already have),
`dump()` — a deterministic diagnostic table
(`{ schema = "facet-rowactions-dump/1", id, offset, openEdge, phase, menuOpen }`,
`phase` one of `"closed" | "open"`; `menuOpen` is the action menu's own open
state, independent of the tray) — and `dispose()`. When either edge has actions,
the node's own input contribution auto-composes the tray buttons' Activate
dispatch (pointer, touch, keyboard, gamepad) exactly like every other
interactive composite, so no mount options are needed.

**Keyboard Delete and the action menu.** When either edge declares a
`role = "destructive"` action, focusing anywhere inside the row's own
mounted subtree — `content`, a revealed tray button, or an open
menu row — and pressing **Delete or Backspace** commits the FIRST
destructive action found (trailing searched before leading) through the
same slide-off + collapse sequence a full swipe uses — never a bare
callback. No destructive action anywhere means the binding is not
registered at all (the key falls through to whatever else wants it). A
**gamepad ButtonX press, or keyboard Shift+Return**, same focus
scope, toggles a small popup menu (transient, focus-trapped, outside-tap
swallows and dismisses) listing every declared
action — leading then trailing, document order — as a focusable row. **The
menu is its own floating `presentModal` surface**, not a child measured
inside this row's own tree: a measured-child menu could grow past the row's own
content height and inflate the row — and, in a Table, the whole list — so
`tests/row_actions_input.spec.luau` pins a sibling row's solved rect
byte-identical whether or not this row's menu is open.
Activating one runs it exactly once (a destructive item through the same
commit sequence as Delete) and closes the menu; Cancel (gamepad ButtonB)
closes it without firing anything. **While the menu is open, it owns all
input**: opening it moves focus onto its own first row, and Delete/Backspace
go inert for as long as `menuOpen` is true — the menu's own Activate/Cancel
is the only way to act on ANY action, destructive or not, once it is up
(closing it, via Activate, Cancel, or a second Shift+Return, hands
Delete/Backspace back).

**`Shift+Return` is a modifier binding in the action system.** `action.bind`
(`src/input/actions.luau` and its real-engine adapter
`src/client/roblox_input.luau`) accepts `modifiers = { shift = true }`
on a keyCode binding, matched only while shift is held. The row's menu
binds `Return` with that modifier in the SAME sink=true, priority-10000
context Delete/ButtonX use, so the preemption of the base Activate
context's unmodified `Return` binding falls out of the existing
priority/Sink arbitration; with shift not held it is never a candidate, so plain
Return reaches the base Activate context untouched.
Gamepad bindings never declare `modifiers` and are unaffected by held
keyboard modifiers. `ctrl`/`alt` are not accepted on `modifiers` — the
action system only tracks `shift` distinctly from a single merged `toggle`
(ctrl+meta) group, so a `ctrl`/`alt` flag could type-check but never
actually match; wire `MODIFIER_GROUP` (`src/input/actions.luau`) first if a
future binding needs one.

**The edit-mode leading minus.** While `spec.editing` is a readable
that reads `true`, AND a `role = "destructive"` action exists on either
edge, a small circular button (diameter `controls.rowActions.editAffordance`,
28px; a `danger`-role disc, the same `role = "destructive"` mapping a tray's
own destructive button carries) appears in a LEADING gutter — the
row's own `content` is INSET by the gutter width to make room (it is the
content node's left padding, so it holds at every swipe offset of either
sign; the minus never collapses mid-swipe and never pops back at settle), and
the leading tray, if declared, shifts right by the same amount. The minus
paints OVER the sliding content, so a trailing swipe passes under it and it
stays pinned at the left for the whole gesture. It is a normal, focusable `UI.Button`
that activates via the standard tap/Return/ButtonA path, and it does **not**
delete directly: activating it opens the trailing tray,
revealing the destructive action one tap away (a
two-step: reveal, then confirm). Activating it while the trailing tray is
already open is a no-op. Absent `editing`, or a row with no destructive
action anywhere, this feature costs nothing — no extra `Instance`, no extra
reactive node. Turning `editing` off does not force-close an already-open
tray; the two are independent state (`editing` gates only the minus and its
gutter).

Invariants:

- **Lazy trays.** A tray mounts zero `Instance`s while closed (`UI.When`
  keyed on which edge, if any, is open) — the perf directive for a list where
  most rows sit closed.
- **A tray button's width is an independent, unconstrained measurement — never
  hand-measured at build time, and never read back from this reveal's OWN
  solved geometry.** Caching a label's width at build time is wrong forever (the
  engine has not laid anything out yet — the "cached before truth
  exists" bug class `docs/research/roblox-text-bounds-boot-window.md` warns
  about), and reading the width back from the tray's own solved rect is a
  feedback loop the moment the reveal itself is what shrinks that geometry.
  The shipped mechanism instead asks `controller.textAt(path)` — the framework's
  own live-subscribed font/size facts for that node, the same delivery shape
  `bindMotion` uses — for each button's label measured at UNLIMITED width
  (`text_metrics.measure(label, font, size, math.huge)`), plus the theme's
  `buttonPad`/`buttonMinWidth` (resolved via `spec.env`, see above). Because
  the measurement is unconstrained, it can never read back anything this
  reveal itself painted, so re-deriving it on every `syncGeometry` is safe by
  construction — it also means a long or pseudo-localized label that grows a
  button past `buttonMinWidth`, or a live preferred-text-size change, still
  reveals correctly and never freezes stale.
- **Labels are never truncated by this control.** The theme's
  `controls.rowActions.buttonMinWidth` (64px) is a floor, not a cap. An
  icon-first tray button measures the GLYPH it draws rather than the label it
  does not, so it settles at that floor.
- **Adjacent tray buttons are separated by `controls.rowActions.trayGap`** (an
  optional theme metric, filled from the package's own `space.xs` when it
  declares none) — two rounded plates drawn flush read as one merged slab. The
  gutters are part of the tray's travel distance too, so the far plate is fully
  uncovered at a full reveal.

```lua
local app = Facet.new()
local UI = app.controls
local row
app.mount(function()
    return UI.Screen("S")({
        UI.RowActions("Row1")({
            width = UI.fill(),
            content = UI.Text("Title")({ text = "Inbox message" }),
            trailing = {
                { id = "delete", label = "Delete", role = "destructive",
                  onAction = function() print("deleted") end },
                { id = "flag", label = "Flag", onAction = function() print("flagged") end },
            },
            ref = function(record) row = record.api end,
        }),
    })
end)
```

### `newRowActionsCoordinator`

`Facet.newRowActionsCoordinator() -> { claim, release, bindScroll }` — the
open-state coordinator for a list of `UI.RowActions` rows: **at most one row
open per surface**. It takes no collaborators: it is three closures over one
local. A plain `VStack`/`ScrollView` list builds its own instance
and passes it to every wrapped row's `coordinator` key; `UI.Table`'s own
`rowActions` wiring does the identical thing for its rows automatically. A row
built with no coordinator stays valid and only ever manages itself. **Every
row sharing one coordinator must pass its own unique `id`** (the example
below does, via `item.id`) — `UI.RowActions` refuses to build, at build time,
a coordinator-sharing row with no `id` at all, since every such row would
otherwise default to the same colliding `"RowActions"` id.

Return surface:

| member | type | meaning |
|---|---|---|
| `claim` | `(instance) -> ()` | called by a row itself (a gesture crossing the axis lock into horizontal, or an open): closes whichever OTHER row is currently claimed — that row's own animated close, a spring, or an instant snap under reduced motion — then claims `instance`. `instance` is the exact record the row's `ref` handed back — no separate id. Claiming away also closes that row's action menu, which is state independent of its tray. |
| `release` | `(instance) -> ()` | called by a row on every close and on removal. Idempotent: releasing an instance that does not currently hold the claim (or nothing is claimed) is a silent no-op. |
| `bindScroll` | `(controller, path: string) -> (() -> ())` | wires `controller.observeScroll(path, ...)` so **any** scroll movement on that host — no distance or velocity threshold — closes whichever row is currently open. Returns the unsubscribe. |

```lua
local app = Facet.new()
local UI = app.controls
local coordinator = Facet.newRowActionsCoordinator()
local close, node, handle = app.mount(function()
    local rows = {}
    for _, item in items do
        table.insert(rows, UI.RowActions(item.id)({
            width = UI.fill(),
            content = rowContent(item),
            trailing = { { id = "delete", label = "Delete", role = "destructive",
                           onAction = function() remove(item) end } },
            coordinator = coordinator,
        }))
    end
    return UI.Screen("S")({ UI.ScrollView("List")(rows) })
end)
local unbindScroll = coordinator.bindScroll(handle.controller, "/S/List")
```

### `newDragSession`

`Facet.newDragSession(opts) -> session` — the pure, engine-free drag-session
model. Roblox's `UIDragDetector` owns
cross-input drag *motion* at the adapter edge; this session owns the framework
*policy* the engine does not: which drop targets are legal for a payload, the
enter/leave hover contract, the predicted result while hovering, and honest
cancellation. It never yields and touches no DataModel — the detector (or a
headless driver in tests) feeds it pointer positions in the same coordinate
space as the target rects.

`opts` fields: `payload` (opaque), `source` (source node path), `targets`
(`{ { id, rect = {x,y,w,h}, accepts: (payload)->boolean? } }`), and the optional
`onEnter(targetId)`, `onLeave(targetId)`, `onPredict(targetId?, payload)` hooks.

Methods (colon-called): `session:update(x, y) -> targetId?` re-evaluates hover,
firing enter/leave exactly once per change; `session:drop(x, y) -> DropResult`
(`{ kind = "dropped", targetId, payload }` over a legal target, else
`{ kind = "rejected" }`) then goes inert; `session:cancel(reason?) ->
{ kind = "cancelled", reason }` fires a leave for the hovered target first, then
goes inert; `session:retarget(targets)` swaps geometry mid-drag (a scroll host
moving under the drag) and re-evaluates hover at the last position;
`session:state() -> { active, hovered, source }`. Overlapping targets resolve to
the **last** array match (later array order = higher z in paint order). An
`accepts` returning false makes a target illegal (no enter fires). Every terminal
state (drop/cancel) makes the session inert.

### `interactionTokens`

`Facet.interactionTokens` — the shared per-input-class interaction thresholds.
**One** place decides whether a press became a
drag, because a promotion threshold is a device fact, not a control fact: a
finger's resting jitter is ~10 px and a mouse's is ~1 px, so no single number
serves both, and a copy per consumer means a device round that retunes touch has
to find every copy.

- `interactionTokens.dragPromotionPx` — `{ pointer = 6, touch = 14, keyboard = 0,
  gamepad = 0 }`. The ratified values ship as framework defaults; the non-pointer
  classes carry `0` because a keyboard or gamepad drag is armed by an explicit
  verb, so there is no travel to measure.
- `interactionTokens.dragPromotionRangePx` — the ratified tuning bands
  (`pointer` 4–8, `touch` 10–18), published so a review can check an override
  against the range it was ratified inside.
- `interactionTokens.classForPointerType(pointerType)` — `"mouse"`/`"pen"` →
  `"pointer"`, `"touch"` → `"touch"`; anything absent or unknown → `"pointer"`.
- `interactionTokens.promotionPx(class, overrides?)` — the gate in px for an
  interaction class. An unknown class falls back to the pointer gate, never to
  zero: a gate that is too small still asks the player to move, while a zero gate
  would eat every tap on that device.
- `interactionTokens.promotionForPointerType(pointerType, overrides?)` — the same
  gate keyed on the engine's pointer type instead, i.e. `promotionPx` composed
  with `classForPointerType`. This is the one to reach for inside an event
  handler, where what you hold is the event's own pointer type.
- `interactionTokens.promoted(dx, dy, pointerType, overrides?) -> boolean` —
  the **magnitude** test. A 5 px diagonal on a mouse is 7 px of travel and reads
  as a drag to the player; two independent axis tests would still call it a tap.
- `interactionTokens.touchDragArm` — `{ holdMs = 320, slopPx = 12 }`. A finger
  arms a drag by **time**; everything else arms by travel. The distances above
  answer "has this press become a drag yet", which is the right question once a
  press is the framework's to interpret — but on touch it is asked too late to
  be the only question, because a finger's press is contended from the first
  frame by the scroller underneath it and by any swipeable row beside it, and
  all three gestures begin identically. So a touch press claims nothing until it
  has been held still for `holdMs`, and travelling `slopPx` first releases it for
  good to whatever is underneath. `slopPx` is deliberately **smaller** than the
  `touch` promotion gate, so a released gesture can never also have promoted.
  A mouse or a pen is not arbitrated at all: it arms on the press, as it always
  has. `UI.draggable`'s `declineTouch` now reaches the engine's own acquisition
  as well, so such a source never arms on a finger at any hold.

- `interactionTokens.contextPriority` — `{ baseScreen = 1500, engagedBase =
  3000, modalStep = 500 }`. The
  **responder priority bands** every presented Facet surface arbitrates at
  (`src/present/presenter.luau`'s own live authority), published so a
  consumer arbitrating its OWN input contexts against a Facet-presented
  surface's — the shape `app.presentModal` exists to keep collision-free — knows
  where the ceiling is without reading a source comment: a context sitting AT
  or above `baseScreen` can sink a Facet screen it does not own. `baseScreen`
  is every presented `kind = "screen"` surface's floor; `engagedBase` is an
  engaged-from-passive or modal surface's floor, strictly above it; each modal
  stacks `modalStep` above the previous one's depth.

The decision is made against the pointer type of the **event in hand**, never
against the live interaction-class set: a hybrid device delivers mouse and touch
events to the same node, and the class set cannot say which one this press was.
`UI.Table`'s reorder threshold reads this module; its touch reorder rides the
edit-mode grip (which presents as a mouse pointer), because the row body declines
the capture on touch so the native `ScrollingFrame` keeps the pan.

### `newDragVelocity`

`Facet.newDragVelocity(opts?) -> tracker` — the rolling release-velocity
tracker. `opts.windowS` defaults to **0.1 s**.

- `tracker:push(x, y, t)` — record a position. **Time is injected**: this module
  never reads `os.clock`, which is what makes a flick replayable frame by frame
  in the headless suite. Samples older than the window are dropped, but the
  buffer never falls below two, so a gesture that paused before release answers
  a real zero instead of "no samples".
- `tracker:velocity() -> vx, vy` — px/s, **first-vs-last across the retained
  window**. Zero for fewer than two samples or a non-advancing clock: never a
  division by zero, never an infinity handed to a spring.
- `tracker:reset()`, `tracker:sampleCount()`, `tracker:last()`,
  `tracker:windowSeconds()`.

One frame of movement is mostly noise — a flick and a stop can report the same
number — so the window is what makes the settle motion continue without a visible
seam. **Read it at release before any state reset**, and seed a non-gestural
cancel with zero through the same consumer path: one path means a keyboard cancel
and a thrown card cannot drift apart in feel.

### `newAutoscroll`

`Facet.newAutoscroll(opts?) -> model` — the pure drag-to-edge autoscroll model.
It answers a **delta**; it scrolls nothing, reads no clock and
re-solves nothing. `model:step(input) -> { delta, state, justArmed }` where
`input` is `{ now, pointerPos, hostRect, canvasPos, maxScroll }` and `state` is
`"idle" | "dwelling" | "active" | "exiting"`.

Defaults (ratified, all overridable through `opts`): `bandH` **40 px** when the
host is wider than it is tall and **44 px** when it is taller — the framework
picks between them from the host's own shape, and `model:options()` reports the
tuning actually in force — `dwellS` 0.3, `vMin` 100, `vMax` 500, `rampS` 0.15,
`exitEaseS` 0.08.

| Rule | Behavior |
|---|---|
| Membership | the **pointer point**, never the proxy's bounds — the band and the drop hit-test must read one coordinate, or the row you are scrolling toward is not the row the verdict is about. |
| Dwell | 300 ms continuous presence in **one** band; leaving both bands or crossing to the other resets, jitter inside a band does not. A flick-through therefore never arms, with no velocity special case. |
| Speed | `v(p) = vMin + (vMax - vMin)·p`, `p` = penetration 0..1 — the player steers the rate with the finger already steering the drop. |
| Ramp | effective velocity eases 0 → `v(p)` over `rampS` (quad ease-out) from the **arming instant**. |
| Coast | leaving the band decays the velocity to 0 over `exitEaseS` instead of cutting it — and so does crossing **straight to the other band**, which still restarts the dwell (`state` goes back to `"dwelling"`) while the old velocity eases out under it. Reversing direction mid-ease reads better than a hard velocity flip. Arming supersedes any live coast, because the start ramp already begins at zero. |
| Clamp | at a canvas end the delta is trimmed to zero and the state **stays** `"active"`: pulling back and pushing again does not re-pay the dwell. |
| Inert | `maxScroll <= 0` → nothing arms and no affordance shows, because the scroll cannot happen. |

`justArmed` is true on exactly the frame arming happens, once per arming — it is
the feedback hook (one tick at scroll-start, not one per frame). Reads:
`model:state()`, `model:band()`, `model:penetration()`, `model:options()`,
`model:reset()`.

**The host's obligation**: apply the delta through `controller.scrollTo`, then
re-run the drop hit-test **in the same frame** (`registry.refreshTargets()`).
A tick-based re-resolve lags about two rows at `vMax`. `UI.VirtualList` does this
for you. Non-pointer schemes have no autoscroll path at all: focus-follows-
navigation already scrolls the host.

### `newDragRegistry`

`Facet.newDragRegistry(opts) -> registry` — a surface's live
`UI.draggable`/`UI.dropTarget` set plus the **one** session every input class
drives. The renderer builds one per surface automatically and
exposes it as `controller.dragRegistry()`; construct your own only for a host
that owns its own acquisition.

`opts` are `core` and `rectOf` (required — the renderer's **live** rects), plus
the optional `zOf` (paint-order tie-break for overlapping targets), `now`,
`feedback`, `proxy`, `motionClock`, `promotionPx`, and the host's two live
predicates: `isPathLive(path)` (a retiring subtree paints its exit but is not a
drag surface; answered at resolution time, so a re-entry mid-exit is eligible the
same frame) and `isSourceEnabled(path)` (whether a source is enabled right now).
Absent, both read as always-live / always-enabled, which is what a standalone
registry wants. **Every collaborator is optional and each degrades exactly one
behavior** — no `motionClock` means terminals resolve instantly instead of
flying, no `proxy` paints nothing, no `feedback` drops the semantic events — but
none of them can change a verdict.

Every member is a **dot** function (`registry.pointerDown(path, pos)`), unlike
the colon-called pure models beside it — a `registry:` call would silently pass
the registry table as the path.

- Registration: `registry.registerSource(path, decl) -> unregister` and
  `registry.registerTarget(path, decl) -> unregister`. The renderer calls these
  for every mounted `UI.draggable` / `UI.dropTarget`; a host that owns its own
  registry calls them itself, and each returns the closure that removes the
  declaration again.
- Acquisition: `registry.pointerDown/pointerMove/pointerUp/pointerCancel(path,
  …)` and `registry.detectorHandlers(path)` (the `UIDragDetector` form). Both
  funnel into one promotion test and one session; the engine's detector merely
  decides when it starts reporting.
- Non-pointer: `registry.arm(sourcePath)`, `registry.armTo(targetPath)`,
  `registry.commit()`, `registry.cancel(reason?)`. `armTo` aims the same session
  at the target's **centre**, so legality, enter/leave and the verdict are
  literally the pointer code path — there is no second policy path to drift.
  **You do not have to call any of them for the default pickup** (ADAPT-16):
  a gamepad/keyboard Activate on a focused `UI.draggable` that
  **nobody else wanted** arms it, the focus ring aims it (the presenter feeds
  `armTo` from focus), the next Activate commits at that aim, and Cancel
  (ButtonB / the surface's cancel verb) puts it back down. "Nobody else wanted it"
  is structural: the node's own `onActivate`, a Toggle's flip and every control
  contribution are offered first, so a draggable that declares `onActivate` keeps
  it — the same rule `UI.VirtualList` states as `grabOnActivate = reorderable and
  onActivate == nil`. Only a session armed this way is committed or cancelled by
  the generic verbs; a control's own grab stays its own.
- Live geometry: `registry.refreshTargets()` re-resolves every target rect and
  re-runs the hover at the last pointer position. Call it in the same frame as a
  scroll write; the renderer already calls it after every re-solve.
- Reads: `registry.verdict` (a readable of
  `{ targetId, overId, legal, reason, mode }`), `registry.heldSource` (a
  readable of `string?` naming the source path a live session is carrying — the
  renderer binds it to write the `dragHeld` state; see "The held source empties"
  under `UI.draggable`), `registry.isActive()`, `registry.session()`,
  `registry.payload()`, `registry.mode()`, `registry.sourcePath()`,
  `registry.pointerPosition()`, `registry.interactionTarget()`,
  `registry.dump()`.
- `registry.onUpdate(fn) -> unsubscribe` — "the session began / moved / ended",
  fired on every hover update and every terminal, with `{ active = false }` once
  the session is gone.
- `registry.setCollaborators({ now?, feedback?, proxy?, motionClock?, promotionPx? })`
  — the injection point for collaborators that only exist once a surface is
  presented. Each is read live, so a swap takes effect on the next gesture, and
  passing **`false`** clears one (nil cannot: it does not survive table
  iteration). The presenter wires every surface automatically; this is how a
  degraded host opts a pre-wired collaborator back out.
- `registry.surfacePresented(kind)` — a modal presenting mid-drag **cancels** the
  session (a focus trap and a drag proxy cannot coexist).
- `registry.dispose()` — cancels the live session, kills detached flights, clears
  sources/targets/watchers and disposes its state. The renderer disposes the
  registry it built; a hand-built one is yours.

`verdict` carries more than the session's hover on purpose. `newDragSession`
skips illegal targets entirely, so it alone cannot say "you are over row 7 and it
is refusing you because `FULL`". The registry hit-tests targets geometrically as
well and publishes `overId` + `reason` alongside the legal `targetId` — the
session still owns every enter/leave and the drop, and the extra read is what
lets a row paint its refusal with the game's own code.

Semantic events reach `opts.feedback.emit(event, info)`: `select` on pickup or
arm, `commit` when a legal drop resolves, `land` when the payload reaches its
target, `reject` (once, with the `reason`) on an illegal drop, `dismiss` on
cancel.

### `touchGestures`

`Facet.touchGestures` — normalization and composition for the native `GuiObject`
touch events. The engine *recognizes*
gestures; this module never re-recognizes from raw samples.

`touchGestures.normalize(kind, args) -> Gesture` turns one engine gesture
callback into a stable value object. **`args` is the callback's POSITIONAL
arguments as an array**, in the order the engine passes them — `{ positions }`
for `TouchTap`, `{ positions, state }` for `TouchLongPress`,
`{ positions, totalTranslation, velocity, state }` for `TouchPan`, and so on for
`TouchPinch`, `TouchRotate` and `TouchSwipe`. Handing it a named-key table
normalizes to an empty gesture, because there is nothing at `args[1]`. The
result is `{ kind, state, positions, totalTranslation?, velocity?, scale?,
rotation?, direction? }`, mapping the `UserInputState` names
(`Begin`/`Change`/`End`) to `began`/`changed`/`ended` (taps and swipes are
instantaneous, state `"none"`), and tolerating any missing optional field
without erroring.

`touchGestures.newArbiter(opts?) -> arbiter` decides which stream owns the
interaction when several fire at once: `arbiter:feed(gesture) -> "own" |
"preempted" | "pass"`, `arbiter:owner() -> kind?`, `arbiter:reset()`. Policy:
pinch/rotate (two-finger) preempt pan; a began longPress preempts tap; swipe and
tap are instantaneous and never own; ownership releases on the owning gesture's
`"ended"` frame. **`opts` is reserved**: the policy is fixed, and a non-empty
table is refused at construction naming that fact, rather than accepted and
ignored.

### `spatial`

`Facet.spatial` — the **contract** for spatial data a normalized pointer event
may one day carry. This is a seam, not a feature: no adapter produces
this data today, every event Facet currently delivers is flat, and the framework
makes no claim about headsets or world-space input. It exists so that adding
spatial input later is an adapter change rather than a change to every control.

The compatibility promise is the whole point. A pointer position is
`{ x, y, pointerType? }` and every handler reads `pos.x` / `pos.y`. Spatial data
is only ever **added beside** those fields, so a handler written today keeps
working unchanged; a handler that wants the third dimension asks for it.

```lua
-- an adapter would build this; a handler reads it (or ignores it)
local pos = Facet.spatial.extend({ x = 120, y = 44 }, {
    ray   = { origin = { x = 0, y = 2, z = 0 }, direction = { x = 0, y = 0, z = -1 } },
    hit   = { x = 0, y = 2, z = -5 },
    pose  = { position = { x = 0, y = 2, z = 0 } },
    handedness = "right",     -- left | right | unknown
    phase = "changed",        -- began | changed | ended | cancelled | none
    target = "GarageSurface", -- opaque; Facet forwards it and never interprets it
})

if not Facet.spatial.isFlat(pos) then
    local s = Facet.spatial.of(pos)   -- { hit?, ray?, pose?, handedness, phase, target?, distance? }
end
```

`spatial.normalize(raw) -> Spatial?` clamps platform data into the contract and
**never errors**: a zero-length direction drops the ray rather than dividing by
zero, `NaN`/infinite coordinates are not positions, unknown vocabulary values
fall back to `"unknown"`/`"none"`, and an event with no spatial content at all
returns `nil` rather than pretending to be spatially targeted. `distance` is
*derived* from the pose and the hit, never taken on trust. `spatial.extend`
returns a new value and leaves the input untouched; `spatial.of(pos)` reads the
spatial payload back off a position (`nil` for a flat one — it is the reader the
example above uses); `spatial.isFlat(pos)` is `true` for every event Facet
produces today; `spatial.describe(pos)` gives a one-line diagnostic.

The two vocabularies are frozen sets, published so an adapter and a consumer
agree on what a value may be: `spatial.PHASES` is
`{ began, changed, ended, cancelled, none }` and `spatial.HANDEDNESS` is
`{ left, right, unknown }`. `none` and `unknown` exist so a partial platform
event still normalizes to a well-formed value rather than a nil every consumer
has to guard.

The matching render-target half is `client.surface_target`: flat,
two-dimensional Facet on a `SurfaceGui`, on a
part a player can walk up to and use. It is not a declarative Part/Model layout
and it is not VR, ray, hand, or gaze support — see
[`../extending/new-platform-mode.md`](../extending/new-platform-mode.md) for the
physical gate a spatial claim would still have to pass.

`target_contract.FUTURE.surface` keeps the questions that work had to answer,
split into `answered` and `openQuestions`, because where the next implementer
looks for the questions is where the answers belong.

---

## Client entry points

Everything above hangs off the `Facet` table. These client modules do not: they
are the code that touches Roblox `Instance`s, real input and real device facts,
so exporting them would put engine requires in the shared/server graph. A client
script requires each **directly**:

```lua
local host = require(ReplicatedStorage.Facet.client.host)
```

**This list is the contract** (constitution §12). These modules are
public surface with the same compatibility promise as anything above; everything
else under `src/` is library-internal, and a consumer requiring one of those is
outside the boundary rule. `tools/lune/check_boundary.luau` holds the same list
in code and is the authority — this section and the constitution are reconciled
to it, never the other way round.

**Start with `client.host`.** It composes four of the others into the one
bootstrap and drives the frame correctly; reach for `screen_target`,
`roblox_env` and `roblox_input` individually only when you are building
something the host does not shape.

#### `client.scene`

`client.scene` re-exports the pinned Compose Roblox host package. Its
`createRuntime()` returns a native Compose runtime with `runtime.constructors`,
`mount`, `mountFragment`, and `dispose`. Use it to compose owned 3D content inside
`controller.stageHost(path).contentRoot()`. The stage content root is borrowed;
Compose owns the nodes and subscriptions it creates beneath it. Dispose the
native scene before dismissing its Facet surface.

```luau
local scene = require(ReplicatedStorage.Facet.client.scene)
local stage = controller.stageHost("/Screen/Preview")
local runtime = scene.createRuntime()
local Host = runtime.constructors
local dispose = runtime.mount(function()
    return Host.Model { Name = "Preview", Host.Part { Anchored = true } }
end, stage.contentRoot())
```

This shares Facet's exact Compose dependency, rather than installing another
runtime copy. Facet still owns the Stage's rectangle, camera and lighting through
its documented content seam. Ordinary interface layout, controls and input use
Facet's public UI surface.

**One model, both halves.** Sharing the dependency is what makes the interesting
thing possible: the same cells drive the interface and the world, with no bridge
between them and nothing to keep in step by hand.

```luau
-- OUTSIDE any app: shared state belongs to the scene, not to a surface
local lifetime = Facet.Compose.createOwner()
local palette = Facet.Compose.cell("sage")

local app = Facet.new({ ... })                    -- the interface reads `palette`
local world = require(ReplicatedStorage.Facet.client.scene).createRuntime()
local Host = world.constructors
local stopWorld = world.mount(function()          -- ...and so does the world
    return Host.Part({
        Anchored = true,
        Color = function(use)
            return PALETTES[use(palette)]
        end,
    })
end, workspace)
```

A `UI.Picker` writing `palette` repaints the Part; nothing subscribes to anything
else. Four rules worth knowing before you build on it:

- **Cells belong to no runtime.** They are values with lifetimes, not children of
  a tree. Create shared ones under an owner you make yourself, outside every app
  and every world, and dispose that owner LAST — after the apps and after the
  world runtime, so nothing is still reading a released cell.
- **Batching is process-wide.** `Compose.batch` groups writes across every
  runtime in the session, so one batch settles the interface and the world
  together rather than leaving a frame where they disagree.
- **Each runtime has its own frame clock.** Two trees can repaint on different
  ticks, so do not assume a write lands in both on the same frame; assume only
  that both see the same value.
- **Ownership is still Compose's.** Use `adopt` for a node Compose must destroy
  and `decorate`/`borrow` for one it must not, and bind any external handle
  (an animation track, a connection) to an owner.

`examples/virtual_monitors` is this shape end to end: its room, its per-card
worlds and its avatar preview are all built with this runtime, and the cells the
interface writes — palette, rotation, auto-spin, light/dark — are the same cells
the world reads.

#### `client.world_anchor`

`world_anchor.new(host, opts) -> { anchor, dispose }` measures a world object for a
screen-overlay radial menu. Require `ReplicatedStorage.Facet.client.world_anchor`.
`host` is the result of `client.host.new()`, or its `{ core, presenter }` pair.
The binding samples once on construction and then on `presenter.onTick`; it creates
no frame driver or GUI instances. Own the binding in the same scope as the menu.

| Option | Meaning and default |
|---|---|
| `target` | Required BasePart, Model, or Player, or Readable of one. A Player resolves its current Character, including after respawn. A nil Readable value is temporarily unavailable. Pass a specific part or smaller model to exclude accessories or tools. |
| `padding` | Finite fraction from 0 to 1 of the measured radius; default 0.15. Zero tightly encloses the bounds, 0.15 adds 15%, and 1 doubles the opening radius. |
| `offscreen` | `"hide"` (default) retains the radial-menu bounds behavior; `"retain"` projects the target center for marker placement, including a direction beyond the viewport for targets behind the camera. Retained anchors include `onscreen` and use `clearance = 0`. |
| `occlusion` | Boolean, default false. When true, one default-filter Workspace raycast from camera to target center hides a target behind another queryable object. This is center visibility, not partial mesh visibility; the local character and decorative parts are not automatically filtered. |
| `camera` | Optional Camera or Readable; defaults to the current Workspace camera and follows camera replacement. Intended for screen overlays, not ViewportFrames or billboard canvases. |

`anchor` is a Readable `{ x, y, clearance, visible }` in Facet window coordinates.
The center is the midpoint of the projected bounding rectangle; clearance encloses
all eight projected bounding-box corners, multiplied by `1 + padding`. This conservatively measures
part/model bounds, including transparent parts and model accessories, rather than
visible mesh pixels. With default options, a missing, empty, removed,
behind-camera, near-plane-intersecting, or offscreen-center target publishes
`visible = false`; RadialMenu dismisses and releases capture. Disposing the binding
also invalidates the anchor and disconnects its frame hook. Respawn/reappearance
updates the anchor but does not reopen a dismissed menu.

Padding scales with the object’s apparent size as camera distance, field of view,
viewport size, or model size changes. For a minimum opening, set the radial menu’s
`clearance` to a theme metric. The larger of that minimum and the measured opening
wins; theme and accessibility rules still determine button sizes. The anchor has
no separate pixel-based minimum radius option.

`Facet.new` forwards host options, so an application reaches its own core
through the `newInputSystem` seam and pairs it with `app.presenter`.

```luau
local roblox_input = require(ReplicatedStorage.Facet.client.roblox_input)
local worldAnchor = require(ReplicatedStorage.Facet.client.world_anchor)

local core
local app = Facet.new({
    newInputSystem = function(built)
        core = built
        return roblox_input.newSystem(built)
    end,
})
local UI = app.controls
local focus = worldAnchor.new({ core = core, presenter = app.presenter }, {
    target = itemModel,
    padding = 0.15,
})

local close = app.mount(function()
    local menu
    local node = UI.RadialMenu("QuickActions") {
        items = actions,
        anchor = focus.anchor,
        clearance = "controlSizes.large.height", -- optional theme-based minimum opening
        preset = "donut",
        center = "empty",
        launcher = false,
        follow = "idle",
        ref = function(record) menu = record.api end,
    }
    local connection = prompt.Triggered:Connect(function() menu.open() end)
    Compose.cleanup(function() connection:Disconnect() end)
    return UI.Screen { node }
end)
```

Mount the menu in a screen covering the object's projected position. Dispose the
binding with `focus.dispose()` when the surface goes away.

The game owns the prompt, proximity/permission rules, and server validation of
commands. Watch `menu.isVisible` to hide the prompt through the entire visual
exit, then restore it. `isOpen` changes as soon as closing begins.

```luau
-- inside the same component, after the node is built
Compose.watch(function(use)
    prompt.Enabled = not use(menu.isVisible)
end)
```

The Showcase's **Quick actions → Item** demonstrates a native prompt, model
rotation, resizing, and pickup. Its invisible local viewer supplies proximity in
the avatar-free Showcase; production games use their existing character.

#### `client.host`

`host.new(opts?) -> { core, env, adapter, inputSystem, presenter, dispose }` —
**the bootstrap.** Builds a core, an environment BOUND to the engine, a
`screen_target` adapter, a `roblox_input` system and a presenter, then connects
**one** `RunService.PreRender` that calls `presenter.tick(dt)` and then
`presenter.refresh()`.

`Facet.new(opts?)` builds a host with these same options and wraps it in an
application. Reach for `host.new` directly only when you want the six pieces
without the application surface.

```luau
local host = require(ReplicatedStorage.Facet.client.host)

local h = host.new({ displayOrder = 100 })
h.presenter.present(myScreen)
-- per-frame work of your own goes here, never on a second connection:
h.presenter.onTick(function(dt) end)
-- ...and when the surface goes away:
h.dispose()
```

**Why both halves of the frame.** `refresh()` re-solves whatever the frame
dirtied; `tick(dt)` advances the MOTION CLOCK that every transition, toast
schedule, spring and timer rides. A `refresh`-only drive leaves that clock
frozen — a toast never expires, a transition never completes — and nothing says
so, because a frozen clock and a settled one look identical in a dump. `PreRender`
and not `Heartbeat`: Heartbeat runs *after* render, so everything the tick drives
arrives a frame late.

**Your per-frame work goes on `presenter.onTick`**, which returns its own
unsubscribe. A second `RunService` connection in a consumer is the bug class the
single frame source exists to prevent.

| Opt | Meaning |
|---|---|
| `nativeStyle`, `style`, `parent`, `autoLocalize`, `themePackage`, `displayOrder` | forwarded verbatim to `screen_target.new` |
| `surface` | where the surface lives: `{ kind = "screen" }` (the default), `{ kind = "billboard", target, canvas, studsOffset?, alwaysOnTop?, maxDistance? }`, or `{ kind = "surface", target, face, canvas, maxDistance?, onAdorneeLost? }`. A non-screen kind builds `billboard_target` or `surface_target` instead |
| `keyboardNavigation` | forwarded to the presenter: arrow-key focus travel |
| `clock` | a motion clock the presenter should use instead of building its own |
| `now` | the presenter's wall clock (`() -> number`), for a spec that needs two presses either side of the echo window |
| `newCore`, `bindEnv`, `newAdapter`, `newInputSystem`, `connectFrame`, `mountComponent` | seams. Each replaces one construction step, so a headless spec or an Edit-mode preview can drive the same host. `connectFrame` takes the per-frame function and returns its disconnect. `newInputSystem` receives the core, which is how an application that needs the core — for `client.world_anchor`, say — gets hold of it |

`dispose()` is idempotent: it takes back the frame connection **first**, then
unbinds the environment — a frame landing between the two would drive a presenter
whose environment has stopped answering. It disposes only what the host built;
whatever you presented is yours to `dismiss`. A construction that throws part-way
unwinds everything that had already succeeded before re-raising.

#### `client.screen_target`

`screen_target.new(opts?) -> RenderTargetAdapter` — the production `ScreenGui`
target. **One adapter per root**: its instance map and capture/cursor state are
adapter-scoped, so an adapter must never host two roots. `destroyRoot`
releases the tree.

| Opt | Meaning |
|---|---|
| `style` | the compiled token style to paint from; default is Facet Neutral |
| `isReducedMotion` | **deprecated** (0.9.0, removed no earlier than 0.10.0): `() -> boolean`, consulted for engine-side motion. Still accepted, and now OR-ed with the fact the renderer pushes from the environment through `adapter.setReducedMotion` — so it can force reduced motion ON, never off. `billboard_target.new(opts.isReducedMotion)` forwards it and retires with it. |
| `parent` | host the root under this Instance instead of `PlayerGui` (the Edit-mode preview and any harness without a LocalPlayer) |
| `rootFactory` | `(screenId) -> { gui }` — swap only the ROOT container; everything below is target-agnostic flat rendering (this is how `billboard_target` is built) |
| `forceScrollFallback` | render `ScrollView` nodes as plain clip hosts with no engine scrolling — the A/B switch that exercises the fallback path deliberately |
| `forceDragFallback` | make `setDragDetector` answer nil so the raw pointer-capture path runs instead |
| `nativeStyle` | the paint path. **Absent is native StyleSheet paint** — the library default since 2026-08-21 (`native_style.DEFAULT_ENABLED`). `true` says the same thing explicitly; `{ model?, handle?, host?, theme?, transitions? }` configures it (native transitions default on; `transitions = false` opts out). **`false` is the opt-out**, per target, and wins over everything: it takes the explicit-write path, which is also where an engine without StyleSheets lands |
| `themePackage` | the installed `ThemePackage` whose chrome recipes decide decoration slots; the theme controller swaps it at runtime |
| `displayOrder` | the `DisplayOrder` every root this target creates gets — where the whole target sits against the game's own `ScreenGui`s. Absent means 0 (the engine's default), which is why a game's hand-made surfaces float above Facet's unless someone says otherwise. The presenter still layers its own surfaces above one another from this floor |

#### `client.billboard_target`

`billboard_target.new(opts) -> RenderTargetAdapter` — the same adapter with a
`BillboardGui` root, for a Facet surface in the world. `opts` is
`{ parent, adornee, canvas = { w, h } }` (all three required and asserted) plus
`studsOffset?`, `alwaysOnTop?`, `maxDistance?`, `style?`, `isReducedMotion?`.
Parent it under `PlayerGui` for input; anywhere else is display-only.
`billboard_target.canvasRect(canvas)` is the matching viewport rect to feed the
environment. It deliberately **removes** two optional adapter methods
(`setPointerHandlers`, `setTouchGestureHandlers`), which is the target contract's
own degrade mechanism — a billboard says honestly what it cannot do. One adapter
per billboard, same rule as above.

#### `client.surface_target`

ScrollView and virtualized collections use native ScrollingFrames on this surface.
The virtual-monitors Studio drive verifies wheel scrolling, paged window updates,
and preserved scroll position across detail selection. Touch inertia and spatial
pointer input require separate verification.

`surface_target.new(opts) -> RenderTargetAdapter` — the same adapter with a
`SurfaceGui` root, for flat Facet **on a part a player can walk up to and use**.
`opts` is `{ parent, adornee, face, canvas = { w, h } }` — all four required and
asserted — plus `maxDistance?`, `onAdorneeLost?`, `style?`, `nativeStyle?`, `displaySize?`,
`isReducedMotion?`. `surface_target.canvasRect(canvas)` is the matching viewport
rect to feed the environment, and the consumer sets
`env:set("presentationSpace", "world")`, which this target is the first thing in
the library to make true.

Four of its choices are unusual enough to state, and each was measured rather
than assumed (the record is
`artifacts/example-games-and-standalones/spike/world-surface.md`):

- **`face` has no default.** For an unrotated part `Enum.NormalId.Front` is the
  *−Z* face, so a camera looking along −Z sees `Back`. A surface on the wrong
  face renders perfectly, measures perfectly, and can never be clicked — which is
  indistinguishable from an engine that does not support this at all.
- **`parent` must be this client's `PlayerGui`, and the reason is ownership.** A
  `SurfaceGui` parented into a Workspace part does take input, and it also
  replicates to every player. Facet does not build shared UI.
- **The adornee must have `CanQuery = true`**, asserted at construction. With it
  false the surface renders at full size and receives nothing, silently.
- **`AlwaysOnTop` is pinned `false` and is not an option.** With it true a player
  operates the terminal through a wall — measured, not inferred.

It exposes `stageHost` through the same owned ViewportFrame content seam as a
screen. See the local `examples/virtual_monitors` showcase for two live scenes
inside world-fixed surfaces.

It **removes** three optional adapter methods — `setPointerHandlers`,
`setTouchGestureHandlers`, `foreignHost` — and passes
`forceScrollFallback = true`. Native StyleSheet paint follows the screen target's
`nativeStyle` option, including its default and explicit opt-out. That is the contract's own
degrade mechanism, and each withholding matches a question
`target_contract.FUTURE.surface` still lists as open. One adapter per surface,
same rule as above.

`onAdorneeLost` exists because **a destroyed part is invisible through
`.Adornee`** — the property still names it, with the canvas size unchanged. The
adapter watches the instance's own lifetime and calls you once; resigning the
surface is your decision.

#### `client.roblox_env`

`roblox_env.bind(env) -> unbind` — populates and keeps live every engine-owned
fact on a `Facet.newEnvironment` (viewport, safe insets, topbar geometry,
keyboard occlusion, input preference and capabilities, display class,
accessibility preferences, locale). This is the one place allowed to read
`UserInputService`/`GuiService` facts. The unbind is yours to own.

#### `client.roblox_input`

`roblox_input.newSystem(core) -> ActionSystem` — the same interface as
`Facet.newActionSystem`, implemented over real `InputContext`/`InputAction`/
`InputBinding` instances, so the presenter runs unchanged on either. Arbitration
(priority and sinking) is the ENGINE's job here; this adapter never
re-implements it. `client.host` builds one for you; return it from the host's
`newInputSystem` seam to supply your own in place of the headless system.

#### `client.roblox_resources`

`roblox_resources.bind(provider) -> unbind` — the transport behind
`app.newResourceProvider`. An application binds it for you unless
`options.bind` replaces it; bind it by hand only for a provider you built
yourself. It drains `provider.pendingRequests()` and fulfils
each key through `ContentProvider:PreloadAsync`, answering
`provider.complete/fail` with the request's generation. Honest about
cancellation: releasing a handle prevents unstarted work and makes a late
completion stale, but nothing can stop an in-flight engine fetch. The unbind is
yours to own.

#### `client.theme_controller`

`theme_controller.install(adapter, package, opts) -> controller` — materializes a
theme package's sheet, links it at the target root, resolves the snapshot and
commits it. Documented in full under [`themes`](#themes) (the controller's
members, the swap transaction, the fallback story). Every capability check runs
**before** the first mutation, so a failed install leaves the target and the
environment untouched.

`opts` in full — `env` is the only unconditionally required field:

| Opt | Meaning |
|---|---|
| `env` | **required** — the resolved snapshot rides it as the `themeMetrics` fact |
| `core` | **required whenever `selectBy` is given**: the paradigm subscription needs an owner. Optional otherwise. An application fills both `env` and `core` in for you when you call `app.installTheme` |
| `theme` | initial theme name; default `package.style.defaultTheme` |
| `selectBy` | `{ touch = pkg, pointer = pkg, gamepad = pkg }` — profile-conditional package selection; the positional `package` is the default for any unmapped class |
| `selectBySettleSeconds` | how long a profile must hold before it counts as settled (default 0.25 s) |
| `selectBySettle` | the settle-timer seam, for tests |
| `facts` | explicit resolve facts; default is to read them from the environment |
| `overrides` | dotted metric paths, recorded as deliberate theme-independence |
| `rootGui` | the target's root, for an adapter that cannot report one |
| `host` | explicit sheet host; otherwise reuse a designer sheet in ReplicatedStorage or keep runtime sheets under `PlayerGui.FacetStyleHost`, a non-rendering ScreenGui with `ResetOnSpawn = false`. An explicit host must provide the required lifetime |
| `sheetModel` | a prebuilt sheet model (else one is derived from the package) |
| `nativeStyle` | the materializer seam (tests and tools inject it) |
| `forceFallback` | exercise the fallback paint path deliberately |
| `transitions` | native paint transitions (default on); `false` opts out; reduced motion suppresses them live |
| `preflightFonts` | preload the package's fonts before committing (default true) |
| `calibrate` | `(keys) -> { [key]: number }`, the font-calibration seam |
| `fontFiles` | family → engine font file, for a package shipping its own faces |
| `warn` | where a one-off warning goes |

#### `client.environment_preview`

`environment_preview.new(env) -> handle` adds reversible display and input
previews to an existing environment. Bind the platform through
`roblox_env.bind(handle.source)` so live facts continue updating behind overrides.
The source is a write sink exposing `set(key, value)` and `batch(body)`.

- `setProfile(value)`: `automatic`, `desktop`, `phone`, `tablet`, or `tv`.
- `setOrientation(value)`: `portrait` or `landscape`; affects phone and tablet.
- `setInput(value)`: `automatic`, `pointer`, `touch`, or `gamepad`.
- `setTextSize(value)`: `automatic` or an engine text-size name (`Medium`,
  `Large`, `Larger`, `Largest`), previewed as `preferredTextOffset` from
  `preferred_text.FALLBACK_OFFSETS`.
- `setTransparency(value)`: `automatic` or a `preferredTransparency` from 0 to 1.
- Setters return false for an unknown value. Defaults are automatic profile,
  portrait orientation, and automatic input, text size and transparency.
- `reset()`: every override back to automatic over the latest platform facts.
- `apply()` reapplies the chosen preview after a demo changes environment facts.
- `dispose()` is `reset()`: it restores the latest platform facts. Disconnect the platform binding
  first when tearing down the host.

Phone and tablet bound the viewport to the existing device-profile dimensions,
limited by the host window. Desktop and TV use the host window's dimensions.
Rendering stays at 1:1 pixels with the normal native hit testing; a small window
can therefore keep a tablet or desktop preview compact. Enlarge the window to
inspect wider layouts. TV applies distant viewing, overscan and gamepad defaults;
phone and tablet default to nearby touch, desktop to nearby mouse and keyboard.
Automatic input uses the selected profile's defaults, or live input when the
profile is also automatic. An explicit input choice persists across platform
input events and profile changes. Input simulation changes capabilities and
presentation; it does not synthesize physical input or a mobile software keyboard.
Accessibility and application chrome remain owned by the host.

The Showcase Settings display section uses this binding with standard Pickers.
Changing previews re-solves the mounted demo through the existing environment,
presenter and focus system. Previewing is a layout check, not physical-device evidence.

#### `client.edit_preview`

`edit_preview.start(Facet, opts) -> handle` — Studio Edit-mode preview: builds
its own application against a device profile, mounts a component and draws a
labelled device frame around it. `opts` is
`{ parent, component, profile?, style? }`. `component(app) -> node` runs inside
the preview application's own mount, so its cells and watches are released with
the preview. The handle is
`{ app, controller, profile, setProfile(name), refresh(), dispose() }`. Taking the
library table as a positional first argument is deliberate (constitution E-11):
dev tooling is injected like a composite so a plugin can hand in the game's own
library table. **Always `dispose()` before saving the place** — it disposes the
preview application, which takes back its frame connection and its root, and
destroys the decoration `ScreenGui`; without it the preview furniture is saved
into the place.

#### `client.motion_driver`

`motion_driver.bind(presenter) -> unbind` — the one binding between a presenter's
frame tick and the engine render clock: it connects `presenter.tick(dt)` to
`RunService.PreRender`. PreRender rather than Heartbeat, because Heartbeat runs
*after* render and would add a frame of latency to every visual the tick drives.
Binding the same presenter twice is refused loudly.

Two things stay the caller's:

- **The unbind.** Nothing here watches presenter lifetime — disposing a presenter
  does not disconnect its binding, and the module keys presenters strongly, so a
  discarded unbind keeps ticking (and retaining) a surface nobody presents. Keep
  the returned function next to whatever owns the presenter.
- **The budget.** A PreRender handler blocks the rendering pipeline until it
  returns, so everything inside one tick — the clock's transaction, every motion
  write, transitions, the toast schedule — spends the frame's *render-thread*
  budget.

#### `client.haptics`

`haptics.new(opts?) -> adapter` — **opt-in, default off.** The one adapter that
turns semantic feedback events into Roblox haptics. It is a *subscriber* to the
bus, never part of it: Facet still plays nothing, and nothing under `src/`
outside `src/client/` names a haptic symbol or requires this module (pinned by
`tests/haptics.spec.luau`). Every engine fact it rests on is recorded, with
sources, in `docs/research/2026-08-12-haptics-engine-facts.md`.

```lua
local haptics = require(ReplicatedStorage.Facet.client.haptics)
local hap = haptics.new({ enabled = playerSettings.haptics })
hap.bind(presenter)            -- the COMPLETED press, and every changed choice
hap.attachButtons(screenGui)   -- the property route: the press going DOWN
```

`bind(presenter) -> unbind`, `attachButtons(root) -> detach`,
`setEnabled(on)`, `isEnabled()`, `support()`, `reprobe()`, `diagnostics()`,
`dispose()`. `opts` is `{ enabled?, profile?, now?, selectIntervalSeconds?,
parent? }` plus five injection seams (`instanceNew`, `floatCurveKey`,
`inputService`, `hapticService`, `enums`) that exist so the whole adapter is
provable headless. `adjustIntervalSeconds` is an accepted alias for
`selectIntervalSeconds`.

##### The three phases

Facet has three interaction phases, and each one has a **different owner of the
moment it fires**. That is the whole shape of this adapter:

| phase | the moment | owner | reaches it through |
|---|---|---|---|
| `press` | the press goes **down** | the **engine** | `GuiButton.PressHapticEffect` — a reference is handed over and never played from here. Reachable only from `decorate`, never from the bus. |
| `release` | the press **completes** | the bus | the presenter stamps `reason = "activation"` on the event a control's activation raises, and that event exists **only** when the activation completed. Checked **first**, so a completed press is the release phase's whatever verb it names. |
| `select` | a **value changed** | the bus | the `select` / `adjust` verbs on an event that is **not** an activation. |

**The cause outranks the verb.** A verb says *what* happened; `reason =
"activation"` says *a control was pressed*, and a press completing is not a
choice moving. So a control declaring `activation = "select"` feels `settle`
when it is pressed and `tick` when its value changes — one sensation per thing
that actually happened. `pressSpecFor` answers `nil` for both of the select
phase's verbs: they have no down edge, because a choice has not moved yet when
the finger lands.

`haptics.activationIsFelt(verb) -> boolean` is the *other* question — is this
control felt at all — and it is deliberately a different function. The select
phase's verbs have no down edge, so one shared answer would cost those controls
their completed edge too.

##### The same-instant collapse

A pointer press has two moments a hand can tell apart. A keyboard or gamepad
press does not: the IAS `Activate` action resolves on the key going **down**, so
the completion event is raised in the same instant the engine would play the
button's own press effect. Two sensations at one instant are one blurred pulse.

For an activation the presenter marks non-pointer (`context.source == "action"`),
the bus therefore contributes exactly **one** sensation — `release` — and drops
anything else it would have played for that path inside
`haptics.SAME_INSTANT_SECONDS` (one frame at 60 Hz). Dropped, never deferred.
`diagnostics().collapsed` counts it, separately from `coalesced` (the select
phase's rate limit): one is *too soon after the last tick*, the other is *the
same gesture*. A pointer activation is never collapsed — the negative control
that keeps the rule from swallowing the ordinary case.

What this cannot do is silence the engine's own press effect in that instant.
Whether it fires at all for a non-pointer press is undocumented, and only a hand
can answer it.

**No double pulse, and the guard is structural.** The two edges are separate
sensations with separate owners, so the rule is that the bus never plays
the PRESS phase — which it cannot, because that phase is unreachable from
`onEvent`.

**A canceled press is silent structurally.** `GuiButton.Activated` does not fire
for a press dragged away from, so the presenter emits no completion and this
module is never asked. There is no cancellation branch in the file and there must
not be one.

**This adapter adds no input listener.** When a press begins, completes or is
abandoned is decided once, in the presenter/responder path, for pointer, touch,
keyboard and gamepad alike. `ContextActionService` never appears here;
`UserInputService` appears only as the device probe's service name.

##### `client.sensory_profile` — what each phase feels like

Engine-free (a `WaveKey` is plain data; `FloatCurveKey` construction happens in
the adapter), so the waveforms are pinnable on a host with no engine.

```lua
export type WaveKey = { timeMs: number, intensity: number, mode: "Constant" | "Linear" | "Cubic" }
export type PhaseSpec =
      { kind: "custom", name: string, keys: { WaveKey } }
    | { kind: "preset", effect: string }   -- a HapticEffectType name
    | { kind: "silent" }
export type SensoryProfile = { press: PhaseSpec, release: PhaseSpec, select: PhaseSpec }
```

`DEFAULTS`, `FALLBACK`, `PHASES`, `MODES`, `EFFECT_TYPES`, `MIN_PEAK`,
`MAX_DURATION_MS`, `resolve(partial) -> SensoryProfile`, `fallbackFor(phase)`,
`key(spec)`, `label(spec)`.

**The three shipped waveforms**, Facet's own, tuned for the role each phase
plays:

| phase | name | character | keys (`timeMs`, `intensity`, `mode`) |
|---|---|---|---|
| `press` | **contact** | one short, crisp tap when the action goes down | `{0, 0, Linear}` · `{6, 0.9, Cubic}` · `{30, 0, Linear}` |
| `release` | **settle** | a lighter, rounder answer when the action completes | `{0, 0, Linear}` · `{10, 0.5, Cubic}` · `{34, 0, Linear}` |
| `select` | **tick** | the smallest audible-to-the-hand step for a changed choice | `{0, 0, Linear}` · `{4, 0.35, Linear}` · `{16, 0, Linear}` |

Every peak stays at or above `MIN_PEAK` (`0.3`) because Roblox records that
intensity below `0.1` may not trigger anything on some clients — an authored
subtlety under that floor is a silence that reports success. Every waveform is
over inside `MAX_DURATION_MS` (`34`), so rapid interaction cannot overlap two
pulses perceptibly. The tables are frozen all the way down.

**Per-phase override and silence.** `profile` is a *partial* merged over the
defaults; anything you do not name keeps Facet's:

```lua
haptics.new({
    enabled = true,
    profile = {
        press = { kind = "custom", name = "thud", keys = { … } },
        release = { kind = "preset", effect = "UIHover" },
        select = { kind = "silent" },
    },
})
```

Validated at construction, so a misspelled phase, a `custom` with no keys, an
unknown effect name, or `{ kind = "preset", effect = "Custom" }` is an error you
read at the call site rather than a silence you discover on a device.

**The fallback, and its limitation.** If a client cannot build a custom waveform,
the phase falls back to a stock preset — never to a bare `Custom`:
`press → UIClick`, `release → UIHover`, `select → UIHover`. Roblox ships exactly
three UI presets and `UINotification` means "draw attention away from gameplay",
which is neither a released button nor a changed choice — so **under fallback
`release` and `select` are the same sensation**, distinct only by cause, while
press keeps `UIClick`'s crisp character.
`diagnostics().phases[phase].fallbackActive` reports it, and is set only once the
preset has actually been built and handed back.

**`HapticEffect`, never `HapticService:SetMotor`.** Roblox's own class reference
says the service "has been superseded by `HapticEffect` … For new work, use
`HapticEffect` instead", and `SetMotor`'s value range, persistence and zeroing
requirement are undocumented — a motor you cannot prove stops is a stuck-rumble
bug with no test.

**The press phase takes the property route.** `GuiButton.PressHapticEffect` is
an assignable reference the *engine* fires, so `attachButtons` hands one over to
every `GuiButton` under the root (now and later, via `DescendantAdded`) and this
module never calls `Play()` on it. An **undeclared** control gets the press
phase — Facet's `contact` waveform; a control that **declared** its own verb
still gets that verb's mapped preset, so a Buy button and a Delete button feel
different. A **disabled** control
(`Active == false`, or `Interactable == false` under native styling) is skipped,
and one that *becomes* disabled has its reference cleared on the next sweep — a
disabled affordance holding a press effect is a promise it does not keep.
`HoverHapticEffect` is deliberately left unassigned.

**The map is total over the closed twelve**, and five map to nothing —
`activate` (the engine plays it), `arrive` (every chase settle; per-frame noise),
`cancel` (the absence of feedback *is* the signal), `dismiss` and `supersede`
(not player-caused). The silences are written out explicitly, so a thirteenth
verb would surface as a visible gap rather than a silent drop.

| Verb | Route | Sensation |
|---|---|---|
| *(undeclared)* / `activate` | property (`PressHapticEffect`), **down edge** | the **press phase** — `contact` |
| any felt verb, `reason = "activation"` | bus, **completed edge** | the **release phase** — `settle` |
| `select` · `adjust`, **no** `reason` | bus, **rate-limited** (default 60 ms; coalescing *drops*) | the **select phase** — `tick` |
| `select` · `adjust`, down edge | — | *none — a choice has not moved yet* |
| `pickup` · `commit` · `land` | bus | `UIClick` |
| `reject` · `celebrate` | bus | `UINotification` |
| `arrive` · `cancel` · `dismiss` · `supersede` | — | *deliberately none, on both edges* |

`select` and `adjust` are named in `haptics.PHASE_VERBS`. They have **no down
edge**: the select phase is reachable from a value change only, so a
select-declared button is handed no press effect and its completed press is
answered by `settle` like any other. Their `MAP` rows are purely the totality
ledger — the map stays total over the twelve so a thirteenth verb surfaces in
`unmappedVerbs()` — plus the preset for every verb the phases do not claim.
**One limiter serves both**: two limiters would let a control alternating the
pair (which a scrubbed picker does) pass both and fire at full rate.

`haptics.pressSpecFor(verb, profile?) -> PhaseSpec?` is the pure resolver behind
the property route: the press phase for an undeclared control, the verb's preset
for a declared one, `nil` for the select phase's two verbs, and `nil` for
`"none"` and for every verb the map silences.
`haptics.activationIsFelt(verb) -> boolean` decides the **release** edge
instead, so a control that is deliberately unfelt is unfelt on both while a
select-declared one keeps its completion.

**The invisible tap band feels the same as the face.** A control solved smaller
than the touch floor gets a second `GuiButton` — `FacetHitExpander`, a sibling at
`hostZ - 1` — and the Roblox adapter mirrors the host's declared verb and its
`Active` / `Interactable` onto it at every seam that can change either. Without
that mirror the band would read as *undeclared and enabled* and would be felt
outside a control that declared `none` or that is disabled.

Effects are **pooled by sensation** — one Instance per distinct resolved
`PhaseSpec` (keyed by `sensory_profile.key`), plus one per mapped verb the phases
do not claim — and never constructed per fire (Roblox documents a "fewer than 100
simultaneous effects" budget). Measured with Facet's defaults: **8** live
Instances for every phase and every verb at once, flat across 40 rounds of
firing. A custom effect gets `SetWaveformKeys` **exactly once, at build**.

The enum is resolved defensively **by name** before anything is constructed and
**never falls back to `Custom`** — a `Custom` effect with no waveform is a
guaranteed silent no-op. A *deliberate* `Custom` is the opposite case and is
safe: the waveform keys are built **first** and the Instance only afterwards, so
a client that cannot make a `FloatCurveKey` never ends up holding a keyless one
— it gets the phase's documented preset instead. If the client cannot create the
class at all (`support() == "absent"`) the attempt is made **once**, not per
event, and no later failure overwrites the engine's own words about why.

**Every effect is `Stop()`ped *and* `Destroy()`ed** when it is released —
`setEnabled(false)`, `dispose()`, and the shared press effect's teardown. A pooled
effect is parented into the DataModel at construction, so dropping the Lua
reference ends nothing. `pooled` and `decorated` are **derived
from the live state** at read time — the press effect included — so the instrument
counts what exists rather than what it remembers building.

**A detach is local.** `attachButtons` records its decorations **per root**, so the
function it returns clears only that surface's buttons: no other attached surface
is stripped, none is re-walked, and the shared press effect survives (it is torn
down at `setEnabled(false)` / `dispose()`, the two moments the adapter genuinely
stops). A button under two attached roots keeps its reference until the last one
lets go, and a root **destroyed without a detach** releases itself through
`Destroying` rather than being retained. The record is a cache, not the authority:
`decorate` re-reads `PressHapticEffect` and restores it if something else — a
second adapter, a recycled instance — cleared it.

**After `dispose()` the adapter is inert, never throwing.** `setEnabled(true)`,
`bind` and `attachButtons` all become no-ops (`bind`/`attachButtons` still return a
safe release function), so nothing can open a subscription or a `DescendantAdded`
connection that the drained `dispose()` will never close.

**`support()` is a lattice, not a boolean**: `supported | unsupported | unknown |
blocked | absent`. There is no capability API for `HapticEffect` at all, and the
only probe on the platform belongs to the superseded service and answers `false`
both for "this device has no motor" and for "no gamepad connected *yet*" — so
touch and the pre-first-gamepad state are **`unknown`** ("attempt it, expect
nothing, publish no platform claim"), never `unsupported`. It re-probes on
`GamepadConnected` / `GamepadDisconnected` / `LastInputTypeChanged` rather than
caching at boot. Pooled effects are parented to `Workspace` by default, *matching
the official sample* — the docs state no parenting requirement and this module
claims none; pass `parent` to override or `parent = false` to parent nothing.

**There is a demo you can feel it in.** The showcase fixture `sensory-feedback`
carries a `Play haptics on this device` switch — **default off, and the library's
default does not move**: the demo opting in is a different decision from the
library opting in, and the panel says so on screen. Flipping it constructs
`haptics.new({ enabled = true })` and hands it both seams, then reports which of
three things happened — **Requested** / **This platform says no** / **Could not
determine** — with `support()` printed verbatim beside the verdict. It says
*requested*, never *played*, because whether a `HapticEffect` fired is not
readable from game code. Both seams matter: `attachButtons` makes the DOWN edge
felt and `bind` makes the completed edge and every changed choice felt.

The same fixture carries a **calibration panel**: one row per phase, a profile
selector (Facet defaults | preset fallback | silent) and a live pulse counter.
`Release` and `Select` are controls that declare `activation = "none"`, so each
puts exactly one cause on the bus and is judged alone; `Press` has no driver and
cannot have one, because the engine owns its moment — holding it and dragging off
before release is also the cancellation proof. The counter prints what the
adapter played per phase and says **in words** that the press count is the
engine's and unreadable, rather than printing a `0` that would read as "it never
fired". Procedure: `artifacts/navigation-and-menus/review-packet.md` row P8 and
`artifacts/release-candidate-review/haptics/device-review-packet.md`.

The performance lab takes `select:haptics=on` and adds a counter line
(`haptics=on built=… pooled=… plays=… coalesced=…`). A whole dense-scroll pass
with the adapter bound moves **no** haptic counter: it is event-driven, and a
scroll produces no feedback verbs.

**What is device-owed.** Roblox documents this repository's own development
platform as one where controller haptics are unsupported, so the dev machine can
only prove "never throws", and
**Studio cannot feel anything** — the effects run locally there with no motor
involved. Whether anything is *felt* on a gamepad, whether it is felt on a phone,
whether the three waveforms are distinguishable and appropriate by hand, and
whether the player's own haptics setting silences it
(`UserGameSettings.HapticStrength` is `RobloxScriptSecurity` on read — game code
cannot see it) are open `PENDING_DEVICE` rows recorded in
`artifacts/release-candidate-review/haptics/defaults.md` §8.

#### `client.gamepad_contention`

The engine's legacy control scripts hold gamepad `ButtonA` (as `jumpAction`) and
the arrow keys (as `RbxCameraKeypress`) through ContextActionService at priority
2000, and **no `InputContext` priority outranks a CAS binding** — the two are
different arbitration spaces, measured live. This module is the seam for the two
things a client can actually do about it, plus the probes that say whether it
matters on the machine you are on.

```lua
local gamepad_contention = require(ReplicatedStorage.Facet.client.gamepad_contention)
if gamepad_contention.legacyStackActive() then
    warn(gamepad_contention.describeContention())
end
```

- `disableLegacyControls(playerModuleParent?, player?) -> (boolean, string)` —
  **UI-ONLY PLACES ONLY**; it turns off avatar input. Returns whether ButtonA is
  believed uncontended, and a status that says why. It asks
  `iasPlayerScriptsActive()` first: where the flag is on there is no legacy stack
  to disable, so it touches nothing and answers
  `true, "inert: IAS owns PlayerScripts"`. Otherwise it disables the whole
  control module (`true, "disabled"`), else unbinds `jumpAction` *and confirms
  the binding is gone* (`true, "unbound"` — an `UnbindAction` on an unbound
  action only warns, so a `pcall` succeeding proves nothing), else
  `false, "unavailable"`.
- `legacyStackActive() -> boolean`, `cameraKeysContended() -> boolean`,
  `traversalKeyContended() -> boolean`, `iasPlayerScriptsActive(player?,
  waitSeconds?) -> boolean` — behavioural probes. They answer different questions
  and one can be false while another is true; measured 2026-08-15,
  `RbxCameraKeypress` held the arrows in a session where `jumpAction` was not
  bound at all. `iasPlayerScriptsActive` reads the artifact of the flag rather
  than the flag: `Player.InputContexts.{Character,Camera,Vehicle}Context` exist
  only once the player scripts are on IAS.
- `describeContention() -> string` — the whole recorded truth, for a log line or
  a doctor check. The real fix for a shipping game is
  `Workspace.PlayerScriptsUseInputActionSystem`, which is not *scriptable* — no
  code can read or set it — but **is** declarable in a Rojo project file with the
  pinned toolchain, which is how every Facet place carries it. This string says
  so.
- `freedJumpAction(before, after) -> boolean` — the pure verdict the fallback
  uses, exported so the rule is provable without a live ContextActionService.

See [`../guide/07-input.md`](../guide/07-input.md) for the full story.

#### `client.responder_effects`

The presenter's first-responder model is engine-free and resolves through IAS
priority and `Sink`. This is the one engine-level side effect it cannot perform
itself: while an **exclusive** (sinking) Facet surface is up, Roblox's mobile
touch controls must be hidden, or the thumbstick and jump button sit under your
modal.

```luau
local responder_effects = require(ReplicatedStorage.Facet.client.responder_effects)
-- `core` comes from `host.new().core`, or from an application's
-- `newInputSystem` seam; `presenter` is `app.presenter`.
local unbind = responder_effects.bind(core, app.presenter)
```

`bind(core, presenter) -> unbind` observes `presenter.exclusiveSurfaceActive`
and drives `GuiService.TouchControlsEnabled`, restoring the **prior** value on
release and on unbind. The suppression is **refcounted at module scope**,
because the engine property is one property: two binders share one suppression,
and only the last release restores — a per-binder hold meant the second binder
captured the already-suppressed value as "prior" and put the controls back
hidden. A write the engine accepts without applying is not counted as a
suppression (the acquire reads the property back).

`suppressionCount() -> number` reports how many binders are holding, for
diagnostics. `readTouchControls` / `writeTouchControls` are the injection seams
the headless suite drives; production never passes them.

## Motion

### `motion`

`Facet.motion` — the motion authority: all value motion in
one pure, engine-free place, stepped by an injectable clock. It contains no
`RunService`, no `os.clock` inside the solver, and no engine globals at all, which
is what makes every motion contract below assertable frame by frame in the
headless suite. The client binds `clock:step()` to `RunService.PreRender` at the
adapter edge; tests and benches script a clock.

**Authority.** Motion drives **signals** only. It never writes solver-owned
geometry (no `Size`, no per-frame re-solve) and never writes a native-sheet-owned
paint property. Downstream, a motion value reaches the screen through the
renderer's **presentation** channel (transform/transparency)
or through any ordinary reactive binding — the authority audit must stay clean
while motion runs.

```luau
local h = require(ReplicatedStorage.Facet.client.host).new()
local clock = Facet.motion.newClock(h.core, { motionPolicy = h.env:get("motionPolicy") })

local x = clock:spring(0, "object")        -- a Compose readable of a number
x:setTarget(240)                           -- interruptible: any frame, any target
x:onSettle(function() print("landed") end)

h.presenter.onTick(function(dt) clock:step(dt) end)
```

#### `motion.newClock(core, opts?) -> clock`

`core` is the services object a host builds (`host.new().core`). `opts.now` is a
`() -> number` (seconds, monotonic; defaults to `os.clock`) and
`opts.motionPolicy` is a Compose readable of a string — pass
`env:get("motionPolicy")`, whose
values are `"full"` and `"reduced"`. The policy is read **live**, so a player
toggling reduced motion changes the next re-target without a remount.

- `clock:step(dt?)` — advances every active motion and commits **every** output
  write inside **one core transaction per stepped frame** (one flush, however many
  springs moved). With no argument, `dt` is derived from `now()`.
- `clock:activeCount()` — motions currently being stepped. **Rest costs zero**: a
  settled motion detaches itself, and a step with nothing active returns before it
  opens a transaction.
- `clock:stats()` — `{ steps, writes, transactions }` for leak and perf
  assertions. The invariant is **`transactions <= steps`**, with equality exactly
  when no frame aborted before the commit phase: a throwing per-frame callback
  aborts that step before a transaction is opened, so counting one would report a
  flush that never happened (measured: 30 steps under a persistently throwing
  live target → 0 transactions). Assert `<=`, not `==`, or the assertion fails in
  precisely the scenario worth asserting on.
- `clock:lastError() -> string?` — the last error a step quarantined, nil when
  none. The instrument for a wedged clock, mirroring `core.lastError`.
- `clock:isReduced() -> boolean` — the live reading of `opts.motionPolicy`, so a
  caller that has to branch (a control choosing an instant snap for a collaborator
  it does not own) asks the clock rather than re-reading the environment.
- `clock:dispose()` / `clock:isDisposed()` — owner-held; inside a component write
  `Compose.cleanup(function() clock:dispose() end)`.
  Disposal releases every value the clock built, so core counters return to
  baseline across mount/reset churn.

#### `clock:animate(source, classOrCurve, opts?) -> MotionValue`

Bind motion to a caller-owned Compose readable of a number. The
returned numeric MotionValue starts at the current source value, then retargets
whenever that cell or formula changes. A spring preserves its current position
and velocity when interrupted; a named curve preserves position and follows its
registered duration. If a name is registered in both vocabularies, the curve wins,
as it does for `presenter.withAnimation`.

`opts` accepts `scope`, `kind`, `quantum`, `reducedMotion`, and `eps`. The motion
options have the same meaning and defaults as `clock:spring` and `clock:tween`;
`scope` owns the result and its subscription together. Disposing the result or the
clock also removes the subscription, without disposing the source. The source
must initially contain a finite number. An invalid later value retains the last
valid target, records `clock:lastError()`, and recovers on the next valid change.
Malformed options and a disposed scope are refused before allocating resources.

```luau
local animated = clock:animate(amount, "object")
local tint = Compose.formula(function(use)
    return { from = "control", role = "accent", blend = math.clamp(use(animated), 0, 1) }
end)
local swatch = UI.Box { tint = tint, width = UI.fill(), height = 40 }
```

This theme-role tint remains live when the theme changes. Clamp a blend because
an intentionally underdamped spring can overshoot. Decorative bindings snap under
reduced motion; informational bindings retain the clock's quantized policy. This
is an explicit numeric binding, not an automatic subtree animation modifier or
an RGB interpolation API. Normal MotionValue verbs remain available; the next
source change retargets after a manual `stop`, `snap`, or `setTarget`.

#### `motion.registerClass(name, params)` and the class vocabulary

A **motion class** is a named `{ dampingRatio, response }` pair — `dampingRatio`
is overshoot (1.0 = critically damped), `response` is how quickly the value
reaches its target in seconds (**not** a duration: settle time emerges from the
physics). Five ship: `container` (1.0 / 0.35), `object` (1.0 / 0.28), `reward`
(0.7 / 0.18), `decay` (1.0 / 0.5), `dismiss` (1.0 / 0.2), the exit twin of
`container` — a structural transition's exit runs on it by default (see
`exitClass` under **Structural transitions**), so a closing surface dips out
about 1.7x faster than it opened.

**Overshoot is earned**: `reward` is the only under-damped built-in, and it is
non-gestural by definition — liveliness elsewhere comes from inherited gesture
velocity, never decorative bounce.

Call sites cite a class **name**. An inline `{ dampingRatio = 1, response = 0.3 }`
literal at a `clock:spring` / `clock:chase` / timeline call site is **refused**
with an error pointing at `registerClass`, so a design system has exactly one
place to tune feel. An unknown name is an error with a did-you-mean and the full
registered list — never a silent fallback. `registerClass` validates
`dampingRatio` in `(0, 2]` and `response` in `(0.05, 2]`; re-registering a
built-in name is the sanctioned ±30 % tuning dial. `motion.resolveClass(name)`,
`motion.classNames()`, `motion.isRegisteredClass(name)` and `motion.resetClasses()`
round out the registry.

#### `motion.registerCurve(name, spec)` and the curve vocabulary

The **other** motion vocabulary, and the one a design handoff arrives in.
A **motion curve** is a named `{ duration, style, direction? }` — a duration in
seconds and an easing shape — where a class is physics with no authorable
duration. Reach for a curve when the duration *is* the requirement: a spec in
milliseconds, a UI beat that must land with an audio cue, a cooldown that has to
arrive **on time** (a spring approaches its target asymptotically and cannot).
Reach for a class for anything a finger interrupts, because a re-targeted tween
hard-cuts velocity to zero where a spring inherits it.

`style` is **Roblox's own `Enum.EasingStyle` vocabulary**, spelled lower-camel:
`linear`, `sine`, `back`, `quad`, `quart`, `quint`, `bounce`, `elastic`,
`exponential`, `circular`, `cubic`. `direction` is `"in"`, `"out"` (the default —
the overwhelmingly common UI shape) or `"inOut"`. `duration` is validated to
`[0, 2]` seconds; `0` is legal and means "arrive on the frame this is stepped",
which is how a data-driven table says *instant*.

**The registry ships EMPTY, deliberately.** There is no defensible built-in
duration: 400 ms is a decision about one specific surface, where a class's two
physics numbers generalize. Registering a curve *is* the act of choosing, once,
with a name. As with classes, an inline `{ duration = 0.4, style = "quad" }` at a
call site is **refused** with an error pointing at `registerCurve`, and an unknown
name is an error with a did-you-mean and the registered list — never a silent
fallback to linear, which is the worst outcome available because it looks like it
worked.

```lua
Facet.motion.registerCurve("banner", { duration = 0.4, style = "quad", direction = "out" })
local reveal = clock:tween(0, "banner")
reveal:setTarget(1)
```

**The engine evaluates the curve.** On Roblox the easing math is
`TweenService:GetValue`, installed onto the clock by `motion_driver.bind` — the
one binding every client already makes — so a game gets the engine's own curves
with no wiring of its own, and a style Roblox adds later needs one line here
rather than a new implementation. `TweenService:Create` is *not* used and cannot
be: it targets an `Instance`, so driving a `MotionValue` through it would need a
proxy instance per animated value and a flight `clock:step(dt)` could not advance,
which would put the shipped path outside the headless suite. Lune has no
`TweenService`, so `src/motion/curves.luau` carries a pure twin for the suite,
pinned to the engine by a differential oracle over 33,033 samples (max
|twin − engine| = 4.73e-7). See `clock:setEasing`.

`motion.resolveCurve(name)`, `motion.curveNames()`,
`motion.isRegisteredCurve(name)` and `motion.resetCurves()` round out the
registry — deliberately one-for-one with the class registry above, so an author
who knows one knows the other and neither needs a lookup.

#### `clock:spring(initial, className, opts?) -> MotionValue`

The returned value **is** a Compose readable of a number (the backing cell itself,
augmented), so `Compose.watch`, `use(value)` inside a `Compose.formula`, and a bound
node property all work on it unchanged. `opts` accepts `eps` (settle epsilon,
default `1e-3` on **both** value and velocity), `kind`
(`"decorative"` default | `"informational"`), `quantum` (informational reduced-motion
tick, default 0.25 s) and `reducedMotion` (`"snap"` default | `"fade"`).

- `value:setTarget(number)` — aim. It touches **neither value nor velocity**, so a
  re-target on any frame continues from where the motion is at the speed it has.
  There is no "restart" verb.
- `value:setTarget(function)` — a **live target**, re-read every step: a flight
  lands on a row that re-sorted mid-flight. If the function returns `nil` (the row
  unmounted), the aim freezes on the last good read and the motion resolves by
  settle.
- `value:setVelocity(pxPerSecond)` — the gesture→animation handoff; a release
  velocity becomes the settle motion's opening velocity, so there is no seam
  between finger and flight. Non-gestural starts simply never call it.
- `value:onSettle(fn) -> unsubscribe` — fires **exactly once per arrival**, after
  the frame's writes are committed, so a handler reads the terminus. The value
  lands exactly on its target on the settling frame.
- `value:snap(v)` — placement: value + target set, velocity zeroed, write
  committed immediately. Not an arrival, so it fires **no** settle event.
- `value:stop()` — abandons the aim where the value stands; also no settle event.
- `value:isSettled()`, `value:getTarget()`, `value:getVelocity()`,
  `value:motionKind()`, `value:reducedForm()`, `value:dispose()`.

2-D motion is always **two** scalar springs, never one spring on a 2-D distance:
a single distance spring desyncs when the axes carry different velocities.

#### `clock:counter(initial, className, opts?) -> MotionValue`

The **numeral a player reads** — a wallet, a score, a tally counting up to its new
value. It is `clock:spring` with two invariants a spring plus a `math.floor` in a
memo does not give you:

- **It publishes whole numbers**, so it **writes once per changed numeral**
  instead of once per frame. A text node re-measures on every write; a 60 Hz
  count-up that changes 30 times must cost 30 writes, not 120.
- **It never overshoots the count.** A counter is a *quantity*: a wallet that
  flashes 130 on the way to 120 reads as a bug even when the physics is perfect,
  so the published value is clamped to the side of the target it started on. The
  class still owns the pacing (`reward`'s overshoot becomes "arrives early and
  waits", which is what a numeral wants) and the target is quantized too, so
  `getTarget()` is the number it will land on.

Everything else is the spring contract: it IS a Compose readable, `setTarget`
re-aims without restarting, it lands exactly, and it is **decorative by default**
— under reduced motion the final count is placed instantly and the same settle
event fires, because the number is a fact that is already on screen. Pass
`kind = "informational"` if you want RM to keep counting in 250 ms steps instead.

#### `clock:timer(spec) -> MotionValue`

`{ from, to, duration, kind?, quantum? }` — the linear ramp for depleting rings,
bars and countdowns. It starts the moment it exists and owes a **wall-clock**
terminus, so it advances by raw `dt` (springs clamp `dt` because they are
target-seeking; a countdown must not stretch across a frame spike). `kind`
defaults to `"informational"` — a timer's content *is* elapsed time. A timer has
no target and no velocity: `setTarget` / `setVelocity` raise an authoring error.

#### `clock:glide(initial, spec) -> MotionValue`

`{ duration, kind?, quantum?, reducedMotion?, eps? }` — the **re-aimable** linear
ramp: the value a fixed cadence resamples, which has to cross each gap at
constant speed. Set `duration` to the cadence the value arrives at, so one
sample's travel exactly fills the wait for the next. The key set is closed and
a non-finite `initial` or a negative `duration` errors at the call.

- **`setTarget(v)` restarts a full-duration ramp from wherever the value
  currently is.** It never moves the value, so a sample arriving mid-flight
  redirects without a visible jump — that is the interruptibility invariant a
  spring owes too.
- **It is not a spring**, because a spring re-aimed every sample is an ease-out
  per sample: it surges to ~2.2× average speed and then decays to ~0.14× before
  the next sample re-launches it, and at a 4 Hz cadence the eye reads that
  surge/stall cycle as stepping (director report, 2026-08-04 — the Sponsor map's
  dots wore exactly that). The velocity PROFILE is the thing to match, not the
  duration.
- **It is not a timer**, because a timer refuses `setTarget` — being re-aimed
  forever is a glide's whole job. It has no velocity to seed either (its speed is
  `(target − from) / duration` by definition), so `setVelocity` raises.
- `kind` defaults to **`"informational"`**: snapping a resampled stream under
  reduced motion would restore the very stepping this primitive removes.
- A fresh glide **starts settled** and costs the clock nothing until something
  aims it. `UI.ProgressView`'s indeterminate shapes are the framework's own
  caller, at `kind = "informational"`.

#### `clock:tween(initial, curveName, opts?) -> MotionValue`

`opts` is `{ eps?, kind?, quantum?, reducedMotion? }` and the key set is closed.
The **duration-and-curve** value: `setTarget(v)` crosses to `v` over the named
curve's exact duration and is **at** the terminus on the frame that duration
elapses — not approaching it. That is the whole primitive, and it is the one thing
no spring can do.

- **It is not a spring**, because a spring's settle time is emergent — `response`
  is a feel dial, not a duration — so "over exactly 400 ms" is not expressible and
  a cooldown built on one is late by an amount nobody can state.
- **It is not a `clock:timer`**, because a timer is fire-and-forget (`setTarget`
  raises on it) and strictly linear. A tween is re-aimable and carries a shape.
- **It is not a `clock:glide`**, because a glide is the *linear* re-aimable ramp
  built for a fixed resample cadence. A tween is that ramp with the curve between
  the endpoints made authorable — the half RascalRally lost when its `p^1.6`
  ease-in had to be flattened to a linear timer for want of a curve to name.
- **`setTarget(v)`** restarts a **full-duration** flight from wherever the value
  currently is. It never moves the value, so a re-aim mid-flight redirects with no
  jump — but the velocity restarts from the curve's opening slope. That kink is
  what a tween *is*, and it is why classes remain the default vocabulary.
- **`setVelocity` raises.** A curve's speed is its shape times its duration;
  accepting a seed would silently do nothing. `getVelocity()` still answers, and
  answers the curve's **instantaneous** slope rather than its average.
- It advances by **raw `dt`** (like `clock:timer`, unlike a spring's clamped
  frame): a tween owes a wall-clock terminus, so a frame spike must not stretch
  the duration it promised.
- A fresh tween starts **settled** and costs the clock nothing until it is aimed.
- `kind` defaults to **`"decorative"`**, exactly as `clock:spring` does. The rule
  the authority follows is that the default follows what the value *means*: only
  the primitives whose content is inherently elapsed time (`timer`) or a resampled
  stream (`glide`) default to `"informational"`. A cooldown sweep is
  informational and must say so.

#### `clock:setEasing(evaluate)`

Installs the easing evaluator — `(alpha, style, direction) -> eased alpha`, the
exact signature of `TweenService:GetValue`. **A game does not normally call this**:
`motion_driver.bind(presenter)` installs the engine's own evaluator, so native is
the default on Roblox rather than an opt-in someone forgets. It defaults to the
pure twin in `src/motion/curves.luau`, which is what makes the headless suite
possible at all, and it is read **per evaluation** rather than captured per value,
so a bind also upgrades values built before it.

#### `clock:chase(opts) -> handle`

`{ x, y, target, arriveRadius?, onArrive? }`, where `target` is
`() -> (number?, number?)`. Pairs two springs against a live target and fires
`onArrive({ how, targetLost })` **once**, on the frame the value enters the
**perceptual arrival radius** (default 4 px, range 2–8). The settle epsilon trails
perceived landing by ~0.7 s at position scale (measured: a 400×300 px flight on
`object` crosses the radius at 0.333 s and settles at 1.050 s), so `how = "radius"`
is the normal
answer and `how = "settle"` is the fallback for a target that vanished
(`targetLost = true`) or a chase that came to rest without ever closing. The
target is read once per frame, in the retarget phase, and arrival is judged
against that same read — never a pixel captured at launch. `handle:cancel()`
abandons the chase without an arrival event; `handle:isDone()` reports it. The
chase detaches itself on arrival.

#### `clock:timeline(spec) -> handle`

`{ beats = { { at, run?, terminal? } }, onDone? }` — beats fire in declared order
at their clock times (`at` is seconds from the start; a beat at `0` fires on the
first step). Beats must be declared in firing order; a regression is an authoring
error.

- `handle:interrupt()` — something else took over: runs every remaining beat's
  declared `terminal`, in order, on the interrupt frame, so nothing is left
  half-painted. It deliberately does **not** play the remaining content.
- `handle:skip()` — the player asked to fast-forward: delivers the remaining
  content instantly, each remaining beat's `run` then its `terminal`, in order,
  with zero elapsed time.
- `handle:isDone()`, `handle:elapsed()`. `onDone(reason)` fires exactly once with
  `"complete"`, `"interrupt"`, `"skip"` or `"reduced"`.

#### Reduced motion is information parity, not deletion

Under `motionPolicy = "reduced"` every contract above substitutes an
information-preserving equivalent, and the **same semantic events fire in both
modes** — that is an invariant of the authority, not a caller's courtesy.

| Contract | Reduced-motion form |
|---|---|
| decorative value (`clock:spring` default) | `setTarget` places the value at the terminal value **instantly** and fires the same settle event on the same frame. The write lands immediately, not on the next step, so parity never depends on a driver being attached. A velocity seed is inert (there is no flight to smooth). |
| informational value or timer (`kind = "informational"`) | **Keeps running** to the same wall-clock terminus; its writes quantize to `quantum` (250 ms) ticks — the stepped policy. Decorative motion snaps; informational motion steps. |
| `clock:counter` | The **final count** is placed instantly and the same settle event fires — the information is the number, not the counting. |
| `clock:tween` (decorative default) | Inherited from the decorative value rule above, with nothing re-decided: the terminus is placed instantly and the same settle event fires. Declare `kind = "informational"` for a cooldown or a charge sweep and it **keeps running** to the same terminus on the quantized tick instead — a frozen cooldown and a hung game look identical. |
| `clock:chase` | Placement is instant and `onArrive` fires on the same frame, with the same `how` / `targetLost` context. |
| `clock:timeline` | Every beat fires immediately, in order, durations zeroed (`run` then `terminal` per beat), and `onDone("reduced")` fires once. No beat is ever dropped. |
| `reducedMotion = "fade"` | A caller **declaration** that the consumer pairs the instant placement with a transparency fade at the destination. The value itself still snaps; motion never paints. |

#### `motion.newValueReveal(spec) -> reveal`

"Hold a number at what it WAS, then move it to what it IS, on cue, and land the
truth whatever happens." A results screen, a wallet, a rank — anything that must
not state its new value before its moment, and must never *withdraw* one it has
already stated. It is the one member of `motion` that is not the clock or the
class registry, because it owns **no clock and no signals**: you pass the two
flags your own view reads and the animator it reads, and the reveal only decides
what state they should be in.

```luau
local held, counting = Compose.cell(false), Compose.cell(false)
local reveal = Facet.motion.newValueReveal({
    held = held,          -- true  -> the view paints `from`
    counting = counting,  -- true  -> the view paints the animator
    animator = coinCount, -- optional: a clock:counter / clock:spring
})

-- whenever ANY input changes — idempotent, cheap, safe before the payload exists
reveal:sync({
    epoch = tailId,   -- "this is a different showing"; nil = no showing at all
    open = false,     -- has the window opened?
    past = false,     -- has it already closed? (a late arrival has nothing to hold for)
    abandoned = false,
    from = 120, to = 154,   -- nil = NOT YET KNOWN
})

coinCount:onSettle(function() reveal:landed() end)
```

Neither flag true means the view paints `to`. Three methods, all colon-called:
`reveal:sync(cue)` (call it whenever an input changes), `reveal:landed()` (wire
it to your animator's `onSettle` — it stops the count without re-holding), and
`reveal:rest()` (release everything to the settled state and rearm, for a
teardown or a new surface).

The five rules it encodes are the contract:

1. **Held is the default.** Before the cue the reveal reads `from`. A caller with
   no payload yet is WAITING, not abandoning — a `sync` with `epoch`, `from` or
   `to` still nil leaves the hold exactly as it was. Releasing there is the
   defect this exists to prevent: the final value paints, the payload arrives,
   the hold goes back up, and the bar visibly empties before filling.
2. **Seed, then count.** `sync` snaps the animator to `from` *before* it sets
   `counting`, so no frame can observe an unseeded animator (a counter is created
   at zero — flipping the flag first paints a 0).
3. **Every abandon path lands the truth.** An explicit `abandoned`, a new epoch,
   a window already `past`, and a caller with no animator all release to `to`.
   There is no path on which a number is left showing what it was.
4. **Once per epoch.** A reveal runs once for a given `epoch` — a tail id, a
   round stamp, whatever "this is a different showing" means to you — and a
   repeated cue is a no-op. A new epoch rearms on the settled state of the last.
5. **Degrading is not withholding.** `animator = nil` (no motion clock, reduced
   motion) is not a hold: every cue lands immediately. Decoration may be skipped;
   the fact may not.

Ownership: nothing. `rest()` is a state reset, not a teardown — the animator and
both flags belong to the caller.

#### `motion.newTextReveal(spec) -> reveal`

"Show a string as it arrives, never a half-glyph, and never a placeholder where
a value already is." The text twin of `newValueReveal`, and the same shape: it
owns no clock and no signals, so it composes with whatever model is already
streaming the string.

```luau
local reveal = Facet.motion.newTextReveal({
    value = function(use) return use(message).content end, -- the full text so far
    cursor = conversation.streamedChars, -- characters revealed; nil = all of them
    placeholder = "Thinking…",           -- painted while nothing has been revealed
    policy = app.environment:get("motionPolicy"), -- "reduced" lands the value whole
})

UI.Text({ text = reveal.text })
```

`reveal.text(use?)`, `reveal.revealed(use?)` and `reveal.complete(use?)` are
bindings: pass them straight to a property, or call them with no argument to
read once. `revealed` is false exactly while the placeholder is on screen, so a
caller can style or announce the two differently.

Four rules:

1. **A prefix ends on a codepoint.** `cursor` counts characters, not bytes, and
   the published prefix never splits one — an accented letter or an emoji is
   either fully there or not yet.
2. **A placeholder is not a value.** `placeholder` paints only while nothing has
   been revealed, and `revealed` says which of the two is showing.
3. **No cursor means fully revealed.** A model that streams by rewriting the
   string itself passes no `cursor` and keeps the other three rules.
4. **Reduced motion lands the whole value.** The fact is the text; the crawl is
   the decoration.

The reveal publishes a string, so each revealed character re-measures the text
node. For a long value that is a real cost: pace the cursor, do not advance it
once per frame.
### `UI.RadialMenu`

`UI.RadialMenu { ... }` / `UI.RadialMenu("Id") { ... }` returns the menu's node.
Pass `ref = function(record) ... end` to receive the frozen `{ api, dump }`
record once, while the control is built. The control is released with the
Compose owner that built it.

A command menu with a launcher, mathematically selected sectors, native readable
labels, and one logical hierarchy across rings, fans and replacement pages. Mount
the node in a bounded `UI.Anchor`/layout offer. Give it the space remaining after
screen chrome; the presenter's safe-area offer is respected. It owns presentation
state and subscriptions; the caller owns actions, check and radio cells.

```luau
local lanternOn = Compose.cell(false)
local menu
local node = UI.RadialMenu("QuickActions") {
    preset = "donut",
    center = "empty",
    items = {
        { id = "wave", label = "Wave", icon = "flag", onSelect = wave },
        { id = "gear", label = "Equipment", compactLabel = { icon = "menu" },
          navigation = "replace", children = {
            { id = "tools", label = "Tools", navigation = "expand", children = {
                { id = "light", label = "Lantern", checked = lanternOn,
                  onChange = setLantern },
            } },
        } },
    },
    ref = function(record) menu = record.api end,
}
```

| Spec property | Meaning and default |
|---|---|
| `id`, `env`, `width`, `height` | Standard control identity/environment/layout; width and height fill the offered box. Give the identity as `id` or as the constructor name, never both. |
| `ref` | `function(record)`, called once while the control is built with the frozen `{ api, dump }`. |
| `items` | Nonempty item array or a Compose readable of an array. |
| `launcher` | Boolean, default true. False omits the built-in launcher for a caller-owned prompt or other trigger; open with `api.open()`. |
| `label`, `icon` | Launcher's accessible name (`"Quick actions"`) and semantic icon (`"more"`). |
| `preset` | `"donut"` (default), `"circle"`, `"top-left"`, `"top-right"`, `"bottom-left"`, `"bottom-right"`. Corners face inward. |
| `appearance` | `"wedges"` (default) or separate `"buttons"`. |
| `buttonSurface` | `"native"` (default) draws a translucent disc and contrasting border for separate buttons. `"none"` omits both, leaving the icon/image and its interaction/focus behavior. Items can override this property. Wedges and list fallback retain their own surfaces. |
| `distribution` | `"even"` (default), or `"compass"` with explicit root item slots. |
| `navigation`, `expansion` | Inherited defaults: `"replace"` / `"expand"`; `"fan"` / `"ring"`. Default replace, fan. Each parent may override them. |
| `center` | `"back"` (default), `"root"`, `"close"`, `"content"`, `"empty"`. Back at root closes. |
| `centerLabel`, `centerContent` | Optional Home/Close label; passive blueprint used by content center. Keep contextual content within the center clearance. |
| `centerPassThrough` | Default false. With empty/content center, uncaptured scene input can pass through the **central square inscribed in the hole**. The curved corner crescents still consume taps. This native rectangular aperture prevents any painted sector from leaking scene input; it is not an alpha hit mask. A captured drag never passes through. |
| `clearance` | Donut/corner minimum inner radius as number or metric. Default 1.5× minimum target, compacting to one target when space is scarce. An explicit clearance is preserved. Circle defaults to a smaller central dead zone. An explicit or measured anchor clearance also applies to circles. Fitting may enlarge this radius. |
| `ringWidth` | Optional desired pixel or theme metric for a slimmer band. Adapts to available space while preserving minimum targets, enlarges for preferred text size, and falls back to a list when content cannot fit. |
| `contentFit` | `"both"` (default) fits painted wedge thickness and arc length to the displayed content. `"radial"` fits one uniform band to the widest content at each level; `"angular"` fits arc length only; `"none"` paints the full logical sectors. Uses theme spacing around measured text/icons. Separate buttons keep their circular treatment. |
| `anchor` | Window-space `{x, y, visible?, clearance?}` or a Compose readable of one. Optional finite nonnegative pixel `clearance` supplies the measured minimum opening, combined with the larger explicit `clearance`. Use `client.world_anchor` for automatic Part/Model/avatar measurement. Missing/invisible targets dismiss. This is a 2D overlay. |
| `gestureSelection` | `"bounded"` (default) requires a hit within the finite capture region. `"direction"` keeps a radial presentation even in a cramped offer and selects by direction after moving beyond 0.6× the minimum target from the center. Direct taps still use geometric hits. |
| `follow` | `"idle"` (default), `"always"`, `"fixed"`. Idle freezes the resolved geometry during captured pointer or active analog selection. Position and measured radius follow smoothly while idle. Fixed preserves the opening center and measured clearance until reopening. During smooth following or frozen selection, geometry can temporarily lag a moving/resizing object. |
| `enabled` | Boolean or a Compose readable of a boolean, default true. Disabling closes and cancels input. |
| `completion` | Default item-completion policy: `"stay"`, `"back"`, `"root"`, `"close"`. |
| `holdAction` | Optional consumer-owned semantic Bool action. Press opens; release commits the active analog candidate. Neutral alone never commits. No game trigger key is reserved. |
| `skin` | Optional image decorations: `item`, `launcher`, `center`, `background`. Each accepts an existing Roblox image URI or the standard image state-variant table. Explicit item `decoration` wins over `skin.item`, which wins over theme decoration. Use transparent annular artwork for a shared background if the center must remain visually open. |
| `onOpen`, `onClose` | Optional synchronous notification callbacks. |

An item has a unique nonempty `id` (no slash; `$navigation` is reserved) and a nonempty accessible `label`
(a string or a Compose readable). It may also have `icon` (semantic icon name), `compactLabel`
(the same short text/icon/image representation as Button), `labelStyle`
(`"text"`, `"icon"`, or `"both"`), `description`, `role`, `decoration`, `buttonSurface`, `slot`,
`enabled` and `hidden`. Enabled and hidden accept Compose readables. Icons do not replace the accessible
name. `both` measures an icon + text row and uses its icon representation when the
full row cannot fit. Both representations are centered in the reserved content box;
compact navigation uses semantic close/back icons. Fitting reserves the displayed
image rectangle for raw `compactLabel.image` content as well as semantic icon art;
it does not use the accessible label as an image-size proxy. Close/back artwork
scales inside that same measured box on compact rings. Content-fit padding also
reserves the border thickness, keeping artwork clear of the visible perimeter. Image skins on
separate buttons fill their measured disc. Selection highlights the
painted circle or wedge; image-only buttons retain their content focus outline. Upright text is placed along the arc, **not bent glyph by
glyph**. A measured safe rectangle stays inside both circular edges and the
sector seams. Long labels compact or truncate through Button's established
representation policy; focus/hover/drag previews show the full label outside the
ring. If a readable target cannot fit, the control switches to a scrollable list unless `gestureSelection = "direction"`. That policy preserves learned directions and may leave the ring partly outside a small offer.

A parent uses `children` (an array or a Compose readable of one), with optional
`navigation` and `expansion`. An action uses `onSelect`. A check uses a
caller-owned writable Compose cell of a boolean in `checked`, plus optional
`onChange(boolean)`. A radio uses a caller-owned writable cell in `selected`,
a `value`, and optional `onChange(value)`. These shapes are
mutually exclusive, as in Menu. Dividers and cyclic/empty children are rejected.

An item's `completion` wins over its `dismiss` boolean; `dismiss` wins over
the menu's `completion`; absent all three, actions close and check/radio items
stay. Capture is released and the navigation/closed state is changed **before**
the state signal and callback. Callbacks do not wait for animation. The outgoing
menu remains visible while its content and surfaces fade together. Focal launchers
fade back in on the same exit clock, without an empty interval. List fallback
finishes fading its rows before that clock reveals the launcher, avoiding overlap.
Radial opening and closing share one transform across the ring so adjacent
sector seams remain aligned. Its pivot is the launcher or focal anchor, including
all four corner presets; reversing the animation retains that same pivot. Callback errors are recorded in `dump().lastError`.

The corner navigation disc stays visible during dismissal. Its glyph crossfades
from Back/Close to the launcher icon while its diameter returns to the launcher
size; activating it during retirement reopens the menu. This keeps one continuous
corner affordance without bringing a central launcher over a retiring list.

Compass root slots are `N`, `NE`, `E`, `SE`, `S`, `SW`, `W`, `NW`; empty slots stay
empty for action selection. When the center cannot provide Back, the navigation control occupies an available slot (preferring SW, then S); a full compass ring uses the external navigation affordance. Conflicting assignments and slots outside a corner are errors. Corner
compass slots must be strictly inside the quarter arc. Authored directions never
rotate during fitting. Disabled/hidden items retain their positions while open.
Children distribute evenly. Expansion retains only the selected branch; when an
outer level cannot fit it replaces the visible level without losing the logical
path. There is no semantic depth limit.

Before choosing a list, fitting pulls the ring inward and reduces oversized
buttons/bands to the largest radial arrangement that fits. Minimum touch sizes,
readable wedge labels, authored directions, and explicit center clearance remain
constraints. Compact icon/short-text representations are selected through the
normal Button system; neither text nor the entire UI is scaled down. Truly
insufficient space still uses the list, except for directional gesture menus.
Preview space is reserved from the current theme's measured text and navigation
size. If an explicit center clearance prevents proportional compaction, the band
uses the remaining space before falling back. Launcher animation containers
include the theme's stroke allowance so rounded borders remain intact.

Pointer/touch press opens immediately. A stationary release latches; movement of
8 window pixels starts selection. Release over an eligible sector commits once.
Returning to the hole cancels; a gesture that opened the menu closes on cancel,
while a gesture begun in a latched menu leaves it open. Gesture selection extends
one minimum target beyond the outer painted edge in `"bounded"` mode; `"direction"` projects the pointer direction onto the deepest visible ring with no outer-distance limit. Direct selection does not use either extension.
Boundary hysteresis is 3 degrees between assigned sectors and never bridges an
empty compass slot. Hover previews only. Resizing during capture cancels safely.

Arrow/D-pad traversal uses solved item positions, Tab follows deterministic
logical order, Enter/Space/A commits, and semantic Cancel/B goes back then closes.
Roblox reserves physical **Escape** for its CoreGui menu, so Facet cannot promise
to intercept that key; the visible Back/Close control and semantic Cancel remain
available. Analog input enters at magnitude 0.35, releases at 0.25, and selects
within the deepest visible ring. Digital traversal reaches every ancestor and
outer item. Existing presenter responder arbitration still applies.

The record's `api` publishes `open()`, `close()`, `toggle()`, `back()`, `root()`
and `select(id)`, which perform the
same state transitions as input. `open()` and `select()` return whether accepted.
`api.isOpen`, `api.isVisible` and `api.openPath` are Compose readables. `isVisible` includes the exit animation, so external launchers can wait until the menu has fully retired. `record.dump()` returns the resolved mode,
local/window geometry, sectors, current path/candidate/capture, opacity, and last
callback/validation error.

Corner Back/Close replaces the launcher at the same center. Empty/content centers
use a Back/Close target in the ring, with even layouts placing it at the lower
left. Back centers use only the central control; list fallback keeps navigation
above its scroll area. The held launcher's capture source remains mounted but
visually hidden, so it cannot cover the list or center navigation.

Each wedge uses two bounded native Path2D strokes: its surface and a closed
contrasting perimeter covering the inner edge, outer edge, and both end caps. Separate buttons use translucent theme-colored discs; image skins cover
the square disc bounds with labels centered over them. Each complete visual has
one bounded CanvasGroup, with the Path2D inside a child Frame, and shares its
opacity/scale. Path stroke thickness explicitly follows that scale because the
engine keeps it in pixels even under UIScale. It does not rely on the
upgraded-gradient Studio beta for fades.
Owned motion values preserve interrupted animation. Replacement pages crossfade concurrently, with child wedges unfolding around
the selected parent sector and separate buttons traveling from its region. There is no empty wait between pages. Expanding fans
retain their ancestors. Each keyed row keeps its motion origin and spring through
interruption, so reversing a transition does not reset its position.
Closing preserves the displayed page until it has contracted and faded. Gameplay
callbacks still run immediately. Retiring visuals reject pointer actions and leave
focus order without dimming their content as disabled controls. An opening ring
blooms as a sequence rather than a slab: each wedge waits 20 ms longer than the one
before it, capped at 100 ms however many wedges the ring holds, so no arrangement
delays the last press beyond that. The candidate wedge — the one under the pointer,
the stick or a direct hover — lifts 4% out of the ring, and committing it seeds an
overshoot into that same lift so the acknowledgement continues the motion instead of
starting a new one. Both are paint; neither changes what the wedge measures or where
it can be pressed. Reduced motion snaps decorative movement: the ring opens whole,
the candidate still reads as lifted, and the commit does not overshoot. The Showcase's **Quick actions** demo (`radial-menu`;
scenario `radial_menu`) teaches corner commands, five compass gestures (direction
selection), and character gear.

The controller's `attachContextGestures(path, handlers)` additionally accepts
`onHover(windowPosition)` through the optional target `setPointerPreview` seam.
It previews mouse movement without taking capture and returns a detach function;
a surface without that target capability still supports the other input paths.

With `contentFit = "none"`, radial wedge separators use parallel caps with a constant pixel gap derived from
`xs`, so their width does not taper across the band. The default content fit paints
compact arc tiles, leaving larger spaces between items. Fitting changes paint,
not learned directions or the full logical touch/gesture sectors; invisible
space within an assigned sector remains selectable. The center hole and empty
compass slots still reject selection. Native labels use the existing theme/text
measurement service and keep the full candidate preview. `ringWidth` changes the band
independently of `clearance`; a compact character ring can use `clearance = 82`,
`ringWidth = "controlSizes.large.height"`, and icon-preferring `compactLabel`s.
Labels remain upright in a mathematically fitted rectangle; the full candidate
name appears outside the ring. `appearance = "buttons"` places separate circular
icons around the same focal anchor, including expanding icon fans. Directions
stay fixed during selection; this version does not rotate a carousel to bring
its selected icon to a fixed compass position. Navigation draws a compact rounded
32px x/< affordance with a full accessible name and the existing target expander.

Compact launcher and navigation discs retain native theme paint without rectangular
theme-art insets. Explicit `skin.launcher` and `skin.center` supply their artwork.
Quick actions → More options → **Arc shape** cycles Hug content, Slim band,
Short arcs, and Full arcs. These correspond to both, radial, angular, and none.

All four corner placements use `preset`; for example `preset = "top-right"`
places the launcher in that corner and opens inward. The Showcase's **Corner**
option cycles the four presets. **Jewel buttons** opts into `buttonSurface = "none"`.
For an image that is itself the entire button, use the existing compact image
representation with no native plate:

```lua
{ id = "map", label = "Open map", buttonSurface = "none",
  compactLabel = { image = mapImage, prefer = true }, onSelect = openMap }
```

This item belongs to an `appearance = "buttons"` radial menu. Keep the accessible
label meaningful: the list fallback and selection preview still use it. Use
`skin.item` or item `decoration` when the artwork is a background for an overlaid
icon/text label. The circular hit region and minimum targets remain independent
of image transparency. See [Choosing controls](../guide/14-choosing-controls.md)
for when to use a radial menu and which presets to start with.

<a id="adaptive-navigation-continuity"></a>
### Adaptive navigation continuity

### `activationGate`

`UI.activationGate(node, { closed, onOpen })` declares that while `closed` reads
true, the first Activate anywhere at or under `node` **wakes the subtree**
instead of reaching what is under the press. Use it for a surface that is not
the active one: an inactive monitor, a background panel in a split, a preview
that must be selected before it can be operated.

```luau
local focused = Compose.cell("left")
return UI.activationGate(UI.ZStack("Monitor") { MonitorBody() }, {
    closed = function(use) return use(focused) ~= "left" end,
    onOpen = function(path) focused:set("left") end,
})
```

`closed` and `onOpen` are the only legal fields; any other key is refused.
`closed` is required. It is a boolean, a Compose readable of a boolean, or a
`function(use)` returning one, sampled at the press without subscribing.
`onOpen(path, meta)` is optional and receives the path the press would have
reached. Declare the gate before the node is mounted; it returns the same node
with the policy attached.

It is an input policy, not a widget. Facet honours it on the one Activate
dispatch every source arrives through, so pointer, touch, keyboard and gamepad
all spend their first press the same way — and the subtree gains no extra focus
stop, hit target or node. A disabled node still consumes its press first. Where
gates nest, the **deepest closed gate wins**, so one press wakes one level,
innermost first.

### `focusSection`

`UI.focusSection(container, { entry = "restore", preferred = "Play" })` marks a
mounted container as a directional entry region. `entry` is `restore` (default),
`first`, or `nearest`; `preferred` is an eligible descendant ID or relative path.
Use unique IDs, or a relative path when names repeat. On initial entry the preferred
child wins; a valid remembered child takes precedence on subsequent restore entry.
Section bounds bridge empty space between a hero, shelf, or settings column. Grid
lanes, contributed collection navigation, explicit exits, and modal containment keep
their existing authority. Sections do not add a focus stop or a frame loop. Supported
containers: Box, VStack, HStack, ZStack, Grid, ScrollView, AdaptiveStack and Anchor.

`focusOnAppear` and `returnFocus` are the other half of the same sentence.
`entry`/`preferred` say where the ring lands when navigation WALKS INTO a region;
these two say where it goes when the region ARRIVES and where it goes back to when
the region LEAVES.

| Key | Value | Effect |
|---|---|---|
| `focusOnAppear` | `true` | focus the section's first stop, in document order, the frame it appears |
| `focusOnAppear` | `"Back"` | focus that descendant — matched on its final path segment or its whole path, the same rule `initialFocus` uses |
| `returnFocus` | `true` | remember what held focus when the section appeared, and put it back when the section goes away |

A presented surface has had this since `initialFocus`. An in-page branch — a
`UI.When`, a `Compose.show`, a route inside a page — had no spelling for it, which
is the shape most of a screen opens and closes in. Without it, a branch that
disables the content underneath (the usual way to show a detail over a list) leaves
the ring with nowhere legal to stand, and the graph takes the nearest surviving
neighbour — which can be outside the app entirely.

```luau
UI.When("Expand")({
    condition = function(use) return use(selected) ~= nil end,
    thenView = function()
        return UI.focusSection(detailPanel, { focusOnAppear = "Back", returnFocus = true })
    end,
})
```

Opening the branch puts the ring on its Back button; closing it puts the ring back
on the row the player opened it from. The two keys are independent: a route that
replaces its parent claims focus without giving it back, and a sheet opened by
pointer gives focus back without having claimed it.

**Restore is by path, re-checked when it is spent.** A remembered target that no
longer exists, or is no longer eligible, falls through to the surviving scope's own
entry rule rather than leaving the ring nowhere. A refusal is retried for a few
solves first, because the edit that closes a branch is usually the same edit that
re-enables the content underneath it, and that content is not eligible yet on the
frame the branch disappears. A windowed list that recycled the row under that path
restores the ring to THAT SLOT — where the player left it on screen — not to the
item that used to be in it.

`UI.Button`, `UI.Toggle` and `UI.Slider` accept
`row = { description?, icon?, value? }`. Fields are strings or readable strings;
`icon` names a semantic theme icon. Button's `value` is an inert trailing readout.
Toggle and Slider derive their readout from their owner-held value and refuse
`row.value`. A row retains one focus target and the existing action, toggle or
adjustment behavior. Slider retains pointer/touch track dragging and highlights the
whole row on keyboard/gamepad focus. The shared row recipe wraps copy, reserves
accessory space, and uses theme padding and border insets. Button row content cannot
be combined with `children` or `image`; Toggle row cannot be combined with `children`.

`UI.ScrollView { navigation = { targets, target?, snap?, progress?, threshold?,
onVisibilityChanged?, focus?, position?, active? }, ... }` configures scrolling:

`UI.VirtualGrid.scrollNavigation` accepts the same configuration for its
owned scroll host.

This also works on `app.controls.ScrollView` in a Compose component. `target`
accepts a Compose cell or formula; `progress` accepts a writable Compose cell.
The component owns the native scroll subscription, and removing it disconnects
navigation without disposing these caller-owned values. For example,
`local target = Compose.cell(nil)` can be passed as `navigation.target`; an
activation handler calls `target:set("Details")` to request that named section.


- `position`: optional writable Compose cell containing a pixel offset along the
  scroll axis. Native scrolling updates it; changing the cell requests a clamped
  offset. Keep the cell in the application model to preserve position across
  unmounts or share it between presentations. Restoring into a smaller viewport
  clamps that presentation without overwriting the stored offset.
- `active`: boolean source, default true. An inactive presentation neither writes
  shared position nor applies pending scroll requests; reactivation restores the
  current model value. Use this when multiple mounted presentations share one cell.
- `targets`: array of unique descendant IDs or paths relative to this ScrollView.
  Optional when `position` is provided.
  Nested scrollers own their own descendants. IDs should be unique in that scope.
- `target`: readable name or nil. Changing it requests leading-edge alignment,
  clamped to the native scroll range. Missing targets remain pending until mounted.
  Set nil before repeating the same request. Focus is preserved by default.
- `focus`: `"preserve"` (default) or `"target"`. Target travel may explicitly hand
  focus to the first eligible stop in the named region after arrival. The handoff
  is canceled by a newer request, user focus change, modal focus, scroll takeover,
  or removal of that destination; gestures never implicitly request focus.
- `snap`: boolean or `"page"`, default false. True settles native gestures to the
  nearest named target or scroll-range endpoint after the shared quiet window;
  oversized regions remain freely scrollable. `"page"` is for horizontal,
  viewport-wide pages: one mouse/touch swipe advances at most one target in
  declaration order and settles on release. Small nudges return to the starting
  page. Explicit target requests can still jump directly to any page.
- `progress`: caller-owned writable numeric Compose cell receiving normalized scroll progress
  (0–1). Bind it to paint properties for subtle image/scrim effects; do not feed it
  back into scroll-dependent layout dimensions.
- `threshold`: visible fraction, default 0.5, in (0,1]. For oversized targets the
  denominator is the viewport length. `onVisibilityChanged(id, visible)` fires on
  initial observation and crossings, not every frame. A visible target removed from
  the tree emits one `false` exit before its visibility record is discarded.

Target travel and snapping share Facet's interruptible motion clock and reduced
motion policy. Ordinary touch/trackpad scrolling retains native ownership. At rest no motion
values remain active. Geometry is indexed after solves; native samples do not walk
the view tree. These are declaration options, not renderer paint props.

`UI.TabView` now has `restoreScroll` (default true) in addition to
`restoreFocus`. Returning to a destination restores a stable descendant and its
intra-item offset after layout. VirtualList, VirtualGrid and virtualized Table use
logical item keys without building offscreen rows. If an item disappeared, restore
the surviving slot at the old index and clamp to the new range. Ordinary scrollers
use descendant paths and a nearest surviving indexed anchor. Bookmarks retain data,
not instances; tab/page scope disposal remains unchanged. Domain state, editing
state, and persistence remain caller-owned. Explicit target scrolling can override
a restored position.

Optional TabView `sections = { { id, label }, ... }` supplies sidebar headings;
a tab names its `section`. Headings appear at section changes in the visible order
and stay out of the focus order. Compact/top/bottom navigation retains the same tabs
without section headings. `customization` is a caller-owned writable Compose cell containing
`{ order = {tabId, ...}, hidden = {tabId, ...} }`. Unknown/duplicate persisted IDs are
ignored, newly authored tabs are appended, and `tab.required = true` protects a
destination from hiding. At least one destination remains visible; hiding the
selected tab selects the first visible destination. Reordering preserves the active
page and its state. `api.moveTab(id, oneBasedPosition)` and
`api.setTabHidden(id, boolean)` return whether the operation was accepted and require
`customization`. Present these commands with ordinary controls, as the Showcase
Profile page does. The host decides whether/how to persist the cell. `dump()`
includes `visibleTabs` in display order.

Live `UI.Picker` options also support the shared `pill` and `underline`
selection indicator. The same spring/geometry implementation tracks stable option
IDs through reorder/removal. Optional `sectionTitle` on live options labels section
starts in vertical presentation; declare the section structure in the initial array.

The mounted controller's internal `observeScrollIntent(path, callback)` seam
announces framework scroll writes before native echoes. Mounted scroll behavior
uses its scoped unsubscribe to prevent snap from undoing focus visibility; game
code should use `ScrollView.navigation` instead.

`controller.geometryEpoch()` is the internal solved-geometry version used by
mounted navigation behavior. Together with `structureEpoch()` it avoids polling
unchanged geometry or depending on notification registration order.

### Controller navigation ownership

`UI.TabView.shoulderNavigation` is `"strip"` by default. `"content"` also
allows L1/R1 paging while focus is inside the current page; it owns only shoulder
keys there. A readable policy may return either value. Nearest nested controls
win: value controls retain adjustment even at their limits. Pages do not wrap.
Content paging transfers focus into the incoming page after its map is ready.
Use the normal surface responder contract so passive HUDs never take gameplay
buttons. Disable content paging during a game-owned edit/confirmation flow with a
readable returning `"strip"`; preserve caller-owned editing state across routes.

Slider, Stepper and LevelPicker/Rating repeat controller adjustments after 0.4s,
then every 0.1s, through the same value operation. Repeat clamps at the value limit;
a fresh directional press retains the existing navigation-at-limit behavior.
Focus transfer, release, modal ownership, resign and disposal end a hold. Keyboard
keys retain their existing delivery. Contribution authors may opt in with
`adjustRepeat = true`; `adjustAxis = "none"` requests shoulder keys without arrows.

Table Cancel first closes a focused row action, releases a selected column or
reverts an in-progress row grab, then a subsequent Cancel exits edit mode. Only
then may Cancel propagate to the enclosing navigation/surface. Committed selection
and rows are not cleared when editing ends.

### Navigation theme chrome

Optional `chrome.navigation` uses the existing native/nineSlice/layered recipe
grammar and art insets. It paints TabView's adaptable top bar and distant top-tab capsule. An omitted recipe is native. Keep it lighter than `panel`:
Fantasy Ornate uses one carved strip with 6px vertical and 12px horizontal content
insets, without the panel's corners/nameplate. This changes art, not input or focus.
### `UI.Alert`

`UI.Alert { ... }` / `UI.Alert("Id") { ... }` returns the alert's anchor node.
Mount it anywhere in the screen; the modal itself is presented over the surface.
Pass `ref = function(record) ... end` to receive the frozen `{ api, dump }`
record once, while the control is built. Alert publishes its verbs on its own
record, so `record.api` carries `present(presenter?)`, `dismiss()`, `dump()` and
`blueprint`. The control is released with the Compose owner that built it.

Alert composes a brief modal decision from existing primitives. Its fade buffer hugs the
card and reserves the theme’s shadow margin, keeping desktop text out of a full-screen
composited texture. It centers a card sized
to its content and capped by the theme. Actions take one of two forms, chosen
from published facts, the platform alert convention: a **row** (hugging buttons,
centered) or a **stack** (full-width buttons). The stack is used with more than
two actions, on a compact width, on a ten-foot display, and at an accessibility
text preference (`preferredTextOffset` ≥ 10, the engine's Larger step). Placement
is role-driven, not authored: the cancel action leads the row and closes the
stack; the remaining actions keep author order. The card scrolls when
text/actions exceed the available height; theme border insets and safe areas
remain in force. Resizing, input changes and text preferences move the same
mounted actions (a keyed region, never a remount), so focus and shortcuts survive
a live flip. Action nodes live at `<alert>/Center/Card/Actions/Order/[<id>]/<id>`
(after `Decision/then/` for a data-bound alert).

Spec: `id?`, `ref?`, `title` (a string, a Compose readable, or a data factory), optional
`message` (same), and optional `actions` (records or a data factory; empty/omitted
supplies OK). `title` may be omitted with `error`. `env?` names the environment
whose `sizeClass`, `distanceProfile` and `preferredTextOffset` choose the action
form; omitted, the control reads the environment published on its core, exactly as
Picker and TabView do. `maxWidth?` is positive pixels
or a metric name, default `"controls.alert.maxWidth"`; `padding?` is nonnegative
pixels or a spacing name, default `"m"`; `surface?` defaults to `"raised"`.
The header is the title alone unless art is called for, and it is CENTRED in the card. A critical severity leads it with a small caution mark, and an authored `icon` supplies that picture — either one is one `iconSizes.medium` square, capped at the height of the heading beside it, so the mark reads as punctuation rather than as artwork. With a mark present the pair is centred AS A UNIT and the title reads from the mark; with no mark the title's own text is centred in the card, as the message under it always is.
The default width cap is `targetSizes.minimum * (560 / 44)`. Game themes own art,
colors, type and border insets.

| Presentation or content property | Behavior |
|---|---|
| `isPresented`, `presenter` | Optional caller-owned writable Compose cell of a boolean, and a presenter. True opens once; every dismissal writes false. An application supplies its own presenter, so `presenter` is only needed outside one. |
| `presenting` | Optional data or readable alongside `isPresented` or manual presentation. Nil prevents opening. Factories and action callbacks receive a shallow snapshot for that presentation. |
| `item`, `presenter` | Alternative optional-item writable cell. Nonnil opens; dismissal clears it. Cannot combine with `isPresented`, `presenting`, or `error`. |
| `error` | Record or readable with `errorDescription`, optional `recoverySuggestion` and `failureReason`. Supplies default title/message. A writable cell without `isPresented` is an automatic binding and requires a presenter; dismissal clears it. |
| `icon` | Optional icon name (drawn through the theme's art like Button's `icon`), image asset, or readable asset, sized using `controls.alert.iconSize`. |
| `severity` | `automatic` (default), `standard`, or `critical`. Automatic errors are critical; critical uses danger emphasis and a small inline vector caution mark — `iconSizes.medium`, capped at the heading it leads, because a package may pitch its picture ladder above its type (Fantasy Ornate's is 32 against a 22 px heading) — unless an image is supplied. |
| `suppression` | `{ isSuppressed, label? }`, where `isSuppressed` is a caller-owned writable Compose cell of a boolean, adds the existing checkbox control. The game must consult this value when deciding whether to ask again. |
| `content` | Optional `(owner, data) -> node?` for brief extra content such as a `UI.TextInput`. Use a full modal for an editor. The content runs inside the alert's own Compose owner, so `Compose.cleanup` releases with the presentation. |
| `transition` | Optional [structural transition](#structural-transitions) spec, or a `Readable` of one, for the modal's own enter/exit. Defaults to `{ enter = "materialize", plate = "fades", scale = 1.015 }` — the card **settles down on the way in** from 1.5% over with a fade, and **dips out** to the ratified 0.96 on the faster `dismiss` class on the way back; pass `{ enter = "instant" }` to opt out. An authored `transition` is MERGED with both keys rather than replacing them: a caller who names `enter = "materialize"` to change its motion class still gets `plate = "fades"` and the text-safe band, because the band answers an engine fact about the type on this card rather than a taste this control holds — declare your own `plate` or `scale` and yours wins, and no other form is given a band it does not drive. It settles down rather than growing in because the engine rasterizes text at `floor(TextSize × effectiveScale)`, so a scale below 1 would paint every string on the card a pixel small for the whole flight and snap it back when the motion ended (see [`scale`](#structural-transitions)). `nil` **and** `false` both fold to that same default — `false` is the framework's "no transition" spelling on `When`/`ForEach`, but Alert's card always materializes unless the enter form is named explicitly. A static value that fails `transitions.resolve` is refused at construction (`UI.Alert: transition: …`); a `Readable` one is refused on its first read instead, recorded on `dump().lastError`, and the binding resets to the default rather than raising inside the observer that opened it. |

The node the constructor returns is an empty anchor: it reserves the alert's
place in the tree and costs no layout. The modal itself arrives through
`isPresented`, an `item`/`error` binding, or a call to `record.api.present()`.

Runtime data/content-factory errors leave the alert closed, reset its presentation binding,
and report sticky `dump().lastError`; a later corrected request can open normally. Static
spec errors fail at construction. Data changes while open do not replace the
presentation snapshot; clearing its source dismisses it.

Each action has a unique `id`, required `label`, optional `compactLabel`, `enabled`
(a boolean or a Compose readable of one), `role` (`"default" | "cancel" | "destructive"`),
and `onActivate(data?)`. Labels may be Compose readables. One action at most is `cancel`.
An optional `shortcut` is `"defaultAction"` (Return), `"cancelAction"` (gamepad B),
or the existing Button `{keyCode, modifiers?}` shortcut. It preserves label
compaction and role styling. Only assign a default shortcut when immediate
confirmation is appropriate; cancellation remains the initial focus preference.
`default` emphasizes the button; it does not steal Return from the focused action.
`destructive` uses destructive styling. Actions invoke their callback once, after
dismissing. `require("…/controls/alert").resolveStacked(count, sizeClass,
distanceProfile, preferredTextOffset)`, `rowFits(labelWidths, chromeX, gap, available)`
and `orderActions(actions, stacked)` are the
pure form and placement rules, for a caller that wants to predict them.

**A modal's action label is never cut before the form changes.**
The categorical rungs above are all proxies for one question — do these labels fit
the width this card has — so the labels themselves get a vote: the control measures
each one at the size and face a Button will draw it (`text_metrics`, the solver's
own measurer), adds the button's chrome and the row's gap, and stacks when the sum
does not fit. Two things make that width worth having:

- the card's `padding` **yields** to the panel slot's carved frame rather than
  stacking with it — down to one `xs`, never to nothing, because the carved
  frame *is* the modal's inner margin and paying for it twice costs the content
  width twice, and
- the chrome-bleed lane a scroller keeps for content that paints past its box is
  **netted against that carved frame** — the frame already holds content that far
  from the clip edge, so the lane owes only the difference
  (`chrome_slots.bleedLane`). Under Fantasy Parchment (bleed 17, carve 18) it owes
  nothing; under Sci-Fi HUD (24, carve 0) it owes all of it, and a package that
  glows without carving keeps its lane in full. The Alert declares no
  `chromeReserve` of its own: the netting is done by the layout reader on every
  solve, so a theme swapped under a live modal moves the lane with it.

Together they turn 288 px of content on that phone into 322, which is what lets a
one-word primary action ("Continue") draw whole at the Largest preference. A flat
package carves nothing, reserves no bleed, and none of this moves a pixel.

`disclose` stays on every action underneath all of it, as the last resort it was
meant to be: a label that does not fit even a full-width stacked button at the
largest preference still has a route to its whole string. It reserves nothing
while the label fits. Cancel receives initial focus when enabled;
otherwise the first enabled non-destructive action is preferred, then ordinary
presenter focus fallback applies.

`api.present(presenter?)` opens one modal and returns its handle; repeated calls while
open return that handle. Inside an application the presenter argument is
optional — the application's own presenter is used. The presenter traps focus, dims the background
and restores focus on dismissal. Gamepad B invokes the cancel action if enabled,
or simply dismisses if no enabled cancel action exists. Pointer/touch users have
the same visible actions; keyboard users navigate and activate with Return. Escape
stays reserved for Roblox. Outside taps are consumed without choosing or dismissing.
`api.dismiss()` closes without invoking an action. Disposal follows the Compose
owner that built the control; after it the alert cannot be presented again.
`dump()` returns `{schema="facet-alert-dump/1", id, presented, actionCount, severity, lastError?}`.

```luau
local leaving = Compose.cell(false)
return UI.VStack {
    UI.Button { label = "Leave race", onActivate = function() leaving:set(true) end },
    UI.Alert("LeaveRace") {
        title = "Leave this race?",
        message = "Your current lap will not be saved.",
        isPresented = leaving,
        actions = {
            { id = "stay", label = "Stay", role = "cancel" },
            { id = "leave", label = "Leave race", role = "destructive", onActivate = leaveRace },
        },
    },
}
```

Use an Alert for a short acknowledgement/decision. Use Menu for many commands and
an authored `presentModal` surface for an editor or multi-step flow. The Showcase
**Alerts and confirmations**, **Actions and menus** and tutorial 04 use this control.

Alert combines title/message, actions and roles, presentation/data bindings,
error copy, icon, severity, suppression choice and shortcuts through Facet's game
input and theme system. It does not implement operating-system alert scenes,
app-termination prevention or secure text entry. Callbacks run after dismissal,
so they can safely open a replacement game surface.

### `UI.Sheet`

`UI.Sheet { ... }` / `UI.Sheet("Id") { ... }` returns the sheet's anchor node.
Pass `ref = function(record) ... end` to receive the frozen `{ api, dump }`
record once, while the control is built. Sheet publishes its verbs on its own
record, so `record.api` carries `present(presenter?)`, `dismiss()`, `dump()` and
`blueprint`. The control is released with the Compose owner that built it.

A modal whose height settles at declared detents. It enters from the bottom of
the screen and exits downward without scaling its text. By default nearby
screens place the panel at the bottom and distant screens center it; `placement`
chooses explicitly. Width, text, focus treatment and safe-area reservation
follow the active surface and theme.

Use a Sheet for a supporting task with its own body, such as a briefing, a
filter set or a loadout, that the player can resize or dismiss. For a centred
decision with pinned actions, use `UI.Dialog`; for a short panel anchored to one
control, use `UI.Popover`.

The panel is a pinned column: the drag grip, an optional sticky hero, the title
(or your `header`), the Size and Close row, ONE scrolling body, and pinned
`actions`. Only the body scrolls. Your `content` node mounts
directly in the body scroller: for a sheet with id `Sheet`, a content node with
id `Briefing` is at `/Sheet/Layer/Panel/Room/Column/Body/Briefing`. A hero that scrolls
with the body moves your content one level down, into `Body/Inset`.

| Field | Contract |
|---|---|
| `id` | Stable name; defaults to `"Sheet"`. Give it as `id` or as the constructor name, never both |
| `ref` | `function(record)`, called once while the control is built with the frozen `{ api, dump }` |
| `title` | Required text, a Compose readable of text, or a `function(use)` returning text |
| `content` | Required node, or a function returning one. A function is re-run for each presentation, so its cells live only as long as the sheet is open. It sits in the sheet's one body scroller |
| `detent` | Required caller-owned writable Compose cell holding a declared detent ID |
| `detents` | Nonempty array; defaults to `{ "medium", "large" }`. Medium requests half the safe height; large requests all of it; `"hug"` (id `hug`) fits the whole body plus the pinned regions and re-measures when copy, text size, theme or viewport change. Custom entries are `{ id, fraction }` with fraction in `(0, 1]`, or `{ id, height }` with positive finite pixels. IDs are unique. Detents are always heights, in every placement |
| `env` | Optional explicit environment; normally discovered from the surface |
| `presenter` | Optional presenter retained for `present()` and bound presentation. An application supplies its own |
| `isPresented` | Optional caller-owned writable Compose cell of a boolean; needs a presenter |
| `interactiveDismissDisabled` | Defaults to false. When true, Back, outside taps and downward dragging cannot dismiss, and Cancel runs no cancel action; the explicit Close button, the caller's own action buttons and `dismiss()` still work |
| `dragIndicator` | `"automatic"` (default), `"visible"`, or `"hidden"`. Automatic shows the header grip while pointer or touch is available |
| `placement` | Construction-only: `"automatic"` (default: centered at ten-foot, otherwise bottom), `"adaptive"` (as automatic, but a regular-or-wider width with a pointer and no touch docks it on the side edge — a desktop inspector; resolved live), `"bottom"`, `"center"`, or `"side"` |
| `edge` | `"left"` or `"right"` (default); only with `placement = "side"` or `"adaptive"`. Physical edges: the sheet docks there, bottom-aligned, and slides in from and out toward that edge |
| `width` | `"automatic"` (default, `controls.alert.maxWidth`), `"narrow"` (`controls.popup.panelWidth`) or `"wide"` (`controls.dialog.wideWidth`): the Dialog presets, bounded by the safe room |
| `closeButton` | Defaults to true. Independent of `interactiveDismissDisabled` |
| `header` | Construction-only. Absent shows `title`; a blueprint replaces the title region and sizes itself; `false` removes it. Size and Close stay in every form |
| `hero` | Construction-only `{ image | content, aspectRatio | height, scaleMode?, background?, sticky? }`: exactly one of an image source or an arbitrary blueprint, exactly one of a ratio or a height (px or metric); `scaleMode` is image-only. `sticky = true` pins it above the body; otherwise it scrolls with the body. It spans the panel width without the body inset. With `header = false`, Size and Close sit over the hero's top corner and stay pinned while a scrolling hero moves; authored hero content starts below a measured band that keeps it clear of them |
| `actions` | Pinned below the body: `{ id, label, role?, enabled?, busy?, onActivate }` (the Dialog action shape, any count). One `role = "default"` (Return) and one `role = "cancel"`. Cancel (ButtonB) runs an eligible cancel action before interactive dismissal, unless `interactiveDismissDisabled` is set. Actions never close the sheet; set your `isPresented` or call `dismiss()` |
| `actionLayout` | `"automatic"` (default), `"row"` or `"stacked"`; a row that cannot show every full label stacks |
| `contentInset` | `"standard"` (default) or `"none"`: the body's own padding only |
| `scrollPolicy` | Construction-only. `"always"` (default): the body scrolls at every height and never hands a pan to the sheet. `"atLargestDetent"`: below the tallest detent a body pan resizes the sheet; at it, the body scrolls and only a downward pan starting at the top shrinks the sheet |

Call `api.present()` to open and `api.dismiss()` to close. Repeated `present()`
calls while open return the current presentation. The node the constructor
returns is an empty anchor; the panel arrives over the surface. The control is
released with the Compose owner that built it.
A bound sheet writes false to `isPresented` when it closes.

Drag the grip, or the panel's free space (the engine's drag detector and touch
pan; interactive children keep their own presses), to resize. A drag from free
space starts after the input class's usual slop. Release projects the drag's
speed 0.15 s ahead and settles on the nearest detent to that; a tie keeps the
current detent. Only where the sheet actually is decides dismissal: below 70% of
the smallest detent, when interactive dismissal is enabled. Past the limits the
drag resists. One drag at a time: it belongs to the input class that started
it, and losing that class cancels it back to the grabbed detent; an outside
detent write or a change of the safe room cancels it too. The settle spring
starts from the painted height at the flick's speed; reduced motion snaps.

The Size button remains available without dragging. Activate it to cycle sizes;
Left/Right adjusts while it holds focus, yielding to navigation at either end.
Up/Down moves through the content. Gamepad Back closes and restores focus to the
presenting surface. The Close button has a downward chevron and works on every
input class. Distant-screen placement does not change these semantics.

Requested heights are capped by one safe rectangle (the viewport less the
platform insets and the on-screen keyboard) and raised to a themed minimum. The
body gives height back first. When the pinned regions alone exceed the room (a
very short screen with a tall header and several stacked actions), they overrun
the panel; no emergency whole-panel scroll exists yet. There is no background
interaction through the modal.

```luau
local detent, shown = Compose.cell("medium"), Compose.cell(false)
return UI.VStack {
    UI.Button { label = "Briefing", onActivate = function() shown:set(true) end },
    UI.Sheet("Briefing") {
        title = "Race briefing",
        detent = detent,
        isPresented = shown,
        content = function()
            return UI.Text { text = "Three laps around the coast." }
        end,
    },
}
```

`dump()` reports `schema = "facet-sheet-dump/1"`, `id`, `detent`, requested settled
`height` after clamping, `presented`, `dragging`, and `placement` (`"bottom"` or
`"center"`).

### `UI.PageView`

`UI.PageView { ... }` / `UI.PageView("Id") { ... }` returns the pager's node.
Pass `ref = function(record) ... end` to receive the frozen `{ api, dump }`
record once, while the control is built; PageView publishes no verbs, so
`record.api` is the record itself and `record.dump` is the useful half. The
control is released with the Compose owner that built it.

A finite sequence of content pages with native horizontal scrolling, snapping,
page dots, and Previous/Next buttons. Each page occupies the scrolling viewport's
width and provides vertical scrolling for longer content. Use it for short tours,
course previews or a small set of related pages; use VirtualList for large catalogs.

| Field | Contract |
|---|---|
| `id` | Stable name; defaults to `"PageView"`. Give it as `id` or as the constructor name, never both |
| `ref` | `function(record)`, called once while the control is built with the frozen `{ api, dump }` |
| `pages` | Required nonempty array of `{ id, title, content }`. IDs are unique nonempty names without `/`; titles are nonempty text and content is a node |
| `selection` | Required caller-owned writable Compose cell holding a declared page ID; programmatic changes navigate to that page |
| `height` | Optional dimension or a Compose readable of one; defaults to fill. Supply a definite height inside an outer vertical scroller |
| `indicators` | Boolean, defaults to true. The horizontal scrollbar is hidden while dots are shown. False hides the dots and restores the usual scrollbar policy; the page summary and Previous/Next remain |
| `summary` | Boolean, defaults to true. False removes the summary text row. The dots and Previous/Next remain |
| `controls` | Boolean, defaults to true. False removes the Previous/Next row. The summary and dots remain |

Dots have full-sized hit regions and semantic page labels. The summary row, when
present, names the current page and its position in the sequence. Activate a dot with
pointer, touch, Return or gamepad A; Left/Right adjusts pages while a dot holds
focus. At the ends those directions return to navigation. Selection also follows
native scrolling and snapping. Page-content focus brings that page into view;
a completed page change moves focus out of content that is no longer visible,
while preserving focus on navigation controls or outside the pager.

Mouse drags and touch swipes advance one page at a time, with no inertial travel
past the adjacent page. A small nudge returns to the current page. Snapping starts
on release, including after a pause while held; dots may jump directly to any
page. Clicks still activate child buttons; pointer-owning controls and text
selection take priority. Vertical gestures scroll the content within a page.

All page blueprints remain mounted. Resizing and input changes retain selection
and page state. The existing scroll motion and gesture system owns interruption
and reduced motion. There is no automatic advancement or wraparound.

```luau
local selection = Compose.cell("coast")
return UI.PageView("Courses") {
    selection = selection,
    controls = false, -- swipe and dots only; no Previous/Next row
    pages = {
        { id = "coast", title = "Coast", content = UI.Text { text = "Coast" } },
        { id = "summit", title = "Summit", content = UI.Text { text = "Summit" } },
    },
}
```

`dump()` reports `schema = "facet-page-view-dump/1"`, `id`, `selection`, the
one-based `index`, and `count`. The control is released with the Compose owner
that built it.
### `UI.CollapsibleView`

`UI.CollapsibleView { ... }` / `UI.CollapsibleView("Id") { ... }` returns the
trigger button's node. Pass `ref = function(record) ... end` to receive the
frozen `{ api, dump }` record once, while the control is built. CollapsibleView
publishes its verbs on its own record, so `record.api` carries `collapse()`,
`dump()` and `blueprint`. The control is released with the Compose owner that
built it.

It transforms a summary button into an expanded view at the same position. The plate
grows while its contents fade in at their final text size; collapsing reverses the
motion. Focus moves into the expanded view and returns to the button on collapse.
The shared presenter clamps the overlapping surface to the available safe area;
a vertical ScrollView makes tall content reachable with touch, pointer, keyboard,
and gamepad. Reduced motion follows the environment.

| Property | Meaning |
|---|---|
| `content` | Required node for the expanded view, or a function returning one. |
| `dismissButton` | `"always"` (default) shows Collapse; `"automatic"` shows it during keyboard/gamepad navigation and lets pointer/touch users dismiss outside. |
| `expanded` | Required caller-owned writable Compose cell of a boolean; set false to collapse after a choice. |
| `label` | Required static text or a Compose readable of text, including a selection-derived summary. |
| `icon` | Optional static or readable semantic icon name. |
| `image` | Optional static or readable asset string, instead of `icon`. |
| `id` | Stable ID, default `CollapsibleView`. Give it as `id` or as the constructor name, never both. |
| `ref` | `function(record)`, called once while the control is built with the frozen `{ api, dump }`. |
| `width` | Optional button width dimension. |
| `enabled` | Optional boolean or Compose readable for the trigger. |
| `initialFocus` | Optional node ID, or a readable of one, within expanded content. Defaults to first focusable. |
| `env` | Optional environment; otherwise discovered from the surface. |

A/Return or a tap opens the view. B, outside tap, or the explicit Collapse button
closes it. Content retains its owner-held state. A bound label or icon changes
without replacing the trigger or losing focus. `api.collapse()` sets `expanded` false;
`dump()` reports `expanded` and whether a surface is presented. The control is
released with the Compose owner that built it. It does not collapse automatically on arbitrary content changes:
the caller decides which choice completes the task.

`UI.TabView` supports `style = "collapsible"` to set this up for navigation.
It uses a top button with the selected tab label and icon, opens a scrollable
selector, and collapses after a choice. Use this explicit style when content should
have priority, especially on distant screens. Other tab styles retain their
existing behavior. This style accepts automatic or topBar placement.

NavigationStack keeps its existing Back hierarchy. It does not add a collapsed
style: use a CollapsibleView for an app destination chooser alongside the stack
when the product actually has sibling destinations.
### `UI.Skeleton`

`app.controls.Skeleton("Id")({ form = "line", lines = 3 })` reserves an
informational loading silhouette. It adds no focus target, input binding, or
surface decoration. Use `UI.ProgressView` when the player needs a progress value
or activity indicator; use Skeleton when the pending content's shape is useful.

`form` is required: `"box"`, `"line"`, or `"circle"`. `controlSize` accepts a
static or bound `"xsmall" | "compact" | "regular" | "large"`; absent means regular. Box and
circle use the rung's control height; line uses its icon size. A line's positive
whole `lines` count defaults to one. Multiple lines have theme-small gaps and a
60% final line. Box/line accept bound `width` and `height` dimensions; their
width defaults to fill. Circle accepts only width, used for both axes.
`corners = "pill" | "square"` overrides box/line rounding; circle refuses it.
Unknown keys and invalid form-specific combinations refuse. Invalid bound size
updates quarantine before geometry changes, and later legal values recover.

The surface-less plate uses the theme's control tint. One shared decorative
1.2-second triangular driver per presenter clock moves a 35% fill band between
percent spacers. It allocates two dimension tables per frame per clock, plus
ordinary per-instance rendering work. An animated circle also uses one small
rounded CanvasGroup to mask its sweep, released under reduced motion; its buffer
shares the documented [CanvasGroup quality and memory limits](#canvasgroup-costs).
Mounted sweeps start it; the last sweep
leaving detaches it immediately. Separate branch holds keep its independent
owner alive until the last Skeleton is disposed. A circular plate and its active
CanvasGroup mask use the shared true-circle shape, independent of theme pill
radii. A circular CanvasGroup is a grouping/clipping aperture and gains no
implicit shape hairline; ordinary circle Button/ZStack chrome is unchanged.
An explicit stroke remains available and additive. Render hooks count structural
presence, not pixel visibility or opacity. Reduced motion removes the sweep;
a missing presenter clock or environment leaves the plate static.

The ordinary `ref` callback receives the frozen record with `dump()`, including
form, lines, authored corners/size, animating and reducedMotion. There are no
imperative control verbs. Build pending placeholders inside their actual branch:

```luau
local UI = app.controls
return UI.When("Pending")({
    condition = loading,
    thenView = function()
        return UI.Skeleton("Article")({ form = "line", lines = 3 })
    end,
})
```
### `UI.Avatar`

`app.controls.Avatar("Id")({ name = "Ada Quill", ... })` shows a circular player
picture or first/last UTF-8 initials, preserving the name's authored case.
The required `name` is a nonempty string. Source choice is construction-time:
provide at most one of `image`, `userId`, or `key`; omit all three for initials.
`image` accepts a content string or readable. `userId` uses the existing 150×150
headshot URI and `key` names another resource; both require the caller's provider.
Avatar creates no provider and performs no fetch itself.

| Property | Default | Meaning |
|---|---|---|
| `form` | `"standard"` | `"standard"` has a border and optional presence; `"icon"` has neither. |
| `controlSize` | `"regular"` | Bound `"compact"`, `"regular"`, or `"large"`; nil restores regular. Standard uses the rung height, icon uses its icon size. |
| `diameter` | none | Positive finite pixels or a theme metric, instead of `controlSize`. |
| `presence` | none | Bound `"online"`, `"away"`, `"busy"`, `"offline"`, or nil. Refused in icon form. |
| `presenceLabel` | presence word | Optional bound localized word, requiring `presence`. |
| `presenceMark` | `true` | False hides the visual mark while retaining semantic presence. |
| `backplate` | `false` | Accent/on-accent initials treatment. |
| `over` | none | `"media"` uses the strong surface/content pair. |
| `frame` | none | Caller-authored overlay content, inside the same face. |
| `onActivate` | none | Adds one ordinary Button activation target. |
| `ref` | none | Receives the control record; `record.dump()` reports current identity and state. |

Use an Avatar to show who a player is beside their name, in a list row, a chat
line or a profile header. For several players at once, use `UI.AvatarGroup`;
for a status mark without a person, use `UI.StatusIndicator`.

Online is a disc, away a disc with a dash, busy a square, and offline a ring.
Presence is validated once into the shared derived value used by paint, dump,
and the interactive raw Button's semantic `label`; an invalid update retains the
last valid published state and a later valid or nil value recovers. Caller cells
are untouched. Passive avatars have no focus stop or native semantic-label prop;
their identity remains available through the ref/dump. This is not a claim about
operating-system accessibility support.

The zero/one-target statements describe Avatar-generated input. A `frame` keeps
its caller-authored content and input; `dump.interactive` reports Avatar's own
`onActivate` route. With `onActivate`, frame content must obey ordinary Button
custom-content restrictions throughout its lifetime: put separate interactive
adornments beside the Avatar. `dump.controlSize` is the requested raw rung; after
an invalid update it may differ from the retained valid geometry.

A mounted keyed Avatar owns one provider lease; the caller keeps the provider.
Pending content owns a Skeleton only for that branch. Ready and failure states
retain the same face diameter; failure shows initials. Removal releases the lease
and rejects stale completion, but cannot cancel an engine fetch already running.
Same-key Avatars share the provider's request/cache while holding separate leases.
Framework-generated face layers use true circles independent of a theme's pill
radius. Interactive layers sit in one zero-padding stack inside the raw Button;
compact visuals reserve the effective target floor in both axes. Initials fit to
the label cap, keep one line, and retain disclosure at large text preferences.
Avatar has no motion of its own; only a pending picture's Skeleton sweeps, and
reduced motion removes that sweep.

```luau
local portraits = app.newResourceProvider()
return UI.Avatar("Driver")({
    name = "Ada Quill",
    userId = 24813339,
    provider = portraits,
    presence = presenceCell,
    presenceLabel = localizedPresence,
    onActivate = openProfile,
})
```
### `UI.AvatarGroup`

`app.controls.AvatarGroup("Team")({ items = roster })` shows the first members of
an ordered roster and summarizes the rest with a count. Members never generate
individual targets; `onOverflow` adds one ordinary Button focus stop when there
are hidden members. Without it, the whole group is informational.

Use an AvatarGroup to show who is in a party, a lobby or a team when the
individual faces are not targets. When each person must be pressable, use one
`UI.Avatar` with `onActivate` per person in a list. The group has no motion of
its own; a pending member's Skeleton sweep is removed under reduced motion.

| Field | Contract |
|---|---|
| `items` | Required dense array, Compose readable, or `function(use)` returning members in caller order. |
| Member | Required unique nonempty string `id` and nonempty string `name`; optional XOR `image`, `userId`, or `key`, plus bound `presence` and `presenceLabel` as on Avatar. Repeated `userId` is allowed. |
| `provider` | Caller-owned resource provider, required if any member uses `key` or `userId`. Hidden members are validated but do not acquire a lease. |
| `layout` | Construction-only `"stacked"` (default) or `"spread"`. Stacked overlaps by `floor(diameter / 3)` and suppresses marks; spread uses theme `"s"` spacing and paints them. |
| `max` | Construction-only positive whole number of visible members; default `4`. |
| `overflow` | Construction-only `"count"` (default, `+N`) or `"ellipsis"`. Both retain the semantic `N more` label. |
| `overflowLabel` | Optional bound localized phrase; a nonempty string replaces the English default. Nil/empty uses the default; other types are refused. |
| `form` | Construction-only `"standard"` (default) or `"icon"`, passed to every member; icon members refuse presence. |
| `controlSize` | Bound `"compact"`, `"regular"`, or `"large"`; absent/nil uses regular. Every diameter and overlap follows the checked live theme rung. |
| `over` | Optional `"media"` tint roles for readability over artwork. |
| `onOverflow` | Optional callback for the only generated target. Compact paint still reserves the effective target floor in both axes. |
| `ref` | Receives `record.dump()`: `schema="facet-avatar-group-dump/1"`, shown ids, hidden count, chip text/label, layout, max, form, presence-mark policy, interactive intent, and requested controlSize/over. |

Every update validates the entire roster before publishing rows or allocating
leases. Malformed members and duplicate ids retain the last valid mounted roster
and diagnostic value; a later valid update recovers. Reordering unchanged ids
keeps their mounted face and lease. Name and presence updates flow through the
current item; changing a source identity rebuilds only that member's source
branch. Leaving the visible prefix releases its lease. Same-key faces share a
request/cache but each owns a lease; the group never owns the caller's provider.

The group's root leaves parent alignment alone. Child line alignment centers the
faces and count, including a compact face beside a larger target. Stacked overlap
is intentional paint, not overlapping member hit areas. Stacked presence remains
in each Avatar's diagnostic semantic label; passive faces expose no new native
accessibility route. An actionable chip's raw Button label carries the localized
count while its child paints `+N` or the ellipsis. `dump.interactive` reports the
supplied command; an empty or fully visible roster has no overflow target.
`dump.controlSize` reports the requested raw value, as on Avatar, while invalid
size updates retain the last accepted geometry.

Validation and publication scan and clone the whole roster on a dependency
change. Mounted cost follows the visible prefix: one keyed face per visible member,
one provider lease per loaded member, and one shared Skeleton driver per clock
while any pending branch is mounted. No hidden member is fetched. The gallery
transport completes on a presenter tick using a stand-in picture; native headshot
fetching is the supplied provider's responsibility.

```luau
local portraits = app.newResourceProvider()
return UI.AvatarGroup("Party")({
    items = partyMembers,
    provider = portraits,
    max = 4,
    layout = "stacked",
    onOverflow = openParty,
    overflowLabel = localizedMore,
})
```


### `UI.StatusIndicator`

`app.controls.StatusIndicator("Unread")({ count = unread, status = "error" })`
paints a passive mark without an input target or ornament surface.

Use a StatusIndicator for a small state mark or an unread count beside other
content, such as a tab name or an inbox row. For a mark with a caption on a
plate, use `UI.Badge`; for a player's online state on a picture, use
`UI.Avatar`'s `presence`. The mark has no motion: a changed count or status
repaints at once.

```lua
local app = Facet.new()
local UI = app.controls
local unread = Facet.Compose.cell(3) -- the caller writes the count; the mark only reads it
app.mount(function()
    return UI.HStack("Inbox")({
        gap = "s",
        UI.Text("Title")({ text = "Messages" }),
        UI.StatusIndicator("Unread")({ count = unread, status = "error", name = "Unread messages" }),
    })
end)
```

| Field | Contract |
|---|---|
| `form` | Bound `dot` (default), `ring`, `square`, or `dash`. Discs and holes stay circular across themes. |
| `status` | Bound `neutral` (default), `info`, `success`, `warning`, `error`, or `accent`. |
| `count`, `max` | Optional bound finite whole count ≥0; static whole cap ≥1, default99. Above the cap the text is `{max}+` (for example `99+`). Counted marks accept dot or square only. |
| `cutout` | Static boolean; adds a surface-colored backing inside the reserved footprint; uncounted gutters use 10% of each axis capped by the theme hairline, counted seals retain the hairline inset. |
| `name` | Optional nonempty semantic word. |
| `controlSize` | Bound compact (default), regular, or large; uses the theme's icon-size ladder. A count's height is a floor and can grow with text. |
| `width`, `height` | Optional bound dimensions for a parent-reserved footprint. |

The six statuses use theme palette pairs: neutral uses contentSecondary/surface,
warning warning/onWarning, success success/onSuccess, error danger/onDanger,
and info/accent accent/onAccent. Themes without semantic pairs retain the former
accent and content fallbacks. Shape and readable names remain independent channels.
A cutout spends the page surface color; it is not a transparent hole through arbitrary art.
Uncounted round forms center a square in the smaller offered axis, rounding the
diameter down to a whole pixel. An existing two-candidate fit ladder keeps both
passive alternatives mounted but paints only the selected one. Square forms use
the full rectangular reservation. Counted height is resolved once at the outer
reservation; the seal and cutout consume that space.
Uncounted cutouts use two zero-gap stacks and four passive spacer gutters so a
small mark keeps its silhouette; larger marks recover the full themed hairline.

`ref` receives `{ api, dump }`; `api.semanticText` is a readable. `dump()` returns
`schema`, `id`, `form`, `status`, displayed `count`, `max`, `cutout`, `name`,
`controlSize`, and `semanticText`. This diagnostic semantic text does not itself
create native text or an operating-system accessibility node. Bound form, status,
count and rung share one checked answer: invalid updates retain the prior paint
and semantic values, preserve the caller's source, and recover on a legal value.

### `UI.Badge`

`app.controls.Badge("Ready")({ label = "Ready", icon = "status.info" })` is an
informational caption with no generated focus stop or activation behavior.

Use a Badge for a short state or category word on a plate, such as "New",
"Ready" or a rank. For a mark or a count with no words, use
`UI.StatusIndicator`; for a tag the player can select or remove, use `UI.Chip`.
The badge has no motion: a bound change repaints it at once.

```lua
local app = Facet.new()
local UI = app.controls
local online = Facet.Compose.cell(true) -- yours; the badge only reads it
app.mount(function()
    return UI.Badge("Server")({
        label = function(use) return if use(online) then "Online" else "Offline" end,
        appearance = "status",
        status = function(use) return if use(online) then "success" else "neutral" end,
    })
end)
```

| Field | Contract |
|---|---|
| `label`, `icon` | Bound caption and/or static semantic icon name. An empty or absent caption requires an icon and a nonempty `name`. Bound caption presence mounts/removes the owned label; invalid updates retain the last legal content. |
| `iconPosition` | leading (default) or trailing; requires an icon. |
| `appearance` | standard (default), status (adds a shared StatusIndicator), or utility (no plate). |
| `status` | Bound StatusIndicator vocabulary, default neutral. |
| `corners` | pill or square; absent uses a pill. |
| `controlSize` | Bound compact (default), regular, or large; an icon-size height floor, not a cap on text growth. |
| `over` | media uses the opaque surfaceStrong/contentStrong pair, overriding the status pair. |
| `name` | Optional nonempty semantic word; required for icon-only content. |

**A count on a host: `UI.badged(host, value, direction?)`.** A count or dot on a
Button, an icon button, an Avatar or any other host sits on the host's corner:
top-right (top-left when `direction = "rtl"`), centred on the corner so it sits
half over the host and paints above it. The host keeps its own layout box, hit
target and focus stop; the seal is a later layer moved by a paint-only offset, so
it never covers the label area and nothing is laid out again. `value` is a string,
a number (above 99 reads "99+"), `true` for a dot (the seal with a bullet), or a
Readable of one; nil, false and "" paint nothing. The seal is the package's badge
slot (a themed seal draws at its full size), the same seal a list, menu or picker
row wears as an inline trailing pill. A tab bar's icon tabs (a segmented Picker
with icons, and so `UI.TabView`'s strip) wear their `badge` on the icon's corner;
text tabs keep the pill. The seal overhangs the host by half its size: give a host
at a clipping edge that much room (`UI.VirtualGrid` keeps half a gutter there).

```lua
UI.badged(UI.Button("Inbox")({ label = "Inbox", onActivate = open }), unread)
```

Every plated Badge owns a surface-less tinted Box; package badge-slot art remains
available to existing `Text.surface = "badge"` sites. Absent, static and bound
neutral all use control/content. Non-neutral statuses use StatusIndicator's pair;
utility uses secondary lettering. The caption can shrink and requests disclosure.
The status appearance paints its nested mark in the plate's lettering role (no
cutout ring), so the mark reads on the plate whatever surface the badge sits on.
One semantic Text host supplies the ASCII fallback and optional managed art. Its
width has an iconSizes.small floor and can grow for multi-character glyphs; its
height hugs the caption line. Art is a square bounded by that line and small icon
size, so different icon names do not change badge height. The four readable
partner roles also paint managed art; other roles keep the package icon tint.

`ref.api.semanticText` and `ref.dump()` expose the current checked label/status/rung
and authored appearance, icon side, corners, over and name. As with StatusIndicator,
passive diagnostic semantics do not promise native or OS accessibility delivery.

### Common control compositions

See [common recipes](../guide/17-recipes.md) for measured action rows, checkbox and chip groups, empty states, divider insets, and single-open DisclosureGroup composition using app.controls and Compose.
