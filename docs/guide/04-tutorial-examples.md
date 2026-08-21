# 4. Tutorial: eight stages across seven example files

The library ships seven small example programs under
`examples/gallery/examples/`. The playlist example covers two distinct learning
stages, so the table below has eight numbered stages. Work through the files in
order and you will have used every major feature of Facet.

## How the examples are structured

Every example file returns the same shape:

```lua
{ title = "...", build = function(Facet, core, deps) ... end }
```

`deps` is always the same four-field table — `{ env, actionSystem, presenter,
adapter }` — and each example uses only the pieces it needs. There are two styles
of `build` in the set, and the difference is worth noticing:

- **Examples 1–5 hand the screen back to the caller.** Their `build` returns
  `{ screen = <blueprint>, ...handles }`, and the caller shows it with
  `presenter.present(built.screen)`. None of them pass `present()` options: the
  presenter auto-composes each mounted control's four-input story (pointer,
  touch, keyboard, gamepad) from the tree, so there is no navigation map,
  activation router, or occlusion wiring to hand it. (One exception uses the
  presenter at all: example 5, whose *action* opens a modal.)
- **Examples 6–8 present themselves.** Their `build` takes `deps.presenter`,
  calls `presenter.present(...)` internally, and returns a handle with a
  `dispose()` you call when finished. They do this because they manage their own
  lifetime (a game scope, a results modal); example 6 additionally raises its own
  input context for the *hardware* keyboard. None of them wire navigation or
  activation by hand — the presenter derives 2D navigation from their layout and
  dispatches Activate to each control's own handler (see §4.5–4.7).

The file order:

| # | File | New idea it introduces |
|---|---|---|
| 1 | `01_temperature_converter.luau` | signals, memos, and activation |
| 2 | `02_playlist_table.luau` | composing a reusable table/control from primitives |
| 3 | `02_playlist_table.luau` (continued) | collections, derived filtering, virtualization |
| 4 | `03_settings_sync.luau` | optimistic mutation and server reconciliation |
| 5 | `04_confirm_dialog.luau` | modals, focus trapping, cancel routing |
| 6 | `05_word_game.luau` | a keyed `UI.Grid`, state as theme roles, a hardware-key context |
| 7 | `06_tile_game.luau` | selection state and derived score at board scale |
| 8 | `07_match3.luau` | adaptive layout, async images, deterministic churn |

---

## 4.1 Temperature converter

**New concepts: signals, memos, and a real text field with its two edit modes.**

The smallest interactive screen. The user types a Fahrenheit value into a
numeric text field (`Facet.newTextInput`) and sees it converted to Celsius. The field is the
primary — and only — input affordance. (Earlier builds of this tutorial used
stepper buttons because the library had no editable text-box control; now that
the text-input control (`Facet.newTextInput`, over the `UI.TextField` primitive) ships, the field replaces them.)

**The way back.** The quality pass played this screen and found it had no reset at
all: once a value was typed, the only route to the starting state was select-all-
and-delete, which is neither discoverable nor a lesson. A **Clear** button now
returns the field, the live preview and the committed result together.

**Style authority.** Every `textSize` here names a typography *role*
(`title`/`label`/`body`/`heading`) and every space names a step (`"m"`, `"s"`),
rather than the px literals this example used to carry. A literal is the same
number under every package, which is exactly what made these screens immune to the
theme picker mounted beside them.

Three pieces of state are held in signals:

```lua
local fahrenheitText = core:signal("")            -- the field's editable text (owner-held)
local liveCelsius    = core:signal(nil :: number?) -- the LIVE preview (onChange)
local celsius        = core:signal(nil :: number?) -- the COMMITTED result (onCommit)
```

The field text is a **string** signal the owner holds (state that outlives the
control belongs to the caller). The two Celsius signals exist to make the whole
lesson visible: one tracks every keystroke, the other changes only when the
edit is finished.

### The two edit modes

A text field has two moments worth distinguishing, and `newTextInput` gives you
a callback for each:

- **`onChange` — LIVE mode.** Fires on every accepted edit *while you type*. We
  parse the text and update `liveCelsius`, which drives a preview label. As you
  type `2`, `1`, `2`, the preview walks toward `100 °C`.
- **`onCommit` — COMMIT mode.** Fires only when the edit is *finished* — on
  Enter (`reason = "enter"`) or when focus leaves the field
  (`reason = "focusLost"`). We update `celsius`, which drives the Result label.
  Until you commit, the Result stays `—`.

```lua
local field = Facet.Controls.TextInput(core, {
    id = "Fahrenheit",
    value = fahrenheitText,
    placeholder = "e.g. 212",
    keyboardType = "numeric",   -- declared INTENT for the engine adapter, not a guarantee
    validate = acceptNumeric,   -- enforces numeric input on every keystroke (below)
    onChange = function(text)
        local n = tonumber(text)
        liveCelsius:set(if n ~= nil then (n - 32) * 5 / 9 else nil)
    end,
    onCommit = function(text, _reason)
        local n = tonumber(text)
        celsius:set(if n ~= nil then (n - 32) * 5 / 9 else nil)
    end,
    env = deps and deps.env,               -- keyboard-occlusion keep-visible (phones)
    actionSystem = deps and deps.actionSystem, -- the text-entry sinking context
})
```

