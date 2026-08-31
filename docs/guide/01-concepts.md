# 1. Core concepts

Read this chapter before writing any code. Each idea builds on the one before
it, and every term is defined the first time it appears.

## 1.1 Declarative UI

Most Roblox UI code is *imperative*. You create a `Frame`, set its `Position`,
and listen for a click. Inside that listener, you reach back out and change
other objects.

This creates "when this changes, remember to also update that" rules. As the
screen grows, the number of these rules grows even faster than the screen
does. They are easy to get wrong.

Facet is *declarative*. You write a function that returns a **description** of
what the screen should look like *right now*, given the current data. You
never mutate objects yourself. When the data changes, Facet compares the new
description to what is on screen now. It makes the minimum set of changes
needed. Your job is to answer one question: "given this data, what should the
screen be?" You answer it as plain data.

A description is built from **constructors** on `Facet.UI`: `UI.Screen`,
`UI.VStack` (a vertical stack), `UI.Text`, `UI.Button`, and so on. Each returns a
small frozen table — nothing is created on screen yet. These descriptions are
called **blueprints** in the code (`src/blueprint.luau`).

```lua
local UI = Facet.UI
local screen = UI.Screen({
    id = "Menu",
    padding = "m",
    gap = "s",
    children = {
        UI.Text({ id = "Title", text = "Main Menu", textSize = "title" }),
        UI.Button({ id = "Play", label = "Play" }),
    },
})
```

`padding` and `gap` take a theme spacing token: `"xs"`, `"s"`, `"m"`, `"l"`, or
`"xl"`. These resolve to 4, 8, 16, 24 and 40 pixels under the default theme.

`textSize` takes a typography role the same way. `"title"` names a rung on the
reading ladder, from `caption` up to `title`. A `Text` with no size set draws
at `body`. `body` already follows the player's preferred text size.

A plain number is legal in any of these places, and it stays exactly that
number. It will not follow a theme swap or the player's text setting, and it
will not grow on a television.

That `screen` value is inert data. Turning it into something live is a
separate step (mounting — see [chapter 3](03-getting-started.md)).

### A description names the shape, not the numbers

Because a blueprint is a description, it names *what the control is*, not the
arithmetic that draws it. `UI.Button{ shape = "circle" }` is the clearest
case. It is the floating round "…" action. You never compute a diameter, a
radius, or a square.

The diameter is a theme metric (`controls.button.height`). A denser theme
package shrinks every disc, and a pixel-art package snaps it onto its grid.
The solver enforces a 1:1 box: giving one axis makes the other follow, and
giving neither uses the metric.

A disc holds exactly one mark: a semantic `icon`, or a `label` of up to three
characters. A longer drawn label is refused when you construct the button.
This names the rule and the fix up front, instead of quietly clipping the
label on somebody's phone.

`icon` is a *meaning* — `"more"`, `"close"`, `"chevron.trailing"` — never an
asset id. Facet draws its own plain-ASCII glyph for that name, so the button
stays legible under every theme. A theme that ships art for the name paints
that picture over the glyph. `label` stays the button's real name for screen
readers and ten-foot readouts.

```lua
UI.Button({ id = "More", label = "More actions", shape = "circle", icon = "more" })
```

The full rules — hit geometry, skinning, and how `UI.corners`/`UI.shadow` compose —
are in [the API reference](../reference/api.md#button).

### Stable identity

Every node can carry an `id`. Sibling nodes with the same parent must have
different ids. Duplicate ids are a hard error. If you omit an `id`, Facet
generates a stable one from the node's class and position (for example
`Button#2`). Ids matter because they are how Facet recognizes "this is the same
button as last time, just with new text" versus "this is a brand-new button."

## 1.2 Two kinds of state: semantic vs. presentation

This distinction runs through the entire library. Understanding it matters.

- **Semantic state** is the *meaning* of your interface: the facts a designer
  or a server would recognize. Examples: the player's coin balance, whether
  music is enabled, the list of tracks, and which item is selected. It is
  data your game genuinely owns.

- **Presentation state** is *how the interface is currently displayed*.
  Examples: which button the keyboard cursor is on, whether the mouse is
  hovering a row, how far a list is scrolled, and the pixel rectangle each
  element occupies. None of this is game data. It is a side effect of showing
  the semantic state on one device at one moment.

