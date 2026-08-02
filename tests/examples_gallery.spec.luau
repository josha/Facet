--!strict
-- Documentation deliverable (design §17 Phase 4): the first FIVE progressive
-- tutorial examples, each a runnable, engine-free gallery module verified
-- headless under Lune. Every example module exports:
--     { title = "...", build = function(LuauUI, core, deps) ... end }
-- and build(...) returns { screen = <Blueprint>, present? = <presenter opts>,
-- ...example-specific handles }. deps is the uniform four-field table
--     { env, actionSystem, presenter, adapter }
-- (each example uses the subset it needs). These tests drive each example the
-- way a real client would — mount + render through the presenter and the
-- headless FakeTarget adapter, then exercise its primary interaction end to
-- end — and assert the reactive core stayed error-free throughout.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")

-- A complete headless stack: the same wiring a client bootstrap uses, minus
-- the Roblox-only adapters (FakeTarget stands in for ScreenTarget; the headless
-- action system stands in for the Input Action System).
local function makeHarness()
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	local deps = { env = env, actionSystem = system, presenter = presenter, adapter = adapter }
	return core, system, adapter, presenter, deps
end

local function countWindow(list: any): number
	local n = 0
	for _ in list.debugWindow() do
		n += 1
	end
	return n
end

-- 1. Temperature converter --------------------------------------------------
-- Now built on a REAL numeric UI.TextInput (the first Phase-5 control). The
-- field is the primary — and only — input affordance (the old stepper buttons
-- and Convert button are gone). It demonstrates the two edit modes side by
-- side: an onChange-driven LIVE preview and an onCommit-driven committed Result.

