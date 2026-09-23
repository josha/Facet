# 4. Tutorial: eight stages across seven example files

The library ships seven small example programs under
`examples/gallery/examples/`. The playlist example covers two distinct learning
stages, so the table below has eight numbered stages. Work through the files in
order and you will have used every major feature of Facet.

The Showcase picker has ten entries. **All controls** groups inputs, actions,
indicators and navigation in nested tabs. Its Status tab includes progress
rings and level indicators; Menus includes the journey stack, pages and
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
{ title = "...", build = function(ctx) ... end }
```

`ctx` is the host's context table. Its fields are `Facet`, `app`, `UI`,
`Compose`, `core`, `env`, `adapter`, `actionSystem` and `presenter`. `UI` is
`app.controls`; `Compose` is `Facet.Compose`. Each example uses only the pieces
it needs.

`build` returns either a component function or a table. A returned table may
carry `screen` (a component function), `present` (mount options), `dispose`, and
a `handle` when the example presented itself. There are two styles in the set:

- **Examples 1–5 hand the screen back to the caller.** Their `build` returns
  `{ screen = <component function>, ...readbacks }`, and the host shows it with
  `ctx.app.mount(built.screen)`. None of them pass mount options. The presenter
  composes each mounted control's four-input story (pointer, touch, keyboard,
  gamepad) from the tree, so there is no navigation map, activation router, or
  occlusion wiring to hand it.
- **Examples 6–8 present themselves.** Their `build` calls `ctx.app.mount(...)`
  internally and returns the resulting `handle` with a `dispose()` the host
  calls when finished. They do this because they manage their own lifetime (a
  game model, a results overlay) and pass their own mount options. Example 6
  also raises its own input context for the *hardware* keyboard. None of them
  wire navigation or activation by hand — the presenter derives 2D navigation
  from their layout and dispatches Activate to each control's own handler.

The file order:

| # | File | New idea it introduces |
|---|---|---|
| 1 | `01_temperature_converter.luau` | component state, reactive properties and controlled text entry |
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
is one component function using `app.controls`. Its cells belong to the mounted
screen. It describes the interface once; only reactive properties update.

```luau
local fahrenheit = Compose.cell("")
local celsius = Compose.cell(nil :: number?)
local function toCelsius(text)
    local n = tonumber(text)
    return if n then (n - 32) * 5 / 9 else nil
end
local liveCelsius = Compose.formula(function(use) return toCelsius(use(fahrenheit)) end)
```

### The two edit modes

A writable cell accepts live text edits, so the preview follows the text.
`onCommit` updates the final result on Enter or focus loss. The cell remains the
source of truth: `validate` can reject a proposed edit before it is accepted.

```luau
UI.TextInput("Fahrenheit")({
    value = fahrenheit,
    placeholder = "e.g. 212", keyboardType = "numeric",
    validate = function(proposed)
        return if string.match(proposed, "^%-?%d*%.?%d*$") then proposed else nil
    end,
    onCommit = function(text) celsius:set(toCelsius(text)) end,
})
```

The grammar accepts unfinished numbers such as `-` and `.` while refusing letters
and a second decimal point. `keyboardType` describes intent; it does not force a
Roblox keyboard layout. A rejected edit leaves the value unchanged.

### Reactive properties and shared work

Use a plain property function for formatting. `liveCelsius` is a formula because
both the preview and the example's readbacks need that derived number.

```luau
UI.Text("Preview")({
    role = "secondary",
    text = function(use)
        local c = use(liveCelsius)
        return if c == nil then "Preview: —" else string.format("Preview: %g °C", c)
    end,
})
UI.Button("Clear")({
    label = "Clear",
    onActivate = function()
        app.runtime:batch(function()
            fahrenheit:set("")
            celsius:set(nil)
        end)
    end,
})
```

### No presenter wiring

The mounted TextInput receives its environment and input integration from the
host. It owns editing, keyboard occlusion and cancellation. The example passes
no owner, runtime or input router into its tree. Closing the screen releases its
resources. Use typography roles and spacing steps so the same description follows
themes and the player's preferred text size.

## 4.2 Playlist table

**New concepts: shared model state, keyed rows, custom cells and table interactions.**

[`02_playlist_table.luau`](../../examples/gallery/examples/02_playlist_table.luau)
keeps the playlist order and ratings in model cells created outside the
component. Filtering or removing a mounted row does not destroy that track's
rating. The application releases the model at its lifetime boundary; the
`Playlist` component owns the mounted controls. This is the same separation to
use for an inventory or a server-backed catalog.

### The data

The model exposes `baseRows`, `sortOrder`, per-track ratings, and derived sorted
and filtered rows. Sorting is stable: equal values keep their original relative
order. A manual reorder first preserves the current displayed ordering, then
clears the sort. Restore resets the fixture's order, ratings, filter and selection.

### Filter-as-you-type over a derived rows list

A controlled search field binds the query. For component-local filtering, the
same idea is:

```luau
local query = Compose.cell("")
local filtered = Compose.formula(function(use)
    local matches = {}
    for _, track in use(tracks) do
        if string.find(string.lower(track.name), string.lower(use(query)), 1, true) then
            table.insert(matches, track)
        end
    end
    return matches
end)
local search = UI.TextInput {
    presentation = "search", value = query,
    placeholder = "Filter tracks",
}
```

`tracks` is a Compose readable, whether the component created it or the model
did. Use a formula because filtering does real work. Formatting a short label
usually needs only a property function. A plain substring search treats
punctuation as text, not a pattern.

### Reordering while filtered

The example refuses reordering while a filter is active: a visible subset cannot
unambiguously describe the full order. Clear the filter before moving rows.
The reorder callback uses the table's post-removal destination index.

### Columns own their cells

A `value` column renders a value. A `cell` column returns a view. A rating is one
adjustable control, so it gets one focus stop and the control's native input story:

```luau
local function starCell(item)
    return UI.Rating { value = ratings[item.id], count = 5 }
