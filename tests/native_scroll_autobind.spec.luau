--!strict
--[[ O-31 — A VIRTUALISED COLLECTION FOLLOWS ITS OWN ENGINE SCROLL WITH NO
	CONSUMER CALL AT ALL.

	THE DEFECT. Every virtualized collection windows its rows against `scrollTop`,
	and `scrollTop` was written only by the engine mirror `bindNativeScroll`
	installs. That call is a POST-`present` obligation, so a consumer who never
	made it got a control that mounted, painted, took taps, and windowed its FIRST
	LINES FOREVER. Measured live in Studio 2026-08-15: an engine scroll to
	`CanvasPosition.Y = 2000`
	left a `virtual_grid`'s mounted window at `c1..c16`; with the bind restored the
	same scroll moved it to `c69..c92`. A census of the showcase demos the same day
	found five of nine callers outside the tests omitting it — an API footgun, not
	one slip. The contract this file pins is public: `docs/reference/api.md`
	(`bindNativeScroll`) states that the framework installs the mirror itself and
	that the public call is an override.

	THE SEAM, AND WHY IT IS NOT THE ONE THE LEDGER PROPOSED. O-31 proposed
	delivering the controller through `buildFocusGroups(rootNode)`, on the ground
	that it is "the one seam that hands a control its own mounted path". It is not
	the one seam, and it does not reach: the presenter only calls a contribution's
	`focusGroups` from `autoGroups`, which runs only when the consumer left
	`opts.navigationGroups` ABSENT (`presenter.luau`, "an explicit array/function
	wins; `false` forces the flat ring"). Measured, four presenter configurations,
	one control:

	    navigationGroups ABSENT     focusGroups=2  syncGeometry=3  bindController=1
	    navigationGroups = false    focusGroups=0  syncGeometry=3  bindController=1
	    navigationGroups = <array>  focusGroups=0  syncGeometry=3  bindController=1
	    navigationGroups = <fn>     focusGroups=0  syncGeometry=3  bindController=1

	So a fix on that seam would have fixed the default screen and left a consumer
	who declares a focus map exactly as broken — and that consumer is worse off
	today than the ledger knew, because with `focusGroups` never called the control
	never learns its mounted path at all and `bindNativeScroll(controller)` REFUSES
	outright. `group (b)` below is that case, and it is what discriminates this fix
	from the proposed one.

	The two seams that DO reach are unconditional for every discovered
	contribution: `bindController(controller)` (once, at present and on a
	structural sync) and `syncGeometry(rectOf, node)` (every refresh AND every
	solve, carrying the control's own mounted node). Together they are exactly what
	the post-`present` call was being asked for by hand.

	THE OPT-OUT IS THE CONTROL'S OWN PUBLISHED SCROLL PATH, and there is only one
	of them (group (d)). A `newTable{ scrolls = false }` owns no ScrollingFrame —
	`api.scrollPath()` is nil and always was — so it auto-binds no mirror while
	still binding its tray-close to the real scrolling ancestor. No second
	mechanism was added: a `newVirtualList`/`newVirtualGrid` always mounts its own
	ScrollView, so "the scrolling is owned elsewhere" is not a state either can be
	in.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local virtual_grid = require("../src/controls/virtual_grid")
local table_control = require("../src/controls/table")
local contribution = require("../src/input/contribution")
local fake_target = require("../tests/lib/fake_target")

local function makeItems(n: number): { { id: string, label: string } }
	local items = table.create(n)
	for i = 1, n do
		items[i] = { id = `i{i}`, label = `Item {i}` }
	end
	return items
end

-- a presenter over a fake target, with NOTHING presented yet
local function stage()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	return { core = core, env = env, system = system, adapter = adapter, pres = pres }
end

--[[ THE MIRROR'S OWN REGISTRATIONS, ABOVE THE FRAMEWORK'S FLOOR.

	`scrollObserverCount` counts every live engine scroll observer on a node. The
	fake target holds a LIST per node (it was a single slot until 2026-08-13,
	which made a second registration silently evict the first), so this is what
	the real `ScreenTarget` would hold as independent `CanvasPosition`
	connections.

	IT IS NOT ZERO BEFORE A MIRROR EXISTS, and that was measured rather than
	assumed: the renderer keeps ONE observer of its own on every scroll host
	(`renderer.luau:2283`, `pathClipObservers` — it re-derives what a clipped
	subtree shows). A presented, never-bound list reads 1. So the number these
	cases care about is the count ABOVE that floor, and asserting the raw count
	would have pinned an unrelated renderer detail into this file. ]]
local RENDERER_CLIP_OBSERVER = 1

local function scrollObserverCount(adapter: any, path: string): number
	local node = adapter.node(path)
	if node == nil or node.scrollObservers == nil then
		return 0
	end
	local n = 0
	for _, entry in node.scrollObservers do
		if entry.live then
			n += 1
		end
	end
	return n
end

-- ===========================================================================
-- (a) THE DEFECT ITSELF — every virtualised control, presented and refreshed,
--     with NO `bindNativeScroll` anywhere. Each case drives the ENGINE
--     (`adapter.driveScroll`, the headless stand-in for a wheel/finger/momentum
--     CanvasPosition write) and reads the WINDOW back, never `scrollTop` alone:
--     a mirror that moves a signal nothing windows against is not the fix.
-- ===========================================================================
describe("O-31: a virtualised collection follows the engine with no consumer call", function()
	local function listWorld(opts: any?)
		local s = stage()
		local options = opts or {}
		local list = virtual_list.build(Facet, s.core, {
			id = "VL",
			rows = s.core:signal(makeItems(400)),
			key = function(item: any)
				return item.id
			end,
			itemExtent = 40,
			viewportExtent = 400,
			overscan = 0,
			cell = function(item: any)
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		local screen = Facet.UI.Screen({ id = "S", padding = 0, gap = 0, children = { list.blueprint } })
		local handle = s.pres.present(screen, options.presentOpts)
		s.pres.refresh()
		return { s = s, list = list, handle = handle }
	end

	it("VirtualList: an engine scroll slides the window — NO bindNativeScroll call", function()
		local w = listWorld()
		expect(w.list.debugWindow().i1).toBe(true)
		-- the engine ScrollingFrame moved; nothing in this test ever touched the
		-- control's api, and no consumer wired a mirror
		w.s.adapter.driveScroll("/S/VL", { x = 0, y = 2000 })
		w.s.pres.refresh()
		expect(w.list.scrollTop:get()).toBe(2000)
		expect(w.list.debugWindow().i1).toBe(nil)
		expect(w.list.debugWindow().i51).toBe(true)
	end)

	local function gridWorld(axis: string, presentOpts: any?)
		local s = stage()
		local grid = virtual_grid.build(Facet, s.core, {
			id = "VG",
			items = s.core:signal(makeItems(400)),
			key = function(item: any)
				return item.id
			end,
			axis = axis,
			columns = 4,
			itemExtent = 40,
			viewportExtent = 400,
			overscan = 0,
			-- `width` is the CROSS axis and belongs to axis="y" only: on axis="x"
			-- the width IS the scroll axis and the control refuses it by name
			width = if axis == "x" then nil else { type = "fixed", px = 320 },
			cell = function(item: any)
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		local screen = Facet.UI.Screen({ id = "S", padding = 0, gap = 0, children = { grid.blueprint } })
		local handle = s.pres.present(screen, presentOpts)
		s.pres.refresh()
		return { s = s, grid = grid, handle = handle }
	end

	it(
		"VirtualGrid (vertical grid, axis y): an engine scroll slides the window — NO bindNativeScroll call",
		function()
			local w = gridWorld("y")
			expect(w.grid.debugWindow().i1).toBe(true)
			w.s.adapter.driveScroll("/S/VG", { x = 0, y = 400 })
			w.s.pres.refresh()
			expect(w.grid.scrollTop:get()).toBe(400)
			expect(w.grid.debugWindow().i1).toBe(nil)
			expect(w.grid.debugWindow().i41).toBe(true)
		end
	)

	it(
		"VirtualGrid (sideways grid, axis x): an engine scroll slides the window — NO bindNativeScroll call",
		function()
			--[[ THE HORIZONTAL GRID IS NOT A SEPARATE CONTROL AND THAT IS THE POINT.
			`newVirtualHGrid` is `newVirtualGrid{ axis = "x" }` on the same arithmetic
			(`virtual_grid.luau` "TWO AXES ... ON THE SAME ARITHMETIC"), so the brief's
			third control is this case: the mirror has to read the CanvasPosition
			component along the control's OWN axis, and an auto-bind that hard-coded
			`pos.y` would pass every case above and fail exactly here. ]]
			local w = gridWorld("x")
			expect(w.grid.debugWindow().i1).toBe(true)
			w.s.adapter.driveScroll("/S/VG", { x = 400, y = 0 })
			w.s.pres.refresh()
			expect(w.grid.scrollTop:get()).toBe(400)
			expect(w.grid.debugWindow().i1).toBe(nil)
			expect(w.grid.debugWindow().i41).toBe(true)
		end
	)

	local function tableWorld(opts: any?)
		local options = opts or {}
		local s = stage()
		local tbl = table_control.build(Facet, s.core, {
			id = "T",
			columns = { { id = "name", title = "Name", width = { type = "fill", weight = 1 } } },
			rows = s.core:signal(makeItems(400)),
			key = function(item: any)
				return item.id
			end,
			cellFor = function(_columnId: string, item: any)
				return Facet.UI.Text({ id = "Value", text = item.label, textSize = 16 })
			end,
			rowHeight = 40,
			header = false,
			virtualized = if options.virtualized == nil then true else options.virtualized,
			scrolls = options.scrolls,
			env = s.env,
		})
		local screen = Facet.UI.Screen({ id = "S", padding = 0, gap = 0, children = { tbl.blueprint } })
		local handle = s.pres.present(screen, options.presentOpts)
		-- two refreshes: the window is taken against the body's MEASURED height,
		-- which only exists after a solve (see tests/table_virtualized.spec.luau)
		s.pres.refresh()
		s.pres.refresh()
		return { s = s, tbl = tbl, handle = handle }
	end

	it("Table (virtualized): an engine scroll slides the window — NO bindNativeScroll call", function()
		local w = tableWorld()
		local before = w.tbl.dump()
		expect(before.scrollTop).toBe(0)
		w.s.adapter.driveScroll("/S/T/Main/Body", { x = 0, y = 2000 })
		w.s.pres.refresh()
		local after = w.tbl.dump()
		expect(after.scrollTop).toBe(2000)
		-- the WINDOW moved, not just the signal: row 1 left and a row that could
		-- only be reached by scrolling arrived (`@0` is the row's revision suffix,
		-- see tests/table_virtualized.spec.luau's own `rowPath`)
		expect(w.s.adapter.node("/S/T/Main/Body/Canvas/Rows/[i1@0]/Row")).toBeNil()
		expect(w.s.adapter.node("/S/T/Main/Body/Canvas/Rows/[i51@0]/Row") ~= nil).toBe(true)
	end)

	-- =======================================================================
	-- (b) THE SEAM DISCRIMINATOR. Every case in (a) again, on a screen that
	--     DECLARES its focus map — the configuration in which the presenter
	--     never calls `focusGroups` at all. A fix built on `buildFocusGroups`
	--     reddens here and nowhere else.
	-- =======================================================================
	local DECLARED_GROUPS = { { name = "consumer-map", axis = "vertical", entry = "nearest", order = {} } }

	it(
		"...and it still does when the CONSUMER declares navigationGroups (the focusGroups seam is dead here)",
		function()
			local w = listWorld({ presentOpts = { navigationGroups = DECLARED_GROUPS } })
			w.s.adapter.driveScroll("/S/VL", { x = 0, y = 2000 })
			w.s.pres.refresh()
			expect(w.list.scrollTop:get()).toBe(2000)
			expect(w.list.debugWindow().i51).toBe(true)
		end
	)

	it("...and when navigationGroups is a FUNCTION, and when it is `false` (the flat ring)", function()
		local byFn = gridWorld("y", {
			navigationGroups = function()
				return DECLARED_GROUPS
			end,
		})
		byFn.s.adapter.driveScroll("/S/VG", { x = 0, y = 400 })
		byFn.s.pres.refresh()
		expect(byFn.grid.scrollTop:get()).toBe(400)
		expect(byFn.grid.debugWindow().i41).toBe(true)

		local flat = gridWorld("y", { navigationGroups = false })
		flat.s.adapter.driveScroll("/S/VG", { x = 0, y = 400 })
		flat.s.pres.refresh()
		expect(flat.grid.scrollTop:get()).toBe(400)
		expect(flat.grid.debugWindow().i41).toBe(true)
	end)

	it(
		"PROOF THE DISCRIMINATOR IS REAL: with a declared focus map the presenter calls focusGroups ZERO times",
		function()
			--[[ Not an assertion about the fix — an assertion about the SEAM the
			ledger proposed, so that a future agent re-reading O-31 can see why it
			was refused rather than take the refusal on trust. The bundle's own
			`focusGroups` is wrapped in a counter and the control presented twice. ]]
			local function callsUnder(presentOpts: any?): number
				local s = stage()
				local grid = virtual_grid.build(Facet, s.core, {
					id = "VG",
					items = s.core:signal(makeItems(40)),
					key = function(item: any)
						return item.id
					end,
					columns = 4,
					itemExtent = 40,
					viewportExtent = 400,
					width = { type = "fixed", px = 320 },
					cell = function(item: any)
						return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
					end,
				})
				local bp = grid.blueprint
				local bundle = contribution.read({ meta = bp.meta }) :: any
				local calls = 0
				local counted = table.clone(bundle)
				local real = bundle.focusGroups
				counted.focusGroups = function(rootNode: any)
					calls += 1
					return real(rootNode)
				end
				local meta = table.clone(bp.meta)
				meta[contribution.PROP] = counted
				bp = table.freeze({
					class = bp.class,
					id = bp.id,
					props = bp.props,
					children = bp.children,
					meta = table.freeze(meta),
				})
				local screen = Facet.UI.Screen({ id = "S", padding = 0, gap = 0, children = { bp } })
				s.pres.present(screen, presentOpts)
				s.pres.refresh()
				s.pres.refresh()
				return calls
			end
			expect(callsUnder(nil) > 0).toBe(true) -- the ONE configuration it reaches
			expect(callsUnder({ navigationGroups = DECLARED_GROUPS })).toBe(0)
			expect(callsUnder({ navigationGroups = false })).toBe(0)
		end
	)

	-- =======================================================================
	-- (c) THE LIVE CONSUMER MUST NOT DOUBLE-BIND. Rascal Rally's Sponsor HUD
	--     calls `api.bindNativeScroll(self._scrollController)` from its own
	--     `onGeometry` (`FacetSponsor/init.luau:2562`) and holds the unbind for
	--     teardown. `onGeometry` is fed BEFORE the contributions' `syncGeometry`
	--     (presenter `feedGeometry`), so the game's call and the framework's meet
	--     on the same frame, on the same controller and the same path.
	-- =======================================================================
	it("an explicit bindNativeScroll on top of the auto-bind adds NO second engine observer", function()
		local w = listWorld()
		-- the framework's floor, plus EXACTLY ONE mirror it installed for itself
		expect(scrollObserverCount(w.s.adapter, "/S/VL")).toBe(RENDERER_CLIP_OBSERVER + 1)
		--[[ TWO INSTRUMENTS, BECAUSE THE LIVE COUNT ALONE CANNOT SEE THE DEFECT.
			An arbitration that tore the mirror down and reinstalled it on every
			consumer call would leave the live count at exactly 1 and pass — measured,
			mutation M4. So the REGISTRATIONS are counted too: the correct answer is
			that the consumer's call touches the engine seam ZERO times. ]]
		local registrations = 0
		local realObserve = w.s.adapter.observeScroll
		w.s.adapter.observeScroll = function(handle: any, cb: any)
			registrations += 1
			return realObserve(handle, cb)
		end
		local unbind = w.list.bindNativeScroll(w.handle.controller)
		expect(registrations).toBe(0)
		expect(scrollObserverCount(w.s.adapter, "/S/VL")).toBe(RENDERER_CLIP_OBSERVER + 1)
		-- ...and the unbind the consumer is handed stops the mirror ONCE, rather
		-- than removing its own registration and leaving the framework's behind
		w.s.adapter.driveScroll("/S/VL", { x = 0, y = 400 })
		expect(w.list.scrollTop:get()).toBe(400)
		unbind()
		expect(scrollObserverCount(w.s.adapter, "/S/VL")).toBe(RENDERER_CLIP_OBSERVER)
		w.s.adapter.driveScroll("/S/VL", { x = 0, y = 800 })
		expect(w.list.scrollTop:get()).toBe(400)
	end)

	it("...and a refresh after that unbind does NOT resurrect the mirror", function()
		--[[ THE AUTO-BIND IS PER MOUNT, NOT PER FRAME. `syncGeometry` runs every
			refresh, so an auto-bind that re-asserted itself unconditionally would
			make `unbindNativeScroll` a one-frame suggestion — and would silently
			delete the one thing a consumer can still say about the mirror. ]]
		local w = listWorld()
		w.list.bindNativeScroll(w.handle.controller)()
		w.s.pres.refresh()
		w.s.pres.refresh()
		expect(scrollObserverCount(w.s.adapter, "/S/VL")).toBe(RENDERER_CLIP_OBSERVER)
		w.s.adapter.driveScroll("/S/VL", { x = 0, y = 800 })
		expect(w.list.scrollTop:get()).toBe(0)
	end)

	it("the same on Table, whose body path can carry a SECOND mirror observer", function()
		--[[ `Table.bindNativeScroll` registers up to two observers on ONE path —
			the `scrollTop` mirror, and (with `rowActions`) the coordinator's
			scroll-closes-the-open-tray. This table declares no `rowActions`, so the
			count below is the mirror alone; the point is the same either way, that
			an explicit consumer call adds none of them a second time. ]]
		local w = tableWorld()
		expect(scrollObserverCount(w.s.adapter, "/S/T/Main/Body")).toBe(RENDERER_CLIP_OBSERVER + 1)
		local registrations = 0
		local realObserve = w.s.adapter.observeScroll
		w.s.adapter.observeScroll = function(handle: any, cb: any)
			registrations += 1
			return realObserve(handle, cb)
		end
		local unbind = w.tbl.api.bindNativeScroll(w.handle.controller)
		expect(registrations).toBe(0)
		expect(scrollObserverCount(w.s.adapter, "/S/T/Main/Body")).toBe(RENDERER_CLIP_OBSERVER + 1)
		unbind()
		expect(scrollObserverCount(w.s.adapter, "/S/T/Main/Body")).toBe(RENDERER_CLIP_OBSERVER)
	end)

	-- =======================================================================
	-- (d) THE ONE LEGITIMATE NON-BIND, and it needs no new mechanism.
	-- =======================================================================
	it("a BLOCK table (scrolls = false) auto-binds NOTHING — its published scroll path is nil", function()
		--[[ ruling 3, director 2026-08-14 (O-10): under `scrolls = false` the Body
			is a plain VStack the renderer elides, so there is no ScrollingFrame of
			this table's own to observe and `api.scrollPath()` answers nil. The
			auto-bind asks the same function the consumer would have, which is why
			"the scrolling is owned elsewhere" needs no opt-out KEY: the control
			already publishes the answer. ]]
		local w = tableWorld({ scrolls = false, virtualized = false })
		expect(w.tbl.api.scrollPath()).toBeNil()
		-- not even the renderer's floor: `scrolls = false` makes the Body a plain
		-- VStack the renderer elides, so there is no scroll host on that path at all
		expect(scrollObserverCount(w.s.adapter, "/S/T/Main/Body")).toBe(0)
		expect(w.tbl.dump().scrollTop).toBe(0)
	end)

	-- =======================================================================
	-- (e) NEGATIVE CONTROL — nothing here happens without a presenter.
	-- =======================================================================
	it("NEGATIVE CONTROL: a bare mount with no presenter still learns no path, and says so", function()
		--[[ The auto-bind rides the presenter's contribution walk. A control
			mounted by `mountLib.mount` alone (the shape half this suite uses) runs
			no such walk, so the refusal that names the alternative must survive
			verbatim — otherwise this fix would have quietly turned a legible
			construction-time error into a nil-deref somewhere downstream. ]]
		local core = Facet.newCore()
		local list = virtual_list.build(Facet, core, {
			id = "VL",
			rows = core:signal(makeItems(10)),
			key = function(item: any)
				return item.id
			end,
			itemExtent = 40,
			viewportExtent = 400,
			cell = function(item: any)
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		local ok, err = pcall(function()
			list.bindNativeScroll({})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "scroll path unknown", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "pass it explicitly", 1, true) ~= nil).toBe(true)
	end)
end)
