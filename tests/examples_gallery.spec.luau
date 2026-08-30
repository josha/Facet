--!strict
-- Documentation deliverable (design §17 Phase 4): the first FIVE progressive
-- tutorial examples, each a runnable, engine-free gallery module verified
-- headless under Lune. Every example module exports:
--     { title = "...", build = function(Facet, core, deps) ... end }
-- and build(...) returns { screen = <Blueprint>, present? = <presenter opts>,
-- ...example-specific handles }. deps is the uniform four-field table
--     { env, actionSystem, presenter, adapter }
-- (each example uses the subset it needs). These tests drive each example the
-- way a real client would — mount + render through the presenter and the
-- headless FakeTarget adapter, then exercise its primary interaction end to
-- end — and assert the reactive core stayed error-free throughout.
--
-- ...AND, SINCE parity round 2, THE GALLERY FIXTURES THAT CARRY A NEW
-- PUBLIC API (the last two sections of this file). The standing obligation is
-- that "every new public API appears in at least one gallery scenario that
-- `examples_gallery.spec` runs headlessly" (docs/plans/parity-round2-brief.md,
-- §"Standing quality bar"), and this is the file that obligation NAMES — so a
-- fixture whose whole job is to be that proof is executed here, beside the
-- tutorials, rather than in a spec nobody thought to look in. Those sections
-- mount through the SHOWCASE's minimal fixture ctx and under the SHOWCASE's own
-- chrome reservation, because that is the host a player reaches them through;
-- the scenario contract is `build(ctx) -> { screen, present?, steps?, ... }`,
-- not the tutorial contract above.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")