Facet keeps these strictly apart because they have different lifetimes and
different owners. Semantic state may come from the server and may need to be
saved. Presentation state is throwaway. It belongs to one screen on one
device. **It must never be sent over the network** (more in
[chapter 6](06-client-server.md)).

## 1.3 The reactive runtime

You need semantic state to *change*: coins go up, a toggle flips. You also
need the screen to follow. Facet provides a small **reactive runtime** for
this, created with `Facet.newCore()`. The object it returns is called the
**core** (`src/core/custom.luau`). It gives you four building blocks:

- **Signal** — a container for a value that can change. `core:signal(0)` returns
  a signal starting at `0`. Read it with `signal:get()`. Change it with
  `signal:set(5)`.

- **Memo** — a value *computed* from other signals or memos. You pass a function
  that receives a reader called `use`. Anything you read through `use` becomes a
  dependency. `core:memo(function(use) return use(a) + use(b) end)` recomputes
  automatically whenever `a` or `b` changes, and *only* then. You read a memo with
  `memo:get()`. You cannot `set` it.

- **Observer** — a callback that runs when a signal or memo changes.
  `core:observe(source, function(newValue) ... end)` returns an unsubscribe
  function. Observers fire only when the value actually differs from what the
  observer last saw.

- **Effect** — like an observer, but its dependencies are discovered
  automatically (the same `use`-reader trick as a memo). `core:effect(function(use)
  ... end)` re-runs whenever anything it read changes.

Facet gives two runtime guarantees:

- **Transactions batch changes.** `core:transaction(function() ... end)` lets you
  change several signals at once. Dependents recompute and observers fire *once*,
  after the whole block ends, instead of after each individual `set`. This
  prevents an interface from briefly showing an inconsistent, half-updated state.

- **Recomputation is glitch-free and pull-based.** When a signal changes, Facet
  marks dependent memos out-of-date. It recomputes a memo only when you actually
  read it, and each recompute sees a fully consistent snapshot of its inputs. You
  do not need to reason about update ordering.

The core also detects and safely contains mistakes, instead of crashing your
game. It catches:

- dependency cycles
- writing to a signal from inside a memo
- runaway feedback loops
- errors thrown inside your callbacks

You can read the last one with `core:lastError()`. The update loop keeps
running.

### Ownership and cleanup: scopes

Reactive things — observers, effects, signals — and other resources need
cleanup when the screen or list row they belong to goes away. Facet handles
this with **scopes** (`core:scope("label")`). A scope owns resources.
Disposing the scope disposes everything it owns, in reverse order, exactly
once. You rarely create scopes by hand for simple screens. The mounting and
presentation layers create and dispose them for you. Remember this rule: a
screen owns a scope, and closing the screen disposes it. That is why Facet
does not leak.

**A structural region hands you the scope for the thing it just made.** Both of
them do, and they are the same idea twice:

```lua
UI.ForEach{ items = rows, key = …, row = function(item, itemScope) … end }   -- the ROW's lifetime
UI.When{ condition = isOpen, thenView = function(branchScope) … end }        -- the PANEL's lifetime
```

Own a panel's timer, motion value, or async handle on `branchScope`. It is
released the moment the panel closes. Every re-opening gets a *fresh* scope,
so nothing a closed panel held can come back with it.

The alternative is to hoist that ownership to the enclosing screen scope
instead. There it outlives the panel, and you have to reset it by hand. That
manual reset is exactly the leak the second argument exists to remove. A leak
like this paints nothing, so nothing on screen will ever tell you it
happened.

Ignoring the argument is still fine — plenty of panels own nothing.

## 1.4 The client-local runtime

**Everything described so far — the reactive core, the blueprints, layout,
navigation, and rendering — runs on each individual player's own machine (the
client).** There is no shared UI running on the server. When two players are in
the same game, each of their clients independently builds and displays its own
interface from whatever data that client has.

This is not an implementation detail you can ignore. It is the mental model.
"What does the screen look like?" is always a *local* computation. The same
blueprint produces different pixel rectangles on a phone and a desktop. The
reason: local device facts, like screen size and input type, differ. Facet
computes both locally, from the same description.

## 1.5 Server-authoritative, validated mutations

If the UI is client-local, where does trustworthy game data come from? The
**server owns the truth.** These live on the server: the player's real coin
balance, their unlocked items, the outcome of a purchase. A client can be
tampered with. Never trust a client to declare its own rewards.

