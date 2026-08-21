# 1. Core concepts

Read this chapter before writing any code. Each idea builds on the one before
it, and every term is defined the first time it appears.

## 1.1 Declarative UI

Most Roblox UI code is *imperative*: you create a `Frame`, set its `Position`,
listen for a click, and inside that listener you reach back out and change other
objects. As the screen grows, the number of "when this changes, remember to also
update that" rules grows faster, and they are easy to get wrong.

Facet is *declarative*. You write a function that returns a **description** of
what the screen should look like *right now*, given the current data. You never
mutate objects yourself. When the data changes, Facet compares the new
description to what is currently on screen and makes the minimum set of changes
needed. Your job is to answer one question — "given this data, what should the
screen be?" — and answer it as plain data.

A description is built from **constructors** on `Facet.UI`: `UI.Screen`,
`UI.VStack` (a vertical stack), `UI.Text`, `UI.Button`, and so on. Each returns a
small frozen table — nothing is created on screen yet. These descriptions are
called **blueprints** in the code (`src/blueprint.luau`).

```lua
local UI = Facet.UI
local screen = UI.Screen({
    id = "Menu",
    padding = 16,
    gap = 8,
    children = {
        UI.Text({ id = "Title", text = "Main Menu", textSize = 24 }),
        UI.Button({ id = "Play", label = "Play" }),
    },
})
```

That `screen` value is inert data. Turning it into something live is a separate
step (mounting — see [chapter 3](03-getting-started.md)).

### A description names the shape, not the numbers

Because a blueprint is a description, the interesting properties are *what the
control is*, not the arithmetic that gets it there. `UI.Button{ shape = "circle" }`
is the clearest case: it is the floating round "…" action, and you never compute a
diameter, a radius, or a square. The diameter is a theme metric
(`controls.button.height`), so a denser theme package shrinks every disc and a
pixel-art package snaps it onto its grid; the solver enforces the 1:1 box, so
giving one axis makes the other follow and giving neither uses the metric. A disc
holds exactly one mark — a semantic `icon`, or a `label` of up to three characters —
and a longer drawn label is refused when you construct the button, naming the rule
and the fix, rather than being quietly clipped on somebody's phone. `icon` is a
*meaning* (`"more"`, `"close"`, `"chevron.trailing"`), never an asset id: Facet
draws its own plain-ASCII glyph for that name so the button is legible under every
theme, a theme that ships art for the name paints the picture over it, and `label`
stays the button's real name for screen readers and ten-foot readouts.

```lua
UI.Button({ id = "More", label = "More actions", shape = "circle", icon = "more" })
```

The full rules — hit geometry, skinning, and how `UI.corners`/`UI.shadow` compose —
are in [the API reference](../reference/api.md#button).

### Stable identity

Every node can carry an `id`. Sibling nodes with the same parent must have
different ids; duplicate ids are a hard error. If you omit an `id`, Facet
generates a stable one from the node's class and position (for example
`Button#2`). Ids matter because they are how Facet recognizes "this is the same
button as last time, just with new text" versus "this is a brand-new button."

## 1.2 Two kinds of state: semantic vs. presentation

This distinction runs through the entire library, so it is worth being precise.

- **Semantic state** is the *meaning* of your interface — the facts a designer or
  a server would recognize: the player's coin balance, whether music is enabled,
  the list of tracks, which item is selected. It is data your game genuinely
  owns.

- **Presentation state** is *how the interface is currently displayed* — which
  button the keyboard cursor is on, whether the mouse is hovering a row, how far
  a list is scrolled, the pixel rectangle each element occupies. None of this is
  game data; it is a consequence of showing the semantic state on one particular
  device at one particular moment.

Facet keeps these strictly apart because they have different lifetimes and
different owners. Semantic state may come from the server and may need to be
saved. Presentation state is throwaway, belongs to one screen on one device, and
— critically — **must never be sent over the network** (more on that in
[chapter 6](06-client-server.md)).

## 1.3 The reactive runtime

You need semantic state to *change* — coins go up, a toggle flips — and you need
the screen to follow. Facet provides a small **reactive runtime** for this,
created with `Facet.newCore()`. The object it returns is called the **core**
(`src/core/custom.luau`). It gives you four building blocks:

- **Signal** — a container for a value that can change. `core:signal(0)` returns
  a signal starting at `0`. Read it with `signal:get()`, change it with
  `signal:set(5)`.

- **Memo** — a value *computed* from other signals or memos. You pass a function
  that receives a reader called `use`; anything you read through `use` becomes a
  dependency. `core:memo(function(use) return use(a) + use(b) end)` recomputes
  automatically whenever `a` or `b` changes, and *only* then. You read a memo with
  `memo:get()`; you cannot `set` it.

- **Observer** — a callback that runs when a signal or memo changes.
  `core:observe(source, function(newValue) ... end)` returns an unsubscribe
  function. Observers fire only when the value actually differs from what the
  observer last saw.

- **Effect** — like an observer, but its dependencies are discovered
  automatically (the same `use`-reader trick as a memo). `core:effect(function(use)
  ... end)` re-runs whenever anything it read changes.

