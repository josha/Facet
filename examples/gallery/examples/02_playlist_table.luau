--!strict
-- ============================================================================
-- Example 2 of the LuauUI tutorial: an iTunes-style playlist table.
-- ============================================================================
--
-- WHAT THIS TEACHES (combining the old star-rating and track-browser examples)
--   * the Table control  — keyed rows, columns that own their cells, a header
--   * custom cells       — an INTERACTIVE star-rating control living inside a
--                          table cell (ONE `newRating` control per row, not five
--                          buttons — see STAR CELL below for why that matters)
--   * reactive cells     — each star's glyph is bound to that track's rating
--                          signal, so a tap repaints exactly five labels and
--                          never rebuilds the row
--   * filter-as-you-type — a UI.TextInput above the table whose value drives a
--                          DERIVED (memo) rows list: typing filters the table
--                          reactively per keystroke; surviving rows keep their
--                          mounted identity; the in-field ✕ clears it
--   * SORTING, and the composition it forces — `sortOrder` is an owner-held
--                          Signal the header cycles; the TABLE NEVER SORTS THE
--                          DATA. So this example owns TWO derivations over ONE
--                          source array (sort over the source, filter over the
--                          sorted view) plus a third writer (drag reorder) that
--                          has to win against a live sort. See THE DERIVATION
--                          CHAIN below — getting that composition right IS the
--                          lesson
--   * RESIZABLE COLUMNS  — Name and Artist carry `resizable`, Rating REFUSES.
--                          A pointer drags the header divider, a keyboard steps
--                          it with , and . after Return on a heading, a gamepad
--                          bumper steps it outright — and all three commit
--                          through one model, `api.setColumnWidth`. The live
--                          width readout above the table is read from
--                          `api.columnWidthOverrides`, never from a copy
--   * drag & drop        — the Table's built-in row reordering: pick a row up
--                          past a small drag threshold and a ghost chip plus a
--                          drop line appear; releasing commits the new order
--                          through onReorder and THIS example re-orders its
--                          own data (the table never mutates your rows)
--   * the PRIMARY ACTION — `onPrimaryAction` (SwiftUI parity round 2 §3.4):
--                          "play this track", the verb that is NOT selection.
--                          Double-click on a mouse, Return on a keyboard, A /
--                          Cross on a gamepad, a single tap on touch
--   * SWIPE ACTIONS      — `rowActions` on BOTH edges (the iOS Mail idiom):
--                          swipe a row left for Remove, right for Top. They work
--                          OUTSIDE edit mode and are a DIFFERENT mechanism from
--                          edit mode's own per-row controls; edit mode then also
--                          shows a red ⊖ that leads to the same Remove
--
-- Interactions to try in the running place:
--   * type in the Filter field to narrow the list (case-insensitive, matches
--     anywhere in the track name); the ✕ clears it; focus + Activate works on
--     keyboard/gamepad too (the field is the first thing focus lands on)
--   * click a star, or press and DRAG left/right across the stars, to rate
--     (drag past the left edge to clear); focus + Activate also works
--   * tap a HEADING to sort by it (tap again to flip); drag the divider between
--     two headings to resize a column, or focus a heading and press Return then
--     , / . — the width line above the table is the only thing that can show a
--     resize happened, because a resize is a change and not a picture
--   * click rows to select them (multi-select: Cmd/Ctrl-click toggles
--     additively; on TOUCH, selection lives in edit mode, because a plain tap
--     plays the track — see THE PRIMARY ACTION below)
--   * DOUBLE-click a row (or focus it and press Return / A) to play it — the
--     "Now playing" line above the table names the track
--   * mouse: drag a row up or down to rearrange; wheel scrolls
--   * touch: tap the Edit button (auto-shown), then drag a row's ≡ handle to
--     rearrange; a plain drag on rows pans/scrolls the list
--   * SWIPE a row sideways — either way, and WITHOUT entering edit mode: left
--     reveals Remove (swipe all the way across to remove outright), right
--     reveals Top
--   * keyboard/gamepad reach those same two actions with no swipe to imitate:
--     Delete on a focused row runs Remove, Shift+Return opens its action menu
--   * gamepad: D-pad navigates the filter, rows, and stars, A (Cross on
--     PlayStation) activates; in edit mode A grabs the focused row, D-pad moves
--     it a slot per press, A again drops it
--   * NOTE: reordering is disabled while a filter is active (see below)
--
-- Module contract (same for every example in this folder):
--   returns { title, build(LuauUI, core, deps) } with
--   deps = { env, actionSystem, presenter, adapter }; build returns
--   { screen, present, ...handles } and the caller presents it.
-- ----------------------------------------------------------------------------

local example = {}
example.title = "Playlist Table"

