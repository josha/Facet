# 4. Tutorial: eight stages across seven example files

The library ships seven small example programs under
`examples/gallery/examples/`. The playlist example covers two distinct learning
stages, so the table below has eight numbered stages. Work through the files in
order and you will have used every major feature of LuauUI.

## How the examples are structured

Every example file returns the same shape:

```lua
{ title = "...", build = function(LuauUI, core, deps) ... end }
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
| 6 | `05_word_game.luau` | a keyed grid + a hardware-key input context (2D nav is auto) |
| 7 | `06_tile_game.luau` | selection state and derived score at board scale |
| 8 | `07_match3.luau` | adaptive layout, async images, deterministic churn |

---

## 4.1 Temperature converter

**New concepts: signals, memos, and a real text field with its two edit modes.**

The smallest interactive screen. The user types a Fahrenheit value into a
numeric text field (`LuauUI.newTextInput`) and sees it converted to Celsius. The field is the
primary — and only — input affordance. (Earlier builds of this tutorial used
stepper buttons because the library had no editable text-box control; now that
the text-input control (`LuauUI.newTextInput`, over the `UI.TextField` primitive) ships, the field replaces them.)

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
local field = LuauUI.newTextInput(LuauUI, core, {
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
controls inside cells, filter-as-you-type over a derived rows list, and
drag-and-drop row reordering.**

This example combines what were previously two separate lessons (a star-rating
control and a track list) into the screen a music app would actually ship: an
iTunes-style playlist with a filter field, a header, and three columns — Name,
Length, and a star Rating you can click — whose rows you can drag into a new
order.

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
`cell`. Name and Length are `value` columns; Rating is a `cell` column that
builds five small buttons whose labels are derived values over that track's
rating signal:

```lua
local glyph = core:memo(function(use)
	return if use(rating) >= i then "★" else "☆"
end)
starButtons[i] = UI.Button({ id = `Star{i}`, label = glyph, padding = 2, width = { type = "fixed", px = 22 } })
```

Because the label is a bound derived value, tapping a star is pure repaint:
the test asserts the row's factory-run counter does not move.

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
reconciles.**

An audio-settings form (a Music toggle and a volume stepper) whose values are
owned by the server. This is the first example to use `LuauUI.replication`, and it
is the practical version of the client/server model from
[chapter 1](01-concepts.md).

There are two layers of state. The **authoritative** state — what the server has
confirmed — lives in a snapshot; the **optimistic draft** — what the UI shows
right now — lives in plain signals that may run ahead of the server:

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

The "server" is a loopback table in the same file, exactly as a single-place demo
would use. When it processes a request it applies the server's *validation rule*
(volume must be 0–10, which the UI deliberately does not enforce), and on success
it replicates the new snapshot **before** confirming, so the reconcile step reads
fresh truth:

```lua
if valid then
    snapshot.ingest(snapshot.revision() + 1, { music = payload.music, volume = payload.volume })
    mutation.confirm(envelope.requestId, "ok")
else
    mutation.reject(envelope.requestId, "volume must be 0..10")
end
```

Activating a control calls `commit`, which calls `mutation.send(...)` (running the
optimistic apply and moving the status to `pending`) and hands the returned
envelope to the loopback server. Push the volume past 10 and the request is
rejected and the stepper snaps back — the visible proof that a pending change is
not a confirmed one. The full replication contract is covered in
[chapter 6](06-client-server.md).

---

## 4.4 Confirm dialog

**New concept over example 4: modals — a second screen stacked on the first, with
focus trapping and cancel routing.**

A "Delete Save" button that opens a confirmation dialog. This is the first example
whose *action* uses `deps.presenter` at runtime, and the first to call
`presenter.presentModal` instead of `present`.

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

**New concepts over example 5: a keyed grid of state, a custom input context, and
navigation groups for two-dimensional movement.**

A Wordle-style game: a six-by-five board of letter tiles and an on-screen
keyboard. This is the first example large enough that it manages its own lifetime,
so it opens with a pattern you will see in the rest of the set — a scope that owns
everything it creates, so `dispose()` cleans up completely:

```lua
local gameScope = core:scope("example-06-word-game")
local function reg(readable)                     -- own a signal/memo for disposal
    gameScope:own(function() readable:dispose() end)
    return readable