describe("examples/gallery 01: temperature converter (numeric TextInput)", function()
	local FIELD = "/TempConverter/Fahrenheit/Field"
	local function tempWorld()
		local ex = require("../examples/gallery/examples/01_temperature_converter")
		local core, _, adapter, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		return core, adapter, presenter, built, handle, deps
	end
	-- focus + open the engine text seam on the field (what a real focus does)
	local function edit(adapter: any)
		adapter.tap(FIELD)
		adapter.focusText(FIELD)
	end

	it("mounts headlessly with no core error", function()
		local core, adapter, presenter, _, handle = tempWorld()
		expect(adapter.node(FIELD) ~= nil).toBe(true)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("the numeric field is the primary affordance: no stepper or Convert buttons remain", function()
		local _, adapter, presenter, _, handle = tempWorld()
		expect(adapter.node("/TempConverter/InputRow/Plus10")).toBe(nil)
		expect(adapter.node("/TempConverter/InputRow/Minus1")).toBe(nil)
		expect(adapter.node("/TempConverter/Convert")).toBe(nil)
		expect(adapter.node(FIELD) ~= nil).toBe(true)
		expect(adapter.node(FIELD).props.keyboardType).toBe("numeric")
		presenter.dismiss(handle)
	end)

	it("LIVE mode: typing a valid number updates the Celsius preview WITHOUT committing the Result", function()
		local core, adapter, presenter, built, handle = tempWorld()
		edit(adapter)
		adapter.typeText(FIELD, "212") -- boiling
		presenter.refresh()
		-- onChange path: the live preview tracks each keystroke
		expect(built.liveCelsius:get()).toBe(100)
		expect(string.find(adapter.node("/TempConverter/Preview").props.text, "100", 1, true) ~= nil).toBeTruthy()
		-- commit path is untouched: nothing has been committed yet
		expect(built.celsius:get()).toBeNil()
		expect(adapter.node("/TempConverter/Result").props.text).toBe("Result: —")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("COMMIT mode: Enter commits the conversion into the Result (onCommit path)", function()
		local core, adapter, presenter, built, handle = tempWorld()
		edit(adapter)
		adapter.typeText(FIELD, "212")
		expect(built.celsius:get()).toBeNil() -- still only a preview
		adapter.commitText(FIELD) -- engine FocusLost(enterPressed)
		expect(built.celsius:get()).toBe(100)
		expect(built.field.api.editing:get()).toBe(false)
		presenter.refresh()
		expect(adapter.node("/TempConverter/Result").props.text).toBe("Result: 100 °C")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("COMMIT mode: focus loss (tapping away) also commits", function()
		local core, adapter, presenter, built, handle = tempWorld()
		edit(adapter)
		adapter.typeText(FIELD, "32") -- freezing
		adapter.blurText(FIELD) -- engine FocusLost, no Enter
		expect(built.celsius:get()).toBe(0)
		expect(built.field.api.editing:get()).toBe(false)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("the validate hook rejects non-numeric characters (value unchanged, no live update)", function()
		local core, adapter, presenter, built, handle = tempWorld()
		edit(adapter)
		adapter.typeText(FIELD, "9") -- accepted digit
		expect(built.fahrenheitText:get()).toBe("9")
		local liveAfterNine = built.liveCelsius:get()
		adapter.typeText(FIELD, "x") -- rejected: not numeric
		expect(built.fahrenheitText:get()).toBe("9") -- unchanged
		expect(built.liveCelsius:get()).toBe(liveAfterNine) -- no live update for the rejected edit
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("per-input activation: pointer tap and touch tap each enter edit mode", function()
		local _, adapter, presenter, built, handle = tempWorld()
		adapter.tap(FIELD) -- mouse/pointer
		expect(built.field.api.editing:get()).toBe(true)
		presenter.dismiss(handle)

		local _, adapter2, presenter2, built2, handle2 = tempWorld()
		adapter2.tap(FIELD, { pointer = "touch" }) -- touch rides the same seam
		expect(built2.field.api.editing:get()).toBe(true)
		presenter2.dismiss(handle2)
	end)

	it("per-input activation: keyboard Activate (Return) on the focused field enters edit mode", function()
		local _, _, presenter, built, handle, deps = tempWorld()
		expect(presenter.focus.focused:get()).toBe(FIELD) -- the field is the initial focus
		deps.actionSystem.deviceKey("Return", true)
		deps.actionSystem.deviceKey("Return", false)
		expect(built.field.api.editing:get()).toBe(true)
		presenter.dismiss(handle)
	end)

	it("per-input activation: gamepad A enters edit mode, B cancels reverting to the snapshot", function()
		local _, adapter, presenter, built, handle, deps = tempWorld()
		local sys = deps.actionSystem
		expect(presenter.focus.focused:get()).toBe(FIELD)
		sys.deviceKey("ButtonA", true) -- gamepad activate
		sys.deviceKey("ButtonA", false)
		expect(built.field.api.editing:get()).toBe(true)
		adapter.focusText(FIELD)
		adapter.typeText(FIELD, "5")
		expect(built.fahrenheitText:get()).toBe("5")
		sys.deviceKey("ButtonB", true) -- cancel: revert to the pre-edit snapshot ("")
		sys.deviceKey("ButtonB", false)
		expect(built.fahrenheitText:get()).toBe("")
		expect(built.field.api.editing:get()).toBe(false)
		presenter.dismiss(handle)
	end)
end)

-- 2. Star rating ------------------------------------------------------------

describe("examples/gallery 02: playlist table (director revision: rating + browser combined)", function()
	local function playlistWorld()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core, _, adapter, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		return core, adapter, presenter, built, handle
	end
	local function rowHit(key: string): string
		return `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/Row/Hit`
	end
	-- ONE CONTROL, NOT FIVE BUTTONS (director round 10, 2026-07-26). The rating
	-- cell is `LuauUI.newRating`, so the glyphs are Texts under a single Grip:
	-- `star()` still names a glyph to READ, but there is nothing to tap there —
	-- every input class lands on the strip.
	local function star(key: string, index: number): string
		return `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/Row/Cells/Cell-rating/Rating/Stars/Star{index}`
	end
	local function ratingStrip(key: string): string
		return `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/Row/Cells/Cell-rating/Rating/Strip`
	end
	local FILTER_FIELD = "/Playlist/Page/Filter/Field"
	local FILTER_CLEAR = "/Playlist/Page/Filter/ClearWhen/then/Clear"
	-- focus + open the engine text seam on the filter field, then type
	local function typeFilter(adapter: any, str: string)
		adapter.tap(FILTER_FIELD)
		adapter.focusText(FILTER_FIELD)
		adapter.typeText(FILTER_FIELD, str)
	end
	local function mountedRowKeys(adapter: any, rows: any): { string }
		local out: { string } = {}
		for _, track in rows:get() do
			if adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[{track.id}@0]/Row`) ~= nil then
				table.insert(out, track.id)
			end
		end
		return out
	end

	it("filter-as-you-type narrows the rows REACTIVELY, and clearing restores them all", function()
		local core, adapter, presenter, built, handle = playlistWorld()
		-- case-insensitive substring on track name: "drift" matches one track
		typeFilter(adapter, "drift")
		presenter.refresh()
		expect(#built.rows:get()).toBe(1)
		expect(built.rows:get()[1].id).toBe("drift")
		expect(adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[drift@0]/Row`) ~= nil).toBeTruthy()
		expect(adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[neon@0]/Row`)).toBe(nil)
		-- clear through the REAL tap path restores every row
		adapter.tap(FILTER_CLEAR)
		presenter.refresh()
		expect(#built.rows:get()).toBe(6)
		expect(adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[neon@0]/Row`) ~= nil).toBeTruthy()
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("case-insensitive match; surviving rows keep their mounted identity (no remount)", function()
		local core, adapter, presenter, built, handle = playlistWorld()
		-- capture a row that survives both filters below (Apex Bloom)
		local apexRowPath = `/Playlist/Page/Tracks/Main/Body/Rows/[apex@0]/Row`
		typeFilter(adapter, "A") -- upper-case query, lower-case data -> several match
		presenter.refresh()
		local apexBefore = adapter.node(apexRowPath)
		expect(apexBefore ~= nil).toBeTruthy()
		expect(#built.rows:get() > 1).toBeTruthy() -- Apex, Straightaway, Cascade, Lane...
		-- narrow to just Apex; the surviving row NODE is the same object (kept mounted)
		adapter.typeText(FILTER_FIELD, "pex")
		presenter.refresh()
		expect(#built.rows:get()).toBe(1)
		expect(built.rows:get()[1].id).toBe("apex")
		expect(adapter.node(apexRowPath)).toBe(apexBefore) -- reference equality: never remounted
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("the in-field clear (✕) exists ONLY while the filter is non-empty", function()
		local _, adapter, presenter, _, handle = playlistWorld()
		expect(adapter.node(FILTER_CLEAR)).toBe(nil) -- empty: no clear affordance
		typeFilter(adapter, "pit")
		presenter.refresh()
		expect(adapter.node(FILTER_CLEAR) ~= nil).toBeTruthy() -- non-empty: it appears
		adapter.tap(FILTER_CLEAR)
		presenter.refresh()
		expect(adapter.node(FILTER_CLEAR)).toBe(nil) -- cleared: gone again
		presenter.dismiss(handle)
	end)

	it("the handshake: typing in the filter field never navigates the table or moves selection", function()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core, _, adapter, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		local sys = deps.actionSystem
		-- focus + enter edit on the filter field
		adapter.tap(FILTER_FIELD)
		expect(built.filterControl.api.editing:get()).toBe(true)
		local focusBefore = presenter.focus.focused:get()
		-- while editing, D-pad is SUNK by the text-entry context: no row focus,
		-- no selection, the table's shortcuts never fire
		sys.deviceKey("DPadDown", true)
		sys.deviceKey("DPadDown", false)
		presenter.refresh()
		expect(presenter.focus.focused:get()).toBe(focusBefore) -- focus did not move
		local anySelected = false
		for _, track in built.rows:get() do
			if adapter.node(rowHit(track.id)).props.selected == true then
				anySelected = true
			end
		end
		expect(anySelected).toBe(false)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("reordering is DISABLED while a filter is active (iTunes/SwiftUI): the base order is preserved", function()
		local core, adapter, presenter, built, handle = playlistWorld()
		local baseBefore = {}
		for _, track in built.baseRows:get() do
			table.insert(baseBefore, track.id)
		end
		typeFilter(adapter, "a") -- a filter is now active (several rows match)
		presenter.refresh()
		-- attempt a drag reorder of the first visible row down past the second
		local visible = built.rows:get()
		local firstRect = adapter.node(rowHit(visible[1].id)).rect
		local secondRect = adapter.node(rowHit(visible[2].id)).rect
		adapter.pointerDown(rowHit(visible[1].id), 100, firstRect.y + 5)
		adapter.pointerMove(100, secondRect.y + secondRect.h - 2)
		presenter.refresh()
		adapter.pointerUp(100, secondRect.y + secondRect.h - 2)
		presenter.refresh()
		-- the underlying base order is UNCHANGED (the move was refused under filter)
		local baseAfter = {}
		for _, track in built.baseRows:get() do
			table.insert(baseAfter, track.id)
		end
		expect(table.concat(baseAfter, ",")).toBe(table.concat(baseBefore, ","))
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("per-input activation: keyboard/gamepad Activate on the focused filter field enters edit mode", function()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core, _, adapter, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		local sys = deps.actionSystem
		-- the filter field is prepended to the nav map, so it is the initial focus
		expect(presenter.focus.focused:get()).toBe(FILTER_FIELD)
		sys.deviceKey("Return", true) -- keyboard Activate
		sys.deviceKey("Return", false)
		expect(built.filterControl.api.editing:get()).toBe(true)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("mounts an iTunes-style table: name, length, and rating columns aligned under the header", function()
		local core, adapter, _, built = playlistWorld()
		expect(core:lastError()).toBeNil()
		local headerName = adapter.node("/Playlist/Page/Tracks/Main/Header/Head-name").rect
		local firstKey = built.rows:get()[1].id
		local nameCell = adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[{firstKey}@0]/Row/Cells/Cell-name`).rect
		expect(nameCell.x).toBe(headerName.x)
		expect(nameCell.w).toBe(headerName.w)
		-- length renders mm:ss
		local lengthText =
			adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[{firstKey}@0]/Row/Cells/Cell-length/Value`)
		expect(string.match(lengthText.props.text, "^%d+:%d%d$") ~= nil).toBeTruthy()
	end)

	it("tapping the rating INSIDE a table cell sets that track's rating and repaints without remount", function()
		local core, adapter, presenter, built, handle = playlistWorld()
		local key = built.rows:get()[1].id
		local runsBefore = handle.root.counters().factoryRuns
		local rect = adapter.node(ratingStrip(key)).rect
		adapter.pointerDown(ratingStrip(key), rect.x + rect.w * 0.7, rect.y + 5)
		adapter.pointerUp(rect.x + rect.w * 0.7, rect.y + 5)
		presenter.refresh()
		expect(built.ratingFor(key):get()).toBe(4)
		expect(adapter.node(star(key, 4)).props.text).toBe("★")
		expect(adapter.node(star(key, 5)).props.text).toBe("☆")
		expect(handle.root.counters().factoryRuns).toBe(runsBefore) -- paint-only
		adapter.pointerDown(ratingStrip(key), rect.x + rect.w * 0.3, rect.y + 5)
		adapter.pointerUp(rect.x + rect.w * 0.3, rect.y + 5)
		presenter.refresh()
		expect(built.ratingFor(key):get()).toBe(2)
		expect(core:lastError()).toBeNil()
	end)

	it("the stars are glyphs, so NO theme can paint a plate behind one", function()
		-- the defect: as five Buttons they classified as `control`, so a glossy
		-- package gave each star a pill and a shadow package gave each a drop
		-- shadow — five of which overlapped into a smeared band behind the row.
		local chrome_slots = require("../src/tokens/chrome_slots")
		local _, adapter, _, built = playlistWorld()
		local key = built.rows:get()[1].id
		for i = 1, 5 do
			local node = adapter.node(star(key, i))
			expect(node.class).toBe("Text")
			expect(chrome_slots.classify({ class = node.class, surface = node.props.surface })).toBeNil()
		end
	end)

	it("multi-select: tapping two rows keeps BOTH selected (additive toggle)", function()
		local core, adapter, presenter, built = playlistWorld()
		local first = built.rows:get()[1].id
		local second = built.rows:get()[2].id
		adapter.tap(rowHit(first))
		adapter.tap(rowHit(second))
		presenter.refresh()
		expect(adapter.node(rowHit(first)).props.selected).toBe(true)
		expect(adapter.node(rowHit(second)).props.selected).toBe(true)
		expect(core:lastError()).toBeNil()
	end)

	it("scrubbing left/right across the stars sets the rating live (pointer drag)", function()
		local core, adapter, presenter, built = playlistWorld()
		local key = built.rows:get()[1].id
		local scrub = ratingStrip(key)
		local rect = adapter.node(scrub).rect
		expect(rect ~= nil).toBeTruthy()
		-- press at ~90% across -> 5 stars
		adapter.pointerDown(scrub, rect.x + rect.w * 0.9, rect.y + 5)
		expect(built.ratingFor(key):get()).toBe(5)
		-- drag left to ~30% -> 2 stars (live scrub)
		adapter.pointerMove(rect.x + rect.w * 0.3, rect.y + 5)
		expect(built.ratingFor(key):get()).toBe(2)
		-- drag past the left edge -> clears to 0
		adapter.pointerMove(rect.x - 4, rect.y + 5)
		expect(built.ratingFor(key):get()).toBe(0)
		-- back to ~50% and release -> 3 stars committed
		adapter.pointerMove(rect.x + rect.w * 0.5, rect.y + 5)
		adapter.pointerUp(rect.x + rect.w * 0.5, rect.y + 5)
		presenter.refresh()
		expect(built.ratingFor(key):get()).toBe(3)
		expect(adapter.node(star(key, 3)).props.text).toBe("★")
		expect(core:lastError()).toBeNil()
	end)

	it("touch input auto-shows the Edit toggle; edit mode + handle drag reorders on touch", function()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core, _, adapter, presenter, deps = makeHarness()
		local env = deps.env
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		local togglePath = "/Playlist/Page/Tracks/Main/ToggleWhen/then/Toolbar/EditToggle"
		expect(adapter.node(togglePath)).toBe(nil) -- mouse: no toggle needed
		env:set("preferredInput", "Touch")
		presenter.refresh()
		expect(adapter.node(togglePath) ~= nil).toBeTruthy()
		built.table_.api.handleActivate(togglePath, nil)
		presenter.refresh()
		local first = built.rows:get()[1].id
		local second = built.rows:get()[2].id
		local handlePath = `/Playlist/Page/Tracks/Main/Body/Rows/[{first}@0]/Row/EditWhen/then/HandleZone/Handle`
		expect(adapter.node(handlePath) ~= nil).toBeTruthy()
		local handleRect = adapter.node(handlePath).rect
		-- DERIVED FROM THE ROW, not a literal. This drag was 60px, which crossed
		-- one 34px row; raising rowHeight to 48 for the phone made 60px land
		-- inside the SAME row and the test failed on a change that was correct.
		-- A reorder test should say "past the next row", not "60 pixels".
		local rowRect = adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[{first}@0]/Row`).rect
		local dropY = handleRect.y + 5 + rowRect.h * 1.5
		adapter.pointerDown(handlePath, handleRect.x + 5, handleRect.y + 5, "touch")
		adapter.pointerMove(handleRect.x + 5, dropY, "touch")
		presenter.refresh()
		adapter.pointerUp(handleRect.x + 5, dropY, "touch")
		presenter.refresh()
		expect(built.rows:get()[1].id).toBe(second)
		expect(built.rows:get()[2].id).toBe(first)
		presenter.dismiss(handle)
	end)

	it("GAMEPAD end to end: d-pad navigation, A to rate, grab-move-drop to reorder", function()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core, _, adapter, presenter, deps = makeHarness()
		local env = deps.env
		env:set("preferredInput", "Gamepad")
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		local system = deps.actionSystem
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
		end
		local first = built.rows:get()[1].id
		local second = built.rows:get()[2].id
		-- initial focus = the filter field (prepended nav group), then down into
		-- the toolbar, then into the rows
		expect(presenter.focus.focused:get()).toBe("/Playlist/Page/Filter/Field")
		press("DPadDown")
		expect(presenter.focus.focused:get()).toBe("/Playlist/Page/Tracks/Main/ToggleWhen/then/Toolbar/EditToggle")
		press("DPadDown")
		expect(presenter.focus.focused:get()).toBe(`/Playlist/Page/Tracks/Main/Body/Rows/[{first}@0]/Row/Hit`)
		-- right into the rating — ONE stop, not five, and the bumpers rate it.
		-- As five buttons this was three DPadRights to cross one cell and an A
		-- press per star; now the whole strip is the target and Adjust is the verb.
		press("DPadRight")
		expect(presenter.focus.focused:get()).toBe(ratingStrip(first))
		expect(built.ratingFor(first):get()).toBe(4) -- the fixture's starting value
		press("ButtonL1")
		presenter.refresh()
		expect(built.ratingFor(first):get()).toBe(3)
		-- back to the toggle, A enters edit mode
		press("DPadLeft")
		press("DPadUp")
		expect(presenter.focus.focused:get()).toBe("/Playlist/Page/Tracks/Main/ToggleWhen/then/Toolbar/EditToggle")
		press("ButtonA")
		presenter.refresh()
		-- down to the first row, A grabs, DPadDown moves it a slot, A drops
		press("DPadDown")
		press("ButtonA")
		expect(built.table_.api.grabbedKey:get()).toBe(first)
		press("DPadDown")
		presenter.refresh()
		expect(built.rows:get()[1].id).toBe(second)
		expect(built.rows:get()[2].id).toBe(first)
		-- focus stayed with the grabbed row (key-based path)
		expect(presenter.focus.focused:get()).toBe(`/Playlist/Page/Tracks/Main/Body/Rows/[{first}@0]/Row/Hit`)
		press("ButtonA")
		expect(built.table_.api.grabbedKey:get()).toBeNil()
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("GAMEPAD: selection follows focus across rows, even when focus sits on a star", function()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core, _, adapter, presenter, deps = makeHarness()
		deps.env:set("preferredInput", "Gamepad")
		local built = ex.build(LuauUI, core, deps)
		presenter.present(built.screen, built.present)
		presenter.refresh()
		local system = deps.actionSystem
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
		end
		local first = built.rows:get()[1].id
		local second = built.rows:get()[2].id
		local function hitOf(key: string): string
			return `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/Row/Hit`
		end
		press("DPadDown") -- filter field -> toolbar
		press("DPadDown") -- toolbar -> first row
		press("ButtonA") -- select it (not editing: action falls through to selection)
		presenter.refresh()
		expect(adapter.node(hitOf(first)).props.selected).toBe(true)
		press("DPadRight") -- onto the stars
		press("DPadDown") -- next row (column memory keeps us on its star)
		presenter.refresh()
		-- the director's rule: selection MOVES with focus
		expect(adapter.node(hitOf(second)).props.selected).toBe(true)
		expect(adapter.node(hitOf(first)).props.selected).toBe(false)
		expect(core:lastError()).toBeNil()
	end)

	it("drag & drop rearranges the playlist rows (post-removal reorder contract)", function()
		local core, adapter, presenter, built = playlistWorld()
		local order = {}
		for _, track in built.rows:get() do
			table.insert(order, track.id)
		end
		-- drag the FIRST row down past the second row's midpoint
		local firstRect = adapter.node(rowHit(order[1])).rect
		local secondRect = adapter.node(rowHit(order[2])).rect
		adapter.pointerDown(rowHit(order[1]), 100, firstRect.y + 5)
		adapter.pointerMove(100, secondRect.y + secondRect.h - 2) -- past threshold + slot 2
		presenter.refresh()
		adapter.pointerUp(100, secondRect.y + secondRect.h - 2)
		presenter.refresh()
		local after = {}
		for _, track in built.rows:get() do
			table.insert(after, track.id)
		end
		expect(after[1]).toBe(order[2])
		expect(after[2]).toBe(order[1])
		expect(after[3]).toBe(order[3])
		expect(core:lastError()).toBeNil()
	end)
end)

describe("examples/gallery 04: settings sync", function()
	it("mounts headlessly with no core error", function()
		local ex = require("../examples/gallery/examples/03_settings_sync")
		local core, _, _, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("a valid toggle applies optimistically, goes pending, then confirms", function()
		local ex = require("../examples/gallery/examples/03_settings_sync")
		local core, _, adapter, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)

		adapter.tap("/Settings/Music") -- flip the toggle
		expect(built.draftMusic:get()).toBe(true) -- optimistic apply
		expect(built.mutation.status:get()).toBe("pending")

		built.server.flush() -- the loopback "server" validates + replicates
		presenter.refresh()

		expect(built.mutation.status:get()).toBe("confirmed")
		expect(built.snapshot.binding:get().music).toBe(true)
		expect(built.draftMusic:get()).toBe(true)
		expect(adapter.node("/Settings/Status").props.text).toBe("Status: confirmed")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("a rejected change restores the optimistic draft to server truth", function()
		local ex = require("../examples/gallery/examples/03_settings_sync")
		local core, _, adapter, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)

		-- volume starts at its max (10); nudging up produces an invalid 11
		adapter.tap("/Settings/VolumeRow/VolPlus")
		expect(built.draftVolume:get()).toBe(11) -- optimistic
		expect(built.mutation.status:get()).toBe("pending")

		built.server.flush() -- server rejects the out-of-range value

		expect(built.mutation.status:get()).toBe("rejected")
		expect(built.draftVolume:get()).toBe(10) -- restored to server truth
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	-- Per-input proofs (ADR-0013): example 03 now carries NO present() opts —
	-- the toggle/steppers' node onActivate handlers are dispatched by the
	-- presenter, and the +/- HStack yields layout-derived 2D navigation. These
	-- close the touch / keyboard / gamepad cells that were UNPROVEN in the audit.
	local function ex03World()
		local ex = require("../examples/gallery/examples/03_settings_sync")
		local core, system, adapter, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		return core, system, adapter, presenter, built, handle
	end

	it("✓ ex03 touch: a touch tap on the Music toggle applies optimistically and goes pending", function()
		local core, _, adapter, presenter, built, handle = ex03World()
		adapter.tap("/Settings/Music", { pointer = "touch" })
		expect(built.draftMusic:get()).toBe(true)
		expect(built.mutation.status:get()).toBe("pending")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	-- DEVICE FINDING, iPhone 15 Pro, 2026-07-26: "I can toggle music on but not
	-- off." Nothing was flushing the loopback server, so the first change stayed
	-- pending forever — and `mutation.send` ERRORS while a request is in flight,
	-- so the control worked exactly once. The example is right to make the
	-- response explicit (that is what it teaches); the HOST is what was missing.
	it("✓ ex03: a second tap without a flush is refused — this is why the control worked once", function()
		local _, _, adapter, presenter, built, handle = ex03World()
		adapter.tap("/Settings/Music", { pointer = "touch" })
		expect(built.draftMusic:get()).toBe(true)
		expect(built.mutation.status:get()).toBe("pending")
		-- the second activation, with the first still in flight: it THROWS, which
		-- on the device surfaced as a control that simply stopped responding
		local ok, err = pcall(function()
			adapter.tap("/Settings/Music", { pointer = "touch" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "while a request is pending", 1, true) ~= nil).toBe(true)
		expect(built.draftMusic:get()).toBe(true) -- STILL on: the flip never happened
		presenter.dismiss(handle)
	end)

	it("✓ ex03: a host that delivers the response gets a toggle that goes both ways", function()
		local core, _, adapter, presenter, built, handle = ex03World()
		adapter.tap("/Settings/Music", { pointer = "touch" })
		built.server.flush() -- what the showcase host now does every frame
		expect(built.draftMusic:get()).toBe(true)
		expect(built.mutation.status:get()).toBe("confirmed")
		adapter.tap("/Settings/Music", { pointer = "touch" })
		built.server.flush()
		expect(built.draftMusic:get()).toBe(false) -- and back off again
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("✓ ex03 keyboard: Return on the focused Music toggle applies optimistically", function()
		local core, system, _, presenter, built, handle = ex03World()
		expect(presenter.focus.focused:get()).toBe("/Settings/Music") -- initial focus
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(built.draftMusic:get()).toBe(true)
		expect(built.mutation.status:get()).toBe("pending")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("✓ ex03 gamepad: ButtonA on the focused Music toggle applies optimistically", function()
		local core, system, _, presenter, built, handle = ex03World()
		expect(presenter.focus.focused:get()).toBe("/Settings/Music")
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		expect(built.draftMusic:get()).toBe(true)
		expect(built.mutation.status:get()).toBe("pending")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("✓ ex03 gamepad: D-pad reaches the volume steppers and ButtonA nudges the volume", function()
		local core, system, _, presenter, built, handle = ex03World()
		-- Music (a standalone vertical group) -> the +/- HStack (a horizontal
		-- group), auto-derived from layout: D-pad Down enters the stepper row.
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		expect(presenter.focus.focused:get()).toBe("/Settings/VolumeRow/VolMinus")
		system.deviceKey("ButtonA", true) -- activate the focused stepper
		system.deviceKey("ButtonA", false)
		expect(built.draftVolume:get()).toBe(9) -- 10 - 1, optimistic
		expect(built.mutation.status:get()).toBe("pending")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)
end)

-- 5. Confirmation dialog ----------------------------------------------------

describe("examples/gallery 05: confirmation dialog", function()
	it("mounts headlessly with no core error", function()
		local ex = require("../examples/gallery/examples/04_confirm_dialog")
		local core, _, _, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("opens a modal that traps focus, and ButtonB dismisses it and restores focus", function()
		local ex = require("../examples/gallery/examples/04_confirm_dialog")
		local core, system, _, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)

		expect(presenter.focus.focused:get()).toBe("/DangerScreen/Delete")
		-- activate the base button -> opens the confirmation modal
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(presenter.depth()).toBe(2)
		expect(presenter.focus.focused:get()).toBe("/ConfirmDialog/Card/Confirm")

		-- focus is trapped inside the modal: navigation moves Confirm<->Cancel
		-- and wraps, never escaping to the base screen
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(presenter.focus.focused:get()).toBe("/ConfirmDialog/Card/Cancel")
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(presenter.focus.focused:get()).toBe("/ConfirmDialog/Card/Confirm") -- wrapped

		-- ButtonB (gamepad B) is Cancel routing: dismiss + restore focus
		system.deviceKey("ButtonB", true)
		system.deviceKey("ButtonB", false)
		expect(presenter.depth()).toBe(1)
		expect(presenter.focus.focused:get()).toBe("/DangerScreen/Delete") -- restored
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("gamepad navigation to Cancel + activate reports a cancel and dismisses", function()
		local ex = require("../examples/gallery/examples/04_confirm_dialog")
		local core, system, _, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)

		system.deviceKey("ButtonA", true) -- open the modal (gamepad activate)
		system.deviceKey("ButtonA", false)
		expect(presenter.depth()).toBe(2)

		system.deviceKey("Down", true) -- move to Cancel
		system.deviceKey("Down", false)
		expect(presenter.focus.focused:get()).toBe("/ConfirmDialog/Card/Cancel")
		system.deviceKey("ButtonA", true) -- activate Cancel
		system.deviceKey("ButtonA", false)

		expect(built.result:get()).toBe("cancelled")
		expect(presenter.depth()).toBe(1)
		expect(presenter.focus.focused:get()).toBe("/DangerScreen/Delete")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	-- Per-input proofs (ADR-0013): example 04 now carries NO present() opts —
	-- the base Delete button and the modal's Confirm/Cancel buttons each carry
	-- their own node onActivate, dispatched by the presenter. These close the
	-- pointer + touch cells the audit left UNPROVEN (a modal example that never
	-- tested a real click/tap).
	local function ex04World()
		local ex = require("../examples/gallery/examples/04_confirm_dialog")
		local core, system, adapter, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		return core, system, adapter, presenter, built, handle
	end

	it("✓ ex04 pointer: tapping Delete opens the modal; tapping Cancel records cancelled and dismisses", function()
		local core, _, adapter, presenter, built, handle = ex04World()
		adapter.tap("/DangerScreen/Delete") -- mouse click opens the dialog
		expect(presenter.depth()).toBe(2)
		expect(presenter.focus.focused:get()).toBe("/ConfirmDialog/Card/Confirm")
		adapter.tap("/ConfirmDialog/Card/Cancel") -- a tap INSIDE the modal routes normally
		expect(built.result:get()).toBe("cancelled")
		expect(presenter.depth()).toBe(1)
		expect(presenter.focus.focused:get()).toBe("/DangerScreen/Delete") -- restored
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("✓ ex04 touch: a touch tap opens the modal and a touch tap on Confirm records confirmed", function()
		local core, _, adapter, presenter, built, handle = ex04World()
		adapter.tap("/DangerScreen/Delete", { pointer = "touch" })
		expect(presenter.depth()).toBe(2)
		adapter.tap("/ConfirmDialog/Card/Confirm", { pointer = "touch" })
		expect(built.result:get()).toBe("confirmed")
		expect(presenter.depth()).toBe(1)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)
end)
