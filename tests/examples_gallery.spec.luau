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
	-- the page is a ScrollView now (example-quality-pass): the tutorial has to stay
	-- reachable on a short landscape phone, and the Clear button sits below the
	-- result. The paths gained one segment; the lesson did not change.
	local FIELD = "/TempConverter/Page/Fahrenheit/Field"
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
		expect(adapter.node("/TempConverter/Page/InputRow/Plus10")).toBe(nil)
		expect(adapter.node("/TempConverter/Page/InputRow/Minus1")).toBe(nil)
		expect(adapter.node("/TempConverter/Page/Convert")).toBe(nil)
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
		expect(string.find(adapter.node("/TempConverter/Page/Preview").props.text, "100", 1, true) ~= nil).toBeTruthy()
		-- commit path is untouched: nothing has been committed yet
		expect(built.celsius:get()).toBeNil()
		expect(adapter.node("/TempConverter/Page/Result").props.text).toBe("Result: —")
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
		expect(adapter.node("/TempConverter/Page/Result").props.text).toBe("Result: 100 °C")
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

	-- THE WAY BACK (example-quality-pass play audit, 2026-08-06). The example had
	-- no reset at all: once a value was typed the only route to the starting state
	-- was select-all-and-delete, which is neither discoverable nor a lesson.
	it("Clear returns the field, the live preview and the committed result to the start", function()
		local core, adapter, presenter, built, handle = tempWorld()
		edit(adapter)
		adapter.typeText(FIELD, "212")
		adapter.commitText(FIELD)
		presenter.refresh()
		expect(built.celsius:get()).toBe(100)
		expect(built.liveCelsius:get()).toBe(100)
		expect(adapter.node("/TempConverter/Page/Result").props.text).toBe("Result: 100 °C")
		adapter.tap(built.clearPath)
		presenter.refresh()
		expect(built.fahrenheitText:get()).toBe("")
		expect(built.liveCelsius:get()).toBeNil()
		expect(built.celsius:get()).toBeNil()
		expect(adapter.node("/TempConverter/Page/Result").props.text).toBe("Result: —")
		expect(adapter.node("/TempConverter/Page/Preview").props.text).toBe("Preview: —")
		expect(core:lastError()).toBeNil()
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

	-- CTRL-05a (api-architecture-consistency F-24). The gallery bootstrap's
	-- native-scroll auto-bind probed `value.bindNativeScroll` only, which is
	-- VirtualList's FLAT spelling; Table publishes the same seam under `api`, so
	-- this shipped example's body-scroll mirror was never bound and its reorder
	-- drag math went canvas-wrong the moment the body scrolled.
	it("the bootstrap auto-bind reaches a returned Table's api.bindNativeScroll", function()
		local core, adapter, presenter, built, handle = playlistWorld()
		-- the shape the bug was made of: flat on VirtualList, nested on Table
		expect(built.table_.bindNativeScroll).toBeNil()
		expect(type(built.table_.api.bindNativeScroll)).toBe("function")

		-- THE SHIPPED LOOP (examples/gallery/client/init.client.luau), run over
		-- the example's real return table
		local bound = 0
		for _, value in built :: any do
			if type(value) == "table" then
				local bind = (value :: any).bindNativeScroll
					or ((value :: any).api ~= nil and (value :: any).api.bindNativeScroll)
				if type(bind) == "function" then
					bind(handle.controller)
					bound += 1
				end
			end
		end
		expect(bound >= 1).toBe(true)

		-- and the mirror is LIVE: an engine canvas move lands in the control
		local bodyPath = built.table_.api.scrollPath()
		expect(bodyPath).toBe("/Playlist/Page/Tracks/Main/Body")
		adapter.driveScroll(bodyPath :: string, { x = 0, y = 120 })
		presenter.refresh()
		expect(built.table_.dump().scrollTop).toBe(120)
		expect(core:lastError()).toBeNil()
	end)

	it("the bootstrap's auto-bind probes BOTH spellings, in both loops (the source is the contract)", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("examples/gallery/client/init.client.luau")
		-- the nested spelling is probed at all...
		expect(string.find(source, "value.api.bindNativeScroll", 1, true) ~= nil).toBe(true)
		-- ...and ONE binder resolves it for BOTH loops (definition + two calls),
		-- so a future loop cannot regress to the flat-only probe by copy-paste
		local _, uses = string.gsub(source, "nativeScrollBinderOf", "")
		expect(uses >= 3).toBe(true)
		-- and no loop reaches for the flat spelling on its own any more
		expect(string.find(source, "value :: any).bindNativeScroll", 1, true)).toBeNil()
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

	-- THE WAY BACK (example-quality-pass play audit, 2026-08-06). Reordering rows
	-- and re-rating tracks are both destructive to the shipped playlist, and there
	-- was no route back short of leaving the place.
	it("Restore puts the original order and every original rating back", function()
		local core, _, adapter, presenter, deps = makeHarness()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		local startOrder = {}
		for _, track in built.baseRows:get() do
			table.insert(startOrder, track.id)
		end
		local startRating = built.ratingFor(startOrder[1]):get()
		-- disturb both: a reorder and a rating change, plus a live filter
		local moved = table.clone(built.baseRows:get())
		table.insert(moved, table.remove(moved, 1))
		built.baseRows:set(moved)
		built.ratingFor(startOrder[1]):set(if startRating == 5 then 1 else 5)
		built.filterText:set("nights")
		presenter.refresh()
		expect(built.baseRows:get()[1].id ~= startOrder[1]).toBe(true)
		adapter.tap(built.restorePath)
		presenter.refresh()
		local after = {}
		for _, track in built.baseRows:get() do
			table.insert(after, track.id)
		end
		expect(table.concat(after, "|")).toBe(table.concat(startOrder, "|"))
		expect(built.ratingFor(startOrder[1]):get()).toBe(startRating)
		expect(built.filterText:get()).toBe("")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)
end)

describe("examples/gallery 04: settings sync", function()
	-- THE WHOLE LESSON HAS TO BE REACHABLE FROM THE SCREEN (example-quality-pass
	-- §"Example 03"). The live play audit found this example dead-ending: one tap
	-- on `+` gave `Volume: 11` / `Status: pending` and nothing on screen could
	-- ever deliver, accept, reject, roll back or reset it, because the loopback
	-- server's `flush()` was a returned TEST HANDLE with no control behind it.
	--
	-- So these tests drive the example the way a player does — through named
	-- controls only — and assert the seven promised states as VISIBLE TEXT.
	local PAGE = "/Settings/Page"
	local MUSIC = PAGE .. "/Music"
	local VOL_MINUS = PAGE .. "/VolumeRow/VolMinus"
	local VOL_PLUS = PAGE .. "/VolumeRow/VolPlus"
	local VOL_VALUE = PAGE .. "/VolumeRow/VolValue"
	local ASK_INVALID = PAGE .. "/AskInvalid"
	local DELIVER = PAGE .. "/Deliver"
	local RESET = PAGE .. "/Reset"
	local DRAFT = PAGE .. "/State/Draft"
	local SERVER = PAGE .. "/State/Server"
	local STATUS = PAGE .. "/Status"
	local HINT = PAGE .. "/Hint"
	local EVENT1 = PAGE .. "/History/Event1"
	local EVENT2 = PAGE .. "/History/Event2"

	local function ex03World()
		local ex = require("../examples/gallery/examples/03_settings_sync")
		local core, system, adapter, presenter, deps = makeHarness()
		local built = ex.build(LuauUI, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		return core, system, adapter, presenter, built, handle
	end

	-- what the PLAYER reads off the screen: the rendered prop, after a refresh,
	-- never the signal behind it
	local function shown(adapter: any, presenter: any, path: string): string
		presenter.refresh()
		local node = adapter.node(path)
		if node == nil then
			return `<no node at {path}>`
		end
		return tostring(node.props.text)
	end

	it("mounts headlessly with no core error", function()
		local core, _, _, presenter, _, handle = ex03World()
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("every state the tutorial promises has an on-screen control", function()
		local _, _, adapter, presenter, _, handle = ex03World()
		for _, path in { MUSIC, VOL_MINUS, VOL_PLUS, ASK_INVALID, DELIVER, RESET } do
			local node = adapter.node(path)
			expect(node ~= nil).toBe(true)
			expect(node.onActivate ~= nil).toBe(true)
		end
		presenter.dismiss(handle)
	end)

	-- THE ACCEPTANCE DRIVE. Seven states, on-screen controls only — no
	-- `built.server`, no signal writes, no direct handler calls.
	it("the seven promised states are reachable through on-screen controls alone", function()
		local core, _, adapter, presenter, _, handle = ex03World()

		-- 1. draft and authoritative state are distinguishable at rest
		expect(shown(adapter, presenter, DRAFT)).toBe("Music off, volume 10")
		expect(shown(adapter, presenter, SERVER)).toBe("Music off, volume 10 (revision 1)")
		expect(shown(adapter, presenter, STATUS)).toBe("Status: idle")

		-- 2. trigger a change the server will accept
		adapter.tap(VOL_MINUS)

		-- 3. the optimistic value is visible IMMEDIATELY, and the server's is not
		expect(shown(adapter, presenter, DRAFT)).toBe("Music off, volume 9")
		expect(shown(adapter, presenter, SERVER)).toBe("Music off, volume 10 (revision 1)")
		expect(shown(adapter, presenter, VOL_VALUE)).toBe("Volume: 9")
		expect(shown(adapter, presenter, STATUS)).toBe("Status: pending (no reply yet)")

		-- 4. deliver the acceptance; the two values reconcile
		adapter.tap(DELIVER)
		expect(shown(adapter, presenter, STATUS)).toBe("Status: accepted")
		expect(shown(adapter, presenter, DRAFT)).toBe("Music off, volume 9")
		expect(shown(adapter, presenter, SERVER)).toBe("Music off, volume 9 (revision 2)")

		-- 5. trigger a change the server will refuse
		adapter.tap(ASK_INVALID)
		expect(shown(adapter, presenter, DRAFT)).toBe("Music off, volume 99")
		expect(shown(adapter, presenter, STATUS)).toBe("Status: pending (no reply yet)")

		-- 6. the rejection carries its REASON, and the draft rolls back
		adapter.tap(DELIVER)
		expect(shown(adapter, presenter, STATUS)).toBe("Status: rejected (volume must be 0..10)")
		expect(shown(adapter, presenter, DRAFT)).toBe("Music off, volume 9")
		expect(shown(adapter, presenter, SERVER)).toBe("Music off, volume 9 (revision 2)")

		-- 7. reset returns the demonstration to its documented start state
		adapter.tap(RESET)
		expect(shown(adapter, presenter, STATUS)).toBe("Status: idle")
		expect(shown(adapter, presenter, DRAFT)).toBe("Music off, volume 10")
		expect(shown(adapter, presenter, SERVER)).toBe("Music off, volume 10 (revision 3)")

		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("the status line names the next action at every step", function()
		local _, _, adapter, presenter, _, handle = ex03World()
		expect(shown(adapter, presenter, HINT)).toBe("Change a setting to send a request.")
		adapter.tap(MUSIC)
		expect(shown(adapter, presenter, HINT)).toBe('Your screen already shows it. Press "Deliver server reply".')
		adapter.tap(DELIVER)
		expect(shown(adapter, presenter, HINT)).toBe("Draft and server agree.")
		adapter.tap(ASK_INVALID)
		adapter.tap(DELIVER)
		expect(shown(adapter, presenter, HINT)).toBe("The server refused it, so the draft rolled back.")
		presenter.dismiss(handle)
	end)

	it("a valid toggle applies optimistically, goes pending, then confirms", function()
		local core, _, adapter, presenter, built, handle = ex03World()

		adapter.tap(MUSIC) -- flip the toggle
		expect(built.draftMusic:get()).toBe(true) -- optimistic apply
		expect(built.mutation.status:get()).toBe("pending")
		expect(built.snapshot.binding:get().music).toBe(false) -- server unmoved

		adapter.tap(DELIVER) -- the loopback "server" validates + replicates

		expect(built.mutation.status:get()).toBe("confirmed")
		expect(built.snapshot.binding:get().music).toBe(true)
		expect(built.draftMusic:get()).toBe(true)
		expect(built.snapshot.revision()).toBe(2)
		expect(shown(adapter, presenter, STATUS)).toBe("Status: accepted")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("a rejected change restores the optimistic draft to server truth", function()
		local core, _, adapter, presenter, built, handle = ex03World()

		-- volume starts at its max (10); nudging up produces an invalid 11
		adapter.tap(VOL_PLUS)
		expect(built.draftVolume:get()).toBe(11) -- optimistic
		expect(built.mutation.status:get()).toBe("pending")

		adapter.tap(DELIVER) -- server refuses the out-of-range value

		expect(built.mutation.status:get()).toBe("rejected")
		expect(built.draftVolume:get()).toBe(10) -- restored to server truth
		expect(built.snapshot.revision()).toBe(1) -- and the server never moved
		expect(shown(adapter, presenter, STATUS)).toBe("Status: rejected (volume must be 0..10)")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("reset recovers from a request the server never answered", function()
		local core, _, adapter, presenter, built, handle = ex03World()
		adapter.tap(ASK_INVALID)
		expect(built.mutation.status:get()).toBe("pending")

		adapter.tap(RESET) -- abandons the in-flight request and rolls it back

		expect(built.mutation.status:get()).toBe("idle")
		expect(built.draftVolume:get()).toBe(10)
		expect(built.draftMusic:get()).toBe(false)
		expect(shown(adapter, presenter, DRAFT)).toBe("Music off, volume 10")
		-- the abandoned reply can still arrive and must change nothing
		adapter.tap(DELIVER)
		expect(built.mutation.status:get()).toBe("idle")
		expect(built.draftVolume:get()).toBe(10)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	-- DEVICE FINDING, iPhone 15 Pro, 2026-07-26: "I can toggle music on but not
	-- off." `mutation.send` ERRORS while a request is in flight, so the control
	-- worked exactly once and then threw. The example now refuses the second
	-- change IN THE EXAMPLE and says why on screen — a tutorial must not throw at
	-- a player for pressing a button twice.
	it("a second change while one is in flight is refused visibly, and never throws", function()
		local core, _, adapter, presenter, built, handle = ex03World()
		adapter.tap(MUSIC)
		expect(built.mutation.status:get()).toBe("pending")

		local ok = pcall(function()
			adapter.tap(MUSIC)
		end)

		expect(ok).toBe(true)
		expect(built.draftMusic:get()).toBe(true) -- unchanged: nothing was sent
		expect(built.mutation.status:get()).toBe("pending")
		expect(shown(adapter, presenter, EVENT1)).toBe("Already waiting for a reply. Deliver it first.")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("Deliver with nothing in flight explains itself instead of doing nothing", function()
		local core, _, adapter, presenter, _, handle = ex03World()
		adapter.tap(DELIVER)
		expect(shown(adapter, presenter, STATUS)).toBe("Status: idle")
		expect(shown(adapter, presenter, EVENT1)).toBe("Nothing to deliver. Send a change first.")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("the visible history reads newest first and is bounded", function()
		local core, _, adapter, presenter, built, handle = ex03World()
		expect(shown(adapter, presenter, EVENT1)).toBe("Ready. Nothing sent yet.")

		adapter.tap(VOL_MINUS)
		expect(shown(adapter, presenter, EVENT1)).toBe("Sent volume 9. Waiting for the server.")
		expect(shown(adapter, presenter, EVENT2)).toBe("Ready. Nothing sent yet.")

		adapter.tap(DELIVER)
		expect(shown(adapter, presenter, EVENT1)).toBe("Server accepted. Revision 2.")
		expect(shown(adapter, presenter, EVENT2)).toBe("Sent volume 9. Waiting for the server.")

		-- bounded: the visible log never grows past the rows the screen has
		for _ = 1, 6 do
			adapter.tap(MUSIC)
			adapter.tap(DELIVER)
		end
		expect(#built.history:get()).toBe(3)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	-- COMPACT PHONE, BOTH ORIENTATIONS, BOTH ENDS OF THE TEXT PREFERENCE.
	-- The solver is asked, not the screenshot (docs/lessons/the-solver-already-
	-- told-you.md): a fixture that never reads `controller.diagnostics()` is not
	-- a fixture. 360x633 is a 360x691 phone minus the 58px topbar inset.
	it("stays laid out and operable on a compact phone at every text size", function()
		local lt = require("./lib/large_text")
		local ex = require("../examples/gallery/examples/03_settings_sync")
		for _, theme in lt.THEMES do
			for _, offset in { 0, lt.LARGEST } do
				for _, view in
					{
						{ name = "portrait", rect = { x = 0, y = 0, w = 360, h = 633 } },
						{ name = "landscape", rect = { x = 0, y = 0, w = 667, h = 317 } },
					}
				do
					local w = lt.world({ viewport = view.rect, offset = offset, input = "touch", theme = theme })
					local built = ex.build(
						LuauUI,
						w.core,
						{ env = w.env, actionSystem = w.system, presenter = w.pres, adapter = w.adapter }
					)
					w.present(built.screen, built.present)
					local label = `{theme.id} {view.name} @ +{offset}px`
					local sweep = lt.sweep(w, "/Settings")
					if #sweep.overlaps > 0 then
						error(`{label}: painted siblings overlap\n{lt.describeFindings(label, sweep.overlaps)}`, 0)
					end
					if #sweep.clipped > 0 then
						error(`{label}: essential text clipped\n{lt.describeFindings(label, sweep.clipped)}`, 0)
					end
					-- The Music Toggle paints 134x28 under the default theme — a
					-- bare UI.Toggle does that on ANY screen, so it is a
					-- framework/theme baseline, not this example's doing.
					-- Everything the EXAMPLE sizes must clear the floor.
					for _, finding in sweep.hitFloor do
						if finding.node ~= "/Settings/Page/Music" then
							error(`{label}: under the target floor\n{lt.describeFindings(label, { finding })}`, 0)
						end
					end
					expect(#w.handle.controller.diagnostics()).toBe(0)

					-- the volume read-out has to have a box: `fill` inside a
					-- content-sized row solved to 0 wide, and the number vanished
					local value = w.adapter.node("/Settings/Page/VolumeRow/VolValue")
					expect(value.rect.w > 0).toBe(true)
					expect(value.rect.h > 0).toBe(true)

					-- and the last control is reachable: the page scrolls over its
					-- whole content, so Reset is never below a dead edge
					local page = w.adapter.node("/Settings/Page")
					local history = w.adapter.node("/Settings/Page/History")
					local contentH = page.scrollRegion.contentH
					expect(contentH >= (history.rect.y + history.rect.h) - page.rect.y).toBe(true)
				end
			end
		end
	end)

	-- Per-input proofs (ADR-0013): example 03 carries NO present() opts — the
	-- toggle/steppers/buttons' node onActivate handlers are dispatched by the
	-- presenter, and the +/- HStack yields layout-derived 2D navigation.
	it("✓ ex03 touch: a touch tap on the Music toggle applies optimistically and goes pending", function()
		local core, _, adapter, presenter, built, handle = ex03World()
		adapter.tap(MUSIC, { pointer = "touch" })
		expect(built.draftMusic:get()).toBe(true)
		expect(built.mutation.status:get()).toBe("pending")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("✓ ex03 touch: the whole accept round trip is reachable by touch alone", function()
		local core, _, adapter, presenter, built, handle = ex03World()
		adapter.tap(MUSIC, { pointer = "touch" })
		adapter.tap(DELIVER, { pointer = "touch" })
		expect(built.draftMusic:get()).toBe(true)
		expect(built.mutation.status:get()).toBe("confirmed")
		adapter.tap(MUSIC, { pointer = "touch" })
		adapter.tap(DELIVER, { pointer = "touch" })
		expect(built.draftMusic:get()).toBe(false) -- and back off again
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("✓ ex03 keyboard: Return on the focused Music toggle applies optimistically", function()
		local core, system, _, presenter, built, handle = ex03World()
		expect(presenter.focus.focused:get()).toBe(MUSIC) -- initial focus
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(built.draftMusic:get()).toBe(true)
		expect(built.mutation.status:get()).toBe("pending")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	-- The gallery client presents with NO `keyboardNavigation` opt, so Tab binds
	-- nothing there; the desktop keyboard path a player actually has is the
	-- arrows plus Return. Drive the one that exists.
	it("✓ ex03 keyboard: the arrows reach Deliver, and Return there completes the round trip", function()
		local core, system, _, presenter, built, handle = ex03World()
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(built.mutation.status:get()).toBe("pending")
		-- Music -> the +/- row -> AskInvalid -> Deliver, derived from the layout
		for _ = 1, 3 do
			system.deviceKey("Down", true)
			system.deviceKey("Down", false)
		end
		expect(presenter.focus.focused:get()).toBe(DELIVER)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(built.mutation.status:get()).toBe("confirmed")
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("✓ ex03 gamepad: ButtonA on the focused Music toggle applies optimistically", function()
		local core, system, _, presenter, built, handle = ex03World()
		expect(presenter.focus.focused:get()).toBe(MUSIC)
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
		expect(presenter.focus.focused:get()).toBe(VOL_MINUS)
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

		expect(presenter.focus.focused:get()).toBe("/DangerScreen/Page/Delete")
		-- activate the base button -> opens the confirmation modal
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(presenter.depth()).toBe(2)
		expect(presenter.focus.focused:get()).toBe("/ConfirmDialog/Center/Card/Confirm")

		-- focus is trapped inside the modal: navigation moves Confirm<->Cancel
		-- and wraps, never escaping to the base screen
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(presenter.focus.focused:get()).toBe("/ConfirmDialog/Center/Card/Cancel")
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(presenter.focus.focused:get()).toBe("/ConfirmDialog/Center/Card/Confirm") -- wrapped

		-- ButtonB (gamepad B) is Cancel routing: dismiss + restore focus
		system.deviceKey("ButtonB", true)
		system.deviceKey("ButtonB", false)
		expect(presenter.depth()).toBe(1)
		expect(presenter.focus.focused:get()).toBe("/DangerScreen/Page/Delete") -- restored
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
		expect(presenter.focus.focused:get()).toBe("/ConfirmDialog/Center/Card/Cancel")
		system.deviceKey("ButtonA", true) -- activate Cancel
		system.deviceKey("ButtonA", false)

		expect(built.result:get()).toBe("cancelled")
		expect(presenter.depth()).toBe(1)
		expect(presenter.focus.focused:get()).toBe("/DangerScreen/Page/Delete")
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
		adapter.tap("/DangerScreen/Page/Delete") -- mouse click opens the dialog
		expect(presenter.depth()).toBe(2)
		expect(presenter.focus.focused:get()).toBe("/ConfirmDialog/Center/Card/Confirm")
		adapter.tap("/ConfirmDialog/Center/Card/Cancel") -- a tap INSIDE the modal routes normally
		expect(built.result:get()).toBe("cancelled")
		expect(presenter.depth()).toBe(1)
		expect(presenter.focus.focused:get()).toBe("/DangerScreen/Page/Delete") -- restored
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("✓ ex04 touch: a touch tap opens the modal and a touch tap on Confirm records confirmed", function()
		local core, _, adapter, presenter, built, handle = ex04World()
		adapter.tap("/DangerScreen/Page/Delete", { pointer = "touch" })
		expect(presenter.depth()).toBe(2)
		adapter.tap("/ConfirmDialog/Center/Card/Confirm", { pointer = "touch" })
		expect(built.result:get()).toBe("confirmed")
		expect(presenter.depth()).toBe(1)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	-- ========================================================================
	-- WHAT THE PLAY AUDIT FOUND (example-quality-pass, 2026-08-06). Driven live,
	-- the modal opened, trapped focus and dismissed correctly — and after
	-- confirming a destructive "Delete" the base screen was BYTE-IDENTICAL to
	-- before. `result` was a test handle; the player saw nothing happen. The
	-- dialog was also authored `alignH/alignV = center` on a Screen, where those
	-- props are documented as ZStack-child alignment and are accepted-and-ignored:
	-- the card rendered at the top-left corner.
	-- ========================================================================
	it("confirming CHANGES THE SCREEN the player is looking at", function()
		local core, _, adapter, presenter, built, handle = ex04World()
		presenter.refresh()
		local titleBefore = adapter.node(built.titlePath).props.text
		local outcomeBefore = adapter.node(built.outcomePath).props.text
		adapter.tap(built.deletePath)
		adapter.tap(built.confirmPath)
		presenter.refresh()
		expect(adapter.node(built.titlePath).props.text ~= titleBefore).toBe(true)
		expect(adapter.node(built.outcomePath).props.text ~= outcomeBefore).toBe(true)
		expect(string.find(adapter.node(built.titlePath).props.text, "empty", 1, true) ~= nil).toBe(true)
		expect(string.find(adapter.node(built.outcomePath).props.text, "Deleted", 1, true) ~= nil).toBe(true)
		-- ...and the destructive action is no longer offered on an empty slot
		expect(adapter.node(built.deletePath).props.enabled).toBe(false)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("cancelling says the save was KEPT, which is a different visible answer", function()
		local core, _, adapter, presenter, built, handle = ex04World()
		adapter.tap(built.deletePath)
		adapter.tap(built.cancelPath)
		presenter.refresh()
		expect(string.find(adapter.node(built.outcomePath).props.text, "Kept", 1, true) ~= nil).toBe(true)
		expect(built.hasSave:get()).toBe(true)
		expect(adapter.node(built.deletePath).props.enabled).toBe(true)
		presenter.dismiss(handle)
	end)

	it("Restore puts the save back, so the demonstration is repeatable in place", function()
		local core, _, adapter, presenter, built, handle = ex04World()
		adapter.tap(built.deletePath)
		adapter.tap(built.confirmPath)
		expect(built.hasSave:get()).toBe(false)
		adapter.tap(built.restorePath)
		presenter.refresh()
		expect(built.hasSave:get()).toBe(true)
		expect(built.result:get()).toBe("none")
		expect(adapter.node(built.deletePath).props.enabled).toBe(true)
		-- and the whole round trip runs again from here
		adapter.tap(built.deletePath)
		expect(presenter.depth()).toBe(2)
		adapter.tap(built.confirmPath)
		expect(built.hasSave:get()).toBe(false)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("the card is CENTRED, not parked in the top-left corner", function()
		local core, _, adapter, presenter, built, handle = ex04World()
		adapter.tap(built.deletePath)
		presenter.refresh()
		local screenRect = adapter.node("/ConfirmDialog").rect
		local card = adapter.node(built.cardPath).rect
		expect(card ~= nil).toBe(true)
		-- the card's centre sits within 2px of the scrim's centre on both axes
		local dx = math.abs((card.x + card.w / 2) - (screenRect.x + screenRect.w / 2))
		local dy = math.abs((card.y + card.h / 2) - (screenRect.y + screenRect.h / 2))
		expect(dx <= 2).toBe(true)
		expect(dy <= 2).toBe(true)
		-- ...and it is genuinely smaller than the scrim, so "centred" means something
		expect(card.w < screenRect.w).toBe(true)
		expect(card.h < screenRect.h).toBe(true)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("tapping Delete twice does not stack two identical modals", function()
		local core, _, adapter, presenter, built, handle = ex04World()
		adapter.tap(built.deletePath)
		expect(presenter.depth()).toBe(2)
		-- the base Delete is behind a modal scrim, so drive the command directly:
		-- the guard is what is under test, not the routing
		built.openDialog()
		expect(presenter.depth()).toBe(2)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)
end)