-- the playlist data: id, display name, artist, starting rating (the track LENGTH
-- column was removed 2026-08-13 — see the columns list below for the
-- measurement that removed it; the field stays because Restore reseeds from here).
--
-- TWO ARTISTS ARE DELIBERATELY THE SAME. `table.sort` is not stable in Luau, so a
-- column with duplicate values is exactly where a sort stops being reproducible;
-- "Nine Volt" twice is what makes the source-index tie-break below observable
-- rather than theoretical.
local TRACKS = {
	{ id = "neon", name = "Neon Straightaway", artist = "Chrome Coyote", length = 214, rating = 4 },
	{ id = "drift", name = "Drift City Nights", artist = "Nine Volt", length = 187, rating = 3 },
	{ id = "turbo", name = "Turbo Cascade", artist = "Paper Lantern", length = 243, rating = 5 },
	{ id = "pit", name = "Pit Lane Shuffle", artist = "Rustbucket", length = 158, rating = 2 },
	{ id = "photo", name = "Photo Finish", artist = "Bad Weather", length = 201, rating = 0 },
	{ id = "apex", name = "Apex Bloom", artist = "Nine Volt", length = 176, rating = 3 },
}

function example.build(LuauUI: any, core: any, deps: any)
	local UI = LuauUI.UI

	-- STATE ------------------------------------------------------------------
	-- The FULL playlist order lives in one signal. Reordering writes a new
	-- array; the table's keyed rows move without rebuilding.
	local baseRows = core:signal(table.clone(TRACKS))
	-- The filter text is owner-held (the TextInput never creates its value).
	local filterText = core:signal("")
	-- THE PRIMARY ACTION'S RESULT. `nil` until a row is opened. It is a separate
	-- signal from the table's selection on purpose: selecting rows and playing one
	-- are two different verbs, and the whole point of `onPrimaryAction` is that the
	-- table stops having to overload the first to express the second.
	local nowPlaying = core:signal(nil :: string?)
	-- THE SORT BINDING, and the Table never touches the data through it
	-- (`spec.sortOrder`, SwiftUI's `Table(sortOrder:)`): tapping a sortable heading
	-- CYCLES this signal — new column → ascending, same column → flip — and that is
	-- the whole of the control's involvement. Re-sorting is the owner's job, which
	-- is this file's job, which is why the derivation chain below exists.
	local sortOrder = core:signal(nil :: { column: string, ascending: boolean }?)

	-- Each track's rating is its own signal, created once up front and looked
	-- up by track id. Star cells bind to these, so rating changes are pure
	-- paint — no row remount, no list rebuild.
	local ratings: { [string]: any } = {}
	for _, track in TRACKS do
		ratings[track.id] = core:signal(track.rating)
	end

	--[[ THE DERIVATION CHAIN, and its ORDER is the lesson ─────────────────────────

		Three things change what the table shows and they are NOT the same kind of
		thing:

		  · `baseRows` is the SOURCE — the stored playlist order. A drag reorder, a
		    Top swipe and a Remove swipe all write here.
		  · the SORT is a derivation over the source. It never writes.
		  · the FILTER is a derivation over the SORTED view. It never writes either.

		SORT FIRST, THEN FILTER, and that is not arbitrary. Filtering first would
		leave the full ordered list existing nowhere, and two things need it: "move
		this track to the top" has to name a position among ALL the tracks, and a
		manual reorder has to be able to BAKE what the player is looking at back into
		the source (see A MANUAL REORDER WINS below). Sorting a subset gives you
		neither.

		BOTH MEMOS HAND BACK THE ARRAY THEY WERE GIVEN when they have nothing to do
		(no sort, empty query). That is deliberate: an identical array means the
		table's keyed reconcile sees no change at all, so an unsorted, unfiltered
		playlist costs one comparison per solve rather than a copy. ]]
	local sortedRows = core:memo(function(use)
		local all = use(baseRows) :: { any }
		local order = use(sortOrder)
		if order == nil then
			return all
		end
		-- THE TIE-BREAK IS THE SOURCE INDEX, and it is not optional: `table.sort` is
		-- not stable in Luau, so two tracks with the same rating (or the same artist)
		-- would otherwise land in an order that is legal, different between Luau
		-- builds, and impossible to write a test against.
		local index: { [string]: number } = {}
		for i, track in all do
			index[track.id] = i
		end
		-- READ THE SORT KEY BEFORE SORTING, once per row. The rating key is a SIGNAL,
		-- so it has to be `use`d for this memo to re-run when a star is tapped — and
		-- calling `use` inside a comparator would do that O(n log n) times for the
		-- same answer.
		local keys: { [string]: any } = {}
		for _, track in all do
			if order.column == "rating" then
				keys[track.id] = use(ratings[track.id])
			elseif order.column == "artist" then
				keys[track.id] = track.artist
			else
				keys[track.id] = track.name
			end
		end
		local out = table.clone(all)
		table.sort(out, function(a, b)
			local av, bv = keys[a.id], keys[b.id]
			if av == bv then
				-- ties keep the source order, whichever way the column is pointing
				return index[a.id] < index[b.id]
			end
			if order.ascending then
				return av < bv
			end
			return av > bv
		end)
		return out
	end)

	-- The rows the table actually shows are a MEMO derived from (sortedRows,
	-- filterText): a case-insensitive substring match on the track name. Using
	-- `string.find(..., 1, true)` makes it a PLAIN substring test (no Lua
	-- pattern magic, so a filter like "." matches a literal dot). Because the
	-- table reads its `rows` reactively, editing the filter re-derives this and
	-- the table reconciles — surviving keys keep their mounted cells; only the
	-- rows that dropped out are removed.
	local filteredRows = core:memo(function(use)
		local query = string.lower(use(filterText))
		local all = use(sortedRows) :: { any }
		if query == "" then
			return all
		end
		local out = {}
		for _, track in all do
			if string.find(string.lower(track.name), query, 1, true) ~= nil then
				table.insert(out, track)
			end
		end
		return out
	end)

	--[[ A MANUAL REORDER WINS, AND TAKES THE SORT WITH IT (the iTunes rule).

		A drop names a SLOT among the visible rows. While a sort is live, that slot
		has no meaning against the stored order — write it and the very next solve
		sorts it away, so the drag would appear to do nothing at all. iTunes answers
		by dropping the column sort the moment you drag a row, and so do we.

		IT IS A BAKE, NOT A REFUSAL: the order the player is currently looking at
		becomes the stored order and `sortOrder` goes nil, so the drop's slot means
		exactly what was on screen when they let go. `sortedRows` is the FULL ordered
		list — never the filtered one — which is why the chain above sorts first.

		REMOVING a track is not a reorder and deliberately does NOT bake: deleting a
		row from a sorted list leaves a sorted list. ]]
	local function bakeManualOrder(): { any }
		if sortOrder:get() ~= nil then
			baseRows:set(table.clone(sortedRows:get() :: { any }))
			sortOrder:set(nil)
		end
		return baseRows:get() :: { any }
	end

	-- THE FILTER FIELD -------------------------------------------------------
	-- A real UI.TextInput. Its `value` IS `filterText`, so every accepted
	-- keystroke updates the signal the `filteredRows` memo reads — the filter
	-- is live by construction (no onChange plumbing needed). `clearButton`
	-- shows a trailing ✕ only while the field is non-empty; activating it
	-- empties `filterText` and the whole list returns.
	local filterControl = LuauUI.newTextInput(LuauUI, core, {
		id = "Filter",
		value = filterText,
		placeholder = "Filter tracks",
		clearButton = true,
		env = deps and deps.env,
		actionSystem = deps and deps.actionSystem,
	})

	-- STAR CELL --------------------------------------------------------------
	-- ONE CONTROL, NOT FIVE BUTTONS (director round 10, 2026-07-26).
	--
	-- This used to be five `UI.Button`s under a Grip, hand-rolled right here,
	-- and a device pass showed why that is the wrong shape: a Button is a
	-- `control` to every theme, so under Glossy Touch the rating rendered as
	-- five glossy PILLS, and under Glossy Mobile — whose control recipe is a
	-- raised SHADOW — the five shadows overlapped into the smeared dark band
	-- the director photographed behind the row. It was also five focus stops
	-- for one number, and five overlapping 44px hit expanders in one cell.
	--
	-- `newRating` is the framework control that replaced it: glyph Texts, which
	-- no theme paints a plate behind, under ONE Grip — so it is one focus stop,
	-- one effective target, and one place pointer input lands, while tap,
	-- drag-to-scrub and the keyboard/gamepad Adjust verb all reach the same
	-- arithmetic. See `docs/reference/api.md` §newRating.
	--
	-- Built ONCE PER TRACK and owned by this example, not inside the cell
	-- factory: a table may call a cell factory again on a re-solve, and building
	-- a control there would leak one control per call.
	local ratingControls: { [string]: any } = {}
	for _, track in TRACKS do
		ratingControls[track.id] = LuauUI.newRating(LuauUI, core, {
			id = "Rating",
			-- the live env, so the star run spaces itself for the input paradigm:
			-- wider between marks under touch, tighter under a pointer
			env = deps.env,
			value = ratings[track.id],
			count = 5,
		})
	end

	local function starCell(item: any)
		return ratingControls[item.id].blueprint
	end

	-- THE SWIPE ACTIONS' COMMANDS --------------------------------------------
	-- Both edit the SAME owner-held `baseRows` the drag-reorder drop writes, so
	-- this example has ONE order and three ways to change it. Both are written
	-- against the track ID rather than a row index, because a swipe can fire
	-- from a FILTERED view where the visible index says nothing about `baseRows`.
	local function removeTrack(id: string)
		local out = {}
		for _, track in baseRows:get() :: { any } do
			if track.id ~= id then
				table.insert(out, track)
			end
		end
		baseRows:set(out)
		-- a track that has left the playlist cannot still be the one playing
		for _, track in TRACKS do
			if track.id == id and nowPlaying:get() == track.name then
				nowPlaying:set(nil)
			end
		end
	end
	-- Move-to-top IS allowed while filtered and the drag-reorder drop below is
	-- not, and the two differ for a reason rather than by accident: a drop names
	-- a SLOT among the visible rows and the meaning of that slot against the
	-- hidden ones is genuinely ambiguous, while "put this at the top" names no
	-- slot at all and reads the same whatever is on screen.
	-- ...and it BAKES, for the reason `bakeManualOrder` states: a "put this first"
	-- that a live sort undoes in the same frame is a button that lies.
	local function moveToTop(id: string)
		local moved, rest = nil, {}
		for _, track in bakeManualOrder() do
			if track.id == id then
				moved = track
			else
				table.insert(rest, track)
			end
		end
		if moved == nil then
			return
		end
		table.insert(rest, 1, moved)
		baseRows:set(rest)
	end

	-- THE DROP'S COMMAND, named rather than inlined so the tests can drive the
	-- exact function the Table calls. `keys` are the dragged rows in document
	-- order and `toIndex` is the insertion slot among the rows NOT being dragged.
	local function reorder(keys: { string }, toIndex: number)
		if filterText:get() ~= "" then
			return -- a filter is active: moves are disabled, and the sort stays
		end
		local moving, staying = {}, {}
		local movingSet: { [string]: boolean } = {}
		for _, key in keys do
			movingSet[key] = true
		end
		for _, track in bakeManualOrder() do
			table.insert(if movingSet[track.id] then moving else staying, track)
		end
		local out = {}
		for i = 1, toIndex do
			table.insert(out, staying[i])
		end
		for _, track in moving do
			table.insert(out, track)
		end
		for i = toIndex + 1, #staying do
			table.insert(out, staying[i])
		end
		baseRows:set(out)
	end

	-- THE TABLE --------------------------------------------------------------
	-- Columns own their content: `value` renders a plain text cell; `cell`
	-- renders any blueprint — here, the interactive star control. `rows` is the
	-- DERIVED memo, so the table filters reactively.
	local tbl = LuauUI.newTable(LuauUI, core, {
		id = "Tracks",
		columns = {
			--[[ TWO `fill` COLUMNS THAT RESIZE, AND ONE FIXED ONE THAT REFUSES.
					This shape is load-bearing and it is not a style choice.

					`resolveDim` (src/controls/table.luau:1140-1144) turns ANY resized
					column into `{ type = "fixed", px }`. With the two columns this
					table used to have — a `fill` Name and a fixed Rating — pinning
					Name made BOTH fixed, so nothing was left to flex and the row
					under-filled its own region. Measured at 800x600 before the third
					column landed: pin Name to 200 and the header painted 16..216 and
					216..360 inside a band running 16..784 — 424px of dead space at the
					trailing edge, every time anyone dragged a divider.

					A THIRD `fill` column fixes it by construction: pin Name and ARTIST
					absorbs the slack, so Rating stays welded to the trailing edge.
					Same run at 800x600 with three: 16..216 / 216..640 / 640..784.

					`minWidth` FLOORS A RESIZE, NOT THE LAYOUT — a fact worth knowing
					before choosing these numbers. `resolveDim` applies `minWidth` to an
					OVERRIDE (and to a `percent` band); a plain `fill` column is divided
					by weight with no floor at all. So 90/72 is the narrowest a PLAYER
					may drag these to, not the narrowest they are ever drawn. It is
					explicit because the default is 24px, which is legible for nothing.
				]]
			{
				id = "name",
				title = "Name",
				width = { type = "fill", weight = 3 },
				minWidth = 90,
				resizable = true,
				-- the value can outgrow its cell at the narrowest viewport (see THE
				-- 320x640 MEASUREMENT below), so it declares itself disclosable: a
				-- truncated track name stays reachable rather than becoming lost
				disclose = true,
				value = function(item)
					return item.name
				end,
			},
			{
				id = "artist",
				title = "Artist",
				width = { type = "fill", weight = 2 },
				minWidth = 72,
				resizable = true,
				disclose = true,
				value = function(item)
					return item.artist
				end,
			},
			-- NO LENGTH COLUMN, AND IT IS THE SWIPE-ACTIONS ROUND THAT REMOVED IT
			-- (director device round 2026-08-13). A third FIXED column and a
			-- `fill` Name column share a row, so the Name column is whatever the
			-- fixed ones leave — and once this table gained `rowActions` with a
			-- destructive action, EDIT MODE spends two leading gutters on a row
			-- rather than one: 32px for the reorder ≡ plus the theme's own
			-- `editAffordance` gutter for the red ⊖. Measured on the narrowest
			-- viewport the overflow sweep covers (320x640, in edit mode) that
			-- left the Name CELL 6px wide and its text 0px, and the solver said
			-- so six times over: "content box collapses to 0px on x".
			--
			-- Removing the fixed 70px Length column is what gave the name room
			-- back, and the two alternatives were measured rather than argued.
			-- Narrowing the rating column to 120 also silenced the diagnostic but
			-- left the name 14px — legal and still unreadable — while breaking
			-- the measured 136px widest-touch-star-run this file documents below.
			-- Dropping Length gives 60px of name at 320x640 and 99px at 359x718.
			--
			-- AND IT WAS ALREADY WRONG BEFORE THE SWIPE ACTIONS, which is the
			-- part worth keeping: the same measurement on the shipped example at
			-- 320x640 in edit mode gave the name 26px — about two characters, no
			-- diagnostic, and nobody had looked. A track duration is the least
			-- valuable thing in a row whose subject is the track's NAME, and it
			-- taught nothing the Name column does not.
			--
			-- ...AND A THIRD COLUMN CAME BACK ON 2026-08-16, WHICH IS ONLY
			-- LEGITIMATE BECAUSE THE MEASUREMENT WAS REPEATED. Resize needs three
			-- columns to be non-degenerate (see the columns above), so the question
			-- was whether a `fill` Artist column is a different animal from the
			-- FIXED 70px Length column that was deleted. It is. Measured at
			-- 320x640, touch, EDIT MODE, all three shapes in the same session:
			--
			--   two columns (what shipped)      name cell 76 / text 60           0 collapse diagnostics
			--   third FIXED 70px (deleted)      name cell  6 / text  0           3 collapse diagnostics
			--   third FILL weight 2 (shipped)   name 46/30, artist 30/14         0 collapse diagnostics
			--
			-- So the fixed column collapsed the row's SUBJECT to nothing and the
			-- fill column does not; the price is the ARTIST cell at 14px of text at
			-- that one viewport in that one mode. That price is paid rather than
			-- hidden: both text columns carry `disclose = true`, so a truncated
			-- value is still reachable, and both truncate to ONE line rather than
			-- wrapping into a row that cannot hold them. The numbers are pinned in
			-- `tests/playlist_columns.spec.luau` so they cannot drift in silence.

			-- THE RATING COLUMN, AND WHY ITS WIDTH IS A FIXED NUMBER --------------
			-- FIXED, and it has to be for now. The director's 2026-07-27 note —
			-- "if the control's max width is 100px, then the hstack or table view
			-- might give the extra space to another control, like a text field,
			-- first" — is right, and this is where it would happen: now that a
			-- rating hugs its glyphs, 132 strands 64px under Compact Pointer, 36
			-- under Pixel Quest and 20 under Glossy Touch, in every viewport, while
			-- at 430px the name text wants 255px and gets 188.
			--
			-- 144, not 132: the run is spaced for the INPUT PARADIGM now, and a
			-- touch fingertip buys a wider gap between stars. Measured, the widest
			-- touch run is 136px (Glossy Touch and Fantasy Ornate, 20px glyphs), so
			-- 144 clears every package with slack instead of by luck.
			--
			-- `width = { type = "hug" }` was tried and is WRONG HERE: a table
			-- resolves its column widths per SECTION, so the header hugged the word
			-- "Rating" while the body hugged the star run and the two disagreed by
			-- 21px — the name column no longer lined up under its own heading. A
			-- content-sized table column has to be measured across the header AND
			-- the body together, which the control cannot do today; that is the
			-- follow-up, not a number to tune here.
			--
			-- Until then the leftover is at least no longer scattered BETWEEN the
			-- stars: the strip hugs and centres, so the slack sits either side of a
			-- run that reads as one rating.
			--
			-- ...AND IT IS THE COLUMN THAT REFUSES TO RESIZE, which is the same fact
			-- said once more: 144 is measured against a star run, so it is not the
			-- player's to drag. Declaring no `resizable` is the whole mechanism —
			-- the header grows no divider and `api.adjustTargets` walks resizable
			-- headings only, so no Adjust key binds while this heading holds focus
			-- ("binding Adjust on a header that cannot resize would shadow gameplay
			-- bumpers for nothing"). Both refusals are INVISIBLE, which is why the
			-- width readout says `locked` for this column rather than a number that
			-- never changes.
			--
			-- `sortable = true` is needed because this column has a `cell` and no
			-- `value`: a text column is sortable by its value for free, a custom
			-- cell has to opt in. It sorts by the rating SIGNAL, not by the seed in
			-- TRACKS, so re-rating a track re-orders the list under you.
			{
				id = "rating",
				title = "Rating",
				width = { type = "fixed", px = 144 },
				sortable = true,
				cell = starCell,
			},
		},
		-- a BLOCK, not a viewport: the page above scrolls it (see `screen` below)
		scrolls = false,
		rows = filteredRows,
		key = function(item)
			return item.id
		end,
		-- NO rowHeight, DELIBERATELY (director report 2026-07-27: "generally, we
		-- likely want taller table cells on mobile for touch targeting. that seems
		-- like the paradigm adaptation luauui should handle").
		--
		-- This used to say 48, with a comment explaining that a phone's narrow Name
		-- column wraps a real track title to two lines and 34 could not hold them.
		-- The reasoning was right and the SHAPE was wrong: it is a pixel count
		-- guessed once, on one device, at one text size — so on a phone whose text
		-- preference is raised a title wrapped to THREE lines and painted straight
		-- through the rows either side of it, which is what the device pass caught.
		--
		-- The framework owns it now. `UI.Table` derives the row from the theme's own
		-- per-paradigm row description and the live text scale: taller under touch
		-- (clearing the target floor for the drag handle, and holding the two-line
		-- wrap this comment always wanted), taller again when the player raises their
		-- text size, denser under a pointer. And whatever the height, the cells are
		-- capped to it, so nothing can spill out of a row again.
		-- ...and the gap BETWEEN rows is a spacing step for the same reason the row
		-- height is a theme decision: `2` was the same two pixels under a dense
		-- pointer package and a chunky touch one.
		rowGap = "controls.table.rowGap",
		header = true,
		-- THE OWNER HOLDS THE SORT AND APPLIES IT. Handing the table this Signal is
		-- what makes the headings tappable at all; everything the sort then does
		-- happens in `sortedRows` above, in this file.
		sortOrder = sortOrder,
		selection = "multi",
		-- THE PRIMARY ACTION (parity round 2 §3.4, corrected 2026-08-13). "Open
		-- this row" — here, play this track. The Table reaches it on all four
		-- inputs with no gesture this example has to invent: double-click on a
		-- mouse, Return on a keyboard, A / Cross on a gamepad, and a PLAIN SINGLE
		-- TAP on touch — the first tap, on any row, selected or not. That is
		-- Apple's own documented rule ("In iOS and iPadOS, tapping on the row
		-- activates the primary action"), not a divergence; a double-tap is a
		-- ZOOM gesture on a phone, which is why nobody uses it to open things.
		--
		-- THE PRICE, AND THIS EXAMPLE PAYS IT: once a table declares a primary
		-- action, a normal-mode touch tap no longer selects at all — it opens,
		-- and leaves any existing selection exactly alone. Touch selection moves
		-- into EDIT MODE, which is also where multi's tap-to-DESELECT lives. That
		-- is the same trade Apple makes deliberately.
		--
		-- THE COROLLARY, which matters more than the rule: if a table's dominant
		-- touch use is SELECTING rather than opening, do not declare a primary
		-- action on it at all. See `src/controls/table.luau`'s primary-action note.
		onPrimaryAction = function(item: any, _key: string)
			nowPlaying:set(item.name)
		end,
		reorderable = true,
		dragLabel = function(item)
			return item.name
		end,
		-- input-aware affordances: with the environment provided, touch users
		-- automatically get an Edit/Done toggle (reordering by handle) while
		-- mouse users keep direct row drags and wheel scrolling
		env = deps and deps.env,
		-- SWIPE ACTIONS, ON BOTH EDGES (`spec.rowActions`; SwiftUI's
		-- `swipeActions(edge:allowsFullSwipe:content:)` — §16 [SW-37]).
		--
		-- THIS IS NOT EDIT MODE, AND THAT IS THE POINT. Edit mode is a MODE you
		-- enter with the Edit button, and while it is on, rows grow a ≡ reorder
		-- handle and taps select. Swipe actions are a per-row GESTURE that works
		-- with the table sitting in its NORMAL state — no mode, no button, no
		-- selection change. Apple separates the two the same way: as of the
		-- 2026-08-13 citation pass, the `swipeActions` page says nothing about
		-- edit mode and the `EditMode`/`EditButton` pages say nothing about
		-- swiping. So this is a SECOND route to Remove, not a replacement for
		-- edit mode's ⊖ — which is exactly why `table.luau`'s auto-Edit predicate
		-- deliberately does NOT count `rowActions` as an edit-mode-only
		-- capability (see THE AUTO EDIT/DONE TOGGLE there).
		--
		-- WHICH EDGE GETS WHAT. Apple's default edge is trailing — "The default
		-- is `HorizontalEdge.trailing`" ([SW-37]) — and that is where a
		-- destructive action belongs, so Remove is trailing and Top is leading.
		--
		-- FULL SWIPE, PER EDGE. "By default, the user can perform the first
		-- action for a given swipe direction with a full swipe... You can opt out
		-- of this behavior for an edge by setting the `allowsFullSwipe` parameter
		-- to `false`. For example, you can disable the full swipe on the leading
		-- edge" ([SW-37]). We take Apple's own worked example: a full trailing
		-- swipe removes the track outright, and a full leading swipe does NOT
		-- silently re-order the playlist — Top stays reveal-then-tap.
		--
		-- IT COMPOSES WITH THE PRIMARY ACTION RATHER THAN FIGHTING IT. A tap
		-- plays the track; a sideways drag opens a tray and plays nothing; a
		-- mostly-vertical drag still scrolls the page. The axis lock decides
		-- which of the three a gesture is before any of them can fire
		-- (`row_actions.composeWithReorder`), so none of them has to know about
		-- the others.
		--
		-- ...AND IT IS REACHABLE WITHOUT A SWIPE. `newRowActions` binds Delete on
		-- the focused row to its destructive action and Shift+Return to the row's
		-- action menu, so a keyboard and a gamepad reach Remove and Top with no
		-- gesture to imitate. That is the four-input rule, not a bonus.
		rowActions = function(item: any)
			-- CAPTURE THE KEY, NOT THE ROW: a row's position in `baseRows` moves
			-- under it, and the id is the only thing that stays true.
			local id = item.id
			return {
				leading = {
					{
						id = "top",
						label = "Top",
						icon = "chevron.up",
						onAction = function()
							moveToTop(id)
						end,
					},
				},
				trailing = {
					{
						id = "remove",
						label = "Remove",
						icon = "trash",
						role = "destructive",
						onAction = function()
							removeTrack(id)
						end,
					},
				},
				fullSwipe = { leading = false, trailing = true },
			}
		end,
		-- The drop contract: `keys` are the dragged rows in document order and
		-- `toIndex` is the insertion slot among the rows NOT being dragged.
		-- REORDER-UNDER-FILTER RULE: reordering is DISABLED while a filter is
		-- active (the iTunes / SwiftUI convention). The visible rows are a
		-- SUBSET of the real order, so a drop's meaning against the hidden rows
		-- is ambiguous — rather than guess, we refuse the move and leave the
		-- base order untouched. Clear the filter to rearrange. When unfiltered,
		-- we apply the splice to the FULL `baseRows`.
		--
		-- REORDER-UNDER-SORT RULE, and it is the OPPOSITE answer to the same shape
		-- of question, on purpose: under a filter the drop is ambiguous, so we
		-- refuse; under a SORT it is perfectly well defined — every row is on
		-- screen, just in a different order — so we honour the drag and drop the
		-- SORT instead (`bakeManualOrder` above). Refusing a drag that carries no
		-- ambiguity would just be a table that ignores you.
		onReorder = reorder,
	})

	-- THE SCREEN -------------------------------------------------------------
	-- THE WHOLE PAGE SCROLLS, NOT JUST THE ROWS (director report 2026-07-27, this
	-- example in landscape: "just the table scrolls. really the whole view should
	-- scroll, as it's unusable having just the table scroll").
	--
	-- The title, filter and hint are a fixed block above the table. On a short
	-- landscape viewport they took 45-55% of the screen and the ONLY thing that
	-- could move was the rows, inside whatever was left — measured, a 144px row
	-- window on a 320px-tall screen.
	--
	-- So the page owns the scrolling and the table is a BLOCK (`scrolls = false`):
	-- every row lays out, nothing clips, and this ScrollView carries the lot —
	-- header included. That also avoids nesting a scroller inside a scroller,
	-- where a vertical drag over the rows is ambiguous and the inner one wins.
	-- RESTORE: the deterministic way back to the shipped playlist. Reordering rows
	-- and re-rating tracks are both destructive to the starting state, and before
	-- this there was no way back short of leaving the place (example-quality-pass
	-- play audit, 2026-08-06).
	local function restore()
		filterText:set("")
		sortOrder:set(nil)
		baseRows:set(table.clone(TRACKS))
		nowPlaying:set(nil)
		for _, track in TRACKS do
			ratings[track.id]:set(track.rating)
		end
	end

	--[[ THE TWO READOUTS A SCREENSHOT CANNOT CARRY ────────────────────────────────

		These moved here on 2026-08-16 from a fixture that existed only to hold them
		(`examples/gallery/scenarios/table_columns.luau`, retired in the same commit),
		and they are not decoration:

		  · A RESIZE IS A CHANGE, NOT A PICTURE. A table whose first column is 218px
		    and one whose first column was ALWAYS 218px are the same image. So the
		    committed width of every column is on screen, live, and it is read from
		    the control's OWN published state — `api.columnWidthOverrides`, the
		    Readable the model commits into — never from a copy this file keeps. That
		    matters most for the POINTER route, which commits inside the control and
		    fires no consumer callback at all: without this line a divider drag would
		    be unobservable from outside the table.
		  · SELECTING A COLUMN PAINTS NOTHING. `api.selectedColumn` is public "so a
		    consumer can paint the selection" and the control draws no state for it,
		    so after a device Activate on a heading the stick silently means something
		    new and the screen does not say so. The hint line below is both the demo
		    and the honest report of that gap. ]]
	local COLUMN_LABELS = { { "name", "Name", true }, { "artist", "Artist", true }, { "rating", "Rating", false } }

	local widthsText = core:memo(function(use)
		local overrides = use(tbl.api.columnWidthOverrides) :: { [string]: number }
		local parts = {}
		for _, column in COLUMN_LABELS do
			local id, label, resizable = column[1] :: string, column[2] :: string, column[3] :: boolean
			local px = overrides[id]
			-- the two NON-numeric states, and they are different facts: a resizable
			-- column nobody has moved yet, and a column that refuses to move at all
			local shown = if px ~= nil then `{math.floor(px + 0.5)}px` elseif resizable then "auto" else "locked"
			table.insert(parts, `{label} {shown}`)
		end
		return table.concat(parts, " · ")
	end)

	local hintText = core:memo(function(use)
		local selected = use(tbl.api.selectedColumn) :: string?
		if selected == nil then
			return "Type to filter · tap a heading to sort · drag a divider to resize · swipe a row for its actions"
		end
		local label = "Rating"
		for _, column in COLUMN_LABELS do
			if column[1] == selected then
				label = column[2] :: string
			end
		end
		--[[ THE KEYS THIS SENTENCE NAMES ARE THE ONES THAT ACTUALLY WORK, and the
			difference was measured live in Studio on 2026-08-14 rather than read off
			the control. `handleGrabNavigate` puts a selected column's resize on ←/→,
			and on the live showcase ←/→ NEVER ARRIVE: Roblox's own
			`RbxCameraKeypress` is bound to `KeyCode.Left`/`Right` at
			ContextActionService priority 2000 and sinks them. Proven by unbinding it
			in the same session — the identical two presses then stepped the column
			437px → 469px. `,` / `.` are the Adjust keys the presenter binds
			dynamically while a resizable header holds focus, and they are not
			contended. See docs/lessons/the-camera-still-owns-the-arrow-keys.md. ]]
		return `{label} has the keys: , and . resize it, ↑/↓ sorts`
	end)

	-- THE PRIMARY ACTION'S ONE VISIBLE CONSEQUENCE. `policy = "none"` text (§15.3):
	-- it declares no `lineLimit`, so a long track name under a ~1.4x localization
	-- expansion WRAPS inside the page rather than clipping. Its em dash is the
	-- localizable half of the string, which is why the whole sentence is built
	-- here rather than concatenated out of a label and a value at paint time.
	local nowPlayingText = core:memo(function(use)
		local track = use(nowPlaying)
		if track == nil then
			return "Nothing playing — double-click a row, or press Return on a focused one"
		end
		return `Now playing — {track}`
	end)

	-- STYLE AUTHORITY: typography ROLES and spacing STEPS, so the theme picker
	-- mounted beside this example actually moves it. `surface = "base"` gives the
	-- page a legible plate instead of floating the title and the secondary hint
	-- over the 3D world.
	local screen = UI.Screen({
		id = "Playlist",
		surface = "base",
		padding = "m",
		children = {
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "s",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.Text({ id = "Title", text = "Playlist", textSize = "title" }),
					filterControl.blueprint,
					-- the hint is the SELECTION READOUT and the instruction at once,
					-- because the control paints no state for a selected column and
					-- the two facts a player needs ("which column has the keys" and
					-- "what those keys do now") are the same sentence. No `lineLimit`,
					-- so it wraps under a ~1.4x localization expansion rather than
					-- clipping.
					UI.Text({
						id = "Hint",
						text = hintText,
						textSize = "label",
						role = "secondary",
						disclose = true,
					}),
					UI.Text({
						id = "NowPlaying",
						text = nowPlayingText,
						textSize = "label",
						role = "secondary",
					}),
					-- the live width of every column, read from the control's own
					-- published state: the only thing on this page that can show a
					-- resize HAPPENED
					UI.Text({
						id = "Widths",
						text = widthsText,
						textSize = "label",
						role = "secondary",
						disclose = true,
					}),
					tbl.blueprint,
					UI.Button({ id = "Restore", label = "Restore the original playlist", onActivate = restore }),
				},
			}),
		},
	})

	-- PRESENTER WIRING -------------------------------------------------------
	-- None. Both composites (the filter TextInput and the Table) attach input
	-- contributions to their root nodes, so mounting them is enough: the
	-- presenter auto-composes the whole screen's four-input story (ADR-0013).
	-- In document order the filter field's group comes first (so it is the
	-- initial focus), then the table's own row/toolbar/star groups — giving
	-- D-pad Up/Down between filter, rows and toolbar and Left/Right across a
	-- row's stars with no consumer nav map. Activate auto-dispatches to the
	-- filter field/clear, to a focused star (its node onActivate above), or to
	-- the table (row select, header); gamepad grab-move-drop (navigateIntercept),
	-- selection-follows-focus (focusMoved) and the filter's keyboard-occlusion
	-- keep-visible are all auto-wired from the contributions. This example
	-- therefore passes NO present() opts.

	return {
		screen = screen,
		-- handles the tutorial / tests reach for:
		rows = filteredRows, -- the DISPLAYED rows (sorted, then filtered)
		sortedRows = sortedRows, -- the full playlist in DISPLAY order (sort, no filter)
		baseRows = baseRows, -- the full STORED order (a reorder writes here)
		sortOrder = sortOrder, -- the owner-held sort binding the header cycles
		widths = widthsText, -- the live per-column width sentence
		hint = hintText, -- the instruction / selected-column readout
		reorder = reorder, -- the drop command the Table calls on a commit
		moveToTop = moveToTop, -- the leading swipe action's command
		removeTrack = removeTrack, -- the trailing swipe action's command
		filterText = filterText, -- the filter query (the field's value)
		filterControl = filterControl, -- the filter TextInput control
		nowPlaying = nowPlaying, -- the primary action's result (nil until a row opens)
		nowPlayingPath = "/Playlist/Page/NowPlaying",
		ratingFor = function(id: string)
			return ratings[id]
		end,
		table_ = tbl,
		restore = restore, -- the Restore button's command (order + ratings back)
		restorePath = "/Playlist/Page/Restore",
		dispose = function()
			tbl.dispose()
			filterControl.dispose()
			-- the rating CONTROLS before the signals they read: a control's own
			-- scope holds the glyph memos, and disposing the signal first would
			-- leave five memos observing a dead source
			for _, control in ratingControls do
				control.dispose()
			end
			nowPlayingText:dispose()
			-- the two readouts read the TABLE's published state, so they go before
			-- nothing in particular — but they do have to go, and they are the two
			-- easiest memos in this file to forget
			widthsText:dispose()
			hintText:dispose()
			-- ...and the derivation chain from the leaf back to its source: the
			-- filter reads the sort, the sort reads the base order and the ratings
			filteredRows:dispose()
			sortedRows:dispose()
			baseRows:dispose()
			sortOrder:dispose()
			filterText:dispose()
			nowPlaying:dispose()
			for _, rating in ratings do
				rating:dispose()
			end
		end,
	}
end

return example