`keyboardType = "numeric"` is a *hint* the engine adapter may honor where a
numeric on-screen keyboard exists — it is never a promise (the current engine
exposes no public keyboard-type API), so it must not be your only line of
defense. The `validate` hook is what actually enforces numeric input, on every
platform:

```lua
-- optional leading '-', digits, at most one '.'; also accepts the in-progress
-- states you pass THROUGH while typing ("", "-", ".", "-.") so a keystroke on
-- the way to a valid number is never blocked. Rejects letters, '+', a 2nd '.'.
local function acceptNumeric(proposed)
    if string.match(proposed, "^%-?%d*%.?%d*$") ~= nil then return proposed end
    return nil   -- nil = reject this edit; the value is left unchanged
end
```

`validate` runs on every proposed edit after the (optional) `maxLength` clamp:
return the accepted string (you may normalize it), or `nil` to reject. A
rejected edit fires no `onChange` and leaves the value untouched.

### Two memos, two labels

Each Celsius value is turned into a display string by a **memo** — a value
computed from other reactive values through the `use` reader, recomputed only
when something it read changes — and bound to a Text by being passed as `text`:

```lua
local previewLabel = core:memo(function(use)
    local c = use(liveCelsius)
    if c == nil then return "Preview: —" end
    return string.format("Preview: %g °C  (live, as you type)", c)
end)
local resultLabel = core:memo(function(use)
    local c = use(celsius)
    if c == nil then return "Result: —" end
    return string.format("Result: %g °C", c)
end)
```

Passing a memo (or signal) as a prop is what makes the text reactive: when it
changes, only that one Text is rewritten — the surrounding UI is not rebuilt.

### No presenter wiring

The field is a control that advertises its own four-input story: mounting it is
enough. The `newTextInput` control attaches an *input contribution* to its root
node, and the presenter auto-composes everything from it — Activate routes into
the field (a tap, or Return/gamepad-A on the focused field, enters edit mode),
the keyboard-occlusion geometry and keep-visible offset are fed automatically,
and the field's own high-priority edit-mode context is raised so typing swallows
the arrow/D-pad keys and never moves focus. So this example passes **no**
`present()` options at all:

```lua
-- the caller just presents the screen; there are no present() opts to hand it
presenter.present(built.screen)
```

The whole loop: typing writes `fahrenheitText`; `onChange` updates
`liveCelsius`; the preview repaints. Press Enter (or tap away) and `onCommit`
updates `celsius`; the Result repaints. You never touch a text node directly —
that is the declarative cycle, with the live-vs-commit distinction on top.

---

## 4.2 Playlist table

File: `examples/gallery/examples/02_playlist_table.luau`

New concepts: **the Table control, columns that own their cells, interactive
controls inside cells, filter-as-you-type over a derived rows list,
drag-and-drop row reordering, and swipe actions on either edge of a row.**

This example combines what were previously two separate lessons (a star-rating
control and a track list) into the screen a music app would actually ship: an
iTunes-style playlist with a filter field, a header, and two columns — Name and
a star Rating you can drag across — whose rows you can drag into a new order and
swipe sideways for their actions.

**There used to be a third column, Length, and measuring edit mode removed it**
(2026-08-13). A `fill` column gets whatever the fixed ones leave, and once this
table declared `rowActions` with a destructive action, edit mode began spending
*two* leading gutters on every row: 32px for the reorder ≡, plus the theme's
`editAffordance` gutter for the red ⊖. On the narrowest viewport the sweep covers
(320×640) that solved the Name cell to 6px and its text to 0px. Removing the
70px Length column gives the name 60px back there. The shipped example had
already been squeezing the name down to 26px on that phone with nothing
complaining, so this was a pre-existing problem the new gutter merely made
visible — the numbers and the two rejected alternatives are in the example's own
columns list.

**Restore.** Reordering rows and re-rating tracks are both destructive to the
shipped playlist, and there was no way back short of leaving the place. A
**Restore the original playlist** button returns the order, every rating and the
filter together.

**A known limit at Largest text.** On a compact phone with the player's text size
at Largest, `UI.Table`'s touch Edit toggle overlaps the rating column's header
title. It is a framework defect in the Table's toolbar/header spacing — this
example authors no toolbar or header geometry — and it is recorded, unclosed, in
`artifacts/example-quality-pass/studio/large-text.json` as `LT-F3`.

### The data

The FULL playlist order lives in one signal holding the array of tracks. Each
track's rating is its **own** signal, created once and looked up by track id:

```lua
local baseRows  = core:signal(table.clone(TRACKS))
local filterText = core:signal("")   -- the filter field's value (owner-held)
local ratings = {}
for _, track in TRACKS do
	ratings[track.id] = core:signal(track.rating)
end
```

Separating "the order" from "each track's rating" is the key move: reordering
writes `baseRows` (rows move, nothing rebuilds — keyed rows keep their mounted
cells), while rating a track writes one small signal (five star glyphs
repaint, nothing else changes).

### Filter-as-you-type over a derived rows list

The rows the table actually shows are a **memo** derived from `(baseRows,
filterText)` — a case-insensitive substring match on the track name:

