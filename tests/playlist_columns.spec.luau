--!strict
--[[
	THE HEADER AND ITS RESIZE DIVIDERS — the half of `newTable` that shipped in
	Phase B, on the surface a player actually reaches: the shipped playlist
	tutorial (`examples/gallery/examples/02_playlist_table.luau`).

	IT USED TO LIVE ON A FIXTURE OF ITS OWN. `examples/gallery/scenarios/
	table_columns.luau` existed from 2026-08-14 to 2026-08-16 because the playlist
	had two columns — a `fill` Name and a Rating pinned to a measured 144px — and
	pinning the only `fill` column in a two-column table leaves NOTHING to absorb
	the remainder (`resolveDim` turns a resized column into `{ type = "fixed" }`,
	`src/controls/table.luau:1140-1144`). Measured at 800x600 before the merge: pin
	Name to 200 and the row painted 16..360 inside a cells region of 16..784 — 424px
	of dead space at the trailing edge. The director overruled the split
	(navigation-and-menus brief §6 ruling 7); the playlist gained a THIRD `fill`
	column so a sibling absorbs the slack, and this file moved onto it.

	`tests/table.spec.luau` already proves the MODEL and the HANDLERS: a grip drag
	previews a guide line and commits on release, an Adjust step is 16px and
	min-clamped, a non-resizable column grows no grip. It does that against
	`fake_target`, which dispatches a pointer event to the path it is HANDED — so it
	is a proof about wiring and structurally cannot be a proof about whether a real
	finger can land on the thing.

	THIS FILE ASKS THE QUESTIONS A MOUNTED SURFACE MAKES ASKABLE:

	  · IS THE HEADER VISIBLE — a non-zero title box per column, not merely a node
	    at a path. `docs/plans/swiftui-parity-round3-brief.md` records the class:
	    a losing `ViewThatFits` candidate stays mounted with its text intact at
	    0x0, so presence is not visibility.
	  · IS IT REACHABLE WITH NO CONSUMER WIRING. The tutorial passes NO present()
	    opts at all — no `onActivate`, no `onAdjust`, nothing. Everything below
	    therefore rides the Table's own contribution, which is the only
	    configuration a player is ever in.
	  · DOES THE READOUT MOVE. A resize is a CHANGE and a screenshot cannot hold
	    one — a table whose first column is 218px and one that was ALWAYS 218px are
	    the same image — so the argument is a number on screen, and that number only
	    exists because `api.columnWidthOverrides` is a Readable. A pointer drag
	    commits inside the control and fires no consumer callback.
	  · SELECTING A COLUMN PAINTS NOTHING. `api.selectedColumn` is public "so a
	    consumer can paint the selection" and the control draws no state for it — so
	    after a device Activate on a heading the stick silently means something new
	    and the screen does not say so. The playlist puts that state in its hint
	    line, which is both the demo and the honest report of the gap.
	  · A COLUMN THAT REFUSES. `rating` is not `resizable`, so it grows no divider
	    and no Adjust key binds while its heading holds focus. A refusal is an
	    ABSENCE until something names it, so the readout says `locked` for it rather
	    than a number that never changes.
	  · HOW BIG IS THE DIVIDER. Measured, per paradigm, against this repo's own
	    touch-target floor — because the answer is a device finding, not a demo.
	  · DOES IT SURVIVE VIRTUALIZATION. A committed width has to remount the
	    WINDOWED rows.
	  · AND THE SORT, which the playlist never had until this round. The table never
	    sorts the data; the owner observes `sortOrder` and re-sorts. So the questions
	    are the owner's: does the sort compose with the filter, and what happens when
	    a manual reorder and a live sort want the same list.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local table_control = require("../src/controls/table")
local fake_target = require("../tests/lib/fake_target")
local example = require("../examples/gallery/examples/02_playlist_table") :: any

local ROOT = "/Playlist/Page/Tracks"
local HEADER = `{ROOT}/Main/Header`

type World = {
	core: any,
	env: any,
	system: any,
	adapter: any,
	pres: any,
	built: any,
}

--[[ THE TUTORIAL'S OWN MOUNT, not a re-implementation of it: the gallery client
	builds with exactly this deps table and presents with exactly `built.present`.
	Nothing here hands the presenter a handler, which is the point — a player gets
	whatever the Table contributes for itself. ]]
local function world(opts: any?): World
	local o: any = opts or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", o.viewport or { x = 0, y = 0, w = 900, h = 640 })
	if o.preferredInput ~= nil then
		env:set("preferredInput", o.preferredInput)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	-- OPT INTO THE LIVE DEFAULT (the fake publishes no bar unless a spec asks —
	-- "which is WHY no headless sweep ever saw this class", scroll_bar_measure).
	-- Written before the presenter, because the boot indicator policy captures the
	-- configured thickness on its first call.
	if o.reserveBar then
		(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
	end
	-- Tab traversal is OPT-IN at the presenter (`keyboardNavigation`), so a case
	-- that walks the document order has to ask for it — the same way the gallery
	-- client does for a desktop session
	local pres = LuauUI.newPresenter(core, env, adapter, system, {
		keyboardNavigation = o.keyboardNavigation,
	})
	local built = example.build(LuauUI, core, {
		env = env,
		actionSystem = system,
		presenter = pres,
		adapter = adapter,
	})
	built.handle = pres.present(built.screen, built.present)
	-- `presentOnly` skips the settling refresh, which is the ONLY way to ask "how
	-- many frames does the gutter cost" — see the frame-count case below
	if not o.presentOnly then
		pres.refresh()
	end
	return { core = core, env = env, system = system, adapter = adapter, pres = pres, built = built }
end

local function headWidth(w: World, columnId: string): number
	return w.adapter.node(`{HEADER}/Head-{columnId}`).rect.w
end

local function key(w: World, code: string)
	w.system.deviceKey(code, true)
	w.system.deviceKey(code, false)
	w.pres.refresh()
end

--[[ PUT THE RING ON A HEADING, and do it explicitly rather than by mounting.
	`table_columns` could assert the name heading held focus straight after
	`present`, because the table was the only focusable thing on its page. The
	tutorial's first focus stop is its FILTER FIELD, deliberately and by document
	order (the example's PRESENTER WIRING note). So every keyboard/gamepad case
	below places the ring the way a Tab walk would land it, and the case that
	proves the walk REACHES the heading at all is its own, below. ]]
local function focusHead(w: World, columnId: string)
	w.pres.focus.focusOn(`{HEADER}/Head-{columnId}/Column`)
	w.pres.refresh()
end

describe("playlist columns: the header is on screen and legible", function()
	it("every column paints a title box with real area — presence is not visibility", function()
		local w = world()
		for _, id in { "name", "artist", "rating" } do
			local title = w.adapter.node(`{HEADER}/Head-{id}/Title`)
			expect(`{id}:mounted:{title ~= nil}`).toBe(`{id}:mounted:true`)
			expect(`{id}:w>0:{title.rect.w > 0}`).toBe(`{id}:w>0:true`)
			expect(`{id}:h>0:{title.rect.h > 0}`).toBe(`{id}:h>0:true`)
		end
		-- ...and the band sits ABOVE the first row rather than on top of it, which
		-- is the failure a `fixed` header height produced at the largest text
		-- preference (src/controls/table.luau's `minMax` FLOOR note)
		local band = w.adapter.node(`{HEADER}/Head-name`)
		local firstRow = w.built.rows:get()[1].id
		local firstCell =
			w.adapter.node(`{ROOT}/Main/Body/Rows/[{firstRow}@0]/RowActions-{firstRow}/Content/Row/Cells/Cell-name`)
		expect(`clear:{firstCell.rect.y >= band.rect.y + band.rect.h}`).toBe("clear:true")
		w.built.dispose()
	end)

	it(
		"a resizable column grows a divider and a locked one refuses — both invisibly, so the readout names them",
		function()
			local w = world()
			expect(w.adapter.node(`{HEADER}/Head-name/Grip`) ~= nil).toBe(true)
			expect(w.adapter.node(`{HEADER}/Head-artist/Grip`) ~= nil).toBe(true)
			expect(w.adapter.node(`{HEADER}/Head-rating/Grip`)).toBe(nil)
			-- the tutorial's own sentence about the same three facts
			expect(w.built.widths:get()).toBe("Name auto · Artist auto · Rating locked")
			w.built.dispose()
		end
	)

	--[[ THE THIRD COLUMN IS WHY RESIZE IS NOT DEGENERATE, and this is the case that
		holds it. With two columns the only `fill` one was Name; pinning it made BOTH
		fixed and the row under-filled its own cells region. With three, a sibling
		absorbs. Measured at 800x600 both ways before the merge:
		    two columns  : pin name=200 -> name 16..216 rating 216..360, cells 16..784
		    three columns: pin name=200 -> name 16..216 artist 216..640 rating 640..784
		The second row is this case. ]]
	it("pinning one column leaves a SIBLING to absorb the remainder — the row still fills its region", function()
		local w = world()
		local cells = w.adapter.node(`{ROOT}/Main/Header`).rect
		w.built.table_.api.setColumnWidth("name", 200)
		w.pres.refresh()
		local name = w.adapter.node(`{HEADER}/Head-name`).rect
		local rating = w.adapter.node(`{HEADER}/Head-rating`).rect
		expect(`pinned:{name.rect and 0 or math.floor(name.w + 0.5)}`).toBe("pinned:200")
		-- the trailing edge of the LAST column still reaches the band's own edge:
		-- nothing was left unpainted at the end of the row
		expect(`fills:{math.floor(rating.x + rating.w + 0.5) >= math.floor(cells.x + cells.w + 0.5) - 1}`).toBe(
			"fills:true"
		)
		w.built.dispose()
	end)
end)

describe("playlist columns: the three routes all move the same column", function()
	it("a pointer drag on the divider MOVES the column, and the live readout follows the commit", function()
		local w = world()
		local before = headWidth(w, "name")
		local grip = w.adapter.node(`{HEADER}/Head-name/Grip`)
		w.adapter.pointerDown(`{HEADER}/Head-name/Grip`, grip.rect.x + grip.rect.w, grip.rect.y + 2)
		w.adapter.pointerMove(grip.rect.x + grip.rect.w - 90, grip.rect.y + 2)
		w.pres.refresh()
		-- a PREVIEW during the drag: the column has not moved yet
		expect(`during:{headWidth(w, "name") == before}`).toBe("during:true")
		w.adapter.pointerUp(grip.rect.x + grip.rect.w - 90, grip.rect.y + 2)
		w.pres.refresh()
		local after = headWidth(w, "name")
		expect(`moved:{after < before}`).toBe("moved:true")
		expect(`delta:{before - after}`).toBe("delta:90")
		-- THE READOUT IS THE DEMO. It only moves because the widths are a Readable;
		-- a pointer drag commits inside the control and calls nothing back.
		expect(w.built.widths:get()).toBe(`Name {after}px · Artist auto · Rating locked`)
		w.built.dispose()
	end)

	it("a KEYBOARD reaches it with no consumer wiring: the heading, Return, then the arrows", function()
		local w = world()
		focusHead(w, "name")
		local before = headWidth(w, "name")
		-- the header handle is a focus stop the Table contributes for itself
		expect(w.pres.focus.focused:get()).toBe(`{HEADER}/Head-name/Column`)
		key(w, "Return") -- a device Activate SELECTS the column
		expect(w.built.table_.api.selectedColumn:get()).toBe("name")
		key(w, "Right")
		expect(`wider:{headWidth(w, "name") - before}`).toBe("wider:16")
		key(w, "Left")
		key(w, "Left")
		expect(`narrower:{headWidth(w, "name") - before}`).toBe("narrower:-16")
		w.built.dispose()
	end)

	it("a GAMEPAD reaches it: the bumper steps the focused heading without selecting anything", function()
		local w = world()
		focusHead(w, "name")
		local before = headWidth(w, "name")
		key(w, "ButtonR1")
		expect(`wider:{headWidth(w, "name") - before}`).toBe("wider:16")
		-- ...and it did NOT need the column selected first, which is the difference
		-- between the bumper route and the stick route
		expect(w.built.table_.api.selectedColumn:get()).toBe(nil)
		key(w, "ButtonL1")
		expect(`back:{headWidth(w, "name") - before}`).toBe("back:0")
		w.built.dispose()
	end)

	it(
		"SELECTING A COLUMN PAINTS NOTHING, so the hint line is the only thing that says the arrows moved house",
		function()
			local w = world()
			focusHead(w, "name")
			local idle = w.built.hint:get()
			key(w, "Return")
			expect(w.built.hint:get()).toBe("Name has the keys: , and . resize it, ↑/↓ sorts")
			key(w, "Return") -- and the second Activate hands them back
			expect(w.built.hint:get()).toBe(idle)
			w.built.dispose()
		end
	)

	it("a LOCKED column binds no Adjust key at all — the bumper stays the game's", function()
		local w = world()
		-- walk the header group to the column that refuses
		focusHead(w, "name")
		key(w, "Right")
		key(w, "Right")
		expect(w.pres.focus.focused:get()).toBe(`{HEADER}/Head-rating/Column`)
		local before = `{headWidth(w, "name")}/{headWidth(w, "artist")}/{headWidth(w, "rating")}`
		-- ONE press, not a press and its inverse: R1 followed by L1 nets to zero and
		-- would pass whether or not the key was bound, which is a check that proves
		-- nothing. This one only passes if nothing moved.
		key(w, "ButtonR1")
		expect(`{headWidth(w, "name")}/{headWidth(w, "artist")}/{headWidth(w, "rating")}`).toBe(before)
		-- THE POSITIVE CONTROL, same session, same key: on a RESIZABLE heading the
		-- identical bumper does move the column. Without this, "nothing happened" is
		-- equally explained by "no bumper ever arrived".
		key(w, "Left")
		key(w, "Left")
		expect(w.pres.focus.focused:get()).toBe(`{HEADER}/Head-name/Column`)
		local nameBefore = headWidth(w, "name")
		key(w, "ButtonR1")
		expect(`control:{headWidth(w, "name") - nameBefore}`).toBe("control:16")
		w.built.dispose()
	end)
end)

describe("playlist columns: the tutorial's contract", function()
	it("the device funnels each move the model, and the readouts follow", function()
		local w = world()
		local before = headWidth(w, "name")
		--[[ EACH DRIVE IS A DEVICE FUNNEL. `handleActivate` with `source = "action"`
			is what a keyboard Return or a gamepad A delivers; `handleGrabNavigate` is
			the stick a selected column owns. Nothing here calls `setColumnWidth`,
			because a drive that reached past the input path would prove the table
			works and say nothing about whether a device can reach the feature. ]]
		local head = `{HEADER}/Head-name/Column`
		w.built.table_.api.handleActivate(head, { source = "action" })
		w.pres.refresh()
		expect(w.built.table_.api.selectedColumn:get()).toBe("name")
		w.built.table_.api.handleGrabNavigate("right")
		w.pres.refresh()
		expect(`wider:{headWidth(w, "name") - before}`).toBe("wider:16")
		w.built.table_.api.handleGrabNavigate("left")
		w.built.table_.api.handleGrabNavigate("left")
		w.pres.refresh()
		expect(`narrower:{headWidth(w, "name") - before}`).toBe("narrower:-16")
		w.built.dispose()
	end)

	it("the header IS reachable by a Tab walk from the page's first focus stop", function()
		--[[ The tutorial's first stop is the filter field, so the heading is not
			where the ring starts — which is exactly why the other cases place it by
			hand. That makes "can a keyboard get there at all" a question this file
			has to answer on its own rather than assume. ]]
		local w = world({ keyboardNavigation = true })
		local reached = false
		local stops = 0
		for _ = 1, 80 do
			if w.pres.focus.focused:get() == `{HEADER}/Head-name/Column` then
				reached = true
				break
			end
			stops += 1
			w.system.deviceKey("Tab", true)
			w.system.deviceKey("Tab", false)
			w.pres.refresh()
		end
		-- the ring really did travel: a walk that never moved would satisfy
		-- `reached` only by having started there, which is the vacuous pass
		expect(`started:{stops > 0}`).toBe("started:true")
		expect(`reached:{reached}`).toBe("reached:true")
		w.built.dispose()
	end)

	it("disposes clean: no node of this surface survives, and the core reports no error", function()
		local w = world()
		expect(w.adapter.node(`{HEADER}/Head-name`) ~= nil).toBe(true)
		w.built.dispose()
		w.pres.dismiss(w.built.handle)
		w.pres.refresh()
		expect(w.adapter.node(`{HEADER}/Head-name`)).toBe(nil)
		expect(w.core:lastError()).toBeNil()
	end)
end)

--[[ ── THE SORT, AND WHAT IT COMPOSES WITH ──────────────────────────────────────

	The Table NEVER sorts the data (`spec.sortOrder`, SwiftUI `Table(sortOrder:)`):
	tapping a sortable heading cycles an owner-held Signal and the owner re-sorts.
	So every case here is about the OWNER's derivation, and the interesting part is
	that the playlist has three ways to change the same list — a filter, a sort, and
	a manual reorder — over ONE source array.

	THE SHAPE THAT MAKES IT WORK: sort is a derivation over the SOURCE
	(`sortedRows`), filter is a derivation over the SORTED view (`filteredRows`).
	The other order would make "move this to the top" ambiguous, because the full
	ordered list would not exist anywhere.

	AND THE TIE-BREAK IS THE SOURCE INDEX. `table.sort` is not stable in Luau, so a
	Rating sort over six tracks with duplicate ratings would otherwise land in an
	order that is legal, reproducible only by accident, and different on a different
	Luau build. ]]
describe("playlist sort: the owner sorts, and the sort composes with the filter", function()
	local function names(w: World): string
		local out = {}
		for _, track in w.built.rows:get() :: { any } do
			table.insert(out, track.name)
		end
		return table.concat(out, "|")
	end

	it("no sort is the SHIPPED order, and the memo hands back the source array untouched", function()
		local w = world()
		expect(w.built.sortOrder:get()).toBeNil()
		expect(names(w)).toBe(
			"Neon Straightaway|Drift City Nights|Turbo Cascade|Pit Lane Shuffle|Photo Finish|Apex Bloom"
		)
		w.built.dispose()
	end)

	it("tapping the Name heading cycles the owner's signal, and the rows follow it", function()
		local w = world()
		w.built.table_.api.handleActivate(`{HEADER}/Head-name/Column`, { source = "pointer" })
		w.pres.refresh()
		expect(`{w.built.sortOrder:get().column}/{w.built.sortOrder:get().ascending}`).toBe("name/true")
		expect(names(w)).toBe(
			"Apex Bloom|Drift City Nights|Neon Straightaway|Photo Finish|Pit Lane Shuffle|Turbo Cascade"
		)
		-- the same heading again FLIPS it (the control's own cycle, not the owner's)
		w.built.table_.api.handleActivate(`{HEADER}/Head-name/Column`, { source = "pointer" })
		w.pres.refresh()
		expect(`{w.built.sortOrder:get().column}/{w.built.sortOrder:get().ascending}`).toBe("name/false")
		expect(names(w)).toBe(
			"Turbo Cascade|Pit Lane Shuffle|Photo Finish|Neon Straightaway|Drift City Nights|Apex Bloom"
		)
		w.built.dispose()
	end)

	it("RATING opts in with `sortable = true` and sorts by the SIGNAL, live", function()
		local w = world()
		w.built.table_.api.handleActivate(`{HEADER}/Head-rating/Column`, { source = "pointer" })
		w.pres.refresh()
		expect(w.built.sortOrder:get().column).toBe("rating")
		-- ascending by rating, ties broken by the source order: 0,2,3,3,4,5
		expect(names(w)).toBe(
			"Photo Finish|Pit Lane Shuffle|Drift City Nights|Apex Bloom|Neon Straightaway|Turbo Cascade"
		)
		--[[ THE LIVE HALF, and it is the reason this column sorts by the SIGNAL
			rather than by the seed value in TRACKS: rate a track and the order moves
			under it, with no re-tap of the heading. A memo that closed over the
			starting number would pass every assertion above and fail this one. ]]
		w.built.ratingFor("photo"):set(5)
		w.pres.refresh()
		expect(names(w)).toBe(
			"Pit Lane Shuffle|Drift City Nights|Apex Bloom|Neon Straightaway|Turbo Cascade|Photo Finish"
		)
		w.built.dispose()
	end)

	it("the FILTER runs over the SORTED view, so both derivations are live at once", function()
		local w = world()
		w.built.table_.api.handleActivate(`{HEADER}/Head-name/Column`, { source = "pointer" })
		w.built.filterText:set("i")
		w.pres.refresh()
		-- every name containing "i", in Name order
		expect(names(w)).toBe("Drift City Nights|Neon Straightaway|Photo Finish|Pit Lane Shuffle")
		-- flipping the sort re-orders the FILTERED rows, not the whole list
		w.built.table_.api.handleActivate(`{HEADER}/Head-name/Column`, { source = "pointer" })
		w.pres.refresh()
		expect(names(w)).toBe("Pit Lane Shuffle|Photo Finish|Neon Straightaway|Drift City Nights")
		w.built.dispose()
	end)

	it("Artist sorts by `value` too, and duplicate artists tie-break on the SOURCE index", function()
		local w = world()
		w.built.table_.api.handleActivate(`{HEADER}/Head-artist/Column`, { source = "pointer" })
		w.pres.refresh()
		expect(w.built.sortOrder:get().column).toBe("artist")
		-- "Nine Volt" is TWO tracks: the tie-break is the source index, so Drift
		-- (source 2) precedes Apex (source 6) and the result is reproducible
		expect(names(w)).toBe(
			"Photo Finish|Neon Straightaway|Drift City Nights|Apex Bloom|Turbo Cascade|Pit Lane Shuffle"
		)
		w.built.dispose()
	end)
end)

--[[ A MANUAL REORDER CLEARS THE SORT — the iTunes rule, and it is a RULING rather
	than an emergent behaviour.

	The two are in genuine tension: a drop names a SLOT among the visible rows, and
	while a sort is live that slot has no meaning against the stored order — write
	it and the very next solve sorts it away, so the player's drag would appear to
	do nothing. iTunes answers by dropping the column sort the moment you drag a
	row, and so do we.

	IT IS IMPLEMENTED AS A BAKE, not as a refusal: the currently displayed order
	becomes the stored order and `sortOrder` goes nil, so the drop's slot means
	exactly what the player saw when they let go. `moveToTop` bakes for the same
	reason — a "put this first" that a live sort immediately undoes is a button
	that lies. REMOVING a row is NOT a reorder and deliberately leaves the sort
	alone. ]]
describe("playlist sort: a manual reorder wins, and takes the sort with it", function()
	local function ids(w: World, list: any): string
		local out = {}
		for _, track in list:get() :: { any } do
			table.insert(out, track.id)
		end
		return table.concat(out, ",")
	end

	it("a drop BAKES the sorted order into the source and clears the sort", function()
		local w = world()
		w.built.table_.api.handleActivate(`{HEADER}/Head-name/Column`, { source = "pointer" })
		w.pres.refresh()
		expect(ids(w, w.built.rows)).toBe("apex,drift,neon,photo,pit,turbo")
		-- the SOURCE is still the shipped order: the sort is a view, not a write
		expect(ids(w, w.built.baseRows)).toBe("neon,drift,turbo,pit,photo,apex")
		-- move the first visible row (apex) down two slots among the rows staying
		w.built.reorder({ "apex" }, 2)
		w.pres.refresh()
		expect(w.built.sortOrder:get()).toBeNil()
		-- the baked order is what the player was looking at, with the move applied
		expect(ids(w, w.built.baseRows)).toBe("drift,neon,apex,photo,pit,turbo")
		expect(ids(w, w.built.rows)).toBe("drift,neon,apex,photo,pit,turbo")
		w.built.dispose()
	end)

	it("`Top` bakes too — a move a live sort would undo is a button that lies", function()
		local w = world()
		w.built.table_.api.handleActivate(`{HEADER}/Head-name/Column`, { source = "pointer" })
		w.pres.refresh()
		w.built.moveToTop("turbo")
		w.pres.refresh()
		expect(w.built.sortOrder:get()).toBeNil()
		expect(ids(w, w.built.rows)).toBe("turbo,apex,drift,neon,photo,pit")
		w.built.dispose()
	end)

	it("REMOVING a row is not a reorder: the sort survives it", function()
		local w = world()
		w.built.table_.api.handleActivate(`{HEADER}/Head-name/Column`, { source = "pointer" })
		w.pres.refresh()
		w.built.removeTrack("neon")
		w.pres.refresh()
		expect(w.built.sortOrder:get().column).toBe("name")
		expect(ids(w, w.built.rows)).toBe("apex,drift,photo,pit,turbo")
		w.built.dispose()
	end)

	it("Restore puts the sort back to nil along with the order and the ratings", function()
		local w = world()
		w.built.table_.api.handleActivate(`{HEADER}/Head-rating/Column`, { source = "pointer" })
		w.pres.refresh()
		expect(w.built.sortOrder:get() ~= nil).toBe(true)
		w.built.restore()
		w.pres.refresh()
		expect(w.built.sortOrder:get()).toBeNil()
		expect(ids(w, w.built.rows)).toBe("neon,drift,turbo,pit,photo,apex")
		w.built.dispose()
	end)

	it("reordering is still REFUSED under a filter, sort or no sort", function()
		-- the shipped rule (a drop's meaning against the HIDDEN rows is ambiguous,
		-- so we refuse rather than guess) is unchanged by the sort, and the sort is
		-- not silently cleared by a refused move either
		local w = world()
		w.built.table_.api.handleActivate(`{HEADER}/Head-name/Column`, { source = "pointer" })
		w.built.filterText:set("i")
		w.pres.refresh()
		local before = ids(w, w.built.baseRows)
		w.built.reorder({ "photo" }, 0)
		w.pres.refresh()
		expect(ids(w, w.built.baseRows)).toBe(before)
		expect(w.built.sortOrder:get().column).toBe("name")
		w.built.dispose()
	end)
end)

--[[ THE DIVIDER'S HIT BOX, per paradigm — a MEASUREMENT, not a demo.

	`gripFor` declares `width = { type = "fixed", px = "s" }`: the theme's small
	spacing step. That is a fine visual hairline and it is the whole target a
	finger has to land on, so the number is worth pinning next to this repo's own
	touch floor rather than left as a token nobody resolved.

	This case does not assert a PASS — it asserts the measured number, so the day
	the token moves (or a paradigm gains its own value) the change is announced
	rather than absorbed. The verdict lives in the mission report and in
	`docs/lessons/`, where a finding belongs. ]]
describe("playlist columns: how big the divider actually is", function()
	it("the grip is the theme's small spacing step in every paradigm, touch included", function()
		local measured = {}
		for _, input in { "KeyboardAndMouse", "Touch", "Gamepad" } do
			local w = world({ preferredInput = input })
			local grip = w.adapter.node(`{HEADER}/Head-name/Grip`)
			-- THE POSITIVE CONTROL: the ROW box IS paradigm-derived
			-- (`controls.table.rowHeight.touch`), so if the row height does not move
			-- between these three the paradigm never switched and the grip
			-- measurement beside it would prove nothing.
			local firstRow = w.built.rows:get()[1].id
			local row = w.adapter.node(`{ROOT}/Main/Body/Rows/[{firstRow}@0]/RowActions-{firstRow}/Content/Row`)
			table.insert(measured, `{input}=grip{grip.rect.w}x{grip.rect.h}/row{row.rect.h}`)
			w.built.dispose()
		end
		--[[ THE FINDING, PINNED AS A NUMBER (2026-08-14, re-measured on this surface
			2026-08-16).

			The ROW grows for touch — `controls.table.rowHeight.touch` floored at
			`targetSizes.minimum`. That is the positive control, and it fires.

			THE DIVIDER DOES NOT. `gripFor` declares `px = "s"`, a space step, and a
			space step has no paradigm: the resize handle is EIGHT PIXELS WIDE on a
			phone, against the same theme's own 44px touch floor. Five and a half
			times under the floor this project holds every other target to, on the
			one control whose row height exists BECAUSE of that floor.

			Pinned rather than fixed here because the fix is a design call about
			where a touch divider's slop comes from (a wider Grip paints a fat
			hairline; an invisible hit inset does not exist as a Box prop today), and
			`docs/lessons/an-eight-pixel-divider-on-a-forty-four-pixel-finger.md`
			carries it. The day it is fixed this line changes, deliberately. ]]
		expect(table.concat(measured, " ")).toBe(
			"KeyboardAndMouse=grip8x28/row36 Touch=grip8x28/row44 Gamepad=grip8x28/row36"
		)
	end)
end)

--[[ THE 44px HIT FLOOR EXPANDS THE DIVIDER OVER ITS OWN HEADER BUTTON.

	`src/controls/contract.luau` gives Grip `minHitSize = 44`, so the renderer asks
	the adapter for a 44x44 hit rect CENTRED on an 8x28 grip. On the live engine
	that is a real `LuauUIHitExpander` TextButton parented beside the grip at
	`grip.z - 1` — which is still ABOVE the header cell's own `Column` button, and a
	GuiButton sinks `InputBegan` (docs/lessons/a-button-eats-the-swipe-underneath-it).

	MEASURED LIVE, 2026-08-14, LuauUI-Showcase, on the fixture this file replaced,
	with the control in the same session (docs/lessons/a-forty-four-pixel-floor-
	under-an-eight-pixel-divider.md):

	  | click            | inside              | result        |
	  |------------------|---------------------|---------------|
	  | (264, 134)       | name header, over the expander | NOTHING |
	  | (100, 134)       | name header, clear of it       | sort cycles, mark '▲' |

	RULED AND FIXED THE SAME DAY (director, option 1 of the four the lesson listed):
	the expander now runs the grip's own gesture, so the 44x44 IS the drag target the
	floor always claimed; and a press that never travels forwards through
	`controller.tapAt` to the `Column` button underneath, so the band sorts. THE
	GEOMETRY BELOW IS UNCHANGED BY THAT FIX AND STAYS PINNED AT THE SAME NUMBERS —
	the repair was to what the rect DOES, not to where it is. It is still the
	geometry that would make the dead band possible, so if any of the three moves,
	the live table has to be re-measured before the behaviour above can be claimed
	again.

	THIS CASE STILL CANNOT SEE THE BEHAVIOUR. `controller.tapAt` is the FRAMEWORK's
	hit test and it arbitrates on solved rects, not on the adapter's expander
	instances — it answers `Column` at every one of those points, before and after.
	The behaviour is held by "the divider forwards a press it did not turn into a
	drag" (below), by the adapter source anchors in `tests/adaptive.spec.luau`, and
	by the live drive in the lesson. ]]
describe("the resize grip's hit floor lands on top of its own header button", function()
	it("asks for 44x44 centred on an 8x28 grip, which covers 26px of the header cell it sits in", function()
		local w = world()
		local cell = w.adapter.node(`{HEADER}/Head-name`)
		local grip = w.adapter.node(`{HEADER}/Head-name/Grip`)
		local column = w.adapter.node(`{HEADER}/Head-name/Column`)
		expect(`grip:{grip.rect.w}x{grip.rect.h}`).toBe("grip:8x28")
		expect(`hit:{grip.hitRect.w}x{grip.hitRect.h}`).toBe("hit:44x44")
		-- how much of the header cell the expanded rect covers, left of the grip
		local eaten = grip.rect.x - grip.hitRect.x
		expect(`eaten:{eaten}`).toBe("eaten:18")
		-- ...and the whole band, grip included, measured from the cell's right edge
		local band = (cell.rect.x + cell.rect.w) - grip.hitRect.x
		expect(`band:{band}`).toBe("band:26")
		-- THE Z RELATIONSHIP IS THE OTHER HALF. The engine paints the expander at
		-- `grip.z - 1`, and the header's own button is lower still, so the expander
		-- wins the press. It is what made the band dead before the ruling, and after
		-- it it is what makes the band a RESIZE target: the expander has to be the
		-- topmost thing under a finger aiming at the divider, or the header button
		-- would take the press and there would be nothing to promote into a drag.
		-- The same number, load-bearing for the opposite reason.
		expect(`above:{grip.z - 1 > column.z}`).toBe("above:true")
		w.built.dispose()
	end)
end)

--[[ RESIZE x VIRTUALIZATION — a combination that is one week old on both sides.

	`virtualized` mounts the body as a full-extent Canvas with absolutely
	positioned windowed rows instead of a flowing stack, and a committed resize
	bumps `widthsVersion`, which is interpolated into every ForEach row key. The
	question is whether the WINDOW remounts at the new width, or whether the rows
	the window happens to hold keep the old one.

	IT BUILDS ITS OWN TABLE. The playlist is a BLOCK table (`scrolls = false`) by a
	measured decision of its own, so it cannot be the surface that asks this. ]]
describe("column resize on a VIRTUALIZED table", function()
	local function virtualWorld()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local rows = {}
		for i = 1, 2000 do
			table.insert(rows, { id = `r{i}`, n = i })
		end
		local tbl = table_control.build(LuauUI, core, {
			id = "V",
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 80,
					resizable = true,
					value = function(item: any)
						return `#{item.n}`
					end,
				},
				{
					id = "laps",
					title = "Laps",
					width = { type = "fixed", px = 64 },
					value = function(item: any)
						return tostring(item.n)
					end,
				},
			},
			rows = core:signal(rows),
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			header = true,
			virtualized = true,
			selection = "single",
			env = env,
		})
		local handle = pres.present(LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } }), {})
		pres.refresh()
		return adapter, pres, tbl, handle, core
	end

	it("a committed width remounts the WINDOWED rows at the new width, and the window stays bounded", function()
		local adapter, pres, tbl = virtualWorld()
		local before = adapter.node("/S/V/Main/Header/Head-name").rect.w
		local windowBefore = tbl.dump().windowRows
		expect(`bounded:{windowBefore < 40}`).toBe("bounded:true")
		tbl.api.setColumnWidth("name", before - 120)
		pres.refresh()
		expect(adapter.node("/S/V/Main/Header/Head-name").rect.w).toBe(before - 120)
		-- THE ROWS, not just the band: a windowed row is mounted under a key that
		-- carries the widths version, so a stale row would still be at `before`
		local firstCell = adapter.node("/S/V/Main/Body/Canvas/Rows/[r1@1]/Row/Cells/Cell-name")
		expect(`row:{firstCell ~= nil and firstCell.rect.w or -1}`).toBe(`row:{before - 120}`)
		expect(`stillBounded:{tbl.dump().windowRows == windowBefore}`).toBe("stillBounded:true")
	end)

	it("...and it is still 2 000 rows the table never mounted", function()
		local adapter, pres, tbl = virtualWorld()
		tbl.api.setColumnWidth("name", 200)
		pres.refresh()
		expect(tbl.dump().rowCount).toBe(2000)
		expect(`mounted:{tbl.dump().windowRows < 40}`).toBe("mounted:true")
		expect(adapter.node("/S/V/Main/Body/Canvas/Rows/[r1500@1]/Row/Cells/Cell-name")).toBe(nil)
	end)
