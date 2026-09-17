# 4. Tutorial: eight stages across seven example files

The library ships seven small example programs under
`examples/gallery/examples/`. The playlist example covers two distinct learning
stages, so the table below has eight numbered stages. Work through the files in
order and you will have used every major feature of Facet.

The Showcase picker has ten entries. **All controls** groups inputs, actions,
indicators and navigation in nested tabs. Its Indicators tab includes progress
rings and level indicators; Navigation includes the journey stack, pages and
collapsible content. **Collections** and **Motion and layout** group the larger
comparisons. **Screen-anchored HUD** owns a full screen for its adaptive zones.
**Quick actions**, **Playlist table**, **Settings sync**, **Word game**,
**Crossword** and **Match 3** show complete interactions and playable examples.

The three grouped demos use adaptable navigation for their outer categories:
a sidebar in roomy pointer windows, top pills for distant viewing, and bottom
tabs on compact nearby screens. Navigation corners follow the theme. Their inner example tabs stay at the top.
See [two-level navigation](14-choosing-controls.md#two-level-navigation) for the
composition and control-selection rule.

Hold keyboard arrows or the D-pad to continue moving focus. Use A to activate,
and B to dismiss a modal or go back in a
navigation stack. Shoulders page the nearest tab strip; focus can move between
both strips and their content. Returning to a category keeps its selected subtab.
Quick actions starts on Corner commands with Slim band fitting. Settings sync
pauses replies in a local server simulation: change a setting, compare the pending
screen value with the saved value, then deliver a reply. The invalid-volume
button demonstrates rejection and rollback. Match 3 supports dragging onto a
neighbor as well as selecting two tiles.
Each control comparison starts fresh when reopened. Individual diagnostic scenarios
remain selectable through `Facet_Scenario` for framework verification.

The Showcase includes **Collections → Grids → Card rail**
([source](../../examples/gallery/scenarios/card_rail.luau)). Its three horizontal
shelves use the same adaptive card layout across displays: one card and a preview
of the next on mobile, more cards on desktop, and fewer, larger cards for distant
viewing. Each shelf scrolls independently; Up/Down moves focus between shelves.
The explicit next-card preview remains visible in the multi-card layouts too.

## How the examples are structured

Every example file returns the same shape:

```lua
{ title = "...", build = function(Facet, core, deps) ... end }
```

`deps` is always the same four-field table — `{ env, actionSystem, presenter,
adapter }` — and each example uses only the pieces it needs. There are two
styles of `build` in the set:

- **Examples 1–5 hand the screen back to the caller.** Their `build` returns
  `{ screen = <blueprint>, ...handles }`, and the caller shows it with
  `presenter.present(built.screen)`. None of them pass `present()` options. The
  presenter auto-composes each mounted control's four-input story (pointer,
  touch, keyboard, gamepad) from the tree, so there is no navigation map,
  activation router, or occlusion wiring to hand it. (One exception uses the
  presenter at all: example 5, whose *action* opens a modal.)
- **Examples 6–8 present themselves.** Their `build` takes `deps.presenter`,
  calls `presenter.present(...)` internally, and returns a handle with a
  `dispose()` you call when finished. They do this because they manage their
  own lifetime (a game scope, a results modal). Example 6 also raises its own
  input context for the *hardware* keyboard. None of them wire navigation or
  activation by hand — the presenter derives 2D navigation from their layout
  and dispatches Activate to each control's own handler (see §4.5–4.7).

The file order:

| # | File | New idea it introduces |
|---|---|---|
| 1 | `01_temperature_converter.luau` | component state, property getters and controlled text entry |
| 2 | `02_playlist_table.luau` | composing a reusable table/control from primitives |
| 3 | `02_playlist_table.luau` (continued) | collections, derived filtering, virtualization |
| 4 | `03_settings_sync.luau` | optimistic mutation and server reconciliation |
| 5 | `04_confirm_dialog.luau` | modals, focus trapping, cancel routing |
| 6 | `05_word_game.luau` | a keyed `UI.Grid`, state as theme roles, a hardware-key context |
| 7 | `06_tile_game.luau` | a pure rules table, nine named refusals, and a board that paints |
| 8 | `07_match3.luau` | adaptive layout, async images, deterministic churn |