```lua
local filteredRows = core:memo(function(use)
	local query = string.lower(use(filterText))
	local all   = use(baseRows)
	if query == "" then return all end
	local out = {}
	for _, track in all do
		-- string.find(..., 1, true) = a PLAIN substring test (no pattern magic),
		-- so a filter like "." matches a literal dot
		if string.find(string.lower(track.name), query, 1, true) ~= nil then
			table.insert(out, track)
		end
	end
	return out
end)
```

The table's `rows` is this memo (`rows = filteredRows`). A `newTextInput` field above
the table has `value = filterText`, so **every keystroke updates the signal the
memo reads** — the filter is live by construction, no `onChange` plumbing
needed. Because the table reads its rows reactively, editing the filter
re-derives the list and the table reconciles: surviving keys keep their mounted
cells (no remount), and only the rows that dropped out are removed. The field's
`clearButton = true` shows a trailing ✕ *only while the filter is non-empty*;
activating it empties `filterText` and the whole list returns.

### Reordering while filtered

Reordering is **disabled while a filter is active** — the iTunes / SwiftUI
convention. The visible rows are a *subset* of the real order, so where a drop
lands relative to the hidden rows is ambiguous; rather than guess, the
`onReorder` handler refuses the move while `filterText` is non-empty and leaves
the base order untouched. Clear the filter to rearrange. When unfiltered, the
splice is applied to the full `baseRows` (the post-removal contract below).

### Columns own their cells

A table column can render plain text with `value`, or any blueprint with
`cell`. Name is a `value` column; Rating is a `cell` column that mounts a real
`Facet.newRating` control — one control, not five buttons, built once per track
and owned by the example — whose glyphs are derived values over that track's
rating signal:

```lua
ratingControls[track.id] = Facet.Controls.Rating(core, {
	id = "Rating", env = deps.env, value = ratings[track.id], count = 5,
})
```

Because each glyph is a bound derived value, rating a track is pure repaint: the
test asserts the row's factory-run counter does not move. (This *was* five
`UI.Button`s built inline, and a device pass showed why that is the wrong shape —
a Button is a `control` to every theme, so the rating painted as five plates,
five focus stops and five overlapping 44px hit targets in one cell. The example's
own comment carries that history.)

### Activation lives on the node

Buttons inside cells activate exactly like any other button. Each star carries
its own effect on its `onActivate` prop, so activating it (a tap, or Return/A on
the focused star) sets that track's rating — no path-matching router, and no
`present()` opts:

```lua
UI.Button({ id = `Star{i}`, label = glyph, surface = "plain",
	onActivate = function() rating:set(i) end })
```

The presenter dispatches Activate to the node's own handler when a leaf declares
one; otherwise it falls through to a mounted control's contribution (here the
Table, for row selection and header behavior) — so the star effect and the
table's own behavior coexist with no consumer routing.

### When the table is too narrow for its columns

A phone in portrait is not a desktop with fewer pixels — a five-column table
crammed into 393pt is five columns of nothing. So a Facet table that cannot fit
every column's declared floor **collapses the lowest-priority column whole**
rather than squeezing all of them past their minimums, and then says so.

Two declarations decide it, and both are optional:

```lua
{ id = "name",   width = { type = "fill", weight = 3 }, minWidth = 90 },
{ id = "artist", width = { type = "fill", weight = 2 }, minWidth = 72 },
{ id = "rating", width = { type = "fixed", px = 144 } },
```

* **A floor is the trigger, wherever it comes from.** `minWidth` is now a floor
  on every dim kind, `fill` included — before, a `fill` column was divided
  strictly by weight and a declared minimum bought nothing. A `fixed` width and a
  `percent` are floors too, and so is any column the PLAYER has resized, because
  a committed width resolves to a `fixed` dim. A table that declares nothing and
  has never been resized has a demand of zero and collapses nothing; a resizable
  one is a single divider drag away from having a floor it never wrote. Either
  way the disclosure follows the collapse — they read the same state, so there is
  no shape where a column can go without the `N more` chip going with it.
* **`priority` is the order.** `priority = 1` is the most important; absent, a
  column's priority is its declaration order, so the playlist above drops Rating
  first because Rating is written last. `priority = "always"` is a refusal — this
  column never goes, at any width. The **first** column never goes either: it is
  the row's identity, and it is what the disclosure names each hidden value
  against.

Nothing is lost when a column collapses. The table grows an `N more` chip — its
own focus stop, a 44px thumb band — whose plate lists each hidden column and
every visible row's value for it, and a collapsed column's **sort** is still
selectable from there. Widen the window and the column comes straight back: the
collapse is a hide rather than a rebuild, so it costs no selection, no focus and
no live control inside a cell.

The playlist demonstrates all of it at 320x640: Rating collapses, the two text
columns go from 30px and 14px of readable text to 66px each, and the width
readout above the table changes from `Rating locked` to `Rating hidden ·
1 hidden`. `api.hiddenColumns` is the Readable that line reads.

### Drag & drop

Row reordering is built into the Table: `reorderable = true` plus an
`onReorder` callback. While dragging, the row stays in place and a ghost chip
plus a drop line carry the affordance; on release the table reports **which
keys moved and where they landed** — it never mutates your data. The example
applies the splice to its own `baseRows` signal (and, per the rule above, only
when no filter is active):

```lua
onReorder = function(keys, toIndex)
	-- split rows into (moving, staying), then reinsert the moving block
	-- after position `toIndex` among the staying rows
end
```

