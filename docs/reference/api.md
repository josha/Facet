# LuauUI API reference

Every public surface of the library, mechanically checked against the source
by `lune run tools/lune/check_registration_cli` (an export without a heading
here — or a heading without an export — fails the check). Format per entry:
signature, parameters, return value, invariants, and a short example.

The library is required as one module (`require(path.to.LuauUI)`); everything
below hangs off that table unless noted. Client-only entry points live under
`src/client/` and are required directly by client scripts, never from shared
or server code — the blessed list is [Client entry points](#client-entry-points).

**The patterns behind these entries** — how a constructor is shaped, who owns
what, which deviations are approved and why — are the
[constitution](constitution.md). Two conventions worth knowing before you read
anything below, because they decide how a call is written:

- **Colon vs dot** (constitution §16, E-7). Reactive-graph objects and pure
  stepped models take `self`: `core:signal()`, `scope:own()`, `clock:step()`,
  `model:step()`, `session:drop()`. Services, controllers and namespaces do not:
  `presenter.present()`, `controller.refresh()`, `registry.pointerDown()`,
  `adaptive.sizeClass()`. Each entry below is written in the form it takes.
- **Who disposes it** (constitution §8). In order of preference: pass
  `opts.scope` and the helper owns its resources there (`adaptive.conditions`,
  `inputHint`); else `scope:own(handle)` the returned object (`motion.newClock`);
  else the return IS an unsubscribe you own (`presenter.onTick`). Where an entry
  says nothing, there is nothing to own.

---

## Library metadata

### `VERSION`

`LuauUI.VERSION: string` — the semantic version (`MAJOR.MINOR.PATCH`),
currently `0.9.0`. Governed by `docs/adr/ADR-0011-semver-and-deprecation.md`:
pre-1.0, a minor bump may change behavior with notice; a patch bump never
does. The version lives only here; docs and tests read it from the source.

### `DEPRECATIONS`

`LuauUI.DEPRECATIONS: { { surface, since, removeNoEarlierThan, replacement, note? } }`
— the machine-readable deprecation ledger, and it is **frozen**: authority, not
a scratch table. It is the UNION of two halves in one record shape, so every
consumer reads one list — the entries generated from the property schema
(`src/blueprint_schema.luau`), then the declared entries for surfaces that are
not blueprint properties (an opts field, a derived condition). A deprecated
surface keeps working for at least one minor version after `since`, and every
entry names its `replacement`.

The current rows are `UI.Text.color` and `UI.Text.font` (schema-generated, since
0.5.0), plus five declared entries: `newResourceProvider(opts.retryAttempts)` and
`adaptive.conditions().contentWidth` (since 0.8.0), and
`newVirtualList(spec.rowHeight)`, `newVirtualList(spec.viewportHeight)` and
`screen_target.new(opts.isReducedMotion)` (since 0.9.0, removed no earlier than
0.10.0). Each is marked deprecated where it is documented below.

One important exception to "keeps working": a property that **never** reached a
render target was never working surface to preserve. Keeping it silently
accepted would preserve the silent failure, not the compatibility. Those
properties stay in the ledger for the record but are **diagnosed at
construction** — you get an error naming the replacement instead of a screen
that quietly omits behavior. `UI.Text.color` and `UI.Text.font` are the current
entries.

---

## Reactive core

### `newCore`

`LuauUI.newCore() -> Core` — creates an independent reactive core: the
signal/memo/observer/effect graph plus the transaction scheduler and scope
(ownership) system. Everything else in the library is built over one core per
client.

`core.name` is the implementation's name (`"custom"` for the shipped core) — a
plain field, useful in a diagnostic dump. A core has **no `dispose()`**: scopes
are the teardown seam, and `core:counters()` returning to its baseline is the
leak test.

Core methods (all take the core as `self`, i.e. call with `:`):

- `core:signal(initial, eq?) -> Signal` — writable value. `signal:get()`,
  `signal:set(value)`, `signal:dispose()`. `eq` customizes change detection
  (default: `==`, NaN-safe; it is a positional optional because these are the
  library's hottest constructors — constitution E-9). A throwing `eq` is
  quarantined (recorded via `lastError`, treated as "changed"), never crashes a
  writer. **Disposing a signal freezes its readers rather than erroring them**:
  dependents are never invalidated again and keep serving their last value, and
  a later `set` on it succeeds silently and reaches nobody. Dispose a signal
  last, or let its scope do it.
- `core:memo(compute, eq?) -> Memo` — derived value. `compute(use)` reads
  dependencies through `use(readable)`; dependencies re-track on every run.
  Reads are glitch-free: inside or outside transactions a memo read is always
  consistent with current signal values. Writing state inside `compute` is an
  error. Compute errors quarantine the memo (it keeps its old value).
- `core:observe(readable, onChange) -> unsubscribe` — calls `onChange(value)`
  after a flush in which the value actually changed. Observer callbacks are
  quarantined: a throwing callback records `lastError` and never wedges the
  scheduler. Disposing an observed node reclaims and silences its observers.
- `core:effect(run) -> unsubscribe` — like observe but dependency-tracked, with
  one difference that matters: **`run(use)` executes immediately, at
  registration**, and then again post-commit whenever a tracked dependency
  changes. (`observe` does NOT fire on registration — it baselines instead.)
  Writes from an effect land in the NEXT flush round; runaway feedback trips a
  100-round cap, which discards that round's pending writes and records the trip
  on `lastError`.
- `core:transaction(body)` — **batching, not atomicity.** Writes inside `body`
  are held and observers/effects fire once at the end; set-then-revert inside a
  transaction fires nothing. There is no snapshot and no rollback: if `body`
  throws, the writes it already made stay applied, the flush still runs, and the
  error is re-raised to you. Reach for it to coalesce updates, not to make a
  group of writes all-or-nothing.
- `core:flush()` — force a flush (rarely needed; writes outside transactions
  flush automatically). Calling it from inside a flush is a no-op.
- `core:scope(label?) -> Scope` — ownership scope: `scope:own(resource)`
  (function, disposable table, or child scope — a table with no `dispose` is
  **refused** at `own` time, naming the resource, rather than silently never
  being torn down), `scope:use(resource)` (borrow: returns it, and does NOT take
  ownership — the spelling for a child that must outlive this scope),
  `scope:child(label?)`, `scope:dispose()` (reverse order, idempotent; double
  disposal is DETECTED via `lastError`), `scope:isDisposed()`.
- `core:counters() -> { signals, memos, observers, effects, scopes }` — live
  registry counts; lifecycle-neutral code returns them to baseline. A root scope
  from `core:scope()` has no parent, so it is yours to dispose.
- `core:lastError() -> string?` — the most recent quarantined error (cycles,
  compute/observer/eq errors, feedback-cap trips, double disposals). **It is
  sticky**: `nil` until the first quarantine, and never cleared afterwards.
  There is no take-or-clear verb, so it reports "something was contained at some
  point in this core's life", not "this core is unhealthy right now" — a health
  assertion built on it has to be scoped to a freshly-built core, the way the
  library's own tests are.

```lua
local core = LuauUI.newCore()
local count = core:signal(0)
local label = core:memo(function(use) return `Count: {use(count)}` end)
core:observe(label, print)
count:set(1) -- prints "Count: 1"
```

---

## Blueprints

### `UI`

`LuauUI.UI` — the blueprint constructors. Blueprints are immutable plain
tables describing a tree; they carry no reactivity themselves, but any prop
may be a Signal/Memo and the mount layer subscribes it to the right update
class. Every constructor takes one spec table; `id` gives a node stable
identity (required for anything you want to address later — focus, tests,
dumps).

**Construction is strict.** Every spec is validated against the public schema
(`src/blueprint_schema.luau`) at build time, and each of these is an immediate
error naming the control, the property, and the valid alternatives:

| Mistake | What you get |
|---|---|
| unknown property | `UI.Button: unknown property 'lable'. Did you mean 'label'? Valid properties: …` |
| wrong value type | `UI.VStack.gap expects number, got string. (spacing between children along the stack axis)` |
| a bare number where a dimension belongs | `UI.Box.width expects dim, got number — a dimension table such as { type = "fixed", px = 120 }` |
| a Signal on a prop read once at mount | `UI.ScrollView.axis does not accept a Signal/Memo …` |
| a missing required property | `UI.Text.text is required (the displayed string)` |
| children on a leaf | `UI.Text does not take children (it is a leaf). Containers: Anchor, Grid, HStack, …` |
| a property that never reached the renderer | `UI.Text.color is not supported (deprecated 0.5.0 …). Use UI.Text{ role = … }.` |

A **modifier's** refusals name the modifier you called, not the internal
property it chose: `UI.alignment(bp, "center")` on a class with no `alignH`
reports `LuauUI UI.alignment on UI.When: UI.When has no property 'alignH'`. A
direct constructor error is unchanged (`LuauUI UI.When: …`).

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
| `lineAlign` | `start \| center \| end \| stretch` | this child's own cross-axis alignment inside its **stack** parent's line; it outranks both the child's own `align` and the container's `align` |
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

#### Tooling surface: `UI.schema`, `UI.isReadable`, `UI.PROP_DIRTY`

Three exports exist for tooling, tests and extension authors rather than for
authoring a screen. They are public and covered by ADR-0011 like anything else.

`LuauUI.UI.schema` is the property schema itself — eleven members:

| Member | Answers |
|---|---|
| `forClass(name) -> ClassSpec?` | one class's declaration (`props`, `container`, `structural`) |
| `all() -> { [name]: ClassSpec }` | every class, keyed by name |
| `classNames() -> { string }` | the class names, sorted |
| `propNames(class) -> { string }` | one class's property names, sorted |
| `sharedPropNames() -> { string }` | the properties declared `shared` (the table above) |
| `checkValue(propSpec, value) -> (ok, problem?)` | the single value ruling every constructor and modifier runs |
| `suggest(class, badKey) -> { string }` | the did-you-mean candidates for an unknown key |
| `propDirty() -> { [prop]: { [class]: { dirtyClass } } }` | which update classes a reactive prop schedules (a fresh table per call) |
| `deprecations() -> { Deprecation }` | the schema-generated half of `LuauUI.DEPRECATIONS` (a fresh table per call) |
| `TRANSITION_MIRROR` | each structural-transition form paired with its mirror |
| `TRANSITION_FADES` | the forms that drive transparency (and therefore need a fade group) |

**Stability.** The schema tables are **deeply frozen** — `all()` and `forClass()`
hand back the live authority, so a writable copy would have been a way to
disable framework validation process-wide. Read them; to annotate one, clone it.
The shape of a `ClassSpec`/`PropSpec` is internal detail that may change in a
minor; the eleven names and what they answer are the contract.

`LuauUI.UI.isReadable(value) -> boolean` is **the one public predicate** for "is
this a Signal or a Memo". Reach for it instead of duck-typing `.get`.

`LuauUI.UI.PROP_DIRTY` is the frozen `prop -> class -> { dirty class }` map the
mount layer reads to decide what a reactive prop invalidates. It is the same
data `schema.propDirty()` builds; the export exists so a diagnostic tool can
read it without rebuilding it per call.

Framework metadata does **not** travel in the prop bag: an input-contribution
bundle rides the blueprint's internal `meta` channel (see `contribution`), so
strict prop validation has no exemptions to work around.

#### Shared properties

These are accepted by every class the note names, so the per-class entries
below list only what is specific to that control. **"Accepted on" is exact** —
the schema is the source, and a property this table does not list for a class is
a construction error on it, not a no-op.

Three groups recur in the column below and are worth naming once:

- **every rendered class** — the twenty-one classes that produce a box:
  `AdaptiveStack`, `Anchor`, `Box`, `Button`, `Composition`, `Divider`, `Grid`,
  `Grip`, `HStack`, `Image`, `Path`, `Screen`, `ScrollView`, `Spacer`, `Stage`,
  `Text`, `TextField`, `Toggle`, `VStack`, `ViewThatFits`, `ZStack`. **Two
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
| `id` | every class | stable node identity; required to address the node later (focus, tests, dumps) |
| `width`, `height` | every rendered class | dimension tables: `{type="fixed",px=}`, `{type="content"}`, `{type="fill",weight=}`, `{type="percent",fraction=,offset=,min=,max=}`, `{type="minMax",min=,preferred=,max=}`, `{type="aspect",ratio=}`. The `px`/`min`/`preferred`/`max` fields take a number **or a theme metric name** (see below) |
| `margin` | every rendered class | outer spacing the parent reserves around this node; a number, a spacing-step name, or `{top?,right?,bottom?,left?}` of either. A **`fill` child spends its own margin out of its fill**, on every container — a `ZStack` layer with `margin = { top = 56 }` is 56 px shorter, not 56 px lower — and a filled axis therefore ignores `alignH`/`alignV`, because there is nothing left to align. A non-fill child keeps its size and is displaced, so alignment still applies to it |
| `anchor`, `offsetX`, `offsetY` | children of an `Anchor` | placement corner plus offset; offsets update in the arrange pass only (no re-measure). An offset takes a number, a theme metric name (`"-s"` negates one), or a **fraction of the parent's inner extent**: `{ scale = 0.5 }`, `{ scale = 0.5, offset = -4 }` (the marker-overlay shape — see `Anchor`) |
| `alignH`, `alignV` | children of a `ZStack` | per-child cross-alignment (`start`/`center`/`end`) |
| `padding` | layout containers, `Button`, and the text-bearing leaves `Text`, `Toggle`, `TextField` | inner spacing; on a control it is the text inset the adapter must match, and on a `Text` the measure adds it. A number, a spacing-step name (`"xs"`…`"xl"`), or per-side values of either |
| `gap` | `Screen`, `VStack`, `HStack`, `AdaptiveStack`, `ScrollView`, `Grid`, `Button` | spacing between children along the stack axis; a number or a spacing-step name (`"xs"`…`"xl"`). On a `Button` it spaces the button's own content |
| `align` | `Screen`, `VStack`, `HStack`, `AdaptiveStack`, `Button` | cross-axis alignment of children (`start`/`center`/`end`/`stretch`) |
| `wrap` | `VStack`, `HStack` | let the children run onto more than one line when they do not fit the main axis (Roblox `UIListLayout.Wraps`). See `VStack` / `HStack` below — it adds no new alignment words, and `align = "stretch"` is refused beside it |
| `overflow` | layout containers | declared overflow handling (`clip`/`scroll`/`visible`/`intentionalOverlap`). **`"clip"` makes the node a clip host** — it sets `clipChildren` at construction unless you authored that flag yourself, so the word does the thing it names. The other three values are declared intent, read by the solver's overflow diagnostic and by the layout dump, and drive no engine property |
| `clipChildren` | layout containers | make this container an engine clip host; `ScrollView` defaults it to true |
| `active` | layout containers, `Box` | engine `Active` flag — an input-sinking panel (modal backdrops) |
| `surface` | layout containers, `Box`, `Button`, `GridRow`, `Image`, `Stage`, `Text` (only `"badge"`/`"chip"` — see `Text`) | surface style role painted behind the node |
| `shadow`, `gradient`, `corners`, `stroke` | every rendered class, **and `GridRow`** | normalized style-modifier data — produce them with `UI.shadow` / `UI.gradient` / `UI.corners` / `UI.stroke`, never by hand |
| `zIndex` | every rendered class, **and `GridRow`** | paint-order override **within the parent's stacking scope**: siblings paint in `(zIndex or 0, declaration order)` order and a node's whole subtree travels with it. A child is always above its own parent, whatever its `zIndex`, so lifting across surfaces stays structural (`presentModal`'s display order). Read once at mount — a lift is what a node *is* (a drag ghost, a toast), not a state it passes through |
| `hidden` | every rendered class | `true` keeps the node's **layout box** and stops painting it — and takes its whole subtree out of focus order and off the tap path with it. This is SwiftUI's `hidden()`, and it is the one thing neither of the other two answers gives you: `UI.When` *removes* the node so the siblings close up, and Roblox's own `Visible = false` frees the layout slot inside a `UIListLayout` (LuauUI arranges absolutely and materializes none of those, which is why one prop is enough). Reactive — bind it to a signal to reserve a slot until the value arrives. Reach for `UI.When` instead whenever the space *should* close up |
| `opacity` | `Box`, `ZStack` | fade this node **and its whole subtree**: `1` is opaque (the default), `0` is invisible while still laid out, focusable and tappable — reach for `hidden` when you want all three gone. This is SwiftUI's `opacity(_:)`. Declaring it **makes the node a fade group** (you never write `canvasGroup = true` beside it), because a fade in this framework is one `CanvasGroup.GroupTransparency` write and that is the one alpha property no style rule owns — a per-node transparency write would permanently defeat the theme's own rules, which is why a leaf like `Text` refuses it. The spelling for a leaf is one wrap: `UI.ZStack { opacity = 0.4, children = { theText } }`. It **multiplies** with any fade the framework is running on the same node (a transition, a toast retiring), exactly as Apple specifies, so an authored `0.5` inside a transition at half-way paints `0.25`. Reactive, and animatable through `presenter.withAnimation` |
| `scale` | every rendered class | paint-only uniform scale about the node's centre; `1` is unscaled. **It changes nothing the solver sees** — the layout box, the tap target and the focus order are all the unscaled ones — which is Apple's rule for `scaleEffect` too; to change a box, change `width`/`height`. It **multiplies** with any scale the framework is applying (a motion pop, an enter transition). Reactive and animatable. It **survives a press**: a `Button`'s dip shares the engine's single `UIScale` per object, so the dip is relative — it goes down to `resting x pressedScale` and comes back to `resting`, never to an absolute `1` |
| `rotation` | every rendered class | paint-only rotation in **degrees** about the node's centre; `0` is upright, positive is clockwise. Like `scale` it moves no layout and no hit geometry — a rotated button's tap target is its unrotated box — and it **adds** to any rotation the framework is applying. Reactive and animatable |
| `onAppear`, `onDisappear` | every rendered class | view-lifetime hooks, both called with the node's path. `onAppear(path)` runs **once**, on the frame the node is first rendered and **after that frame's layout solve**, so it can read its own rect (`controller.rectOf`) and nothing has reached the screen yet. `onDisappear(path)` runs **once**, **after** the node's render instance has been released — the path is already unmounted, so `rectOf` on it is `nil` — and it also runs for everything still mounted when the surface is torn down, so a cleanup is never silently dropped. The lifetime measured is the *rendered* one: a virtualized row that scrolls out of the window disappears, and a subtree still playing its exit transition has not disappeared yet. Not reactive (a lifetime is not a value that changes), and an error thrown inside a hook is loud rather than swallowed |
| `textSize` | `Text`, `Button`, `Toggle`, `TextField` | an explicit px number, or a typography role name (`"caption"` \| `"label"` \| `"body"` \| `"heading"` \| `"title"` \| `"control"` \| `"strong"` \| `"numeral"`) resolved from the active theme. A role supplies the **font descriptor and line height** as well as the size, and both travel to the measure seam AND the paint seam — so `"strong"` (emphasis at reading size) and `"numeral"` (a rank or score figure) are how a node asks for **weight**; there is no `weight` prop, because a face that reached only one seam is what `Text.font` was deprecated for. Either form is scaled at both seams |
| `textAlign` | `Text` | horizontal alignment of the node's own text in its box (`start` \| `center` \| `end`); default `start`. Vertical alignment stays adapter-owned and is always centred, because the headless measurer over-reserves and centring splits that error evenly |
| `focusable` | `Button`, `Toggle`, `TextField` (opt **out**), `Grip` (opt **in**) | membership in focus order |
| `traversalPriority` | `Button`, `Toggle`, `TextField`, `Grip` | linear-traversal (Tab/Shift+Tab) sort **tier**, default `0`. The sort key is `(traversalPriority, document position)`, so a negative value traverses earlier and a positive one later, and **within a tier document order always wins** — the `tabindex` model. Affects Tab only; the directional arrows never read it. Construction-only: a traversal position is what a node *is*, so binding a Readable here is refused with the rebuild idiom |
| `onActivate` | `Button`, `Toggle` | `onActivate(path, meta)` — the presenter auto-dispatches tap / Return / ButtonA to it (ADR-0013) |

**Theme metric names.** Anywhere the table above accepts a theme-owned number
it also accepts a NAME for it, resolved from the active `ThemeSnapshot` on every
solve — which is why installing or swapping a theme changes geometry without
rebuilding a blueprint. A name is either a spacing step (`"xs"`, `"s"`, `"m"`,
`"l"`, `"xl"`) or a dotted path into the snapshot
(`"targetSizes.minimum"`, `"controlSizes.large.height"`,
`"controls.slider.thumbSize"`, `"strokes.hairline"`, `"radii.panel"`); a leading
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
`Path`, `Stage`, `Grip`. **Structural regions**: `When`, `ForEach`, `ErrorBoundary`.
**Style modifiers**: `shadow`, `gradient`, `corners`, `stroke`, `styleGroup`.

#### Continuous colour: `tint`

`Box`, `Text`, `Image`, `Path` and `Stage` accept a **`tint`** — the one
continuous colour channel, on the **binding** authority, for values a finite
selector cannot express. Two value forms:

| Form | Meaning |
|---|---|
| `{ role = "accent", blend = 0..1, from? }` | **themable, preferred.** Blends from `from` to `role` — both names from the closed palette vocabulary (`surface`, `surfaceStrong`, `content`, `contentStrong`, `contentSecondary`, `accent`, `control`, `controlSelected`, `danger`, `hairline`), resolved against the **active theme**. `from` defaults to the class's identity paint: the page colour for a `Box`, `content` for `Text`/`Path`, white (the picture as authored) for an `Image` — and white for a `Stage` too, for the same reason: white multiplies to the scene the engine already drew. `blend = 0` is the base, `1` is the role. |
| `{ direct = { r, g, b } \| "#rrggbb" }` | a **declared theming-exempt** identity hue — the loud word is in the value, so every use greps. Use it when the colour IS game data (a racer's hue), never for a state. |

**`transparency` (0..1, either form, default `0` = opaque).** The tint's own
alpha, engine-true and the same word and polarity as [`UI.stroke`](#uistroke).
It exists for the one thing a composite cannot express: a translucent plate over
a backdrop the author cannot know — a scrim over a live 3D scene, a label pill
over a canvas that draws its own content. Where the backdrop *is* known, prefer
stating the composite colour: one paint per node stays themable and
contrast-checkable, and an alpha does not.

It rides the tint's existing claim on a `Box` (a tinted Box has always owned
`BackgroundTransparency`); on `Text`, `Image` and `Stage` it claims one more
property (`TextTransparency` / `ImageTransparency`) and only when it is declared,
so a tint without it is byte-identical to before. A `Path` **refuses** it at the write
site — `Path2D` carries a colour and a thickness and no transparency at all — and
the error names the working idiom (fade the path's container).

**A value from a closed set is a state, not a tint.** Hover, selected, disabled,
verdict, phase — those stay `surface`/`role`/`selected` + tags + native-sheet
rules (ADR-0018), which is what keeps them themable and contrast-checkable.
Reaching for the continuous channel to express one is a defect, and the schema
cannot catch it for you.

**What a tint claims.** Each class hands the adapter exactly one paint channel:
`Box` → `BackgroundColor3` **and** `BackgroundTransparency` (a tinted Box paints —
a bare Frame is transparent until something says otherwise, so a colour alone
would be an invisible fill), `Text` → `TextColor3`, `Image` → `ImageColor3`,
`Stage` → `ImageColor3` as well (a stage's "picture" is the scene it renders and
the engine multiplies it through the same pair, so the tint hues the *content*,
not the plate), `Path` → the `Path2D`'s colour. In native-stylesheet mode those properties are
sheet-owned, so a tinted node **claims** them: the write is an intentional,
recorded defeat of the rule, published on the instance as the
`LuauUI_PaintClaims` attribute so the `GetStyled` authority audit reads a declared
hand-off instead of tripping on an accident. Two consequences, both by design — a
claim is permanent for the instance's lifetime (releasing a tint restores the
value recorded when the claim was taken; the engine has no operation that gives
ownership back), and a claimed property no longer follows a theme swap. That is
the price of a continuous channel, and the reason finite states must stay on tags.
The node's other properties are untouched: its tags stay, so its radius, its
hairline and its hover/press rules keep working.

### `Screen`

`UI.Screen{ id?, padding?, gap?, distribute?, surface?, children? }` — root container of a
presented screen; fills the presenter-resolved content rect (safe-area aware).
`distribute` is the shared main-axis distribution documented under `VStack` /
`HStack` below.

### `VStack` / `HStack`

`UI.VStack{ id?, gap?, padding?, align?, distribute?, wrap?, width?, height?, offsetX?, offsetY?, surface?, children? }`
— vertical / horizontal stacks. Children with `fill` dims share leftover
main-axis space by weight; `align` = `start | center | end | stretch` on the
cross axis. Stack children never overlap along the stack axis.

**`wrap = true` lets the children run onto more than one line** — Roblox's
`UIListLayout.Wraps`, and a stack that does not fit its main axis wraps instead of
painting past its own box. It is a **prop, not a class**: a wrapping stack is the
same stack in a second mode, so it keeps every other word it had, and it is
reactive — `wrap = adaptive.conditions(…).compact` re-solves in place and never
remounts a child. SwiftUI ships no flow layout at all (verified 2026-08-13), so
this is native parity, not SwiftUI parity.

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

**It does not compose with `newVirtualList`** — that is a deliberate non-goal. The
virtualizer windows by `index × pitch` and needs a uniform item extent; a wrapped
line has ragged extents and a variable items-per-line, so `index × pitch` cannot
window it. `newVirtualList`'s spec is closed, so `wrap` there is a construction
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

`UI.ZStack{ id?, alignH?, alignV?, width?, height?, surface?, canvasGroup?, opacity?, virtualSlot?, children? }` —
layered container; children align independently (`alignH`/`alignV`), `fill`
children stretch to the stack (scrims, backdrops).

`virtualSlot = { list, extent, axis?, contentFrom? }` declares that this stack is
**one slot of a fixed-pitch windowed list** — a list that places item *i* at
`i × extent` and therefore depends on `extent` being the item's TRUE size.
`newVirtualList` declares it on every row it builds, so ordinary callers never
write it; declare it yourself only on a hand-rolled surface that windows the same
way. It changes no geometry. Per solve, the solver measures the slot's content
(children from `contentFrom`, default 1) along `axis` (`"y"` default) and, when
that measure is **taller than `extent`**, files a finding through
`controller.diagnostics()` naming *both* numbers and the row — see
[a lying `itemExtent`](#a-lying-itemextent). Content SHORTER than its slot is
legitimate over-reservation and says nothing, and a cell that scrolls or clips its
own overflow is skipped. The finding is worded in `newVirtualList`'s vocabulary
(it quotes `list` and calls `extent` "itemExtent"), which is what a hand-rolled
declarer will read back.

`canvasGroup = true` makes this stack a **fade group**: the adapter materializes
it as a `CanvasGroup`, it becomes its subtree's real instance parent, and
`controller.setPresentationTransparency` fades the whole subtree through one
`GroupTransparency` write that no style rule owns. It is the container form of
`UI.Box{ canvasGroup = true }` (which fades a single plate), and it is what a
fading `transition` needs — a leaf has no subtree to fade. Not reactive: it
decides which engine class the node IS, at creation, and it costs a render
buffer, so declare it only where a group fade is wanted.

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
- **Resizing recreates the texture**, and LuauUI writes `Size` on every re-solve
  that changes the box. A group belongs on a subtree whose box is stable (a card,
  a toast, a screen), not on one that re-measures every frame.

### `ScrollView`

`UI.ScrollView{ id?, axis? ("y" default | "x"), padding?, gap?, autoscroll?, indicators? ("auto" default | "none" — a peeking carousel's affordance is the half-visible next tile, so it may declare its indicator off; layout is untouched), onScrollWheel?, children? }`
— scrolling container. `onScrollWheel(path, delta, rectOf)` receives
hover-wheel input routed by the adapter (the composite scrolling controls use
it; a plain `ScrollView` relies on the native host instead). the scroll axis measures children unbounded and reports
`contentSize` to the renderer. On the Roblox adapter it mounts as a native
`ScrollingFrame` (native-substrate NS-A2): the solver owns every content rect
and the canvas extent (`contentSize` + padding), while the ENGINE owns live
scrolling — wheel, touch momentum, elastic overscroll, and scroll bars. It is
always a clip host (`clipChildren` defaults true), so the fallback path (an
adapter without the scroll seam, e.g. billboards) still crops overflow.
**Both axes work.** `axis = "x"` lays children out along x, accumulates the
canvas extent along x, and stretches cross-axis `fill` children to the viewport
height (before this the solver stacked horizontal children in a column and
reported a canvas the engine could not scroll to).

**Scroll indicators (director ruling 2026-08-09).** The environment derives
`scrollIndicatorPolicy` from `interactionClasses.primary` — `"always"` on
pointer sessions (the desktop convention: a persistent bar whose thickness the
solver RESERVES off the scrolling region's cross axis), `"auto"` on touch and
gamepad sessions (the platform convention: OVERLAY indicators that lay claim
to no layout space, appear while scrolling, FLASH once when a scrollable
region first mounts — so a page that continues below never reads as cut off —
and fade when idle). Reduced motion never fades: `auto` degrades to
visible-whenever-scrollable. The presenter pushes the policy through the
declared optional target method `setScrollIndicatorPolicy(policy, reduced)`;
an adapter without the seam keeps the constant persistent bar. The indicator's
COLOR stays the theme's `Scroll bar` rule; its visibility is behavior, not
paint. Known limit, recorded: the engine bar is a single tintable image, so a
theme-colored thumb can vanish over live WORLD content behind a transparent
surface — outline indicator art is the follow-on (framework-fixes.md).

**`autoscroll` — drag-to-edge, and it belongs to the SCROLLER.** While a pointer
drag is in flight, a `ScrollView` whose edge band the drag point is inside scrolls
itself, so a drag can reach content below the fold. It is **on by default and
inert**: nothing happens unless a drag is announced, so a screen with no draggable
content behaves identically. Pass `false` to opt a scroller out entirely, or an
options table to tune the model (`bandH`, `dwellS`, `rampS`, `exitEaseS`, `vMin`,
`vMax` — see `LuauUI.newAutoscroll` for what each one means). The band defaults
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
| `controller.scrollToVisible(path)` | scroll the node's nearest `ScrollView` **ancestor** the minimum distance that brings the node fully into view; returns `false` when it is already visible, has no scroll ancestor, or the adapter has no scroll seam |
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

`UI.AdaptiveStack{ id?, axis?, gap?, align?, distribute?, padding?, surface?, children? }` — a
stack whose **`axis` is a reactive prop**. Bind it and a viewport, orientation, or
display-class change re-solves the stack in place:

```lua
-- pass the screen's scope: `conditions` builds six memos, and a screen that
-- rebuilds without owning them leaks six per cycle (see below)
local conditions = LuauUI.adaptive.conditions(core, env, { scope = scope })
UI.AdaptiveStack{ id = "Toolbar", axis = conditions.axis, gap = 8, children = { ... } }
```

Why this is a distinct class rather than a recipe: swapping `UI.VStack` for
`UI.HStack` through a `UI.When` is a STRUCTURAL change, so every child unmounts and
remounts and loses its state, focus, and scroll position on a phone rotation. One
class with a bound axis makes the flip a re-solve — the specs assert zero factory
reruns, zero creates, and zero removes across an axis change. `gap` is reactive for
the same reason, so spacing can adapt without a rebuild.

`axis` is `"y"` (default) or `"x"`; anything else fails at construction.
`distribute` is the same main-axis distribution `VStack` / `HStack` carry, and it
follows the axis: the leftover it spreads is always the leftover on whichever
axis is live.

### `ViewThatFits`

`UI.ViewThatFits{ id?, children (required) }` — tries its children as candidate
layouts in **declared preference order** and shows the first that fits, using the
real measurement contract against the space *this container* actually received.
The last candidate is the fallback when none fits (as in SwiftUI).

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
squeezed into.** SwiftUI selects "the first child whose *ideal size* on the
constrained axes fits within the proposed size", and an ideal size is what a view
reports when nothing is proposed to it — so truncation, `lineLimit` and
`minimumScaleFactor` are all invisible to the choice there. LuauUI's member of
that family is `shrinkWeight`, and it is invisible here for the same reason: a
candidate that only fits *after* being squeezed does not fit. Once a candidate has
won it is laid out against the real offer and shrinks normally, exactly as
SwiftUI hands its winner the parent's proposal. Picking is unshrunk; showing is
not. (`docs/lessons/a-candidate-is-judged-at-its-ideal-size.md` carries the
measurement, the citations, and the one place LuauUI still differs on purpose.)

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

This is also the **container-relative** condition: `LuauUI.adaptive.conditions` is
viewport-relative, while this measures the container.

### `Composition`

`UI.Composition{ id?, arrangements (required), groups (required), laneGap?, groupGap?, maxMeasure?, padding?, surface?, width?, height?, children (UI.Region…) }`
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
                   children = { twoLineTally, oneLineTally } },
        UI.Region{ id = "Hero",  group = "ceremony", rank = 3, floor = { lines = 1 },
                   children = { fullPlate, oneLineChip } },
        UI.Region{ id = "Field", group = "field", rank = 2, sizing = "fill",
                   mayScroll = true, floor = { lines = 1 }, children = { theList } },
        UI.Region{ id = "Ctas",  group = "next", rank = 1, floor = { targets = 2 },
                   children = { ctaRow, ctaColumn } },
        UI.Region{ id = "Tease", group = "next", rank = 9, mayDrop = true,
                   children = { twoLine, oneLine } },
    },
}
```

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
- **`groups`** — `{ id, lane | span, sizing = "hug"|"fill", weight?, place, minWidth?, gap? }`.
  `lane` is the affinity an arrangement's lanes absorb; `place` is `"start"` ·
  `"center"` · `"end"` or a fraction (the thumb-arc idiom is `0.66`); `minWidth`
  is a px number **or a theme metric name**, resolved every solve, and a `fill`
  lane below it makes that arrangement illegal.
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
the layout dump as `luauui-composition-dump/1`: which arrangement won, which form
and rect every region resolved to, which regions dropped, the **spanning rows**
(`spans = { { id, side, rect } }`, empty when none is declared — an additive key,
same schema), every lane's **`collapsed`** flag (rule 9 — a lane that used to be
omitted is now reported with `collapsed = true`; every lane a reader already saw
is unchanged with `collapsed = false`) and — for every richer
candidate — the **rule it broke** and the measured detail (`laneWidth`,
`overflow`). Read it live with `controller.compositionAt(path)`. In the mounted
dump a region is addressed by its **node path** (`/Screen/Results/Field`), exactly
like every rect key and every hidden root; the declared id is its last segment.
The same decision is callable with no tree at all through `LuauUI.composition`,
where a region id is simply whatever the caller passed.

### `Region`

`UI.Region{ id (required), group (required), rank (required), floor?, sizing?, weight?, mayScroll?, mayDrop?, reserved?, children (required) }`
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
| `reserved` | hold its box while its content rests **between pieces**, so a finishing transient never moves its neighbours. `true` reserves for the surface's whole life; **a `Readable<boolean>`** — the only reactive prop on a `Region` — reserves only while it reads true ("this schedule can still produce a piece") and releases the box, and with it the lane (rule 9), when it reads false. Mutually exclusive with `mayDrop` |

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

Declaration errors are refused at **construction**: an unknown field, a second
`mayScroll`, `reserved` with `mayDrop`, a rank that is not a positive integer, a
region with no forms, a duplicate id, a group with no home in some arrangement, an
unknown arrangement name, a `floor` that states neither `lines` nor `targets`.

### `Divider`

`UI.Divider{ id?, axis?, thickness?, width?, height? }` — an axis-aware hairline.
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

The hairline is **style-owned**: under native styling it carries the `luau-divider`
tag and the sheet's "Divider" rule paints it, so a designer can restyle every
separator in the place from one rule. On the fallback path the adapter writes the
hairline colour directly. It is never an unpainted `Frame` — an invisible divider is
exactly the accepted-and-ignored failure the strict-authoring work removed.

### `Grid`

`UI.Grid{ id?, columns? | minColumnWidth?, itemSizing?, gap?, rowGap?, padding?, surface?, children? }`
— row-major grid: children fill a fixed `columns` count, or a count derived
from `minColumnWidth` against the available width. `gap` spaces cells on both
axes. Use it for uniform tiled layouts (icon grids, match-3 boards) where a
stack's single axis is not enough.

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
1). A spanning cell contributes to **no** single column's maximum — SwiftUI's own
rule, so a span cannot widen one column on its own — and is then fitted to the
sum of the columns it covers plus the gaps between them. Naturals that do not fit
are reduced **proportionally** rather than overflowing, because the flow grid
cannot overflow (its column width is derived from the offer) and a row grid under
the same name must not either.

A row grid also feeds the focus map: the D-pad walks the rows you declared. (A
grid without `GridRow` children keeps inferring its rows from `columns`.)

### `Text`

`UI.Text{ id?, text (required), textSize?, textAlign?, lineLimit?, disclose?, reveal?, role?, surface?, tint?, width?, height? }`
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

**`lineLimit`** caps how many lines this label may occupy (SwiftUI's
`.lineLimit`; a px number or a theme metric name, minimum 1). Beyond the cap the
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
**Full-value disclosure** under `newPresenter`). It does nothing while the text fits,
so declaring it costs nothing; **omitting** it on text that truncates is what the
text audit reports as a clipped-essential finding. Binding a Readable here is
refused with the rebuild idiom, exactly like `traversalPriority`.

**`reveal`** (`"auto"`, construction-only; director ruling 2026-08-04, superseding
LTN-2's "no marquee" for surfaces that declare it) makes a truncated **one-line**
label auto-scroll its whole value instead of resting behind the ellipsis alone.
The presenter owns the cycle (see **The auto reveal** under `newPresenter`): a
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
Image take the full eight-surface vocabulary; a Text takes the two that are
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

**`tint`** is the continuous-colour channel (see [above](#continuous-colour-tint));
on a Text it claims `TextColor3`. `role` remains the way to say "secondary" — a
tint is for a colour a role cannot name, and it leaves `TextTransparency` alone so
the disabled state still dims.

`color` and `font` are **diagnosed, not accepted** (see `DEPRECATIONS`).
Neither ever reached a render target: `color` was dropped entirely, and `font`
reached only the measure seam, so an authored font silently made measured and
painted bounds disagree. Both are style authority — use `role`.

### `Image`

`UI.Image{ id?, image?, surface?, tint?, scaleMode?, width?, height? }` — image
node; `image` is an asset string (pair with `newResourceProvider` for async
ready/pending/failed handling). `image` is optional so a node can mount empty and
receive content later — that is exactly what `newAsyncImage` binds.

**`scaleMode`** decides how the picture fills the box the solver already sized —
`"fit"` (contain: the whole picture, letterboxed), `"fill"` / `"crop"` (cover:
aspect preserved, overflow cropped), `"stretch"` (ignore the aspect ratio, the
engine's own default). `fill` and `crop` are deliberate synonyms: Roblox's `Crop`
*is* the cover behaviour other vocabularies call fill, and neither audience should
have to look it up. Nine-slice is **not** offered here — slice geometry is
theme-owned chrome (a package's `sliceCenter`/`sliceScale`), and an authored slice
would be a second authority over the same engine properties. `scaleMode` is style
authority and it claims `ScaleType` in native mode, exactly as `tint` claims a
colour.

**`tint`** multiplies the picture (`ImageColor3`; see
[above](#continuous-colour-tint)). It leaves `ImageTransparency` alone, so a dim
treatment composes with it rather than fighting it.

### `Button`

`UI.Button{ id?, label (required), compactLabel?, enabled?, selected?, role?,
shape?, icon?, gap?, align?, children?, onPointerDown?, onPointerMove?,
onPointerUp?, onPointerCancel? }` — activatable control.

**Custom content.** A Button takes `children`, which render inside the ONE
activation surface. `label` stays **required** even for an icon-only button — it is
the semantic label — and when content is present the button paints no text of its
own, so the label never shows through beneath the content. A focusable in the
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
  control's content and the word is its name: `newRowActions`' tray buttons are the
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
  normally ask for its content size — so the icon-button shape every spec writes for
  a 44 px control (`width = height = { type = "fixed", px = "targetSizes.minimum" }`)
  used to skip the ladder entirely and paint its full label ellipsized. The case
  `compactLabel` exists for was the one case that could not reach it (found live
  2026-07-30). The measure is now forced for any node that declared a compact form.
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

**Semantic roles.** `role` is `"default"`, `"cancel"`, or `"destructive"`. It drives
a style **tag** and its sheet rule (`Destructive button`, `Cancel button`), never a
bespoke fill, so a designer retheming those rules restyles every such button. The
destructive palette is a gated `$Danger`/`$OnDanger` token pair, and the role is not
colour-only — it carries the tag and semantics too. A style that predates the pair
keeps working: the library default fills in and the contrast gate runs on the
effective pair.

**Circle buttons.** `shape = "circle"` turns the button into a true 1:1 disc — the
floating round "…" action. It is **not reactive**: a shape is what the control *is*.

- **Geometry is solver-enforced; you never do the math.** The diameter comes from
  the control metric `controls.button.height`, resolved from the live theme
  snapshot, so a metric package resizes every disc and a pixel package snaps it
  onto its grid. Author one axis (`width` *or* `height`) and the other follows 1:1;
  author neither and both are the metric. Authoring **both** is refused at
  construction — that is the author doing the math the solver already does.
- **Content is one mark.** Either a semantic `icon` or a short `label` of at most
  **3 characters with no spaces**. A longer or multi-word drawn label is refused at
  construction, naming the field, the rule and the fix. The default padding is `0`
  (the diameter *is* the box); an explicit `padding` still wins.
- **`icon` is a semantic NAME, never an asset id** — `"more"`, `"close"`, `"menu"`,
  `"chevron.trailing"`, or a package's namespaced `"ns:name"`. The framework draws
  its own ASCII-safe glyph for that name immediately, so the affordance is legible
  under *every* theme, and a package that ships art for the name has the adapter
  paint the picture over it, tinted by that asset's `tintRole`. With an `icon` the
  `label` stays the **semantic name** and is not drawn — so an icon button still
  has a real accessible name. `icon` is circle-only; for an icon *beside* a title,
  put a `LuauUI.newLabel` in the button's `children`.
- **Paint costs a flat theme nothing.** The pill radius and the rim are phantom
  `::UICorner` / `::UIStroke` rules on the `luau-shape-circle` tag (the same radii
  machinery the slider thumb uses) — no extra instances. The rim carries
  `ApplyStrokeMode = Border`, so it outlines the disc instead of haloing the glyph.
- **Skinning needs no new slot.** A circle Button classifies to the ordinary
  `control` decoration slot, so a package dresses it with the same recipe it
  already writes — whole-image round art works exactly like the ornate stepper
  plate. Once art covers the node the image *is* the silhouette (ADR-0020 R9): the
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
Return / ButtonA) to it with NO consumer `present()` wiring (ADR-0013). An
explicit `opts.onActivate` on `present()` overrides it.

#### Hit-target floor

`Button`, `Toggle`, `TextField` and `Grip` declare a 44 px minimum effective target
(`src/controls/contract.luau`). The renderer now **enforces** it: after each solve,
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

`UI.Toggle{ id?, label (required), value?, enabled?, disclose?, onActivate? }` —
boolean control. When `value` is a settable Signal the presenter AUTO-FLIPS it on
Activate (tap / Return / ButtonA) with no consumer wiring (contract "Activate
flips value"; ADR-0013). Supply `onActivate(path, meta)` to take over the effect,
or an explicit `opts.onActivate` on `present()` to override the whole auto path.
The label draws ONE line with an end ellipsis by measured design (a wrapped label
plus the press-scale affordance produced mid-word breaks — director finding 13),
so `disclose` (construction-only, Step 8.5) is the label's full-value path: where
a compact width truncates it, engaging the toggle (hover dwell / focus /
long-press) presents the full label through the presenter's static disclosure
plate, exactly as a `Text` with `disclose` does.

### `TextField`

`UI.TextField{ id?, text?, placeholder?, editing?, enabled?, focusable?,
maxLength?, keyboardType?, onTextChanged?, onFocusGained?, onFocusLost? }` —
the text-entry leaf primitive the renderer maps to an engine `TextBox`. All of
`text`/`placeholder`/`editing`/`enabled`/`maxLength`/`keyboardType` ride the
binding authority (the engine adapter maps `editing` to CaptureFocus/
ReleaseFocus, `text`/`placeholder` to `.Text`/`.PlaceholderText`); layout/style
props inherit `common`. The three handler props are functions the adapter wires
through the optional `setTextInputHandlers(handle, handlers)` seam
(`handlers = { onTextChanged(text), onFocusGained(path), onFocusLost(reason) }`,
`reason ∈ "enter" | "focusLost" | "cancel"`; `path` is the focused node's full
path — engine-initiated focus must deliver it so occlusion keep-visible works
without a prior activate). Prefer the `LuauUI.newTextInput`
composite over building on the raw primitive.

### `Box` / `Spacer`

`UI.Box{ id?, width?, height?, surface?, tint?, canvasGroup?, opacity?, offsetX?, offsetY? }`
— plain rect. `UI.Spacer{}` — takes space in a stack (pair with `fill` dims).

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
NORMALIZED control points from `LuauUI.pathShapes` — a points change is a
paint-only prop write (never a re-solve), and the adapter re-scales the same
normalized points when the solved rect changes. `role` picks the stroke color
from the style (`"accent"`, `"secondary"`, default content) — never a raw
color — or, for a value no role can name, `tint` (see
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
character turnaround, a hero rig) instead of content LuauUI lays out. The adapter
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

`surface` is the standard eight-surface vocabulary (`base`, `raised`, `control`,
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

**Who owns what.** LuauUI owns the frame, the `WorldModel`, the `Camera`, the box,
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

### `Grip`

`UI.Grip{ id?, cursorHint?, focusable?, focusVisual?, onPointerDown?,
onPointerMove?, onPointerUp?, onPointerCancel? }` — non-button pointer zone with
capture-based drag routing (used by Table column resize). Opt-in focusable for
gamepad reachability, where the focus-gated `Adjust` verb replaces the drag (a
virtual cursor cannot see a `MouseIcon` hint).

**`focusVisual`** (construction-only) is `"default"` or `"none"`, and it answers
*who draws the focused state*. A focused Grip fills with the accent colour,
because a thin sliver wearing a hairline ring read as "focus went nowhere" in the
2026-07-20 hand test. That is right for a resize handle and wrong for a control
whose grip spans its whole width: `newSlider`'s track is exactly that, and filling
it paints a solid bar over the value the player is trying to read. `"none"` says
this control paints its own focused treatment, so the adapter paints none — the
decision is made in the renderer, where the node is visible, and a control that
declares it owes a focused treatment of its own. Handlers receive `(path, pos, rectOf)`;
`onPointerDown` may return `false` to decline the capture so a sibling zone
under the same point can take it, and `onPointerCancel(path, reason)` may
return `true` to keep a capture alive when its origin node unmounts mid-drag.

`rectOf` here is the renderer's **`screenRectOf`** — the rect where the node is
painted, not the solved one (see "Two rect reads" under `newRenderTarget`). `pos`
always arrives in window space, so the lookup a pointer handler is given has to
answer in window space too: a node inside a scrolled container solves in canvas
space, and a handler that mixed the two put its drag arithmetic off by the
container's scroll offset. Ask it again on every move rather than caching the
answer from `onPointerDown` — a scroll host above the node can move it under a
live capture (found on device 2026-07-28: dragging a row in the playlist example
while the page scrolled left the ghost chip behind by exactly the scroll).

### `When`

`UI.When{ id?, condition (Signal/Memo), thenView (() -> Blueprint), transition? }` —
structural region: mounts/unmounts its branch when `condition` changes. Only
structural regions may mount or unmount nodes. `transition` declares how the
branch comes and goes — see **Structural transitions** below.

### `ForEach`

`UI.ForEach{ id?, items (Signal/Memo of array), key (item) -> string, row (item, itemScope) -> Blueprint, transition? }`
— keyed structural region: add/remove/move only; surviving keys keep their
mounted identity and scopes; duplicate keys are hard errors. `row` receives
the item's ownership scope so cells can own item-lifetime resources (async
handles, per-row memos). `transition` applies per keyed row — see **Structural
transitions** below.

#### Structural transitions

`transition = { enter, exit?, class?, fade? }` on `UI.When`, `UI.ForEach`, a
`presentToast` and `PresentOpts` (ADR-0022 Decision 3).

- **Forms:** `"fade"`, `"slide-up"`, `"slide-down"`, `"slide-left"`,
  `"slide-right"`, `"materialize"` (scale 0.96 → 1 with a fade), `"instant"`.
  A form names the direction of **travel** — an enter travels toward rest, an
  exit away from it.
- **`exit` defaults to the mirror of `enter`** (`slide-up` ⇄ `slide-down`,
  `slide-left` ⇄ `slide-right`): *if it disappears one way, it emerges from
  where it came*. An asymmetric exit is legal but must be **declared**
  (`exit = "instant"` is the common one) — undeclared asymmetry does not exist.
  Because a mirror pair displaces the node to the *same* absent place, a
  re-entry mid-exit reverses through one continuous motion.
- **`class`** names a motion class (default `"container"`); **`fade = true`**
  pairs a slide with a transparency fade.
- **A fading form needs a fade group.** `fade`, `materialize` and
  `fade = true` drive transparency, so the region's child must be declared
  `UI.ZStack{ canvasGroup = true }` (or `UI.Box{ canvasGroup = true }` for a
  single plate). Anything else is an authoring error that names the fix.
- **A departing subtree RETIRES, it does not vanish.** It stays mounted in its
  slot (a `ForEach` row exits in place, clamped to its old index), turns
  **non-interactive** — focus order and tap routing both skip it and everything
  beneath it — and disposes when the exit completes. Re-entry mid-exit reuses
  the same mounted subtree: same node identity, same scopes, same instances,
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

`UI.shadow(blueprint, presetOrParams, style?) -> Blueprint` — SwiftUI-style
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
child named `LuauUIGradient` — never a sheet rule, because a rule matches a
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
across three packages the same `LuauUIGradient` survived with identical stops and
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

| Field | Meaning |
|---|---|
| `thickness` | px, or a stroke token name (`"hairline"`). Default: the style's hairline weight. |
| `color` | a colour token name resolved against the active style (`colors` first, then `extra`), an `{ r, g, b }` table, or a `"#rrggbb"` literal. Default: the `hairline` role. |
| `transparency` | 0..1. Default: the style's hairline opacity. |

Architecture follows `UI.gradient` exactly: bounded normalized data, materialized
by the adapter as **one** bespoke `UIStroke` child named `LuauUIStroke` and
**reused**, never re-created — so a reactive pulse or a theme swap can never stack
two borders on one node — and destroyed when the declaration goes away.
`ApplyStrokeMode` is always `Border`, because the engine default (`Contextual`)
strokes a text node's *glyphs* instead of its box.

**It is additive, not a replacement.** A theme's own chrome stroke is a phantom
`::UIStroke` **rule**, and the engine renders a real `UIStroke` child alongside it
(ADR-0020 R8, measured live) — so an authored stroke composes with a panel's
hairline rather than suppressing it. A node that must show exactly one border
should name a surface that carries none (`plain`).

### `strokeData`

`UI.strokeData(spec, style?) -> StrokeData` — the same normalization as
`UI.stroke`, without a blueprint. It takes the identical
`{ thickness?, color?, transparency? }` spec (same defaults, same closed key set,
same refusals) and returns the normalized data table, so it is what you build a
**reactive** stroke out of.

Normalized style data is read once at construction, so a Signal *inside* the spec
is refused there and the error names this fix: bind the whole `stroke` prop
instead.

```lua
UI.Box({
    id = "Row",
    surface = "control",
    stroke = core:memo(function()
        return UI.strokeData({ thickness = 2, color = "accent", transparency = pulse:get() })
    end),
})
```

### `shadowData` / `gradientData` / `cornersData`

`UI.shadowData(spec, style?)`, `UI.gradientData(spec, style?)` and
`UI.cornersData(spec, style?)` complete the family: each is the normalizer its
modifier already uses (`UI.shadow` / `UI.gradient` / `UI.corners`), without a
blueprint, returning the normalized data table. Same specs, same defaults, same
closed key sets, same refusals — and the same reactive idiom as `strokeData`
above, so an animated blur, wash or radius is a **pulsing prop** rather than a
rebuilt blueprint:

```lua
UI.Box({
    id = "Card",
    surface = "raised",
    shadow = core:memo(function()
        return UI.shadowData({ blurRadius = { offset = use(lift) }, color = "shadow" })
    end),
})
```

`UI.gradientData` does not run `UI.gradient`'s text-bearing wall, because there
is no blueprint here to judge; the wall still applies wherever the data is bound.

### `draggable` / `dropTarget`

`UI.draggable(blueprint, spec) -> Blueprint` and
`UI.dropTarget(blueprint, spec) -> Blueprint` — the public drag/drop contract
(ADR-0022 Decision 5, rows SF-D1/SF-D5). They are **declarations**, not wiring:
each returns a new frozen blueprint carrying a validated declaration on the
metadata channel, and the renderer builds the acquisition when the node mounts.
The same declaration therefore works on a node an author wrote and a row a
control generated.

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
| `declineTouch` | touch presses **decline the capture** so a native scroll host under this node keeps the pan. A row inside a `ScrollView` sets it; a card lying on a screen does not. Pointer/pen acquisition is unaffected. |
| `promotionPx` | per-class overrides for the promotion gate (`{ pointer = 8 }`); absent keys fall through to `interactionTokens`. |
| `enabled` | a boolean or `Readable<boolean>` gating **acquisition only**. While it reads false this source arms nothing and promotes nothing, and the node stays enabled, hit-testable and activatable — which is what a control that must *explain* why it cannot be picked up needs ("disabled stays inspectable"). Setting `enabled = false` on the node itself also refuses acquisition, and additionally kills the tap, so it cannot serve that case. |

**The held source empties — a framework guarantee.** While a live session
carries a node's payload (pointer drag or the armed paradigm alike), the
framework stamps that node with the `dragHeld` state: the registry publishes it,
the renderer writes it, and every theme's sheet empties the node's label through
the `luau-drag-held` rule ("the slot sits empty until it lands or returns").
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
silent. LuauUI never invents legality, and there is exactly one legality path for
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

**Form 1 — the change form**, `{ trigger, event }`. SwiftUI's
`.sensoryFeedback(_:trigger:)`. When the `trigger` Readable **changes**, the
framework emits `{ type = event, path = <this node's mounted path>, surface =
<the surface> }` on the presenter's feedback bus, synchronously, inside the write
that moved it.

**Form 2 — the control form**, `{ activation }`. No SwiftUI equivalent. It names
what **this control's own press** means, and the presenter emits that verb in
place of the `activate` it would otherwise emit, stamped `reason = "activation"`.

| Field | Meaning |
|---|---|
| `trigger` | change form, required. A `Signal`/`Memo`. Its **transitions** are the cause; the value itself never reaches the event. A plain value is refused — it can never change, so the declaration would be accepted and inert. |
| `event` | change form, required. One of the closed twelve: `activate`, `select`, `adjust`, `pickup`, `commit`, `reject`, `cancel`, `arrive`, `land`, `dismiss`, `supersede`, `celebrate`. Anything else is an authoring error at the call site that lists the vocabulary. |
| `activation` | control form, required. One of the same twelve, **plus `"none"`** for a control that is deliberately unfelt (it emits nothing at all rather than a verb every subscriber must know to ignore). |

Passing keys from both forms in one spec is refused: two causes and one verb has
no honest reading. Declaring `activation` twice on one node is refused too — a
control has one activation sensation, and a silent last-writer-wins would make
the two orderings of the same two modifiers produce different results.

**LuauUI plays nothing.** SwiftUI's modifier names a haptic; this one names a
verb, and whether that becomes a rumble, a sound, a particle or nothing at all is
the subscriber's ruling (`presenter.onFeedback` / `handle.onFeedback`).
`src/client/haptics.luau` is one opt-in, default-off subscriber — see
[Client entry points](#client-entry-points).

**The control form CASCADES.** It is resolved down the mounted tree, nearest
declaration winning, which is what lets it reach the composite controls
(`newChip`, `newStepper`, `Table` rows, `newPopupButton` …) that build their own
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
local hearts = core:signal(3)

local heart = UI.sensoryFeedback(
    UI.Text({ id = "Hearts", text = core:memo(function(use) return `{use(hearts)} ♥` end) }),
    { trigger = hearts, event = "adjust" }
)
```

Like the drag declarations it rides the metadata channel rather than the prop
bag, it returns a **new frozen blueprint**, and it **refuses a structural region**
(`When`, `ForEach`, `ErrorBoundary`) — those mount no node of their own, so the
declaration would have been accepted and never emitted. It **composes**: applying
it twice to one node declares two triggers, and both fire.

The change form's observer is owned by the mounted node's scope, so it stops the
frame the node unmounts, and it is built **only** when a presentation layer is
wired — a bare `mount()` with no feedback sink buys no observer at all. The
control form buys **no observer**: its cause is a press, which the presenter
already owns, and a tree that declares nothing carries no extra field on any node.

The control form also reaches the **engine**: the renderer publishes each
activatable control's resolved verb to the adapter, which the Roblox target
realizes as a `LuauUI_ActivationFeedback` attribute, and the opt-in haptics
adapter hands that button the effect its verb maps to. So a Buy button and a
Cancel button feel different — and LuauUI still never calls `Play()` for a press.

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
| `frame` | `UI.frame(bp, spec)` | exact `width`/`height`, or a `minWidth`/`idealWidth`/`maxWidth` band (same for height). `maxWidth = "infinity"` is SwiftUI's fill idiom. An unknown field in `spec` is an error, not a no-op. |
| `padding` | `UI.padding(bp, sides)` | inner spacing; `sides` is a number or `{top?,right?,bottom?,left?}`. Valid on containers, `Button`/`Toggle`/`TextField`, and `Text` (whose measure adds it). On any other class it errors and tells you to wrap the node — it never silently does nothing. |
| `offset` | `UI.offset(bp, x?, y?)` | arrange-only placement offset (no re-measure); meaningful for a child of `UI.Anchor` |
| `aspectRatio` | `UI.aspectRatio(bp, ratio)` | derives the height from the resolved width (16:9 media). A non-positive ratio is an error. |
| `alignment` | `UI.alignment(bp, horizontal?, vertical?)` | placement inside a `ZStack` parent |
| `overlay` | `UI.overlay(bp, content, align?)` | layers `content` **above** `bp` |
| `background` | `UI.background(bp, content, align?)` | layers `content` **behind** `bp` |

`overlay` and `background` are the only two that change **structure** — a layered
pair is a `ZStack` — so they need the base to carry an explicit `id`. The wrapper
takes a derived id and the base keeps its own, so the base stays addressable by
focus, tests and dumps at `<parent>/<id>+overlay/<id>`.

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
applies the modifier set to EVERY element of a collection (SwiftUI `Group`
semantics); returns the new array (use as a `children` list). All four style
modifiers are members, and the spec's key set is closed: an unknown key is a
construction error naming the four, rather than a style that silently never
appears. Spec-first is deliberate — the collection is the thing being produced
(constitution E-3).

---

### `newAsyncImage`

`LuauUI.newAsyncImage(LuauUI, core, spec) -> { blueprint, state, handle }` —
an Image whose content arrives through the async resource provider
(native-substrate NS-A14): `spec = { id, scope, provider, key, width?,
height?, failureLabel?, retry?, dimmed? }`. Shows a placeholder surface while
`pending`, the fetched content when `ready`, and a visible failure mark when
`failed`.

`retry` passes a per-call-site retry policy (`{ count, delaySeconds?, giveUp? }`)
straight through to `provider.acquire` — an avatar in a results list can afford
two spaced attempts where a decorative badge cannot. **Failure stays silent**
either way: the placeholder persists, and there is never a spinner or a
broken-image glyph.

`dimmed` (a `Bound<boolean>`) applies the dim treatment: the image blends 35 %
toward the `surface` role through the authored `tint` channel — themable,
contrast-checkable at both ends, and no contest with native-sheet paint. The
undimmed value is the same tint at blend 0, so toggling the state never adds or
removes a paint claim mid-life; an image that declares no `dimmed` carries no
`tint` at all.
`state` is the provider's Readable. The provider handle is owned by `scope`;
releasing it makes any late completion STALE (never applied) and prevents
queued-unstarted work — it does NOT stop an in-flight engine fetch (Roblox
exposes no cancellation; measured 2026-07-23). The Roblox transport is
`src/client/roblox_resources.luau` (`bind(provider) -> unbind`), which fulfils
requests via `ContentProvider:PreloadAsync` per-asset statuses.

### `pathShapes`

`LuauUI.pathShapes` — pure, headlessly-tested shape math for `UI.Path`
(`src/controls/path_shapes.luau`): `arc(startDeg, sweepDeg, { segments?,
radius? })`, `ring({ radius? })`, `needle(angleDeg, { innerRadius?, radius? })`
return normalized control points (unit box; tangents relative to each point;
exact circular-arc bezier handles). Angles are screen-clockwise with 0° at
12 o'clock. Segment counts assert the engine's 100-point limit.

### Engine-selection bridge (a presentModal opt)

`presentModal(bp, { engineSelectionBridge = true })` — opt-in mirror of
LuauUI's logical focus to `GuiService.SelectedObject` while the modal owns UI
input (native-substrate NS-A12). Modal-only: `present()` ignores the opt so
passive/gameplay surfaces always keep `SelectedObject = nil` (NS-A11). The
mirrored instance is made `Selectable` only while selected (the engine warns
and reassigns selection set on a non-selectable object — measured); expect
native autoscroll inside scroll hosts; the bridge clears on dismiss/teardown.
EXPERIMENT until the physical-gamepad row (ledger NS-P1) closes — LuauUI's
focus graph remains the authority and every surface works with the bridge off.

## Mounting and rendering

### `mount`

`LuauUI.mount(core, blueprint, opts?) -> MountedRoot` — materializes a
blueprint over a core. Factories run exactly once per node; dynamic props
subscribe to their declared update classes. `opts.scope` supplies an owning
scope. MountedRoot: `.node` (tree), `.takeDirty()` (drain the update queue),
`.counters()` (`{ mounted, factoryRuns }`), `.dump()` (deterministic tree),
`.dispose()`.

`opts.transitions` supplies the structural-transition collaborator — the
presenter passes one automatically, and a bare `mount` + `renderer` consumer can
build its own with `require("…/render/transitions").new{ core, clock }`. The
contract: `shouldRetire(path, node) -> spec?` (nil = dispose now),
`beginExit(path, node, spec, done)`, `cancelExit(path)` (an exit that is no
longer wanted — the enter that follows reverses from the value *and* velocity it
parks at), `beginEnter(path, node, spec)`, and optional `release(path)` (the
region is being torn down; drop any motion for that path). The mount layer owns
lifetime and identity; the collaborator owns time — which is why the 500 ms cap
lives in the coordinator and not here.

### `renderer`

`LuauUI.renderer` is a namespace, not a factory: it carries the attach verb
**and** the adapter-conformance data an adapter author writes against
(constitution E-10 — `attach` is not `newRenderer` because the controller's
lifetime is the mount's, not the module's).

**Module exports**

| Export | What it is |
|---|---|
| `renderer.attach(core, mountedRoot, env, adapter, opts?) -> Controller` | bind a controller to a mounted root (below) |
| `renderer.EMITTED_PROPS` | frozen set of **every** prop name this module can hand to `adapter.setProp`. This is the conformance list a render target implements against, and `tests/render_target_contract.spec.luau` fails when the live and fake adapters disagree with it |
| `renderer.DIRECT_PROPS` | frozen `prop -> which seam writes it`, for the writes that do not ride the style or binding channel (`clipChildren`, `textSize`, `padding`, `transform`, `transparency`) |
| `renderer.STYLE_PROPS` / `renderer.BINDING_PROPS` | the two channel sets, keyed by prop name: which writes are style authority and which are binding authority |
| `renderer.compactForm(props) -> form?` | pure: the normalized compact representation of a `Button`'s `compactLabel` (`{ kind = "text" \| "icon" \| "image", … }`, `nil` when none). The one place the authored grammar becomes a shape, shared by the measure seam, the paint seam and the adapter |
| `renderer.drawnButtonText(props, compact?) -> string` | pure: what a `Button`'s own engine text node actually shows (empty for a content button; the framework's ASCII-safe glyph for an icon button) |

**`attach` options** — `{ rootPolicy?, onNodeTap?, engineSelectionBridge?,
onDiscloseHover?, onDiscloseLongPress?, recycleInstances?, incrementalLayout? }`
(the last two are the two performance opts described under `present()`, both on
by default; a presented surface forwards its own).
`rootPolicy` is the surface's content-rect policy (`"coreSafeContent"` default,
`"deviceSafeContent"`, `"edgeToEdge"`; an unknown value errors and lists the
set). **`onNodeTap(path, meta)` takes two arguments** — `meta` carries the tap
geometry (`x`/`y`) the outside-tap policy reads, and `via` for a
detector-driven tap. **`engineSelectionBridge`** is the same opt-in mirror
`presentModal` exposes, available here for a hand-attached surface.
**`onDiscloseHover(path?)` / `onDiscloseLongPress(path?)`** (Step 8.5) receive
the live adapter's disclosure engagement zones on `disclose` text nodes —
`path` on engage, `nil` on disengage; the presenter routes them to its
`_discloseHover`/`_discloseLongPress` seams. Omit both on a hand-attached
surface and no zones are wired (focus-driven disclosure still works).

**Controller** — 35 members, all dot-called:

| Group | Members |
|---|---|
| Render cycle | `initialRender()`, `refresh()`, `dispose()` |
| Geometry reads | `rectOf(path)` (solved), `screenRectOf(path)` (painted — see "Two rect reads"), `hiddenRoots()`, `compositionAt(path?)`, `textAt(path?)` (the per-text-node facts of the last solve: font, size, lines, naturalLines, truncated, disclose, reveal, naturalWidth, policy — the channel the disclosure plate and the auto reveal both read), `structureEpoch()` (a monotonic counter bumped by exactly the two things that change what a tree derives to — a structural sync, and a change in which roots are hidden — so a caller can cache a derivation on it instead of redoing it every frame, which is what the presenter's focus map does) |
| Focus | `setFocusPath(path?, visible?)` |
| Scrolling | `scrollTo(path, {x,y})`, `scrollPosition(path)`, `scrollToVisible(path)`, `scrollHostFor(path, includeSelf?)` (the nearest `ScrollView` ancestor's handle — reach for this instead of re-deriving the host), `observeScroll(path, fn) -> unsubscribe`, `stepAutoscroll(dt?)`, `setPointerDrag(info?)` |
| Drag | `dragRegistry()` (builds one on demand), `peekDragRegistry()` (nil when none exists yet), `setDragCollaborators(collaborators)`, `attachDragDetector(path, handlers) -> detach?` |
| Presentation channel | `setPresentationTransform(path, t?)`, `setPresentationTransparency(path, alpha?)`, `setPresentationOffset(dy)`, `setPaintHeld(path, held)` (hold a node's own paint while something is painted over it — the auto reveal's strip is the framework's only caller; the solve, the rects and the truncation facts are untouched, and the hold survives a re-solve and a remount of that path) |
| Engine content | `stageHost(path)` — the `UI.Stage` seam, nil on an adapter without it (see [The content seam](#the-content-seam-controllerstagehostpath)) |
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
declared it means to cover the other are reported on both of them
(ADR-0028). It is a defect like any other, and the three ways to say you meant it
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
(`src/layout/solver.luau`, the composition arrange branch), and both LuauUI's
always-on overflow sweep and Rascal Rally's own screen checks read it — they used
to recognise the sentence separately and had reached opposite conclusions about
whether it counted as a defect. A designed report added later is handled
correctly by every consumer on the day it is written.

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
  `LuauUIMotionScale` `UIScale`, removed at rest — and on a pressable control it
  *shares* that control's own `UIScale`, because the engine honours one per object.
  `rotation` maps to `GuiObject.Rotation`, which is paint-only in Roblox. `nil`
  clears. Values are compared before writing, so a settled motion costs nothing.
- `controller.setPresentationTransparency(path, alpha | nil)` — fades a **fade
  group**: the node must have been declared `UI.Box{ canvasGroup = true }`, and the
  refusal for any other node is loud and names that fix. One `GroupTransparency`
  write, which no style rule owns, so a fade never contests native-sheet paint.

`setPresentationOffset(dy)` (the keyboard keep-visible shift the presenter drives)
is now this channel's first consumer rather than its own special case. **On the
real client the instance tree is flat** — every node parents under the ScreenGui
unless a real parent claimed it — so an offset accumulates down the subtree: a node
pays its own transform plus every ancestor's, stopping at its real parent, whose
own move already carries it. That is what makes a transform on the root move the
whole surface instead of one transparent frame, which is exactly how SF-M9 hid: the
prop was written, the fake adapter recorded it, and the live adapter had no branch
for it at all. `FakeTarget` now mirrors the composition (`node.presentedPosition`)
and both adapters declare which props they handle, so
`tests/render_target_contract.spec.luau` fails if they ever diverge again.

Scale and rotation reach the node's own instance (and whatever is really parented
under it) — to scale a subtree, put the transform on a `canvasGroup` node.

**Two rect reads, and which one a pointer question takes.** `controller.rectOf(path)`
answers the **solved** rect — layout space, what the solver wrote, and what a
consumer computing layout facts wants. `controller.screenRectOf(path)` answers the
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

One consumer still reads the solved rect: the presenter's `syncGeometry`/`onGeometry`
feed, which Slider's track math and the presenter's zone-A outside-tap test use. A
slider inside a scrolled container or under a live enter/exit slide therefore still
scrubs against layout space (ESC-2 residual, tracked in
`artifacts/sponsor-framework-gaps/responsibility-ledger.md`).

### `newPresenter`

`LuauUI.newPresenter(core, env, adapter, actionSystem, opts?) -> Presenter` —
owns screen/modal lifetimes, focus scopes, and input contexts. `opts` is
`{ clock?, now?, keyboardNavigation? }`: pass `clock` to share one motion clock
with the rest of the application, `now` to inject time.

#### `presenter.withAnimation(class, fn)`

```lua
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
  property SwiftUI animates this way (opacity, rotation, scale, colour) is an
  *authored paint* value, and LuauUI has no authored prop in the presentation
  channel for one to be diffed from — see `swiftui-parity.md` §6's `opacity(_:)`
  row for the authority decision that has to happen first.
- **A size delta does NOT reach into the subtree**, and this is the one rule to
  carry away. A position offset accumulates downward (LuauUI's instance tree is
  flat, so a container's move carries nothing inside it and every descendant
  re-adds its ancestors' offsets); a size delta is the node's own and stops
  there. A label pinned to the top of a growing card stays exactly where it is
  while the box opens underneath it — it neither drifts nor stretches.
- **The box's interior relayouts while it travels**, because it is a real engine
  `Size`: a wrapped label re-wraps at the intermediate width, a clip host crops
  at the intermediate height, a `canvasGroup` re-buffers each frame. That is what
  animating a size means (SwiftUI's frame animation behaves the same way), but
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
pure continuity. (Contrast `newProgressView`'s indeterminate indicator, which is
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
flushed — an outer `core:transaction` is still open, or this ran during a core
commit — it raises **after `fn` has already been applied**: the change landed
instantly with no flight, so a caller catching it must **not** retry the mutation
or it lands twice.

**There is no cap on how many records one frame may install.** An earlier draft
of this entry described a per-frame ceiling past which the commit would land
instantly with a diagnostic; that ceiling was designed but never built, and the
paragraph describing it was a claim the code did not honour — the exact defect
constitution §14 rates as severely as the reverse. It is recorded as a gap
rather than quietly implemented, because the design required the number to be
*derived* from measured work (subtree rect writes, elision materializations)
rather than picked, and no such measurement has been taken. In practice the
roots-only rule keeps the count near the number of things that actually started
moving, and the adversarial review found no frame-budget problem — so this is a
missing guard, not a live defect. `presenter.animationRecordCount()` reports the
live count if you want to assert a bound yourself.

`presenter.animationRecordCount()` and `presenter.commitCount()` are diagnostics
for tests, not features.

**`keyboardNavigation`** (default **`false`**) opts this presenter's surfaces into
the desktop keyboard conventions: **Tab / Shift+Tab** traverse the focus chain and
**Space** joins Return as Activate. It is **off by default because the keys it
claims are keys an avatar is already using** — with it implicitly on, Space jumped
the character while the UI held focus (director playtest 2026-08-03). Turn it on
for a UI-driven place or a keyboard-first surface; leave it off for a HUD over
live gameplay.

Even when on, the bindings exist only while **keyboard capability is live** and
the surface's **responder is engaged**, so a phone binds nothing and a passive HUD
binds nothing until it engages. All three conditions are reactive: a keyboard
plugged in mid-session adds real bindings and unplugging removes them, with no
dead sink left behind.

Per-surface override: `present(bp, { keyboardNavigation = … })`, below.

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

This is not something LuauUI can fix from inside — the binding belongs to the
player scripts, and silently unbinding a consumer's camera would be worse than the
symptom. A keyboard-first place should release the action (or ship its own camera);
a place that keeps the default camera should not rely on Left/Right for UI. Note
that disabling the PlayerModule's **controls** module does *not* free the key — the
camera module is a separate binding.

**Session lifetime, stated.** A presenter is built **once per client session**
and has **no `dispose()`**. It owns a feedback bus, a focus graph, a motion clock
(its own, unless you passed one) and up to four private surfaces, and nothing
releases them — so building a second presenter to replace the first leaks all of
it. Present and dismiss surfaces on the one presenter instead. `newFocusGraph`
and `newEnvironment` carry the same contract for the same reason (constitution
§8; PKT-3 tracks adding teardown).

Methods:

- `presenter.present(blueprint, opts?) -> handle` — base screen.
- `presenter.presentModal(blueprint, opts?) -> handle` — focus trap +
  higher-priority sinking input context; Cancel (gamepad B) dismisses.
- `presenter.presentCritical(blueprintFactory, opts) -> handle` — runs the
  factory and presentation under protection; on error presents
  `opts.fallbackScreen(err)` instead (critical-screen fallback). **The fallback
  is presented with the caller's own opts** — `rootPolicy`, `navigationGroups`,
  `transition`, `keepVisibleOffset` and the rest all still apply, because
  everything you declared about this screen is still true of the screen standing
  in for it. `fallbackScreen` itself does not ride along: the fallback presents
  as an ordinary screen and its own errors stay hard.
- `presenter.dismiss(handle)` — removes THAT handle's screen, focus scope
  (wherever it sits in the stack), input context, and mounted tree.
- `presenter.back() -> boolean` — dismisses the top modal.
- `presenter.refresh()` — re-renders all presented screens, **re-discovers each
  surface's input contributions from its live mounted tree**, and re-derives
  focus rings from those trees. The contribution walk matters as much as the
  focus one: a control whose `contribution.attach` bundle mounts LATER (inside a
  `UI.When` that opens on a role, a phase, a load) is wired the frame it appears
  — `handleActivate`, `handleCancel`, `focusGroups`, `focusMoved`,
  `navigateIntercept`, `bindController` and `bindActionSystem` all start
  working then, and a bundle whose region CLOSES stops receiving dispatch.
  One-time bindings are keyed on bundle identity, so a surviving contribution is
  never bound twice. (Before 2026-07-31 this was a one-shot walk at `present()`
  time: a screen whose whole interactive tree was gated behind a `When` that was
  closed at present had **no** input wiring for its entire life, and every
  headless rig hid it by mounting the region before presenting.)
- `presenter.depth() -> number`, `presenter.focus` (the focus graph).
- **Focus identity vs the focus RING** (`presenter.focus.focusVisible`,
  `presenter.focus.setFocusOrigin(kind)`). Focus always moves — a tap moves it
  (the Apple model), and every consumer that follows focus (a drag's aim,
  keep-visible, the engine-selection bridge) keeps working on touch. The RING is
  a different question — "where does the next Navigate go" — and a finger never
  asked it. So the graph records the ORIGIN of the last focus move: `"pointer"`
  (a tap/click, and any programmatic `focusOn` that follows one) hides the ring,
  `"navigation"` (a key, a d-pad, an explicit call) shows it, and the first
  navigation verb after a tap brings it straight back onto the node the finger
  left it on. `focusVisible` is the Readable the presenter feeds to
  `controller.setFocusPath(path, visible)`; hybrid devices need no branch and no
  env fact. Consumers only call `setFocusOrigin` when they synthesize input.
- `presenter.tick(dt?)` — **one frame of presenter time**: steps the motion
  clock every surface and toast transition rides, then advances the toast
  schedule. The client binds it to `RunService.PreRender`; the headless suite
  passes a scripted `dt`. Nothing animates and no deferred teardown completes
  without it — including the exit cap, which is clock time, not wall time. A
  region whose exit finishes during a tick disposes then; its instances leave on
  the next `presenter.refresh()`, as every structural change does (they are
  already faded out or off the edge, so nothing is visible in between).
  **The binding is yours to release.** `motion_driver.bind(presenter)` returns an
  `unbind`, and nothing calls it for you: disposing a presenter does **not**
  disconnect the `PreRender` connection, so a discarded unbind keeps ticking (and
  retaining) a presenter nobody presents any more. Own it where you own the
  presenter. And because `PreRender` handlers **block the rendering pipeline until
  they return**, everything inside one tick — every motion write, every
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
  unsubscribe is yours to own (`scope:own(presenter.onTick(...))`).
- `presenter.motionClock` — the clock itself. `LuauUI.newPresenter(core, env,
  adapter, actionSystem, opts?)` takes `opts.clock` to share one with the rest
  of the application, and `opts.now` to inject time.
- `presenter.presentToast(blueprint, opts?) -> { id, dismiss() }` — see
  **Toasts** below.
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
- `presenter.exclusiveSurfaceActive` — a `Readable<boolean>`, true while any
  presented surface is EXCLUSIVE (a modal, or an engaged-from-passive HUD — both
  sink, becoming first responder over gameplay). A client adapter observes this
  to hide the mobile touch controls (`src/client/responder_effects`; ADR-0014).
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
  `.responder` (a `Readable<"passive" | "engaged">`), `.engage()`, `.resign()`,
  `.focusOrder()` (the focus-map inspection dump, below).

Options — the key set is closed, and an unknown one is refused at present time:
`onActivate(path, meta)`, `onAdjust`, `onFocusNav`, `onReorderNav`,
`onNavigateIntercept`, `navigationGroups`, `onGeometry`, `keepVisibleOffset`,
`sinkNavigation`, `responder`, `gameplayGuard`, `rootPolicy`, `outsideTapCancel`,
`cancelPolicy`, `scrim`, `revealWhenTextExact`, `revealTimeout`, `transition`,
`traversalWrap`, `keyboardNavigation`, `initialFocus`,
`engineSelectionBridge` (the `presentModal` mirror described above),
`fallbackScreen` (read by `presentCritical`), and the two performance opts the
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

The four string-enum opts — `rootPolicy`, `responder`, `cancelPolicy`, `scrim` —
are validated at present time and an unknown value errors naming the legal set.

**`sinkNavigation` does nothing on a passive surface.** A `responder = "passive"`
screen exists precisely so navigation reaches the gameplay contexts beneath it,
so it never sinks while passive whatever this opt says; engagement is what turns
sinking on. Set it on an ordinary `present()` (a modal always sinks).

**`traversalWrap`** (default `true`) declares whether **Tab / Shift+Tab** wrap at
the ends of this surface's focus scope. It is declared per surface and never by a
control, so one screen has one answer wherever the ring is standing. `true` is the
default because it matches the ring the arrows have always walked and because a
modal has nowhere else for Tab to go; set `false` where running off the end should
read as an end. It governs Tab only — a `NavigationGroup`'s own `wrap` still
governs the directional arrows along that group's axis.

**`keyboardNavigation`** overrides the presenter default (see `newPresenter`) for
this one surface: `true` gives a keyboard-driven modal Tab and Space over a
gameplay HUD that does not want them, `false` keeps one HUD out of the way on a
keyboard-navigable presenter. The capability and responder conditions still
apply.

> **If your surface sits over a live world, pair it with `responder = "passive"`.**
> `keyboardNavigation = true` makes an ordinary `present()` screen **sink** — it has
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
> presenter.present(hud, { keyboardNavigation = true, responder = "passive" })
> ```
>
> | | binds Tab/Space | sinks | gives it back |
> |---|---|---|---|
> | `present()` (engaged-open) | on mount, forever | yes | **no** |
> | `responder = "passive"` | on first tap on the UI | while engaged | on a tap outside, Cancel, or `resign()` |
> | `presentModal()` | while open | yes | on dismiss |

### `handle.focusOrder()`

Returns this surface's focus map **as data**, for debugging and for tests. Frozen,
and deterministic — two calls with nothing changed in between return equal data.

```lua
{
  schema = "luauui-focus-order/1",
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
  },
}
```

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
`deviceSafeContent` (per-edge max of CoreGui and device insets), and
`edgeToEdge` (the whole window — a scrim, a backdrop, or a surface that
deliberately places itself in a platform band the insets exclude).

**Placing a surface in the platform's TOPBAR band.** Read the derived fact
**`platformChrome`** and present the surface `edgeToEdge`, whose content rect *is*
window space:

```lua
local chrome = env:get("platformChrome"):get()
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
the band starts, which is what a surface that means to ride the band applies
instead. When there is no band the two are equal, so a consumer needs no branch.

Do not add `topbarSafeInsets.left` to `topbarInset.x`. They are two encodings of
one rect — measured on the live engine 2026-08-14 at 735x413, `TopbarInset` reads
`(164,0)+571x58` and the topbar-safe area reads x 164..735 / y 0..58 — and
`platformChrome` intersects them. (An earlier version of this page said to add
them; that was wrong, and adding them pushes content a cluster-width too far
right. See ADR-0027.)

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
the root itself otherwise.

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

#### Toasts

`presenter.presentToast(blueprint, opts?) -> { id, dismiss() }` — a transient,
**input-transparent**, self-retiring surface.

```
opts = {
  key?,        -- same-subject supersede
  priority?,   -- default 0; higher runs first in the queue
  duration?,   -- seconds visible, default 4
  readFloor?,  -- minimum dwell before anything may replace it, default 1.5
  position?,   -- "top" (default) | "bottom" — the edge it docks to
  transition?, -- default: in from its own edge, with a fade
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

**LuauUI plays nothing.** It never triggers a sound, a haptic or a particle — it
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

**Modal outside-tap dismissal (two-zone spec, ADR-0014 §Drive-F1).** While a
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

**First responder (ADR-0014).** `present()` default is today's engaged-open
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
  LuauUI never disables a consumer's leaderboard. Everything else here — Space,
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
  Wrap is `traversalWrap`, above. A focused `newTextInput` sees the press first
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

**Input auto-wiring (ADR-0013).** Composite controls attach an input-contribution
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
`keepVisibleOffset` (`Readable<number>`), `bindActionSystem(actionSystem)`,
`bindFocusGraph(focusGraph)`, and the **paradigm-axis seams** (UI-PARADIGM-001):
- `bindFocusGraph(focusGraph)` — the presenter hands over the screen's focus graph
  at the same moment it binds the action system and the controller, for the one
  case a control has to **move** focus rather than follow it: the data under a
  focused row changed and the control's own policy says the ring belongs
  somewhere else now (`newVirtualList.focusPolicy = "index"`). It is the canonical
  route — a control handed the graph by its *consumer* leaves the consumer owning
  half the focus story. Absent, the control degrades to logical focus only.
- `adjustTargets(rootNode) -> { [path]: true }` + `handleAdjust(path, direction)`
  — the Adjust verb (grip resize, value stepper). The presenter binds the Adjust
  keys DYNAMICALLY — only while the focused path is a declared target — so a bare
  screen never shadows gameplay arrow/bumper keys off-target. `direction` is −1 /
  +1; `handleAdjust` returns true when consumed; longest-path-prefix wins.
  `opts.onAdjust` still overrides both per-opt.
- `adjustAxis = "horizontal" | "vertical"` — which **arrow keys** the control's
  declared targets consume while one of them holds focus. `"horizontal"` takes
  Left/Right + DPadLeft/DPadRight; `"vertical"` takes Up/Down + DPadUp/DPadDown.
  The *other* axis keeps navigating. Comma/Period and L1/R1 are axis-independent
  and are bound for a declared target either way. Any other value is refused at
  `contribution.attach`, naming the two legal ones.

  **Choose the axis your screen does not navigate on.** On a *grouped* screen both
  axes navigate, so either choice leaves the ring a way out on the arrows plus Tab.
  On a *flat* screen only the vertical axis navigates — so `"vertical"` there takes
  the only arrows that could move focus, and **Tab becomes the only way off the
  control**. Every shipped value control declares `"horizontal"` for this reason;
  `"vertical"` exists for a genuinely vertical value (a level meter, a
  bottom-anchored slider) and is the author's call to make knowingly.

  Omitting it is a real choice, not an oversight: an undeclared target keeps the
  pre-0.9 key set (Comma/Period/L1/R1 always, plus the horizontal arrows only on
  a *flat* screen where nothing else wants them). `newSlider`, `newStepper` and
  `newRating` declare `"horizontal"` because their value **is** that axis;
  `newTable` deliberately does not, because its resizable headers are navigation
  stops and adjust targets at once and it resolves the contention with a mode
  (Activate selects the column, then the arrows resize it, Cancel releases).
- `handleTraverse(path, direction) -> boolean` — a chance to consume Tab /
  Shift+Tab *before* the focus ring moves. `direction` is +1 (Tab) or −1
  (Shift+Tab); return true to keep focus where it is, false/nil to let the
  presenter traverse. Longest-path-prefix wins, like `handleActivate`. It exists
  for controls that must finish something first: `newTextInput` commits through
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
- `outsideDismiss = { active: Readable<boolean>, dismiss }` — while `active`, a
  tap outside the contribution's subtree dismisses it (non-destructive) and the
  presenter synthesizes a transparent full-viewport catcher so a tap on empty
  space dismisses too (the two-zone model without making the control a modal).
- `transientScope = { active: Readable<boolean>, rootPath? }` — while `active`,
  focus is trapped within `rootPath` (default: the control root) and restored to
  the pre-activation path on deactivation.

PopupButton is the worked example (outside-tap dismiss, ButtonB close, focus
trap-and-restore) without engaging the modal machinery.

---

## Environment

### `newEnvironment`

`LuauUI.newEnvironment(core) -> Env` — per-client observable platform facts plus
derived policy. Four methods: `env:get(key) -> Readable` (any key, fact or
derived; an unknown key errors), `env:set(key, value)` (**facts only** — setting
a derived key errors), `env:batch(body)` (below), and `env:keys() -> { string }`
(every key, sorted, facts and derived merged with no marker distinguishing them —
the split is the table below). The client adapter
(`src/client/roblox_env.luau`) pushes the real engine facts; tests set fakes.

**`env:batch(body)` — one real change is one fact-group.** An adapter almost
never learns a single fact at a time: one device rotation teaches SIX at once
(the viewport, three inset shapes, the topbar rect and the size class). Written
loose, each is its own flush, and everything downstream — the renderer's
re-solve above all — pays once per *write* for a change the player made once.
`env:batch` runs `body` inside the core's own transaction: writes are invisible
to observers until the outermost batch closes, nested batches collapse into it,
and memos stay glitch-free throughout.

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

Like the presenter, an environment is a **session-lifetime service**: it is built
once per client, has no `dispose()`, and its ~27 core registrations live as long
as the core does.

**The keys are the API.** Settable facts:

| Fact | Value |
|---|---|
| `viewportRect` | `{ x, y, w, h }` of the window |
| `deviceSafeInsets` | per-edge `{ top, bottom, left, right }` device (notch) insets |
| `coreSafeInsets` | per-edge CoreGui reservation |
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
| `themeMetrics` | the frozen `ThemeSnapshot`; the single atomic metric commit point |

Derived policy (memoized, read-only):

| Derived | Answers |
|---|---|
| `typographyScale` | the MEASURE-seam text scale: `preferredTextSize` clamped to 0.5–3, times 1.5 on a `Large` display |
| `typographyPaintScale` | the PAINT-seam scale: the ten-foot factor only (1.5 on `Large`, else 1). The engine applies the player's preference itself, so paint must not multiply it in again |
| `effectiveTransparency` | `preferredTransparency` clamped to 0–1 |
| `sizeClass` | `"compact" \| "regular" \| "wide"` from `viewportRect.w`, capped at `regular` on a `Large` display |
| `motionPolicy` | `"reduced"` when `reducedMotion` is true, else `"full"` |
| `distanceProfile` | `"ten-foot"` on a `Large` display, else `"near"` |
| `effectiveOverscanInsets` | authored `overscanInsets` when any edge is non-zero; `"none"` means all zero; otherwise the console defaults (60 top/bottom, 90 left/right) on a `Large` display and zeros elsewhere |
| `platformChrome` | WHERE THE PLATFORM'S OWN CONTROLS ARE (ADR-0027): `{ band, rects, insets, bandInsets }`. `band` is the free topbar strip in window space or `nil`; `rects` is what the engine's own controls occupy (a list — the top band minus a free strip is an L); `insets` clears everything (what `deviceSafeContent` applies); `bandInsets` clears everything except the free band |
| `presentationProfile` | `{ space, flat, world }`; an unrecognised `presentationSpace` resolves to `"screen"` |
| `interactionClasses` | the LIVE set of input idioms plus `primary` (ADR-0015): capabilities and preference together, never the preference alone |
| `effectiveInput` | `interactionClasses.primary` in the platform fact's own vocabulary |

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

---

## Input

### `newActionSystem`

`LuauUI.newActionSystem(core) -> ActionSystem` — the headless semantic-action
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
Shift+Return menu, `newRowActions` above, is the shipped example: it wins
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

**`action._deliver(value)` and `binding._sample(x, y)` are the engine-adapter
seam.** The leading underscore means exactly that (constitution §2): they are
how an alternate action-system adapter — `src/client/roblox_input.luau` is the
first-party one — delivers state into the headless model. They are not private,
and they are not for consumer code: a control or a screen drives an action
through `bind`/`deviceKey`, never through these.

### `inputHint`

`LuauUI.inputHint(core, env, action, opts?) -> Readable<string>` — a reactive
input-affordance label for an action (ADR-0013). It tracks the environment's
`effectiveInput` fact and resolves the action's `preferredBinding(...)`,
returning that binding's `displayName` (falling back to its `keyCode` /
`uiButton`), or `""` when no binding matches the current input class
(nil-tolerant). Mount the returned Readable as a `UI.Text` `text` prop so the
label re-flips with no remount when the player switches input device:

```lua
local hint = LuauUI.inputHint(core, env, activateAction) -- "Enter" | "A" | "Tap"
local text = UI.Text{ id = "Hint", text = hint }
-- ... hint:dispose() with the rest of the screen's resources
```

**`opts.style`** is `"key"` (default, the bare label) or `"phrase"`, which answers
the whole affordance — `"Press Enter"`, `"Press A"`, `"Tap"` — so a consumer can
write one template instead of branching on input class to author copy:

```lua
local how = LuauUI.inputHint(core, env, activateAction, { style = "phrase" })
local line = core:memo(function(use) return `{use(how)} to apply` end)
```

A key label alone cannot remove that branch, because touch does not differ by
KEY, it differs by VERB: you tap, you do not press Enter.

An unknown `style` is refused at the call, naming the two legal values — the
same rule `rootPolicy` and `cancelPolicy` follow.

**`opts.scope`** hands the returned memo to a scope, the same idiom
`adaptive.conditions` uses; omit it and disposing the memo is yours.

Invariants: it never injects visible UI on its own (the consumer decides where
the label appears). It reads `env:get("effectiveInput")` — a change re-labels the
same node, no factory rerun.

### `adaptive`

`LuauUI.adaptive` — the adaptive-layout decisions. Two halves, both usable
independently.

**Pure functions** (no core, no environment, no DataModel — deterministic and
headlessly testable):

| Call | Result |
|---|---|
| `adaptive.sizeClass(width, opts?)` | `"compact"` (< 600) / `"regular"` (< 1000) / `"wide"`. `opts.distanceProfile = "ten-foot"` caps the result at `regular`, because a TV at 3 m must not resolve the densest arrangement however wide it is. A nil or NaN width degrades to `"compact"` rather than to a nonsense class. |
| `adaptive.axisFor(width, opts?)` | `"y"` below `opts.stackAbove` (default 600), `"x"` at or above it |
| `adaptive.columnsFor(available, minColumnWidth, gap?)` | the column count a `UI.Grid` with that `minColumnWidth` will derive — the same arithmetic the solver uses, so a screen can ask before laying anything out |
| `adaptive.heightClass(height, opts?)` | `"short"` (< 600) / `"medium"` (< 1000) / `"tall"`. `opts.distanceProfile = "ten-foot"` caps at `"medium"`, for the same reason the width cap exists: `tall` is the densest vertical arrangement. Degrades to `"short"` on nil/NaN |
| `adaptive.orientationFor(width, height)` | `"landscape"` / `"portrait"` / `"square"` — a **shape** fact, not a device fact: a windowed pane on a desktop is portrait and must be treated as one |
| `adaptive.navPlacement(facts)` | `"bottomBar"` / `"bottomBarCompact"` / `"topBar"` / `"sidebar"` — THE app-level tab/sidebar placement policy (director rulings 2026-08-09, aligned to the platform tab-bar guidance): compact width → a full-width bottom tab bar in the thumb zone; short height → the same bar in its reduced INLINE form (short labels, tighter band, CENTERED and hugging its tabs — a landscape phone); ten-foot → a center-aligned top tab bar that HUGS its content, never full width; pointer-primary → a sidebar (desktop shape); touch- or gamepad-primary with a `Medium`/`Large` engine DisplaySize → the same centered top bar (tablet shape); touch/gamepad with a `Small` or unknown display → bottom tabs (a roomy canvas the display fact cannot tell from a phone or handheld stays one — when we cannot differentiate, bottom tabs). `facts = { sizeClass, heightClass, distanceProfile?, primary?, displaySize? }` — shape, input and display facts only, never a device idiom (touch ALONE is not the top-bar indicator: a touch phone and a touch tablet share the class, and DisplaySize is what separates them). Every placement must remain gamepad-traversable — enter, through, away, and ButtonA activation — which the reference proofs pin per home. Pure, so the `conditions` memo and tests share one implementation |
| `adaptive.BREAKPOINTS` | `{ regular = 600, wide = 1000 }` as data |
| `adaptive.DEFAULT_STACK_ABOVE` | `600` — the default `axisFor` threshold, as data. It is the compact/regular boundary on purpose, so a screen that adapts its stack and a screen that adapts its density flip at the same width |
| `adaptive.HEIGHT_BREAKPOINTS` | **the same table**. The question is identical on both axes ("how much content fits along this one"), and a second set of literals would be a second thing to justify and a second thing to drift. A rotation therefore maps a class pair onto its mirror: 733×313 is `regular`×`short`, 313×733 is `compact`×`medium` |

**Reactive conditions:** `adaptive.conditions(core, env, opts?)` returns Readables
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

The height half is **additive**: every key that existed before it keeps its exact
meaning and its exact value, including the ten-foot demotion. It exists so no
screen re-derives a private viewport-height threshold in its own code — which is
how the results surface ended up with a `vpH < 520` guess it got wrong twice. For
an adaptation that must depend on the box one *container* received rather than on
the viewport, these classes are still the wrong tool: use `UI.Composition` (whole
screen, both axes) or `ViewThatFits` (one container).

**Pass `opts.scope`.** "The caller owns them" is literal: this call builds **twelve
memos** (six before the height half landed), and on a long-lived core a screen that
rebuilds without owning them leaks twelve per build/dispose cycle (measured — the
leak is invisible to a per-screen test
because the memos die with a short-lived core). `opts.scope` hands them to a scope
so they die with the screen:

```lua
local conditions = LuauUI.adaptive.conditions(core, env, { scope = screenScope })
```

Omitting it is still legal — then you own the twelve memos by hand, which is the
same rule every other resource follows. `opts` also carries the `axisFor`
breakpoint override (`stackAbove`).

`isTenFoot` follows the **viewing distance** (`displaySize == "Large"`), not the
input class: a console is Large and gamepad, but Large alone earns the distance
treatment.

These conditions are **viewport-relative**, and `viewportWidth` is the RAW viewport
width: it does not subtract safe insets or overscan. On a console row it reads 1920
while overscan removes 106 px per side, so near a breakpoint a screen can resolve for
space it does not have. For a decision that must depend on the space one particular
container actually received, use the real measurement contract instead — see
`ViewThatFits`.

**`contentWidth` is deprecated (since 0.8.0; replacement `viewportWidth`).** It
is the same value under a second name, and the name is a lie: it states an inset
subtraction that never happens. It keeps working — it is in `LuauUI.DEPRECATIONS`
with at least one minor of notice — but new code reads `viewportWidth`.

### `composition`

`LuauUI.composition` — the **pure** half of declared-content adaptive composition
(ADR-0023). `UI.Composition` / `UI.Region` are the declaration face; this is the
decision itself, callable with **no mount, no engine and no theme**, which is what
makes a whole device matrix a headless sweep rather than a screenshot review.

| Call | Result |
|---|---|
| `composition.resolve(decl, offer, ctx)` | the full `Resolution`: `arrangement`, `legal`, `fallback`, per-region `{ form, mounted, dropped, floor, rect, lane }` (plus `regionById`), lane rects with each lane's `collapsed` flag (rule 9), group rects, `scroller`, `used`, and `rejected` — one entry per losing candidate with the **rule** it broke and the measured detail. `offer` is `{ w, h }`; `ctx.measure(regionId, formIndex, availW, availH) -> (w, h)` supplies the measurements and `ctx.floorOf(region) -> number?` the authored floors |
| `composition.normalize(decl)` | validate and default a declaration — the ONE ruling on what a declaration may say, run both at construction and on every solve. Idempotent |
| `composition.dump(resolution)` | the deterministic diagnostic table (`{ schema = "luauui-composition-dump/1", … }`); two calls are equal. This is what the solver publishes and the layout dump carries |
| `composition.floorPx(floor, metrics)` | a CONTENT floor (`{ lines = n, role? }`, `{ targets = n }`) resolved to pixels against a theme snapshot; `nil` when nothing was declared |
| `composition.arrangementOf(value)` | a preset name or a custom table, validated to `{ name, lanes }` |
| `composition.ARRANGEMENTS` | the three presets as data: `column` = one lane holding every affinity, `twoLane` = `{ main } { lead, trail }`, `threeLane` = `{ lead } { main } { trail }` |
| `composition.HUD` | the **screen-anchored HUD** arrangement as data (ADR-0025): three lanes, `{ left } { center } { right }` — the three screen columns |
| `composition.HUD_GROUPS` | the thirteen groups that go with it: one `fill` **column** group per lane (it holds the lane's third of the band, and `holdsLane` keeps that third on a round where the column is empty), the nine **zone** groups `topLeft … bottomRight`, and the `topbar` **span** row (ADR-0027) |
| `composition.ZONES` | the ten zone ids in that table, in order. Nine are the same nine words the `anchor` box prop uses; the tenth, `topbar`, is not an anchor at all — it is the `span = "above"` row LEVEL WITH the platform's own controls, so the lanes start below it. It is inert until a region declares it: a HUD that never mentions `topbar` resolves and dumps byte-identically. Its geometry comes from the `platformChrome` env fact — see **Placing a surface in the platform's TOPBAR band** |

A declaration is `{ id?, groups, regions, arrangements, laneGap?, groupGap?, maxMeasure? }`,
where each region carries `{ id, group, rank, forms = <count>, sizing?, weight?, floor?, mayScroll?, mayDrop?, reserved? }`.
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
UI.Composition{
  id = "Hud",
  width = fill, height = fill,
  groups = LuauUI.composition.HUD_GROUPS,
  arrangements = { LuauUI.composition.HUD },
  children = {
    UI.Region{ id = "Rail", group = "topRight", rank = 3, children = { rich, compact } },
    UI.Region{ id = "Tasks", group = "left", rank = 8, mayDrop = true, children = { panel, chip } },
  },
}
```

`resolution.collisions` is the alarm for the one failure a partition cannot
remove: a region whose chosen form **measures** bigger than the box it was
allotted paints outside it, and if a neighbour is there it is painting on that
neighbour. Every unordered pair, offender first, with the overlap in px — and the
solver files one finding per pair, so the always-on overflow sweep sees it at
every viewport. The scroll region and a `fill` region's height are excluded: those
extents are granted by the mechanism rather than claimed by the author.

### `contribution`

`LuauUI.contribution` — the input-contribution seam (ADR-0013). A composite
control advertises its whole four-input story by attaching one bundle to its
blueprint root; the presenter discovers it on mount and composes navigation
groups, Activate dispatch, grab intercept, focus reporting, geometry feed,
keep-visible offset, action binding, the Adjust verb, and transient-surface
cancel/dismiss/trap — with **no** `present()` opts from the consumer.

```lua
local root = UI.VStack{ id = "MyControl", children = { … } }
root = LuauUI.contribution.attach(root, {
    focusGroups = function(rootNode) … end,
    handleActivate = function(path, meta) … return true end,
    adjustTargets = function(rootNode) … end,
    handleAdjust = function(path, direction) … end,
})
```

`attach(rootBlueprint, bundle) -> Blueprint` returns a new frozen blueprint
carrying the bundle on the internal `meta` channel (never in the public prop
bag). `read(mountedNode) -> Bundle?` is the presenter's side and type-guards a
non-table value to `nil`. Every field is optional; fill only what your control
needs. See `docs/extending/new-control.md` step 3 and `Bundle` in
`src/input/contribution.luau` for the full field list.

Invariant: when the bundle declares `handleActivate`, the inner focusable
primitives must carry **no** `onActivate` prop — the presenter dispatches to
the node's own handler first and then to the longest-prefix contribution, so
declaring both double-fires the verb.

---

## Text measurement

### `text`

`LuauUI.text` — the library's own measurement engine, reachable. Three pure
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

**`text.measure`** takes a spec table — the canonical form, and the one that
matches its two siblings:

```lua
local m = LuauUI.text.measure({
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
  from, so `exact = false` no longer conflates "this font is not calibrated yet"
  with "an engine measurement failed". Wait on `pending`; give up on `failed`.

The search is exact rather than iterative-until-close: fit is monotone in size,
so a binary search over `[floor, cap]` lands on the true answer in ~log2(cap)
measures, each of them memoized per `(text, font, size, width)`.

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
store belong to the module, not to a core or a scope, and there is nothing to
own or dispose.

---

## Focus

### `newFocusGraph`

`LuauUI.newFocusGraph(core) -> FocusGraph` — the logical focus graph (engine
selection is a render output). Scopes stack; the top scope owns navigation;
modal scopes trap and restore the previous focus on pop.

- `graph.pushScope{ name, trap, order }` — FLAT scope: one ring,
  `graph.navigate(±1)` wraps.
- `graph.pushScope{ name, trap, groups }` — GROUPED scope: each
  NavigationGroup declares `name`, `axis` ("vertical"/"horizontal"),
  `order`, `wrap?`, `containment?`, `entry?` ("first" | "restore" |
  "nearest"), and `exit?` (`{ up/down/left/right = targetGroupName }`).
- `graph.navigateDirection("up"|"down"|"left"|"right")` — axis-aware
  movement: within the active group along its axis; at edges wraps (if
  `wrap`), follows a declared `exit`, or (uncontained) falls through to the
  neighboring group in array order; orthogonal directions only move via
  declared exits. `containment = true` blocks implicit exits.
- `graph.focusOn(path)`, `graph.setOrder(name, order)`,
  `graph.setGroupOrder(scopeName, groupName, order)`, `graph.remove(id)` —
  structural updates keep focus when it survives, else the nearest surviving
  neighbor (preferring the following item).
- `graph.popScope()`, `graph.removeScope(name)` (used by
  `presenter.dismiss` so dismissing a covered screen removes ITS scope, not
  the top one), `graph.activeScopeName()`, `graph.focused` (Readable).

**Focus-skip by live predicate** (ADR-0022 Decision 5, row SF-L3). Any order
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

### `newTable`

`LuauUI.newTable(LuauUI, core, spec) -> { blueprint, api, dump, dispose }` —
the multi-column list control (SwiftUI-`Table`-shaped columns that own their
cells; owner-held `sortOrder`; selection none/single/multi with the
Apple-style focus/selection model; column resize via focusable grips;
pointer-drag row reordering with ghost + drop indicator). See
`src/controls/table.luau` for the full spec shape.

`dump()` is the deterministic diagnostic summary, and it carries the live
interaction state a bug report actually needs, not only the construction:
`{ schema, id, columns, rowCount, selection, sortOrder, selectedKeys (sorted),
grabbedKey, editing, scrollTop, dragging, reorderable, rootPath }`.

A column's `alignment` applies to its **header title** as well as its cells, so a
numeric column's heading sits over its numbers rather than left of them.

**`rowSelectable(item)` / `rowMovable(item)` / `rowDeletable(item)` — per-row
capability opt-outs.** The same three predicates `newVirtualList` takes, from the
same module (`src/row_capability.luau`), with the same rules: positive polarity
(true = this row may take part), a construction error if you declare one without
the container capability it narrows (`rowSelectable` needs `selection`,
`rowMovable` needs `reorderable` **and** `onReorder`, `rowDeletable` needs a
destructive row action), absent means every row participates, and a predicate
that throws **fails closed** — the row refuses, and the refusal is visible rather
than a silently deleted row. Use them for "this list reorders, but the pinned row
at the top stays put" and "these rows can be deleted, that one cannot". SwiftUI
spells the family negatively (`selectionDisabled` / `moveDisabled` /
`deleteDisabled`); the inverse mapping is in
[`swiftui-parity.md`](swiftui-parity.md) §5.

**`onPrimaryAction(item, key)` — "open this row", the verb that is not
selection.** Optional; absent, every gesture below behaves exactly as it does
without it. Reachable on all four inputs with no invented gesture:

| Input | Gesture |
|---|---|
| Pointer | double-click (500 ms window, the shared Windows/macOS default) |
| Keyboard | `Return` on the focused row |
| Gamepad | **A** / Cross on the focused row |
| Touch | a plain **single tap** on any row; **edit mode** is where touch selection lives instead |

**The name is ours; the touch rule is Apple's.** SwiftUI has no `onPrimaryAction`
symbol — it delivers this verb as the `primaryAction:` argument of
`contextMenu(forSelectionType:menu:primaryAction:)`, and that API's
documentation is the model implemented here, verbatim: *"In macOS, a single click
on a row in a selectable container selects that row, and a double click performs
the primary action. In iOS and iPadOS, tapping on the row activates the primary
action. To select a row without performing an action, either enter edit mode or
hold shift or command on a keyboard while tapping the row."* (The keyboard's
`Return` is **not** parity — Apple documents no key for row activation. It is a
reasonable convention, and matches `NSTableView` practice, but it is ours.)

**Edit mode is the touch selection mode**, and it is the half that makes the
first half affordable — `EditMode`: *"On devices without an attached keyboard and
mouse or trackpad, people can make multiple selections in lists only when edit
mode is active"*; the HIG's Lists and tables: *"In iOS and iPadOS, people must
enter an edit mode before they can select table items."* So while `api.editing`
is `true` a tap **toggles selection and never opens** — which hands back
`multi`'s tap-to-**deselect** gesture in exactly the mode a player enters to
manage selection.

**Reaching edit mode is not left to the consumer.** The built-in Edit/Done toggle
auto-shows whenever edit mode is the **only route to a capability the table
declares** — today that means a `reorderable` table, **or a selectable table that
declares `onPrimaryAction`**, whose touch selection lives nowhere else. It is
gated to a non-mouse session when `env` is supplied (a mouse click already
selects), and suppressed entirely when the consumer passes `spec.editing`, which
makes the affordance theirs. Without that second clause a
`selection = "single"|"multi"` + `onPrimaryAction` + non-`reorderable` table had
no route into edit mode at all, so its own `selection` was unreachable on touch —
closed 2026-08-13. `spec.editing` / `api.editing` remains the seam for a consumer
who wants to own the toggle.

Auto-showing it is **ours, not Apple's**: SwiftUI's `EditButton` is placed by hand
and Apple documents no condition on its appearance. What Apple conditions on
declared capabilities is the *content* of edit mode (`EditMode`: a `List` whose
`ForEach` carries `onDelete(perform:)`/`onMove(perform:)` "provides controls to
delete or move list items while in edit mode"). The auto-show is what LuauUI's
four-input reachability rule requires on top of that.

**The cost is real, deliberate, and yours to weigh.** With a primary action
declared, touch loses tap-to-select in **normal mode entirely** — including the
single selection iOS 16+ would otherwise allow by tap (`List`: *"When people make
a single selection by tapping or clicking, the selected cell changes its
appearance… To enable multiple selections with tap gestures, put the list into
edit mode"*). Declaring the action is precisely what makes a list retreat into
edit mode for selection. Apple accepts that trade; so does this control. **The
corollary:** if a table's dominant touch use is *selecting* rather than
*opening*, the right call is to not declare `onPrimaryAction` on that table at
all.

A double-*tap* was never a candidate, and that avoidance is documented too: the
HIG's Gestures lists double tap as **zoom**, and watchOS warns explicitly that it
conflicts with list navigation.

Two more consequences worth stating. A **modified** click (Shift / Cmd / Ctrl) is
a selection gesture and never opens, on any input. And a touch tap that opens
does **not** touch the selection at all — it neither adds, replaces nor clears,
so a selection made in edit mode survives every row you open afterwards;
`api.clearSelection()` remains exact.

**Input is auto-composed** by the presenter
with no `present()` opts (ui_todo §0; ADR-0013): row select, sort, focus-nav
and grab-mode reorder wire themselves from the mounted control. Every
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

A device Activate **selects the column** (`api.selectedColumn`, a Readable of the
column id or `nil`) rather than sorting it, because a stick had nowhere else to
put "resize this" — and a selected column is the handle the rest of the
column-wide verbs will hang off. A **pointer tap still sorts directly**: that
convention is older than this table. While a column is selected it owns the
stick — Left/Right resizes, Up/Down cycles its sort, Activate or Cancel releases
it, and moving focus off the header releases it too, so a selection can never be
left behind swallowing input.

The presenter binds the Adjust keys only while a **resizable** column's header
holds focus, so a non-modal screen never shadows gameplay bumper bindings on a
fixed-width column (UI-PARADIGM-001; affordance-matrix Amendments).
`opts.onAdjust` still overrides per-opt.

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
(`Text.lineLimit`), so **cell text can never paint outside its row**. That was a
real device defect: a fixed 48px row with an uncapped label drew a three-line
track name straight through the rows either side of it, on hardware only, because
turning two lines into three takes a handful of pixels of extra text width. A
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

**`rowActions`** (row-actions, docs/plans/row-actions-implementation.md Task
10) wraps individual rows in a swipeable [`newRowActions`](#newrowactions)
tray without a second construct: `rowActions: (item) -> { leading?, trailing?,
fullSwipe? }?`, a per-item callback returning the same three fields
`newRowActions` itself takes minus `content`/`coordinator`/`env`/`editing` —
Table supplies all four automatically (the wrapped row content, ONE shared
`newRowActionsCoordinator` instance for the whole table so at most one tray is
open at a time, its own `env`, and its own `editing` signal, so the edit-mode
leading minus and the reorder handle can both show at once). Returning `nil`
for an item (the common case, and the only legal value besides the closed
three-key table above) leaves that row completely unwrapped — no extra
`Instance`, no extra subscription, the same true-inert-passthrough guarantee
`newRowActions` itself ships. An unknown key in a returned table is a
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
pointer path, the same split `newVirtualList` documents above). Keyboard and
gamepad Delete/menu bind per row through the wrapper itself (Task 8/8b) with
no separate Table wiring.

*The iOS tap-to-close rule.* A tap that lands on a row's own content while
THAT row's own tray is open closes the tray and does **not** select or
activate the row (a second, deliberate tap is what proceeds) — a tap
elsewhere (another row, off the list) is unaffected. This was a RED-TEAM
finding (the row activated AND stayed open); `tests/table.spec.luau`'s
"iOS tap-to-close" case pins the fix.

*A swipe survives its own release.* A row's hit surface is a real engine
`GuiButton`, so the pointer sequence that swipes it **also** fires that button's
`Activated`, on either side of `InputEnded`. Both hosts (`newTable`'s wrapped
rows and `newVirtualList`'s hosted rows) therefore swallow exactly one Activate
on the origin row, armed the moment the gesture crosses the axis lock sideways —
so a swipe never selects the row, never fires `onPrimaryAction`/`onActivate`, and
never closes the tray it just opened, on either edge, either pointer kind, and
either ordering. The suppression is **one pointer Activate wide**: the next tap
on the row is genuine, and a **device** Activate (gamepad A / keyboard Return) is
never consumed by it — it carries no pointer and so can never be a pointer
gesture's artifact. A gesture that ends in a cancel disarms it outright. Pinned
by `tests/row_actions_scenario.spec.luau`'s four release-Activate cases and
`tests/virtual_list_row_actions.spec.luau`'s twelve-combination hosted matrix.

### `newVirtualList`

`LuauUI.newVirtualList(LuauUI, core, spec) -> VirtualList` — keyed-row
virtualization: only visible rows plus a bounded overscan mount;
same-window scrolls are rect-writes-only; window slides add/remove only the
entering/leaving keys. Spec: `{ id?, rows (Readable array), key (item) ->
string, axis? ("y" default | "x"), itemExtent (px, Readable<number>, or (item, index, use) -> px), rowGap? (px or
Readable<number>), viewportExtent (px or Readable<number>), overscan?, cell (item, ctx {
scope }) -> Blueprint, width?, focusPolicy? ("key" | "index"),
onActivate? ((item, meta) -> ()) }` — plus the collection fields tabled below.
Returns `{
blueprint, scrollTop (Signal), focusedKey (Signal), pathOf(key) -> path?,
focusKey(key) -> path? (scrolls into view and materializes), debugWindow(),
dump(), dispose() }`. Item state lives in the item scope and dies when a row
leaves the window — durable state belongs in your data model.

**`axis` is the direction the list runs**, `"y"` (a vertical list of rows, the
default) or `"x"` (a sideways strip of items), and it is **construction-only** for
the reason `ScrollView.axis` is (constitution §16, E-6): a reactive scroll axis
would rebuild the engine's native scroll state mid-gesture. Every other field is
written in the vertical vocabulary and reads on both axes — `itemExtent` is one
item's size *along the list's own axis*, `viewportExtent` is the host's size along
it, and the list's one navigation group takes that axis too. Two fields are
axis-restricted, and each says so at construction: **`width` is an `axis = "y"`
field** (there it is the CROSS axis; on `axis = "x"` the width *is*
`viewportExtent`), and **`rowActions` is vertical-only**, because a tray's reveal
and a horizontal list's own scroll would be the same sideways swipe.

**`rowHeight` and `viewportHeight` are DEPRECATED aliases** of `itemExtent` and
`viewportExtent` (since 0.9.0, removed no earlier than 0.10.0 — see
`LuauUI.DEPRECATIONS`). Both still work and are identical on `axis = "y"`, so a
vertical list needs no edit at all; they were renamed because a `rowHeight` on
`axis = "x"` names a height that is really a width, and the alias would have to
lie to somebody. Passing the new name and the old one together is refused at
construction: it is one field. (This is `newVirtualList`'s `rowHeight` only —
`newTable.rowHeight` is a different control's current API and is **not**
deprecated.)

<a id="variable-item-extents"></a>
**`itemExtent` may be ONE number or a PER-ITEM function**, and which one you pass
decides the arithmetic.

* A **number** or a **`Readable<number>`** is *uniform*: every row is that tall
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
Readable instead gives the right number *once* and registers no dependency — the
extents then go stale silently, which is the failure mode this form exists to
end. An extent that is not a positive number is refused at construction, naming
the row's key.

**A variable list anchors its scroll.** `scrollTop` is a pixel offset, so when
every row grows at once — a text preference, a ~1.4× localization, a theme swap —
that pixel would land on a different item. The list holds the item under the
viewport's leading edge, and the offset into it, and re-applies it through the
bound controller whenever the extents change. (Uniform lists keep today's
behaviour; see `docs/plans/variable-item-extents.md`.)

Why this exists, which candidate design was refused and what remains:
[`docs/plans/variable-item-extents.md`](../plans/variable-item-extents.md).

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

> `/Screen/Racers/Canvas/W/[r7]/Row/Cell` :: newVirtualList 'Racers' declares
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
auto-composed** by the presenter with no `present()` opts (ui_todo §0;
ADR-0013): mouse wheel and one-finger touch pan scroll the window; each row is
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
After presenting, the CONSUMER wires the engine mirror once:
`local unbind = list.bindNativeScroll(presentedHandle.controller)` — engine
`CanvasPosition` then drives `scrollTop` (wheel/touch/momentum/bars are
native), and `focusKey`/keep-visible compute a canvas target written through
`controller.scrollTo`. Unbound (or on a scroll-less adapter) the list is
clip-only and programmatic scrolls no-op. VirtualList publishes the seam **flat**
on its returned table; `newTable` publishes the same seam as
`api.bindNativeScroll`. The gallery client auto-binds either spelling.

**The unified collection** (ADR-0022 Decision 5, rows SF-L1/L2/L3). One
construct windows, **selects**, **reorders** and **accepts drops** at the same
time, because the racer-list shape needs all four at once and a second list
construct would have to re-derive windowing, keyed identity and keep-visible to
get there. Reorder and drop ride the public `UI.draggable` / `UI.dropTarget`
contract rather than a private path, so an internal row move and a card dropped
in from another container are literally the same session, the same legality seam
and the same terminals.

| Spec field | Meaning |
|---|---|
| `itemExtent` | a number, a **`Readable<number>`**, or a **function `(item, index, use) -> px`**: one item's size along the list's own axis. The first two are UNIFORM (windowed by index×pitch); the function is a PER-ITEM extent (windowed by a running-offset prefix sum) and must read live facts through its `use` argument. See [variable item extents](#variable-item-extents) above. (`rowHeight` is its deprecated alias, above — and it reaches the same three forms.) |
| `rowGap` | the gutter **between item slots**, a non-negative number **or a `Readable<number>`**, default `0` (the name is not axis-specific on purpose: a gap is a gap on either axis). The **pitch** is `itemExtent + rowGap` and every windowing number rides it — canvas extent, the scroll clamp, window membership, keep-visible, the insertion slot, the reorder slide. The item's own node stays **`itemExtent`** along the axis, so the gutter is **dead space**: a pointer in it hits neither neighbour. The content extent carries no trailing gutter — N rows span `N*itemExtent + (N-1)*rowGap`, exactly like a `UIListLayout.Padding`. Uniform per list — unlike `itemExtent`, the gutter has no per-item form, because a gap that differs per row is a property of the ROWS and belongs in their extents. Do **not** reach for the old workaround (hand in the pitch as the extent and inset the cell): that inflates the row's hit into the gutter, so a press between two plates activates one of them. |
| `viewportExtent` | a number **or a `Readable<number>`** — a list that fills a container, or one derived from the viewport rect, hands in a memo and BOTH consumers track it: the painted host box and the windowing arithmetic. A build-time pixel goes stale the moment the device rotates. (`viewportHeight` is its deprecated alias, above.) |
| `selection` | `"none"` (default) or `"single"`. Activate selects the row from **every** paradigm (tap / Return / ButtonA). `selectedKey` is a Signal; `list.select(key)` / `list.clearSelection()` drive it; `onSelect(item, key)` reports it. Selection **prunes with the data** and survives a re-sort that keeps the row. The selected row also carries the **native `selected` state** on its own hit node (Table parity), so the theme paints it (`controlSelected`) and a cell never has to spend an elevation role saying "chosen". |
| `selectionPaint` | `"native"` (default) or `"none"`. `"none"` keeps the selection — `selectedKey`, `onSelect` and the ring all stay — and drops only the row's native `selected` state, for a list whose "chosen" is carried somewhere that is not the row (the standings list whose selected racer is the one the camera is watching). `selection = "none"` cannot express that: it deletes the selection itself. |
| `reorderable` + `onReorder(key, toIndex)` | rows become draggable. `toIndex` is the **1-based index the row will occupy in the resulting order**; a drop that reproduces the current order emits nothing. Order is owner state: the list renders what it is handed. |
| `reorderMotion` | motion class for the slide to a new slot (default `"object"`, `"instant"` to opt out — finding F6). Needs `motionClock`; the slide rides the presentation channel, so it never re-solves. |
| `dropSurface` / `rowDropTarget(item)` | each row becomes a drop target. `rowDropTarget` returns `{ accepts, onDrop }` for that row; `onDrop(payload, info)` gets `info.key`, `info.item`, `info.index`. |
| `rowActions(item)` | `(item) -> { leading?, trailing?, fullSwipe? }?` — **hosted row actions** (see below). Returning `nil` for an item leaves that row completely unwrapped. Refused together with `reorderable` (v1). |
| `rowFocusable(item)` | the SF-L3 focus-skip predicate, evaluated at navigation time. |
| `rowSelectable(item)` / `rowMovable(item)` / `rowDeletable(item)` | **per-row capability opt-outs** — SwiftUI's `selectionDisabled(_:)` / `moveDisabled(_:)` / `deleteDisabled(_:)` family, spelled **positively** (true = the row may take part) so they read the same way as `rowFocusable` beside them. Each answers "may THIS row do it?", never "can this container do it at all?" — so declaring one without the capability it narrows is a **construction error**: `rowSelectable` needs `selection`, `rowMovable` needs `reorderable` **and** `onReorder`, `rowDeletable` needs a destructive row action. Absent = every row participates, and the check is one `~= nil`, so adopting the family costs nothing. They **fail closed**: a predicate that throws refuses the capability, because a consumer bug that stubbornly refuses to move a row is visible and harmless while one that silently deletes a protected row is not. Only an explicit `false` refuses — returning `nil` from a forgotten branch keeps the permissive default, matching `rowFocusable`'s shipped reading. One implementation (`src/row_capability.luau`), two callers. |
| `focusPolicy` | `"key"` (default) or `"index"` — **when the ORDER changes under the player, does the cursor follow the ITEM or stay on the SLOT?** `"key"` is the pre-field control byte for byte: focus follows the item, so a list re-sorting every 250 ms walks the pad cursor up and down the rows on its own. `"index"` pins the slot: when a data update moves the focused item off the slot it was focused at, focus **retargets to whoever occupies that slot now**, clamped to the last slot if the list shrank. This is the answer a live standings list needs ("selection riding a racer's button visibly JUMPS slots on every overtake"). The retarget drives BOTH halves of focus — the logical `focusedKey` *and* the screen's focus graph, which the presenter hands the control through the contribution's `bindFocusGraph` — so there is one focus authority and no consumer-side re-pin loop. It is an **ordinary focus move**: keep-visible applies, and it never summons a focus ring the player put away (the ring-visibility origin is left alone). It **declines** in exactly two situations: while a drag session is live (a policy that re-aimed a gesture mid-flight would fight the player's hand), and when the slot's new occupant fails `rowFocusable` — parking the ring where Activate can do nothing is worse than the jump the policy prevents, so focus falls through to the item. Construction-only, and an illegal value is refused naming both. `dump()` reports `focusPolicy` and the live `pinnedSlot`. |
| `navigation` | `{ name?, wrap?, containment?, entry?, exit? }` — overrides for the ONE navigation group this list contributes. Absent, the group is `vl:<id>`, vertical, `entry = "nearest"`, unwrapped and with no declared exits (unchanged). An unknown field is refused at construction. `list.focusGroupName` reports the resolved name so a **sibling** group can declare `exit = { down = list.focusGroupName }` without hardcoding the `vl:` convention. |
| `autoscroll` | `false` to disable, or an options table. Defaults on whenever the list is reorderable or a drop surface. |
| `grabOnActivate` | whether a non-pointer Activate **arms** the row. Defaults true when the list is reorderable and declares no `onActivate` (so the two verbs never shadow each other); bind `list.toggleGrab()` to a key when it declares both. |
| `env` | the surface environment (Table's own `env` key, and read for the identical reason). Only consulted by `rowActions`: a hosted tray's `buttonPad`/`buttonMinWidth` are theme facts with no font component, so measuring a tray's natural width needs the live `themeMetrics`. Absent degrades to the neutral snapshot — right until a theme package moves those two metrics, and silently wrong from then on. Accepted (and unread) on a list without `rowActions`. |

Reads and verbs added: `selectedKey`, `armedKey`, `dropIndex` (the 1-based slot a
live reorder would commit to), `autoscroll` (a Signal of `{ state, band }` for
the edge affordance), `focusGroupName`, `select`, `clearSelection`, `toggleGrab`,
`stepAutoscroll(now)`, `engagedKey` (Readable: which row is currently revealing
a hosted row-actions tray, nil when none), `engagedOffset` (Readable: that
row's signed reveal offset in px). Both are nil on a list without
`rowActions`.

**Naming the list to its neighbours.** A screen that puts this list beside an
authored row of controls has to state how focus crosses between them ("left from
any row returns to the hand"; "the hand's up/down enters the list"). Both halves
are declarations: the neighbour attaches its own group through
`LuauUI.contribution.attach`, and the list's own `wrap`/`exit` come from
`navigation`. Rebuilding the list's group consumer-side is never the answer — its
order entries carry the live focus-skip predicates *and* the active-interaction
exemption, so a hand-written copy silently loses both.

**Reachability of reorder, per input class.** Mouse: press and travel past the
pointer promotion token. Keyboard/gamepad: `arm → navigate → commit/cancel` —
Activate arms, Navigate moves the predicted slot (and keep-visible-scrolls, so
rows past the window are reachable), Activate commits, Cancel cancels. **Touch**:
a press on the row body **declines the capture** so the native `ScrollingFrame`
keeps the pan — fighting engine momentum scroll is never winnable — so touch
reorder rides the grab verbs, which is the split `newTable` shipped for the same
reason.

**Edge autoscroll** is wired but not self-driving: call
`list.stepAutoscroll(now)` once per frame (the client's `PreRender` shim,
alongside `clock:step`). It applies the scroll through `controller.scrollTo` and
re-runs the drop hit-test **in the same frame**, which is the correctness core of
SF-L2. Non-pointer sessions never autoscroll: focus-follows-navigation already
scrolls the host.

**Hosted row actions (`rowActions`, docs/plans/row-actions-hosted-mode-design.md).**
Table's own `rowActions` wraps every actionable row in a `newRowActions`
COMPOSITE — five extra `Instance`s per row, mounted whether the row is ever
touched or not (~+45% steady / ~+82% fling per refresh, measured). A
virtualized list cannot pay that on rows nobody ever swipes, so VirtualList
**hosts** the feature instead of delegating it: `rowActions: (item) -> {
leading?, trailing?, fullSwipe? }?`, a per-item callback returning the same
three fields `newRowActions` itself takes minus
`content`/`coordinator`/`env`/`editing` (VirtualList supplies the row's own
content, one shared `newRowActionsCoordinator` for the whole list, and its own
`env` automatically; there is no per-row edit-mode minus in v1 — that is
Table-only). Returning `nil` for an item — the common case — leaves that row
completely unwrapped: no extra `Instance`, no extra subscription, the same
true-inert-passthrough guarantee `newRowActions` itself ships. An unknown key
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

*Shipped behavior worth knowing, beyond parity with Table/standalone:*

- **Keyboard/pad Delete reaches a hosted row only once that row has an
  engine — i.e. after a swipe.** Standalone's `newRowActions` binds Delete
  the moment the composite mounts; hosted mode's engine is lazy (see above),
  so an unswiped hosted row has no engine and therefore no Delete binding
  yet. A list-level Delete binding that reaches every row without a prior
  swipe is a booked follow-up, not shipped here.
- **A row refuses a new gesture until it is home.** After a full-swipe
  commit fires, the row's own persistent spring carries it the rest of the
  way closed (or, for a destructive action, collapses its height first) — and
  a press landing anywhere in that return flight is refused, for roughly
  0.3–1.1s depending on how far the row has to travel. This is shared
  `row_actions.luau` behavior, not hosted-only: standalone and Table rows have
  the identical window (a real double-commit bug this same branch fixed, in
  the shared engine body).
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

## Async resources

### `newResourceProvider`

`LuauUI.newResourceProvider(core, opts?) -> Provider` — bounded async
resource provider (images and friends). `opts`: `maxConcurrent` (default 4),
`cacheBudget` (LRU entries, default 16),
`retry = { count, delaySeconds?, giveUp? }`, `now` (injected clock, default
`os.clock`), and the deprecated `retryAttempts` (below).

`opts` is **construction-strict**: `maxConcurrent` must be an integer ≥ 1,
`cacheBudget` an integer ≥ 0, and a declared `retry`'s `count`/`delaySeconds`
non-negative numbers. A `maxConcurrent = 0` used to be accepted (zero is truthy
in Lua) and then nothing could ever start — a UI that loaded nothing, with no
diagnostic anywhere. Each refusal names the option and the rule.

**`retryAttempts` is deprecated (since 0.8.0; replacement
`retry = { count, delaySeconds?, giveUp? }`).** Two words for one concept, with
different semantics: the legacy spelling means immediate attempts and a failed
key that re-requests on the next `acquire`, while `retry` means spaced attempts
against the injected clock and, by default, a give-up that lasts the session. It
keeps its old promise until removal.

- `provider.acquire(scope, key, opts?) -> handle` — `handle.state`
  (`"pending" | "ready" | "failed"` Readable), `handle.value`,
  `handle.error`, `handle.release()` (also released by the owning scope).
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
  yours to release.** `acquire` takes a scope and registers its release there;
  `preload` takes no scope, so a forgotten `release()` keeps the warm wave alive
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
- The provider itself has **no `dispose()`**: its cache and per-key state live as
  long as it does. Handles are scope-owned, and releasing the last handle for a
  key disposes that key's shared `state`/`value`/`error` Readables — so a
  blueprint prop that captured `handle.state` outlives the signal behind it and
  will read its last value forever. Bind the handle, not a copy of its field.

---

## Replication

### `replication`

`LuauUI.replication` — the client-side replicated-state adapters. Transport
is game-owned; you feed these from your remotes.

**Three ingest verbs, not one overloaded one** (constitution E-16): the name
says *what arrived* — a whole state, a delta, a recovery — because that is what
call sites branch on.

- `replication.snapshot(core, initialRevision, initialData)` — full-state
  snapshots: `.binding` (Signal), `.ingest(revision, data) -> "applied" |
  "stale" | "duplicate"`, `.revision()`. Revisions are monotonic; stale and
  duplicate ingests are refused.
- `replication.collection(core, initialRevision, initialItems, requestResnapshot)`
  — keyed items with patch streams: `.binding`, `.revision()`,
  `.ingestPatch(revision, { set?, remove? }) -> "applied" | "stale" |
  "duplicate" | "gap"`, and
  `.ingestResnapshot(revision, items) -> "applied" | "stale"`.

  A patch beyond the next revision is a **gap**: patching freezes and
  `requestResnapshot(fromRevision)` is called once, with the client's CURRENT
  revision. A throwing `requestResnapshot` does not latch the gap — the next
  patch asks again, so a transient remote error cannot kill the collection.

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
  (`idle/pending/confirmed/rejected` Signal — pending NEVER implies
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

`LuauUI.tokens` — the token compiler. `tokens.compile(schema) -> (compiled?,
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

The built-in default style ("Studio Neutral",
`src/tokens/default_style.luau`) is the neutral floor every app gets for
free; games override via their own schema. Style-modifier normalization
lives in `src/tokens/styling.luau`; the style lint (jagged corner+shadow
caveat, ~100 on-screen shadow budget) in `src/render/style_lint.luau`.

### `themes`

`LuauUI.themes` — theme packages and the effective metric snapshot (ADR-0019).
Engine-free: this is the pure half of the theme system, safe in a shared or
server require graph.

`themes.define(def) -> (package?, report)` compiles a declarative package
(schema `luauui-theme/1`). Sections: `identity` (`id`, `displayName`,
`schemaVersion`, `version`), `style` (ordered per-theme colour variants, gated
by the same 4.5:1 contrast/completeness rules `tokens.compile` applies),
`metrics` (typography roles, spacing steps, control sizes, per-family control
metrics, radii, strokes, `targetSizes.minimum`, per-slot content insets,
`iconSizes`, motion), `chrome` (a recipe per decoration slot: `{kind="native"}`,
`{kind="nineSlice", asset, contentInsets, fallback="native"}` or
`{kind="layered", layers, contentInsets, fallback="native"}`, any of which may
add `shadow`; plus the reserved non-slot key `focus`), `icons` (semantic icon
name → asset reference), `assets`
(semantic name → `{content, sliceCenter?, sliceScale?, preload?, fallback?,
tintRole?}`; `contentId` is a permanent alias for `content` and declaring both is
an error), and `compatibility`. `base = <package>` derives: values you omit
are inherited key-by-key, so "start from Studio Neutral and change the parts I
mean to" is one line. On success the package is deeply frozen and carries a
deterministic content `stamp`; on failure it returns `nil` plus a report whose
`errors` name the offending field, the problem, and the fix. Rejections cover
missing roles, unknown fields (with a "did you mean"), rule properties LuauUI
does not allow a theme to write, contrast failures, invalid insets, target
sizes under the 44px accessibility floor, nine-slice recipes without a declared
fallback or naming an undeclared asset, incompatible schema versions, and any
function anywhere in the definition — a theme is inspectable data, never code.

**The rich-skinning fields (ADR-0020).** Additive to everything above, and all
of them are package data:

| Field | Where | What it is |
|---|---|---|
| `kind = "layered"` + `layers` | a chrome recipe | a contiguous array of at most 8 layers from the closed set `fill` / `frame` / `corners` / `edges` / `plaque` / `tile`, each with its own fixed geometry vocabulary. Z-order is array order. `scrollbar` and `barFill` refuse a stack (canvas space; clipped whole art) — both are compile errors naming the reason and the fix. |
| a per-state `asset` map | any asset reference, at BOTH customization rungs | `{ default, hover, pressed, selected, disabled, error }` through one normalizer. `default` required; unstated states fall back to it with tint rules still applying; a per-state `contentInsets` difference on any axis is a compile error. |
| `barTrack` / `barFill` / `barCap` / `barCenter` | slots | image value displays. `barFill` takes `direction` (`ltr` default, `rtl`, `ttb`, `btt`); its art is drawn at full track size and revealed through an adapter-owned clip window, so a value change costs no adapter write. `barCap` takes `startAsset` / `endAsset` / `size`. |
| `toggleTrack` / `toggleKnob` / `stepperPlate` | slots | the sliding switch and the stepper's glyph plate. Knob travel stays solver-owned. `stepperPlate` is whole-image by default and falls back to the `control` recipe when a package does not declare it. |
| `spinner` | slots | one dot of an indeterminate `newProgressView`'s ring. Round by default (a dot, like the slider thumb); carries its own solid native paint so an unskinned spinner still reads, and refuses a gradient for the same reason every other value-control slot does. **It is the one slot that refuses ART**: the travelling pulse is the control's `tint`, which paints the node's own plate — and art suppresses that plate (`.luau-skinned-spinner { BackgroundTransparency = 1 }`, the image-is-the-element rule), so a skinned spinner would be five identical pictures that never move. A `kind = "nineSlice"` / `"layered"` recipe on it is a compile error naming the size metric, the radius and the accent colour that *do* retune it; `kind = "native"` stays legal. |
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
the frozen `ThemeSnapshot`, exactly once, in the ADR's order: authored metrics →
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

`themes.neutral()` is the Studio Neutral snapshot (the `themeMetrics` default;
its values are the literals the framework shipped before packages existed).
`themes.neutralPackage()` is the compiled package behind it — pass it as `base`.
`themes.lintProperty(prop, scope?)` is the legal-property ruling: a theme rule
may write only the native paint set, plus image chrome inside a nine-slice
recipe (`scope = "chrome"`). `themes.SCHEMA` is the schema string this build
speaks (`luauui-theme/1`).

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

The engine half is client-only and is required directly, not from the `LuauUI`
table (the same rule as `screen_target`):

```lua
local theme_controller = require(ReplicatedStorage.LuauUI.client.theme_controller)
local controller = theme_controller.install(adapter, package, {
    env = env,                -- REQUIRED: the snapshot rides it as `themeMetrics`
    rootGui = rootHandle.gui, -- the target's root; per-target isolation is one
                              -- sheet + one StyleLink at this root
    theme = "Daylight",       -- optional; defaults to style.defaultTheme
    -- profile-conditional selection (ADR-0020 R7): map the input paradigm to a
    -- package and the controller installs the right one and swaps live on a
    -- SETTLED profile change (0.25s debounce). An unmapped class falls back to
    -- the package passed positionally; a manual swapPackage wins until the next
    -- profile change and warns once. The view tree never observes it.
    selectBy = { touch = touchPkg, pointer = pointerPkg, gamepad = pointerPkg },
    -- core?, selectBySettleSeconds?, overrides?, host?, transitions?,
    -- forceFallback?, preflightFonts?, fontFiles?
})
```

`install` materializes the package's own sheet (named `LuauUITheme <id>`, with a
`Theme <name>` child per theme), links it at the target root, resolves the
snapshot and commits it. Every capability check runs **before** the first
mutation: a schema this build does not speak, an unknown or unprovided capability
(`themeMetrics`, `nativeStyleSheets`, `styleTransitions`), or a missing root
fails with an error naming what is missing, and the target and environment are
left untouched.

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
### `newPopupButton`

`LuauUI.newPopupButton(LuauUI, core, spec) -> { blueprint, api, dump, dispose }`
— a select/dropdown control. Closed, it is a single focusable button showing
the currently-selected option's label. Activating it (tap, keyboard Return,
gamepad ButtonA) opens a popup panel listing the options as activatable rows
plus a Cancel row. Activating an option writes the owner-held `value` signal,
fires `onChange`, and closes the popup — the button's label reflects the new
selection with no structural rebuild (the label is a binding on `value`).
Activating the trigger again, or the Cancel row, closes the popup without
changing the selection. While open, the option rows are ordinary focusable
buttons, so keyboard/gamepad users navigate them with the normal focus ring
(Down/Up) and select with Activate; closed, only the trigger is focusable.

Spec: `{ id?, options: { { id: string, label: string } }, value:
Signal<string> (the selected option id), onChange: ((id: string) -> ())?,
presentation: ("automatic" | "menu" | "inline" | "sheet")?, sizeClass:
(string | Readable)?, interactionClasses: (table | Readable)? }`.
Option `id`s must be path-safe (no `/`) and are asserted at build. `value` must
be a **settable Signal you own** — a read-only Memo is refused at build, the way
every sibling control refuses one, rather than crashing on the first selection.
The
selection is OWNER-HELD in `value`: the control reads it (label + per-row
selected marks) and writes it on selection, but never stores selection state
of its own — durable state belongs in your data model. `onChange` fires only
on an actual change (re-selecting the current option just closes).

Returns `{ blueprint, api, presentation, dump, dispose }`, where
`api = { handleActivate(path, meta?) -> boolean, open(), close(), select(id),
isOpen (Signal), presentation() }`. `presentation` here is a **function**
returning the resolved idiom — `"menu"`, `"inline"` or `"sheet"` — chosen from
the option count, the space class and whether touch is live: touch takes the
sheet; a compact space with more than 6 options takes the sheet; 3 or fewer
options outside a compact space go inline; everything else is a menu. (Note the
sibling asymmetry: `newPicker`'s `presentation` is a Readable, not a function.
PKT-1 tracks unifying them at 1.0.) Route the presenter's `onActivate` to
`api.handleActivate` (it returns `true` when the path was the control's — the
trigger, an option row, or Cancel); `open`/`close`/`select` drive the control
from host code without a pointer. `dump()` returns the deterministic
diagnostic summary (`{ schema, id, open, value, selectedLabel, options }`).

```lua
local value = core:signal("normal")
local difficulty = LuauUI.newPopupButton(LuauUI, core, {
	id = "Difficulty",
	options = {
		{ id = "easy", label = "Easy" },
		{ id = "normal", label = "Normal" },
		{ id = "hard", label = "Hard" },
	},
	value = value,
	onChange = function(id)
		print("picked", id)
	end,
})
-- host screen wires activation to the control's router:
pres.present(LuauUI.UI.Screen({ id = "S", children = { difficulty.blueprint } }), {
	sinkNavigation = true,
	onActivate = function(path, meta)
		difficulty.api.handleActivate(path, meta)
	end,
})
```
### `newStepper`

`LuauUI.newStepper(LuauUI, core, spec) -> { blueprint, model, semanticText, dump, dispose }`
— a labelled value with discrete decrement/increment affordances, composed from
shipped primitives over the shared value model.

```lua
local volume = core:signal(5)
local stepper = LuauUI.newStepper(LuauUI, core, {
    id = "Volume", label = "Volume",
    value = volume,              -- OWNER-held settable Signal<number>
    min = 0, max = 10, step = 1, -- step defaults to 1
    format = function(v) return `{v} dB` end,   -- optional
    enabled = true,                             -- boolean | Readable<boolean>
    onChange = function(v) print(v) end,        -- optional
})
```

`value` must be a **settable Signal you own** — the control never creates it,
because the value has to outlive the control. A read-only Memo is rejected at build
rather than erroring on the first press.

Reach: pointer and touch press the two Buttons; keyboard (`,`/`.`) and gamepad
(L1/R1) reach the *same* arithmetic through the focus-gated `Adjust` verb, which is
bound **only while focus sits inside the control**, so a screen containing a Stepper
never shadows gameplay bumper keys. At a bound the affordance is `enabled = false` —
disabled, not silently inert. `enabled = false` on the control refuses every input
class, including Adjust.

### `newProgressView`

`LuauUI.newProgressView(LuauUI, core, spec) -> { blueprint, model, semanticText, phase, dump, dispose }`
— progress, determinate or indeterminate, linear or circular. `spec = { id?,
label?, value? (number | Readable), min? = 0, max? = 1, format?, showValue?,
height?, presentation? ("bar" | "circular" | "spinner"), motionClock?, scope? }`.

**Indeterminate is selected by `value = nil`** — SwiftUI's own rule
(`ProgressView()` with no value is indeterminate). There is deliberately no
second flag: an `indeterminate = true` sitting beside a `value = 0.4` is a
contradiction the framework would have to arbitrate, and the value already
carries the answer. Because `min`, `max`, `format` and `showValue` all describe a
value, declaring one *without* a value is an authoring error rather than a silent
no-op. The mode is construction-fixed, exactly as SwiftUI's two initializers are
two different views.

`presentation` picks the shape, and **the shape and the mode are two independent
axes** — three shapes, two modes. Which cells are legal is a **capability
registry** in the control (`PRESENTATIONS`), and every refusal below is generated
from it rather than hand-written per shape, so a new shape joins by adding a row:

| `presentation` | indeterminate | determinate | `height` | `showValue` |
|---|---|---|---|---|
| `"bar"` (default) | ✅ | ✅ | ✅ the track's thickness | ✅ beside the track |
| `"circular"` | ✅ | ✅ | ❌ refused | ❌ refused |
| `"spinner"` | ✅ | ❌ refused | ❌ refused | ❌ refused |

`"bar"` is the track; indeterminate it grows a segment that sweeps to the far end
and folds back.

**`"circular"` is a ring, and it takes both modes** because both are the same
function of one scalar: determinate binds `arc(0, 360 × fraction)` — a fixed head
with a growing sweep, over a static capacity ring — and indeterminate binds
`arc(360 × phase, 90°)`, a fixed sweep whose *start angle* advances, which is how
it rotates without any rotation existing. There is no native radial primitive in
the engine (searched, 2026-08-13: `UIGradient` has no angular mode, `ImageLabel`
no fractional fill, `EditableImage` no arc, and `GuiObject.Rotation` cannot move
its pivot and is documented incompatible with `ClipsDescendants`), so both forms
are strokes on the `UI.Path` primitive that already ships, drawn from
`LuauUI.pathShapes.arc`. `points` is `dirty = { "paint" }`, so a value change and
a frame of rotation are each **one prop write and zero re-solves**. It adds **no
blueprint prop and no decoration slot**: the arc's paint identity is the Path's
own `role` (`accent`, over a `secondary` capacity ring), and its size is the pair
of optional theme metrics `controls.progress.circularSize` /
`circularThickness` — small by default off the theme's own `space` scale, with no
per-call diameter, because Apple's only size guidance here is "prefer an activity
indicator when space is constrained". Two consequences worth knowing before you
reach for one: **it cannot fade** (`Path2D` has no `Transparency` — wrap it in
your own `UI.ZStack({ canvasGroup = true })` if you need to), and a `UI.Path` that
is not *fully* inside every clip host above it **does not paint at all** rather
than being cropped (`tests/path.spec.luau`, RS-PATHCLIP) — a stroke has no
half-crop, so a ring in a scrolling list winks out at the edge instead of being
sliced.

**Do not read the circular ring as `ProgressView` parity.** On iOS/macOS/tvOS
`ProgressView(value:).progressViewStyle(.circular)` is *indeterminate* — the
determinate ring is a **`Gauge`** (`.accessoryCircularCapacity`, "a closed ring
that's partially filled in"), which LuauUI does not otherwise ship. The
indeterminate form is the `ProgressView` parity claim; the determinate one is the
Gauge shape, offered on the same control because the arithmetic is identical.

`"spinner"` is a ring of five pulsing dots and is **indeterminate only** — a
determinate ring is `presentation = "circular"`, which the refusal now names. (It
used to say "the blueprint has no rotation or trim channel to draw one with",
which stopped being true when `circular` shipped.) It is kept, unchanged, as the
fallback if the arc's per-frame paint ever proves too expensive on a device. The
dots
are fixed squares whose PULSE rides the `tint` channel rather than their size: a
loading indicator lives inside a vertical `ScrollView`, and a fraction of an
unbounded axis is not a size — so the ring animates for zero re-solves and can be
dropped into any container. They paint through one new decoration slot, `spinner`;
the bar paints through `barTrack` / `barFill` exactly as it always has.

### What a theme can change about these two shapes

Both shapes are **theme-sized**, and since 2026-08-14 every shipped package
authors all three numbers rather than inheriting them from its spacing scale
(which is a gap between elements and a poor ruler for the diameter of one —
Classic Desktop's inherited "ring" was a 12px circle):

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
cannot reach. Measured live on 2026-08-14 (Edit datamodel, showcase place), a
`Path2D`'s entire property surface is `Color3`, `Thickness`, `Closed`, `Visible`,
`ZIndex` — and `IsA("GuiObject")` is **false**:

| what a package might want | can it? | through what |
|---|---|---|
| the arc's colour | ✅ | `colors.accent` — the arc declares `role = "accent"` |
| the track's colour | ✅ | `contentSecondary` — the backing ring declares `role = "secondary"` |
| the diameter | ✅ | `controls.progress.circularSize` |
| the stroke weight | ✅ | `controls.progress.circularThickness` |
| the cap shape (round / butt / square ends) | ❌ | the engine has no cap or join property on `Path2D` at all — probed by name, not assumed |
| art along the arc | ❌ | a `Path2D` is not a `GuiObject`, so no stylesheet rule can select one, and the decoration materializer builds `ImageLabel`s, which cannot follow a partial arc. The nearest legal thing is a plate *behind* the ring, which is the caller's own `UI.Box`, not a theme slot |

**The dots** are ordinary `Box` leaves, so they take the whole `luau-slot-spinner`
own-paint ladder — the accent fill, the round corner and the theme's own hairline
— plus `spinnerDotSize`. What they refuse is art; see the `spinner` row in the
recipe table above for why.

**`height` is the bar's track thickness, and only the bar's.** No other shape has
a track, so `presentation = "spinner"` or `"circular"` with a `height` is
**refused** rather than silently reinterpreted as the dot's size or the ring's
diameter — which is what it used to do, turning a
`height` chosen for a chunky bar into five oversized dots and a much wider row. The
dot is the theme metric `controls.progress.spinnerDotSize`, which is where a size
every spinner should agree on belongs. This is the same rule as the `min` / `max` /
`format` / `showValue` refusals above: a field whose meaning does not survive the
mode is an authoring error, never a silent reinterpretation.

**`showValue` is refused on `"circular"` for the same reason**, and it is the one
place this control deliberately does *not* copy Apple. `.accessoryCircularCapacity`
centres the value inside the ring — but that is a complication-sized dial, while
this indicator is theme-sized and small with no per-call diameter to grow it, so a
centred readout has no size it is guaranteed to fit inside; and putting it *beside*
the ring, where the bar puts it, would ship a different design under Apple's
description. Both alternatives are named in the refusal: compose your own
`UI.Text` next to the control (what the gallery fixture does), or use the bar.

`motionClock` is the surface's motion clock (`presenter.motionClock`), and only
the indeterminate cycle reads it — a determinate bar never touches it. With no
clock the indeterminate view holds its rest pose and reports
`dump().animating = false`: honest, rather than a spinner that silently is not
spinning.

**`scope` is REQUIRED when `value = nil`, and it is the only control in this
family that demands one** — for the same reason `newAsyncImage` does: an
indeterminate view *acquires* something with a lifetime. It holds a live entry on
the motion clock and writes its phase signal every frame for as long as it exists,
and the only thing that stops it is disposal. Measured before the requirement:
a view presented and then **dismissed**, and a view **built and never presented**,
each kept one clock entry active and wrote 121 times over 120 steps — forever,
because nothing called `dispose()`. Every other control in this library is inert
the moment you drop it; this one was not.

Pass the scope that owns the surface — the presenter's own `handle.scope` retires
the cycle exactly when the surface's mounted tree is disposed — or any scope you
dispose yourself. The control builds a **child** of it, so disposing yours disposes
the whole control (memos, motion value and all) with no second call. `dispose()`
remains public and is **idempotent**, so calling it *and* letting the scope fall is
safe in either order.

There is deliberately no automatic release keyed off "nobody is watching": measured,
`presenter.dismiss` produces no unmount event a control can see (the phase memos are
simply never pulled again, 0 adapter ops over 10 frames), and re-presenting the same
blueprint recomputes nothing — so a cycle that parked itself on "nobody read me"
could never learn it was back on screen, and a frozen spinner is the one lie a
loading indicator must not tell. Naming the owner at construction makes the leak
unrepresentable instead. A determinate view acquires no clock entry at all
(`activeCount` stays `0` even when handed a clock), so `scope` stays optional there.

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
single** phase value from the **same** `clock:glide(…, kind = "informational")`
call, so a rotating ring acquires no clock entry the five dots did not already
cost, and the reduced-motion policy above applies to it verbatim.

Retheming those slots — or shipping art for them — restyles every progress bar.
It does **not** borrow the `control` and `accent` surfaces any more, and that is
the point: those are treatments meant for buttons and panels, so an ornate
package stretched a button plate across the track and a panel gradient's alpha
made the fill see-through (ADR-0020 R3). A theme customizes a bar through
`chrome.barTrack` / `chrome.barFill`, never through the button rules.
Out-of-range values clamp through the shared value model rather than overflowing, and
`semanticText` states the value in its range; an indeterminate view's `semanticText`
is the static string `"Loading"`, because the only true sentence about it is that the
work is running and re-announcing it sixty times a second is exactly what a live
region must not do. **Non-interactive** by declaration — it reports, it does not
accept input, and it deliberately attaches no input contribution.

`dump()` carries `{ schema, id, indeterminate, presentation, … }`; a determinate
view keeps every key it published before indeterminate existed, with the same
values (`value`, `fraction`, `formatted`, `semanticText`, `min`, `max`,
`showValue`), and an indeterminate one adds `phase` (the live 0..1 cycle position)
and `animating`.

### `newLabel`

`LuauUI.newLabel(LuauUI, core, spec) -> { blueprint, semanticText, dump, dispose }`
— an icon + title pair. `spec = { id?, title (required), icon?, presentation?
("titleAndIcon" | "titleOnly" | "iconOnly"), iconSize?, textSize?, gap? }`.

`title` is **required** because it *is* the semantic text: `semanticText` is the title
whatever the presentation, so an icon-only Label is never a control with no accessible
name. It is a **`Readable<string>`**, like the one every other control in the family
publishes (`newProgressView`, `newStepper`, `newSlider`, `newRating`) — read it with
`:get()`, so an accessibility or readout layer can be written once for all five.
`iconOnly` **degrades to the title** when there is no icon to show — an empty
square is worse than a word. Non-interactive: put it inside a `Button` (which takes
content) when it must be pressable, which keeps one activation surface.

### `newPicker`

`LuauUI.newPicker(LuauUI, core, spec) -> { blueprint, presentation, dump, dispose }`
— single selection from a small option set. `spec = { id?, label?, options ({ value,
label }[]), selected (Signal), presentation? ("automatic" | "segmented" | "inline"),
sizeClass?, enabled?, onChange? }`.

**The presentation is adaptive, not a platform branch.** `"automatic"` (the default)
picks from the option count and the space class you pass in — typically
`LuauUI.adaptive.conditions(core, env).sizeClass`. The rule is small enough to
state in full, and it is the whole rule — a device name appears nowhere:

| Condition (first match wins) | Presentation |
|---|---|
| more than 4 options | `inline` |
| `sizeClass == "compact"` **and** (more than 3 options **or** the longest label is over 10 characters) | `inline` |
| otherwise | `segmented` |

`presentation` on the returned table is a **`Readable<string>`** of the resolved
answer, so you can bind it. (The rule function itself is not on the public
`LuauUI` table today; the table above is the contract.)

The option group is a `UI.AdaptiveStack`, so a live space change **flips the
presentation without remounting the options** — they keep their identity, focus and
state. Selection rides the `selected` binding (a style tag), never a bespoke fill, and
every option row meets the enforced 44 px floor. For a popup presentation use
`newPopupButton`, which owns the transient-surface machinery.

### `newDisclosureGroup`

`LuauUI.newDisclosureGroup(LuauUI, core, spec) -> { blueprint, bindFocus, dump, dispose }`
— a labelled header that expands and collapses its content. `spec = { id?, label
(required), expanded (Signal<boolean>), content (() -> Blueprint), enabled?, onToggle? }`.

Content mounts through `UI.When`, so a collapsed group genuinely costs nothing (only
structural regions may mount or unmount).

**Focus is the load-bearing detail.** Collapsing while focus sits inside the content
would leave focus on a node that is about to be unmounted, so the control moves focus
back to its own header **before** the content disappears. Expanding leaves focus on
the header — the player asked to see the content, not to jump into it. Call
`bindFocus(presenter.focus)` (or let the control pick the focus graph up from the
controller) so it can do that.

`expanded` is a Signal **you** own, so a settings screen remembers which sections were
open across a remount.

### `newSlider`

`LuauUI.newSlider(LuauUI, core, spec) -> { blueprint, model, semanticText, fillWidth, thumbOffset, onInteractionClassLost, dump, dispose }`
— a continuous or stepped value along a track, sharing the value arithmetic with
`newStepper`.

```lua
local volume = core:signal(50)
local slider = LuauUI.newSlider(LuauUI, core, {
    id = "Vol", label = "Volume",
    value = volume,               -- OWNER-held settable Signal<number>
    min = 0, max = 100, step = 5, -- step nil = continuous
    tapToPosition = true,         -- default; false requires a drag to move
    onChange = function(v) end,   -- every accepted change
    onCommit = function(v) end,   -- once, when the drag ends
    thumbImage = nil,             -- optional: a content URI, or a per-state map
    trackImage = nil,             -- optional: a content URI, or a per-state map
})
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

**Both props take the same per-state grammar a recipe's `asset` does** (ADR-0020
R2), normalized by the same function, so the two rungs can never drift into
different vocabularies:

```lua
thumbImage = { default = "rbxassetid://…", hover = "rbxassetid://…", pressed = "rbxassetid://…" }
```

`default` is required in map form. HONEST LIMIT: a slider thumb is a `Frame` and
never leaves `GuiState.Idle`, so `hover` and `pressed` on a *thumb* are
unreachable at both rungs today; those states are reachable on an interactive
node such as a button's `control` slot. See
[`../guide/10-rich-skinning.md`](../guide/10-rich-skinning.md) §10.10.

**Live drag is the native detector.** The track adopts `UIDragDetector` through
`controller.attachDragDetector` (`roblox-native-audit-corrections.md` §1). The
corrections also require a fallback for targets where the detector is not usable, so
the track is a `UI.Grip` whose capture-based pointer handlers drive the **same**
mutation site — nothing here is a slider-specific recognizer, and `dump().nativeDetector`
reports which route is live.

**Keyboard and gamepad use `Adjust`, not a continuous stick.** Increments are
predictable and the binding is focus-gated, so a screen containing a Slider never
shadows gameplay bumper keys.

**Hot-switch is CANCEL.** Unlike `Stepper`, a Slider holds in-flight state. Losing the
pointer class mid-drag — or the engine cancelling the capture — reverts to the
pre-drag snapshot rather than committing a value the player did not choose. Drive it
from your live interaction-class watcher via `onInteractionClassLost(class)`.

The root row is `fill`-width by design: a fill-width track inside a content-sized
parent would resolve to zero and leave nothing to drag along.

### `newRating`

`LuauUI.newRating(LuauUI, core, spec) -> { blueprint, semanticText, onInteractionClassLost, dump, dispose }`
— a short run of glyphs that reads as **one** value: a star rating, a difficulty
dial, a five-point score.

```lua
local score = core:signal(3)
local rating = LuauUI.newRating(LuauUI, core, {
    id = "Score",
    value = score,             -- OWNER-held settable Signal<number>
    count = 5,                 -- how many glyphs; default 5
    allowZero = true,          -- default; false makes 1 the floor
    readOnly = false,          -- true paints it and takes it out of the focus ring
    glyphs = nil,              -- optional { filled = "★", empty = "☆" } override
    starSize = "small",        -- the rung the glyph is DRAWN at; the box is a share
    onChange = function(v) end,
})
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
  Five activation handlers writing one signal is one verb in five costumes, and
  nothing could read the control's value *as* a value.

A Rating is instead an `HStack` of glyph `Text` nodes under a single `UI.Grip`:
one focus stop, one effective target, one place pointer input lands, and a value
change repaints exactly `count` labels without remounting anything.

**Reach.** Pointer and touch tap anywhere on the strip to set, or press and drag
to scrub live (dragging off the leading edge clears to zero when `allowZero`).
Keyboard and gamepad use the focus-gated `Adjust` verb — Comma/Period and L1/R1
— bound **only** while focus is inside the control, so a screen containing a
Rating never shadows gameplay bumper keys.

**Hot-switch is CANCEL**, like `newSlider`: a scrub is in-flight state, so losing
the pointer class mid-drag reverts to the pre-scrub value rather than committing
a rating nobody chose. Drive it from your interaction-class watcher via
`onInteractionClassLost(class)`.

**The glyphs are the control's own characters, not theme icons.** `★`/`☆` are
chosen the same way `newTextInput`'s clear `×` (U+00D7) is — BMP characters
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

### `valueModel`

`LuauUI.valueModel.new({ min, max, step?, format? }) -> Model` — the shared,
pure arithmetic behind the value-control family, so `Stepper` and a `Slider` cannot
disagree at the edges: `clamp`, `quantize`, `stepped`, `fraction`, `fromFraction`,
`format`, `semanticText`, `atMin`, `atMax`.

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

### `newTextInput`

`LuauUI.newTextInput(LuauUI, core, spec) -> { blueprint, api, dump, dispose }`
— a single-line text field: a composite of the `UI.TextField` primitive and an
optional trailing clear button. The OWNER holds the text in a `Signal<string>`;
the control never creates it (state that must outlive the control belongs to
the caller, §10.5). Editing is a control-owned handshake — activating the field
(tap, or focus + Activate on keyboard/gamepad) enters text-entry mode, which
raises a high-priority **sinking** InputContext so keystrokes/arrows stop being
navigation while the field is focused; commit-on-Enter and focus-loss arrive
from the engine through the render-adapter text seam. Cross-platform by
construction: pointer, touch, keyboard, and gamepad each drive the same value
model.

**Spec** `{ id, value, onChange?, onCommit?, placeholder?, disabled?,
keyboardType?, submitLabel?, clearButton?, clearButtonMode?, maxLength?,
validate?, env?, actionSystem? }`:

- `id: string` — path-stable identity.
- `value: Signal<string>` (required, owner-held) — the field text. Must be a
  **settable** signal (the control calls `value:set` on every accepted edit); a
  read-only Memo is a build error. The field's `text` is a binding on it; an
  accepted edit relabels the field with no structural churn.
- `onChange: (text) -> ()?` — **live** mode: fires on every accepted edit while
  typing (and on clear). Never fires for a cancel revert.
- `onCommit: (text, reason) -> ()?` — **commit** mode: fires on Enter
  (`reason = "enter"`) and on focus loss (`reason = "focusLost"`). `onChange`
  and `onCommit` are distinct and may coexist.
- `placeholder: string?` — shown by the engine when the value is empty.
- `disabled: boolean | Signal<boolean>?` — a disabled field is excluded from
  focus, cannot be edited (tap/Activate do nothing), and shows no clear button.
- `keyboardType: "default" | "numeric" | "email" | "phone"?` — declared intent;
  an unknown value is a build error. **The current engine exposes no public
  keyboard-type API** (`TextBox.TextInputType` is CoreScript-only), so the
  adapter detects capability and degrades to the default keyboard; the
  declaration is preserved as data on the field for the engine adapter and never
  promises a particular keyboard.
- `submitLabel: "default" | "done" | "go" | "next" | "search" | "send"?` — the
  Return-key label hint, validated at build and **never applied to anything**.
  `TextBox.ReturnKeyType` is hidden and not scriptable, so there is no engine
  surface to write it to; this is a declared, justified engine-absent exception
  kept as data (it appears in `dump()`) for parity with `keyboardType`. Declaring
  it changes no pixels today.
- `clearButton: boolean?` — sugar for `clearButtonMode = "always"`. Activating
  the `×` empties the value (a user edit: fires `onChange`, does not commit);
  focus returns to the field as the vanished button's nearest survivor.
- `clearButtonMode: "never" | "whileEditing" | "unlessEditing" | "always"` —
  **when** the trailing `×` is offered, spelled as UIKit spells it
  (`UITextField.clearButtonMode`), because that vocabulary is already in every
  designer's head and the four states are the four real answers:

  | mode | offered |
  |---|---|
  | `"never"` (default) | no affordance at all |
  | `"whileEditing"` | only while the field has focus — the iOS search-field convention, and the one that stops a list of filled fields being a wall of `×` glyphs |
  | `"unlessEditing"` | only while it does *not* have focus — a settings row that offers "clear this" at rest and gets out of the way once you type |
  | `"always"` | whenever there is text to clear |

  Every mode is additionally gated on **there is something to clear** and **the
  field is not disabled**: an empty field offers nothing in any mode. The two
  focus-sensitive modes read the control's own `editing` state, so the
  affordance appears and disappears with the caret and nothing else has to drive
  it. An unrecognised mode is a **build error**, not a field that silently never
  offers a `×`.
- `maxLength: number?` — accepted text is clamped at the value-model boundary
  (Unicode-scalar count); edits that would exceed are truncated, including a
  paste-like multi-character append. A proposed edit that is not valid UTF-8 is
  rejected outright (value unchanged, no `onChange`) — the model never accepts a
  malformed byte sequence, so nothing can slip past `maxLength`.
- `validate: (proposed) -> string??` — runs on every proposed edit (typing,
  clear, engine-reported text) AFTER the maxLength clamp, and on the commit
  path. Return the accepted (possibly normalized) string, or `nil` to REJECT
  (value unchanged, no `onChange`). **`validate` MUST be an idempotent
  normalizer: `validate(validate(x)) == validate(x)`.** A real engine echoes a
  programmatic `.Text` write back through `onTextChanged`, so a non-idempotent
  normalizer (one whose output re-normalizes to something different) would not
  reach a fixed point and could loop; an idempotent one settles in one round.
- `env: Environment?` — when provided, keyboard-occlusion keep-visible is
  active (see invariants).
- `actionSystem?` — the action system to raise the text-entry sinking context
  in. Injected like `env`; without it the value model still works but keystroke
  sinking cannot engage. The presenter's action system is the right one to pass.

**Returns** `api = { editing (readable Signal<boolean>), keepVisibleOffset
(readable Signal<number>, 0 when clear), handleActivate(path, meta?) -> boolean,
syncGeometry(rectOf), focusGroups(rootNode), bindActionSystem(actionSystem) }`.
Route the presenter's `onActivate` to `api.handleActivate` (returns `true` when
the path was the field or its clear button); wire `onGeometry` to
`api.syncGeometry` and `keepVisibleOffset` to `api.keepVisibleOffset` to enable
keep-visible. (`focusGroups` and `bindActionSystem` also ride the control's own
input contribution, so the presenter already calls them — they are on `api` for a
host that composes input by hand.) `dump()` returns
`{ schema, id, value, editing, disabled, placeholderVisible, clearVisible,
clearButtonMode, occlusionOffset, keyboardType, submitLabel }`.

**Invariants**

- **Accepted-edit semantics.** `value` only ever holds a value that passed
  clamp + validate. The engine view may briefly diverge past the model when an
  edit is rejected/clamped (the engine avoids rewriting `.Text` per keystroke,
  which is IME-unsafe); the model keeps the last accepted value and the next
  refresh reconciles the shown text on commit/blur.
- **Text-entry mode sinks navigation, not Activate.** While editing, arrows and
  D-pad are swallowed so typing never navigates; Activate (Return/ButtonA) is
  intentionally left un-sunk (re-activation is an idempotent no-op) so the
  presenter's shared Activate state is never corrupted and keyboard/gamepad
  re-entry keeps working. Cancel (ButtonB, or the engine-reported desktop
  Escape as `onFocusLost("cancel")`) reverts to the pre-edit snapshot.
- **Keyboard occlusion.** With `env` provided, while editing, if the field's
  solved rect intersects `env.keyboardOcclusionRect` the control publishes a
  minimal upward offset on `api.keepVisibleOffset`; the presenter applies it as
  a presentation-authority transform on the screen root (no remount, no factory
  reruns) and restores 0 on exit.
- **Ownership.** `dispose()` = `scope:dispose()`; the text-entry context is
  owned by the control scope and disposed even if disposed mid-edit.

```lua
local name = core:signal("")
local field = LuauUI.newTextInput(LuauUI, core, {
	id = "Name",
	value = name,
	placeholder = "Your name",
	clearButton = true,
	maxLength = 24,
	onChange = function(text) print("editing:", text) end,
	onCommit = function(text, reason) print("committed", text, "via", reason) end,
	env = env,
	actionSystem = system,
})
-- these three opts ARE the text-entry wiring; nothing here is required to make
-- typing stop navigating — that comes from the injected `actionSystem` raising
-- the field's own sinking edit context while editing.
pres.present(LuauUI.UI.Screen({ id = "S", children = { field.blueprint } }), {
	onActivate = function(path, meta) field.api.handleActivate(path, meta) end,
	onGeometry = function(rectOf) field.api.syncGeometry(rectOf) end,
	keepVisibleOffset = field.api.keepVisibleOffset,
})
```
### `newChip`

`LuauUI.newChip(LuauUI, core, spec) -> { blueprint, dump, dispose }` — a small
toggleable tag/filter pill. It renders as a single rounded label (a Button with
`pill` corners) whose surface reflects a caller-owned selection: activating it
(pointer tap, mouse click, keyboard Return, or gamepad ButtonA) flips the
`selected` signal and calls the optional `onToggle`. Use it for filter rows,
multi-select tags, and any place a compact on/off chip reads better than a
full-width toggle row.

Spec fields:

| field | type | required | meaning |
|---|---|---|---|
| `id` | `string` | no (default `"Chip"`) | the blueprint id; the mounted path is `<screen>/<id>`. |
| `label` | `string` | no (default `""`) | the text painted on the pill. |
| `selected` | `Signal<boolean>` | **yes** | the owner-held selection. The chip reads it to paint the surface and flips it on activate — it never creates or owns it. Validated at build: absent, or a read-only Memo, is an error naming the control and the field, not a crash on the first tap. |
| `onToggle` | `(nextValue: boolean) -> ()` | no | called after each flip with the new value (e.g. to persist a filter). |

Return surface:

- `blueprint` — mount it (usually as a child of a `Screen`). The four-input
  story is auto-composed by the presenter from the input contribution the chip
  attaches to its root, so **no `present()` opts are needed** — a bare
  `pres.present(screen)` makes the chip reachable and activatable on pointer,
  touch, keyboard, and gamepad.
- `dump()` — a deterministic diagnostic table
  (`{ schema = "luauui-chip-dump/1", id, label, selected }`); two calls with
  unchanged state are byte-identical.
- `dispose()` — disposes the control scope and nothing else.

Invariants:

- **Selection is the caller's data model.** It must outlive the control, so the
  chip only reads and flips the passed-in `selected` signal; it holds no
  persistent state of its own. Build/mount/interact/dispose is registry-neutral.
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

```lua
local raining = core:signal(false)
local chip = LuauUI.newChip(LuauUI, core, {
	id = "Rain",
	label = "Rain",
	selected = raining,
	onToggle = function(on) print("rain filter:", on) end,
})
-- zero present opts: pointer/touch/keyboard/gamepad all just work
pres.present(LuauUI.UI.Screen({ id = "S", children = { chip.blueprint } }))
```
### `newRowActions`

`LuauUI.newRowActions(LuauUI, core, spec) -> { blueprint, dump, dispose }` — a
swipeable action tray around an arbitrary row (iOS Mail-style leading/trailing
actions: Delete, Flag, Mark Read, ...): the spec contract, a lazily-mounted
tray on each edge, spring-animated reveal with proportional tray-button
growth, and the full cross-input gesture story — mouse drag, touch, keyboard
Delete/Backspace and Shift+Return, gamepad ButtonX/A/B, and full-swipe commit
— every action reachable on every input device (see Tasks 5-8b below). `_open`
and `_close` remain available as the programmatic entry points a caller (or
the edit-mode minus, Task 9) can drive directly, animated exactly like a live
gesture's release.

A row with **no actions on either edge is a true inert passthrough**: `spec.content`
mounts completely unwrapped (no extra node, no extra `Instance`) — the perf
floor for a list where most rows carry no actions.

Spec fields:

| field | type | required | meaning |
|---|---|---|---|
| `id` | `string` | no (default `"RowActions"`), **required when `coordinator` is set** | the blueprint id when either edge has actions; irrelevant to the inert-passthrough shape, since nothing wraps `content` then. When `coordinator` is present, omitting `id` is a build-time error (redteam item 16, constitution strictness): every row in a shared-coordinator list defaulting to the same literal `"RowActions"` id collides — Table's own integration always supplies `"RowActions-" .. rowKey`, so this can only ever be reached by a standalone caller composing its own list. |
| `content` | `Blueprint` | **yes** | the wrapped row. Slides horizontally over a revealed tray; otherwise painted exactly as authored. |
| `leading` | `{ ActionSpec }?` | no | actions revealed by swiping right (or opening edge `"leading"`). `nil` = no leading tray; an empty table `{}` is a spec error (use `nil` for "none"). |
| `trailing` | `{ ActionSpec }?` | no | actions revealed by swiping left (edge `"trailing"`). Same `nil`/`{}` rule. |
| `fullSwipe` | `boolean \| { leading: boolean?, trailing: boolean? }` | no (default `true`) | whether a full swipe past the tray commits that edge's FIRST action outright (iOS "swipe to delete"), per edge. Committing a **`role = "destructive"`** first action runs the slide-off + row-height-collapse sequence, fires `onAction` once, and leaves the row committed (a later gesture/tray-tap on it is a no-op — the owner is expected to remove it from the data model). Committing a **non-destructive** first action fires `onAction` immediately (the identical quarantined call a direct tray-button tap makes) and springs the row back to CLOSED — it never slides off-screen or collapses height, and stays fully interactive: SwiftUI parity for a full swipe on "Flag"/"Archive"/"Mark Read"-shaped actions, which must feel exactly like tapping that button in the revealed tray, not like a deletion (RED-TEAM finding, director-ruled). An edge with `fullSwipe = false` still opens/closes on a partial swipe; it can never commit past the tray. |
| `coordinator` | `table?` | no | the value `newRowActionsCoordinator` returns (single-row-open-at-a-time policy for a list of rows). Wired (Task 7): a gesture crossing the axis lock, or `_open`, claims it — closing whichever other row is open — and this row releases its own claim on every close/dispose. Omitted, an instance only ever manages itself. **When present, `id` becomes required** (see the `id` row above) — every row sharing one coordinator must carry its own unique `id`. |
| `env` | `Environment?` | no | live theme reactivity for each tray button's reserved width (`buttonPad`, `buttonMinWidth`), the same `spec.env` precedent `newTable` already ships (a composite has no other line to the environment — font/size facts arrive fully resolved through `controller.textAt` instead; see the Invariants note below). Absent degrades to `themeSnapshot.neutral()`, exactly like `newTable`'s own fallback — the neutral package at authored size. |
| `editing` | `Readable<boolean>?` | no | Task 9: the caller's own edit-mode signal (`newTable`'s own `spec.editing` is the shipped precedent for this exact shape, and Table's `rowActions` integration passes its own straight through). Present AND true, on a row that declares a `role = "destructive"` action anywhere: a leading minus button appears (see Task 9 below). Absent (the default), the minus never appears and this control costs nothing extra. Must be a Readable when present — a plain `true`/`false` literal is a build-time error. |

`ActionSpec`:

| field | type | required | meaning |
|---|---|---|---|
| `id` | `string?` | no (default: `label`) | must be path-safe (no `/`); becomes the tray button's id, `Action:<id>`. |
| `role` | `"normal" \| "destructive"` | no (default `"normal"`) | `"destructive"` paints the Button's own `role = "destructive"` (the shipped danger/onDanger style rule — no bespoke color). |
| `label` | `string` | **yes** | the action's semantic name, and the string the framework reserves the button's box for. **Drawn** in the tray only when the action declares no `icon` (see below), and always drawn in the action menu's own row. Never truncated by this control; a label-drawing button widens past the theme's `controls.rowActions.buttonMinWidth` floor rather than clip a long (e.g. pseudo-localized) label. **Accessibility rider:** icon-first replaces the tray button's engine `Text` with the icon's glyph, so on an icon action the word itself reaches the player through the action MENU row, not the tray plate — the menu is the reading of the tray, one activation away (`ButtonX` / Shift+Return / the framework's own tap path). A screen-reader name independent of drawn text is not a seam this control owns today; it is the platform-wide `Button.label` question. |
| `icon` | `string?` | no | a `standard_icons` name. **The tray is icon-first**: an action that declares one wears its icon on the tray button at every width — settled and mid-swipe alike — and `label` becomes the semantic name only. The **menu row keeps the word**, so the reading of the tray is always one activation away. Carried as `compactLabel = { icon = …, prefer = true }` on the tray button and as `compactLabel = { icon = … }` (degrade-only) on the menu row; `Button.icon` itself is circle-only, so this never reaches that prop directly. Omitted is text-only everywhere, unconditionally. |
| `onAction` | `() -> ()` | **yes** | called when the action activates: a tap/click/Return/ButtonA on the revealed tray button, an activation of the action's own row in the Task 8 menu, or — for a `role = "destructive"` action — keyboard Delete/Backspace. |

Return surface:

- `blueprint` — mount it (usually as a row inside a list). When either edge
  has actions, its own input contribution auto-composes the tray buttons'
  Activate dispatch (pointer, touch, keyboard, gamepad) exactly like every
  other interactive composite — **no `present()` opts are needed**.
- `dump()` — a deterministic diagnostic table
  (`{ schema = "luauui-rowactions-dump/1", id, offset, openEdge, phase, menuOpen }`,
  `phase` one of `"closed" | "open"`; `menuOpen` is the action menu's own open
  state, independent of the tray).
- `dispose()` — disposes the control scope and nothing else.

**Task 8: keyboard Delete + the action menu.** When either edge declares a
`role = "destructive"` action, focusing anywhere inside the row's own
mounted subtree — `content`, a revealed tray button, or (see below) an open
menu row — and pressing **Delete or Backspace** commits the FIRST
destructive action found (trailing searched before leading) through the
same slide-off + collapse sequence a full swipe uses — never a bare
callback. No destructive action anywhere means the binding is not
registered at all (the key falls through to whatever else wants it). A
**gamepad ButtonX press, or keyboard Shift+Return (Task 8b)**, same focus
scope, toggles a small popup menu (PopupButton-pattern: transient,
focus-trapped, outside-tap swallows and dismisses) listing every declared
action — leading then trailing, document order — as a focusable row. **The
menu is its own floating `presentModal` surface**, not a child measured
inside this row's own tree (RED-TEAM fix: the original measured-child menu
could grow past the row's own content height and inflate the row — and, in a
Table, the whole list — it sat in; `tests/row_actions_input.spec.luau`'s
"the menu contributes zero to row/list measure" cases pin a sibling row's
solved rect byte-identical whether or not this row's menu is open);
activating one runs it exactly once (a destructive item through the same
commit sequence as Delete) and closes the menu; Cancel (gamepad ButtonB)
closes it without firing anything. **While the menu is open, it owns all
input**: opening it moves focus onto its own first row, and Delete/Backspace
go inert for as long as `menuOpen` is true — the menu's own Activate/Cancel
is the only way to act on ANY action, destructive or not, once it is up
(closing it, via Activate, Cancel, or a second Shift+Return, hands
Delete/Backspace back).

**Task 8b: `Shift+Return`.** Task 8 shipped ButtonX only — `Shift+Return`
was NOT expressible: the action system had no modifier slot on a key
binding, `Return` was already the base screen's own Activate key, and a
focused leaf's own `onActivate` fires before any contribution or modifier
state is consulted, so a second Return-bound context would either
double-fire alongside Activate on a shifted press or, sinking to avoid
that, silently eat plain Return for the row. Task 8b's fix is additive, in
the action system itself, not this control: `action.bind` (both
`src/input/actions.luau` and its real-engine adapter
`src/client/roblox_input.luau`) now accepts `modifiers = { shift = true }`
on a keyCode binding, matched only while shift is held. `RowActionsMenu`
binds `Return` with that modifier in the SAME sink=true, priority-10000
context Delete/ButtonX already use — the preemption of the base Activate
context's unmodified `Return` binding falls out of the EXISTING
priority/Sink arbitration (a higher-priority Sink context blocks a lower
one on the same key) the instant the held modifier makes this binding an
eligible candidate; with shift not held it is never a candidate, so plain
Return reaches the base Activate context exactly as before Task 8b.
Gamepad bindings never declare `modifiers` and are unaffected by held
keyboard modifiers. `ctrl`/`alt` are not accepted on `modifiers` — the
action system only tracks `shift` distinctly from a single merged `toggle`
(ctrl+meta) group, so a `ctrl`/`alt` flag could type-check but never
actually match; wire `MODIFIER_GROUP` (`src/input/actions.luau`) first if a
future binding needs one.

**Task 9: the edit-mode leading minus.** While `spec.editing` is a Readable
that reads `true`, AND a `role = "destructive"` action exists on either
edge, a small circular button (diameter `controls.rowActions.editAffordance`,
28px; a `danger`-role disc, the same `role = "destructive"` mapping a tray's
own destructive button already carries) appears in a LEADING gutter — the
row's own `content` is INSET by the gutter width to make room (it is the
content node's left padding, so it holds at every swipe offset of either
sign; the minus never collapses mid-swipe and never pops back at settle), and
the leading tray, if declared, shifts right by the same amount. The minus
paints OVER the sliding content, so a trailing swipe passes under it and it
stays pinned at the left for the whole gesture. It is a normal, focusable `UI.Button`
(activates via the standard tap/Return/ButtonA path already proven for
every other tray button above — no separate registry citation, since the
reachability MECHANISM does not change) and does **not** delete directly:
activating it calls the same `_open("trailing")` the public API exposes,
revealing the trailing tray with the destructive action one tap away (iOS
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
  solved geometry.** Two shapes were tried and rejected (code review,
  2026-08-10): caching a label's width at build time is wrong forever (the
  engine has not laid anything out yet — the exact "cached before truth
  exists" bug class `docs/research/roblox-text-bounds-boot-window.md` warns
  about), and reading the width back from the tray's own solved rect is a
  feedback loop the moment the reveal itself is what shrinks that geometry,
  and permanently stale against a later `preferredTextSize`/theme change
  (a solved rect only exists because THIS composite triggered a solve). The
  shipped mechanism instead asks `controller.textAt(path)` — the framework's
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
local row = LuauUI.newRowActions(LuauUI, core, {
	id = "Row1",
	content = LuauUI.UI.Text({ id = "Title", text = "Inbox message" }),
	trailing = {
		{ id = "delete", label = "Delete", role = "destructive", onAction = function() print("deleted") end },
		{ id = "flag", label = "Flag", onAction = function() print("flagged") end },
	},
})
pres.present(LuauUI.UI.Screen({ id = "S", children = { row.blueprint } }))
```

### `newRowActionsCoordinator`

`LuauUI.newRowActionsCoordinator(core) -> { claim, release, bindScroll }` — the
open-state coordinator for a list of `newRowActions` rows: **at most one row
open per surface**. A plain `VStack`/`ScrollView` list builds its own instance
and passes it to every wrapped row's `spec.coordinator` key; `newTable`'s own
`rowActions` wiring does the identical thing for its rows automatically. A row
built with no coordinator stays valid and only ever manages itself. **Every
row sharing one coordinator must pass its own unique `spec.id`** (the example
below does, via `item.id`) — `newRowActions` refuses to build, at build time,
a coordinator-sharing row with no `id` at all, since every such row would
otherwise default to the same colliding `"RowActions"` id.

Return surface:

| member | type | meaning |
|---|---|---|
| `claim` | `(instance) -> ()` | called by a row itself (a gesture crossing the axis lock into horizontal, or its `_open`): closes whichever OTHER row is currently claimed (that row's own animated `_close` — a spring, or an instant snap under reduced motion / no bound motion clock), then claims `instance`. `instance` is the exact table `newRowActions` returned for that row — no separate id. |
| `release` | `(instance) -> ()` | called by a row on every close and on `dispose()`. Idempotent: releasing an instance that does not currently hold the claim (or nothing is claimed) is a silent no-op. |
| `bindScroll` | `(controller, path: string) -> (() -> ())` | wires `controller.observeScroll(path, ...)` (present-time, same idiom as `Table.bindNativeScroll`) so **any** scroll movement on that host — no distance/velocity threshold, matching iOS — closes whichever row is currently open. Returns the unsubscribe. |

```lua
local coordinator = LuauUI.newRowActionsCoordinator(core)
local rows = {}
for _, item in items do
	table.insert(rows, LuauUI.newRowActions(LuauUI, core, {
		id = item.id,
		content = rowContent(item),
		trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() remove(item) end } },
		coordinator = coordinator,
	}))
end
local scrollHandle = LuauUI.UI.ScrollView({ id = "List", children = blueprintsOf(rows) })
-- after present(): controller comes from pres.present/pres.refresh's own render controller
local unbindScroll = coordinator.bindScroll(controller, "/S/List")
```

### `newDragSession`

`LuauUI.newDragSession(opts) -> session` — the pure, engine-free drag-session
model (roblox-native audit corrections §1). Roblox's `UIDragDetector` owns
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

`LuauUI.interactionTokens` — the shared per-input-class interaction thresholds
(ADR-0022 Decision 5, row SF-D3). **One** place decides whether a press became a
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

The decision is made against the pointer type of the **event in hand**, never
against the live interaction-class set: a hybrid device delivers mouse and touch
events to the same node, and the class set cannot say which one this press was.
`newTable`'s reorder threshold reads this module; its touch reorder rides the
edit-mode grip (which presents as a mouse pointer), because the row body declines
the capture on touch so the native `ScrollingFrame` keeps the pan.

### `newDragVelocity`

`LuauUI.newDragVelocity(opts?) -> tracker` — the rolling release-velocity
tracker (row SF-D2). `opts.windowS` defaults to **0.1 s**.

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

`LuauUI.newAutoscroll(opts?) -> model` — the pure drag-to-edge autoscroll model
(row SF-L2). It answers a **delta**; it scrolls nothing, reads no clock and
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
A tick-based re-resolve lags about two rows at `vMax`. `newVirtualList` does this
for you. Non-pointer schemes have no autoscroll path at all: focus-follows-
navigation already scrolls the host.

### `newDragRegistry`

`LuauUI.newDragRegistry(opts) -> registry` — a surface's live
`UI.draggable`/`UI.dropTarget` set plus the **one** session every input class
drives (rows SF-D1/D4/D5). The renderer builds one per surface automatically and
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
- Live geometry: `registry.refreshTargets()` re-resolves every target rect and
  re-runs the hover at the last pointer position. Call it in the same frame as a
  scroll write; the renderer already calls it after every re-solve.
- Reads: `registry.verdict` (a Readable of
  `{ targetId, overId, legal, reason, mode }`), `registry.heldSource` (a
  `Readable<string?>` naming the source path a live session is carrying — the
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
  sources/targets/watchers and disposes its signals, returning `core:counters()`
  to baseline. The renderer disposes the registry it built; a hand-built one is
  yours.

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

`LuauUI.touchGestures` — normalization and composition for the native `GuiObject`
touch events (roblox-native audit corrections §2). The engine *recognizes*
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

`LuauUI.spatial` — the **contract** for spatial data a normalized pointer event
may one day carry (ADR-0021). This is a seam, not a feature: no adapter produces
this data today, every event LuauUI currently delivers is flat, and the framework
makes no claim about headsets or world-space input. It exists so that adding
spatial input later is an adapter change rather than a change to every control.

The compatibility promise is the whole point. A pointer position is
`{ x, y, pointerType? }` and every handler reads `pos.x` / `pos.y`. Spatial data
is only ever **added beside** those fields, so a handler written today keeps
working unchanged; a handler that wants the third dimension asks for it.

```lua
-- an adapter would build this; a handler reads it (or ignores it)
local pos = LuauUI.spatial.extend({ x = 120, y = 44 }, {
    ray   = { origin = { x = 0, y = 2, z = 0 }, direction = { x = 0, y = 0, z = -1 } },
    hit   = { x = 0, y = 2, z = -5 },
    pose  = { position = { x = 0, y = 2, z = 0 } },
    handedness = "right",     -- left | right | unknown
    phase = "changed",        -- began | changed | ended | cancelled | none
    target = "GarageSurface", -- opaque; LuauUI forwards it and never interprets it
})

if not LuauUI.spatial.isFlat(pos) then
    local s = LuauUI.spatial.of(pos)   -- { hit?, ray?, pose?, handedness, phase, target?, distance? }
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
example above uses); `spatial.isFlat(pos)` is `true` for every event LuauUI
produces today; `spatial.describe(pos)` gives a one-line diagnostic.

The two vocabularies are frozen sets, published so an adapter and a consumer
agree on what a value may be: `spatial.PHASES` is
`{ began, changed, ended, cancelled, none }` and `spatial.HANDEDNESS` is
`{ left, right, unknown }`. `none` and `unknown` exist so a partial platform
event still normalizes to a well-formed value rather than a nil every consumer
has to guard.

The matching render-target half is `target_contract.FUTURE.surface`: a
`SurfaceGui` world target, **declared with its eleven unanswered questions and
not implemented**. See [`../extending/new-platform-mode.md`](../extending/new-platform-mode.md)
for the physical gate a support claim would have to pass first.

---

## Client entry points

Everything above hangs off the `LuauUI` table. These nine modules do not: they
are the code that touches Roblox `Instance`s, real input and real device facts,
so exporting them would put engine requires in the shared/server graph. A client
script requires each **directly**:

```lua
local screen_target = require(ReplicatedStorage.LuauUI.client.screen_target)
```

**This list is the contract** (ADR-0011, constitution §12). These nine are
public surface with the same compatibility promise as anything above; everything
else under `src/` is library-internal, and a consumer requiring one of those is
outside the boundary rule.

#### `client.screen_target`

`screen_target.new(opts?) -> RenderTargetAdapter` — the production `ScreenGui`
target. **One adapter per root**: its instance map and capture/cursor state are
adapter-scoped, so an adapter must never host two roots (ADR-0009). `destroyRoot`
releases the tree.

| Opt | Meaning |
|---|---|
| `style` | the compiled token style to paint from; default is Studio Neutral |
| `isReducedMotion` | **deprecated** (0.9.0, removed no earlier than 0.10.0): `() -> boolean`, consulted for engine-side motion. Still accepted, and now OR-ed with the fact the renderer pushes from the environment through `adapter.setReducedMotion` — so it can force reduced motion ON, never off. `billboard_target.new(opts.isReducedMotion)` forwards it and retires with it. |
| `parent` | host the root under this Instance instead of `PlayerGui` (the Edit-mode preview and any harness without a LocalPlayer) |
| `rootFactory` | `(screenId) -> { gui }` — swap only the ROOT container; everything below is target-agnostic flat rendering (this is how `billboard_target` is built) |
| `forceScrollFallback` | render `ScrollView` nodes as plain clip hosts with no engine scrolling — the A/B switch that exercises the fallback path deliberately |
| `forceDragFallback` | make `setDragDetector` answer nil so the raw pointer-capture path runs instead |
| `nativeStyle` | opt into native StyleSheet paint: `true` for the built-in Dark/Light model, or `{ model?, handle?, host?, theme?, transitions? }`. Absent or unsupported keeps the explicit-write path |
| `themePackage` | the installed `ThemePackage` whose chrome recipes decide decoration slots; the theme controller swaps it at runtime |

#### `client.billboard_target`

`billboard_target.new(opts) -> RenderTargetAdapter` — the same adapter with a
`BillboardGui` root, for a LuauUI surface in the world. `opts` is
`{ parent, adornee, canvas = { w, h } }` (all three required and asserted) plus
`studsOffset?`, `alwaysOnTop?`, `maxDistance?`, `style?`, `isReducedMotion?`.
Parent it under `PlayerGui` for input; anywhere else is display-only.
`billboard_target.canvasRect(canvas)` is the matching viewport rect to feed the
environment. It deliberately **removes** two optional adapter methods
(`setPointerHandlers`, `setTouchGestureHandlers`), which is the target contract's
own degrade mechanism — a billboard says honestly what it cannot do. One adapter
per billboard, same rule as above.

#### `client.roblox_env`

`roblox_env.bind(env) -> unbind` — populates and keeps live every engine-owned
fact on a `LuauUI.newEnvironment` (viewport, safe insets, topbar geometry,
keyboard occlusion, input preference and capabilities, display class,
accessibility preferences, locale). This is the one place allowed to read
`UserInputService`/`GuiService` facts. The unbind is yours to own.

#### `client.roblox_input`

`roblox_input.newSystem(core) -> ActionSystem` — the same interface as
`LuauUI.newActionSystem`, implemented over real `InputContext`/`InputAction`/
`InputBinding` instances, so the presenter runs unchanged on either. Arbitration
(priority and sinking) is the ENGINE's job here; this adapter never
re-implements it. Pass it to `newPresenter` in place of the headless system.

#### `client.roblox_resources`

`roblox_resources.bind(provider) -> unbind` — the transport for
`LuauUI.newResourceProvider`. It drains `provider.pendingRequests()` and fulfils
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
| `core` | **required whenever `selectBy` is given**: the paradigm subscription needs a scope. Optional otherwise |
| `theme` | initial theme name; default `package.style.defaultTheme` |
| `selectBy` | `{ touch = pkg, pointer = pkg, gamepad = pkg }` — profile-conditional package selection (ADR-0020 R7); the positional `package` is the default for any unmapped class |
| `selectBySettleSeconds` | how long a profile must hold before it counts as settled (default 0.25 s) |
| `selectBySettle` | the settle-timer seam, for tests |
| `facts` | explicit resolve facts; default is to read them from the environment |
| `overrides` | dotted metric paths, recorded as deliberate theme-independence |
| `rootGui` | the target's root, for an adapter that cannot report one |
| `host` | explicit sheet host (else ADR-0018's host policy) |
| `sheetModel` | a prebuilt sheet model (else one is derived from the package) |
| `nativeStyle` | the materializer seam (tests and tools inject it) |
| `forceFallback` | exercise the fallback paint path deliberately |
| `transitions` | opt into native paint transitions (default off) |
| `preflightFonts` | preload the package's fonts before committing (default true) |
| `calibrate` | `(keys) -> { [key]: number }`, the font-calibration seam |
| `fontFiles` | family → engine font file, for a package shipping its own faces |
| `warn` | where a one-off warning goes |

#### `client.edit_preview`

`edit_preview.start(LuauUI, opts) -> handle` — Studio Edit-mode preview: builds
its own core, environment and device profile, mounts a blueprint and draws a
labelled device frame around it. `opts` is
`{ parent, blueprint, profile?, style? }`, where `blueprint` may be a factory
`(LuauUI, core) -> Blueprint` so an entry can create its own signals. The handle
is `{ controller, profile, setProfile(name), refresh(), dispose() }`. Taking the
library table as a positional first argument is deliberate (constitution E-11):
dev tooling is injected like a composite so a plugin can hand in the game's own
library table. **Always `dispose()` before saving the place** — it disconnects
the heartbeat, disposes the controller and root, and destroys the decoration
`ScreenGui`; without it the preview furniture is saved into the place.

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
bus, never part of it: LuauUI still plays nothing, and nothing under `src/`
outside `src/client/` names a haptic symbol or requires this module (pinned by
`tests/haptics.spec.luau`). Every engine fact it rests on is recorded, with
sources, in `docs/research/2026-08-12-haptics-engine-facts.md`.

```lua
local haptics = require(ReplicatedStorage.LuauUI.client.haptics)
local hap = haptics.new({ enabled = playerSettings.haptics })
hap.bind(presenter)            -- the verbs with no engine hook
hap.attachButtons(screenGui)   -- the property route, for `activate`
```

`bind(presenter) -> unbind`, `attachButtons(root) -> detach`,
`setEnabled(on)`, `isEnabled()`, `support()`, `reprobe()`, `diagnostics()`,
`dispose()`. `opts` is `{ enabled?, now?, adjustIntervalSeconds?, parent? }` plus
four injection seams (`instanceNew`, `inputService`, `hapticService`, `enums`)
that exist so the whole adapter is provable headless.

**`HapticEffect`, never `HapticService:SetMotor`.** Roblox's own class reference
says the service "has been superseded by `HapticEffect` … For new work, use
`HapticEffect` instead", and `SetMotor`'s value range, persistence and zeroing
requirement are undocumented — a motor you cannot prove stops is a stuck-rumble
bug with no test.

**`activate` takes the property route.** `GuiButton.PressHapticEffect` is an
assignable reference the *engine* fires, so `attachButtons` hands one over to
every `GuiButton` under the root (now and later, via `DescendantAdded`) and this
module never calls `Play()` on it. `HoverHapticEffect` is deliberately left
unassigned. The bus subscription covers only the verbs with no engine hook.

**The map is total over the closed twelve**, and five map to nothing —
`activate` (the engine plays it), `arrive` (every chase settle; per-frame noise),
`cancel` (the absence of feedback *is* the signal), `dismiss` and `supersede`
(not player-caused). The silences are written out explicitly, so a thirteenth
verb would surface as a visible gap rather than a silent drop.

| Verb | Route | `HapticEffectType` |
|---|---|---|
| `activate` | property (`PressHapticEffect`) | `UIClick` |
| `select` · `pickup` · `commit` · `land` | bus | `UIClick` |
| `adjust` | bus, **rate-limited** (default 60 ms; coalescing *drops*) | `UIHover` |
| `reject` · `celebrate` | bus | `UINotification` |
| `arrive` · `cancel` · `dismiss` · `supersede` | — | *deliberately none* |

Effects are **pooled**, one per mapped verb plus one for the press property, and
never constructed per fire (Roblox documents a "fewer than 100 simultaneous
effects" budget). The enum is resolved defensively **by name** before anything is
constructed and **never falls back to `Custom`** — a `Custom` effect with no
waveform is a guaranteed silent no-op. If the client cannot create the class at
all (`support() == "absent"`) the attempt is made **once**, not per event.

**Every effect is `Stop()`ped *and* `Destroy()`ed** when it is released —
`setEnabled(false)`, `dispose()`, and the shared press effect's teardown. A pooled
effect is parented into the DataModel at construction, so dropping the Lua
reference ends nothing: before this was fixed, five toggles of a settings-screen
haptics switch left fifteen `HapticEffect` instances in `Workspace` while
`diagnostics().pooled` reported `0`. `pooled` and `decorated` are now **derived
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

**What is device-owed.** Roblox documents controllers on macOS 15+ as
unsupported, so this repository's dev machine can only prove "never throws".
Whether anything is *felt* on a gamepad, whether it is felt on a phone, and
whether the player's own haptics setting silences it (`UserGameSettings.Haptic-
Strength` is `RobloxScriptSecurity` on read — game code cannot see it) are three
open `PENDING_PHYSICAL` rows.

## Motion

### `motion`

`LuauUI.motion` — the motion authority (ADR-0022 Decision 1): all value motion in
one pure, engine-free place, stepped by an injectable clock. It contains no
`RunService`, no `os.clock` inside the solver, and no engine globals at all, which
is what makes every motion contract below assertable frame by frame in the
headless suite. The client binds `clock:step()` to `RunService.PreRender` at the
adapter edge; tests and benches script a clock.

**Authority.** Motion drives **signals** only. It never writes solver-owned
geometry (no `Size`, no per-frame re-solve) and never writes a native-sheet-owned
paint property. Downstream, a motion value reaches the screen through the
renderer's **presentation** channel (transform/transparency, ADR-0022 Decision 2)
or through any ordinary reactive binding — the authority audit must stay clean
while motion runs.

```lua
local motion = LuauUI.motion
local clock = motion.newClock(core, { motionPolicy = env:get("motionPolicy") })

local x = clock:spring(0, "object")        -- a Readable<number>, bindable anywhere
x:setTarget(240)                           -- interruptible: any frame, any target
x:onSettle(function() print("landed") end)

clock:step(dt)                             -- the client's PreRender shim calls this
```

#### `motion.newClock(core, opts?) -> clock`

`opts.now` is a `() -> number` (seconds, monotonic; defaults to `os.clock`) and
`opts.motionPolicy` is a `Readable<string>` — pass `env:get("motionPolicy")`, whose
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
  none. The instrument for a wedged clock, mirroring `core:lastError`.
- `clock:isReduced() -> boolean` — the live reading of `opts.motionPolicy`, so a
  caller that has to branch (a control choosing an instant snap for a collaborator
  it does not own) asks the clock rather than re-reading the environment.
- `clock:dispose()` / `clock:isDisposed()` — scope-owned (`scope:own(clock)`).
  Disposal releases every value the clock built, so core counters return to
  baseline across mount/reset churn.

#### `motion.registerClass(name, params)` and the class vocabulary

A **motion class** is a named `{ dampingRatio, response }` pair — `dampingRatio`
is overshoot (1.0 = critically damped), `response` is how quickly the value
reaches its target in seconds (**not** a duration: settle time emerges from the
physics). Four ship: `container` (1.0 / 0.35), `object` (1.0 / 0.28), `reward`
(0.7 / 0.18), `decay` (1.0 / 0.5).

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

#### `clock:spring(initial, className, opts?) -> MotionValue`

The returned value **is** a `Readable<number>` (the backing core signal itself,
augmented), so `core:observe(value, …)`, `use(value)` in a memo, and a bound
blueprint prop all work on it unchanged. `opts` accepts `eps` (settle epsilon,
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

Everything else is the spring contract: it IS a `Readable<number>`, `setTarget`
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
  aims it. `newProgressView`'s indeterminate shapes are the framework's own
  caller, at `kind = "informational"`.

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

```lua
local reveal = LuauUI.motion.newValueReveal({
    held = heldSignal,        -- true  -> the view paints `from`
    counting = countingSignal,-- true  -> the view paints the animator
    animator = coinCount,     -- optional: a clock:counter / clock:spring
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