---

## 4.1 Temperature converter

**New concepts: component state, shared derived values and controlled text entry.**

[`01_temperature_converter.luau`](../../examples/gallery/examples/01_temperature_converter.luau)
is a `Facet.component` using `Facet.View`. Its state and bindings belong to the
mounted screen. It describes the interface once; only property recipes update.

```luau
local fahrenheit, setFahrenheit = ui.state("")
local celsius, setCelsius = ui.state(nil :: number?)
local function toCelsius(text)
    local n = tonumber(text)
    return if n then (n - 32) * 5 / 9 else nil
end
local liveCelsius = ui.memo(function() return toCelsius(fahrenheit()) end)
```

### The two edit modes

`onChange` accepts live text edits; the preview follows the text. `onCommit`
updates the final result on Enter or focus loss. The getter remains the source of
truth: validation can reject a proposed edit before its change callback runs.

```luau
UI.TextInput {
    id = "Fahrenheit", value = fahrenheit, onChange = setFahrenheit,
    placeholder = "e.g. 212", keyboardType = "numeric",
    validate = function(proposed)
        return if string.match(proposed, "^%-?%d*%.?%d*$") then proposed else nil
    end,
    onCommit = function(text) setCelsius(toCelsius(text)) end,
}
```

The grammar accepts unfinished numbers such as `-` and `.` while refusing letters
and a second decimal point. `keyboardType` describes intent; it does not force a
Roblox keyboard layout. A rejected edit leaves the value unchanged.

### Recipes and shared work

Use a simple property function for formatting. `liveCelsius` is a memo because
both the preview and the example driver read that derived number.

```luau
UI.Text {
    id = "Preview", role = "secondary",
    text = function()
        local c = liveCelsius()
        return if c == nil then "Preview: —" else string.format("Preview: %g °C", c)
    end,
}
UI.Button {
    label = "Clear",
    onActivate = function()
        ui.batch(function() setFahrenheit(""); setCelsius(nil) end)
    end,
}
```

### No presenter wiring

The mounted TextInput receives its environment and input integration from the
host. It owns editing, keyboard occlusion and cancellation. The example passes
no manual scope, core, input router or `.blueprint` into its view tree. Dismissing
the component releases its resources. Use typography roles and spacing steps so
the same description follows themes and the player's preferred text size.

## 4.2 Playlist table

**New concepts: shared model state, keyed rows, custom cells and table interactions.**

[`02_playlist_table.luau`](../../examples/gallery/examples/02_playlist_table.luau)
keeps the playlist order and ratings in a model scope. Filtering or removing a
mounted row does not destroy that track's rating. The application releases that
model at its lifetime boundary; the `Playlist` component owns mounted controls.
This is the same separation to use for an inventory or a server-backed catalog.

### The data

The model exposes `baseRows`, `sortOrder`, per-track ratings, and derived sorted
and filtered rows. Sorting is stable: equal values keep their original relative
order. A manual reorder first preserves the current displayed ordering, then
clears the sort. Restore resets the fixture's order, ratings, filter and selection.

### Filter-as-you-type over a derived rows list

A controlled search field binds the query. For component-local filtering, the
same idea is:

```luau
local query, setQuery = ui.state("")
local filtered = ui.memo(function()
    local matches = {}
    for _, track in tracks() do
        if string.find(string.lower(track.name), string.lower(query()), 1, true) then
            table.insert(matches, track)
        end
    end
    return matches
end)
local search = UI.TextInput {
    presentation = "search", value = query, onChange = setQuery,
    placeholder = "Filter tracks",
}
```