`toIndex` counts positions among the rows NOT being dragged (drop the moved
rows out, then insert the block after that slot) — this "post-removal"
convention makes multi-row drags unambiguous.

### Swipe actions on either edge

Swiping a row sideways reveals its actions — left for **Remove**, right for
**Top**. This is `rowActions`, the turnkey form of `Facet.newRowActions` that
`Table` hosts for you: return `{ leading, trailing, fullSwipe }` for a row and
that row gets a tray on each edge you filled in.

```lua
rowActions = function(item)
	local id = item.id
	return {
		leading  = { { id = "top",    label = "Top",    icon = "chevron.up", onAction = ... } },
		trailing = { { id = "remove", label = "Remove", icon = "trash",
		               role = "destructive", onAction = ... } },
		fullSwipe = { leading = false, trailing = true },
	}
end
```

**This is not edit mode, and the difference is the whole point.** Edit mode is a
*mode* you enter with the Edit button, and while it is on, rows grow a ≡ reorder
handle and taps select. Swipe actions are a per-row *gesture* that works with the
table sitting in its normal state — no mode, no button, no selection change.
SwiftUI draws the same line: its `swipeActions` documentation never mentions edit
mode, and its `EditMode`/`EditButton` documentation never mentions swiping.

**Which edge gets what.** Apple's default edge is trailing ("The default is
`HorizontalEdge.trailing`", [SW-37]), and that is where a destructive action
belongs — so Remove is trailing and Top is leading. Within an edge, actions
appear in the order you list them, starting from the swipe's originating edge.

**Full swipe is per edge.** By default a full swipe performs the first action for
that direction, and you opt an edge out with `allowsFullSwipe: false` — Apple's
own worked example disables it on the leading edge, and this example does the
same. So a full swipe *left* removes the track outright; a full swipe *right*
only reveals Top, which still needs a tap.

**It composes with the primary action rather than fighting it.** A tap plays the
track, a sideways drag opens a tray and plays nothing, and a mostly-vertical drag
still scrolls the page. The Table's axis lock decides which of the three a
gesture is before any of them can fire, so none of them has to know about the
others.

**And it is reachable without a swipe.** On a focused row, **Delete** runs the
destructive action and **Shift+Return** opens the row's action menu — so a
keyboard and a gamepad reach Remove and Top with no gesture to imitate. That is
the four-input rule, not a bonus.

**Edit mode adds a second route to the same Remove.** Because the trailing tray
carries a `role = "destructive"` action, entering edit mode also puts a small red
⊖ in a leading gutter on every row. Tapping it *reveals the trailing tray* rather
than deleting outright — the destructive action stays one more tap away.

### Scrolling vs. reordering on touch

A vertical touch drag can only mean one thing, so the table follows the
platform convention you know from phone playlist apps: a plain touch pan
always SCROLLS; reordering happens in an explicit edit mode. When reordering
is enabled and you hand the table the environment (`env = deps.env`), touch
users automatically get an Edit/Done toggle in the table's corner — tap Edit
and every row grows a LEADING ≡ handle in a left-hand gutter (the cells
slide right to clear it); dragging the handle reorders — one row, or the
whole selection when the dragged row is selected (tap rows to multi-select
first) — while dragging anywhere else still scrolls. Rows that are partially
scrolled out render cropped at the table's edge, exactly like a native list.
The toggle appears whenever a touchscreen **or a gamepad** is live on the
device — gamepad reordering starts from the same edit mode (focus a row,
press A to grab it, D-pad to move, A to drop) — and it keys off the full
live capability set, so a desktop with a controller plugged in gets it even
while the mouse is still the primary input. A pure mouse-and-keyboard machine
never sees it: the wheel scrolls and a direct row drag reorders,
desktop-style. Owners who want their own edit UI pass an `editing` signal
instead and the built-in toggle steps aside.

### Gamepad

