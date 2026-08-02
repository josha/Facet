--!strict
-- UI.Path + path_shapes (native-substrate NS-A7, ledger row NS-A7):
-- deterministic shape math (E1) and the paint-only reactive contract. The
-- engine half (Path2D stroking, 100-point limit, scaling into the solved
-- rect) is proven by the Studio scenario 'path_ring' and spike m5-path2d.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local path_shapes = require("../src/controls/path_shapes")
local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

describe("path_shapes: deterministic arc math (NS-A7)", function()
	it("a full ring closes: 9 points, endpoints coincide, all on the radius", function()
		local pts = path_shapes.ring()
		expect(#pts).toBe(9)
		expect(near(pts[1].x, pts[#pts].x)).toBe(true)
		expect(near(pts[1].y, pts[#pts].y)).toBe(true)
		for _, p in pts do
			local r = math.sqrt((p.x - 0.5) ^ 2 + (p.y - 0.5) ^ 2)
			expect(near(r, 0.5, 1e-9)).toBe(true)
		end
	end)

	it("screen angle convention: 0deg is up, 90deg is right, y grows down", function()
		local pts = path_shapes.arc(0, 90, { segments = 2 })
		expect(near(pts[1].x, 0.5)).toBe(true)
		expect(near(pts[1].y, 0.0)).toBe(true) -- top of the box
		expect(near(pts[#pts].x, 1.0)).toBe(true)
		expect(near(pts[#pts].y, 0.5)).toBe(true) -- right of the box
	end)

	it("tangent handedness: out = forward along the path, in = backward, exact bezier handle length", function()
		local segs = 4
		local pts = path_shapes.arc(0, 180, { segments = segs })
		local thetaSeg = math.rad(180 / segs)
		local expectedLen = (4 / 3) * math.tan(thetaSeg / 4) * 0.5
		-- at the start point (top, moving clockwise = +x direction)
		local p1 = pts[1]
		expect(near(p1.outX, expectedLen, 1e-9)).toBe(true)
		expect(near(p1.outY, 0, 1e-9)).toBe(true)
		expect(near(p1.inX, -expectedLen, 1e-9)).toBe(true)
		-- in/out are always mirrored for a smooth arc point
		for _, p in pts do
			expect(near(p.inX, -p.outX, 1e-9)).toBe(true)
			expect(near(p.inY, -p.outY, 1e-9)).toBe(true)
		end
	end)

	it("progress sweep is monotonic: a bigger sweep ends farther along the circle", function()
		local a = path_shapes.arc(0, 90)
		local b = path_shapes.arc(0, 234)
		-- 90deg endpoint at the right; 234deg endpoint in the lower-left
		expect(a[#a].x > 0.9).toBe(true)
		expect(b[#b].x < 0.5).toBe(true)
		expect(b[#b].y > 0.5).toBe(true)
	end)

	it("needle: two straight points from inner to outer radius at the angle", function()
		local pts = path_shapes.needle(90, { innerRadius = 0.2, radius = 1 })
		expect(#pts).toBe(2)
		expect(near(pts[1].x, 0.6)).toBe(true)
		expect(near(pts[1].y, 0.5)).toBe(true)
		expect(near(pts[2].x, 1.0)).toBe(true)
		expect(pts[1].outX).toBe(0)
	end)

	it("segment counts respect the engine's 100-point limit", function()
		local ok = pcall(function()
			return path_shapes.arc(0, 360, { segments = 120 })
		end)
		expect(ok).toBe(false)
	end)
end)

describe("UI.Path: paint-only reactive stroke (NS-A7)", function()
	it("mounts as a leaf; a points change is one prop write and never a re-solve", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local progress = core:signal(0.25)
		local points = core:memo(function(use)
			return path_shapes.arc(0, 360 * use(progress))
		end)
		local bp = UI.Screen({
			id = "P",
			children = {
				UI.Path({
					id = "Ring",
					points = points,
					thickness = 6,
					role = "accent",
					width = { type = "fixed", px = 120 },
					height = { type = "fixed", px = 120 },
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local node = adapter.node("/P/Ring")
		expect(node ~= nil).toBe(true)
		expect(node.rect.w).toBe(120)
		expect(#node.props.points >= 3).toBe(true)
		expect(node.props.thickness).toBe(6)
		adapter.takeOps()
		local solvesBefore = controller.stats().solves
		progress:set(0.75)
		controller.refresh()
		local ops = adapter.takeOps()
		expect(#ops).toBe(1)
		expect(string.find(ops[1], "prop /P/Ring.points") ~= nil).toBe(true)
		expect(controller.stats().solves).toBe(solvesBefore)
		controller.dispose()
		root.dispose()
	end)
end)

-- ===== RS-PATHCLIP: a stroked path never paints outside its clip host ======
--
-- The engine draws `UI.Path` as a stroke that no ancestor clip crops, so a
-- windowed row sitting outside a list's viewport still painted its ring — a
-- family-hued arc floating on empty plate, unattached to any row (Sponsor
-- review round 1, F1). A stroke cannot be cropped half-way, so the framework's
-- rule is all-or-nothing: a path not FULLY inside every clip host above it does
-- not paint. These specs are the mechanism, over the same scroll host the real
-- adapter mounts.
local function mountClippedPaths(rows: number, rowH: number, viewportH: number, ringPx: number?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 300, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local children = {}
	for i = 1, rows do
		table.insert(
			children,
			UI.ZStack({
				id = "Row" .. i,
				height = { type = "fixed", px = rowH },
				children = {
					UI.Path({
						id = "Ring",
						points = path_shapes.ring(),
						closed = true,
						width = { type = "fixed", px = ringPx or 16 },
						height = { type = "fixed", px = ringPx or 16 },
					}),
				},
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
				height = { type = "fixed", px = viewportH },
				axis = "y",
				padding = 0,
				gap = 0,
				clipChildren = true,
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

describe("UI.Path clipping (RS-PATHCLIP)", function()
	it("a path whose row is outside the scroll viewport does not paint", function()
		-- 6 rows of 50 in a 100px viewport: rows 1-2 are inside, 3-6 are not
		local _, root, adapter, controller = mountClippedPaths(6, 50, 100)
		expect(adapter.visibleOf("/S/List/Row1/Ring")).toBe(true)
		expect(adapter.visibleOf("/S/List/Row2/Ring")).toBe(true)
		expect(adapter.visibleOf("/S/List/Row3/Ring")).toBe(false)
		expect(adapter.visibleOf("/S/List/Row6/Ring")).toBe(false)
		controller.dispose()
		root.dispose()
	end)

	it("the cull follows the LIVE scroll offset, with no re-solve", function()
		local _, root, adapter, controller = mountClippedPaths(6, 50, 100)
		local solvesBefore = controller.stats().solves
		-- the engine scrolled two rows down: 3-4 come in, 1-2 go out
		adapter.driveScroll("/S/List", { x = 0, y = 100 })
		expect(adapter.visibleOf("/S/List/Row1/Ring")).toBe(false)
		expect(adapter.visibleOf("/S/List/Row3/Ring")).toBe(true)
		expect(adapter.visibleOf("/S/List/Row4/Ring")).toBe(true)
		expect(adapter.visibleOf("/S/List/Row5/Ring")).toBe(false)
		-- a same-window scroll writes no rects, so the cull may not force one
		expect(controller.stats().solves).toBe(solvesBefore)
		controller.dispose()
		root.dispose()
	end)

	it("a partially-clipped row's path is culled: a stroke has no half-crop", function()
		-- row-filling rings of 60 in a 70px viewport: row 2's ring spans 60..120
		-- and the viewport ends at 70, so it OVERLAPS the edge rather than
		-- missing it entirely — the case the engine has no operation for
		local _, root, adapter, controller = mountClippedPaths(3, 60, 70, 60)
		expect(adapter.visibleOf("/S/List/Row1/Ring")).toBe(true)
		expect(adapter.visibleOf("/S/List/Row2/Ring")).toBe(false)
		controller.dispose()
		root.dispose()
	end)

	it("a path with no clip host above it is never culled", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 300 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bp = UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.Path({
					id = "Ring",
					points = path_shapes.ring(),
					width = { type = "fixed", px = 40 },
					height = { type = "fixed", px = 40 },
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.visibleOf("/S/Ring") ~= false).toBe(true)
		controller.dispose()
		root.dispose()
	end)
end)
