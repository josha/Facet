--!strict
-- Native scroll host conformance (native-substrate NS-A2, ledger rows
-- NS-A2/NS-I1/NS-I2): the solver keeps owning content geometry (E1 here);
-- the adapter receives the scroll REGION (canvas extent) and the framework's
-- programmatic scroll writes; the engine (mirrored headlessly by the fake
-- target's driveScroll) owns the live offset. The fallback path — an adapter
-- WITHOUT the scroll seam — must keep working clip-only, never crash.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")

local function makeScrollSlice(rows: number, opts: { stripScrollSeam: boolean? }?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local children = {}
	for i = 1, rows do
		table.insert(
			children,
			UI.Text({
				id = "Row" .. i,
				text = "Row " .. i,
				textSize = 16,
				height = { type = "fixed", px = 40 },
			})
		)
	end
	local bp = UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.ScrollView({
				id = "List",
				height = { type = "fixed", px = 200 },
				gap = 0,
				padding = 8,
				children = children,
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	if opts and opts.stripScrollSeam then
		(adapter :: any).setScrollRegion = nil
		(adapter :: any).setScrollPosition = nil
		(adapter :: any).observeScroll = nil
	end
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return core, env, root, adapter, controller
end

describe("native scroll host (NS-A2)", function()
	it("a ScrollView declares itself a clip host and sends its solved content extent as the scroll region", function()
		local _, _, _, adapter = makeScrollSlice(10)
		local list = adapter.node("/S/List")
		expect(list.props.clipChildren).toBe(true)
		expect(list.scrollRegion ~= nil).toBe(true)
		expect(list.scrollRegion.axis).toBe("y")
		-- 10 rows x 40px + padding 8 top + 8 bottom = 416
		expect(list.scrollRegion.contentH).toBe(416)
		-- content geometry is still solver-owned: rows carry absolute rects
		expect(adapter.node("/S/List/Row1").rect.y).toBe(8)
		expect(adapter.node("/S/List/Row10").rect.y).toBe(8 + 9 * 40)
	end)

	it("a content change updates the scroll region (and only when it changes)", function()
		local core, env, root, adapter, controller = makeScrollSlice(10)
		adapter.takeOps()
		-- re-solve WITHOUT content change: no scrollregion op
		env:set("viewportRect", { x = 0, y = 0, w = 401, h = 600 })
		local opsA = adapter.takeOps()
		for _, op in opsA do
			expect(string.find(op, "scrollregion") == nil).toBe(true)
		end
		controller.dispose()
		root.dispose()
	end)

	it("non-overflowing content still declares its region honestly", function()
		local _, _, _, adapter = makeScrollSlice(3)
		local list = adapter.node("/S/List")
		-- 3 x 40 + 16 = 136 < 200 viewport: region declared, engine simply
		-- cannot scroll (canvas <= viewport) — no special-case hiding
		expect(list.scrollRegion.contentH).toBe(136)
	end)

	it("controller.scrollTo writes a programmatic scroll position through the adapter", function()
		local _, _, _, adapter, controller = makeScrollSlice(10)
		adapter.takeOps()
		controller.scrollTo("/S/List", { x = 0, y = 120 })
		local sawPos = false
		for _, op in adapter.takeOps() do
			if op == "scrollpos /S/List=0,120" then
				sawPos = true
			end
		end
		expect(sawPos).toBe(true)
		expect(adapter.node("/S/List").scrollPosition.y).toBe(120)
	end)

	it("engine-driven scroll (driveScroll) reaches a framework observer", function()
		local _, _, _, adapter, controller = makeScrollSlice(10)
		local seen: any = nil
		local unsub = controller.observeScroll("/S/List", function(pos)
			seen = pos
		end)
		adapter.driveScroll("/S/List", { x = 0, y = 77 })
		expect(seen ~= nil).toBe(true)
		expect(seen.y).toBe(77)
		unsub()
		adapter.driveScroll("/S/List", { x = 0, y = 99 })
		expect(seen.y).toBe(77)
	end)

	it("FALLBACK: an adapter without the scroll seam mounts, clips, and lays out identically (no crash)", function()
		local _, _, _, adapter, controller = makeScrollSlice(10, { stripScrollSeam = true })
		local list = adapter.node("/S/List")
		expect(list.props.clipChildren).toBe(true)
		expect(list.scrollRegion).toBe(nil)
		expect(adapter.node("/S/List/Row10").rect.y).toBe(8 + 9 * 40)
		-- programmatic scroll degrades to a no-op, never a crash
		controller.scrollTo("/S/List", { x = 0, y = 50 })
		local unsub = controller.observeScroll("/S/List", function() end)
		unsub()
	end)
end)

describe("scroll contentSize includes gaps (migration-agent finding 2026-07-23)", function()
	it("a gapped scroll region's canvas covers rows plus gaps", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 300 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local rows = {}
		for i = 1, 3 do
			table.insert(
				rows,
				UI.Text({ id = "R" .. i, text = "r" .. i, textSize = 14, height = { type = "fixed", px = 40 } })
			)
		end
		local bp = UI.Screen({
			id = "G",
			padding = 0,
			children = {
				UI.ScrollView({
					id = "L",
					height = { type = "fixed", px = 100 },
					gap = 10,
					padding = 0,
					children = rows,
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		-- 3 rows x 40 + 2 gaps x 10 = 140 (was 120: the canvas under-covered and
		-- the last row's tail was unreachable by scrolling)
		expect(adapter.node("/G/L").scrollRegion.contentH).toBe(140)
		-- arrange places R3 at 100 (40+10+40+10): region must cover its bottom
		expect(adapter.node("/G/L/R3").rect.y).toBe(100)
		controller.dispose()
		root.dispose()
	end)
end)

-- ===== A-SV1: the horizontal axis ==========================================
-- `ScrollView{ axis = "x" }` was declared, documented, and validated, but the
-- solver stacked children vertically and summed the WRONG axis in both passes,
-- so a horizontal scroll region reported a canvas that could not be scrolled to
-- and painted its children in a column.

local function makeAxisSlice(axis: string, count: number, cell: number)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local children = {}
	for i = 1, count do
		table.insert(
			children,
			UI.Box({
				id = "Cell" .. i,
				width = { type = "fixed", px = cell },
				height = { type = "fixed", px = cell },
			})
		)
	end
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.ScrollView({
				id = "Strip",
				axis = axis,
				gap = 10,
				width = { type = "fixed", px = 200 },
				height = { type = "fixed", px = 120 },
				children = children,
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return core, root, adapter, controller
end

describe("A-SV1: horizontal ScrollView", function()
	it("lays children out along x and advances by gap", function()
		local _, _, adapter = makeAxisSlice("x", 5, 60)
		local c1 = adapter.node("/S/Strip/Cell1")
		local c2 = adapter.node("/S/Strip/Cell2")
		local c3 = adapter.node("/S/Strip/Cell3")
		expect(c1.rect.y).toBe(c2.rect.y)
		expect(c2.rect.x - c1.rect.x).toBe(70) -- 60 cell + 10 gap
		expect(c3.rect.x - c2.rect.x).toBe(70)
	end)

	it("reports a horizontal canvas extent, not a vertical one", function()
		local _, _, adapter = makeAxisSlice("x", 5, 60)
		local region = adapter.scrollRegionOf("/S/Strip")
		expect(region ~= nil).toBe(true)
		expect((region :: any).axis).toBe("x")
		-- 5 cells x 60 + 4 gaps x 10 = 340
		expect((region :: any).contentW).toBe(340)
		-- cross axis does not accumulate
		expect((region :: any).contentH).toBe(60)
	end)

	it("a cross-axis fill child stretches to the viewport height", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Strip",
					axis = "x",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 120 },
					children = {
						UI.Box({
							id = "Tall",
							width = { type = "fixed", px = 300 },
							height = { type = "fill", weight = 1 },
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/Strip/Tall").rect.h).toBe(120)
	end)

	it("the vertical axis is unchanged", function()
		local _, _, adapter = makeAxisSlice("y", 5, 60)
		local c1 = adapter.node("/S/Strip/Cell1")
		local c2 = adapter.node("/S/Strip/Cell2")
		expect(c1.rect.x).toBe(c2.rect.x)
		expect(c2.rect.y - c1.rect.y).toBe(70)
		local region = adapter.scrollRegionOf("/S/Strip")
		expect((region :: any).contentH).toBe(340)
		expect((region :: any).contentW).toBe(60)
	end)
end)

-- ===== A-SV1: scroll-to-visible ============================================
-- One shared keep-visible substrate: every control that needs to bring a focused
-- or selected descendant into view asks the SAME controller for it, instead of
-- each carrying its own scroll arithmetic.

describe("A-SV1: scrollToVisible", function()
	it("scrolls the minimum distance to bring a node below the viewport into view", function()
		local _, _, _, adapter, controller = makeScrollSlice(20)
		-- rows are 40px in a 200px-tall viewport with 8px padding
		local moved = controller.scrollToVisible("/S/List/Row10")
		expect(moved).toBe(true)
		local pos = adapter.scrollPositionOf("/S/List")
		-- row 10 spans canvas y 368..408 (8 padding + 9*40); the 200px band scrolls
		-- the MINIMUM distance that puts its bottom edge at the band's bottom
		expect((pos :: any).y).toBe(208)
	end)

	it("scrolls up for a node above the current offset", function()
		local _, _, _, adapter, controller = makeScrollSlice(20)
		controller.scrollTo("/S/List", { x = 0, y = 400 })
		local moved = controller.scrollToVisible("/S/List/Row2")
		expect(moved).toBe(true)
		local pos = adapter.scrollPositionOf("/S/List")
		expect((pos :: any).y).toBe(48) -- row 2 top: 8 padding + 40
	end)

	it("does nothing when the node is already fully visible", function()
		local _, _, _, adapter, controller = makeScrollSlice(20)
		local moved = controller.scrollToVisible("/S/List/Row1")
		expect(moved).toBe(false)
	end)

	it("finds the nearest scroll ancestor, not just a direct parent", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local rows = {}
		for i = 1, 12 do
			table.insert(
				rows,
				UI.HStack({
					id = "Row" .. i,
					height = { type = "fixed", px = 40 },
					children = { UI.Button({ id = "Btn", label = "b" .. i }) },
				})
			)
		end
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({ id = "List", height = { type = "fixed", px = 160 }, children = rows }),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(controller.scrollToVisible("/S/List/Row10/Btn")).toBe(true)
		expect(adapter.scrollPositionOf("/S/List") ~= nil).toBe(true)
	end)

	it("returns false for a node with no scroll ancestor", function()
		local _, _, _, _, controller = makeScrollSlice(20)
		expect(controller.scrollToVisible("/S")).toBe(false)
	end)

	it("works on the horizontal axis", function()
		local _, _, adapter, controller = makeAxisSlice("x", 10, 60)
		expect(controller.scrollToVisible("/S/Strip/Cell8")).toBe(true)
		local pos = adapter.scrollPositionOf("/S/Strip")
		expect((pos :: any).x > 0).toBe(true)
	end)

	it("degrades to false on an adapter without the scroll seam", function()
		local _, _, _, _, controller = makeScrollSlice(20, { stripScrollSeam = true })
		expect(controller.scrollToVisible("/S/List/Row10")).toBe(false)
	end)
end)

-- ===== A-SV1: keep-visible is a framework service, not a per-control recipe ==
-- The presenter routes every focus move through the ONE shared substrate, so a
-- plain focusable inside a plain ScrollView scrolls into view with no
-- contribution, no opts, and no control-specific scroll arithmetic.

describe("A-SV1: focus keep-visible through the shared substrate", function()
	local presenterLib = require("../src/present/presenter")
	local actionsLib = require("../src/input/actions")

	local function makeFocusSlice()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local rows = {}
		for i = 1, 15 do
			table.insert(
				rows,
				UI.Button({
					id = "Btn" .. i,
					label = "Row " .. i,
					height = { type = "fixed", px = 40 },
				})
			)
		end
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({ id = "List", height = { type = "fixed", px = 160 }, children = rows }),
			},
		}))
		return core, adapter, pres, handle, system
	end

	it("moving focus past the visible band scrolls the host without any control wiring", function()
		local _, adapter, pres, _, system = makeFocusSlice()
		-- real semantic navigation through the action system, never a direct
		-- focus-graph call (the four-input discipline)
		for _ = 1, 8 do
			system.deviceKey("DPadDown", true)
			system.deviceKey("DPadDown", false)
		end
		pres.refresh()
		local pos = adapter.scrollPositionOf("/S/List")
		expect(pos ~= nil).toBe(true)
		expect((pos :: any).y > 0).toBe(true)
	end)

	it("focus stays on the first rows without scrolling", function()
		local _, adapter, pres = makeFocusSlice()
		pres.refresh()
		local pos = adapter.scrollPositionOf("/S/List")
		expect(pos == nil or (pos :: any).y == 0).toBe(true)
	end)
end)

-- ===== A-SV2: one keep-visible arithmetic, three sources of span =============
-- The consolidation A-SV2 actually calls for. VirtualList and Table are NOT
-- duplicating the renderer's substrate: they serve the case it structurally
-- cannot, because `controller.scrollToVisible` reads a SOLVED RECT and a
-- virtualized or culled row has none. What they legitimately shared was the
-- minimum-distance clamp, and it used to be written three times.

describe("A-SV2: the keep-visible clamp exists exactly once", function()
	local solverLib = require("../src/layout/solver")

	it("scrolls the minimum distance in each direction, or not at all", function()
		-- band 100 at offset 0; a span fully inside needs no scroll
		expect(solverLib.keepVisibleOffset(10, 20, 0, 100)).toBe(nil)
		-- below the band: just enough that its bottom edge reaches the band bottom
		expect(solverLib.keepVisibleOffset(150, 20, 0, 100)).toBe(70)
		-- above the band: just enough that its top edge reaches the band top
		expect(solverLib.keepVisibleOffset(30, 20, 100, 100)).toBe(30)
	end)

	it("clamps to the scrollable extent when one is given", function()
		-- extent 200, band 100 => max offset 100
		expect(solverLib.keepVisibleOffset(500, 20, 0, 100, 200)).toBe(100)
		-- and never below zero
		expect(solverLib.keepVisibleOffset(-50, 20, 10, 100, 200)).toBe(0)
	end)

	it("returns nil rather than a no-op scroll", function()
		-- already at the clamped target: issuing a write would be a wasted engine
		-- round trip and, on a real host, could fight a user fling
		expect(solverLib.keepVisibleOffset(500, 20, 100, 100, 200)).toBe(nil)
	end)

	it("a span taller than the band aligns to its top", function()
		expect(solverLib.keepVisibleOffset(300, 400, 0, 100)).toBe(600)
	end)

	it("all three consumers call it — no second implementation survives", function()
		local fs = require("@lune/fs")
		--[[ THE RENDERER'S OWN CALL LEFT `renderer.luau` FOR `render/scroll_into_view.luau`
			(wicked-fast T8's Phase 0), so "the renderer uses it" is read over
			`renderer_source.all()` — every part the renderer has shed, joined — rather
			than over the one file, the same move `commit_walks_seam`'s own pin needed the
			first time a walk moved out from under it. The other two consumers are not
			part of that split and stay direct file reads. ]]
		local renderer_source = require("./lib/renderer_source")
		if string.find(renderer_source.all(), "keepVisibleOffset", 1, true) == nil then
			error("the renderer (across its own parts) does not use the shared keepVisibleOffset")
		end
		for _, file in { "src/controls/virtual_list.luau", "src/controls/table.luau" } do
			local source = fs.readFile(file)
			if string.find(source, "keepVisibleOffset", 1, true) == nil then
				error(`{file} does not use the shared keepVisibleOffset`)
			end
		end
	end)

	it("the renderer's substrate and the index path agree on the same geometry", function()
		-- the same row, described once by a solved rect and once by an index, must
		-- produce the same offset — that equivalence is the point of sharing it
		local rowHeight, band, index = 40, 200, 10
		local fromIndex = solverLib.keepVisibleOffset((index - 1) * rowHeight, rowHeight, 0, band)
		local fromRect = solverLib.keepVisibleOffset(360, 40, 0, band)
		expect(fromIndex).toBe(fromRect)
		expect(fromIndex).toBe(200)
	end)
end)

-- ===========================================================================
-- THE ADAPTER'S OWN OBSERVER CONTRACT (2026-08-13, playlist swipe-actions round)
-- ===========================================================================
-- `observeScroll` is a MULTI-observer seam on the real target: ScreenTarget
-- opens an independent `GetPropertyChangedSignal("CanvasPosition")` connection
-- per call and hands back a closure that disconnects only that one. The fake
-- target held a SINGLE slot, so the second registration silently replaced the
-- first -- and `Table.bindNativeScroll` genuinely registers two on the same
-- body path (the `scrollTop` mirror, then a `rowActions` coordinator's
-- scroll-closes-the-tray). Headlessly the mirror went dead and reported 0.
--
-- These cases pin the instrument, because a fake target that cannot hold what
-- the real one holds does not fail loudly -- it reports a wrong number.

describe("fake target: observeScroll holds every observer, like the engine does", function()
	local function scrollNode()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bp = UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.ScrollView({
					id = "List",
					height = { type = "fixed", px = 100 },
					children = { UI.Text({ id = "R", text = "row", height = { type = "fixed", px = 400 } }) },
				}),
			},
		})
		local adapter = fake_target.new()
		local root = mountLib.mount(core, bp)
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return adapter, controller, "/S/List"
	end

	it("TWO observers on one node BOTH fire (the single-slot bug, pinned)", function()
		local adapter, controller, path = scrollNode()
		local a, b = {}, {}
		controller.observeScroll(path, function(pos)
			table.insert(a, pos.y)
		end)
		controller.observeScroll(path, function(pos)
			table.insert(b, pos.y)
		end)
		adapter.driveScroll(path, { x = 0, y = 40 })
		-- the SECOND registration used to evict the first: `a` stayed empty
		expect(#a).toBe(1)
		expect(#b).toBe(1)
		expect(a[1]).toBe(40)
		expect(b[1]).toBe(40)
	end)

	it("unsubscribing one leaves the other live, and is idempotent", function()
		local adapter, controller, path = scrollNode()
		local a, b = {}, {}
		local offA = controller.observeScroll(path, function(pos)
			table.insert(a, pos.y)
		end)
		controller.observeScroll(path, function(pos)
			table.insert(b, pos.y)
		end)
		offA()
		offA() -- a second call must not evict SOMEBODY ELSE'S entry
		adapter.driveScroll(path, { x = 0, y = 60 })
		expect(#a).toBe(0)
		expect(#b).toBe(1)
		expect(b[1]).toBe(60)
	end)

	it("an observer that unsubscribes itself mid-fire does not skip its sibling", function()
		local adapter, controller, path = scrollNode()
		local seen = {}
		local off
		off = controller.observeScroll(path, function()
			table.insert(seen, "first")
			off()
		end)
		controller.observeScroll(path, function()
			table.insert(seen, "second")
		end)
		adapter.driveScroll(path, { x = 0, y = 30 })
		expect(table.concat(seen, ",")).toBe("first,second")
		-- ...and the self-removal really took effect
		adapter.driveScroll(path, { x = 0, y = 70 })
		expect(table.concat(seen, ",")).toBe("first,second,second")
	end)
end)

--[[ THE ENGINE ADAPTER'S NIL-INSTANCE CONTRACT (live showcase, 2026-08-13) ────
	`src/client/screen_target.luau` is engine-only (module-level `game` requires),
	so it cannot be mounted here — the house pattern for pinning an invariant in
	it is a SOURCE anchor (tests/adaptive.spec.luau and tests/button_shape.spec
	.luau both do exactly this). What is pinned is a FAMILY invariant rather than
	one line: every function in the scroll seam must tolerate a handle whose
	instance is nil, because the renderer elides a node that paints nothing and a
	`Table` with `scrolls = false` still publishes `<root>/Main/Body` as its
	scroll path. `observeScroll` was the one member that did not, and it threw on
	the real client — "'Playlist table' failed to mount: screen_target:3338:
	attempt to index nil with 'IsA'" — abandoning the example's mount there.
]]
describe("screen_target: the scroll seam tolerates an elided (instance-less) handle", function()
	local SEAM = { "setScrollRegion", "setScrollPosition", "getScrollPosition", "observeScroll" }

	-- THE SEAM SPANS TWO FILES since the scroll extraction: `setScrollRegion` and
	-- `setScrollPosition` moved to src/client/screen_scroll_indicators (Studio's
	-- 200_000-char `Source` write cap) where they are plain locals rebound onto the
	-- adapter, while `getScrollPosition` / `observeScroll` are still declared on the
	-- adapter in screen_target. Both declaration shapes are searched, in both files,
	-- so the guard stays pinned wherever the function lives.
	local SEAM_SOURCES = {
		"src/client/screen_target.luau",
		"src/client/screen_scroll_indicators.luau",
	}
	local function declShapes(name: string): { string }
		return { `\n\tfunction adapter.{name}(`, `\n\tlocal function {name}(` }
	end

	it("every scroll-seam adapter function guards a nil instance before indexing it", function()
		local fs = require("@lune/fs")
		local missing = {}
		for _, name in SEAM do
			-- the function body from its declaration to the next top-level
			-- function (or end of file)
			local source: string? = nil
			local from: number? = nil
			for _, path in SEAM_SOURCES do
				local candidate = fs.readFile(path)
				for _, decl in declShapes(name) do
					local at = string.find(candidate, decl, 1, true)
					if at ~= nil then
						source, from = candidate, at
					end
				end
			end
			expect(`{name} declared: {from ~= nil}`).toBe(`{name} declared: true`)
			local rest = string.sub(source :: string, (from :: number) + 1)
			local nextFn: number? = nil
			for _, marker in { "\n\tfunction adapter.", "\n\tlocal function " } do
				local at = string.find(rest, marker, 1, true)
				if at ~= nil and (nextFn == nil or at < nextFn) then
					nextFn = at
				end
			end
			local body = if nextFn ~= nil then string.sub(rest, 1, nextFn) else rest
			-- it must READ handle.instance (otherwise the guard question is moot
			-- and this case would pass on a function that no longer does the job)
			expect(`{name} reads handle.instance: {string.find(body, "handle.instance", 1, true) ~= nil}`).toBe(
				`{name} reads handle.instance: true`
			)
			local guarded = string.find(body, "instance == nil", 1, true) ~= nil
				or string.find(body, "instance ~= nil", 1, true) ~= nil
			if not guarded then
				table.insert(missing, name)
			end
		end
		expect(`unguarded: {table.concat(missing, ",")}`).toBe("unguarded: ")
	end)

	it("...and so do the indicator helpers that share the same handle", function()
		local fs = require("@lune/fs")
		-- the sibling precedent the guard above is modelled on — if these ever
		-- lose it, the "every neighbour already does this" argument is stale.
		-- Counted across BOTH seam files: the helpers moved to
		-- screen_scroll_indicators, the count did not change.
		local count = 0
		for _, path in SEAM_SOURCES do
			for _ in string.gmatch(fs.readFile(path), 'if instance == nil or not instance:IsA%("ScrollingFrame"%) then') do
				count += 1
			end
		end
		expect(count >= 6).toBe(true)
	end)
end)