None of this is wired by the example. Because both composites attach input
contributions, the presenter auto-merges their focus groups in document order:
the filter field's group comes first (so focus starts on the filter), then the
table's own row/toolbar/star groups. D-pad Up/Down steps between the filter,
rows, and toolbar, Left/Right moves from a row into its stars and across them,
and A (Cross on PlayStation) activates whatever is focused — select a row, press
a star, or hit the Edit toggle. In edit mode, A on a focused row GRABS it (it
highlights); each D-pad press then moves the row one slot — the whole selection
moves as a block if the grabbed row is selected — and A drops it. Grab-move-drop
(the table's `navigateIntercept`) and selection-follows-focus (its `focusMoved`)
ride the same contribution, so the screen passes no navigation or intercept opts.

### Try it in the place

Type in the Filter field to narrow the list (case-insensitive, matches anywhere
in a track name) and clear it with the ✕. Click or scrub the stars to rate.
Click rows to select them. With a mouse, drag a row to reorder and wheel-scroll
the list. On touch (or the Studio device emulator), tap Edit, then drag a row's
≡ handle to reorder — plain drags pan the list. With a gamepad, D-pad + A drives
everything (starting on the filter field), including grab-to-reorder in edit
mode. Reordering is disabled while a filter is active — clear it first.


## 4.3 Settings sync

**New concept over example 3: talking to a server — an optimistic mutation that
reconciles, with every step of the round trip on the screen.**

An audio-settings form (a Music toggle and a volume stepper) whose values are
owned by the server. This is the first example to use `Facet.replication`, and it
is the practical version of the client/server model from
[chapter 1](01-concepts.md).

### What the screen shows

Two labelled read-outs sit next to each other, because the whole lesson is the
gap between them:

```
What you see now (your optimistic draft)
Music off, volume 10
------------------------------------------
What the server has confirmed
Music off, volume 10 (revision 1)
```

Under them, a **status** line (`idle` / `pending` / `accepted` / `rejected` with
its reason), a **hint** line naming the next action, the controls, and a short
**history** of what happened, newest first. Nothing about the lesson is hidden
behind a test handle: a player who has never read the source can reach every
state from the screen.

### Two layers of state

The **authoritative** state — what the server has confirmed — lives in a
snapshot; the **optimistic draft** — what the UI shows right now — lives in plain
signals that may run ahead of the server:

```lua
local snapshot    = replication.snapshot(core, 1, { music = false, volume = 10 })
local draftMusic  = core:signal(snapshot.binding:get().music)
local draftVolume = core:signal(snapshot.binding:get().volume)
```

The **mutation** ties them together. Its `optimistic.apply` runs the instant you
send (so the UI changes immediately), and its `optimistic.restore` re-syncs the
draft to server truth — used both on confirm (reconcile) and on reject (roll
back):

```lua
local mutation = replication.mutation(core, {
    optimistic = {
        apply = function(payload)
            draftMusic:set(payload.music); draftVolume:set(payload.volume)
        end,
        restore = function()
            local truth = snapshot.binding:get()
            draftMusic:set(truth.music); draftVolume:set(truth.volume)
        end,
    },
})
```

### The reply is delivered by the player

The "server" is a loopback table in the same file, exactly as a single-place demo
would use. It **queues** its answer and hands it over only when the
**Deliver server reply** button is pressed, because *when the answer lands* is
the thing this example is about: while a request is in flight the draft read-out
already shows the new value and the server read-out still shows the old one.

The method is called `deliver`, not `flush`, on purpose — the gallery host
auto-flushes any `server.flush` every frame, which would answer before a player
could ever watch a request be pending.

When it processes a request it applies the server's *validation rule* (volume
must be 0–10, which the UI deliberately does not enforce), and on success it
replicates the new snapshot **before** confirming, so the reconcile step reads
fresh truth:

```lua
if valid then
    snapshot.ingest(snapshot.revision() + 1, { music = payload.music, volume = payload.volume })
    mutation.confirm(envelope.requestId, "accepted")
else
    mutation.reject(envelope.requestId, "volume must be 0..10")
end
```

### One request at a time

`mutation.send` **throws** while a request is in flight — one in flight per
Mutation is the adapter's contract. A tutorial must not throw at a player for
pressing a button twice, so the example checks the status first and writes
`Already waiting for a reply. Deliver it first.` into the history instead:

```lua
if mutation.status:get() == "pending" then
    log("Already waiting for a reply. Deliver it first.")
    return
end
```

### Reset moves the revision forward

**Reset demo** returns the demonstration to its documented start state (music
off, volume 10) — by having the server *write those values again at a new
revision*, not by pretending the history never happened. A snapshot refuses an
older revision, so a revision only ever moves forward. `mutation.reset()` is what
abandons a request the server never answered, and it rolls that request's
optimistic presentation back on the way out.

### Try it in the place

1. Read the two read-outs: draft and server agree, `Status: idle`.
2. Press **–**. The draft says `volume 9` and `Status: pending (no reply yet)`
   immediately, while the server still says `volume 10 (revision 1)`.
3. Press **Deliver server reply**. `Status: accepted`, and both read-outs settle
   on `volume 9 (revision 2)` — that is the reconcile.
4. Press **Ask for volume 99**. The draft jumps to `volume 99` and goes pending —
   an optimistic value the server is certain to refuse.
5. Press **Deliver server reply** again. `Status: rejected (volume must be
   0..10)`, and the draft rolls back to `volume 9`. The server never moved.
6. Press **Reset demo** to return to the start state.

The page scrolls, so every control stays reachable on a phone and at the largest
preferred-text setting. Touch, mouse, the arrow keys plus Return, and a gamepad
D-pad plus A all drive the same controls — the example wires none of that; the
presenter derives it from the layout (ADR-0013). The full replication contract is
covered in [chapter 6](06-client-server.md).

---

## 4.4 Confirm dialog

**New concept over example 4: modals — a second screen stacked on the first, with
focus trapping and cancel routing.**

A "Delete Save" button that opens a confirmation dialog. This is the first example
whose *action* uses `deps.presenter` at runtime, and the first to call
`presenter.presentModal` instead of `present`.

**The answer has to be visible.** Played in Studio, this example confirmed a
destructive "Delete" and left the base screen *byte-identical*: the outcome went
into a `result` signal that only a test could read. The slot now holds a save,
empties when you confirm, says which happened, offers **Restore the save**, and
stops offering Delete on an empty slot — so the round trip is readable and
repeatable in place.

**And the card really is centred now.** The dialog declared `alignH`/`alignV` on a
`UI.Screen`, where those props are documented as *ZStack-child* alignment and are
accepted-and-ignored: the card rendered at `16,16`, the top-left corner, while
every reader of the file believed it was centred. The scrim now holds one
full-bleed `UI.ZStack` and the card centres inside that, with a test asserting its
centre sits within 2 px of the scrim's on both axes.