`tracks` is a getter; borrow a shared model readable with `ui.read(model.rows)`.
Use a memo because filtering does real work. Formatting a short label usually
needs only a property function. A plain substring search treats punctuation as
text, not a pattern.

### Reordering while filtered

The example refuses reordering while a filter is active: a visible subset cannot
unambiguously describe the full order. Clear the filter before moving rows.
The reorder callback uses the table's post-removal destination index.

### Columns own their cells

A `value` column renders a value. A `cell` column returns a view. A rating is one
adjustable control, so it gets one focus stop and the control's native input story:

```luau
local function starCell(item)
    return UI.Rating { id = "Rating", value = ratings[item.id], count = 5 }
end
```

Here `ratings` contains shared writable model signals, which View also accepts.
For local state use `value = rating, onChange = setRating`. Mount owns each rating
control; no eager cache of control handles or manual disposal loop is needed.

### Activation lives on the node

Buttons use `onActivate`. Table row selection, header sorting and primary actions
come from the table's contribution. Use `onPrimaryAction` to play the selected
track; do not route events by matching strings in node paths. Child controls and
the enclosing table retain their own input responsibilities.

### When the table is too narrow for its columns

The example declares minimum widths for Name and Artist and a fixed width for
Rating. Facet drops a lower-priority column as a whole when the floors cannot fit,
then offers the hidden values through its disclosure. The first identity column
stays available. Player column-width overrides participate in this calculation.
Widening the viewport restores the column without replacing the surviving rows.

The demo also displays the table's column widths and selected header. That is a
concrete reason to keep an explicit handle in this one component:

```luau
local tableHandle = ui.own(Facet.Controls.Table(core, tableSpec))
local widths = ui.read(tableHandle.api.columnWidthOverrides)
-- Include tableHandle.blueprint in the view tree; read widths() in a recipe.
```

Use `UI.Table(tableSpec)` for a table that does not need those imperative
readbacks. Do not introduce a manual handle solely to get a blueprint.

### Drag & drop

The table owns pickup, the insertion indicator, scrolling and drop input.
The model's `onReorder` command applies the proposed order. Game rules can refuse
a move; keep those rules in the model rather than duplicating drag machinery.

### Swipe actions on either edge

The example supplies Top on the leading edge and Remove on the trailing edge.
Only Remove opts into full-swipe commit. Keyboard and gamepad users reach those
same actions through the row-actions affordance. Destructive intent belongs in
the action's role, so the active theme supplies its treatment.

### Scrolling vs. reordering on touch

Let the table arbitrate the gesture. Its contribution distinguishes ordinary
scrolling from a deliberate reorder and owns cancellation. Adding a second
screen-local gesture detector would split that responsibility.

### Gamepad

The same table supports directional focus, row selection, sorting, column
resizing and row actions. The search field owns its editing context, so typing
or navigating inside an edit cannot also move table selection.

### Try it in the place

Open Playlist table. Filter a name, clear the filter, rate a track, sort a column,
resize it, play a row, move a row, and remove one. Restore makes the demonstration
repeatable. Change the viewport, preferred text size and theme without rebuilding
it. The headless tutorial spec drives these same controls and model commands.

## 4.3 Settings sync

**New concept over example 3: talking to a server — an optimistic mutation that
reconciles, with every step of the round trip on the screen.**

An audio-settings form (a Music toggle and a volume stepper) whose values the
server owns. This is the first example to use `Facet.replication`, and it
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

Under them sits:

- a **status** line (`idle` / `pending` / `accepted` / `rejected` with its reason)
- a **hint** line naming the next action
- the controls
- a short **history** of what happened, newest first

The lesson hides nothing behind a test handle: a player who has never read
the source can reach every state from the screen.

### Two layers of state

The **authoritative** state — what the server has confirmed — lives in a
snapshot. The **optimistic draft** — what the UI shows right now — lives in
plain signals that may run ahead of the server:

```lua
local snapshot    = replication.snapshot(core, 1, { music = false, volume = 10 })
local draftMusic  = core:signal(snapshot.binding:get().music)
local draftVolume = core:signal(snapshot.binding:get().volume)
```

The **mutation** ties them together. Its `optimistic.apply` runs the instant
you send, so the UI changes immediately. Its `optimistic.restore` re-syncs
the draft to server truth — used both on confirm (reconcile) and on reject
(rollback):

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

The "server" is a loopback table in the same file, exactly as a single-place
demo would use. It **queues** its answer and hands it over only when someone
presses the **Deliver server reply** button, because *when the answer lands*
is the thing this example is about. While a request is in flight, the draft
read-out already shows the new value, and the server read-out still shows the
old one.

The method is called `deliver`, not `flush`, on purpose. The gallery host
auto-flushes any `server.flush` every frame, which would answer before a
player could ever watch a request be pending.

When it processes a request, it applies the server's *validation rule*:
volume must be 0–10, which the UI deliberately does not enforce. On success,
it replicates the new snapshot **before** confirming, so the reconcile step
reads fresh truth:

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
off, volume 10). It does this by having the server *write those values again
at a new revision*, not by pretending the history never happened. A snapshot refuses an
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

The page scrolls, so every control stays reachable on a phone and at the
largest preferred-text setting. Touch, mouse, the arrow keys plus Return, and
a gamepad D-pad plus A all drive the same controls. The example wires none of
that — the presenter derives it from the layout. The full replication
contract is covered in [chapter 6](06-client-server.md).

---

## 4.4 Confirm dialog

**New concept: presentation is state; the Alert owns the modal behavior.**

[`04_confirm_dialog.luau`](../../examples/gallery/examples/04_confirm_dialog.luau)
keeps a local `open` value and declares an Alert beside the screen's content.
The declaration contributes no inline copy or layout gap. The Alert supplies
responsive sizing, safe initial focus, input routing and dismissal.

```luau
local open, setOpen = ui.state(false)
local hasSave, setHasSave = ui.state(true)

return UI.Screen {
    UI.Button { label = "Delete Save", enabled = hasSave, onActivate = function() setOpen(true) end },
    UI.Alert {
        title = "Delete this save?", message = "This cannot be undone.", severity = "critical",
        isPresented = open, onPresentedChange = setOpen,
        actions = {
            { id = "Delete", label = "Delete Save", role = "destructive",
              onActivate = function() setHasSave(false) end },
            { id = "Cancel", label = "Cancel", role = "cancel" },
        },
    },
}
```

**The answer has to be visible.** Confirming empties the save slot and offers
Restore; Cancel keeps the save. The full example records the outcome so both
answers are visible and the demonstration is repeatable. Gamepad B takes the cancel
route; focus returns to the original action. Roblox reserves Escape, so the
on-screen Cancel remains available to keyboard users.

For a single confirmed command, `UI.Button { confirm = { title = "Delete?" },
onActivate = deleteSave, ... }` is shorter. Use a bound Alert when the decision
has its own state or multiple actions; use a custom modal for a substantial task.

## 4.5 Word game

[`05_word_game.luau`](../../examples/gallery/examples/05_word_game.luau) separates
word validation and scoring from a mounted `WordGame` component. The game model
owns guesses, keyboard verdicts and the hardware input context. Its Core scope
outlives the results overlay; closing the example releases that scope.

The view borrows model values and shares a tile's derived verdict:

```luau
local rowsNow, activeNow = ui.read(rowsSig), ui.read(activeSig)
local state = ui.memo(function() return tileState(rowsNow(), activeNow(), r, c) end)
local tint = function() return TILE_TINT[state()] end
local mark = function() return TILE_MARK[state()] end
local tile = UI.ZStack {
    id = `tile{r}_{c}`, width = TILE, height = TILE,
    UI.Box { id = "fill", width = UI.fill(), height = UI.fill(), tint = tint },
    UI.Text { id = "mark", text = mark, textSize = "caption" },
}
```