Two runtime guarantees are worth knowing up front:

- **Transactions batch changes.** `core:transaction(function() ... end)` lets you
  change several signals and have dependents recompute and observers fire *once*,
  after the whole block, instead of after each individual `set`. This prevents an
  interface from briefly showing an inconsistent half-updated state.

- **Recomputation is glitch-free and pull-based.** When a signal changes, memos
  that depend on it are marked out-of-date but are only recomputed when actually
  read, and each recompute sees a fully consistent snapshot of its inputs. You do
  not need to reason about update ordering.

The core also detects and safely contains mistakes rather than crashing your
game: dependency cycles, writing to a signal from inside a memo, runaway
feedback loops, and errors thrown inside your callbacks are all caught and
recorded (readable via `core:lastError()`), and the update loop keeps running.

### Ownership and cleanup: scopes

Reactive things (observers, effects, signals) and other resources need to be
cleaned up when the screen or list row they belong to goes away. Facet handles
this with **scopes** (`core:scope("label")`). A scope owns resources; disposing
the scope disposes everything it owns, in reverse order, exactly once. You rarely
create scopes by hand for simple screens — the mounting and presentation layers
create and dispose them for you — but understanding that "a screen owns a scope,
and closing the screen disposes it" explains why Facet does not leak.

**A structural region hands you the scope for the thing it just made.** Both of
them do, and they are the same idea twice:

```lua
UI.ForEach{ items = rows, key = …, row = function(item, itemScope) … end }   -- the ROW's lifetime
UI.When{ condition = isOpen, thenView = function(branchScope) … end }        -- the PANEL's lifetime
```

Own a panel's timer, motion value or async handle on `branchScope` and it is
released the moment the panel closes — and every re-opening gets a *fresh* scope,
so nothing a closed panel held can come back with it. The alternative is to hoist
it to the enclosing screen scope, where it outlives the panel and has to be reset
by hand; that is the leak the second argument exists to remove, and it paints
nothing, so nothing on screen will ever tell you about it. Ignoring the argument
is still fine — plenty of panels own nothing.

## 1.4 The client-local runtime

**Everything described so far — the reactive core, the blueprints, layout,
navigation, and rendering — runs on each individual player's own machine (the
client).** There is no shared UI running on the server. When two players are in
the same game, each of their clients independently builds and displays its own
interface from whatever data that client has.

This is not an implementation detail you can ignore; it is the mental model.
"What does the screen look like?" is always a *local* computation. The same
blueprint on a phone and on a desktop produces different pixel rectangles because
the local device facts (screen size, input type) differ — and Facet computes
both locally, from the same description.

## 1.5 Server-authoritative, validated mutations

If the UI is client-local, where does trustworthy game data come from? The
**server owns the truth.** The player's real coin balance, their unlocked items,
the outcome of a purchase — these live on the server, because a client can be
tampered with and must never be trusted to declare its own rewards.

Facet's model for this has two directions:

- **Down (server → client):** the server sends **semantic state** to the client,
  which feeds it into a signal. The UI reads that signal like any other. Facet
  provides **replication adapters** (`Facet.replication`) that handle the
  bookkeeping of receiving these updates in order and recovering from dropped
  messages. Covered in [chapter 6](06-client-server.md).

- **Up (client → server):** the client never changes authoritative state
  directly. Instead it sends a **typed request** — "I would like to buy item X" —
  and the server validates it, decides, and (if it accepts) sends back new
  semantic state. Facet models this as a **mutation** with an explicit lifecycle:
  `idle → pending → confirmed` or `rejected`. A pending request on the client
  *never* means success; only the server's confirmation does.

You may show the *expected* result immediately for responsiveness (called
optimistic presentation) and then reconcile with what the server actually says —
also covered in chapter 6. The point for now: the client proposes, the server
disposes.

## 1.6 Design tokens

A **token** is a named design value — a color, a spacing size, a text size, a
corner radius — used instead of a raw number. Rather than writing "18-pixel gap"
in fifty places, you refer to a spacing token; change the token once and every
screen follows.

Facet's tokens live under `Facet.tokens`. `tokens.compile(schema)` takes a
game's design values, checks them for completeness and for adequate text
contrast, and returns a frozen, validated set. The library ships a built-in
default token set called **Studio Neutral** (`src/tokens/default_style.luau`) so
you get a polished, professional-looking interface with zero configuration. A
game can override it. Tokens and styling are the subject of
[chapter 5](05-styling.md).

## 1.7 Actions and input contexts

Here is a rule that surprises people: **Facet controls never listen for hardware
keys directly.** A button does not "know" it is activated by the Enter key or the
gamepad's A button or a screen tap. Instead there is one indirection layer.

- An **action** is a named *intent*: `"Activate"`, `"Navigate"`, `"Cancel"`.
- A **binding** maps a real device input to an action: the Enter key and gamepad
  A both bind to `"Activate"`.
- An **input context** is a named group of actions with a **priority** and a
  **sink** flag. When several contexts are bound to the same physical key, the
  highest-priority enabled context wins; if that context *sinks*, lower contexts
  never see the input.