The base screen is ordinary; its button carries the open action on its node, so
the base is presented with no options:

```lua
UI.Button({ id = "Delete", label = "Delete Save", onActivate = openDialog })
```

`openDialog` presents the dialog blueprint *on top* of the base screen. The
dialog's two buttons each carry their own outcome on `onActivate`, so the modal
is presented with no options either:

```lua
UI.Button({ id = "Confirm", label = "Delete", onActivate = function()
    result:set("confirmed"); presenter.dismiss(currentModal)
end }),
UI.Button({ id = "Cancel", label = "Cancel", onActivate = function()
    result:set("cancelled"); presenter.dismiss(currentModal)
end }),
-- ...
local function openDialog()
    currentModal = presenter.presentModal(dialog)
end
```

Presenting a modal gives you three behaviors for free, all handled by the
presenter (recall [chapter 1](01-concepts.md)):

- **Focus trap** — while the dialog is open, keyboard/gamepad focus cannot leave
  it; navigation wraps inside the two buttons.
- **Cancel routing** — the gamepad B button dismisses the modal *without* reaching
  the `onActivate` above; the presenter handles it. (There is no Escape-key path:
  Roblox reserves Escape, so a keyboard user clicks the on-screen Cancel button.)
- **Focus restoration** — dismissing the dialog returns focus to the Delete button
  that was focused before it opened.

None of that required either screen to know about the other.

---

## 4.5 Word game

**New concepts over example 4: a keyed grid laid out by `UI.Grid`, game state as
a set of pure rules the UI never touches, state expressed as theme roles, and a
custom hardware-key input context.**

A complete Wordle-like game. What the player sees at startup is a title, a status
line, a **six-row by five-column board** of empty tiles with a caret (`_`) in the
cell the next letter lands in, a legend, a three-row on-screen keyboard, and a
"New game" button.

The loop: type five letters, press Enter, read the row. A guess shorter than five
letters, or one that is not in the example's word list, is **refused with a
message and does not consume a row**. Six accepted wrong guesses lose and reveal
the word; solving wins. Either ending opens a results card and disables the
keyboard — only "New game" and the card's own buttons still respond. "New game"
is deterministic: the solution comes from a seed, so the same seed always gives
the same word.

### The rules are a pure table, and they are not framework code

Wordle scoring is *domain* logic. It lives in the example, exported so the tests
can drive the whole game without mounting anything:

```lua
example.rules = rules      -- evaluate, validate, strongest, mergeKeys, solutionForSeed
```

The only genuinely subtle part is the duplicate-letter rule, and it is why
`rules.evaluate` runs in **two passes**: the solution's letters are a *budget*,
exact matches spend it first, and only what is left can pay for a misplaced
letter. Guessing `AWARE` against `CRANE` is the case worth reading twice — the
guess's first `A` is `absent`, not `present`, because the `A` in column 3 already
spent the solution's only `A`. A single left-to-right pass gets that wrong, and
nothing on screen tells you.

The on-screen keyboard remembers the **strongest** thing ever learned about each
letter — correct beats present, present beats absent — so a later, weaker verdict
can never downgrade a key:

```lua
rules.KEY_RANK = { absent = 1, present = 2, correct = 3 }
```

### The board is one `UI.Grid`

```lua
UI.Grid({ id = "board", columns = COLS, gap = "xs", rowGap = "xs",
          itemSizing = "uniform", children = tiles })
```

`columns` is the entire board layout — the example never positions a tile.
`itemSizing = "uniform"` is what makes it a *board* rather than five columns of
whatever width the screen happens to be: every cell takes the widest measured
cell, so the grid reports "5 tiles + 4 gaps" as its own width and the parent
stack's `align = "center"` can centre it. Without it a grid reports "I need the
whole offer", and the tiles scatter across a desktop with a hundred pixels of
nothing between them.

Each tile is a `UI.ZStack` sized from a **theme metric** (`targetSizes.minimum`),
never a device pixel, holding a plate, a letter and a mark. Every visible property
is a memo over the state signals, so the view is a pure function of the state.

### State is a theme role, never a colour and never an invented token

This is the part of the example most worth copying. A tile is a `UI.Box`, and a
Box's one paint channel is `tint`, so tile state is a **blend along a theme
role** — and the blend *is* the strength of the evidence:

```lua
absent  = { role = "contentSecondary", blend = 0.3  }   -- receded
present = { role = "accent",           blend = 0.55 }   -- partial
correct = { role = "accent",           blend = 1    }   -- full
```

An on-screen key is a `UI.Button`, which paints from its `surface` role and its
own interaction states, so a key's state rides `surface` (`base` for an
eliminated letter, `chip` for a known-present one, `accent` for a solved one)
rather than a tint that would fight the control's own affordance.

Both also carry a plain-ASCII **mark** — `v` correct, `~` present, `x` absent,
`_` "type here" — because colour alone is not a cue, and ASCII is the only range
every Roblox font is guaranteed to draw. The board is readable in greyscale.

Reaching for a made-up token here is the classic version of this mistake. An
earlier build of this example bound `surface` to `"tileCorrect"`, which is not a
member of the closed `surface` enum; every one of the thirty tiles rendered
completely transparent, and nothing said so. Values from a **closed set** are
states — use the enum. Values on a **continuum** are `tint`.

