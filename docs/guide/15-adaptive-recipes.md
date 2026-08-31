# 15. Adaptive layout recipes

Ten small problems that come up once a screen has to work on more than one
device, each with the Facet answer and a snippet you can paste.

This chapter is a reference, not a lesson. Read
[chapter 1 §1.9](01-concepts.md#19-adapting-a-whole-screen-you-declare-the-content-not-the-layout)
first: it explains how adaptation works and which of the three primitives to
reach for. Come here when you have a specific problem from the list below.

| Problem | Recipe |
|---|---|
| a row is tight and something has to give | [§15.1](#151-deciding-who-gives-way-when-a-row-is-too-tight-layoutpriority-shrinkweight) |
| a card should be a fraction of the visible width | [§15.2](#152-sizing-against-the-container-not-the-parent-containerrelativeframe) |
| columns should line up across rows | [§15.3](#153-lining-columns-up-across-rows-uigridrow-and-gridspan) |
| a state change should animate | [§15.4](#154-animating-a-state-change-presenterwithanimation) |
| a row is simply too long | [§15.5](#155-when-a-row-is-simply-too-long-wrap) |
| the data is a dictionary, not an array | [§15.6](#156-listing-a-dictionary-uisortedentries) |
| a long list needs to scroll cheaply | [§15.7](#157-promising-a-rows-height-newvirtuallist-and-itemextent) |
| one card per swipe on a phone, a row on a desktop | [§15.8](#158-cards-and-rails-one-card-per-swipe-on-a-phone-a-row-of-them-on-a-desktop) |
| something should disappear without moving its neighbours | [§15.9](#159-hiding-something-without-moving-everything-else-hidden) |
| code should run when a node arrives or leaves | [§15.10](#1510-knowing-when-something-arrives-and-leaves-onappear--ondisappear) |

## 15.1 Deciding who gives way when a row is too tight: `layoutPriority`, `shrinkWeight`

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

## 15.2 Sizing against the container, not the parent: `containerRelativeFrame`

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

## 15.3 Lining columns up across rows: `UI.GridRow` and `gridSpan`

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

## 15.4 Animating a state change: `presenter.withAnimation`

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

## 15.5 When a row is simply too long: `wrap`

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

## 15.6 Listing a dictionary: `UI.sortedEntries`

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

## 15.7 Promising a row's height: `newVirtualList` and `itemExtent`

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

## 15.8 Cards and rails: one card per swipe on a phone, a row of them on a desktop

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

## 15.9 Hiding something without moving everything else: `hidden`

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

## 15.10 Knowing when something arrives and leaves: `onAppear` / `onDisappear`

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

Next: [chapter 2](02-architecture.md) shows how the modules fit together, and
[chapter 3](03-getting-started.md) builds a working screen.