end)

--[[ A PRESS IN THE 44px BAND THAT NEVER MOVES IS A TAP, AND A TAP BELONGS TO THE
	HEADER UNDERNEATH (director ruling, 2026-08-14 — option 1 of the four in
	`docs/lessons/a-forty-four-pixel-floor-under-an-eight-pixel-divider.md`).

	The lesson measured two symptoms of one mechanism: the grip's `minHitSize = 44`
	expander SANK every press in the trailing 26px of the header cell and forwarded
	nothing (a dead band), while buying the divider no drag target at all (the
	expander is painted BEHIND the grip). The ruled repair gives the expander the
	grip's own gesture — so the 44px band really is the resize target — and makes a
	press the gesture did NOT claim forward on through `controller.tapAt`, which is
	the machinery `row_actions` already uses for exactly this (ruling 6, `aa1e271`).

	THE HALF THIS SPEC CAN HOLD is the control's: whether the grip distinguishes a
	tap from a drag and hands the tap on. The adapter half (the expander running the
	host's `InputBegan`) is engine-only and is asserted at the source anchors in
	`tests/adaptive.spec.luau`, then measured live.

	IT BITES: before the ruling `onPointerUp` committed `setColumnWidth(id, width)`
	unconditionally, so a press-and-release on the divider wrote a phantom width
	override for a column nobody had moved and cycled no sort. ]]
describe("playlist columns: the divider forwards a press it did not turn into a drag", function()
	local function tapGrip(w: World, dx: number)
		local grip = w.adapter.node(`{HEADER}/Head-name/Grip`)
		local x, y = grip.rect.x + 2, grip.rect.y + 4
		w.adapter.pointerDown(`{HEADER}/Head-name/Grip`, x, y)
		if dx ~= 0 then
			w.adapter.pointerMove(x + dx, y)
		end
		w.adapter.pointerUp(x + dx, y)
		w.pres.refresh()
	end

	it("a press and release with no travel sorts the column and commits NO width", function()
		local w = world()
		expect(w.built.sortOrder:get()).toBeNil()
		tapGrip(w, 0)
		-- the tap reached the header cell's own Button, one layer down
		expect(`sorted:{w.built.sortOrder:get().column}`).toBe("sorted:name")
		-- ...and nothing was resized: `auto` is the readout for a column with no
		-- committed override at all
		expect(w.built.widths:get()).toBe("Name auto · Artist auto · Rating locked")
		w.built.dispose()
	end)

	it("travel UNDER the pointer promotion gate is still a tap; travel over it is a resize", function()
		local w = world()
		local before = headWidth(w, "name")
		-- 3px on a mouse: under `interaction_tokens.promotionPx("pointer")` = 6
		tapGrip(w, -3)
		expect(`under:{headWidth(w, "name") == before}`).toBe("under:true")
		expect(w.built.widths:get()).toBe("Name auto · Artist auto · Rating locked")
		-- the SAME gesture 40px further is the resize it always was — the positive
		-- control, because "nothing moved" is otherwise equally explained by a grip
		-- that stopped receiving presses at all
		tapGrip(w, -40)
		expect(`over:{headWidth(w, "name") - before}`).toBe("over:-40")
		w.built.dispose()
	end)

	it("the guide line does not appear for a press that never becomes a drag", function()
		local w = world()
		local grip = w.adapter.node(`{HEADER}/Head-name/Grip`)
		local x, y = grip.rect.x + 2, grip.rect.y + 4
		w.adapter.pointerDown(`{HEADER}/Head-name/Grip`, x, y)
		w.adapter.pointerMove(x - 2, y)
		w.pres.refresh()
		-- a 44px band that flashed a resize guide under every press near a column
		-- edge would be the dead zone's cosmetic twin
		expect(w.adapter.node(`{ROOT}/ResizeWhen/then/ResizeLine`)).toBe(nil)
		w.adapter.pointerMove(x - 30, y)
		w.pres.refresh()
		expect(w.adapter.node(`{ROOT}/ResizeWhen/then/ResizeLine`) ~= nil).toBe(true)
		w.adapter.pointerUp(x - 30, y)
		w.pres.refresh()
		w.built.dispose()
	end)
end)

--[[ ── THE INVARIANT: A TABLE'S HEADER BOUNDARIES ARE ITS BODY'S ────────────────

	THE DEFECT (director, 2026-08-14): "on desktop, the scroll bar is persistent
	(correct) but it always overlaps content" — and, after the first diagnosis came
	back vertical-only, "the scroll bar issue should apply to both horizontal and
	vertical ones."

	The header is a SIBLING of the scrolling body. The body's rows correctly stop
	short of the reserved bar; the header laid its columns across the FULL frame,
	so every boundary drifted by the reserve, worsening left to right. Measured
	live at the fixture this file replaced, desktop:

	    Body: Abs=883  Win=875   bar occupies 887..895
	      header 'name': 12..277    ok
	      header 'team': 277..630   ok
	      header 'best': 630..895   <-- 8px UNDER THE BAR

	WHY NOTHING CAUGHT IT. `tests/scroll_window_clip.spec.luau` is the instrument
	for "content laid out past the window the player can see", and it walks a
	scroll host's DESCENDANTS — a sibling header is structurally invisible to it,
	whatever the sweep. The class needs its own shape of check, and this is it: not
	"is the header inside the window" but "is the header's grid the body's grid".

	IT IS AN INVARIANT, NOT A SPOT CHECK: every column, both edges, derived from
	the control's own column list rather than from three hard-coded ids.

	NON-VACUITY IS ASSERTED, not assumed. A world with no reserve passes this check
	trivially — the cases below therefore prove the bar is really there first (the
	body's engine window is a whole bar narrower than its frame) and only then
	compare the grids. Without that line the case is the "check that proves
	nothing" class this repo has already paid for once.

	MUTATION-PROVEN 2026-08-14 by deleting the `gutter.right` term from
	`newTable`'s `headerPadding`: the columns come back 3/6/8px wide of their cells
	and this case fails on the first column it compares.

	THE PLAYLIST IS A BLOCK TABLE, so its body does not own a scroller and reserves
	no bar of its own — the page around it does. The scrolling table this invariant
	needs is therefore built here, with the playlist's own three-column shape. ]]
describe("newTable: the header's column boundaries are the body's", function()
	local COLUMNS = { "name", "artist", "rating" }

	local function scrollingWorld(opts: any?): World
		local o: any = opts or {}
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 640 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		if o.reserveBar ~= false then
			(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
		end
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local rows = {}
		for i = 1, 28 do
			table.insert(rows, { id = `r{i}`, name = `Track {i}`, artist = `Artist {i}`, rating = i % 6 })
		end
		local tbl = table_control.build(LuauUI, core, {
			id = "Tracks",
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 3 },
					minWidth = 90,
					resizable = true,
					disclose = true,
					value = function(item: any)
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
					value = function(item: any)
						return item.artist
					end,
				},
				{
					id = "rating",
					title = "Rating",
					width = { type = "fixed", px = 144 },
					value = function(item: any)
						return tostring(item.rating)
					end,
				},
			},
			rows = core:signal(rows),
			key = function(item: any)
				return item.id
			end,
			header = true,
			selection = "single",
			env = env,
		})
		local built: any = {
			table_ = tbl,
			dispose = function()
				tbl.dispose()
			end,
		}
		built.handle = pres.present(LuauUI.UI.Screen({ id = "Grid", padding = 12, children = { tbl.blueprint } }), {})
		if not o.presentOnly then
			pres.refresh()
		end
		return {
			core = core,
			env = env,
			system = system,
			adapter = adapter,
			pres = pres,
			built = built,
		}
	end

	local GRID_ROOT = "/Grid/Tracks"
	local GRID_HEADER = `{GRID_ROOT}/Main/Header`

	-- the first row's cell region, found rather than spelled: a committed resize
	-- bumps `widthsVersion` and that version is interpolated into every ForEach
	-- key, so a hard-coded `[r1@0]` reads a node that a resize has just replaced
	local function firstRowCells(w: World): string
		for _, path in w.adapter.paths() do
			local cells = string.match(path, `^({GRID_ROOT}/Main/Body/Rows/%[r1@%d+%]/Row/Cells)$`)
			if cells ~= nil then
				return cells
			end
		end
		error(`playlist_columns: no mounted first-row cell region under {GRID_ROOT}`, 0)
	end

	local function grids(w: World): (string, string)
		local cellsRegion = firstRowCells(w)
		local head, cells = {}, {}
		for _, id in COLUMNS do
			local h = w.adapter.node(`{GRID_HEADER}/Head-{id}`).rect
			local c = w.adapter.node(`{cellsRegion}/Cell-{id}`).rect
			table.insert(head, `{id}:{h.x}..{h.x + h.w}`)
			table.insert(cells, `{id}:{c.x}..{c.x + c.w}`)
		end
		return table.concat(head, " "), table.concat(cells, " ")
	end

	it("every column's header spans exactly its cells, with the bar reserved", function()
		local w = scrollingWorld()
		-- THE BAR IS REALLY THERE, and it is the SOLVER'S OWN VERDICT that says so —
		-- not the adapter's configured thickness, which is only what a bar would
		-- take. Without this line the comparison below passes on a world that
		-- reserved nothing, which is every world this file had before.
		local inset = w.built.handle.controller.scrollBarInsetOf(`{GRID_ROOT}/Main/Body`)
		expect(`spent:{inset ~= nil and `{inset.right}/{inset.bottom}` or "nil"}`).toBe(
			`spent:{fake_target.SCROLL_BAR_THICKNESS}/0`
		)
		local head, cells = grids(w)
		expect(head).toBe(cells)
		-- ...and the band as a whole now ends inside the ENGINE WINDOW rather than
		-- under the bar — the trailing edge is the one the drift accumulated onto,
		-- and the window is the box the live report was measured against
		-- ("Body: Abs=883 Win=875 ... header 'best': 630..895").
		local window = w.adapter.windowRectOf(`{GRID_ROOT}/Main/Body`)
		local last = w.adapter.node(`{GRID_HEADER}/Head-rating`).rect
		expect(`under:{last.x + last.w > window.x + window.w}`).toBe("under:false")
		w.built.dispose()
	end)

	it("...and with no bar to reserve, the same grid, and no gutter paid", function()
		-- THE OTHER HALF OF THE FIX: the gutter is the reserve the body SPENT, so a
		-- table whose adapter publishes none pays nothing and its shipped geometry
		-- is byte-identical to what it was before this change.
		local w = scrollingWorld({ reserveBar = false })
		expect(w.built.handle.controller.scrollBarInsetOf(`{GRID_ROOT}/Main/Body`)).toBeNil()
		local head, cells = grids(w)
		expect(head).toBe(cells)
		w.built.dispose()
	end)

	it("PRESENT ALONE lands the grids together — the gutter costs no frame at all", function()
		--[[ THE FRAME COUNT, asked the only way it can be asked: with no refresh.
			The gutter is a MEASUREMENT fed back through `syncGeometry`, and a prop
			write made there used to be drained by the NEXT `controller.refresh()` —
			so `present`'s own solve laid the header out un-guttered and the first
			refresh corrected it. ONE frame, already down from two.

			The renderer now re-drains the prop dirty a solve's own consumers
			published, inside that solve (the same settle phase L-31 gave env
			writes), so the count is ZERO: `present` returns final.

			NON-VACUITY: the bar is proven spent first, exactly as the case above —
			without that line a world that reserved nothing passes trivially. ]]
		local w = scrollingWorld({ presentOnly = true })
		local inset = w.built.handle.controller.scrollBarInsetOf(`{GRID_ROOT}/Main/Body`)
		expect(`spent:{inset ~= nil and `{inset.right}/{inset.bottom}` or "nil"}`).toBe(
			`spent:{fake_target.SCROLL_BAR_THICKNESS}/0`
		)
		local head, cells = grids(w)
		expect(head).toBe(cells)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("converges in one refresh and then holds still", function()
		--[[ The gutter is a MEASUREMENT fed back through `syncGeometry`, so the one
			thing that would make it unshippable is a cycle. It cannot have one: the
			gutter narrows only the header's INNER width, and a `lineLimit = 1` title
			in a `minMax`-floored band cannot answer that with a taller header — so
			the body's rect, its overflow verdict and the gutter are all fixed points
			after the first solve. ]]
		local w = scrollingWorld()
		local before = select(1, grids(w))
		w.pres.refresh()
		w.pres.refresh()
		expect(select(1, grids(w))).toBe(before)
		expect(w.core:lastError()).toBeNil()
		w.built.dispose()
	end)

	it("a committed resize keeps the grids together", function()
		-- a resize re-resolves every column against the header's inner width, so it
		-- is the operation most likely to reintroduce the drift on one side only
		local w = scrollingWorld()
		w.built.table_.api.setColumnWidth("name", 200)
		w.pres.refresh()
		local head, cells = grids(w)
		expect(head).toBe(cells)
		w.built.dispose()
	end)
end)

--[[ THE ARROW KEYS: THE CLAIM THAT WAS RULED, BUILT, MEASURED AND WITHDRAWN.

	`docs/lessons/the-camera-still-owns-the-arrow-keys.md` measured live 2026-08-14:
	Roblox's own default camera binds Left/Right as `RbxCameraKeypress` through
	ContextActionService at priority 2000 and SINKS them, so a selected column's
	Left/Right resize never receives a press. The ruled repair was a sinking
	`InputContext` above the camera, scoped to the selection.

	IT WAS BUILT AND IT DOES NOT WORK, and the measurement is in the second lesson
	round and in `src/controls/table.luau`'s own comment: a ContextActionService
	sink at priority **100** consumed both presses while a LuauUI `InputContext` at
	priority **10000, Sink = true** received nothing. The two priorities are not one
	arbitration space, so no number takes a key back from a CAS binding. What is
	left of the ruling is the RELEASE — which was a live bug in its own right, and
	is the half that ships.

	The engine truth itself is carried by `src/client/gamepad_contention.luau` (the
	module this repo already uses for "a CoreScript binding eats our key") and
	checked in `tests/gamepad_contention.spec.luau`. There is no headless surface
	for CAS at all, which is exactly why it took a live drive to find. ]]
describe("playlist columns: a selected column is released the moment focus leaves it", function()
	it("Cancel releases it, and a second Activate releases it", function()
		local w = world()
		focusHead(w, "name")
		key(w, "Return")
		expect(w.built.table_.api.selectedColumn:get()).toBe("name")
		key(w, "ButtonB")
		expect(w.built.table_.api.selectedColumn:get()).toBeNil()
		key(w, "Return")
		expect(w.built.table_.api.selectedColumn:get()).toBe("name")
		key(w, "Return")
		expect(w.built.table_.api.selectedColumn:get()).toBeNil()
		w.built.dispose()
	end)

	--[[ THE LEAK, and it was already shipped.

		The presenter routes `focusMoved` only to the contributions whose mounted path
		is a PREFIX of the newly focused one, so focus leaving the Table entirely never
		reached `api.handleFocusMoved` and `releaseColumnOnFocusLeave` never ran. A
		column stayed selected after the ring had gone somewhere else — and a selected
		column swallows EVERY direction (`handleGrabNavigate` returns true for all four
		so the selection cannot be steered off) and answers Cancel. The ring was on
		another control and the arrows still belonged to a table nobody was looking at.

		Driven live in the showcase the same day, on the shipped fix: select a column,
		press Tab twice, and the hint line goes back to idle with the selection
		released. ]]
	it("focus leaving the table entirely releases it too, however it left", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 640 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local tbl = table_control.build(LuauUI, core, {
			id = "T",
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 80,
					resizable = true,
					value = function(item: any)
						return item.id
					end,
				},
			},
			rows = core:signal({ { id = "r1" } }),
			key = function(item: any)
				return item.id
			end,
			header = true,
			env = env,
		})
		pres.present(
			LuauUI.UI.Screen({
				id = "S",
				children = { tbl.blueprint, LuauUI.UI.Button({ id = "Away", label = "Away", focusable = true }) },
			}),
			{}
		)
		pres.refresh()
		tbl.api.handleActivate("/S/T/Main/Header/Head-name/Column", { source = "action" })
		pres.refresh()
		expect(tbl.api.selectedColumn:get()).toBe("name")
		-- a selected column swallows every direction, so while it is held the ring
		-- cannot be steered off it: that is what makes a leaked selection permanent
		expect(`swallows:{tbl.api.handleGrabNavigate("down")}`).toBe("swallows:true")

		-- the ring goes somewhere this table does not own
		pres.focus.focusOn("/S/Away")
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/Away")
		expect(tbl.api.selectedColumn:get()).toBeNil()
		-- ...and it has stopped answering for a stick that is not its own
		expect(`released:{tbl.api.handleGrabNavigate("down")}`).toBe("released:false")
		tbl.dispose()
	end)
end)

--[[ ── THE MEASUREMENT THAT DECIDED THE THIRD COLUMN ────────────────────────────

	The playlist deleted its Length column on 2026-08-13 for a measured reason: a
	third FIXED 70px column plus edit mode's two leading gutters left the Name cell
	6px wide at 320x640 and the solver said "content box collapses to 0px on x".
	The navigation-and-menus brief required that measurement to be REPEATED before a
	third column could come back, because a `fill` column is a different animal from
	a fixed one — a hypothesis, not a fact, until measured.

	MEASURED 2026-08-16, 320x640, touch capabilities, EDIT MODE ON:

	  | shape                          | Name cell/text | Artist cell/text | collapse diagnostics |
	  |--------------------------------|----------------|------------------|----------------------|
	  | two columns (what shipped)     | 76 / 60        | —                | 0                    |
	  | third FIXED 70px (deleted)     | 6 / 0          | 70 / 54          | 3                    |
	  | third FILL w2, min 72 (shipped)| 46 / 30        | 30 / 14          | 0                    |

	So the hypothesis holds where it was posed — the fill column does not reproduce
	the collapse, and the Name cell keeps 30px of text where the fixed one left it
	none — and it costs the Artist column 14px of text at that one viewport in that
	one mode. That number is pinned HERE rather than left in a report, because it is
	the number that would drift silently if the Rating column's 144, the edit
	gutters or the weights ever moved.

	The cost is survivable and it is not silent: both text columns carry
	`disclose = true`, so a truncated value is still reachable, and both truncate to
	ONE line rather than wrapping into a row that cannot hold them. ]]
describe("playlist columns: the 320x640 edit-mode measurement that kept the third column", function()
	local function editModeCell(vw: number, vh: number, columnId: string): (number, number)
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = vw, h = vh })
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local built =
			example.build(LuauUI, core, { env = env, actionSystem = system, presenter = pres, adapter = adapter })
		pres.present(built.screen, built.present)
		pres.refresh()
		built.table_.api.editing:set(true)
		pres.refresh()
		local cellW, textW = -1, -1
		for _, path in adapter.paths() do
			if string.match(path, `/Row/Cells/Cell%-{columnId}$`) ~= nil then
				cellW = adapter.node(path).rect.w
			elseif string.match(path, `/Row/Cells/Cell%-{columnId}/Value$`) ~= nil then
				textW = adapter.node(path).rect.w
			end
		end
		built.dispose()
		return cellW, textW
	end

	it("at the narrowest swept viewport, in edit mode, no cell collapses and the numbers are these", function()
		local nameCell, nameText = editModeCell(320, 640, "name")
		local artistCell, artistText = editModeCell(320, 640, "artist")
		expect(`name:{nameCell}/{nameText} artist:{artistCell}/{artistText}`).toBe("name:46/30 artist:30/14")
	end)

	it("the solver files NO collapse diagnostic — which is the whole difference from the fixed column", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local built =
			example.build(LuauUI, core, { env = env, actionSystem = system, presenter = pres, adapter = adapter })
		local handle = pres.present(built.screen, built.present)
		pres.refresh()
		built.table_.api.editing:set(true)
		pres.refresh()
		local collapses = 0
		for _, entry in handle.controller.diagnostics() do
			if string.find(entry.issue, "collapses to 0px", 1, true) ~= nil then
				collapses += 1
			end
		end
		expect(`collapses:{collapses}`).toBe("collapses:0")
		built.dispose()
	end)
end)
