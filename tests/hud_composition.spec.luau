--!strict
-- THE SCREEN-ANCHORED HUD (ADR-0025).
--
-- The commissioning case is two screenshots of a shipped FPS: fullscreen the HUD
-- is right, and with a browser URL bar open — SAME WIDTH, ~200px LESS HEIGHT —
-- the clusters climb into each other. A task panel lands on the round buttons
-- above it; a weapon rail runs into the fps/ping readout beside it.
--
-- So every case in this file drives a HEIGHT SHRINK at a fixed width, and asserts
-- the two things the screenshots got wrong:
--
--   1. the nine anchored zones PARTITION the box — their rects never intersect,
--      at any height, and a zone stays in the column it was pinned to even when
--      a neighbouring column empties (`holdsLane`, ADR-0025 Decision 2);
--   2. when the height runs out the HUD DEGRADES BY RANK — step down before
--      drop, descending rank — which is ADR-0023's ladder reused literally
--      rather than a second copy of it;
--
-- ...and the alarm for the residual case a partition cannot remove: a zone whose
-- CONTENT is wider than the column it was given is drawing on top of the column
-- next door, and `resolution.collisions` says so by name (Decision 3).
--
-- Most of this is the PURE decision (ADR-0023 Decision 2's bargain), so a device
-- matrix is a sweep rather than a screenshot review. The last describe closes the
-- loop through the real path: a mounted HUD over FakeTarget whose viewport loses
-- 200px of height, where the proof is rects and the solver's own findings.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local composition = require("../src/layout/composition")
local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

-- ===== the fixture =========================================================
-- Shaped like the screenshot: Roblox's own chrome top-left, a round-button strip
-- and a task panel down the left, a round timer top-centre, a weapon rail and a
-- readout top-right, action buttons bottom-right.

local SIZES: { [string]: { { w: number, h: number } } } = {
	Chrome = { { w = 180, h = 40 } },
	RoundBtns = { { w = 220, h = 60 }, { w = 110, h = 60 } },
	Tasks = { { w = 220, h = 180 }, { w = 220, h = 90 } },
	Timer = { { w = 120, h = 48 } },
	Rail = { { w = 160, h = 200 }, { w = 160, h = 96 } },
	Readout = { { w = 140, h = 34 } },
	Actions = { { w = 140, h = 160 }, { w = 140, h = 80 } },
}

local function measureFn(id: string, form: number, _availW: number, _availH: number): (number, number)
	local list = SIZES[id]
	local s = list[math.min(form, #list)]
	return s.w, s.h
end

local CTX = { measure = measureFn }

local function hud(regions: { any }): any
	return {
		groups = composition.HUD_GROUPS,
		arrangements = { composition.HUD },
		regions = regions,
	}
end

local FULL = {
	{ id = "Chrome", group = "topLeft", rank = 1, forms = 1 },
	{ id = "RoundBtns", group = "topLeft", rank = 5, forms = 2 },
	{ id = "Tasks", group = "left", rank = 8, forms = 2, mayDrop = true },
	{ id = "Timer", group = "top", rank = 2, forms = 1 },
	{ id = "Rail", group = "topRight", rank = 3, forms = 2 },
	{ id = "Readout", group = "topRight", rank = 7, forms = 1, mayDrop = true },
	{ id = "Actions", group = "bottomRight", rank = 4, forms = 2 },
}

local function intersects(a: any, b: any): (number, number)
	local dx = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local dy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if dx > 0.5 and dy > 0.5 then
		return dx, dy
	end
	return 0, 0
end

-- every mounted pair, so a failure names WHICH two zones landed on each other
local function assertNoOverlap(resolution: any, where: string)
	for i, a in resolution.regions do
		for j, b in resolution.regions do
			if j <= i or not a.mounted or not b.mounted or a.rect == nil or b.rect == nil then
				continue
			end
			local dx, dy = intersects(a.rect, b.rect)
			if dx > 0 then
				error(`{where}: zone '{a.id}' and zone '{b.id}' overlap by {dx}x{dy}px`, 0)
			end
		end
	end
end

-- ===== 1. the partition ====================================================

describe("ADR-0025: the nine anchors PARTITION the screen", function()
	it("the HUD preset resolves three equal columns that tile the offer exactly", function()
		local r = composition.resolve(hud(FULL), { w = 900, h = 500 }, CTX)
		expect(r.arrangement).toBe("hud")
		expect(r.fallback).toBe(false)
		expect(#r.lanes).toBe(3)
		expect(r.lanes[1].rect.x).toBe(0)
		expect(r.lanes[1].rect.w).toBe(300)
		expect(r.lanes[2].rect.x).toBe(300)
		expect(r.lanes[2].rect.w).toBe(300)
		expect(r.lanes[3].rect.x).toBe(600)
		expect(r.lanes[3].rect.w).toBe(300)
	end)

	it("each zone lands in the column and the band its name says", function()
		local r = composition.resolve(hud(FULL), { w = 900, h = 500 }, CTX)
		local by = r.regionById
		-- upper LEFT
		expect(by.Chrome.rect.x).toBe(0)
		expect(by.Chrome.rect.y).toBe(0)
		-- upper CENTRE: centred across its own column, not the screen's left edge
		expect(by.Timer.rect.x >= 300).toBe(true)
		expect(by.Timer.rect.x + by.Timer.rect.w <= 600).toBe(true)
		expect(by.Timer.rect.y).toBe(0)
		-- upper RIGHT, hard against the right edge
		expect(by.Rail.rect.x + by.Rail.rect.w).toBe(900)
		expect(by.Rail.rect.y).toBe(0)
		-- LOWER right: its bottom is the offer's bottom
		expect(by.Actions.rect.y + by.Actions.rect.h).toBe(500)
		expect(by.Actions.rect.x + by.Actions.rect.w).toBe(900)
		-- MIDDLE left: below the top band, above the bottom
		expect(by.Tasks.rect.y > by.Chrome.rect.y + by.Chrome.rect.h).toBe(true)
	end)

	it("an aligned zone takes ITS OWN width inside the column, not the whole column", function()
		-- `align` is what asks for the content width: aligning a box that already
		-- fills its lane would mean nothing. Without it the zone is the column, and
		-- "hard against the right edge" would be true of a 300px-wide blank.
		local r = composition.resolve(hud(FULL), { w = 900, h = 500 }, CTX)
		expect(r.regionById.Rail.rect.w).toBe(160) -- its measure, not the 300px lane
		expect(r.regionById.Rail.rect.x).toBe(740) -- 900 - 160
		expect(r.regionById.Timer.rect.w).toBe(120)
		expect(r.regionById.Timer.rect.x).toBe(390) -- 300 + (300 - 120) / 2
		expect(r.regionById.Chrome.rect.w).toBe(180)
		expect(r.regionById.Chrome.rect.x).toBe(0)
	end)

	it("no two zones intersect, at any height a landscape phone can lose", function()
		for _, h in { 500, 440, 380, 320, 300, 260, 240, 200 } do
			local r = composition.resolve(hud(FULL), { w = 900, h = h }, CTX)
			assertNoOverlap(r, `900x{h}`)
		end
	end)
end)

-- ===== 2. holdsLane: a column keeps its place when it empties ===============

describe("ADR-0025 Decision 2: holdsLane pins a column that has nothing in it", function()
	local SPARSE = {
		{ id = "Chrome", group = "topLeft", rank = 1, forms = 1 },
		{ id = "Rail", group = "topRight", rank = 3, forms = 2 },
	}

	it("an empty centre column keeps its third and the right cluster does not move", function()
		local full = composition.resolve(hud(FULL), { w = 900, h = 500 }, CTX)
		local sparse = composition.resolve(hud(SPARSE), { w = 900, h = 500 }, CTX)
		expect(sparse.lanes[2].collapsed).toBe(false)
		expect(sparse.lanes[2].rect.w).toBe(300)
		expect(sparse.lanes[3].rect.x).toBe(600)
		-- the director's requirement, stated as an equality: the same zone is in
		-- the same place whether or not its neighbour has anything to say
		expect(sparse.regionById.Rail.rect.x).toBe(full.regionById.Rail.rect.x)
	end)

	it("without the flag the lane still releases — rule 9 is unchanged", function()
		local groups = {}
		for _, g in composition.HUD_GROUPS do
			local copy = table.clone(g)
			copy.holdsLane = nil
			table.insert(groups, copy)
		end
		local r = composition.resolve({
			groups = groups,
			arrangements = { composition.HUD },
			regions = SPARSE,
		}, { w = 900, h = 500 }, CTX)
		expect(r.lanes[2].collapsed).toBe(true)
		expect(r.lanes[3].rect.x).toBe(450)
	end)

	it("holdsLane is refused on a spanning group — a span row has no lane to hold", function()
		local ok, err = pcall(function()
			composition.normalize({
				groups = { { id = "band", span = "above", holdsLane = true }, { id = "a", lane = "main" } },
				regions = { { id = "R", group = "a", rank = 1, forms = 1 } },
				arrangements = { { name = "one", lanes = { { "main" } } } },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "holdsLane") ~= nil).toBe(true)
	end)

	it("holdsLane must be a boolean", function()
		local ok, err = pcall(function()
			composition.normalize({
				groups = { { id = "a", lane = "main", holdsLane = "yes" } },
				regions = { { id = "R", group = "a", rank = 1, forms = 1 } },
				arrangements = { { name = "one", lanes = { { "main" } } } },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "holdsLane") ~= nil).toBe(true)
	end)
end)

-- ===== 2b. the topbar zone: the row level with the platform's controls =======

describe("ADR-0027: the `topbar` zone is a span row, and it is free when unused", function()
	local function serialize(v: any): string
		if type(v) ~= "table" then
			return tostring(v)
		end
		local keys: { any } = {}
		for k in v do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, k in keys do
			table.insert(parts, `{tostring(k)}={serialize((v :: any)[k])}`)
		end
		return `\{{table.concat(parts, ",")}\}`
	end

	it("a HUD that declares nothing in it resolves BYTE-IDENTICALLY to one without the group", function()
		local before: { any } = {}
		for _, g in composition.HUD_GROUPS do
			if g.id ~= "topbar" then
				table.insert(before, g)
			end
		end
		expect(#before).toBe(#composition.HUD_GROUPS - 1)
		for _, size in { { w = 900, h = 500 }, { w = 900, h = 300 }, { w = 320, h = 640 } } do
			local withZone = composition.resolve(hud(FULL), size, CTX)
			local without =
				composition.resolve({ groups = before, arrangements = { composition.HUD }, regions = FULL }, size, CTX)
			expect(serialize(composition.dump(withZone))).toBe(serialize(composition.dump(without)))
		end
	end)

	it("a region declared in it rides ABOVE every lane and spends the height from the lane budget", function()
		local regions = table.clone(FULL)
		table.insert(regions, { id = "Strip", group = "topbar", rank = 2, forms = 1 })
		local sizes = table.clone(SIZES)
		sizes.Strip = { { w = 900, h = 58 } }
		local ctx = {
			measure = function(id: string, form: number, _w: number, _h: number): (number, number)
				local list = sizes[id]
				local s = list[math.min(form, #list)]
				return s.w, s.h
			end,
		}
		local r = composition.resolve({
			groups = composition.HUD_GROUPS,
			arrangements = { composition.HUD },
			regions = regions,
		}, { w = 900, h = 500 }, ctx)
		local strip = r.regionById.Strip
		expect(strip.span).toBe("above")
		expect(strip.rect.y).toBe(0)
		expect(strip.rect.h).toBe(58)
		-- every lane — and therefore every one of the nine anchored zones — starts
		-- BELOW it, which is what keeps the top-left cluster off the platform's own
		for _, lane in r.lanes do
			expect(lane.rect.y >= 58).toBe(true)
		end
		expect(r.regionById.Chrome.rect.y >= 58).toBe(true)
		assertNoOverlap(r, "900x500 with a topbar row")
	end)
end)

-- ===== 3. the height shrink degrades by rank ================================

describe("ADR-0025: a height shrink DEGRADES, in rank order", function()
	it("the least important zone in the failing column gives way first", function()
		local tall = composition.resolve(hud(FULL), { w = 900, h = 500 }, CTX)
		expect(tall.regionById.Rail.form).toBe(1)
		expect(tall.regionById.Readout.dropped).toBe(false)

		-- the screenshot's exact case: a landscape phone loses ~200px of HEIGHT at
		-- the same width. The right column needs 200+34+160 = 394px and has 300.
		local short = composition.resolve(hud(FULL), { w = 900, h = 300 }, CTX)
		assertNoOverlap(short, "900x300")
		-- Actions (rank 4) and Rail (rank 3) both have a second form; Readout is
		-- rank 7 and droppable. Descending rank = the highest number gives way
		-- first, and STEP DOWN comes before DROP — so Actions steps before
		-- Readout drops, even though Readout ranks lower.
		expect(short.regionById.Actions.form).toBe(2)
		expect(short.regionById.Readout.dropped).toBe(false)
	end)

	it("a column that runs out of forms drops its droppable zone, and no other", function()
		local r = composition.resolve(hud(FULL), { w = 900, h = 200 }, CTX)
		assertNoOverlap(r, "900x200")
		expect(r.regionById.Readout.dropped).toBe(true)
		-- rank 3 and rank 4 are still on screen: a drop takes the least important
		-- thing in the FAILING column, not everything
		expect(r.regionById.Rail.mounted).toBe(true)
		expect(r.regionById.Actions.mounted).toBe(true)
		-- ...and the LEFT column, which fits, was never touched
		expect(r.regionById.Tasks.dropped).toBe(false)
	end)

	--[[ THE WIDTH HALF, found by the sweep rather than by this file (2026-08-14).

		Rule 2 asks whether the HUG lanes fit the offer, which is the only width
		question a lane whose width IS its content can fail. A HUD's lanes are
		`fill` — a share of the box — so a cluster wider than its share could not
		fail anything: it painted over the column next door and the ladder never
		ran. On a 320px phone each column is 106px, which is where every horizontal
		cluster in the showcase met it at once.

		So a lane's width overflow is an overflow like any other and goes to the
		same rule-3 ladder. The scroll region is excluded for the same reason it is
		excluded from the collision scan. ]]
	it("a cluster WIDER than its column steps down too — width is space", function()
		local ctx = {
			measure = function(id: string, form: number, _availW: number, _availH: number): (number, number)
				if id == "Rail" then
					-- a 3-pill row, then a single pill: the width ladder
					return (if form == 1 then 240 else 90), 40
				end
				return 80, 40 -- the Timer, narrow enough for any column here
			end,
		}
		local ZONES = {
			{ id = "Rail", group = "topRight", rank = 3, forms = 2 },
			{ id = "Timer", group = "top", rank = 2, forms = 1 },
		}
		local roomy = composition.resolve(hud(ZONES), { w = 900, h = 500 }, ctx)
		expect(roomy.regionById.Rail.form).toBe(1)
		expect(#roomy.collisions).toBe(0)

		-- 320px wide: each column is 106px and the 240px rail does not fit one
		local narrow = composition.resolve(hud(ZONES), { w = 320, h = 500 }, ctx)
		expect(narrow.regionById.Rail.form).toBe(2)
		expect(narrow.fallback).toBe(false)
		expect(#narrow.collisions).toBe(0)
		assertNoOverlap(narrow, "320x500")
	end)

	it("a zone that was never in the failing column keeps its richest form", function()
		local r = composition.resolve(hud(FULL), { w = 900, h = 320 }, CTX)
		expect(r.regionById.Timer.form).toBe(1)
		expect(r.regionById.Chrome.mounted).toBe(true)
	end)
end)

-- ===== 4. the collision alarm ==============================================

describe("ADR-0025 Decision 3: a zone painting over its neighbour is REPORTED", function()
	-- one wide zone, authored to a size no column can hold: 400px of content in a
	-- 300px column is 100px of paint on top of the column next door
	local WIDE = {
		{ id = "Chrome", group = "topLeft", rank = 1, forms = 1 },
		{ id = "Timer", group = "top", rank = 2, forms = 1 },
	}

	local function wideCtx(chromeW: number)
		return {
			measure = function(id: string, form: number, availW: number, availH: number): (number, number)
				if id == "Chrome" then
					return chromeW, 40
				end
				if id == "Timer" then
					-- as wide as its own column, so the overlap arithmetic is the two
					-- column edges and not a centring offset
					return 300, 48
				end
				return measureFn(id, form, availW, availH)
			end,
		}
	end

	it("a well-behaved HUD reports NO collisions", function()
		local r = composition.resolve(hud(FULL), { w = 900, h = 500 }, CTX)
		expect(#r.collisions).toBe(0)
	end)

	it("a zone wider than its column names the zone it is painting over", function()
		local r = composition.resolve(hud(WIDE), { w = 900, h = 500 }, wideCtx(400))
		expect(#r.collisions).toBe(1)
		local c = r.collisions[1]
		expect(c.a).toBe("Chrome")
		expect(c.b).toBe("Timer")
		expect(c.dx).toBe(100)
		expect(c.dy > 0).toBe(true)
	end)

	it("a wide zone with nothing beside it is not a collision", function()
		-- the same 400px zone, alone: it overflows its column and lands on empty
		-- screen. That is the inner stack's finding, not a collision
		local r = composition.resolve(hud({ WIDE[1] }), { w = 900, h = 500 }, wideCtx(400))
		expect(#r.collisions).toBe(0)
	end)

	it("the SCROLL region is excluded — its content is meant to be bigger than its box", function()
		-- rule 5's one scroll region clips its own content, so a measure past the
		-- column it was given is the mechanism working, not a zone on a zone. The
		-- same 400px measure that is a collision above is silence here.
		local r = composition.resolve(
			hud({
				{ id = "Chrome", group = "topLeft", rank = 1, forms = 1, mayScroll = true },
				{ id = "Timer", group = "top", rank = 2, forms = 1 },
			}),
			{ w = 900, h = 500 },
			wideCtx(400)
		)
		expect(r.scroller).toBe("Chrome")
		expect(#r.collisions).toBe(0)
	end)

	it("the collisions ride the dump, deterministically ordered", function()
		local r = composition.resolve(hud(WIDE), { w = 900, h = 500 }, wideCtx(400))
		local a = composition.dump(r)
		local b = composition.dump(r)
		expect(a.collisions[1].a).toBe("Chrome")
		expect(a.collisions[1].b).toBe("Timer")
		expect(#b.collisions).toBe(1)
	end)

	it("ADDITIVE: a declaration with no collision dumps `collisions = {}`", function()
		local d = composition.dump(composition.resolve(hud(FULL), { w = 900, h = 500 }, CTX))
		expect(#d.collisions).toBe(0)
		expect(d.schema).toBe("luauui-composition-dump/1")
	end)
end)

-- ===== 5. mounted, through the real path ===================================

local function box(id: string, w: number, h: number): any
	return UI.Box({ id = id, width = { type = "fixed", px = w }, height = { type = "fixed", px = h } })
end

local function hudScreen(): any
	return UI.Screen({
		id = "S",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.Composition({
				id = "H",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				groups = composition.HUD_GROUPS,
				arrangements = { composition.HUD },
				children = {
					UI.Region({ id = "Chrome", group = "topLeft", rank = 1, children = { box("ChromeA", 180, 40) } }),
					UI.Region({
						id = "Tasks",
						group = "left",
						rank = 8,
						mayDrop = true,
						children = { box("TasksA", 220, 180), box("TasksB", 220, 90) },
					}),
					UI.Region({ id = "Timer", group = "top", rank = 2, children = { box("TimerA", 120, 48) } }),
					UI.Region({
						id = "Rail",
						group = "topRight",
						rank = 3,
						children = { box("RailA", 160, 200), box("RailB", 160, 96) },
					}),
					UI.Region({
						id = "Actions",
						group = "bottomRight",
						rank = 4,
						children = { box("ActionsA", 140, 160), box("ActionsB", 140, 80) },
					}),
				},
			}),
		},
	})
end

describe("ADR-0025: a mounted HUD loses 200px of height", function()
	it("re-solves in place: the zones stay pinned and nothing overlaps", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 500 })
		local root = mountLib.mount(core, hudScreen())
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()

		local tall = controller.compositionAt("/S/H")
		expect(tall.arrangement).toBe("hud")
		local railTall = adapter.node("/S/H/Rail").rect

		local creates = controller.stats().creates
		-- the URL bar opens: same width, 200px less height
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 300 })
		controller.refresh()

		local short = controller.compositionAt("/S/H")
		expect(short.arrangement).toBe("hud")
		-- an arrange pass, not a rebuild (ADR-0023 Decision 4)
		expect(controller.stats().creates).toBe(creates)
		expect(controller.stats().removes).toBe(0)

		-- the right column is still the right column
		local railShort = adapter.node("/S/H/Rail").rect
		expect(railShort.x).toBe(railTall.x)
		expect(railShort.y).toBe(0)
		-- ...and the bottom cluster is still on the bottom edge
		local actions = adapter.node("/S/H/Actions").rect
		expect(actions.y + actions.h).toBe(300)
		-- ...and the two right-column zones do not touch
		local dx, dy = intersects(railShort, actions)
		expect(dx).toBe(0)
		expect(dy).toBe(0)
	end)

	it("the solver files a NAMED finding when one zone paints over another", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 500 })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.Composition({
						id = "H",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						groups = composition.HUD_GROUPS,
						arrangements = { composition.HUD },
						children = {
							-- 300px of content in a 200px column
							UI.Region({
								id = "Wide",
								group = "topLeft",
								rank = 1,
								children = { box("WideA", 300, 40) },
							}),
							UI.Region({ id = "Timer", group = "top", rank = 2, children = { box("TimerA", 120, 48) } }),
						},
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()

		local found = nil
		for _, d in controller.diagnostics() do
			if string.find(d.issue, "paints over region", 1, true) ~= nil then
				found = d
			end
		end
		expect(found ~= nil).toBe(true)
		expect(string.find((found :: any).issue, "Wide", 1, true) ~= nil).toBe(true)
		expect(string.find((found :: any).issue, "Timer", 1, true) ~= nil).toBe(true)
		-- the OFFENDER is named first, and the finding is filed on it
		expect(string.find((found :: any).issue, "region '/S/H/Wide' paints over", 1, true) ~= nil).toBe(true)
		expect((found :: any).node).toBe("/S/H/Wide")
		expect((found :: any).designed).toBe(nil)
	end)
end)

-- ===== 6. the platform's own controls are NEVER painted on (ADR-0027) =======
--
-- THE COMMISSIONING CASE, again from the director (2026-08-14): a shipped Roblox
-- FPS whose HUD collapses into Roblox's own chrome when a browser URL bar shrinks
-- the viewport. The framework's answer was already safe — `deviceSafeContent`
-- insets by the per-edge MAX of the core and device insets, so the whole 58px top
-- band was spent — but NOTHING ASSERTED IT, and an unasserted guarantee is a
-- guarantee until someone looks.
--
-- It is asserted here, and asserted against the fact rather than a number: the
-- rects the platform's own controls occupy are `platformChrome.rects`, and the
-- oracle is EVERY PAINTED NODE of the SHIPPED showcase fixture — not a lookalike
-- built in this file, and not the composition's own idea of where it put things.
-- A pure layout container is skipped (the target reports the live adapter's own
-- elision verdict: it paints nothing), which is what lets the topbar ROW span the
-- full width while its content starts at the free band's edge.
--
-- The profiles are driven facts, never this machine's: `deviceSafeInsets` reads 0
-- in Studio and non-zero on a notched phone, so a check that trusted the local
-- environment would pass everywhere and prove nothing.

describe("ADR-0027: nothing the HUD paints lands on the platform's own controls", function()
	local LuauUI = require("../src") :: any
	local hudScenario = require("../examples/gallery/scenarios/hud")

	-- verbatim from the live engine where marked; the rest are the device classes
	-- the matrix already models. `bar` is `GuiService.TopbarInset` in window space.
	local PROFILES = {
		{
			id = "studio live 735x413 (measured 2026-08-14)",
			vp = { w = 735, h = 413 },
			core = { top = 58, bottom = 0, left = 0, right = 0 },
			device = { top = 0, bottom = 0, left = 0, right = 0 },
			topbarSafe = { top = 0, bottom = 355, left = 164, right = 0 },
			bar = { x = 164, y = 0, w = 571, h = 58 },
		},
		{
			-- THE DIRECTOR'S SCREENSHOT: the browser URL bar takes 200px of height
			-- and the same facts describe a 213px-tall window
			id = "the same window with a URL bar open (735x213)",
			vp = { w = 735, h = 213 },
			core = { top = 58, bottom = 0, left = 0, right = 0 },
			device = { top = 0, bottom = 0, left = 0, right = 0 },
			topbarSafe = { top = 0, bottom = 155, left = 164, right = 0 },
			bar = { x = 164, y = 0, w = 571, h = 58 },
		},
		{
			id = "notched landscape phone (812x375, notch 47 + home 21)",
			vp = { w = 812, h = 375 },
			core = { top = 58, bottom = 0, left = 59, right = 59 },
			device = { top = 0, bottom = 21, left = 47, right = 47 },
			topbarSafe = { top = 0, bottom = 317, left = 273, right = 59 },
			bar = { x = 273, y = 0, w = 480, h = 58 },
		},
		{
			id = "narrow portrait phone (320x640) — the cluster is HALF the width",
			vp = { w = 320, h = 640 },
			core = { top = 58, bottom = 0, left = 0, right = 0 },
			device = { top = 0, bottom = 0, left = 0, right = 0 },
			topbarSafe = { top = 0, bottom = 582, left = 164, right = 0 },
			bar = { x = 164, y = 0, w = 156, h = 58 },
		},
		{
			-- an engine without `GetInsetArea`: no topbar facts at all, so the whole
			-- band is the platform's and there is nothing to ride
			id = "an engine that reports NO strip",
			vp = { w = 1280, h = 720 },
			core = { top = 58, bottom = 0, left = 0, right = 0 },
			device = { top = 0, bottom = 0, left = 0, right = 0 },
			topbarSafe = { top = 0, bottom = 0, left = 0, right = 0 },
			bar = { x = 0, y = 0, w = 0, h = 0 },
			-- ...and the fixture must not MODEL one either: it states a platform
			-- strip when the platform reports none, so the headless sweep exercises
			-- the mechanism. This flag is how the other platform is driven.
			noStrip = true,
		},
	}

	local function drive(profile: any): any
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = profile.vp.w, h = profile.vp.h })
		env:set("coreSafeInsets", profile.core)
		env:set("deviceSafeInsets", profile.device)
		env:set("topbarSafeInsets", profile.topbarSafe)
		env:set("topbarInset", profile.bar)
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, system)
		local built = hudScenario.build({
			LuauUI = LuauUI,
			core = core,
			env = env,
			adapter = adapter,
			presenter = presenter,
			actionSystem = system,
			record = function() end,
			flags = { noTopbarStrip = profile.noStrip == true },
		})
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		return {
			env = env,
			adapter = adapter,
			built = built,
			handle = handle,
			refresh = function()
				presenter.refresh()
			end,
			dispose = function()
				built.dispose()
			end,
		}
	end

	--[[ WHAT COUNTS AS "PAINTS". A container may legitimately SPAN the platform's
		band — the topbar row is full-width by definition, and so is the surface it
		is in; what must never happen is something DRAWN there. So a node is checked
		unless it is a pure structural box: one the target elides outright (the live
		adapter's own verdict — it gives a layout container a handle and no engine
		object), or one of the classes that only ever carries children. Those are
		skipped ONLY while they carry no decoration, so a Screen with a backdrop or a
		Region with a plate is still checked and the exemption cannot become a hole. ]]
	local STRUCTURAL: { [string]: boolean } =
		{ Screen = true, Composition = true, Region = true, When = true, ForEach = true, ViewThatFits = true }

	-- every node the adapter would actually PAINT, against every rect the platform
	-- keeps for itself. The failure names both boxes, because "which node" and
	-- "which rect" are two different bugs.
	local function assertClearsChrome(w: any, where: string, minPainted: number)
		local chrome = w.env:get("platformChrome"):get()
		expect(#chrome.rects > 0).toBe(true) -- a check with nothing to check is decoration
		local checked = 0
		for _, path in w.adapter.paths() do
			local node = w.adapter.node(path)
			local rect = if node ~= nil then node.rect else nil
			if rect == nil or node.elided == true or rect.w <= 0 or rect.h <= 0 then
				continue
			end
			--[[ ...AND A HIDDEN NODE PAINTS NOTHING (hole found 2026-08-14, closed
				rather than tolerated). A DROPPED region keeps its mount and gets a
				zero rect plus the hidden mark — solver.luau, "it keeps its MOUNT (an
				offer change must not rebuild it)" — and the adapter writes
				`Visible = false` down that whole subtree. Its descendants' RECTS are
				not all zero, though: a child with a fixed extent (a themed dot, a
				badge's padding) keeps the box it was given, so this loop was reading
				boxes for content the player cannot see and calling them painted.

				It never fired before because every droppable region in the earlier
				HUD held nothing but Text, and a Text in a zero-width box measures
				zero width and was skipped by the line above — i.e. the check was
				passing by a property of the fixture rather than by anything it
				asserts. This is the check's own stated contract ("every node the
				adapter would actually PAINT"), applied; and it cannot become a hole,
				because `checked` — the floor that proves the HUD rendered at all —
				now counts only the nodes that are really on screen. ]]
			if w.adapter.visibleOf(path) == false then
				continue
			end
			if STRUCTURAL[node.class] and node.decorationHint == nil then
				continue
			end
			checked += 1
			for _, r in chrome.rects do
				local dx, dy = intersects(rect, r)
				if dx > 0 then
					error(
						`{where}: '{path}' [box {rect.w}x{rect.h} at {rect.x},{rect.y}] paints {dx}x{dy}px into `
							.. `the platform's own controls [rect {r.w}x{r.h} at {r.x},{r.y}]`,
						0
					)
				end
			end
		end
		-- ...and the check saw a HUD, not an empty adapter: the whole failure class
		-- this file exists for is a check that proves nothing
		if checked < minPainted then
			error(`{where}: only {checked} painted node(s) were checked — this HUD did not render`, 0)
		end
	end

	for _, profile in PROFILES do
		it(`clears the chrome on {profile.id}, riding the strip and not`, function()
			local w = drive(profile)
			assertClearsChrome(w, `{profile.id} (riding)`, 10)
			-- ...and with the URL bar open, which is the state the screenshot caught
			w.built.steps.openUrlBar()
			w.refresh()
			-- a window with 13px of HUD left still paints its reserved row and its
			-- top-ranked buttons; the floor is here so a surface that VANISHED could
			-- never be mistaken for one that cleared the chrome
			assertClearsChrome(w, `{profile.id} (riding, URL bar open)`, 5)
			-- ...and on the rung that does NOT ride the band, which is what every
			-- platform reporting no strip gets
			w.built.steps.leaveStrip()
			w.refresh()
			assertClearsChrome(w, `{profile.id} (not riding, URL bar open)`, 5)
			w.built.steps.closeUrlBar()
			w.refresh()
			assertClearsChrome(w, `{profile.id} (not riding)`, 10)
			w.dispose()
		end)
	end

	it("...and it is USING the strip: the objective chip is level with Roblox's own buttons", function()
		local w = drive(PROFILES[1])
		local chrome = w.env:get("platformChrome"):get()
		local band = chrome.band
		expect(band ~= nil).toBe(true)
		local chip = w.adapter.node("/HudScreen/Hud/Strip/StripRow/StripFree/StripChip/then/StripFit/Objective")
		expect(chip ~= nil).toBe(true)
		local rect = (chip :: any).rect
		-- INSIDE the platform's own band, vertically — this is the "aligned with the
		-- controls" half, and it is what a full-width top inset made impossible
		expect(rect.y >= band.y).toBe(true)
		expect(rect.y + rect.h <= band.y + band.h).toBe(true)
		-- ...and to the RIGHT of the cluster, which is the "never overlapping" half
		expect(rect.x >= band.x).toBe(true)
		expect(rect.x + rect.w <= band.x + band.w).toBe(true)
		-- ...centred in the FREE BAND, not in the window. On a wide screen those two
		-- are far enough apart to tell apart and close enough that only this
		-- assertion does: a row that ignored the cluster entirely would still clear
		-- it here, and would be over it on a phone.
		local centre = rect.x + rect.w / 2
		expect(math.abs(centre - (band.x + band.w / 2)) <= 1).toBe(true)
		expect(math.abs(centre - 735 / 2) > 1).toBe(true)
		-- the nine anchored zones are all below the band, by construction: the row
		-- is a span, so the lanes start under it
		local rounds = w.adapter.node("/HudScreen/Hud/Rounds")
		expect((rounds :: any).rect.y >= band.y + band.h).toBe(true)
		w.dispose()
	end)

	--[[ THE HUD IS BUILT FROM REAL CONTROLS, NOT FROM TEXT DRESSED AS THEM
		(director round 2026-08-14: *"for the showcase based on rivals, let's make
		it pretty conceptually similar to rivals"*).

		The redesign's whole risk is silent regression to the thing it replaced: a
		HUD of text pills passes every geometric check in this file, because a pill
		and a round button occupy boxes just the same. So the shape is pinned by
		what each piece IS and by whether it MOVES — a ring that is not bound to the
		round clock is a picture of a timer, which is exactly the "painted at a size
		nobody measured" family read from the paint end. ]]
	it("the timer is a live ring, the health bar is bound, and the buttons are icon discs", function()
		local w = drive(PROFILES[1])
		local RING = "/HudScreen/Hud/Clock/ClockStack/TimerPod/TimerRow/TimerRingBox/TimerRing/Ring/Arc"
		local arc = w.adapter.node(RING)
		expect(`the timer's arc is a {if arc == nil then "MISSING node" else arc.class}`).toBe(
			"the timer's arc is a Path"
		)
		-- SQUARE, and from the THEME's own ring metric rather than an authored box
		local ring = (
			w.adapter.node("/HudScreen/Hud/Clock/ClockStack/TimerPod/TimerRow/TimerRingBox/TimerRing/Ring") :: any
		).rect
		expect(`the ring is {ring.w}x{ring.h}`).toBe(`the ring is {ring.w}x{ring.w}`)
		-- ...AND IT IS BOUND: driving the round clock moves the arc's sweep. A
		-- fixed picture of a ring would pass every line above this one.
		local function sweepOf(): number
			local pts = (w.adapter.node(RING) :: any).props.points
			local function angle(p: any): number
				return (math.deg(math.atan2(p.x - 0.5, 0.5 - p.y)) + 360) % 360
			end
			return (angle(pts[#pts]) - angle(pts[1]) + 360) % 360
		end
		local before = sweepOf()
		local step = w.built.steps.tickRound()
		w.refresh()
		expect(`the round clock moved: {sweepOf() ~= before}`).toBe("the round clock moved: true")
		expect(`...and reports its own fraction: {type(step.fraction)}`).toBe("...and reports its own fraction: number")
		-- the health bar is a real ProgressView, and its FILL follows the signal
		local fillPath = "/HudScreen/Hud/Health/HealthPod/HealthRow/HealthBarBox/HealthBar/Bar/Fill"
		local fillBefore = (w.adapter.node(fillPath) :: any).rect.w
		w.built.steps.takeDamage()
		w.refresh()
		expect(`the health fill shrank: {(w.adapter.node(fillPath) :: any).rect.w < fillBefore}`).toBe(
			"the health fill shrank: true"
		)
		-- the two clusters are ICON DISCS: circle Buttons carrying a semantic icon
		-- name, never an asset, and square by construction
		for _, entry in
			{ { "/HudScreen/Hud/Rounds/RoundStrip/R1", "menu" }, { "/HudScreen/Hud/Actions/ActionsCol/A1", "more" } }
		do
			local node = w.adapter.node(entry[1]) :: any
			expect(`{entry[1]} is a {if node == nil then "MISSING node" else node.class}`).toBe(
				`{entry[1]} is a Button`
			)
			expect(`{entry[1]} shape={tostring(node.props.shape)} icon={tostring(node.props.icon)}`).toBe(
				`{entry[1]} shape=circle icon={entry[2]}`
			)
			expect(`{entry[1]} is {node.rect.w}x{node.rect.h}`).toBe(`{entry[1]} is {node.rect.w}x{node.rect.w}`)
		end
		-- ...and the thumb cluster is the LARGER one: a bottom-right action is what
		-- a thumb reaches for and a top-left chip is not
		local big = (w.adapter.node("/HudScreen/Hud/Actions/ActionsCol/A1") :: any).rect.w
		local small = (w.adapter.node("/HudScreen/Hud/Rounds/RoundStrip/R1") :: any).rect.w
		expect(`thumb disc {big} > chip disc {small}: {big > small}`).toBe(`thumb disc {big} > chip disc {small}: true`)
		w.dispose()
	end)

	--[[ THE STUDIO'S STANDING LOCALIZATION RULE, ON A HUD.
		`docs/lessons/localization-safe-ui-text.md`: all player copy must survive a
		~1.4x expansion, fitting and wrapping, never clipping. A HUD is the hardest
		case for it — every zone is a third of a lane and half of them are one line
		— and the always-on sweep deliberately does NOT cover this axis (it sweeps
		one locale; see its header). So it is asked here, on the surface, through
		the fixture's own exported `copy` table: the module table is shared, so this
		expands the REAL strings rather than a parallel copy of them. ]]
	it("every string on the HUD survives a 1.4x pseudo-localization", function()
		local l10n = require("./fixtures/a11y_l10n_fixtures")
		local original: { [string]: string } = {}
		for key, value in hudScenario.copy do
			original[key] = value
			hudScenario.copy[key] = l10n.pseudoLocalize(value)
		end
		local ok, err = pcall(function()
			for _, profile in PROFILES do
				local w = drive(profile)
				for _, state in { "rest", "urlBar" } do
					if state == "urlBar" then
						w.built.steps.openUrlBar()
						w.refresh()
					end
					local findings = w.handle.controller.diagnostics()
					if #findings > 0 then
						local lines: { string } = {}
						for _, f in findings do
							table.insert(lines, `  {f.node}: {f.issue}`)
						end
						error(
							`{profile.id} ({state}), pseudo-localized: {#findings} diagnostic(s)\n`
								.. table.concat(lines, "\n"),
							0
						)
					end
				end
				w.dispose()
			end
		end)
		for key, value in original do
			hudScenario.copy[key] = value
		end
		expect(`restored: {hudScenario.copy.timer}`).toBe("restored: 2:14")
		if not ok then
			error(err, 0)
		end
	end)

	it("the rung with no strip is EXACTLY what deviceSafeContent applied: the top band is spent whole", function()
		local w = drive(PROFILES[5])
		local chrome = w.env:get("platformChrome"):get()
		expect(chrome.band).toBe(nil)
		local rounds = w.adapter.node("/HudScreen/Hud/Rounds")
		expect((rounds :: any).rect.y).toBe(chrome.insets.top)
		w.dispose()
	end)
end)
