--!strict
-- ============================================================================
-- Example 2 of the LuauUI tutorial: an iTunes-style playlist table.
-- ============================================================================
--
-- WHAT THIS TEACHES (combining the old star-rating and track-browser examples)
--   * the Table control  — keyed rows, columns that own their cells, a header
--   * custom cells       — an INTERACTIVE star-rating control living inside a
--                          table cell (five small buttons per row)
--   * reactive cells     — each star's glyph is bound to that track's rating
--                          signal, so a tap repaints exactly five labels and
--                          never rebuilds the row
--   * filter-as-you-type — a UI.TextInput above the table whose value drives a
--                          DERIVED (memo) rows list: typing filters the table
--                          reactively per keystroke; surviving rows keep their
--                          mounted identity; the in-field ✕ clears it
--   * drag & drop        — the Table's built-in row reordering: pick a row up
--                          past a small drag threshold and a ghost chip plus a
--                          drop line appear; releasing commits the new order
--                          through onReorder and THIS example re-orders its
--                          own data (the table never mutates your rows)
--   * the PRIMARY ACTION — `onPrimaryAction` (SwiftUI parity round 2 §3.4):
--                          "play this track", the verb that is NOT selection.
--                          Double-click on a mouse, Return on a keyboard, A /
--                          Cross on a gamepad, a single tap on touch
--
-- Interactions to try in the running place:
--   * type in the Filter field to narrow the list (case-insensitive, matches
--     anywhere in the track name); the ✕ clears it; focus + Activate works on
--     keyboard/gamepad too (the field is the first thing focus lands on)
--   * click a star, or press and DRAG left/right across the stars, to rate
--     (drag past the left edge to clear); focus + Activate also works
--   * click rows to select them (multi-select: Cmd/Ctrl-click toggles
--     additively; on TOUCH, selection lives in edit mode, because a plain tap
--     plays the track — see THE PRIMARY ACTION below)
--   * DOUBLE-click a row (or focus it and press Return / A) to play it — the
--     "Now playing" line above the table names the track
--   * mouse: drag a row up or down to rearrange; wheel scrolls
--   * touch: tap the Edit button (auto-shown), then drag a row's ≡ handle to
--     rearrange; a plain drag on rows pans/scrolls the list
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

-- the playlist data: id, display name, length in seconds, starting rating
local TRACKS = {
	{ id = "neon", name = "Neon Straightaway", length = 214, rating = 4 },
	{ id = "drift", name = "Drift City Nights", length = 187, rating = 3 },
	{ id = "turbo", name = "Turbo Cascade", length = 243, rating = 5 },
	{ id = "pit", name = "Pit Lane Shuffle", length = 158, rating = 2 },
	{ id = "photo", name = "Photo Finish", length = 201, rating = 0 },
	{ id = "apex", name = "Apex Bloom", length = 176, rating = 3 },
}

local function formatLength(seconds: number): string
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

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

	-- The rows the table actually shows are a MEMO derived from (baseRows,
	-- filterText): a case-insensitive substring match on the track name. Using
	-- `string.find(..., 1, true)` makes it a PLAIN substring test (no Lua
	-- pattern magic, so a filter like "." matches a literal dot). Because the
	-- table reads its `rows` reactively, editing the filter re-derives this and
	-- the table reconciles — surviving keys keep their mounted cells; only the
	-- rows that dropped out are removed.
	local filteredRows = core:memo(function(use)
		local query = string.lower(use(filterText))
		local all = use(baseRows) :: { any }
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

	-- Each track's rating is its own signal, created once up front and looked
	-- up by track id. Star cells bind to these, so rating changes are pure
	-- paint — no row remount, no list rebuild.
	local ratings: { [string]: any } = {}
	for _, track in TRACKS do
		ratings[track.id] = core:signal(track.rating)
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

	-- THE TABLE --------------------------------------------------------------
	-- Columns own their content: `value` renders a plain text cell; `cell`
	-- renders any blueprint — here, the interactive star control. `rows` is the
	-- DERIVED memo, so the table filters reactively.
	local tbl = LuauUI.newTable(LuauUI, core, {
		id = "Tracks",
		columns = {
			{
				id = "name",
				title = "Name",
				width = { type = "fill", weight = 1 },
				value = function(item)
					return item.name
				end,
			},
			{
				id = "length",
				title = "Length",
				width = { type = "fixed", px = 70 },
				value = function(item)
					return formatLength(item.length)
				end,
			},
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
			{ id = "rating", title = "Rating", width = { type = "fixed", px = 144 }, cell = starCell },
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
		-- The drop contract: `keys` are the dragged rows in document order and
		-- `toIndex` is the insertion slot among the rows NOT being dragged.
		-- REORDER-UNDER-FILTER RULE: reordering is DISABLED while a filter is
		-- active (the iTunes / SwiftUI convention). The visible rows are a
		-- SUBSET of the real order, so a drop's meaning against the hidden rows
		-- is ambiguous — rather than guess, we refuse the move and leave the
		-- base order untouched. Clear the filter to rearrange. When unfiltered,
		-- we apply the splice to the FULL `baseRows`.
		onReorder = function(keys: { string }, toIndex: number)
			if filterText:get() ~= "" then
				return -- a filter is active: moves are disabled
			end
			local moving, staying = {}, {}
			local movingSet: { [string]: boolean } = {}
			for _, key in keys do
				movingSet[key] = true
			end
			for _, track in baseRows:get() :: { any } do
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
		end,
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
		baseRows:set(table.clone(TRACKS))
		nowPlaying:set(nil)
		for _, track in TRACKS do
			ratings[track.id]:set(track.rating)
		end
	end

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
					UI.Text({
						id = "Hint",
						text = "Type to filter · tap stars to rate · drag rows to reorder",
						textSize = "label",
						role = "secondary",
					}),
					UI.Text({
						id = "NowPlaying",
						text = nowPlayingText,
						textSize = "label",
						role = "secondary",
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
		rows = filteredRows, -- the DISPLAYED rows (filtered view)
		baseRows = baseRows, -- the full ordered playlist (reorder writes here)
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
			filteredRows:dispose()
			baseRows:dispose()
			filterText:dispose()
			nowPlaying:dispose()
			for _, rating in ratings do
				rating:dispose()
			end
		end,
	}
end

return example