end
local rowsSig = reg(core:signal(emptyRows()))
```

The game state is one signal holding the whole board, and — importantly — every
edit produces a **new** board table (via `cloneRows`) rather than mutating the old
one, so the core sees a genuine change and recomputes the tile bindings. The UI is
a pure function of that state: each tile's letter and its color come from memos
over `rowsSig`. No game logic lives in the view.

The keyboard is built as three `HStack` rows of key buttons, and **that layout
is the navigation map**. The presenter derives 2D navigation from any horizontal
container automatically: each `HStack` row becomes a horizontal group, so a
gamepad moves left/right within a row and up/down between rows, landing on the
nearest key in the same column — with no `present()` opts and no focus-scope
dance. (Earlier builds of this example popped the auto flat ring and pushed a
hand-written grouped scope; that hook is gone because the layout now supplies it.)

Activating a key — a tap, or gamepad A on the focused key — runs that key's
command, because each key carries it on its node:

```lua
UI.Button({ id = "key_" .. key, label = label, onActivate = function()
    if thisKey == "Enter" then submit()
    elseif thisKey == "Back" then backspace()
    else typeLetter(thisKey) end
end })
```

The one thing that genuinely stays at the consumer level is the **hardware
keyboard**, and it is app-semantic: a physical letter key should TYPE into the
grid (not activate whatever key button happens to be focused), and Enter should
SUBMIT the guess. So the example raises its own higher-priority context that
**sinks** those keys, shadowing the presenter's default Activate:

```lua
local ctx = actions.createContext({ name = "WordleInput", priority = 2000, sink = true })
-- 26 letter actions, plus Submit (Return) and Backspace — NO navigation actions:
-- arrows/D-pad fall through to the presenter's auto grid navigation
```

The test harness drives hardware keys through `actions.deviceKey(keyCode, true/false)`
— the same arbitrated path a real device uses — which is how a headless test can
prove keyboard, touch, and gamepad all reach the same game commands.

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
signals, which repaints exactly the affected tiles. Because the board rows and
the rack are `HStack`s, the presenter also derives 2D grid navigation from the
layout for free, so a gamepad D-pad crosses the whole board and rack and A
select-then-places — the example passes no `present()` opts.

---

## 4.7 Match-3

**New concepts over example 7: adaptive layout from device facts, asynchronous
images, and deterministic rapid state churn.**

A match-3 grid — the "write once, run everywhere" showcase — where swapping two
adjacent tiles clears matches, tiles fall, and new tiles refill from the top. It
pulls together three features not seen before.

**Adaptive layout.** The tile size is a memo over the environment's `sizeClass`
fact (compact/regular/wide, derived from screen width — see
[chapter 5](05-styling.md)). The *same* blueprint sizes itself sensibly on a
phone, a tablet, and a desktop, because changing the bound size dimension
re-solves layout without rebuilding the tree:

```lua
local cellDim = reg(core:memo(function(use)
    local sizeClass = use(env:get("sizeClass"))
    local px = if sizeClass == "compact" then 40 elseif sizeClass == "regular" then 56 else 72
    return { type = "fixed", px = px }
end))
```

**Asynchronous images.** Each tile kind's picture is loaded through
`LuauUI.newResourceProvider`, which models the *ready* and *pending* states a real
texture load has. A tile shows an explicit placeholder until its image resolves,
so nothing on screen assumes an image exists the instant a tile appears:

```lua
local provider = LuauUI.newResourceProvider(core, { maxConcurrent = 8 })
kindHandle[kind] = provider.acquire(gameScope, `img/{kind}`)
...
local image = reg(core:memo(function(use)
    local resolved = use(kindHandle[use(kindSig[rr][cc])].value)
    return if resolved ~= nil then resolved else PENDING
end))
```

The provider is *drained by the caller*, never by this file: a test calls
`provider.complete(...)` to simulate a load finishing; a real client would map
each key to an uploaded asset id through its texture transport. This is the async
model from [chapter 2](02-architecture.md) in action.

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