The full example includes letters, a non-color mark for every verdict, and a
separate cue for the row accepting input. A `Grid` lays out the board; three
stacks lay out the keyboard. Custom keyboard hit targets use `Facet.UI.Button`
for compact glyph sizing and verdict paint. Ordinary actions such as New game
use `UI.Button` from `Facet.View`. Navigation still comes from Facet's solved
layout and semantic input system.

Try a short guess, an unknown word, a repeated letter and a completed game.
Refused guesses leave the current row intact. Closing the result card keeps the
board; starting another game resets the model. The tests drive the same hardware
commands and mounted node actions as the showcase.

## 4.6 Crossword tile game

[`06_tile_game.luau`](../../examples/gallery/examples/06_tile_game.luau) adds a
rack, tentative placements, word validation and scoring. The rules are pure
functions. Commands update shared game state in a transaction, while a
`Crossword` component owns the display's derived values.

**Refusal is feedback, with the exact problem named.** The rules distinguish nine
refusals. A refused submit keeps every tentative tile in place, so the player can
correct the problem without rebuilding the word. Validation also feeds a live
verdict before Submit is pressed. Use a memo for that shared work, and ordinary
getters for short presentation values:

```luau
local boardNow, pendingNow = ui.read(boardSig), ui.read(pendingSig)
local turnNow = ui.read(turnSig)
local verdict = ui.memo(function()
    local pending = pendingNow()
    if next(pending) == nil then return nil end
    return rules.validate(boardNow(), pending, turnNow())
end)
local wordText = function()
    local result = verdict()
    return if result then result.message else "No tiles placed this turn."
end
```

Cells and rack letters use custom primitive hit targets because their glyphs,
selected paint and cell surfaces are part of the board representation. Submit,
Undo and Start over are ordinary `View.Button` declarations. The board and rack
are ordered child arrays in uniform grids. Nothing calculates native GUI positions.

Try placing and taking back a tile, Undo, an invalid word, a valid crossing word
and Start over. The mounted example tests check input, board paint, deterministic
dealing, score and cleanup.

## 4.7 Match-3

[`07_match3.luau`](../../examples/gallery/examples/07_match3.luau) gives every tile
a stable id. Its model owns the board and the phase sequence: swap, mark, remove,
gravity, refill and land. A row component owns a tile's local presentation state.
The array order is deterministic, while identity follows the key.

```luau
local board = UI.Anchor {
    id = "board", overflow = "clip", width = BOARD_WIDTH, height = BOARD_HEIGHT,
    animation = { layout = "object" },
    UI.ForEach {
        id = "tiles", items = items, key = "id",
        row = function(item) return TileView { item = item } end,
        transition = { enter = "materialize", exit = "fade", class = "object" },
    },
}
```

The board's animation policy coordinates position changes automatically. Game
commands batch model changes; they do not wrap each swap or fall in
`withAnimation`. A tile's component reads its current position through a getter
and declares scaled offsets. Facet solves the target rectangles and animates the
presentation between them. Removing a key runs its exit transition and disposes
the row. Fading tile artwork uses a CanvasGroup; ordinary text outside that fade
stays native.

**Who drains the provider.** The example owns its artwork transport and delivers
the fixture once during build, so the board is playable immediately. The gallery
host does not drain the provider. Re-request artwork returns the tiles to pending;
Deliver artwork resolves them; Fail a load shows a named failure that re-request
can recover. Readable fallback labels distinguish the tile kinds while loading.
Try swaps by pointer drag, two taps, keyboard and gamepad. The tests cover legal
and rejected swaps, identity through falling, phase progression, resource states
and teardown. See [component authoring](15-components.md) for the same patterns
without the game rules.