This is the **action system** (`Facet.newActionSystem`, `src/input/actions.luau`).
Why the indirection? Three reasons:

1. **Every control works on every device automatically.** Because a control
   responds to the *intent* `"Activate"`, it works with keyboard, gamepad, and
   touch without the control author writing a single device check. This is one
   of **three adaptation axes** Facet holds together: the *layout* adapts to
   the screen (size classes, safe areas), the *input* adapts to the device
   (bindings and reachability), and the *interaction paradigm* adapts to how
   the player actually manipulates things — a mouse drags a row directly, a
   finger gets an Edit mode with grab handles, a gamepad gets focus-and-grab.
   Controls choose those affordances from the environment's **live
   interaction-class set** (everything the device can do right now — a
   handheld with a touchscreen *and* a gamepad offers both idioms at once),
   never from a single "current input type". Chapter 7 covers the whole story.
2. **Screens layer cleanly.** A pop-up dialog can put its input context at a
   higher priority that sinks navigation, so the menu behind it correctly stops
   responding while the dialog is open — without either screen knowing about the
   other.
3. **It mirrors the real engine.** On Roblox the client adapter maps this model
   one-to-one onto the engine's Input Action System, so the headless model and
   the real device behave identically.

One platform fact baked into the presenter: the **Escape key cannot be bound** —
Roblox permanently reserves it for its own menu. Close affordances are therefore
provided on screen (a tap-to-dismiss backdrop, a close button), and on gamepad
the B button is the bindable "cancel."

## 1.8 Focus and navigation

**Focus** is the presentation-state answer to "which control would a keyboard or
gamepad act on right now?" On a touchscreen you just tap; with a keyboard or
gamepad there is a moving cursor, and focus is where it sits.

Facet owns focus logically, in the **focus graph** (`src/focus/focus_graph.luau`),
independent of any engine. A **focus scope** is the set of focusable controls for
one screen, in navigation order. Scopes stack: opening a modal pushes a new scope
that *traps* focus (navigation cannot escape into the screen behind it) and
restores the previous focus when it closes.

Within a scope, navigation can be a simple ring (press down/up to move through a
flat list, wrapping at the ends) or organized into **navigation groups** — named
clusters each with an axis (`"vertical"` or `"horizontal"`), a wrap policy, and
rules for how focus crosses from one group to the next. Groups are what let a
grid or a sidebar-plus-content layout navigate the way a player expects.

Crucially, when the list of focusable controls changes (a row is added or
removed), focus does not silently vanish: it stays put if the focused control
survived, otherwise it moves to the nearest surviving neighbor, preferring the
following item.

## 1.9 Adapting a whole screen: you declare the content, not the layout

Three primitives adapt, at three different scales, and picking the right one is
most of the work:

| Scale | Primitive | What it decides | From what |
|---|---|---|---|
| one axis | `UI.AdaptiveStack` | should this stack run down or across? | a `Readable` **you** bind |
| one container | `UI.ViewThatFits` | which of these candidate layouts fits here? | the space **that container** received |
| a whole screen | `UI.Composition` | which arrangement, and which form of each region? | the box **it** received, on **both** axes |