Facet's model for this has two directions:

- **Down (server → client):** the server sends **semantic state** to the
  client. The client feeds it into a signal, and the UI reads that signal
  like any other. Facet provides **replication adapters** (`Facet.replication`)
  that receive these updates in order and recover from dropped messages.
  Covered in [chapter 6](06-client-server.md).

- **Up (client → server):** the client never changes authoritative state
  directly. Instead, it sends a **typed request** — "I would like to buy item
  X." The server validates the request, decides, and, if it accepts, sends
  back new semantic state. Facet models this as a **mutation** with an
  explicit lifecycle: `idle → pending → confirmed` or `rejected`. A pending
  request on the client *never* means success. Only the server's confirmation
  does.

For responsiveness, you may show the *expected* result immediately. This is
called optimistic presentation. You then reconcile it with what the server
actually says — also covered in chapter 6. The point for now: the client
proposes, the server disposes.

## 1.6 Design tokens

A **token** is a named design value — a color, a spacing size, a text size, a
corner radius — used instead of a raw number. Rather than writing "18-pixel
gap" in fifty places, you refer to a spacing token. Change the token once, and
every screen follows.

Facet's tokens live under `Facet.tokens`. `tokens.compile(schema)` takes a
game's design values. It checks them for completeness and for adequate text
contrast. It returns a frozen, validated set. The library ships a built-in
default token set called **Studio Neutral** (`src/tokens/default_style.luau`),
so you get a polished, professional-looking interface with zero configuration.
A game can override it. Tokens and styling are the subject of
[chapter 5](05-styling.md).

## 1.7 Actions and input contexts

**Facet controls never listen for hardware keys directly.** A button does not
"know" it is activated by the Enter key, the gamepad's A button, or a screen
tap. Instead, there is one indirection layer.

- An **action** is a named *intent*: `"Activate"`, `"Navigate"`, `"Cancel"`.
- A **binding** maps a real device input to an action: the Enter key and gamepad
  A both bind to `"Activate"`.
- An **input context** is a named group of actions with a **priority** and a
  **sink** flag. When several contexts are bound to the same physical key, the
  highest-priority enabled context wins. If that context *sinks*, lower
  contexts never see the input.

This is the **action system** (`Facet.newActionSystem`, `src/input/actions.luau`).
Why the indirection? Three reasons:

1. **Every control works on every device automatically.** A control responds
   to the *intent* `"Activate"`, so it works with keyboard, gamepad, and touch.
   The control author never writes a single device check.

   This is one of Facet's **three adaptation axes**:
   - *layout* adapts to the screen (size classes, safe areas).
   - *input* adapts to the device (bindings and reachability).
   - *interaction paradigm* adapts to how the player actually manipulates
     things: a mouse drags a row directly, a finger gets an Edit mode with
     grab handles, a gamepad gets focus-and-grab.

   Controls choose those affordances from the environment's **live
   interaction-class set** — everything the device can do right now. A
   handheld with a touchscreen *and* a gamepad offers both idioms at once.
   Controls never choose from a single "current input type". Chapter 7
   covers the whole story.
2. **Screens layer cleanly.** A pop-up dialog can put its input context at a
   higher priority that sinks navigation. This stops the menu behind it from
   responding while the dialog is open. Neither screen needs to know about the
   other.
3. **It mirrors the real engine.** On Roblox the client adapter maps this model
   one-to-one onto the engine's Input Action System, so the headless model and
   the real device behave identically.

One platform fact baked into the presenter: the **Escape key cannot be
bound**. Roblox permanently reserves it for its own menu. Facet provides
close affordances on screen instead: a tap-to-dismiss backdrop, a close
button. On gamepad, the B button is the bindable "cancel."

## 1.8 Focus and navigation

**Focus** is the presentation-state answer to one question: "which control
would a keyboard or gamepad act on right now?" On a touchscreen, you just tap.
With a keyboard or gamepad, there is a moving cursor, and focus is where it
sits.

Facet owns focus logically, in the **focus graph** (`src/focus/focus_graph.luau`),
independent of any engine. A **focus scope** is the set of focusable controls for
one screen, in navigation order. Scopes stack. Opening a modal pushes a new
scope that *traps* focus, so navigation cannot escape into the screen behind
it. Closing the modal restores the previous focus.