### One command, three input paths

The keyboard is three `HStack` rows of key buttons, and **that layout is the
navigation map**. The presenter derives 2D navigation from any horizontal
container automatically: each row becomes a horizontal group, so arrows/D-pad
move left/right within a row and up/down between rows, landing on the nearest key
in the same column — with no navigation table in the file.

Activating a key — a tap, Space on the focused key, or gamepad A — runs that
key's command, because each key carries it on its own node:

```lua
UI.Button({ id = "key_" .. key, label = labelOf, surface = surfaceOf,
            enabled = playingSig, padding = 0,
            width = { type = "fill", weight = 1 },       -- the row divides itself
            height = { type = "fixed", px = "targetSizes.minimum" },
            onActivate = function()
                if thisKey == "Enter" then submit()
                elseif thisKey == "Back" then backspace()
                else typeLetter(thisKey) end
            end })
```

Note the widths: no key is a fixed pixel count. Each letter key is `fill` weight
1 and Enter/Delete are weight 1.5, so the row divides whatever width it is given
— from a 320 px phone to a desktop — instead of adding up to a number that only
suits one screen.

The one thing that genuinely stays at the consumer level is the **hardware
keyboard**, and it is app-semantic: a physical letter key should TYPE into the
grid (not activate whatever key happens to be focused), and Enter should SUBMIT.
So the example raises its own higher-priority context that **sinks** those keys,
shadowing the presenter's default Activate:

```lua
local ctx = actions.createContext({ name = "WordleInput", priority = 2000, sink = true })
-- 26 letter actions, plus Submit (Return) and Backspace — NO navigation actions:
-- arrows/D-pad fall through to the presenter's auto grid navigation, so a player
-- can switch between typing and navigating without losing the guess in flight
```

Because Return is taken, the screen asks for the one presenter option in the
file — `present(screen, { keyboardNavigation = true })` — which gives a
keyboard-only player Tab/Shift+Tab traversal and Space-as-Activate.

### Lifetime, and the results card

This is the first example large enough to manage its own lifetime, so it opens
with a pattern you will see in the rest of the set — a scope that owns everything
it creates, so `dispose()` cleans up completely:

```lua
local gameScope = core:scope("example-05-word-game")
local function reg(readable)                     -- own a signal/memo for disposal
    gameScope:own(function() readable:dispose() end)
    return readable
end
local rowsSig = reg(core:signal(emptyRows()))
```

Every edit produces a **new** board table (via `cloneRows`) rather than mutating
the old one, so the core sees a genuine change and recomputes only the tile
bindings that moved. Multi-signal edits — a submit, a restart — go through
`core:transaction` so the screen never paints a half-applied move.

The ending presents a results card on top of the board. Note how it is centred:

```lua
UI.Screen({ id = "WordleResult", surface = "scrim", padding = "m", children = {
    UI.ZStack({ id = "centre", width = FILL, height = FILL,
                alignH = "center", alignV = "center", children = { card } }) } })
```

`alignH`/`alignV` are **ZStack-child** props. Set on a `Screen` or a `VStack`
they are accepted and silently ignored; a filling `ZStack` in between is what
actually centres a card. (A stack's own children are aligned across the axis with
`align` instead.)

Finally, the whole page is a `UI.ScrollView`. The board plus a keyboard fits a
compact phone at the default text size and does *not* fit at the largest
accessibility text size, so it scrolls rather than running off the screen.

Its pure rules and its state machine are tested in
`tests/example_word_game.spec.luau`; the four mounted input paths are in
`tests/examples_games.spec.luau`. The test harness drives hardware keys through
`actions.deviceKey(keyCode, true/false)` — the same arbitrated path a real device
uses — which is how a headless test can prove keyboard, touch, and gamepad all
reach the same game commands.

---

## 4.6 Tile game

**New concepts over example 6: selection state and a derived score across a whole
board.**

A Scrabble-style board: a rack of lettered tiles and a five-by-five grid. The
interaction is *select-then-place* — tap a rack tile to select it, then tap a
board cell to place it. (This is deliberately not drag-and-drop; pick-up-by-drag
is a later expansion, and select-then-place needs nothing new.)

The entire interaction is expressed as three signals plus memos over them:

```lua
local selected    = reg(core:signal(nil :: number?))          -- selected rack slot
local placedSlots = reg(core:signal({} :: { [number]: boolean }))  -- which rack tiles are spent
local placements  = reg(core:signal({} :: { [string]: any }))      -- board cell -> { letter, value }
```

Every visible property is a pure binding over those. A board cell's label is the
placed letter or empty; a rack tile's `label`, its `enabled` flag, and its
`selected` flag are each a memo:

```lua
local enabled    = reg(core:memo(function(use) return not use(placedSlots)[slot] end))
local isSelected = reg(core:memo(function(use) return use(selected) == slot end))
UI.Button({ id = "rt" .. i, label = label, enabled = enabled, selected = isSelected, ... })
```

This is the first example to drive the `enabled` and `selected` props of a button
reactively — a spent tile blanks and disables itself; the chosen tile shows its
selected state — with no imperative toggling.

The **score** shows why deriving state matters: it is a memo that sums the value
of every placed tile, so it *cannot* drift out of sync with the board no matter
how placements change:

```lua
local score = reg(core:memo(function(use)
    local total = 0
    for _, p in use(placements) do total += p.value end
    return total
end))
```

Activation lives on each node: a rack tile's `onActivate` selects its slot, a
board cell's `onActivate` places the selection — and each command updates the
signals, which repaints exactly the affected tiles. The board and the rack are
each one `UI.Grid`, and the presenter derives 2D navigation from a Grid for free
(per-row groups linked by up/down exits), so a D-pad or the arrow keys cross the
whole board and rack and Activate select-then-places — the example passes no
`present()` opts.

**Refusal is feedback.** The quality pass played this example and found that every
move the rules rejected did *nothing at all*: tapping a square with nothing picked
up, tapping an occupied square, and tapping a spent rack slot were all completely
silent, and the second of them left the tile still highlighted with no reason
given. A rule that silently does nothing is indistinguishable from a broken
button. Each refusal now names itself in the instruction line — "Pick a letter
from your rack first", "Row 2, column 3 already has a letter" — and a successful
move clears the message, so the line always describes the state it sits above. A
spent rack slot is `enabled = false` with a spent marker, which answers the
question *before* the tap rather than after it.

The example also gained what a player needs to finish: a score and a `3 of 7 tiles
placed` progress readout, a completion message, and **Start over**, which returns
every observable — including the selection and the message — to its starting
value.

---

## 4.7 Match-3

**New concepts over example 7: adaptive layout from device facts, asynchronous
images, and deterministic rapid state churn.**

A match-3 grid — the "write once, run everywhere" showcase — where swapping two
adjacent tiles clears matches, tiles fall, and new tiles refill from the top. It
pulls together three features not seen before.

**Adaptive layout — and who is allowed to do it.** This example used to size its
own tiles from the environment's `sizeClass` fact, with a `compact/regular/wide ->
40/56/72 px` branch computed right here. That is *imperative responsive geometry
inside a consumer*, and the quality pass removed it: adaptation is Facet's job,
not an example's, and an example that names device classes has taken over a
decision the framework already makes.

The tile is now one theme metric, on a `UI.Grid`:

```lua
local CELL: any = { type = "fixed", px = "controls.large.height" }

UI.Grid({ id = "board", columns = COLS, itemSizing = "uniform", gap = "xs", children = cells })
```

A metric path resolves against the live theme snapshot on every solve, so a denser
package makes the board denser and a chunky touch package makes it chunkier —
without this file knowing what a phone is. The old test asserted the *defect*
(`desktopW > phoneW`, which was only true because of the branch); it now asserts
what actually matters, which is that a viewport change reflows without rebuilding
the tree and the tile never drops below the theme's touch floor at any of four
viewports.

**Asynchronous images.** Each tile kind's picture is loaded through
`Facet.newResourceProvider`, which models the *ready* and *pending* states a real
texture load has. A tile shows an explicit placeholder until its image resolves,
so nothing on screen assumes an image exists the instant a tile appears:

```lua
local provider = Facet.newResourceProvider(core, { maxConcurrent = 8 })
kindHandle[kind] = provider.acquire(gameScope, `img/{kind}`)
...
local image = reg(core:memo(function(use)
    local resolved = use(kindHandle[use(kindSig[rr][cc])].value)
    return if resolved ~= nil then resolved else PENDING
end))
```

**Who drains the provider, and why that mattered.** This file used to say the
provider was "drained by the caller, never by this file" — and the gallery host
never drained it, so on a real client every one of the thirty-six tiles showed the
pending placeholder forever and all five tile kinds were indistinguishable. The
game was unplayable in the only place it was meant to be played.

The example owns its transport now, because the artwork is its own fixture data:
it delivers once at build so the board is playable from the first frame, and the
three async states are on screen as controls a player can drive — **Re-request
artwork** puts every kind back to pending, **Deliver artwork** resolves them, and
**Fail a load** produces the failed state, which the status line names and the
re-request recovers. "Still loading" and "will never load" look identical to a
player unless you say which one it is.

The five kinds are five of the framework's own shipped icons — five distinct
*shapes*, so the board reads without relying on colour — and a test pins each id
against `src/themes/standard_icons.luau` so a re-upload fails loudly instead of
silently blanking the board. This is the async model from
[chapter 2](02-architecture.md) in action.

**Deterministic churn.** The board refills from a small seeded pseudo-random
generator, so replaying the same swap always produces the same board — which is
what lets a test assert an exact outcome. The board logic (`findMatches`,
`collapse`, `resolve`, `swapCells`) is pure and engine-free; it updates
per-cell signals so that only the cells that actually changed repaint, which is
what keeps a whole cascading refill cheap.

Each tile is an `Image` with a transparent, focusable `Button` layered on top
(a `ZStack`), and the board rows are `HStack`s — so the presenter derives the
grid navigation from the layout automatically, and a gamepad moves around the
board with no custom context and no focus-scope swap. Selection and swapping ride
each tile's own `onActivate`, so this example, too, passes no `present()` opts.

One thing the example is explicit about *not* doing: sliding a tile smoothly from
one cell to another would animate a layout position over time, and time-based
layout animation is a future expansion of the library, so tiles change instantly
here.

---

That is the whole feature surface. From here, [chapter 5](05-styling.md) covers
how any of these screens is styled, and [chapter 6](06-client-server.md) goes
deeper on the replication used in example 4.