-- A complete headless stack: the same wiring a client bootstrap uses, minus
-- the Roblox-only adapters (FakeTarget stands in for ScreenTarget; the headless
-- action system stands in for the Input Action System).
local function makeHarness()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, system)
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
		local built = ex.build(Facet, core, deps)
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
		local built = ex.build(Facet, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		return core, adapter, presenter, built, handle
	end
	local function rowHit(key: string): string
		return `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/RowActions-{key}/Content/Row/Hit`
	end
	-- ONE CONTROL, NOT FIVE BUTTONS (director round 10, 2026-07-26). The rating
	-- cell is `Facet.newRating`, so the glyphs are Texts under a single Grip:
	-- `star()` still names a glyph to READ, but there is nothing to tap there —
	-- every input class lands on the strip.
	local function star(key: string, index: number): string
		return `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/RowActions-{key}/Content/Row/Cells/Cell-rating/Rating/Stars/Star{index}`
	end
	local function ratingStrip(key: string): string
		return `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/RowActions-{key}/Content/Row/Cells/Cell-rating/Rating/Strip`
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
			if
				adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[{track.id}@0]/RowActions-{track.id}/Content/Row`)
				~= nil
			then
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
		expect(adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[drift@0]/RowActions-drift/Content/Row`) ~= nil).toBeTruthy()
		expect(adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[neon@0]/RowActions-neon/Content/Row`)).toBe(nil)
		-- clear through the REAL tap path restores every row
		adapter.tap(FILTER_CLEAR)
		presenter.refresh()
		expect(#built.rows:get()).toBe(6)
		expect(adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[neon@0]/RowActions-neon/Content/Row`) ~= nil).toBeTruthy()
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("case-insensitive match; surviving rows keep their mounted identity (no remount)", function()
		local core, adapter, presenter, built, handle = playlistWorld()
		-- capture a row that survives both filters below (Apex Bloom)
		local apexRowPath = `/Playlist/Page/Tracks/Main/Body/Rows/[apex@0]/RowActions-apex/Content/Row`
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
		local built = ex.build(Facet, core, deps)
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

	it(
		"reordering is DISABLED while a filter is active (the media-library convention): the base order is preserved",
		function()
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
		end
	)

	it("per-input activation: keyboard/gamepad Activate on the focused filter field enters edit mode", function()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core, _, adapter, presenter, deps = makeHarness()
		local built = ex.build(Facet, core, deps)
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

	-- The Length column was removed on 2026-08-13 (its own comment in the example
	-- carries the measurement: with two edit-mode gutters on a row, a third fixed
	-- column left the `fill` Name cell 6px wide at 320x640). Its "length renders
	-- mm:ss" assertion proved that a column's `value` FUNCTION reaches its cell,
	-- so that claim moves onto the Name column below rather than being dropped —
	-- same mechanism, a column that still exists.
	it("mounts an iTunes-style table: name and rating columns aligned under their headers", function()
		local core, adapter, _, built = playlistWorld()
		expect(core:lastError()).toBeNil()
		local firstKey = built.rows:get()[1].id
		local firstName = built.rows:get()[1].name
		local function cell(id: string): any
			return adapter.node(
				`/Playlist/Page/Tracks/Main/Body/Rows/[{firstKey}@0]/RowActions-{firstKey}/Content/Row/Cells/Cell-{id}`
			).rect
		end
		for _, id in { "name", "rating" } do
			local header = adapter.node(`/Playlist/Page/Tracks/Main/Header/Head-{id}`).rect
			expect(cell(id).x).toBe(header.x)
			expect(cell(id).w).toBe(header.w)
		end
		-- a column's `value` function reaches its cell
		local nameText = adapter.node(
			`/Playlist/Page/Tracks/Main/Body/Rows/[{firstKey}@0]/RowActions-{firstKey}/Content/Row/Cells/Cell-name/Value`
		)
		expect(nameText.props.text).toBe(firstName)
		-- and the `fill` column really is the one absorbing the leftover
		expect(cell("name").w > cell("rating").w).toBe(true)
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

		--[[ ...AND THIS TABLE HAS NO MIRROR TO BIND, WHICH IS THE POINT (ruling 3,
			2026-08-13). This test used to end by driving `driveScroll` on
			`api.scrollPath()` and asserting `dump().scrollTop == 120` — an assertion
			only the FAKE could satisfy. The shipped playlist is a BLOCK table
			(`scrolls = false`, "the page owns the scrolling"), so that path is a
			plain VStack: on the real client the renderer elides it and nothing can
			ever move it, while `fake_target.driveScroll` writes `scrollPosition` onto
			any node it is handed and fires its observers regardless. The suite was
			pinning a number the engine could not produce.

			What the auto-bind actually buys a block table is the TRAY-CLOSE, bound to
			the page — proved by the live-shaped case below, not by a mirror. ]]
		expect(built.table_.api.scrollPath()).toBe(nil)
		expect(built.table_.dump().scrollTop).toBe(0)
		expect(core:lastError()).toBeNil()
	end)

	--[[ RULING 3, THE REPORTED SYMPTOM, ON THE SHIPPED SURFACE (director
		2026-08-13). Open a swipe tray in the playlist, scroll the PAGE, and the tray
		used to ride along still open: "any scroll closes the tray" was bound to
		`<root>/Main/Body`, which in a block table is a node that never scrolls.
		Now `api.scrollPath()` publishes nothing and the coordinator binds to the
		real scrolling ancestor, so the page scroll closes it. ]]
	it("RULING 3: scrolling the PAGE closes a swiped-open tray on the shipped playlist", function()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local clock = { t = 0 } -- a swipe needs a scripted clock (drag velocity)
		local presenter = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clock.t
			end,
		})
		local built =
			ex.build(Facet, core, { env = env, actionSystem = system, presenter = presenter, adapter = adapter })
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		-- THE SHIPPED BOOTSTRAP's auto-bind, the same loop as the case above
		built.table_.api.bindNativeScroll(handle.controller)
		local function settle(frames: number?)
			for _ = 1, frames or 120 do
				clock.t += 1 / 60
				presenter.tick(1 / 60)
				presenter.refresh()
			end
		end
		local key = built.rows:get()[1].id
		local root = `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/RowActions-{key}`
		local hit = `{root}/Content/Row/Hit`
		local remove = `{root}/TrayTrailingWhen/then/TrayTrailing/Action:remove`
		local rect = adapter.node(hit).rect
		local startX, y = rect.x + rect.w - 8, rect.y + rect.h / 2
		adapter.pointerDown(hit, startX, y, "mouse")
		for i = 1, 8 do
			adapter.pointerMove(startX - rect.w * 0.3 * (i / 8), y, "mouse")
			settle(1)
		end
		adapter.pointerUp(startX - rect.w * 0.3, y)
		settle(120)
		expect(`tray open: {adapter.node(remove) ~= nil}`).toBe("tray open: true")

		-- the PAGE moves — the only thing that CAN move on this screen
		adapter.driveScroll("/Playlist/Page", { x = 0, y = 40 })
		settle(120)
		expect(`tray open after a page scroll: {adapter.node(remove) ~= nil}`).toBe(
			"tray open after a page scroll: false"
		)
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

	-- RE-POINTED 2026-08-13 with Table's touch contract. This example declares
	-- `onPrimaryAction`, so under the documented convention a plain tap OPENS a row
	-- and EDIT MODE is where touch selection lives (edit mode; the list guidance and
	-- tables). The old body drove `adapter.tap` with NO meta — the table's
	-- unknown-device fallback, which is the touch idiom — and asserted additive
	-- selection; that is now the edit-mode gesture, so the case drives the
	-- example's OWN auto-shown Edit toggle first and proves the same additive
	-- multi-select through the surface a phone player actually reaches. No
	-- assertion was dropped: both rows are still asserted selected, and the
	-- deselect half (the gesture the rule gives back) is asserted on top.
	it(
		"multi-select on touch: EDIT MODE is where taps select, and both rows stay selected (additive toggle)",
		function()
			local ex = require("../examples/gallery/examples/02_playlist_table")
			local core, _, adapter, presenter, deps = makeHarness()
			local built = ex.build(Facet, core, deps)
			presenter.present(built.screen, built.present)
			presenter.refresh()
			local first = built.rows:get()[1].id
			local second = built.rows:get()[2].id
			-- the Edit affordance auto-shows for a touch session (the same gate the
			-- reorder case below drives); it is the surface a phone player reaches
			deps.env:set("preferredInput", "Touch")
			presenter.refresh()
			local togglePath = "/Playlist/Page/Tracks/Main/ToggleWhen/then/Toolbar/EditToggle"
			adapter.touchTap(togglePath)
			presenter.refresh()
			adapter.touchTap(rowHit(first))
			adapter.touchTap(rowHit(second))
			presenter.refresh()
			expect(adapter.node(rowHit(first)).props.selected).toBe(true)
			expect(adapter.node(rowHit(second)).props.selected).toBe(true)
			-- nothing played: activation is unreachable in edit mode, on purpose
			expect(built.nowPlaying:get()).toBeNil()
			-- and the gesture the new rule GIVES BACK: a second tap deselects
			adapter.touchTap(rowHit(second))
			presenter.refresh()
			expect(adapter.node(rowHit(second)).props.selected).toBeFalsy()
			expect(adapter.node(rowHit(first)).props.selected).toBe(true)
			expect(core:lastError()).toBeNil()
		end
	)

	-- THE PRIMARY ACTION ON A TUTORIAL EXAMPLE (parity round 2 §3.4). The
	-- four-input proof for the Table's own gesture table lives in
	-- tests/table_input.spec.luau §5; what is proved HERE is the other half — that
	-- this example declares it, that the handler reaches the example's own state,
	-- and that the page says so. THE CLOCK IS SCRIPTED, because a double-click is
	-- a MEASUREMENT: with `os.clock`, two `adapter.tap` calls in a spec are
	-- microseconds apart and the window would be satisfied by the test's own speed
	-- rather than by the code under test. The slow-pair case below only bites with
	-- a scripted one.
	local function playingWorld()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local clock = { t = 100 }
		local presenter = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clock.t
			end,
		})
		local built =
			ex.build(Facet, core, { env = env, actionSystem = system, presenter = presenter, adapter = adapter })
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		return core, adapter, presenter, built, handle, clock
	end
	local function mouseTap(adapter: any, key: string)
		local rect = adapter.node(rowHit(key)).rect
		adapter.tap(rowHit(key), {
			source = "pointer",
			pointer = "mouse",
			x = rect.x + rect.w / 2,
			y = rect.y + rect.h / 2,
		})
	end

	it("onPrimaryAction: a DOUBLE-click plays the track and the page says so; a single click only selects", function()
		local core, adapter, presenter, built, _, clock = playingWorld()
		local key = built.rows:get()[2].id
		local name = built.rows:get()[2].name
		presenter.refresh()
		expect(built.nowPlaying:get()).toBeNil()
		expect(string.find(adapter.node(built.nowPlayingPath).props.text, "Nothing playing", 1, true) ~= nil).toBeTruthy()
		-- one click is a SELECTION and nothing else
		mouseTap(adapter, key)
		presenter.refresh()
		expect(built.nowPlaying:get()).toBeNil()
		expect(adapter.node(rowHit(key)).props.selected).toBe(true)
		-- ...and a second one inside the window is the primary action
		clock.t += 0.2
		mouseTap(adapter, key)
		presenter.refresh()
		expect(built.nowPlaying:get()).toBe(name)
		expect(adapter.node(built.nowPlayingPath).props.text).toBe(`Now playing — {name}`)
		-- opening is not a selection verb: the row it opened is still selected
		expect(adapter.node(rowHit(key)).props.selected).toBe(true)
		expect(core:lastError()).toBeNil()
	end)

	it("onPrimaryAction: two clicks SLOWER than the double-click window play nothing", function()
		local _, adapter, presenter, built, _, clock = playingWorld()
		local key = built.rows:get()[1].id
		mouseTap(adapter, key)
		clock.t += 0.6 -- past the 500 ms window
		mouseTap(adapter, key)
		presenter.refresh()
		expect(built.nowPlaying:get()).toBeNil()
	end)

	it("onPrimaryAction: on TOUCH the FIRST plain tap plays the track (the compact-touch rule)", function()
		local _, adapter, presenter, built, _, clock = playingWorld()
		local key = built.rows:get()[3].id
		local name = built.rows:get()[3].name
		adapter.touchTap(rowHit(key))
		presenter.refresh()
		expect(built.nowPlaying:get()).toBe(name)
		-- THE PRICE THIS EXAMPLE PAYS, ON THE RECORD: a normal-mode tap does not
		-- select at all any more — selection retreats into edit mode, which is
		-- exactly what the convention documents once a primary action is declared
		expect(adapter.node(rowHit(key)).props.selected).toBeFalsy()
		-- and touch activation is a MODE, not a measurement: a second tap after an
		-- arbitrarily long pause plays it again rather than doing something else
		local other = built.rows:get()[2].id
		clock.t += 30
		adapter.touchTap(rowHit(other))
		presenter.refresh()
		expect(built.nowPlaying:get()).toBe(built.rows:get()[2].name)
	end)

	it("Restore puts the playlist back INCLUDING what was playing", function()
		local _, adapter, presenter, built, _, clock = playingWorld()
		local key = built.rows:get()[1].id
		mouseTap(adapter, key)
		clock.t += 0.2
		mouseTap(adapter, key)
		presenter.refresh()
		expect(built.nowPlaying:get()).never().toBeNil()
		adapter.tap(built.restorePath)
		presenter.refresh()
		expect(built.nowPlaying:get()).toBeNil()
		expect(string.find(adapter.node(built.nowPlayingPath).props.text, "Nothing playing", 1, true) ~= nil).toBeTruthy()
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
		local built = ex.build(Facet, core, deps)
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
		local handlePath =
			`/Playlist/Page/Tracks/Main/Body/Rows/[{first}@0]/RowActions-{first}/Content/Row/EditWhen/then/HandleZone/Handle`
		expect(adapter.node(handlePath) ~= nil).toBeTruthy()
		local handleRect = adapter.node(handlePath).rect
		-- DERIVED FROM THE ROW, not a literal. This drag was 60px, which crossed
		-- one 34px row; raising rowHeight to 48 for the phone made 60px land
		-- inside the SAME row and the test failed on a change that was correct.
		-- A reorder test should say "past the next row", not "60 pixels".
		local rowRect =
			adapter.node(`/Playlist/Page/Tracks/Main/Body/Rows/[{first}@0]/RowActions-{first}/Content/Row`).rect
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
		local built = ex.build(Facet, core, deps)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		local system = deps.actionSystem
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
		end
		local first = built.rows:get()[1].id
		local second = built.rows:get()[2].id
		-- initial focus = the filter field (prepended nav group), then down through
		-- the HEADER BAND, then the toolbar, then into the rows.
		--
		-- THE HEADER IS A STOP SINCE 2026-08-16 (navigation-and-menus D8), and it is
		-- ONE stop rather than three: the band is a nav group, so Up/Down enters and
		-- leaves it while Left/Right walks its columns. That is the cost of a table
		-- whose headings sort and resize, and it is paid on every input class — a
		-- header a pad cannot reach would be a sort a pad cannot perform.
		expect(presenter.focus.focused:get()).toBe("/Playlist/Page/Filter/Field")
		press("DPadDown")
		expect(presenter.focus.focused:get()).toBe("/Playlist/Page/Tracks/Main/Header/Head-name/Column")
		press("DPadDown")
		expect(presenter.focus.focused:get()).toBe("/Playlist/Page/Tracks/Main/ToggleWhen/then/Toolbar/EditToggle")
		press("DPadDown")
		expect(presenter.focus.focused:get()).toBe(
			`/Playlist/Page/Tracks/Main/Body/Rows/[{first}@0]/RowActions-{first}/Content/Row/Hit`
		)
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
		expect(presenter.focus.focused:get()).toBe(
			`/Playlist/Page/Tracks/Main/Body/Rows/[{first}@0]/RowActions-{first}/Content/Row/Hit`
		)
		press("ButtonA")
		expect(built.table_.api.grabbedKey:get()).toBeNil()
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("GAMEPAD: selection follows focus across rows, even when focus sits on a star", function()
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core, _, adapter, presenter, deps = makeHarness()
		deps.env:set("preferredInput", "Gamepad")
		local built = ex.build(Facet, core, deps)
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
			return `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/RowActions-{key}/Content/Row/Hit`
		end
		press("DPadDown") -- filter field -> header band (sortable/resizable since D8)
		press("DPadDown") -- header -> toolbar
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

	it(
		"KEYBOARD: a swiped-open tray is REACHABLE on the shipped playlist — Tab lands on Remove and fires it",
		function()
			--[[ THE SHOWCASE HALF of parity round 3's owed row 8, on the example a
			player actually sees. A Table tray opens only by swipe, so this swipes it
			open with the mouse and then leaves the pointer alone.

			MEASURED BEFORE AND AFTER, on this surface: pre-fix the walk from the Edit
			toggle ran Hit -> Rating -> next row's Hit, straight past a mounted, lit
			tray button; after it, Remove is a stop. (Tab is document-order RANK, and
			the tray mounts AHEAD of the row's content — trays are the wrapper's first
			children — so it comes before the row it belongs to. The navigation groups
			read the same set in painting order.)

			WHY TAB HERE, AND WHAT CHANGED (ruling 9, 2026-08-14). This case used to
			carry the note "the d-pad cannot get past this row's rating strip": the
			strip is a value control that owns Left/Right, and at 5 of 5 a DPadRight
			moved neither the rating nor the ring, so nothing later in the row was
			pad-reachable at all. That is now fixed — a value control yields the arrow
			at its limit — and the d-pad walk is asserted in the case immediately
			below, on this same surface. Tab stays proved here because Tab is a
			DIFFERENT order (document-order rank, above) and losing it would be a
			separate regression. ]]
			local ex = require("../examples/gallery/examples/02_playlist_table")
			local core = Facet.newCore()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			env:set("preferredInput", "KeyboardAndMouse")
			local system = Facet.newActionSystem(core)
			local adapter = fake_target.new()
			local clock = { t = 0 } -- a swipe needs a scripted clock (drag velocity)
			local presenter = Facet.newPresenter(core, env, adapter, system, {
				now = function()
					return clock.t
				end,
				keyboardNavigation = true, -- Tab is opt-in at the presenter
			})
			local built =
				ex.build(Facet, core, { env = env, actionSystem = system, presenter = presenter, adapter = adapter })
			presenter.present(built.screen, built.present)
			presenter.refresh()
			local function settle(frames: number?)
				for _ = 1, frames or 120 do
					clock.t += 1 / 60
					presenter.tick(1 / 60)
					presenter.refresh()
				end
			end
			local function press(key: string)
				system.deviceKey(key, true)
				system.deviceKey(key, false)
				settle(2)
			end
			local key = built.rows:get()[1].id
			local root = `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/RowActions-{key}`
			local hit = `{root}/Content/Row/Hit`
			local remove = `{root}/TrayTrailingWhen/then/TrayTrailing/Action:remove`
			expect(adapter.node(remove)).toBe(nil)

			local rect = adapter.node(hit).rect
			local startX, y = rect.x + rect.w - 8, rect.y + rect.h / 2
			adapter.pointerDown(hit, startX, y, "mouse")
			for i = 1, 8 do
				adapter.pointerMove(startX - rect.w * 0.3 * (i / 8), y, "mouse")
				settle(1)
			end
			adapter.pointerUp(startX - rect.w * 0.3, y)
			settle(120)
			expect(adapter.node(remove) ~= nil).toBeTruthy() -- open, by finger

			-- ...and now the KEYBOARD, with no pointer anywhere near it
			presenter.focus.focusOn("/Playlist/Page/Tracks/Main/ToggleWhen/then/Toolbar/EditToggle")
			presenter.refresh()
			--[[ THE HEADER BAND SITS BETWEEN THEM SINCE 2026-08-16 (D8): the table's
				headings sort and resize now, so each is a document-order stop of its
				own, ahead of the body. Spelled out one press at a time rather than
				looped, because the ORDER is the claim — Tab is document-order RANK
				(`97e9d93`) and a walk that reached the tray by some other route would
				be a different fact. ]]
			press("Tab")
			expect(presenter.focus.focused:get()).toBe("/Playlist/Page/Tracks/Main/Header/Head-name/Column")
			press("Tab")
			expect(presenter.focus.focused:get()).toBe("/Playlist/Page/Tracks/Main/Header/Head-artist/Column")
			press("Tab")
			expect(presenter.focus.focused:get()).toBe("/Playlist/Page/Tracks/Main/Header/Head-rating/Column")
			press("Tab")
			expect(presenter.focus.focused:get()).toBe(remove)
			expect(adapter.node(remove).focused).toBe(true)
			expect(#built.baseRows:get()).toBe(6)
			press("Return")
			settle(400)
			local ids = {}
			for _, track in built.baseRows:get() do
				table.insert(ids, track.id)
			end
			expect(#ids).toBe(5)
			expect(table.find(ids, key)).toBeNil()
			expect(core:lastError()).toBeNil()
		end
	)

	it("GAMEPAD: the d-pad walks PAST the rating and into the swiped-open tray (ruling 9)", function()
		--[[ THE SHOWCASE DEMO for ruling 9, on the surface it was measured on.

			Before: `DPadRight` on this row's rating strip moved the rating 4 -> 5 and
			then, at the maximum, moved nothing at all — the strip had taken Right
			away from navigation and would not give it back, so the tray that the row
			had just been taught to expose was unreachable on a gamepad. A gamepad has
			no Tab, so the case above was the only route in.

			After: the strip yields the arrow at its limit, and the walk continues.
			The row is swiped open with the mouse first (a Table tray opens only by
			swipe), and then the pointer is left alone — everything after the swipe is
			the pad. ]]
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("preferredInput", "Gamepad")
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local clock = { t = 0 }
		local presenter = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clock.t
			end,
		})
		local built =
			ex.build(Facet, core, { env = env, actionSystem = system, presenter = presenter, adapter = adapter })
		presenter.present(built.screen, built.present)
		presenter.refresh()
		local function settle(frames: number?)
			for _ = 1, frames or 120 do
				clock.t += 1 / 60
				presenter.tick(1 / 60)
				presenter.refresh()
			end
		end
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			settle(2)
		end
		local key = built.rows:get()[1].id
		local root = `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/RowActions-{key}`
		local hit = `{root}/Content/Row/Hit`
		local remove = `{root}/TrayTrailingWhen/then/TrayTrailing/Action:remove`

		local rect = adapter.node(hit).rect
		local startX, y = rect.x + rect.w - 8, rect.y + rect.h / 2
		adapter.pointerDown(hit, startX, y, "mouse")
		for i = 1, 8 do
			adapter.pointerMove(startX - rect.w * 0.3 * (i / 8), y, "mouse")
			settle(1)
		end
		adapter.pointerUp(startX - rect.w * 0.3, y)
		settle(120)
		expect(adapter.node(remove) ~= nil).toBeTruthy()

		-- ...and from here it is the PAD only. Park the ring on the row, walk right
		-- onto the rating, push it to its maximum, and keep pushing.
		presenter.focus.focusOn(hit)
		presenter.refresh()
		press("DPadRight")
		expect(presenter.focus.focused:get()).toBe(ratingStrip(key))
		local ratingBefore = built.ratingFor(key):get()
		for _ = 1, 8 do
			press("DPadRight")
			if presenter.focus.focused:get() ~= ratingStrip(key) then
				break
			end
		end
		-- the rating went to its maximum and STAYED there; the ring moved on
		-- the rating went to its maximum and STAYED there, and the ring moved on to
		-- the tray button — the exact thing that was unreachable on a pad
		expect(`rating={built.ratingFor(key):get()} landed={presenter.focus.focused:get()}`).toBe(
			`rating=5 landed={remove}`
		)
		expect(ratingBefore < 5).toBe(true) -- the walk really did have to climb
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
		local built = ex.build(Facet, core, deps)
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

	-- =======================================================================
	-- THE DEVICE-ROUND PINS (director device round, 2026-08-13)
	-- =======================================================================
	--
	-- FINDING 1 ("the Edit button doesn't actually make rows editable") and
	-- FINDING 2 ("on a touch phone you can swipe a row either side to get the edit
	-- controls even if the table isn't in edit mode — we lost that").
	--
	-- The framework half of BOTH was measured and found intact: on the live
	-- showcase place the Edit toggle mounts, flips to Done, mounts the ≡ gutter
	-- on every row, insets the cells by it, drags to reorder, and an edit-mode
	-- tap selects without playing. What was missing was in THIS example: it
	-- declared no `rowActions`, so there was nothing to swipe and edit mode
	-- surfaced a reorder handle and nothing else.
	--
	-- These cases pin what the measurement found, in the two shapes the suite
	-- could not previously see.

	-- A PHONE IS NOT A DESKTOP WITH A FINGER. Every touch case above this one
	-- sets `preferredInput = "Touch"` on the harness's DEFAULT capabilities,
	-- which are `{ keyboard = true, mouse = true, touch = false }` — so what
	-- they actually drive is a HYBRID (`interactionClasses.pointer == true`),
	-- and the one class a real phone does not have is the one they all kept.
	-- Three table decisions branch on `classes.pointer`, so "the suite is green
	-- on touch" was never the same sentence as "this works on a phone".
	local function phoneWorld(vw: number?, vh: number?)
		local ex = require("../examples/gallery/examples/02_playlist_table")
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = vw or 390, h = vh or 844 })
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		-- ...and PreferredInput reads KeyboardAndMouse on a phone nobody has
		-- touched yet (the engine default, not a fact — environment.luau's own
		-- 2026-07-29 note). Boot in exactly that state.
		env:set("preferredInput", "KeyboardAndMouse")
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local clock = { t = 0 }
		local presenter = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clock.t
			end,
		})
		local built =
			ex.build(Facet, core, { env = env, actionSystem = system, presenter = presenter, adapter = adapter })
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		local world: any = {
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			built = built,
			handle = handle,
			-- exposed so a case can hot-switch this surface onto a pad and drive the
			-- REAL bindings (`deviceKey`) rather than the graph directly
			system = system,
		}
		function world.settle(frames: number?)
			for _ = 1, frames or 120 do
				clock.t += 1 / 60
				presenter.tick(1 / 60)
				presenter.refresh()
			end
		end
		return world
	end
	local TOGGLE = "/Playlist/Page/Tracks/Main/ToggleWhen/then/Toolbar/EditToggle"
	local function rowRoot(key: string): string
		return `/Playlist/Page/Tracks/Main/Body/Rows/[{key}@0]/RowActions-{key}`
	end
	--[[ swipe the row's own Hit surface sideways. `frac` is signed: negative is a
		trailing (leftward) swipe, positive a leading one, as a fraction of the
		row's own width — never a pixel count, so a row-height/width change
		cannot silently make this test stop crossing the reveal threshold.

		THE RELEASE ACTIVATES (redteam BLOCKER, 2026-08-13). This helper used to
		end at `pointerUp`, and a real gesture on a row `Hit` — a real engine
		`GuiButton` — does not: it ends with that button's `Activated`, on either
		side of `InputEnded`. Every swipe case below therefore drove a sequence no
		engine produces, and the "a swipe is not a tap" assertion beneath them
		(`nowPlaying` still nil) was satisfied by its own starting value: it could
		not fail, and the defect it was written to close was live under it. The
		order defaults to "after", the common engine order and the one that used
		to destroy the tray in the frame it appeared; the case below drives
		"before" too, which used to play the track the swipe was reaching for. ]]
	local function swipeRow(
		world: any,
		key: string,
		frac: number,
		pointerType: string?,
		activate: ("before" | "after")?
	)
		local hit = `{rowRoot(key)}/Content/Row/Hit`
		local rect = world.adapter.node(hit).rect
		local startX = if frac < 0 then rect.x + rect.w - 8 else rect.x + 8
		local y = rect.y + rect.h / 2
		local dx = rect.w * frac
		world.adapter.pointerDown(hit, startX, y, pointerType or "touch")
		for i = 1, 8 do
			world.adapter.pointerMove(startX + dx * (i / 8), y, pointerType or "touch")
		end
		world.presenter.refresh()
		world.adapter.pointerUpActivating(startX + dx, y, activate or "after")
		world.settle(120)
	end

	it("PHONE (no mouse capability): Edit mounts the ≡ gutter, a handle drag reorders, and a tap selects", function()
		local world = phoneWorld()
		local classes = world.env:get("interactionClasses"):get()
		-- the discriminator: this world is genuinely NOT the hybrid the older
		-- touch cases drive, so what follows is proved on the phone's class set
		expect(classes.pointer).toBe(false)
		expect(classes.touch).toBe(true)
		expect(classes.primary).toBe("touch")

		expect(world.adapter.node(TOGGLE) ~= nil).toBeTruthy()
		expect(world.adapter.node(TOGGLE).props.label).toBe("Edit")
		local first = world.built.rows:get()[1].id
		local second = world.built.rows:get()[2].id
		-- the gutter is NOT there before Edit — otherwise "it mounted" proves
		-- nothing about the button
		local handlePath = `{rowRoot(first)}/Content/Row/EditWhen/then/HandleZone/Handle`
		expect(world.adapter.node(handlePath)).toBe(nil)

		world.adapter.touchTap(TOGGLE)
		world.presenter.refresh()
		expect(world.built.table_.api.editing:get()).toBe(true)
		expect(world.adapter.node(TOGGLE).props.label).toBe("Done")
		expect(world.adapter.node(handlePath) ~= nil).toBeTruthy()

		-- ...and the cells moved over to make room for it, rather than the ≡
		-- painting on top of the first column (the shape of "the button did
		-- something visible but nothing usable")
		local nameCell = `{rowRoot(first)}/Content/Row/Cells/Cell-name`
		local handleRect = world.adapter.node(handlePath).rect
		expect(world.adapter.node(nameCell).rect.x >= handleRect.x + handleRect.w).toBe(true)

		-- the ≡ drag actually reorders on touch
		local rowRect = world.adapter.node(`{rowRoot(first)}/Content/Row`).rect
		local dropY = handleRect.y + 5 + rowRect.h * 1.5
		world.adapter.pointerDown(handlePath, handleRect.x + 5, handleRect.y + 5, "touch")
		world.adapter.pointerMove(handleRect.x + 5, dropY, "touch")
		world.presenter.refresh()
		world.adapter.pointerUp(handleRect.x + 5, dropY, "touch")
		world.presenter.refresh()
		expect(world.built.rows:get()[1].id).toBe(second)
		expect(world.built.rows:get()[2].id).toBe(first)

		-- and an edit-mode tap SELECTS rather than playing (the other half of
		-- what "editable" has to mean once a primary action is declared)
		local hit = `{rowRoot(second)}/Content/Row/Hit`
		world.adapter.touchTap(hit)
		world.presenter.refresh()
		expect(world.adapter.node(hit).props.selected).toBe(true)
		expect(world.built.nowPlaying:get()).toBeNil()

		expect(world.core:lastError()).toBeNil()
		expect(#world.handle.controller.diagnostics()).toBe(0)
	end)

	it("TRAILING swipe reveals Remove OUTSIDE edit mode, and firing it drops the track", function()
		local world = phoneWorld()
		-- NOT editing — the whole point of finding 2
		expect(world.built.table_.api.editing:get()).toBe(false)
		local key = world.built.rows:get()[1].id
		local trayAction = `{rowRoot(key)}/TrayTrailingWhen/then/TrayTrailing/Action:remove`
		expect(world.adapter.node(trayAction)).toBe(nil)

		swipeRow(world, key, -0.3)
		expect(world.built.table_.api.editing:get()).toBe(false) -- still not a mode
		expect(world.adapter.node(trayAction) ~= nil).toBeTruthy()
		-- a swipe is not a tap: the primary action never fired
		expect(world.built.nowPlaying:get()).toBeNil()
		expect(#world.built.baseRows:get()).toBe(6)

		world.adapter.touchTap(trayAction)
		world.settle(400) -- the commit collapses the row over a spring first
		local ids = {}
		for _, track in world.built.baseRows:get() do
			table.insert(ids, track.id)
		end
		expect(#ids).toBe(5)
		expect(table.find(ids, key)).toBeNil()
		expect(world.core:lastError()).toBeNil()
		expect(#world.handle.controller.diagnostics()).toBe(0)
	end)

	it("LEADING swipe reveals Top OUTSIDE edit mode, and firing it moves the track to the front", function()
		local world = phoneWorld()
		local key = world.built.rows:get()[3].id -- NOT already first
		expect(world.built.baseRows:get()[1].id).never().toBe(key)
		local trayAction = `{rowRoot(key)}/TrayLeadingWhen/then/TrayLeading/Action:top`
		expect(world.adapter.node(trayAction)).toBe(nil)

		-- A FULL swipe, deliberately past the commit threshold a trailing swipe
		-- would fire on. The leading edge OPTS OUT of full-swipe commit
		-- (`fullSwipe = { leading = false, trailing = true }`, the standard worked
		-- example — §16 [SW-37]), so this must REVEAL and commit nothing. A 30%
		-- swipe would have passed whether the opt-out existed or not.
		swipeRow(world, key, 0.9)
		expect(world.built.table_.api.editing:get()).toBe(false)
		expect(world.adapter.node(trayAction) ~= nil).toBeTruthy()
		expect(world.built.nowPlaying:get()).toBeNil()
		expect(world.built.baseRows:get()[1].id).never().toBe(key)

		world.adapter.touchTap(trayAction)
		world.settle(120)
		expect(world.built.baseRows:get()[1].id).toBe(key)
		expect(#world.built.baseRows:get()).toBe(6) -- moved, not copied
		expect(world.core:lastError()).toBeNil()
		expect(#world.handle.controller.diagnostics()).toBe(0)
	end)

	--[[ THE SWIPE SURVIVES ITS OWN RELEASE ACTIVATE — the OTHER order, and the
		other pointer kind (redteam BLOCKER, 2026-08-13). The two cases above drive
		the common "after InputEnded" order through `swipeRow`'s default. This one
		drives "before", which fails differently and worse: with no tray open yet,
		the swipe's own artifact reached the primary-action branch and PLAYED THE
		TRACK the player was reaching past to reveal a Remove for. Mouse is here
		because the playlist table is `reorderable`, so a mouse gesture resolves
		through a different dispatcher (`composeWithReorder`'s axis lock) than a
		finger does, and only one of the two would have been proven otherwise. ]]
	for _, pointerType in { "touch", "mouse" } do
		it(`a swipe never plays the track, whichever side of InputEnded its Activate lands ({pointerType})`, function()
			for _, activate in { "after", "before" } do
				local world = phoneWorld()
				local key = world.built.rows:get()[1].id
				local trayAction = `{rowRoot(key)}/TrayTrailingWhen/then/TrayTrailing/Action:remove`
				expect(world.built.nowPlaying:get()).toBeNil()

				swipeRow(world, key, -0.3, pointerType, activate :: any)

				expect(world.adapter.node(trayAction) ~= nil).toBeTruthy() -- the tray survived
				expect(world.built.nowPlaying:get()).toBeNil() -- and nothing played
				expect(world.built.table_.api.editing:get()).toBe(false)
				expect(#world.built.baseRows:get()).toBe(6) -- no commit either
				expect(world.core:lastError()).toBeNil()
				expect(#world.handle.controller.diagnostics()).toBe(0)
			end
		end)
	end

	it("a plain TAP still plays the track and opens no tray — the two gestures do not fight", function()
		local world = phoneWorld()
		local key = world.built.rows:get()[2].id
		local name = world.built.rows:get()[2].name
		world.adapter.touchTap(`{rowRoot(key)}/Content/Row/Hit`)
		world.presenter.refresh()
		expect(world.built.nowPlaying:get()).toBe(name)
		expect(world.adapter.node(`{rowRoot(key)}/TrayTrailingWhen/then/TrayTrailing/Action:remove`)).toBe(nil)
		expect(world.adapter.node(`{rowRoot(key)}/TrayLeadingWhen/then/TrayLeading/Action:top`)).toBe(nil)
		expect(world.core:lastError()).toBeNil()
	end)

	-- RE-DECIDED 2026-08-13 (game-director ruling, parity round 3 item C).
	-- THIS IS THE DIRECTOR'S OWN DEVICE SCENARIO, headless: the showcase
	-- playlist table, on a phone, in edit mode, tapping the ⊖. It used to
	-- assert `#baseRows == 6` — "revealed, nothing removed" — as the CORRECT
	-- outcome. The report was that a player doing exactly this expects the row
	-- to go, and the ruling agreed. So the assertion inverts: the row goes.
	--
	-- Why the old behaviour read as a bug rather than a design: the ⊖ borrows
	-- the destructive action's accessible label, so it announced itself as
	-- "Remove" and then removed nothing. The source justified the two-step as
	-- "the platform pattern"; the documented rules cover the control's appearance and edit
	-- mode's purpose but documents NO tap behaviour, so that was an uncited
	-- recollection (standing rule 7).
	it("edit mode ADDS the ⊖, and tapping it REMOVES the row (the director's device scenario)", function()
		local world = phoneWorld()
		local key = world.built.rows:get()[1].id
		local minus = `{rowRoot(key)}/EditAffordanceWhen/then/EditAffordance`
		expect(world.adapter.node(minus)).toBe(nil)
		world.adapter.touchTap(TOGGLE)
		world.presenter.refresh()
		expect(world.adapter.node(minus) ~= nil).toBeTruthy()
		expect(world.adapter.node(minus).props.icon).toBe("decrement")
		expect(world.adapter.node(minus).props.role).toBe("destructive")
		-- the ≡ handle is there TOO: two affordances, one row, at once
		expect(world.adapter.node(`{rowRoot(key)}/Content/Row/EditWhen/then/HandleZone/Handle`) ~= nil).toBeTruthy()

		expect(#world.built.baseRows:get()).toBe(6)
		world.adapter.touchTap(minus)
		world.settle(120)
		-- THE ROW IS GONE. This is the whole ruling, asserted on the real
		-- showcase fixture rather than on a unit world.
		expect(#world.built.baseRows:get()).toBe(5)
		-- and it is the row that was tapped, not merely "some row"
		for _, row in world.built.baseRows:get() do
			expect(row.id ~= key).toBeTruthy()
		end
		-- nothing stands painted behind it: the ⊖ commits through the same
		-- slide-off + collapse the swipe uses, so the tray it never revealed
		-- is not left mounted (round 2's C8a, in its edit-mode costume)
		local trayAction = `{rowRoot(key)}/TrayTrailingWhen/then/TrayTrailing/Action:remove`
		expect(world.adapter.node(trayAction)).toBe(nil)
		expect(world.core:lastError()).toBeNil()
		expect(#world.handle.controller.diagnostics()).toBe(0)
	end)

	--[[ THE DIRECTOR'S GAMEPAD SCENARIO, on the surface he found it on (2026-08-16):
		"in playlist table with gamepad, when the table is in edit mode and a row is
		selected, I'd expect left on the d-pad to select delete for this row.
		Instead it goes to delete for the prior row."

		The unit repro is `table_input.spec.luau` (R8-5/R8-6); this is the SHOWCASE
		half, and it is not redundant with it — this one presses A at the end and
		asks which TRACK left the playlist. A targeting bug that focuses the wrong
		row still focuses a real, lit, correctly-labelled ⊖, so every assertion that
		stops at "an affordance is focused" agrees with the bug. Only the name of
		the row it belongs to disagrees. ]]
	it("GAMEPAD in edit mode: Left selects THIS row's ⊖, and A removes THIS track", function()
		local world = phoneWorld()
		-- hot-switch the surface onto a pad: the ⊖ and the Edit toggle are offered
		-- to touch AND gamepad, so this is the same table the finger case drives
		world.env:set("capabilities", { keyboard = true, mouse = false, touch = false, gamepad = true })
		world.env:set("preferredInput", "Gamepad")
		world.presenter.refresh()
		local function press(key: string)
			world.system.deviceKey(key, true)
			world.system.deviceKey(key, false)
			world.settle(2)
		end
		-- into edit mode with the pad, not with a finger
		world.presenter.focus.focusOn(TOGGLE)
		world.presenter.refresh()
		press("ButtonA")
		expect(world.built.table_.api.editing:get()).toBe(true)

		-- THE SECOND ROW: the first row cannot show this defect at all, because it
		-- has no row group above it to fall into
		local key = world.built.rows:get()[2].id
		local above = world.built.rows:get()[1].id
		world.presenter.focus.focusOn(`{rowRoot(key)}/Content/Row/Hit`)
		world.presenter.refresh()
		press("DPadLeft")
		expect(world.presenter.focus.focused:get()).toBe(`{rowRoot(key)}/EditAffordanceWhen/then/EditAffordance`)

		local before = #world.built.baseRows:get()
		press("ButtonA")
		world.settle(120)
		expect(#world.built.baseRows:get()).toBe(before - 1)
		-- ...and it is THIS track that went, with the one above it untouched
		local left: { string } = {}
		for _, row in world.built.baseRows:get() do
			table.insert(left, row.id)
		end
		expect(table.find(left, key)).toBeNil()
		expect(table.find(left, above) ~= nil).toBe(true)
		expect(world.core:lastError()).toBeNil()
	end)

	--[[ EDIT MODE COSTS ROW WIDTH, AND THE SWEEP CANNOT SEE IT ────────────────
		`tests/overflow_sweep.spec.luau` mounts every surface AT REST, so it has
		nothing to say about edit mode — and edit mode is exactly where this row
		gets expensive: a `rowActions` row with a destructive action spends the
		theme's `editAffordance` gutter on the red ⊖ AND Table's own 32px gutter
		on the reorder ≡, both leading, both only while editing.

		That is what tipped this example over on 2026-08-13: with a third fixed
		column still in the row, the `fill` Name cell solved to 6px at 320x640 and
		its text to 0px, and the only thing that said so was the solver. So the
		narrowest swept viewport gets its own edit-mode case, in both
		orientations, asking the solver directly.
	]]
	it("edit mode is diagnostic-clean at the NARROWEST swept viewport, in both orientations", function()
		for _, view in { { w = 320, h = 640 }, { w = 640, h = 320 } } do
			local world = phoneWorld(view.w, view.h)
			-- the discriminator: reach edit mode, or this measures the resting
			-- layout the sweep already covers and proves nothing new
			world.adapter.touchTap(TOGGLE)
			world.presenter.refresh()
			expect(world.built.table_.api.editing:get()).toBe(true)
			local key = world.built.rows:get()[1].id
			expect(world.adapter.node(`{rowRoot(key)}/Content/Row/EditWhen/then/HandleZone/Handle`) ~= nil).toBeTruthy()
			expect(world.adapter.node(`{rowRoot(key)}/EditAffordanceWhen/then/EditAffordance`) ~= nil).toBeTruthy()
			-- ...and the track name still has room to be a track name
			local nameText = world.adapter.node(`{rowRoot(key)}/Content/Row/Cells/Cell-name/Value`)
			expect(nameText ~= nil).toBeTruthy()
			expect((nameText.rect.w > 24) or error(`{view.w}x{view.h}: name text solved to {nameText.rect.w}px`, 2)).toBe(
				true
			)
			local diagnostics = world.handle.controller.diagnostics()
			local detail = {}
			for _, d in diagnostics do
				table.insert(detail, `{d.node or "?"}: {d.issue or "?"}`)
			end
			expect(`{view.w}x{view.h}: {table.concat(detail, " / ")}`).toBe(`{view.w}x{view.h}: `)
			expect(world.core:lastError()).toBeNil()
		end
	end)

	it("Restore brings a REMOVED track back (the way out of the destructive action)", function()
		local world = phoneWorld()
		local key = world.built.rows:get()[1].id
		swipeRow(world, key, -0.3)
		world.adapter.touchTap(`{rowRoot(key)}/TrayTrailingWhen/then/TrayTrailing/Action:remove`)
		world.settle(400)
		expect(#world.built.baseRows:get()).toBe(5)
		world.adapter.touchTap(world.built.restorePath)
		world.presenter.refresh()
		expect(#world.built.baseRows:get()).toBe(6)
		expect(world.built.baseRows:get()[1].id).toBe(key)
		expect(world.core:lastError()).toBeNil()
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
		local built = ex.build(Facet, core, deps)
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

	-- DEVICE FINDING, a physical phone, 2026-07-26: "I can toggle music on but not
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
	-- The solver is asked, not the screenshot: a fixture that never reads
	-- `controller.diagnostics()` is not
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
						Facet,
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

	-- Per-input proofs: example 03 carries NO present() opts — the
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
		local built = ex.build(Facet, core, deps)
		local handle = presenter.present(built.screen, built.present)
		expect(core:lastError()).toBeNil()
		presenter.dismiss(handle)
	end)

	it("opens a modal that traps focus, and ButtonB dismisses it and restores focus", function()
		local ex = require("../examples/gallery/examples/04_confirm_dialog")
		local core, system, _, presenter, deps = makeHarness()
		local built = ex.build(Facet, core, deps)
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
		local built = ex.build(Facet, core, deps)
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

	-- Per-input proofs: example 04 now carries NO present() opts —
	-- the base Delete button and the modal's Confirm/Cancel buttons each carry
	-- their own node onActivate, dispatched by the presenter. These close the
	-- pointer + touch cells the audit left UNPROVEN (a modal example that never
	-- tested a real click/tap).
	local function ex04World()
		local ex = require("../examples/gallery/examples/04_confirm_dialog")
		local core, system, adapter, presenter, deps = makeHarness()
		local built = ex.build(Facet, core, deps)
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

-- ===========================================================================
-- THE ROUND-2 SHOWCASE FIXTURES (docs/plans/parity-round2.md).
--
-- Two gallery scenarios, each the ONE hands-on proof of a public API this round
-- added, and each registered in `demo_picker.DEMOS` so a player reaches it from
-- the chip rather than by editing a workspace attribute and republishing:
--
--   * `card_rail`      — `newVirtualList` with `axis = "x"` (§2.3);
--   * `with_animation` — `presenter.withAnimation` and the Full|Reduced control
--                        the motion demo owes (§Phase 4).
--
-- MOUNTED THE WAY THE SHOWCASE MOUNTS THEM, not the way a test would find
-- convenient. Two facts about that host are load-bearing here and neither is
-- cosmetic:
--
--   1. THE MINIMAL CTX. `init.client.luau`'s fixture branch passes
--      {Facet, core, env, actionSystem, presenter} — no adapter, no `record`,
--      no `flags`, and NO step ever runs. Anything a fixture needs at BUILD has
--      to be in that set, and anything a player must be able to do has to work
--      with no scripted help.
--   2. THE CHROME RESERVATION. Every demo is laid out below the picker's chip
--      strip, which the host writes into `coreSafeInsets.top`. A world that
--      omitted it would be measuring a screen 120px taller than the real one —
--      the margin several shipped overflow defects lived in. The number is READ from
--      the picker, exactly as tests/overflow_sweep.spec.luau reads it, so the
--      two cannot drift.
--
-- The always-on sweep in tests/overflow_sweep.spec.luau asks BOTH of these
-- surfaces the overflow question at eight viewports. What is here instead is
-- what that sweep structurally cannot ask: that the thing the fixture exists to
-- demonstrate actually happens.
-- ===========================================================================

local demo_picker = require("../examples/gallery/client/demo_picker") :: any
local l10n = require("./fixtures/a11y_l10n_fixtures")

local SHOWCASE_CORE_TOP = 58 -- a notched phone's Roblox topbar inset
local SHOWCASE_TOP = demo_picker.barReservation(SHOWCASE_CORE_TOP, nil, 8)

local NARROW_PORTRAIT = { w = 320, h = 640 }
local NARROW_LANDSCAPE = { w = 640, h = 320 }
local DESKTOP = { w = 1232, h = 1067 }

-- a surface that publishes its own measured geometry settles over a couple of
-- frames; the same bounded settle the sweep uses, and for the same reason
local function settleFixture(presenter: any)
	for _ = 1, 3 do
		presenter.refresh()
	end
end

local function fixtureWorld(view: any): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new();
	-- the live adapter publishes a bar thickness for a pointer session and the
	-- fake publishes none unless asked — a sweep laid out without it models a
	-- desktop 8px wider than the real one (tests/scroll_bar_measure.spec.luau)
	(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_RESERVE
	local presenter = Facet.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

-- exactly the call `init.client.luau`'s `mountDemo` makes for `kind == "fixture"`
local function mountFixture(w: any, module: any): any
	local built = module.build({
		Facet = Facet,
		core = w.core,
		env = w.env,
		actionSystem = w.system,
		presenter = w.presenter,
	})
	built.handle = w.presenter.present(built.screen, built.present)
	settleFixture(w.presenter)
	return built
end

-- THE NON-NEGOTIABLE: a
-- fixture must FAIL on the solver's own diagnostics, or the list is a log nobody
-- reads. ALL of them, not only the main-axis ones the sweep filters for — a new
-- animated surface is the highest-risk addition to a repo whose named recurring
-- defect is "content overflows and nothing scrolls".
local function expectNoDiagnostics(label: string, w: any, built: any)
	local findings = built.handle.controller.diagnostics()
	if #findings > 0 then
		local lines = {}
		for _, finding in findings do
			local node = w.adapter.node(finding.node)
			local rect = if node ~= nil and node.rect ~= nil
				then string.format(" [box %dx%d at %d,%d]", node.rect.w, node.rect.h, node.rect.x, node.rect.y)
				else ""
			table.insert(lines, `  {finding.node}{rect}\n      {finding.issue}`)
		end
		error(`{label}: the solver reports {#findings} diagnostic(s):\n{table.concat(lines, "\n")}`, 0)
	end
	expect(#findings).toBe(0)
end

-- Put every string in a fixture's exported `copy` table through a ~1.4x
-- pseudo-localizing expansion, run `body`, and put the originals back on every
-- path including a throw. The module table is shared, so this is a real
-- expansion of the real surface rather than a parallel one.
local function underPseudoLocalization(module: any, body: () -> ())
	local original: { [string]: string } = {}
	for key, value in module.copy do
		original[key] = value
		module.copy[key] = l10n.pseudoLocalize(value)
	end
	local ok, err = pcall(body)
	for key, value in original do
		module.copy[key] = value
	end
	if not ok then
		error(err, 0)
	end
end

-- A text node that declares no `lineLimit` is `policy = "none"` text (§15.3): it
-- must FIT, wrapping if it has to, and never clip. `truncated` is the solver's
-- own answer for that node at its real font and its real box, which is why this
-- reads it rather than comparing string widths.
local function expectUnclipped(label: string, built: any, paths: { string })
	for _, path in paths do
		local facts = built.handle.controller.textAt(path)
		if facts == nil then
			error(`{label}: no measured text at {path} — the assertion below would be vacuous`, 0)
		end
		expect(`{path} truncated:{facts.truncated}`).toBe(`{path} truncated:false`)
		expect(facts.lines >= 1).toBe(true)
	end
end

-- ---------------------------------------------------------------------------
-- card_rail — newVirtualList `axis = "x"`
-- ---------------------------------------------------------------------------
describe('examples/gallery fixture: card rail (newVirtualList axis = "x")', function()
	local module = require("../examples/gallery/scenarios/card_rail") :: any
	local RAIL = "/CardRail/Page/RailPane/Rail"
	local CANVAS = RAIL .. "/Canvas"
	local CARD_GAP, CARDS = 8, 400
	--[[ THE CARD WIDTH IS THE PARADIGM'S ANSWER, NOT THIS FILE'S (ADAPT-17). It was
		a pinned 132 until the rail started deriving it from how many cards belong in
		view — so every number below is read off the control that resolved it, which
		is the same rule this fixture's own `report()` already keeps for the rail
		width. A pin here would test the constant, not the rail. ]]
	local function cardExtent(built: any): number
		return built.rail.dump().itemExtent
	end

	local function railWorld(view: any)
		local w = fixtureWorld(view)
		local built = mountFixture(w, module)
		return w, built
	end
	-- the item's hit node: `pathOf` answers relative to the LIST, so the surface
	-- prefix is added here rather than hardcoded twice
	local function hitPath(built: any, key: string): string
		return "/CardRail/Page/RailPane" .. (built.rail.pathOf(key) :: string) .. "/Hit"
	end

	it("mounts under the showcase's own chrome with ZERO solver diagnostics", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = railWorld(view)
			expectNoDiagnostics(`card_rail at {view.w}x{view.h}`, w, built)
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	end)

	it("windows a full-WIDTH canvas: 400 cards, a handful mounted, the rest not built", function()
		local w, built = railWorld(DESKTOP)
		local canvas = w.adapter.node(CANVAS)
		expect(canvas ~= nil).toBe(true)
		-- N items span N*extent + (N-1)*gap along the SCROLL axis, and that axis is
		-- x here: a vertical virtualizer would have put this number on the height
		expect(canvas.rect.w).toBe(CARDS * cardExtent(built) + (CARDS - 1) * CARD_GAP)
		expect(canvas.rect.h <= w.adapter.node(RAIL).rect.h).toBe(true)
		-- ...and only a window of it exists
		local mounted = built.steps.mountedCount()
		expect(mounted > 0).toBe(true)
		expect(mounted < 30).toBe(true)
		expect(built.report().total).toBe(CARDS)
		built.dispose()
	end)

	it("the rail's width is re-derived from the viewport, never a constant", function()
		local narrowW, narrow = railWorld(NARROW_PORTRAIT)
		local wideW, wide = railWorld(DESKTOP)
		local narrowExtent = narrow.report().viewportExtent
		local wideExtent = wide.report().viewportExtent
		expect(wideExtent > narrowExtent).toBe(true)
		-- and neither one paints past the screen it was derived from
		expect(narrowW.adapter.node(RAIL).rect.w <= NARROW_PORTRAIT.w).toBe(true)
		expect(wideW.adapter.node(RAIL).rect.w <= DESKTOP.w).toBe(true)
		narrow.dispose()
		wide.dispose()
	end)

	it("keyboard: Left/Right step the rail — and Up/Down do nothing at all", function()
		-- THE DISCRIMINATOR for "the list declares its own axis to the focus
		-- graph". A group still saying `vertical` would step on Up/Down here and be
		-- dead on Left/Right, which is a rail no keyboard can reach.
		local w, built = railWorld(DESKTOP)
		expect(w.presenter.focus.focused:get()).toBe(hitPath(built, "c1"))
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(built.rail.focusedKey:get()).toBe("c2")
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(built.rail.focusedKey:get()).toBe("c3")
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		expect(built.rail.focusedKey:get()).toBe("c2")
		for _, key in { "Down", "Up" } do
			w.system.deviceKey(key, true)
			w.system.deviceKey(key, false)
			expect(`{key} moved focus to {tostring(built.rail.focusedKey:get())}`).toBe(`{key} moved focus to c2`)
		end
		expect(w.core:lastError()).toBeNil()
		built.dispose()
	end)

	it("gamepad: the D-pad steps it sideways and A picks the focused card", function()
		local w, built = railWorld(DESKTOP)
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(built.rail.focusedKey:get()).toBe("c3")
		w.system.deviceKey("DPadLeft", true)
		w.system.deviceKey("DPadLeft", false)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(built.rail.selectedKey:get()).toBe("c2")
		built.dispose()
	end)

	it("keyboard: Return picks the focused card, and the surface SAYS which one", function()
		local w, built = railWorld(DESKTOP)
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(built.rail.selectedKey:get()).toBe("c2")
		w.presenter.refresh()
		-- the player-visible consequence, not just the signal: a pick nobody can
		-- see on screen is a pick that proves nothing about the fixture
		local shown = w.adapter.node("/CardRail/Page/Selected").props.text
		expect(string.find(shown, "Livery 002", 1, true) ~= nil).toBe(true)
		built.dispose()
	end)

	it("pointer and touch: a tap picks the card it landed on", function()
		for _, pointer in { "mouse", "touch" } do
			local w, built = railWorld(DESKTOP)
			w.adapter.tap(hitPath(built, "c4"), { pointer = pointer })
			expect(`{pointer}:{tostring(built.rail.selectedKey:get())}`).toBe(`{pointer}:c4`)
			built.dispose()
		end
	end)

	it("binds its own engine-scroll mirror with no scripted step (the showcase path)", function()
		-- The showcase's generic auto-bind loop runs only on the tutorial-EXAMPLE
		-- branch, so a fixture that waited for a `bind` step would never mirror
		-- CanvasPosition for the one host where a real thumb does the scrolling.
		local w, built = railWorld(DESKTOP)
		expect(built.report().bound).toBe(false)
		w.presenter.tick(1 / 60)
		expect(built.report().bound).toBe(true)
		built.dispose()
	end)

	it("a sideways engine scroll slides the window along X", function()
		local w, built = railWorld(DESKTOP)
		w.presenter.tick(1 / 60)
		expect(built.rail.debugWindow().c1).toBe(true)
		w.adapter.driveScroll(RAIL, { x = 1400, y = 0 })
		w.presenter.refresh()
		-- `scrollTop` mirrors CanvasPosition.X on this axis: the name predates the
		-- field and is public API
		expect(built.rail.scrollTop:get()).toBe(1400)
		expect(built.rail.debugWindow().c1).toBe(nil)
		local index = math.floor(1400 / (cardExtent(built) + CARD_GAP)) + 1
		expect(built.rail.debugWindow()[`c{index}`]).toBe(true)
		-- a Y scroll is not this list's axis and must not move its window
		w.adapter.driveScroll(RAIL, { x = 1400, y = 900 })
		w.presenter.refresh()
		expect(built.rail.scrollTop:get()).toBe(1400)
		expect(w.core:lastError()).toBeNil()
		built.dispose()
	end)

	it("keep-visible scrolls a far-off card into the band on the X axis", function()
		local w, built = railWorld(DESKTOP)
		w.presenter.tick(1 / 60)
		built.steps.focusEnd()
		w.presenter.refresh()
		local left = built.rail.scrollTop:get()
		expect(left > 0).toBe(true)
		local last = (CARDS - 1) * (cardExtent(built) + CARD_GAP)
		expect(last >= left).toBe(true)
		expect(last + cardExtent(built) <= left + built.report().viewportExtent + 1).toBe(true)
		expect(built.rail.debugWindow()[`c{CARDS}`]).toBe(true)
		built.dispose()
	end)

	it("its chrome copy survives a 1.4x pseudo-localization without clipping", function()
		underPseudoLocalization(module, function()
			for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE } do
				local w, built = railWorld(view)
				expectNoDiagnostics(`card_rail pseudo-localized at {view.w}x{view.h}`, w, built)
				expectUnclipped(
					`card_rail at {view.w}x{view.h}`,
					built,
					{ "/CardRail/Page/Title", "/CardRail/Page/Hint", "/CardRail/Page/Selected" }
				)
				built.dispose()
			end
		end)
		-- the strings really did come back, or every case after this one is a lie
		expect(string.find(module.copy.title, "Card rail", 1, true) ~= nil).toBe(true)
	end)
end)

-- ---------------------------------------------------------------------------
-- with_animation — presenter.withAnimation, and the Full|Reduced control
-- ---------------------------------------------------------------------------
describe("examples/gallery fixture: withAnimation + reduced motion", function()
	local module = require("../examples/gallery/scenarios/with_animation") :: any
	local PAGE = "/MotionDemo/Page"
	local RUN = PAGE .. "/Run"
	local STAGE = PAGE .. "/Stage/Decorative"
	local PUCK = STAGE .. "/Lane/Puck"
	local PANEL = STAGE .. "/Detail/then/Panel"
	local CARD = STAGE .. "/Card"
	local CARD_PIP = CARD .. "/Pip"
	-- ONE LEVEL DEEPER since navigation-and-menus D6: this picker is declared
	-- `segmented`, and the segmented presentation now paints the sliding indicator
	-- by default, which shares a parent with the option stack.
	local FULL_OPTION = PAGE .. "/MotionMode/Indicator/Options/Opt1"
	local REDUCED_OPTION = PAGE .. "/MotionMode/Indicator/Options/Opt2"
	local FRAME = 1 / 60

	local function chipPath(name: string): string
		return `{STAGE}/Chips/Order/[{name}]/Chip`
	end
	local function motionWorld(view: any?)
		local w = fixtureWorld(view or DESKTOP)
		local built = mountFixture(w, module)
		return w, built
	end
	-- `container` responds in 0.35 s; 200 frames is ~3.3 s of clock, and every
	-- assertion below is on the terminal state rather than on a frame count
	local function settleMotion(w: any)
		for _ = 1, 200 do
			w.presenter.tick(FRAME)
		end
	end

	it("mounts under the showcase's own chrome with ZERO solver diagnostics", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = motionWorld(view)
			expectNoDiagnostics(`with_animation at {view.w}x{view.h}`, w, built)
			-- ...and still zero mid-flight, which is the state a fixture that
			-- animates can reach and a static one cannot
			w.adapter.tap(RUN)
			for _ = 1, 5 do
				w.presenter.tick(FRAME)
			end
			settleFixture(w.presenter)
			expectNoDiagnostics(`with_animation mid-flight at {view.w}x{view.h}`, w, built)
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	end)

	it(
		"one press, four consequences: something moves, something GROWS, something appears, something re-orders",
		function()
			local w, built = motionWorld()
			local puckBefore = w.adapter.node(PUCK).rect.x
			local alphaBefore = w.adapter.node(chipPath("Alpha")).rect.x
			local deltaBefore = w.adapter.node(chipPath("Delta")).rect.x
			local cardBefore = w.adapter.node(CARD).rect.h
			expect(w.adapter.node(PANEL)).toBe(nil)

			w.adapter.tap(RUN)

			-- (1) MOVED: the puck's solved rect is at the other end of its lane
			expect(w.adapter.node(PUCK).rect.x > puckBefore).toBe(true)
			-- (2) GREW: the card's solved height is the new one, exactly and instantly
			expect(w.adapter.node(CARD).rect.h > cardBefore).toBe(true)
			-- (3) APPEARED: the panel exists now
			expect(w.adapter.node(PANEL) ~= nil).toBe(true)
			-- (4) RE-ORDERED: the two end chips have swapped places, and they kept
			-- their identity while doing it (a rebuild would have changed the paths)
			expect(w.adapter.node(chipPath("Alpha")).rect.x).toBe(deltaBefore)
			expect(w.adapter.node(chipPath("Delta")).rect.x).toBe(alphaBefore)
			expect(built.chipOrder:get()[1]).toBe("Delta")
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	)

	--[[ THE BADGE — the fifth consequence, and the director's own question
		(2026-08-14): *"should opacity, transparency, and scale get
		owned/influenced by facet? it seems like we should be able to animate
		those."*

		THREE ASSERTIONS, and each of them fails against a DIFFERENT plausible
		defect, which is why none of them is redundant:

		  · the three engine values REACH their destinations — a design that
		    accepted the props and never composed them passes nothing here;
		  · the LAYOUT BOX does not move — scale and rotation are paint, and a
		    design that let either reach the solver would move the tap target;
		  · the values TRAVEL rather than snapping, and they travel at the SAME
		    fraction as the puck's position — four independent tweens would land in
		    the right places and drift on the way, which no end-state check sees. ]]
	it("the BADGE fades, shrinks and turns — on the puck's own spring, and its BOX never moves", function()
		local w, built = motionWorld()
		local BADGE = STAGE .. "/Effects/Badge"
		local boxBefore = w.adapter.node(BADGE).rect
		local puckBefore = w.adapter.node(PUCK).rect.x
		local cardBefore = w.adapter.node(CARD).rect.h

		w.adapter.tap(RUN)

		--[[ THE SOLVER NEVER SAW ANY OF THE THREE, stated as a differential rather
			than as "nothing moved" — because something DID move it. The card above
			this badge grows on the same press, so the badge's `y` slides down by
			exactly the card's growth and by nothing else. Asserting `y` was
			unchanged would have been a check that fails for the wrong reason;
			asserting the delta EQUALS the card's is the check that proves the scale
			and the rotation contributed zero to layout. ]]
		local boxAfter = w.adapter.node(BADGE).rect
		expect(boxAfter.x).toBe(boxBefore.x)
		expect(boxAfter.w).toBe(boxBefore.w)
		expect(boxAfter.h).toBe(boxBefore.h)
		expect(boxAfter.y - boxBefore.y).toBe(w.adapter.node(CARD).rect.h - cardBefore)

		-- SEEDED at the old paint, not the new one
		expect(w.adapter.node(BADGE).canvasGroupInstance.groupTransparency).toBeCloseTo(0)
		local puckAfter = w.adapter.node(PUCK).rect.x

		-- ...and mid-flight every one of them is at the SAME fraction as the puck
		for _ = 1, 8 do
			w.presenter.tick(FRAME)
			local node = w.adapter.node(BADGE)
			local alpha = node.canvasGroupInstance.groupTransparency
			local painted = w.adapter.node(PUCK).presentedPosition.x
			local moveFrac = (painted - puckBefore) / (puckAfter - puckBefore)
			-- opacity 1 -> 0.3 means transparency 0 -> 0.7
			expect(alpha / 0.7).toBeCloseTo(moveFrac, 1e-3)
			-- scale 1 -> 0.6 and rotation 0 -> 45, on the same fraction
			expect((1 - node.motionScaleInstance.scale) / 0.4).toBeCloseTo(moveFrac, 1e-3)
			expect(node.rotation / 45).toBeCloseTo(moveFrac, 1e-3)
		end

		settleMotion(w)
		local settled = w.adapter.node(BADGE)
		expect(settled.canvasGroupInstance.groupTransparency).toBeCloseTo(0.7)
		expect(settled.motionScaleInstance.scale).toBeCloseTo(0.6)
		expect(settled.rotation).toBeCloseTo(45)
		expect(built.report().badgeRotation).toBe(45)
		expect(w.core:lastError()).toBeNil()
		built.dispose()
	end)

	it("REDUCED MOTION lands the badge's three values instantly, and never deletes one", function()
		local w, built = motionWorld()
		local BADGE = STAGE .. "/Effects/Badge"
		built.steps.setMotion(built, "reduced")
		w.adapter.tap(RUN)
		-- no flight at all, and the destination is exact on the frame the call returns
		expect(w.presenter.animationRecordCount()).toBe(0)
		local node = w.adapter.node(BADGE)
		expect(node.canvasGroupInstance.groupTransparency).toBeCloseTo(0.7)
		expect(node.motionScaleInstance.scale).toBeCloseTo(0.6)
		expect(node.rotation).toBeCloseTo(45)
		built.dispose()
	end)

	--[[ THE CARD, AND THE LESSON IT IS SHAPED TO TEACH (withAnimation size,
		2026-08-14). Before round 3 this fixture had nothing that changed size, so
		the one thing `withAnimation` could not do was also the one thing nobody
		could see it failing to do. The card is that hole closed, and it is built
		around the asymmetry an author has to know: a POSITION delta accumulates
		down a subtree and a SIZE delta does not, so the label pinned to the card's
		top stays exactly where it is while the box opens underneath it.

		Both halves are asserted, because either alone passes against a defect:
		"the card's paint travels" is satisfied by a design that also stretched its
		children, and "the label did not move" is satisfied by a card that snapped. ]]
	it("the CARD's painted height travels — and the pip inside it does not move or stretch", function()
		local w, built = motionWorld()
		local cardBefore = w.adapter.node(CARD).rect.h
		local pipBefore = w.adapter.node(CARD_PIP).rect.y
		w.adapter.tap(RUN)
		local card = w.adapter.node(CARD)
		-- solved: at its destination on the frame the press returns
		expect(card.rect.h > cardBefore).toBe(true)
		-- painted: still at the old height, so it has somewhere to travel FROM
		expect(card.presentedSize.h).toBe(cardBefore)
		w.presenter.tick(FRAME)
		local mid = w.adapter.node(CARD).presentedSize.h
		expect(mid > cardBefore).toBe(true)
		expect(mid < card.rect.h).toBe(true)
		-- ...and THE PIP DID NOT MOVE OR STRETCH, at the seed or mid-flight: it is
		-- pinned to the top of a box that is growing downward, and a size delta
		-- that leaked into the subtree would show up here first
		local pip = w.adapter.node(CARD_PIP)
		expect(pip.rect.y).toBe(pipBefore)
		expect(pip.presentedPosition.y).toBe(pipBefore)
		expect(pip.presentedSize.h).toBe(pip.rect.h)
		settleMotion(w)
		local landed = w.adapter.node(CARD)
		expect(landed.presentedSize.h).toBe(landed.rect.h)
		expect(w.core:lastError()).toBeNil()
		built.dispose()
	end)

	it("the card rides the SAME spring as the puck — one call, one curve", function()
		local w, built = motionWorld()
		local puckFrom = w.adapter.node(PUCK).rect.x
		local cardFrom = w.adapter.node(CARD).rect.h
		w.adapter.tap(RUN)
		local puckTo = w.adapter.node(PUCK).rect.x
		local cardTo = w.adapter.node(CARD).rect.h
		for _ = 1, 8 do
			w.presenter.tick(FRAME)
		end
		-- the same ratio discipline the puck-vs-chips case uses, across the two
		-- DIFFERENT property kinds: a size half driven by its own spring would
		-- agree with the position half only by coincidence
		local puckP = (w.adapter.node(PUCK).presentedPosition.x - puckFrom) / (puckTo - puckFrom)
		local cardP = (w.adapter.node(CARD).presentedSize.h - cardFrom) / (cardTo - cardFrom)
		expect(math.abs(puckP - cardP) < 0.02).toBe(true)
		built.dispose()
	end)

	it("the solver stays exact and instant; only the PAINT travels", function()
		local w, built = motionWorld()
		local puckBefore = w.adapter.node(PUCK).rect.x
		w.adapter.tap(RUN)
		local puck = w.adapter.node(PUCK)
		-- geometry: already at its destination on the frame the press returns
		expect(puck.rect.x > puckBefore).toBe(true)
		-- paint: still where it was, so it has somewhere to travel FROM
		expect(puck.presentedPosition.x).toBe(puckBefore)
		w.presenter.tick(FRAME)
		local mid = w.adapter.node(PUCK).presentedPosition.x
		expect(mid > puckBefore).toBe(true)
		expect(mid < puck.rect.x).toBe(true)
		built.dispose()
	end)

	it("ONE shared spring: the flights start together, run together and land together", function()
		local w, built = motionWorld()
		local puckFrom = w.adapter.node(PUCK).rect.x
		local alphaFrom = w.adapter.node(chipPath("Alpha")).rect.x
		local commitsBefore = w.presenter.commitCount()
		w.adapter.tap(RUN)
		-- ONE ARMED COMMIT, and this is the half that can actually fail. Progress
		-- alone cannot tell "one shared spring" from "three identical springs
		-- started on the same frame" — they are in lockstep either way, and a
		-- mutation splitting the body into three `withAnimation` calls was measured
		-- passing every ratio assertion below. What separates them is that each
		-- call forces its OWN commit: three calls are three. (The same reasoning
		-- tests/with_animation.spec.luau records for its own two-call case: assert
		-- on commits, because an animation-SET count would not have caught it.)
		expect(w.presenter.commitCount() - commitsBefore).toBe(1)
		local puckTo = w.adapter.node(PUCK).rect.x
		local alphaTo = w.adapter.node(chipPath("Alpha")).rect.x
		expect(puckTo ~= puckFrom).toBe(true)
		expect(alphaTo ~= alphaFrom).toBe(true)
		-- SHARED PROGRESS is the claim, so it is measured as a RATIO: at any frame
		-- mid-flight each node has covered the same fraction of its own distance.
		-- Two independent springs would agree only by coincidence.
		for _ = 1, 8 do
			w.presenter.tick(FRAME)
		end
		local puckP = (w.adapter.node(PUCK).presentedPosition.x - puckFrom) / (puckTo - puckFrom)
		local alphaP = (w.adapter.node(chipPath("Alpha")).presentedPosition.x - alphaFrom) / (alphaTo - alphaFrom)
		expect(puckP > 0.02 and puckP < 0.98).toBe(true) -- genuinely mid-flight
		expect(math.abs(puckP - alphaP) < 0.02).toBe(true)
		-- ...and the channel is clean once they arrive
		settleMotion(w)
		expect(w.presenter.animationRecordCount()).toBe(0)
		for _, path in { PUCK, chipPath("Alpha"), chipPath("Delta") } do
			local node = w.adapter.node(path)
			expect(`{path} landed:{node.presentedPosition.x == node.rect.x}`).toBe(`{path} landed:true`)
		end
		built.dispose()
	end)

	it("the appearing panel installs no record of its own — that is the transition system's job", function()
		local w, built = motionWorld()
		w.adapter.tap(RUN)
		local panel = w.adapter.node(PANEL)
		expect(panel ~= nil).toBe(true)
		expect(panel.presentedPosition.y).toBe(panel.rect.y)
		-- ...while the things it displaced DO fly, so the case is not vacuous
		expect(w.presenter.animationRecordCount() > 0).toBe(true)
		local chip = w.adapter.node(chipPath("Bravo"))
		expect(chip.presentedPosition.y ~= chip.rect.y).toBe(true)
		built.dispose()
	end)

	it("the control is a SEGMENTED Full | Reduced, and the words 'On'/'Off' appear nowhere", function()
		local w, built = motionWorld()
		expect(w.adapter.node(FULL_OPTION).props.label).toBe("Full")
		expect(w.adapter.node(REDUCED_OPTION).props.label).toBe("Reduced")
		-- segmented is DECLARED, not inherited from the adaptive rule: the two
		-- options must read as peers even on a compact phone
		local narrowWorld, narrowBuilt = motionWorld(NARROW_PORTRAIT)
		expect(narrowWorld.adapter.node(FULL_OPTION) ~= nil).toBe(true)
		expect(narrowWorld.adapter.node(REDUCED_OPTION) ~= nil).toBe(true)
		-- the options sit SIDE BY SIDE (the segmented arrangement), not stacked
		local a = narrowWorld.adapter.node(FULL_OPTION).rect
		local b = narrowWorld.adapter.node(REDUCED_OPTION).rect
		expect(b.x > a.x).toBe(true)
		expect(a.y).toBe(b.y)
		-- and the label is never the binary one the effect is not
		for _, value in module.copy do
			expect(`copy '{value}' says off:{string.lower(value) == "off" or string.lower(value) == "on"}`).toBe(
				`copy '{value}' says off:false`
			)
		end
		narrowBuilt.dispose()
		built.dispose()
	end)

	it("Reduced removes the DECORATIVE travel entirely — layout exact, no records, nothing in flight", function()
		local w, built = motionWorld()
		w.adapter.tap(REDUCED_OPTION) -- the player's own route to it
		w.presenter.refresh()
		expect(built.motionMode:get()).toBe("reduced")
		expect(w.env:get("reducedMotion"):get()).toBe(true)
		expect(w.env:get("motionPolicy"):get()).toBe("reduced")

		local puckBefore = w.adapter.node(PUCK).rect.x
		w.adapter.tap(RUN)
		local puck = w.adapter.node(PUCK)
		-- the layout still happened, exactly...
		expect(puck.rect.x ~= puckBefore).toBe(true)
		expect(w.adapter.node(PANEL) ~= nil).toBe(true)
		expect(built.chipOrder:get()[1]).toBe("Delta")
		-- ...and nothing was installed to travel it. "Installed and cleared" is the
		-- bug: a settle-ordering slip then paints a stale delta forever.
		expect(w.presenter.animationRecordCount()).toBe(0)
		expect(puck.presentedPosition.x).toBe(puck.rect.x)
		built.dispose()
	end)

	it("...and the INFORMATIONAL half keeps running under Reduced, quantized rather than deleted", function()
		-- THE WHOLE POINT OF THE FIXTURE, and the reason its control may never say
		-- "off": decorative motion snaps, informational motion steps
		-- (src/motion/motion.luau:31-42). Both columns run off the same press.
		local function samplesUnder(mode: string): (number, number)
			local w, built = motionWorld()
			if mode == "reduced" then
				w.adapter.tap(REDUCED_OPTION)
				w.presenter.refresh()
			end
			w.adapter.tap(RUN)
			local distinct, last = 0, nil
			for _ = 1, 150 do
				w.presenter.tick(FRAME)
				local value = built.charge:get()
				if value ~= last then
					distinct += 1
					last = value
				end
			end
			local terminal = built.charge:get()
			built.dispose()
			return distinct, terminal
		end

		local fullSteps, fullEnd = samplesUnder("full")
		local reducedSteps, reducedEnd = samplesUnder("reduced")
		-- NOTHING IS SKIPPED: both arrive at the same terminus
		expect(fullEnd).toBe(1)
		expect(reducedEnd).toBe(1)
		-- ...but reduced publishes in countable steps rather than every frame. The
		-- ramp is 1.4 s at a 250 ms quantum, so ~6-8 of them; full is per-frame.
		expect(reducedSteps > 2).toBe(true)
		expect(reducedSteps <= 12).toBe(true)
		expect(fullSteps > 40).toBe(true)
	end)

	it("four inputs reach the demonstration: pointer, touch, keyboard and gamepad", function()
		-- pointer and touch on the button
		for _, pointer in { "mouse", "touch" } do
			local w, built = motionWorld()
			w.adapter.tap(RUN, { pointer = pointer })
			expect(`{pointer}:{built.laneRight:get()}`).toBe(`{pointer}:true`)
			built.dispose()
		end
		-- keyboard: Return on the focused button
		local kbWorld, kbBuilt = motionWorld()
		kbWorld.presenter.focus.focusOn(RUN)
		kbWorld.system.deviceKey("Return", true)
		kbWorld.system.deviceKey("Return", false)
		expect(kbBuilt.laneRight:get()).toBe(true)
		-- ...and the reduced-motion control is reachable the same way
		kbWorld.presenter.focus.focusOn(REDUCED_OPTION)
		kbWorld.system.deviceKey("Return", true)
		kbWorld.system.deviceKey("Return", false)
		expect(kbBuilt.motionMode:get()).toBe("reduced")
		kbBuilt.dispose()
		-- gamepad: A on the focused button
		local padWorld, padBuilt = motionWorld()
		padWorld.presenter.focus.focusOn(RUN)
		padWorld.system.deviceKey("ButtonA", true)
		padWorld.system.deviceKey("ButtonA", false)
		expect(padBuilt.laneRight:get()).toBe(true)
		padBuilt.dispose()
	end)

	it("carries the INDETERMINATE pair, and reduced motion steps them instead of stopping them", function()
		-- §3.1's claim, hands-on: the decorative half stops travelling under
		-- Reduced while these two go on sweeping. A fixture that only carried the
		-- decorative half would teach that reduced motion means no motion.
		local BUSY = PAGE .. "/Stage/Informational/Busy"
		local SPIN = PAGE .. "/Stage/Informational/Working/Spinner"
		local w, built = motionWorld()
		expect(w.adapter.node(BUSY .. "/Bar/Sweep/Fill") ~= nil).toBe(true)
		for index = 1, 5 do
			expect(w.adapter.node(`{SPIN}/Dot{index}`) ~= nil).toBe(true)
		end
		local function reading(): string
			local blends: { string } = {}
			for index = 1, 5 do
				table.insert(blends, string.format("%.3f", w.adapter.node(`{SPIN}/Dot{index}`).props.tint.blend))
			end
			return `{w.adapter.node(BUSY .. "/Bar/Sweep/Fill").rect.x}|{table.concat(blends, ",")}`
		end
		local function distinctOverASecond(): number
			local seen: { [string]: boolean } = {}
			local n = 0
			for _ = 1, 60 do
				w.presenter.tick(FRAME)
				settleFixture(w.presenter)
				local key = reading()
				if seen[key] == nil then
					seen[key] = true
					n += 1
				end
			end
			return n
		end
		local full = distinctOverASecond()
		w.adapter.tap(REDUCED_OPTION)
		local reduced = distinctOverASecond()
		expect(w.env:get("reducedMotion"):get()).toBe(true)
		-- STILL MOVING under reduced motion — the whole decision — and visibly
		-- coarser than full motion over the same wall clock
		expect(reduced > 1).toBe(true)
		expect(full > reduced).toBe(true)
		expect(w.core:lastError()).toBeNil()
		built.dispose()
	end)

	it("puts the environment back when it is dismissed", function()
		-- the toggle writes the REAL environment fact, which is what makes the demo
		-- honest; leaving it written after the player walks away is what would make
		-- it a trap for every OTHER demo in the same place
		local w, built = motionWorld()
		expect(w.env:get("reducedMotion"):get()).toBe(false)
		w.adapter.tap(REDUCED_OPTION)
		expect(w.env:get("reducedMotion"):get()).toBe(true)
		built.dispose()
		expect(w.env:get("reducedMotion"):get()).toBe(false)
	end)

	it("its copy survives a 1.4x pseudo-localization without clipping", function()
		underPseudoLocalization(module, function()
			for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE } do
				local w, built = motionWorld(view)
				w.adapter.tap(RUN) -- with the detail panel open, which is the taller shape
				settleFixture(w.presenter)
				expectNoDiagnostics(`with_animation pseudo-localized at {view.w}x{view.h}`, w, built)
				expectUnclipped(`with_animation at {view.w}x{view.h}`, built, {
					PAGE .. "/Title",
					STAGE .. "/Caption",
					PAGE .. "/Stage/Informational/Caption",
					PAGE .. "/Stage/Informational/Busy/Label",
					PAGE .. "/Stage/Informational/Working/Label",
					PANEL .. "/Body",
				})
				built.dispose()
			end
		end)
		expect(string.find(module.copy.title, "withAnimation", 1, true) ~= nil).toBe(true)
	end)
end)

-- ---------------------------------------------------------------------------
-- progress_ring — the CIRCULAR progress indicator, both forms (round 3 D2)
--
-- The showcase obligation for a new public API, met the same way `card_rail` and
-- `with_animation` meet it: the fixture is mounted exactly as the host mounts it,
-- and what is asserted here is the thing the fixture exists to demonstrate —
-- which the always-on overflow sweep structurally cannot ask.
-- ---------------------------------------------------------------------------
describe("examples/gallery fixture: circular progress, both forms", function()
	local module = require("../examples/gallery/scenarios/progress_ring") :: any
	local PAGE = "/ProgressRing/Page"
	local RING = PAGE .. "/Ring/Ring"
	local BUSY = PAGE .. "/Busy/Ring"

	local function ringWorld(view: any?)
		local w = fixtureWorld(view or DESKTOP)
		local built = mountFixture(w, module)
		return w, built
	end

	it("mounts under the showcase's own chrome with ZERO solver diagnostics", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = ringWorld(view)
			expectNoDiagnostics(`progress_ring at {view.w}x{view.h}`, w, built)
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	end)

	it("both forms are on screen: a filled ring, a rotating head, and the dot spinner", function()
		local w, built = ringWorld()
		-- determinate: an arc over its capacity ring
		expect(w.adapter.node(RING .. "/Track") ~= nil).toBe(true)
		expect(w.adapter.node(RING .. "/Arc") ~= nil).toBe(true)
		-- indeterminate: the head alone, no capacity ring behind it
		expect(w.adapter.node(BUSY .. "/Arc") ~= nil).toBe(true)
		expect(w.adapter.node(BUSY .. "/Track")).toBeNil()
		-- ...and the five-dot spinner is still here: it is the fallback if the
		-- arc's per-frame paint ever fails on a device, and the fixture is where
		-- the two are compared
		expect(w.adapter.node(PAGE .. "/Dots/Spinner/Dot5") ~= nil).toBe(true)
		expect(built.report().busyAnimating).toBe(true)
		built.dispose()
	end)

	it("the steps drive the ring's sweep, and the arc follows the value", function()
		local w, built = ringWorld()
		local function endpoint(): { x: number, y: number }
			local pts = w.adapter.node(RING .. "/Arc").props.points
			return pts[#pts]
		end
		expect(built.report().fraction).toBe(0.25)
		local at25 = endpoint()
		built.steps.setProgress65()
		settleFixture(w.presenter)
		expect(built.report().fraction).toBe(0.65)
		local at65 = endpoint()
		-- 25% ends at 3 o'clock; 65% is past 6 o'clock, on the other side
		expect(`moved:{math.abs(at65.x - at25.x) > 0.01 or math.abs(at65.y - at25.y) > 0.01}`).toBe("moved:true")
		-- the arc is inset from the box edge by half its stroke (CIRCULAR_RADIUS =
		-- 0.8), so 3 o'clock is x = 0.9 exactly, not the box edge
		expect(`x25=0.9:{math.abs(at25.x - 0.9) < 1e-6} x65<0.5:{at65.x < 0.5}`).toBe("x25=0.9:true x65<0.5:true")
		built.steps.setProgress100()
		settleFixture(w.presenter)
		expect(built.report().fraction).toBe(1)
		built.dispose()
	end)

	it("the indeterminate head TRAVELS when the surface's clock advances", function()
		local w, built = ringWorld()
		local function head(): number
			local p = w.adapter.node(BUSY .. "/Arc").props.points[1]
			return (math.deg(math.atan2(p.x - 0.5, 0.5 - p.y)) + 360) % 360
		end
		local before = head()
		built.steps.advance(built, "20")
		settleFixture(w.presenter)
		expect(`travelled:{math.abs(head() - before) > 0.001}`).toBe("travelled:true")
		expect(built.report().busyPhase > 0).toBe(true)
		built.dispose()
	end)

	it("its copy survives a 1.4x pseudo-localization without clipping", function()
		underPseudoLocalization(module, function()
			for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE } do
				local w, built = ringWorld(view)
				expectNoDiagnostics(`progress_ring pseudo-localized at {view.w}x{view.h}`, w, built)
				expectUnclipped(`progress_ring at {view.w}x{view.h}`, built, {
					PAGE .. "/Title",
					PAGE .. "/Caption",
					PAGE .. "/Ring/Label",
					PAGE .. "/Busy/Label",
					PAGE .. "/Dots/Label",
				})
				built.dispose()
			end
		end)
		expect(string.find(module.copy.title, "Circular", 1, true) ~= nil).toBe(true)
	end)
end)

-- ---------------------------------------------------------------------------
-- adaptive_controls — the round-2 LAYOUT VOCABULARY (§2.1/2.2/2.4/2.5/2.6, §3.3)
--
-- The standing obligation is that every new public API this round added appears
-- in at least one gallery scenario this file runs headlessly. `card_rail` and
-- `with_animation` above carry `newVirtualList{ axis = "x" }`,
-- `presenter.withAnimation` and the two indeterminate indicators. The six that
-- are left — `distribute`, `layoutPriority`, `shrinkWeight`, `lineAlign`,
-- `UI.GridRow`/`gridSpan` and `UI.containerRelativeFrame` — plus
-- `UI.sensoryFeedback` ride the all-controls fixture, which is where the plan
-- puts the adaptive ones (§Phase 4) and which is already picked from the chip
-- strip as "All controls".
--
-- EVERY CASE BELOW IS A DIFFERENCE, not a value. A layout prop is only doing
-- something if the geometry without it would be different, and the cheapest way
-- to ship an inert prop is to assert a number the default already produces. So
-- each case names the arrangement the DEFAULT would have given and asserts the
-- fixture is not at it — which is also what makes the mutation proofs bite.
-- ---------------------------------------------------------------------------
describe("examples/gallery fixture: all controls — the round-2 layout vocabulary", function()
	local module = require("../examples/gallery/scenarios/adaptive_controls") :: any
	local HUD = "/AdaptiveScreen/BodyScroll/Body/Hud"
	local SCROLL = "/AdaptiveScreen/BodyScroll"
	local SETTINGS = "/AdaptiveScreen/BodyScroll/Body/Settings"

	local function vocabWorld(view: any)
		local w = fixtureWorld(view)
		local built = mountFixture(w, module)
		return w, built
	end
	local function rectOf(w: any, path: string): any
		local node = w.adapter.node(path)
		if node == nil or node.rect == nil then
			error(`no rect at {path} — the assertion below would be vacuous`, 0)
		end
		return node.rect
	end

	it("mounts under the showcase's own chrome with ZERO solver diagnostics", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = vocabWorld(view)
			expectNoDiagnostics(`adaptive_controls at {view.w}x{view.h}`, w, built)
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	end)

	-- §2.6 -------------------------------------------------------------------
	it(
		"§2.6 `distribute = spaceBetween` puts the leftover in the GAPS: first at the start edge, last flush to the end",
		function()
			for _, view in { NARROW_PORTRAIT, DESKTOP } do
				local w, built = vocabWorld(view)
				local row = rectOf(w, HUD .. "/Legend")
				local low = rectOf(w, HUD .. "/Legend/LegendLow")
				local mid = rectOf(w, HUD .. "/Legend/LegendMid")
				local high = rectOf(w, HUD .. "/Legend/LegendHigh")
				expect(`low.x@{view.w}={low.x}`).toBe(`low.x@{view.w}={row.x}`)
				expect(`high.right@{view.w}={high.x + high.w}`).toBe(`high.right@{view.w}={row.x + row.w}`)
				-- ...and this is NOT what packing from the start would have produced:
				-- the middle marker sits well past `row.x + low.w`, which is exactly
				-- where `distribute = "start"` (the default) would have put it
				expect(`spread@{view.w}={mid.x > row.x + low.w + 1}`).toBe(`spread@{view.w}=true`)
				built.dispose()
			end
		end
	)

	-- §2.4 -------------------------------------------------------------------
	it("§2.4 with room, nothing shrinks: all three bars are at their natural 140", function()
		local w, built = vocabWorld(DESKTOP)
		for _, id in { "VocabOptional", "VocabUseful", "VocabEssential" } do
			expect(`{id}={rectOf(w, `{HUD}/Shrink/{id}`).w}`).toBe(`{id}=140`)
		end
		built.dispose()
	end)

	it(
		"§2.4 when the axis is short the LOWEST tier gives way first, and a weightless child never gives at all",
		function()
			-- 320x640: the HUD column is 279px (288 less the scroller's own reserve —
			-- the bar plus its gutter) and the row's natural is 432, so the deficit is
			-- real rather than arranged for the assertion
			local w, built = vocabWorld(NARROW_PORTRAIT)
			local row = rectOf(w, HUD .. "/Shrink")
			local optional = rectOf(w, HUD .. "/Shrink/VocabOptional")
			local useful = rectOf(w, HUD .. "/Shrink/VocabUseful")
			local essential = rectOf(w, HUD .. "/Shrink/VocabEssential")
			expect(`row={row.w}`).toBe("row=279")
			-- tier -1 is spent to its declared floor before tier 0 gives a pixel...
			expect(`optional={optional.w}`).toBe("optional=24")
			-- ...tier 0 then gives the remainder, and only the remainder
			expect(`useful={useful.w}`).toBe("useful=103")
			-- ...and `shrinkWeight = 0` (the default) is rigid whatever its siblings do
			expect(`essential={essential.w}`).toBe("essential=140")
			-- the row absorbed its whole deficit: it fits, so the overflow diagnostic
			-- that fires when everything is at its floor is NOT what made this pass
			expect(`sum={optional.w + useful.w + essential.w + 12}`).toBe(`sum={row.w}`)
			expectNoDiagnostics("adaptive_controls shrink row at 320x640", w, built)
			built.dispose()
		end
	)

	-- §2.1 -------------------------------------------------------------------
	it("§2.1 `lineAlign = end` sits the short bar on the BOTTOM of a line its siblings set", function()
		local w, built = vocabWorld(DESKTOP)
		local row = rectOf(w, HUD .. "/Shrink")
		local tall = rectOf(w, HUD .. "/Shrink/VocabUseful")
		local short = rectOf(w, HUD .. "/Shrink/VocabEssential")
		expect(`line={row.h} tall={tall.h} short={short.h}`).toBe("line=24 tall=24 short=16")
		-- bottom edges flush...
		expect(`short.bottom={short.y + short.h}`).toBe(`short.bottom={row.y + row.h}`)
		-- ...which is 8px BELOW where the row's own `align = "start"` puts its
		-- siblings, so the per-child override is what moved it
		expect(`short.y={short.y} tall.y={tall.y}`).toBe(`short.y={row.y + 8} tall.y={row.y}`)
		built.dispose()
	end)

	-- §2.5 -------------------------------------------------------------------
	it("§2.5 `containerRelativeFrame` measures against the SCROLLER's viewport, not the parent column", function()
		for _, view in { NARROW_PORTRAIT, DESKTOP } do
			local w, built = vocabWorld(view)
			local scroll = rectOf(w, SCROLL)
			local page = rectOf(w, HUD .. "/Page")
			-- (viewport - spacing x (count - 1)) / count x span, viewport = the
			-- scroller's inner width (its box less the RESERVE it holds back — the
			-- bar plus its one-pixel gutter, fake_target.SCROLL_BAR_RESERVE).
			-- ROUNDED, not floored: `num.roundPx` is what the solver's own
			-- `containerRelativeSize` spends, and the two agreed only by luck while
			-- the viewport happened to divide evenly by 3 — the gutter made it 279
			-- and 87.67 rounds UP (director report 2026-08-30).
			local viewport = scroll.w - fake_target.SCROLL_BAR_RESERVE
			expect(`page@{view.w}={page.w}`).toBe(`page@{view.w}={math.floor((viewport - 16) / 3 + 0.5)}`)
			built.dispose()
		end
	end)

	it("§2.5 ...and on a desktop that answer DIFFERS from a third of the parent column", function()
		-- THE CASE THAT DISTINGUISHES THE FEATURE, and it only exists at a width
		-- where the two candidates disagree. At 320 the Body stacks, so the HUD
		-- column IS the scroller's viewport and a `percent` dim would have given the
		-- identical number — an assertion there proves nothing about which container
		-- was measured. On a desktop the Body is side by side and the column is about
		-- half the scroller, so the two answers are ~200px apart.
		local w, built = vocabWorld(DESKTOP)
		local scroll = rectOf(w, SCROLL)
		local column = rectOf(w, HUD)
		local page = rectOf(w, HUD .. "/Page")
		local viewport = scroll.w - fake_target.SCROLL_BAR_RESERVE
		expect(`column={column.w} viewport={viewport}`).toBe(`column=587 viewport=1191`)
		expect(`page={page.w}`).toBe(`page={math.floor((viewport - 16) / 3 + 0.5)}`)
		-- the parent-relative reading, which this is NOT
		expect(page.w > math.floor((column.w - 16) / 3) + 100).toBe(true)
		built.dispose()
	end)

	-- §2.2 -------------------------------------------------------------------
	it(
		"§2.2 a Grid of `UI.GridRow`s aligns its columns across rows, and `gridSpan` covers both plus the gap",
		function()
			local w, built = vocabWorld(DESKTOP)
			local aKey, aVal = rectOf(w, HUD .. "/Specs/SpecA/SpecAKey"), rectOf(w, HUD .. "/Specs/SpecA/SpecAVal")
			local bKey, bVal = rectOf(w, HUD .. "/Specs/SpecB/SpecBKey"), rectOf(w, HUD .. "/Specs/SpecB/SpecBVal")
			local title = rectOf(w, HUD .. "/Specs/SpecHead/SpecTitle")
			-- COLUMN 1 is the widest natural key, not each row's own width: "Span" is
			-- narrower than "Columns" and still starts its value at the same x
			expect(`bKey.w={bKey.w} aKey.w={aKey.w}`).toBe(`bKey.w={bKey.w} aKey.w=53`)
			expect(bKey.w < aKey.w).toBe(true)
			expect(`aVal.x={aVal.x}`).toBe(`aVal.x={bVal.x}`)
			expect(`aKey.x={aKey.x}`).toBe(`aKey.x={bKey.x}`)
			-- COLUMN 2 is the widest natural value across the rows
			local col1, col2 = aKey.w, bVal.w
			expect(`aVal.x={aVal.x}`).toBe(`aVal.x={aKey.x + col1 + 6}`)
			-- THE SPAN covers both columns AND the gap between them — a spanning cell
			-- that forgot the gap would be 6px short, and one that took a single
			-- column would be `col1`
			expect(`title.w={title.w}`).toBe(`title.w={col1 + 6 + col2}`)
			expect(title.w > col1).toBe(true)
			built.dispose()
		end
	)

	-- §3.3 -------------------------------------------------------------------
	it(
		"§3.3 `UI.sensoryFeedback` emits the declared verb on the presenter's bus, stamped with the mounted path",
		function()
			local w, built = vocabWorld(DESKTOP)
			local events: { any } = {}
			local unsubscribe = w.presenter.onFeedback(function(event: any)
				table.insert(events, event)
			end)
			-- nothing fires from mounting alone: the modifier is a CHANGE, not a value
			expect(#events).toBe(0)
			built.steps.bumpVolume()
			expect(#events).toBe(1)
			expect(`{events[1].type} {events[1].path}`).toBe(`adjust {SETTINGS}/Volume`)
			built.steps.cycleQuality()
			expect(#events).toBe(2)
			expect(`{events[2].type} {events[2].path}`).toBe(`select {SETTINGS}/Quality`)
			-- ...and the fixture is still exactly the controls it was: Facet plays
			-- nothing, so the only trace of either verb is the event above
			expect(w.core:lastError()).toBeNil()
			unsubscribe()
			built.dispose()
		end
	)
end)

-- ---------------------------------------------------------------------------
-- variable_extents — `newVirtualList.itemExtent` as a per-item function
-- (game-director ruling 7, 2026-08-13)
-- ---------------------------------------------------------------------------
describe("examples/gallery fixture: variable item extents", function()
	local module = require("../examples/gallery/scenarios/variable_extents") :: any
	--[[ THE LIST LIVES INSIDE THE PANE WHOSE SOLVED HEIGHT IS ITS WINDOW
		(2026-08-14), so this path gained a segment. It is asserted rather than
		written, because a stale path here is a test that silently stops looking:
		`postRect` below answers nil for every row and the walk simply finds no rows
		— which is the failure this one produced when the pane landed, and the same
		class as `06_tile_game`'s readouts moving off their published paths. ]]
	local FEED = "/VariableExtents/ListPane/Feed"

	local function feedWorld(view: any)
		local w = fixtureWorld(view)
		return w, mountFixture(w, module)
	end

	local function postRect(w: any, key: string): any
		local node = w.adapter.node(`{FEED}/Canvas/W/[{key}]/Row/Hit`)
		return if node ~= nil then node.rect else nil
	end

	it("mounts under the showcase's own chrome with ZERO solver diagnostics", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = feedWorld(view)
			expectNoDiagnostics(`variable_extents at {view.w}x{view.h}`, w, built)
			expect(w.core:lastError()).toBeNil()
			-- THE PATH IS A CLAIM, so it is asserted once rather than assumed forty
			-- times: every row lookup in this describe hangs off `FEED`, and a path
			-- that no longer resolves turns each of them into a silent nil
			expect(`{view.w} feed at {FEED}: {w.adapter.node(FEED) ~= nil}`).toBe(`{view.w} feed at {FEED}: true`)
			built.dispose()
		end
	end)

	it("the posts really are DIFFERENT heights, and none overlaps its neighbour", function()
		--[[ WALK THE MOUNTED WINDOW, not a fixed row count: the whole point of the
			fixture is that the rows are different heights, so how many of them fit a
			320px phone is not a number this test may assume. Four distinct heights are
			asserted where the window is big enough to hold four (the desktop view);
			the NO-OVERLAP invariant is asserted on every mounted row at both. ]]
		for _, view in { NARROW_PORTRAIT, DESKTOP } do
			local w, built = feedWorld(view)
			local heights: { [number]: boolean } = {}
			local distinct, checked = 0, 0
			local previous: any = nil
			for i = 1, 40 do
				local r = postRect(w, `p{i}`)
				if r == nil then
					break
				end
				checked += 1
				if heights[r.h] == nil then
					heights[r.h] = true
					distinct += 1
				end
				if previous ~= nil then
					-- the next post starts at or after the previous one ends: a
					-- running-offset list that got its prefix sum wrong shows up here as
					-- a NEGATIVE gap, on the real solved boxes
					expect(`{view.w}: p{i} at {r.y} follows {previous.y + previous.h}`).toBe(
						`{view.w}: p{i} at {math.max(r.y, previous.y + previous.h)} follows {previous.y + previous.h}`
					)
				end
				previous = r
			end
			expect(`{view.w} mounted rows: {checked >= 4}`).toBe(`{view.w} mounted rows: true`)
			-- at least three of the four line counts are on screen even on the phone;
			-- the desktop window holds all four
			local want = if view.h > 700 then 4 else 3
			expect(`{view.w} distinct heights: {distinct >= want}`).toBe(`{view.w} distinct heights: true`)
			built.dispose()
		end
	end)

	it("THE TOGGLE IS THE ARGUMENT: one declared height for all of them is a LIE, and the solver says so", function()
		local w, built = feedWorld(NARROW_PORTRAIT)
		expectNoDiagnostics("variable_extents honest", w, built)

		built.steps.setMode(built, "uniform")
		settleFixture(w.presenter)
		local named = 0
		for _, finding in built.handle.controller.diagnostics() do
			if string.find(finding.issue, "itemExtent", 1, true) ~= nil then
				named += 1
			end
		end
		-- the taller posts now declare 84 and measure more; the guard names each
		expect(`lying rows named: {named > 0}`).toBe("lying rows named: true")

		-- ...and turning it back off silences every one of them, on the same nodes
		built.steps.setMode(built, "variable")
		settleFixture(w.presenter)
		expectNoDiagnostics("variable_extents back to honest", w, built)
		built.dispose()
	end)

	it("the four measured text offsets grow every row, and the list stays virtualized", function()
		local w, built = feedWorld(NARROW_PORTRAIT)
		local previousCanvas = 0
		for _, offset in { 0, 4, 10, 14 } do
			built.steps.setTextSize(built, tostring(offset))
			settleFixture(w.presenter)
			local r = built.report()
			expect(`+{offset} mode: {r.itemExtentMode}`).toBe(`+{offset} mode: variable`)
			-- every step is strictly taller than the last: the extents re-derived
			expect(`+{offset} grew: {r.contentExtent > previousCanvas}`).toBe(`+{offset} grew: true`)
			previousCanvas = r.contentExtent
			-- ...and the window did not grow with the canvas
			expect(`+{offset} mounted: {r.mounted < 20}`).toBe(`+{offset} mounted: true`)
			expectNoDiagnostics(`variable_extents at +{offset}`, w, built)
		end
		built.dispose()
	end)

	it("growing the text while scrolled keeps the SAME post under the top edge", function()
		local w, built = feedWorld(NARROW_PORTRAIT)
		built.steps.bind(built)
		settleFixture(w.presenter)
		built.steps.focusPost200(built)
		settleFixture(w.presenter)
		local moved = built.steps.growWhileScrolled(built, "14")
		settleFixture(w.presenter)
		-- the canvas is far longer at +14, so a fixed pixel offset would have
		-- landed on a different post entirely
		expect(`scroll moved: {moved.scrollAfter ~= moved.scrollBefore}`).toBe("scroll moved: true")
		expect(`first post held: {moved.firstAfter}`).toBe(`first post held: {moved.firstBefore}`)
		built.dispose()
	end)
end)

-- ---------------------------------------------------------------------------
-- flow_wrap — `UI.HStack{ wrap = true }` (parity round 3 item A)
-- ---------------------------------------------------------------------------
describe("examples/gallery fixture: flow wrap (UI.HStack wrap = true)", function()
	local module = require("../examples/gallery/scenarios/flow_wrap") :: any
	local CLOUD = "/FlowWrap/Page/Cloud"
	local ALIGN_BOX = "/FlowWrap/Page/AlignBox"

	local function wrapWorld(view: any)
		local w = fixtureWorld(view)
		return w, mountFixture(w, module)
	end

	-- the tag ids the fixture builds, in declaration order
	local function tagPath(n: number): string
		return `{CLOUD}/T{n}`
	end

	it("mounts under the showcase's own chrome with ZERO solver diagnostics", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = wrapWorld(view)
			expectNoDiagnostics(`flow_wrap at {view.w}x{view.h}`, w, built)
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	end)

	it("the tags really WRAP: more than one distinct row of y at every viewport", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = wrapWorld(view)
			local rows: { [number]: boolean } = {}
			local count = 0
			for i = 1, module.tagCount do
				local node = w.adapter.node(tagPath(i))
				expect(`{view.w}: tag {i} exists: {node ~= nil}`).toBe(`{view.w}: tag {i} exists: true`)
				if rows[node.rect.y] == nil then
					rows[node.rect.y] = true
					count += 1
				end
			end
			-- fourteen tags cannot fit one line at 1232 either — that is why the
			-- fixture ships fourteen and not four
			expect(`{view.w}x{view.h} lines: {count > 1}`).toBe(`{view.w}x{view.h} lines: true`)
			built.dispose()
		end
	end)

	it("...and NOTHING in a line overlaps its neighbour, at every viewport", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = wrapWorld(view)
			local placed: { any } = {}
			for i = 1, module.tagCount do
				local r = w.adapter.node(tagPath(i)).rect
				for _, other in placed do
					local overlaps = r.x < other.r.x + other.r.w
						and other.r.x < r.x + r.w
						and r.y < other.r.y + other.r.h
						and other.r.y < r.y + r.h
					if overlaps then
						error(
							`flow_wrap at {view.w}x{view.h}: tag {i} [{r.x},{r.y} {r.w}x{r.h}] overlaps `
								.. `tag {other.i} [{other.r.x},{other.r.y} {other.r.w}x{other.r.h}]`,
							0
						)
					end
				end
				table.insert(placed, { i = i, r = r })
			end
			built.dispose()
		end
	end)

	it("THE TOGGLE IS THE ARGUMENT: wrap off overflows, wrap on does not — same nodes", function()
		local w, built = wrapWorld(NARROW_PORTRAIT)
		local identity = tostring(w.adapter.node(tagPath(14)))
		expectNoDiagnostics("flow_wrap wrapping", w, built)

		built.steps.setWrap(built, "off")
		settleFixture(w.presenter)
		local overflowed = false
		for _, finding in built.handle.controller.diagnostics() do
			if string.find(finding.issue, "on the main axis", 1, true) ~= nil then
				overflowed = true
			end
		end
		expect(`wrap off overflows: {overflowed}`).toBe("wrap off overflows: true")

		built.steps.setWrap(built, "on")
		settleFixture(w.presenter)
		expectNoDiagnostics("flow_wrap wrapping again", w, built)
		-- ...and the flip was a RE-SOLVE, never a remount: the fourteenth tag is
		-- the same node it was before the round trip. A `UI.FlowStack` class behind
		-- a `UI.When` could not make this claim, which is why `wrap` is a prop.
		expect(tostring(w.adapter.node(tagPath(14)))).toBe(identity)
		built.dispose()
	end)

	it("`align` moves the BLOCK of lines, and only the block", function()
		local w, built = wrapWorld(DESKTOP)
		local boxRect = w.adapter.node(ALIGN_BOX).rect
		local function firstTagY(): number
			return w.adapter.node(`{ALIGN_BOX}/S1`).rect.y
		end
		local atStart = firstTagY()
		built.steps.setAlign(built, "center")
		settleFixture(w.presenter)
		local atCenter = firstTagY()
		built.steps.setAlign(built, "end")
		settleFixture(w.presenter)
		local atEnd = firstTagY()
		expect(`start<center<end: {atStart < atCenter and atCenter < atEnd}`).toBe("start<center<end: true")
		-- ...and the block never leaves the box it is aligned inside
		expect(`inside: {atEnd + w.adapter.node(`{ALIGN_BOX}/S1`).rect.h <= boxRect.y + boxRect.h}`).toBe(
			"inside: true"
		)
		expectNoDiagnostics("flow_wrap aligned end", w, built)
		built.dispose()
	end)

	it("pseudo-localized (~1.4x), it still wraps, still fits, and still clips nothing", function()
		underPseudoLocalization(module, function()
			for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
				local w, built = wrapWorld(view)
				expectNoDiagnostics(`flow_wrap pseudo-localized at {view.w}x{view.h}`, w, built)
				expectUnclipped(`flow_wrap at {view.w}x{view.h}`, built, {
					"/FlowWrap/Page/Title",
					"/FlowWrap/Page/CloudCaption",
					"/FlowWrap/Page/AlignCaption",
					"/FlowWrap/Page/Status",
				})
				built.dispose()
			end
		end)
	end)
end)

-- ---------------------------------------------------------------------------
-- lifecycle_hidden — `hidden`, `onAppear`, `onDisappear` (parity round 3 item D)
-- ---------------------------------------------------------------------------
describe("examples/gallery fixture: lifecycle hooks and hidden", function()
	local module = require("../examples/gallery/scenarios/lifecycle_hidden") :: any
	local PAGE = "/LifecycleHidden/Page"
	local REMOVED_NOTE = `{PAGE}/Removed/RemovedNote`
	local RESERVED_NOTE = `{PAGE}/Reserved/ReservedNote`
	local GHOST = `{PAGE}/Reserved/Ghost`

	local function lifeWorld(view: any)
		local w = fixtureWorld(view)
		return w, mountFixture(w, module)
	end

	it("mounts under the showcase's own chrome with ZERO solver diagnostics", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = lifeWorld(view)
			expectNoDiagnostics(`lifecycle_hidden at {view.w}x{view.h}`, w, built)
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	end)

	it("THE TWO PANELS ARE THE ARGUMENT: one caption moves, the other does not", function()
		-- the whole fixture in one assertion. `UI.When` removes its badge and the
		-- caption under it climbs; `hidden` keeps the slot and the caption under
		-- THAT one is byte-identical in both states.
		for _, view in { NARROW_PORTRAIT, DESKTOP } do
			local w, built = lifeWorld(view)
			local removedBefore = w.adapter.node(REMOVED_NOTE).rect.y
			local reservedBefore = w.adapter.node(RESERVED_NOTE).rect.y
			built.steps.setShowing(built, "off")
			settleFixture(w.presenter)
			local removedAfter = w.adapter.node(REMOVED_NOTE).rect.y
			local reservedAfter = w.adapter.node(RESERVED_NOTE).rect.y
			expect(`{view.w} removed moved: {removedAfter < removedBefore}`).toBe(`{view.w} removed moved: true`)
			expect(`{view.w} reserved: {reservedAfter - reservedBefore}`).toBe(`{view.w} reserved: 0`)
			built.dispose()
		end
	end)

	it("the kept slot stops painting and stops taking taps, and comes back", function()
		local w, built = lifeWorld(NARROW_PORTRAIT)
		expect(w.adapter.visibleOf(GHOST)).toBe(true)
		local box = w.adapter.node(GHOST).rect
		built.steps.setShowing(built, "off")
		settleFixture(w.presenter)
		expect(w.adapter.visibleOf(GHOST)).toBe(false)
		-- ...and it still has the SAME box, which is the whole capability
		local hiddenBox = w.adapter.node(GHOST).rect
		expect(`{hiddenBox.w}x{hiddenBox.h}`).toBe(`{box.w}x{box.h}`)
		-- a hidden badge fires no lifetime event of its own: hiding is a paint and
		-- interaction state, never a mount
		local beforeCounts = `{built.appearCount:get()}/{built.disappearCount:get()}`
		w.adapter.tap(GHOST, {})
		settleFixture(w.presenter)
		expect(`{built.appearCount:get()}/{built.disappearCount:get()}`).toBe(beforeCounts)
		built.steps.setShowing(built, "on")
		settleFixture(w.presenter)
		expect(w.adapter.visibleOf(GHOST)).toBe(true)
		built.dispose()
	end)

	it("the log and the counters are the only evidence a lifetime hook ran", function()
		local w, built = lifeWorld(NARROW_PORTRAIT)
		-- the badge is present at mount, so exactly one appearance has happened
		expect(`{built.appearCount:get()}/{built.disappearCount:get()}`).toBe("1/0")
		built.steps.setShowing(built, "off")
		settleFixture(w.presenter)
		expect(`{built.appearCount:get()}/{built.disappearCount:get()}`).toBe("1/1")
		built.steps.setShowing(built, "on")
		settleFixture(w.presenter)
		expect(`{built.appearCount:get()}/{built.disappearCount:get()}`).toBe("2/1")
		-- ...and the log is BOUNDED, so a player who flips the switch all afternoon
		-- cannot grow a Text past its page
		for _ = 1, module.logLines * 2 do
			built.steps.setShowing(built, "off")
			settleFixture(w.presenter)
			built.steps.setShowing(built, "on")
			settleFixture(w.presenter)
		end
		local lines = 1
		for _ in string.gmatch(built.logText:get(), "\n") do
			lines += 1
		end
		expect(`log lines: {lines}`).toBe(`log lines: {module.logLines}`)
		expectNoDiagnostics("lifecycle_hidden after many flips", w, built)
		built.dispose()
	end)

	it("teardown fires the badge's own disappear, so the count is never left short", function()
		local w, built = lifeWorld(NARROW_PORTRAIT)
		expect(`{built.appearCount:get()}/{built.disappearCount:get()}`).toBe("1/0")
		built.handle.controller.dispose()
		expect(`{built.appearCount:get()}/{built.disappearCount:get()}`).toBe("1/1")
		built.dispose()
	end)

	it("pseudo-localized (~1.4x), every line still reads whole and clips nothing", function()
		underPseudoLocalization(module, function()
			for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
				local w, built = lifeWorld(view)
				expectNoDiagnostics(`lifecycle_hidden pseudo-localized at {view.w}x{view.h}`, w, built)
				expectUnclipped(`lifecycle_hidden at {view.w}x{view.h}`, built, {
					`{PAGE}/Title`,
					`{PAGE}/Intro`,
					REMOVED_NOTE,
					RESERVED_NOTE,
					`{PAGE}/NoFire`,
				})
				built.dispose()
			end
		end)
	end)
end)

-- ---------------------------------------------------------------------------
-- text_degrade — the degrade cascade and the wrap rule (director rulings 1 & 5)
-- ---------------------------------------------------------------------------
describe("examples/gallery fixture: what a label gives up first", function()
	local module = require("../examples/gallery/scenarios/text_degrade") :: any
	local ROW = "/TextDegrade/Page/RowPanel/Row"
	local WRAP_BODY = "/TextDegrade/Page/WrapPanel/WrapBody"

	local function degradeWorld(view: any)
		local w = fixtureWorld(view)
		return w, mountFixture(w, module)
	end

	-- the fixture's own driver, so a case reads a rung by NAME rather than by a
	-- width literal it would have to keep in step with the scenario
	local function at(w: any, built: any, stop: string)
		built.steps.setStop(built, stop)
		settleFixture(w.presenter)
	end

	local function rowSpans(w: any): string
		local row = w.adapter.node(ROW).rect
		local out: { string } = {}
		for _, id in { "Sort", "Rank", "Date" } do
			local rect = w.adapter.node(`{ROW}/{id}`).rect
			table.insert(out, `{id}:{rect.x - row.x}..{rect.x - row.x + rect.w}`)
		end
		return table.concat(out, " ")
	end

	it("mounts under the showcase's own chrome, and only the LAST stop files a finding", function()
		-- the deliberate exception, and the reason it is stated as one: the
		-- Impossible stop exists to show the clip rung, so it MUST reach the
		-- overflow diagnostic — exactly as `flow_wrap`'s "wrapping off" state does.
		-- Every other stop must be silent, which is what makes the last one signal.
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = degradeWorld(view)
			for _, entry in module.stops do
				at(w, built, entry.value)
				local count = #built.handle.controller.diagnostics()
				if entry.value == "impossible" then
					expect(`{view.w}x{view.h} {entry.value} findings>0: {count > 0}`).toBe(
						`{view.w}x{view.h} {entry.value} findings>0: true`
					)
				else
					local detail = ""
					for _, d in built.handle.controller.diagnostics() do
						detail ..= ` [{d.node}] {string.sub(d.issue, 1, 90)}`
					end
					expect(`{view.w}x{view.h} {entry.value} findings: {count}{detail}`).toBe(
						`{view.w}x{view.h} {entry.value} findings: 0`
					)
				end
			end
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	end)

	it("THE ORDER IS THE ARGUMENT: it says it shorter BEFORE anything is cut", function()
		-- the whole fixture in one assertion, and stated as the ORDER rather than as
		-- four width literals: literals would have to be re-tuned for every theme and
		-- every viewport the showcase chrome hands this row, and re-tuning a literal
		-- until it passes is how a check stops meaning anything. What the ruling
		-- claims is a sequence, so the sequence is what is asserted.
		--
		-- Read off the ADAPTER: the drawn label is what a player sees, and asserting
		-- the declaration would be emission-not-application.
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = degradeWorld(view)
			local firstCompact, firstCut = nil, nil
			for index, entry in module.stops do
				at(w, built, entry.value)
				if firstCompact == nil and w.adapter.node(`{ROW}/Sort`).props.label == module.sortCompact then
					firstCompact = index
				end
				for _, id in { "Sort", "Rank", "Date" } do
					local facts = built.handle.controller.textAt(`{ROW}/{id}`)
					if firstCut == nil and facts ~= nil and facts.truncated == true then
						firstCut = index
					end
				end
			end
			local label = `{view.w}x{view.h}`
			-- both arms have to happen, or the surface never reaches the rungs it
			-- exists to show and this case passes by demonstrating nothing
			expect(`{label} compact={firstCompact ~= nil} cut={firstCut ~= nil}`).toBe(`{label} compact=true cut=true`)
			-- ...and the compact form is spent STRICTLY EARLIER than the first cut,
			-- which is the director's order: "switch to compact and THEN truncate"
			expect(`{label} compactAt<{firstCut}: {(firstCompact :: number) < (firstCut :: number)}`).toBe(
				`{label} compactAt<{firstCut}: true`
			)
			built.dispose()
		end
	end)

	it("the widest stop gives nothing up at all, so the sequence has a top", function()
		-- the negative control for the case above: at its first stop this row is a
		-- plain row of labels, full strings and no compact form. Without it, a
		-- fixture that started already degraded would satisfy every ordering claim.
		local w, built = degradeWorld(DESKTOP)
		at(w, built, module.stops[1].value)
		expect(`label={w.adapter.node(`{ROW}/Sort`).props.label}`).toBe(`label={module.copy.sortLabel}`)
		for _, id in { "Sort", "Rank", "Date" } do
			expect(`{id} cut={built.handle.controller.textAt(`{ROW}/{id}`).truncated}`).toBe(`{id} cut=false`)
		end
		built.dispose()
	end)

	it("nothing ever leaves the row, at any stop, at any viewport", function()
		-- the floor guarantee, asked of the surface rather than of the solver: this
		-- is the claim ruling 1 exists to make true, so the demo has to carry it.
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w, built = degradeWorld(view)
			for _, entry in module.stops do
				at(w, built, entry.value)
				local row = w.adapter.node(ROW).rect
				for _, id in { "Sort", "Rank", "Date" } do
					local rect = w.adapter.node(`{ROW}/{id}`).rect
					expect(`{entry.value}@{view.w} {id} inside: {rect.x + rect.w <= row.x + row.w}`).toBe(
						`{entry.value}@{view.w} {id} inside: true`
					)
				end
			end
			built.dispose()
		end
	end)

	it("the lower panel is ruling 5 on its own: it wraps until it cannot, then cuts", function()
		local w, built = degradeWorld(NARROW_PORTRAIT)
		at(w, built, "roomy")
		local roomy = built.handle.controller.textAt(WRAP_BODY)
		at(w, built, "impossible")
		local narrow = built.handle.controller.textAt(WRAP_BODY)
		expect(`roomy wraps={roomy.wraps} cut={roomy.truncated}`).toBe("roomy wraps=true cut=false")
		expect(`narrow wraps={narrow.wraps} lines={narrow.lines} cut={narrow.truncated}`).toBe(
			"narrow wraps=false lines=1 cut=true"
		)
		built.dispose()
	end)

	it("pseudo-localized (~1.4x), the row still keeps every label inside its box", function()
		-- the studio's standing localization rule, on the surface built to be
		-- squeezed. The expanded strings reach the lower rungs SOONER, which is the
		-- point: what must survive is the box, not the wrapping.
		underPseudoLocalization(module, function()
			for _, view in { NARROW_PORTRAIT, DESKTOP } do
				local w, built = degradeWorld(view)
				for _, entry in module.stops do
					at(w, built, entry.value)
					local row = w.adapter.node(ROW).rect
					for _, id in { "Sort", "Rank", "Date" } do
						local rect = w.adapter.node(`{ROW}/{id}`).rect
						expect(`xa {entry.value}@{view.w} {id} inside: {rect.x + rect.w <= row.x + row.w}`).toBe(
							`xa {entry.value}@{view.w} {id} inside: true`
						)
					end
				end
				expect(`spans at {view.w}: {#rowSpans(w) > 0}`).toBe(`spans at {view.w}: true`)
				built.dispose()
			end
		end)
	end)
end)