Within a scope, navigation can work two ways. It can be a simple ring: press
down/up to move through a flat list, wrapping at the ends. Or it can be
organized into **navigation groups** — named clusters, each with an axis
(`"vertical"` or `"horizontal"`) and a wrap policy. Rules govern how focus
crosses from one group to the next. Groups let a grid or a
sidebar-plus-content layout navigate the way a player expects.

When the list of focusable controls changes — a row is added or removed —
focus does not silently vanish. It stays put if the focused control survived.
Otherwise, it moves to the nearest surviving neighbor, preferring the
following item.

## 1.9 Adapting a whole screen: you declare the content, not the layout

Three primitives adapt, at three different scales, and picking the right one is
most of the work:

| Scale | Primitive | What it decides | From what |
|---|---|---|---|
| one axis | `UI.AdaptiveStack` | should this stack run down or across? | a `Readable` **you** bind |
| one container | `UI.ViewThatFits` | which of these candidate layouts fits here? | the space **that container** received |
| a whole screen | `UI.Composition` | which arrangement, and which form of each region? | the box **it** received, on **both** axes |

The first two are enough for a toolbar or an action row. They are not enough
for a results screen, a summary, or an inspector — any surface with a lot to
say and a priority order among it.

Screens like that have all historically been written the same way: a
hand-rolled ladder of viewport-height guesses. For example: "if the screen is
shorter than 520, collapse the hero; shorter than 440, hide the callout."
That ladder is wrong on the next device, every time. The reason is structural: it re-derives
the screen's box from the *viewport*, and a windowed pane, a notched phone,
and an overscanned TV all lie about that.

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

- A **region** is one thing to say. **Its children are its forms**, richest
  first. The last form is the smallest version you are willing to show.
- **`rank`** is adaptation priority: 1 means most important. Regions are
  declared in *reading* order. Rank is a separate axis, and it only says who
  gives way first.
- A **group** is a set of regions that travel together. It is the unit a lane
  holds. A group either hugs its content or it `fill`s. **Exactly one group
  filling** is what sends the slack somewhere deliberate, instead of letting
  it pool in a dead band.
- An **arrangement** is a list of lanes side by side. `column` is one lane
  holding everything; `threeLane` is three. The first legal arrangement wins,
  and the last is the fallback. A group that should be a **band** rather than
  a lane — a masthead, a caption, a footer — declares `span = "above"` or
  `"below"` instead of a `lane`. That group then spans the composition's full
  width, in that place, in *every* arrangement.
- A **floor** is content, never a pixel count — for example `{ lines = 1 }`
  or `{ targets = 2 }`. This lets it survive a theme swap, a bigger text
  size, and a longer language.
- **Nothing is ever squeezed.** A region takes a smaller form, or it leaves.
  It never renders as a sliver.
- **A lane with nothing in it is not there.** When every region in a lane
  resolves to nothing — empty, at rest, or dropped — the lane **collapses**,
  and its width goes to the lane that fills. This is why `reserved` takes a
  `Readable<boolean>` as well as `true`. `reserved` holds this region's box so
  a finishing transient never moves its neighbours. Bind it to "can my
  schedule still produce a piece." It then keeps the box still *between*
  pieces. It lets the whole column go once there is nothing left to say.
  Half of that guarantee is yours: a form that paints a fixed box
  unconditionally is never empty, so put the box behind that same read.

When space runs out, the framework steps regions down to their next form, in
descending rank order. Only when nothing can step down further does it start
dropping regions — again in descending rank. At most one region scrolls. A
second `mayScroll` is a construction error, not a layout outcome.

Two properties matter as much as the layout:

- **A rotation is a re-solve, not a rebuild.** Every form stays mounted; only
  rects change. Scroll offsets, focus, and in-flight animations all survive
  an arrangement change — the same promise `AdaptiveStack` makes about an
  axis flip, at screen scale. Forms that lost, and regions that dropped, are
  *hidden*. That is what takes them out of the focus ring.
- **You can ask why.** `controller.compositionAt(path)` returns the
  resolution. It reports which arrangement won, which form each region
  resolved to, and which regions dropped. For every richer arrangement, it
  also reports the rule that arrangement broke, and by how much. An adaptive
  screen whose only evidence is a screenshot cannot be debugged. A screenshot
  cannot tell you that the three-lane candidate lost the field lane's minimum
  width by six pixels.