end
```

Here `ratings` holds writable model cells, which the control accepts directly.
Pair a read-only value with `onChange` when a model must approve the change
first. The mount owns each rating control; no cache of control handles or manual
disposal loop is needed.

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
concrete reason to ask this one control for its record:

```luau
local tracksApi
UI.Table("Tracks")({
    rows = rows, columns = columns,
    key = function(track) return track.id end,
    ref = function(record) tracksApi = record.api end,
})

UI.Text {
    text = function(use)
        local selected = use(tracksApi.selectedColumn)
        return if selected then `Sorted by {selected}` else "Unsorted"
    end,
}
```

`ref` must be a function. It runs once, while the control is built, with a
frozen `{ api, dump }`. Its `api` publishes readables such as
`columnWidthOverrides`, `hiddenColumns` and `selectedColumn`. Leave `ref` off a
table that needs no imperative readback.

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
plain cells that may run ahead of the server:

```lua
local snapshot    = replication.snapshot(core, 1, { music = false, volume = 10 })
local draftMusic  = Compose.cell(snapshot.binding:peek().music)
local draftVolume = Compose.cell(snapshot.binding:peek().volume)
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
            local truth = snapshot.binding:peek()
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
if mutation.status:peek() == "pending" then
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
local open = Compose.cell(false)
local hasSave = Compose.cell(true)

return UI.Screen {
    UI.Button { label = "Delete Save", enabled = hasSave, onActivate = function() open:set(true) end },
    UI.Alert {
        title = "Delete this save?", message = "This cannot be undone.", severity = "critical",
        isPresented = open,
        actions = {
            { id = "Delete", label = "Delete Save", role = "destructive",
              onActivate = function() hasSave:set(false) end },
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

Use a bound Alert whenever the decision has its own state or more than one
action. Use `UI.Sheet` or a modal component for a substantial task.

## 4.5 Word game

[`05_word_game.luau`](../../examples/gallery/examples/05_word_game.luau) separates
word validation and scoring from a mounted `WordGame` component. The game model
owns guesses, keyboard verdicts and the hardware input context. Its cells are
created outside the component, so they outlive the results overlay; closing the
example releases them.

The view reads model cells and shares a tile's derived verdict:

```luau
local state = Compose.formula(function(use)
    return tileState(use(rowsSig), use(activeSig), r, c)
end)
local tint = Compose.formula(function(use) return TILE_TINT[use(state)] end)
local mark = Compose.formula(function(use) return TILE_MARK[use(state)] end)
local tile = UI.ZStack(`tile{r}_{c}`)({
    width = TILE, height = TILE,
    UI.Box("fill")({ width = UI.fill(), height = UI.fill(), tint = tint }),
    UI.Text("mark")({ text = mark, textSize = "caption" }),
})
```

The full example includes letters, a non-color mark for every verdict, and a
separate cue for the row accepting input. `UI.Grid` lays out the board; three
stacks lay out the keyboard. Keyboard hit targets and ordinary actions such as
New game are both `UI.Button`; the compact keys set `surface` and a small
`textSize` for their glyph paint. Navigation still comes from Facet's solved
layout and semantic input system.

Try a short guess, an unknown word, a repeated letter and a completed game.
Refused guesses leave the current row intact. Closing the result card keeps the
board; starting another game resets the model. The tests drive the same hardware
commands and mounted node actions as the showcase.

## 4.6 Crossword tile game

[`06_tile_game.luau`](../../examples/gallery/examples/06_tile_game.luau) adds a
rack, tentative placements, word validation and scoring. The rules are pure
functions. Commands update shared game cells inside one
`app.runtime:batch(...)`, while a `Crossword` component owns the display's
derived values.

**Refusal is feedback, with the exact problem named.** The rules distinguish nine
refusals. A refused submit keeps every tentative tile in place, so the player can
correct the problem without rebuilding the word. Validation also feeds a live
verdict before Submit is pressed. Use a formula for that shared work, and plain
property functions for short presentation values:

```luau
local verdict = Compose.formula(function(use)
    local pending = use(pendingSig)
    if next(pending) == nil then return nil end
    return rules.validate(use(boardSig), pending, use(turnSig))
end)
local wordText = function(use)
    local result = use(verdict)
    return if result then result.message else "No tiles placed this turn."
end
```

Board cells and rack letters are `UI.Button` hit targets, because their glyphs,
selected paint and cell surfaces are part of the board representation. Submit,
Undo and Start over are ordinary `UI.Button` declarations too. The board and rack
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
local board = UI.Anchor("board")({
    overflow = "clip", width = BOARD_WIDTH, height = BOARD_HEIGHT,
    animation = { layout = "object" },
    UI.ForEach("tiles")({
        items = items,
        key = function(tile) return tile.id end,
        row = function(item) return TileView { item = item } end,
        transition = { enter = "materialize", exit = "fade", class = "object" },
    }),
})
```

`UI.ForEach` and `UI.When` take the schema-shaped spec only through a named
constructor: `UI.ForEach("tiles")({ items = ..., key = ..., row = ... })`. That
is the form whose `transition` reaches the transition coordinator.

The board's animation policy coordinates position changes automatically. Game
commands batch model changes; they do not wrap each swap or fall in
`withAnimation`. A tile's component reads its current position through a readable
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