The first two are enough for a toolbar or an action row. They are not enough for
a results screen, a summary, an inspector — any surface with a lot to say and a
priority order among it. Those screens have all historically been written the
same way: a hand-rolled ladder of viewport-height guesses ("if the screen is
shorter than 520, collapse the hero; shorter than 440, hide the callout"). That
ladder is wrong on the next device, every time, and it is wrong for a structural
reason — it re-derives the screen's box from the *viewport*, and a windowed pane,
a notched phone and an overscanned TV all lie about that.

`UI.Composition` replaces the ladder with a **declaration**. You write down what
the screen has to say:

```lua
UI.Composition{
    id = "Summary",
    arrangements = { "threeLane", "twoLane", "column" }, -- richest first
    groups = {
        { id = "ceremony", lane = "lead",  sizing = "hug",  place = "center" },
        { id = "facts",    lane = "main",  sizing = "fill", minWidth = 240 },
        { id = "next",     lane = "trail", sizing = "hug",  place = 0.66 },
    },
    children = {
        UI.Region{ id = "Headline", group = "ceremony", rank = 3, floor = { lines = 1 },
                   recover = "none",                              -- forms: richest first
                   children = { bigPlate, oneLineChip } },
        UI.Region{ id = "List", group = "facts", rank = 2, sizing = "fill",
                   mayScroll = true, floor = { lines = 2 }, children = { theList } },
        UI.Region{ id = "Actions", group = "next", rank = 1, floor = { targets = 2 },
                   recover = "none", children = { buttonRow, buttonColumn } },
        UI.Region{ id = "Tease", group = "next", rank = 9, mayDrop = true,
                   recover = "overflow", children = { twoLines, oneLine } },
    },
}
```

Six ideas, and that is the whole model:

- a **region** is one thing to say, and **its children are its forms**, richest
  first — the last is the smallest version you are willing to show;
- **`rank`** is adaptation priority, 1 = most important. Regions are declared in
  *reading* order; rank is a separate axis and only says who gives way first;
- a **group** is a set of regions that travel together and is the unit a lane
  holds. It hugs its content, or it `fill`s — and **exactly one group filling** is
  what makes the slack flow somewhere deliberate instead of pooling in a dead
  band;
- an **arrangement** is a list of lanes side by side; `column` is one lane holding
  everything, `threeLane` is three. The first that is *legal* wins, and the last
  is the fallback. A group that should be a **band** rather than a lane — a
  masthead, a caption, a footer — declares `span = "above"` or `"below"` instead
  of a `lane`, and is then the composition's full width, in that place, in *every*
  arrangement;
- a **floor** is content — `{ lines = 1 }`, `{ targets = 2 }` — never a pixel
  count, so it survives a theme swap, a bigger text size and a longer language;
- **nothing is ever squeezed.** A region takes a smaller form, or it leaves. It
  never renders as a sliver;
- **a lane with nothing in it is not there.** When every region in a lane resolves
  to nothing — empty, at rest, or dropped — the lane **collapses** and its width
  goes to the lane that fills. That is why `reserved` (hold this region's box so a
  finishing transient never moves its neighbours) takes a `Readable<boolean>` as
  well as `true`: bound to "can my schedule still produce a piece", it keeps the
  box still *between* pieces and lets the whole column go once there is nothing
  left to say. Half of that is yours — a form that paints a fixed box
  unconditionally is never empty, so put the box behind the same read.

When space runs out the framework steps regions down to their next form in
descending rank, and only when nothing can step down does it start dropping them,
still in descending rank. At most one region scrolls, and a second `mayScroll` is
a construction error rather than a layout outcome.

Two properties matter as much as the layout:

- **A rotation is a re-solve, not a rebuild.** Every form stays mounted and only
  rects change, so scroll offsets, focus and in-flight animations survive an
  arrangement change — the same promise `AdaptiveStack` makes about an axis flip,
  at screen scale. Forms that lost and regions that dropped are *hidden*, which
  is what takes them out of the focus ring.
- **You can ask why.** `controller.compositionAt(path)` returns the resolution:
  which arrangement won, which form each region resolved to, which regions
  dropped, and for every richer arrangement the rule it broke and by how much. An
  adaptive screen whose only evidence is a screenshot cannot be debugged; a
  screenshot cannot tell you the three-lane candidate lost the field lane's
  minimum width by six pixels.

The same decision is available with no screen at all — `Facet.composition.resolve`
takes a declaration, a box and a measure callback — so "does this survive a
landscape phone" is a unit test, not a device round.

#### Adapting without dead ends

Everything above decides **what to show**. This decides what happens to what it
stopped showing, and it is the half that used to be left to the author.

Two things can happen to a region: it steps DOWN to a poorer form, or it is
DROPPED. From the player's side those are one event — content this screen used to
have and does not — so a multi-form region must state where it went:

```lua
recover = "none"      -- every form still shows everything. A poorer LAYOUT, not less
recover = "self"      -- the reduced form is the route: ask it, where it stands
recover = "overflow"  -- the screen's overflow surface is the route (it reads resolution.unshown)
```

`recover` is **required** with more than one form and refused with one. Silence is
not consent: a declaration that says nothing is exactly the state this contract
exists to remove.

**The framework builds the `"self"` route for you.** A region standing on a form
below its richest gets one **expand** affordance, appended as its last child, and
it stands exactly while a reduced form stands:

The affordance is a **chevron**: a mark BESIDE the compact form, in width the
form's own measure reserved for it, with its own tap target at the standard floor
and its own focus stop **after** the form's own stops. It is never a surface over
the form. One gesture, one meaning — a compact form that already holds a button
has spoken for the tap, and a form that holds nothing keeps every pixel it painted.

> **It used to cover.** A form carrying no control of its own got a full-size
> activation surface instead, so the whole compact form was the target. A device
> round (2026-08-21) killed that: every stepped-down zone on the HUD demo rendered
> as an **empty pill**, and no headless instrument in this repository could see it
> — the model had a rect and `visible = true` for every one of those labels. What
> the framework had done was put its own instance on top of them, and "it is
> transparent, so it is harmless" is a claim about the ENGINE that nothing here
> makes or can make. The rule that replaced it is structural: **the framework
> puts nothing of its own above your content.**

The resolution still reports `formInteractive` — whether the standing form
contributes a focus stop or a semantic action — read off the class contract every
primitive declares its focus role and semantic actions in, never a list of class
names, plus the four classes whose *content* that registry cannot describe:
`UI.When`, `UI.ForEach` and `UI.ErrorBoundary` (their subtrees are produced lazily,
from a function) and `UI.Foreign` (an adopted engine instance whose own input still
works). **The framework will not call a form passive when it cannot see inside it.**
The fact is worth reading — it is what tells you whether the player has two things
to press in that box — even though both answers now get the same mark.

Activating it presents the region's **richest form** — the same blueprint, by
identity — in a transient plate at the region's own anchor, sized by the same
solve that chose the ladder rung. Where the richest form cannot meet its floor in
a plate, the identical content is presented as a full-width sheet instead. It
closes on a tap outside, on its own **Close** control (an icon chip carrying the
standard close mark; its accessibility name stays the word "Close"), on gamepad B,
and by itself when the box it was opened against moves, resizes or goes (a rotation, a viewport
change, a theme change, or a re-solve that put the region back at its richest
form).

The Close control is the framework's, not yours, and it is there because of the
platform fact above: **Escape cannot be bound**, and a plate that traps focus — as
it must, or its own contents are on nobody's ring — would otherwise have no
keyboard exit at all. It is the panel's last child, so focus on open lands on your
content's first control when form 1 has one, and on the way out when it does not.

You can turn it off — `expand = "none"` says there is nothing to disclose or that
you are disclosing it yourself — or replace it with a handler:

```lua
UI.Region{ id = "Clock", group = "top", rank = 2, recover = "overflow",
           expand = function() myOwnPanel() end,        -- or "none", or omit for "auto"
           children = { clockAndScores, clockOnly } }
```

**A region with one form never simplifies**, so `expand` is refused on one — and
that is also the answer to *"how do I stop this region collapsing?"*. `rank` and
the forms list are the whole collapse-customization surface. One form means one
representation, at every size, or the region drops whole.

**The minimum form must carry the region's essential value.** This is an authoring
rule the framework cannot check for you, and it is the one thing that makes the
expand honest. A ladder is a promise that each rung is still *worth reading*: a
round timer's last rung may lose its precision (`2m` for `2:14`) but not the fact
that a round is running; a scoreboard's last rung may lose the team names but not
the score. If the last rung drops the number the player actually needs, you have
moved a defect behind a tap — and no disclosure repairs that, because the player
has to know there is something to ask for before they will ask. **The expand is
for the rest**, never for the point.

Finally, the census: `resolution.unshown` is the framework's own list of what the
screen has stopped showing, in declaration order, with the route for each. Build
your overflow surface from it and it cannot drift — and use `expandable` beside it
to tell the two row types apart: a DROPPED region needs its content carried into
the sink (there is no form left to disclose from), while a SIMPLIFIED one only
needs a row that calls `presenter.expand(path)` and opens the plate the region
already has.

#### A HUD is a composition too

A game HUD looks like the opposite problem — clusters pinned to the screen's
corners with the world visible behind them, not a document that flows. It isn't.
The three screen **columns** are three lanes (lanes sit side by side and never
overlap, which is what stops two clusters from growing into each other), the
three vertical **bands** are the `place` a lane already spreads its groups by,
and the nine anchor names are the nine group ids. So the whole thing is data:

```lua
UI.Composition{
    id = "Hud",
    width = fill, height = fill,
    groups = Facet.composition.HUD_GROUPS,     -- the twelve groups, frozen
    arrangements = { Facet.composition.HUD },  -- one arrangement: three columns
    children = {
        UI.Region{ id = "Rounds", group = "topLeft", rank = 1, children = { wrappedStrip } },
        UI.Region{ id = "Tasks",  group = "left",   rank = 7, mayDrop = true,
                   recover = "self",     -- every reduced form is a Button that opens the rest
                   children = { panel, oneTask, chip } },
        UI.Region{ id = "Clock",  group = "top",     rank = 2, recover = "overflow",
                   children = { clockAndScore, clock } },   -- the scores go to the sink
        UI.Region{ id = "Rail",   group = "topRight", rank = 4, mayDrop = true,
                   recover = "overflow", children = { tallRail, onePill } },
        UI.Region{ id = "Actions", group = "bottomRight", rank = 3, recover = "overflow",
                   children = { column, oneButton } },
    },
}
```

`topLeft`, `left`, `bottomLeft`, `top`, `center`, `bottom`, `topRight`, `right`,
`bottomRight` — the same nine words the `anchor` box prop uses. Three things are
worth knowing:

- **The zones stay put.** Each column is a third of the box whatever is in it,
  so a round with nothing in the middle does not slide the right-hand cluster
  left. (That is what the `holdsLane` on each column group buys: it is the
  opposite of "a lane with nothing in it is not there", and a HUD wants the
  opposite, because its lane positions *are* its coordinate system.)
- **Losing height degrades, it does not collapse.** A browser URL bar opening
  takes ~67px off the box (measured against Chrome 151: a location-bar row is
  `outerHeight - innerHeight` on a popup window); the ladder above runs, in
  descending rank, and the least important zone in the column that ran out gives
  up its richest form and then leaves. Nothing lands on anything.
- **...and what it gave up is still reachable.** Every multi-form region states
  `recover`: `"none"` (the poorer form still shows everything), `"self"` (the
  poorer form is a control that opens the rest) or `"overflow"` (the screen's own
  disclosure surface carries it, reading `resolution.unshown`). It is **required**
  where it means something, because a ladder with no notion of where the content
  went makes "step down" and "delete" the same operation. Adaptation may change
  how much is shown and what it costs to reach; it may not change whether it can
  be reached at all.
- **A cluster your column cannot hold is reported.** `align` on those groups
  means each zone takes *its own* measured width inside its column, so a row of
  controls that cannot shrink to a third of a phone is visible rather than
  silently painted over its neighbour: `resolution.collisions` names the pair and
  the solver files a finding, which the always-on overflow sweep reads at every
  viewport.

The showcase's **Screen-anchored HUD** demo is exactly this, with a "URL bar"
switch so you can watch it happen.

For the coarse facts a screen sometimes still wants, `Facet.adaptive.conditions`
now classifies **both** axes (`sizeClass` / `heightClass`, plus `orientation`), so
no screen has to invent a height threshold of its own. They stay viewport-relative
and therefore coarse: when the answer must depend on the space a particular
container really got, measure it — that is what `UI.Composition` and
`UI.ViewThatFits` are for.

### Deciding who gives way when a row is too tight: `layoutPriority`, `shrinkWeight`

Before a row is *too long* it is merely *tight*, and something has to give. By
default Facet shrinks nothing — a child keeps its natural size — so a row that
does not fit simply overflows and the solver complains. Two props say what should
happen instead:

- **`layoutPriority`** is a **tier**: the lowest tier gives way first, the highest
  gives way last. Default `0`. Put the value on the thing that must survive
  ("keep the score, drop the subtitle").
- **`shrinkWeight`** is the **share within a tier**: `0` (the default) means "never
  shrinks", and a bigger number means "takes more of the squeeze than its
  neighbours". Two children at weight 1 and 3 give up a quarter and three quarters
  of the shortfall.

They compose: the tiers are consulted first, then the weights inside the tier that
is currently giving way.

```lua
UI.HStack{ id = "Row", children = {
    UI.Text{ id = "Name",  text = playerName, shrinkWeight = 3 },  -- squeezes most
    UI.Text{ id = "Note",  text = subtitle,   shrinkWeight = 1 },
    UI.Text{ id = "Score", text = score,      layoutPriority = 1 }, -- survives longest
} }
```

### Sizing against the container, not the parent: `containerRelativeFrame`

`width = { type = "percent", fraction = 0.5 }` is half of *the immediate parent's
offer*, which is rarely what a carousel wants. `UI.containerRelativeFrame(bp, …)`
measures against the nearest ancestor that owns a **viewport** — a `ScrollView`'s
content window, or the surface root — so a card can be "half the visible width"
however deeply it is nested:

```lua
UI.containerRelativeFrame(card, { axis = "horizontal", count = 2, span = 1, spacing = 8 })
```

That is the **paging** form: divide the container into `count` slots, take `span`
of them, and leave `spacing` px between. Two-up cards on a phone, four-up on a
desktop, from one declaration. The other form is **fractional** —
`{ axis, fraction }` — and you use exactly one of the two per call; declaring both,
or neither, is an error at the call site. (What it does *not* do is make the
scroller **land** on those slots — snapping is not shipped.)

### Lining columns up across rows: `UI.GridRow` and `gridSpan`

`UI.Grid` sizes each column to its widest cell across the whole grid, which is what
makes a table of stats line up without hand-picked widths. `UI.GridRow` is one row
of it, and `gridSpan` on a cell lets it cover more than one column — a title band
above a three-column stat block, say:

```lua
UI.Grid{ id = "Stats", children = {
    UI.GridRow{ id = "Head", children = { UI.Text{ id = "T", text = "Lap times", gridSpan = 3 } } },
    UI.GridRow{ id = "R1",   children = { lapCell, timeCell, deltaCell } },
} }
```

### Animating a state change: `presenter.withAnimation`

Normally a signal write repaints immediately. Wrap the write and the *movement it
causes* is interpolated instead:

```lua
presenter.withAnimation("container", function()
    expanded:set(true)
end)
```

**In plain terms:** you do not animate a property, you animate a *write*.
Everything whose **position** changes because of that write slides to its new
place under the named motion class instead of jumping. The class comes from the
registered set (`"container"`, `"object"`, `"decay"`, `"reward"`) — inline spring
numbers are deliberately a hard error, so motion stays a vocabulary rather than a
pile of magic constants. It animates *position*; a number that must count up
rather than jump is still a `MotionValue`.

### When a row is simply too long: `wrap`

The three primitives above all *choose*: a different axis, a different candidate,
a different arrangement. Sometimes there is nothing to choose — you have fourteen
tags, or nine filter chips, and they just do not fit across the screen. For that
there is one word:

```lua
UI.HStack{ id = "Tags", wrap = true, gap = 6, children = tags }
```

**In plain terms:** a normal `UI.HStack` is one line. It puts its children across,
side by side, and if they run past the edge they run past the edge — the row
paints outside its own box and the solver complains about it. With `wrap = true`
it behaves like a paragraph of text instead: it fills a line, and when the next
child will not fit it starts a **new line** underneath, as many times as it
needs. A `UI.VStack{ wrap = true }` does the same thing sideways — it fills a
column, then starts a new column beside it.

Three things follow, and none of them is a new idea to learn:

- **it adds no new words.** `align` still says where things sit on the cross axis
  — it just now moves the whole *block* of lines rather than one line. `lineAlign`
  on a child still says where that child sits inside its own line. `distribute`
  still spreads the leftover along the main axis, now per line. And one `gap`
  spaces both the children and the lines, exactly as Roblox's own `UIListLayout`
  does;
- **each line is as tall as its tallest child**, so a ragged row of chips does not
  reserve the tallest chip's height for every line;
- **it is a prop, not a class.** So you can *bind* it — `wrap = conditions.compact`
  wraps the row on a phone and keeps it on one line on a desktop, and the flip
  re-arranges the same nodes rather than rebuilding them. Nothing loses its focus,
  its scroll position or its in-flight animation.

One rule to know before you meet it: `align = "stretch"` is **refused** on a
wrapping stack. On a one-line stack it means "each child fills the line's cross
axis"; on a wrapping one it could just as easily mean "the lines grow to fill the
container", and a word that means two things is a bug waiting to be written. Put
`lineAlign = "stretch"` on the children that should fill their line instead.

If a single child is wider than the whole line it gets a line to itself and is
clamped to the line — and the solver says so on `controller.diagnostics()`, along
with the case where you have more lines than the box is tall. Wrapping removes
the main-axis overflow; it does not remove the need to have room.

### Listing a dictionary: `UI.sortedEntries`

`UI.ForEach` takes an array, so a map — player id → score, a settings table — has
to be flattened first. Write that flatten by hand and it is three obvious lines
that are quietly wrong:

```lua
local rows = {}
for id, score in scores do            -- DON'T: `pairs` order is not an order
    table.insert(rows, { key = id, value = score })
end
```

Luau's iteration order comes from the table's hash layout, and the hash layout
comes from **how the table was built** — what was inserted, in what order, and
what was deleted along the way. Two maps with identical contents iterate
differently. Your leaderboard ends up sorted by the order the players happened to
join, and it will look completely stable while you test it, because building the
same table the same way twice really does iterate the same way twice. The instant
a player leaves and rejoins, the rows move.

```lua
local rows = scope:own(core:memo(function(use)
    return UI.sortedEntries(use(scores))
end))
```

That is the same list, in the same order, whatever built the map. Keys sort
naturally (numbers before strings); pass a second argument to order them yourself
— `UI.sortedEntries(dict, function(a, b) return RANK[a] < RANK[b] end)` — and note
that the comparator gets **keys**, not entries, which is what makes the ordering
deterministic no matter what you pass. To rank by *value*, sort the array it
returns and break ties on the key.

### Promising a row's height: `newVirtualList` and `itemExtent`

A long list only builds the rows you can see. To do that it has to know, without
building anything, where row 700 will be — so it multiplies: row *i* sits at
`i × itemExtent`. That one number is what makes scrolling ten thousand rows cost
the same as scrolling ten, and it means **you** are promising how tall your row
is, for every player, on every screen.

The promise is easy to get wrong, because a row's real height moves with things
you did not type: how wide the window is, the player's text-size setting, the
theme's borders and padding, a display scale on a TV. Get it wrong by 8px and
nothing looks wrong on your machine — every row on somebody else's paints 8px
over the row beneath it, further down the list every time.

So the framework checks the promise. Every solve, it measures what you actually
put in the row and compares it with the extent you declared. If your content is
**taller** than its slot, `controller.diagnostics()` says so, in those words:

> newVirtualList 'Racers' declares itemExtent = 56, but this row's content
> measures 74px on the list's y axis — 18px taller than the slot it is windowed
> into…

Both numbers, and the row it happened on. Nothing is said when your row is
*shorter* than its slot: reserving a few px too many is the safe direction, and
plenty of lists do it on purpose. Nothing is said either for a cell that scrolls
or clips its own content, because that content is not going anywhere.

The fix is always to recompute `itemExtent` from the same facts your cell reads —
not to give the row a flexible height. A windowed list cannot use one: it has to
know where row 700 is without building it.

**When your rows genuinely are not all the same height** — a feed of posts with
different body lengths, a settings list with wrapped explanations — `itemExtent`
also takes a function:

```luau
itemExtent = function(item, index, use)
    return HEADER + item.lines * lineHeight(use(preferredTextOffset))
end,
```

Each item declares its own size, and the list adds them up once instead of
multiplying. It is still lazy in the way that matters: adding up numbers builds
nothing and measures nothing, so only the rows you can see are ever created.

The one thing to get right is `use`. It is the third argument, and it is how the
list learns that your extents depend on the player's text size: read the setting
through it and every row re-derives when the setting moves. Read it with `:get()`
instead and you get the right answer once and never again — and the list will
quietly window against heights that are no longer true. When the extents do move,
the list keeps the post that was under the top edge under the top edge, so
changing text size does not lose the player's place.

### Cards and rails: one card per swipe on a phone, a row of them on a desktop

A set of cards is the most-reached-for thing in a game menu — liveries, tracks,
loadouts — and it is the one arrangement whose *right answer changes with the
screen*. On a phone you want one card filling the view, with a sliver of the next
one showing so the player knows to swipe. On a tablet or a desktop you want four
of them side by side, because there is room and because scrolling past one card
at a time would be tedious. Written by hand that is a size branch in every screen
that shows cards, and the branch is where it goes stale.

Declare the *arrangement* instead of the width:

```luau
local rail = Facet.Controls.VirtualList(core, {
    id = "Liveries",
    axis = "x",                 -- a rail runs sideways
    rows = liveries,
    key = function(item) return item.id end,
    itemExtent = "cards",       -- how many belong in view, not how wide one is
    viewportExtent = railWidth, -- the space this rail actually got
    rowGap = 8,
    cell = function(item) return LiveryCard(item) end,
})
```

That is the whole difference. On a compact, touch-driven surface the rail
resolves **one card per view with a peek of the next**, and turns snapping on,
because a one-card view is a page. On anything larger it resolves a **multi-up
rail** with snapping off. Nothing above mentions a width, a breakpoint or a
device, and the same control changes its mind in place when the space does — a
rotation re-arranges it with no remount and no lost scroll position.

If you want to pin part of it, `cards` is the options table: `perView` fixes the
count, `minWidth` moves the width at which a lane is dropped, `peek` overrides
the sliver (`0` removes it). Anything you write there wins.

**A rail that adapts needs the facts, and says so if it cannot find them.** A screen
stood up with `Facet.client.host.new` publishes its environment for free, so the
snippet above is all you write there. Building one by hand — a test, a tool, a
bespoke bootstrap — means building the environment first
(`local env = Facet.newEnvironment(core)`), or passing `env` to the rail, or pinning
`cards = { perView = n }`, which asks for no facts at all. Leave all three out and
the rail refuses to construct and names which of them to add: adaptation is not
allowed to silently not happen.

**Snapping is its own key, and it works without cards.** `snap = "item"` on any
scrolling collection — a list, a rail, a grid on its scroll axis — means the
offset settles onto an item boundary when the gesture stops, instead of resting
wherever the momentum ran out:

```luau
snap = "item",  -- "none" is the default
```

A quick flick always advances at least one item in the direction it went, so a
short swipe cannot undo itself; a slow drag that did not clear an item's midpoint
falls back where it came from, so a half-swipe is a way to change your mind. The
end of the list is a resting place of its own, so the last card can sit flush
against the edge. Keyboard and gamepad traversal land on boundaries too, and so
does a programmatic `scrollTo`. If a player has turned reduced motion on, the
offset is *placed* rather than travelled — same landing place, no flight.

Two things snapping deliberately does **not** do. It never snaps while an item is
taller than the viewport: you cannot align something the player is still reading
past, so alignment gives way to content, the same way a long label reflows before
it truncates. And it costs nothing when nothing is happening — a snapping list
sitting still runs no per-frame work at all.

### Hiding something without moving everything else: `hidden`

There are two different meanings of "make this go away", and mixing them up is
the cause of a whole family of jumpy screens.

`UI.When` **removes** the node. It stops existing, so everything below it slides
up to fill the space — which is what you want for a panel that appears, a row
that is added, a warning that only shows sometimes.

`hidden = true` **keeps the node's box and stops drawing it**. The space is still
reserved; nothing else moves. That is what you want for a value that has not
arrived yet, a locked item you still want to leave a gap for, or a badge that
comes and goes on a row whose height must never change.

```lua
UI.Button{ id = "Badge", label = "New", hidden = notEarnedYet }
```

It is a normal prop, so you can bind it to a signal and flip it live. When it
flips, nothing is destroyed and nothing is rebuilt — the same button is there the
whole time, keeping its focus, its animation and its place.

A hidden node is genuinely inert, not just invisible: it is skipped by Tab and
gamepad navigation, and it does not respond to taps. That is deliberate — an
invisible thing you can still accidentally click is worse than either state on
its own.

### Knowing when something arrives and leaves: `onAppear` / `onDisappear`

Sometimes you need to *do* something the moment a piece of UI shows up or goes
away: start a countdown, log that a screen was opened, play a sound, stop a
sound. Every rendered node takes two optional callbacks for exactly that:

```lua
UI.Box{
    id = "Card",
    onAppear = function(path) startPreviewAnimation() end,
    onDisappear = function(path) stopPreviewAnimation() end,
}
```

**In plain terms:** `onAppear` runs once, the first time this node is actually
drawn. `onDisappear` runs once, right after it stops being drawn. Both are handed
the node's path, so one shared function can serve many nodes.

Three details worth knowing, because they are what make the pair safe to rely on:

- **`onAppear` runs after the layout is worked out**, so by the time your code
  runs the node already has its real size and position — you can ask
  `controller.rectOf(path)` and get an answer. Nothing has reached the player's
  screen yet either way;
- **`onDisappear` runs after the node is gone.** The path is no longer mounted, so
  do not try to read or write it; this hook is for *your* cleanup, not for a last
  look at the node;
- **closing the screen still fires `onDisappear`** for everything on it. That is
  the usual way a panel goes away, and a cleanup that only ran when a row scrolled
  out of view would be a leak waiting to happen.

`hidden` and these two are unrelated on purpose. Hiding a node fires nothing —
it never left. If you want an event, use `UI.When`, which really does remove it.

With these concepts in hand, [chapter 2](02-architecture.md) shows how the
modules fit together, or [chapter 3](03-getting-started.md) jumps straight to a
working screen.