The same decision is available with no screen at all. `Facet.composition.resolve`
takes a declaration, a box, and a measure callback. This turns "does this
survive a landscape phone" into a unit test, not a device round.

#### Adapting without dead ends

Everything above decides **what to show**. This section decides what happens
to what it stopped showing. That is the half that used to be left to the
author.

Two things can happen to a region: it steps DOWN to a poorer form, or it is
DROPPED. From the player's side, those are one event — content this screen
used to have and does not — so a multi-form region must state where it went:

```lua
recover = "none"      -- every form still shows everything. A poorer LAYOUT, not less
recover = "self"      -- the reduced form is the route: ask it, where it stands
recover = "overflow"  -- the screen's overflow surface is the route (it reads resolution.unshown)
```

`recover` is **required** with more than one form and refused with one. Silence is
not consent: a declaration that says nothing is exactly the state this contract
exists to remove.

**The framework builds the `"self"` route for you.** A region standing on a
form below its richest gets one **expand** affordance, appended as its last
child. That affordance stands exactly while a reduced form stands:

Its shape is the forms' own answer. Take a compact form that carries **no**
control of its own: that whole form IS the affordance. The whole pill is the
target, at the standard tap floor, with one focus stop and **no arrow drawn
anywhere**.

Now take a compact form that already holds a button. That button has already
claimed the tap, so it keeps its meaning. Here, the affordance becomes a
**chevron** beside it, in a width the form's own measure reserves.

One gesture, one meaning. The arrow exists exactly for that disambiguation,
and nowhere else.

> **The framework puts nothing of its own above your content.** A device run
> paid for that rule. A cover laid OVER the compact form once rendered every
> stepped-down zone on the HUD demo as an **empty pill**. No headless
> instrument in this repository could see the bug. The model reported a
> correct rect and `visible = true` for every one of those labels. The claim
> "it is transparent, so it is harmless" is about the ENGINE — and nothing
> here can make that claim or check it.
>
> The cover now obeys the rule, instead of being an exception to it. It is
> declared with `zIndex = -1`, so it paints **under** every form. The
> framework only synthesizes it where nothing above it is interactive. That is
> why the gesture still reaches it: a Facet node that is not interactive is
> not an `Active` GuiObject, and it is the GuiButton that sinks.

The resolution still reports `formInteractive`: whether the standing form
contributes a focus stop or a semantic action. This is read off the class
contract — every primitive declares its focus role and semantic actions
there, never through a list of class names.

Four classes have content that registry cannot describe: `UI.When`,
`UI.ForEach`, and `UI.ErrorBoundary` (their subtrees are produced lazily, from
a function), and `UI.Foreign` (an adopted engine instance whose own input
still works). **The framework will not call a form passive when it cannot see
inside it.**

The `formInteractive` fact is still worth reading. It tells you whether the
player has two things to press in that box — even though, for these four
classes, both answers now get the same mark.

Activating it presents the region's **richest form** — the same blueprint, by
identity — in a transient plate at the region's own anchor. That plate is
sized by the same solve that chose the ladder rung. Where the richest form
cannot meet its floor in a plate, Facet presents the identical content as a
full-width sheet instead.

The plate or sheet closes in any of these ways:
- a tap outside it.
- its own **Close** control (the corner disc below, which carries the
  standard close mark; its accessibility name stays the word "Close").
- gamepad B.
- on its own, when the box it was opened against moves, resizes, or goes
  away. This can happen from a rotation, a viewport change, a theme change,
  or a re-solve that puts the region back at its richest form.

The Close control belongs to the framework, not to you. It exists because of
the platform fact above: **Escape cannot be bound**. A plate that traps focus
— as it must, or its own contents are on nobody's ring — would otherwise have
no keyboard exit at all.

It is a circular icon button on the plate's top-right corner, half on and
half off it. It never covers your content: the plate's right padding is the
disc's own metric, so the content box ends exactly where the disc begins. It
is the panel's last child, so focus on open lands on your content's first
control when form 1 has one. It lands on the way out when form 1 does not.

You can turn it off. `expand = "none"` says there is nothing to disclose, or
that you are disclosing it yourself. Or you can replace it with a handler:

```lua
UI.Region{ id = "Clock", group = "top", rank = 2, recover = "overflow",
           expand = function() myOwnPanel() end,        -- or "none", or omit for "auto"
           children = { clockAndScores, clockOnly } }
```

**A region with one form never simplifies**, so `expand` is refused on a
single-form region. That is also the answer to *"how do I stop this region
collapsing?"* `rank` and the forms list are the whole collapse-customization
surface. One form means one representation at every size, or the region
drops whole.

**The minimum form must carry the region's essential value.** This is an
authoring rule; the framework cannot check it for you. It is the one thing
that makes the expand honest.

A ladder is a promise that each rung is still *worth reading*. For example: a
round timer's last rung may lose its precision (`2m` for `2:14`), but not the
fact that a round is running. A scoreboard's last rung may lose the team
names, but not the score.

If the last rung drops the number the player actually needs, you have moved a
defect behind a tap. No disclosure repairs that, because the player must
already know there is something to ask for, before they will ask. **The
expand is for the rest**, never for the point.

Finally, the census. `resolution.unshown` is the framework's own list of what
the screen has stopped showing, in declaration order, with the route for
each. Build your overflow surface from it, and it cannot drift.

Use `expandable` beside it to tell the two row types apart. A DROPPED region
needs its content carried into the sink — there is no form left to disclose
from. A SIMPLIFIED region only needs a row that calls `presenter.expand(path)`,
which opens the plate the region already has.

#### A HUD is a composition too

A game HUD looks like the opposite problem: clusters pinned to the screen's
corners, with the world visible behind them, not a document that flows. It
isn't.

The three screen **columns** are three lanes. Lanes sit side by side and
never overlap — that is what stops two clusters from growing into each other.
The three vertical **bands** are the `place` a lane already spreads its
groups by. The nine anchor names are the nine group ids. So the whole thing
is data:

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
`bottomRight` — the same nine words the `anchor` box prop uses. Three facts
matter:

- **The zones stay put.** Each column is a third of the box, whatever is in
  it. So a round with nothing in the middle does not slide the right-hand
  cluster left. This is what `holdsLane` buys, on each column group. It is
  the opposite of "a lane with nothing in it is not there." A HUD wants that
  opposite, because its lane positions *are* its coordinate system.
- **Losing height degrades; it does not collapse.** A browser URL bar opening
  takes ~67px off the box. (Measured against Chrome 151: a location-bar row
  equals `outerHeight - innerHeight` on a popup window.) The ladder above
  runs, in descending rank. The least important zone, in the column that ran
  out of space, gives up its richest form and then leaves. Nothing lands on
  anything.
- **...and what it gave up is still reachable.** Every multi-form region
  states `recover`: `"none"` (the poorer form still shows everything),
  `"self"` (the poorer form is a control that opens the rest), or
  `"overflow"` (the screen's own disclosure surface carries it, reading
  `resolution.unshown`). This is **required** wherever it means something. A
  ladder with no notion of where the content went makes "step down" and
  "delete" the same operation. Adaptation may change how much is shown, and
  what it costs to reach. It may not change whether the content can be
  reached at all.
- **A cluster your column cannot hold is reported.** `align` on those groups
  means each zone takes *its own* measured width inside its column. So a row
  of controls that cannot shrink to a third of a phone stays visible, instead
  of being silently painted over its neighbour. `resolution.collisions` names
  the pair, and the solver files a finding. The always-on overflow sweep
  reads that finding at every viewport.

The showcase's **Screen-anchored HUD** demo is exactly this, with a "URL bar"
switch so you can watch it happen.

Sometimes a screen still wants coarse facts. `Facet.adaptive.conditions` now
classifies **both** axes: `sizeClass` / `heightClass`, plus `orientation`. No
screen has to invent its own height threshold. These stay viewport-relative,
and therefore coarse. When the answer must depend on the space a particular
container really got, measure it instead — that is what `UI.Composition` and
`UI.ViewThatFits` are for.

Those three primitives, plus `conditions`, are the whole adaptation model.
They solve individual problems: a row that is too tight, a card that should
be half the visible width, a list that has to scroll cheaply. Each problem
has a short recipe in [chapter 15](15-adaptive-recipes.md).

With these concepts in hand, [chapter 2](02-architecture.md) shows how the
modules fit together, or [chapter 3](03-getting-started.md) jumps straight to a
working screen.
