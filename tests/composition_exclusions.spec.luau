--!strict
--[[ PER-LANE EXCLUSIONS — reserving around a host's own chrome (framework-gaps §8).

	THE HOLE THIS CLOSES, in the audit's own words: *"A `Composition`'s lane band is
	one rectangle, so a host's own chrome row (covering some columns and not others)
	cannot be reserved around declaratively. `hud.luau` spends ~150 lines plus a
	sampled monotone latch and a hand-built `reachEpoch` dependency token doing it —
	and records that leaving the platform insets out of that token latched a wrong
	answer for a whole epoch on a real device."* `src/env/environment.luau` documents
	the punt in as many words: *"which is what lets a consumer reserve around it per
	column."*

	THE RULE IS A MEASUREMENT, NOT A COVERAGE FRACTION, and the three fractions that
	were tried are each wrong on a case this repository has recorded:

	  · ANY OVERLAP pushes the centre column down at 749x380 for 17px the centred
	    clock never comes near — the director's own round-2 refusal;
	  · MAJORITY misses a 46%-covered right column whose `end`-anchored rail is
	    inside the chrome row (measured at 360x691 under fantasy-ornate: 28px of
	    overlap, the director's photograph to the pixel);
	  · THE ANCHOR POINT misses that one too, and already failed once on a padded
	    left column's start edge.

	Every one of them is a guess about the WIDTH OF THE CONTENT, and the content's
	width is a thing the composition MEASURES. So the four cases below are the three
	shapes those rules each got wrong, plus the additivity control.

	AND THERE IS NO LATCH. The consumer needed an epoch token and a monotone latch
	because it was sampling SOLVED rects back through the geometry feedback seam;
	inside one `resolve` the lane rects and the exclusion are in scope at the same
	moment, so the answer is decided once, from the richest forms, and the settled
	tree equals a fresh mount by construction rather than by convergence.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local composition = require("../src/layout/composition")

--[[ THE MEASURED SHAPE, from the DIR-2 reproduction: three 250px columns at
	749x380 with the showcase's chip row declared, and a 360x691 portrait whose
	right column is 46% covered. Widths are what each zone measures at its richest
	form — the fact the rule reads. ]]
local SIZES: { [string]: { { w: number, h: number } } } = {
	Rounds = { { w = 80, h = 36 } }, -- left column, start-anchored
	Clock = { { w = 80, h = 30 } }, -- centre column, centred
	Rail = { { w = 80, h = 60 } }, -- right column, end-anchored
}

local CTX = { measure = function(id: string, form: number, _w: number, _h: number): (number, number)
	local list = SIZES[id]
	local s = list[math.min(form, #list)]
	return s.w, s.h
end }

local REGIONS = {
	{ id = "Rounds", group = "topLeft", rank = 1, forms = 1 },
	{ id = "Clock", group = "top", rank = 2, forms = 1 },
	{ id = "Rail", group = "topRight", rank = 3, forms = 1 },
}

local function hud(): any
	return { groups = composition.HUD_GROUPS, arrangements = { composition.HUD }, regions = REGIONS }
end

local function resolveWith(offer: any, exclusions: { any }?): any
	local ctx = table.clone(CTX) :: any
	ctx.exclusions = exclusions
	return composition.resolve(hud(), offer, ctx)
end

local function laneY(r: any, index: number): number
	return r.lanes[index].rect.y
end

describe("§8: a lane starts below an exclusion its own CONTENT reaches into", function()
	it("the covered column gives way and the columns beside it stay LEVEL with the chrome", function()
		--[[ 750 wide, three 250px columns. The chrome row runs x 8..267 — 97% of the
			left column, 7% of the centre one. `Rounds` is start-anchored at x 0..80
			and is inside it; the centred `Clock` measures 80 in a 250px column, so it
			sits at x 335..415 and no y the chrome could take would touch it. ]]
		local r = resolveWith({ w = 750, h = 400 }, { { x = 8, y = 0, w = 259, h = 62 } })
		expect(laneY(r, 1)).toBe(62)
		expect(laneY(r, 2)).toBe(0)
		expect(laneY(r, 3)).toBe(0)
		expect(r.lanes[1].exclusion).toBe(62)
		expect(r.lanes[2].exclusion).toBe(nil)
	end)

	it("a column the chrome BARELY clips still gives way when its content reaches in", function()
		--[[ THE CASE A MAJORITY RULE MISSES, and it is the director's photograph:
			360 wide, three 120px columns, a 282px chip row. The right column runs
			x 240..360 and is 42px covered — 35%, so every fraction rule leaves it
			level — while `Rail` is `end`-anchored and 80 wide, so it solves at
			x 280..360 against a row ending at 282. Two pixels of overlap is a rail
			painted on the app's own chrome. ]]
		local r = resolveWith({ w = 360, h = 600 }, { { x = 0, y = 0, w = 282, h = 62 } })
		expect(laneY(r, 3)).toBe(62)
		expect(r.lanes[3].exclusion).toBe(62)
	end)

	it("...and a column whose content clears the chrome entirely stays where it was", function()
		-- CONTROL for the case above: narrow the row until the rail is clear again
		local r = resolveWith({ w = 360, h = 600 }, { { x = 0, y = 0, w = 270, h = 62 } })
		expect(laneY(r, 3)).toBe(0)
		expect(r.lanes[3].exclusion).toBe(nil)
	end)

	it("the LOWEST exclusion a lane meets wins — two rows are not two reservations", function()
		local r = resolveWith(
			{ w = 750, h = 400 },
			{ { x = 0, y = 0, w = 100, h = 40 }, { x = 0, y = 40, w = 100, h = 30 } }
		)
		expect(laneY(r, 1)).toBe(70)
	end)

	it("a lane that gives way is SHORTER by exactly what it gave, so its content still fits its box", function()
		local r = resolveWith({ w = 750, h = 400 }, { { x = 8, y = 0, w = 259, h = 62 } })
		expect(r.lanes[1].rect.y + r.lanes[1].rect.h).toBe(400)
		expect(r.lanes[1].rect.h).toBe(400 - 62)
		-- ...and the zone inside it is inside its lane
		local rounds = r.regionById.Rounds
		expect(rounds.rect.y >= r.lanes[1].rect.y).toBe(true)
	end)

	it("ADDITIVITY: declaring none is byte-identical to the composition that never heard of them", function()
		local without = composition.resolve(hud(), { w = 750, h = 400 }, CTX)
		local with = resolveWith({ w = 750, h = 400 }, {})
		expect(composition.dump(with)).toEqual(composition.dump(without))
		for _, lane in without.lanes do
			expect(lane.exclusion).toBe(nil)
		end
	end)

	it("a malformed rect is SKIPPED, not clamped — a zero-width rect excludes nothing", function()
		local r = resolveWith(
			{ w = 750, h = 400 },
			{ { x = 0, y = 0, w = 0, h = 62 }, { x = 0, y = 0, w = 100, h = 0 }, "not a rect" :: any }
		)
		expect(laneY(r, 1)).toBe(0)
	end)
end)

describe("§8: the decision is a FIXED POINT, so no latch is needed", function()
	it("re-resolving the same declaration twice lands on the same answer", function()
		--[[ THE 2-CYCLE THE CONSUMER'S LATCH EXISTED TO BOUND: the reservation shrinks
			the lane's budget, the budget steps a zone down to a narrower form, the
			narrower form no longer reaches the chrome, the reservation goes away, the
			richer form comes back. The rule reads the RICHEST forms once, so the
			second resolve of the same inputs is the first one's answer. ]]
		local a = resolveWith({ w = 750, h = 120 }, { { x = 8, y = 0, w = 259, h = 62 } })
		local b = resolveWith({ w = 750, h = 120 }, { { x = 8, y = 0, w = 259, h = 62 } })
		expect(composition.dump(a)).toEqual(composition.dump(b))
	end)

	it("...and a lane squeezed past its floor still holds the exclusion rather than buying it back", function()
		--[[ THE PURCHASE THE LADDER MUST NOT MAKE: dropping an exclusion buys pixels
			that are not the composition's to spend — they are occupied by somebody
			else's chrome. Rule 3's own principle, one level out. ]]
		local r = resolveWith({ w = 750, h = 80 }, { { x = 8, y = 0, w = 259, h = 62 } })
		expect(laneY(r, 1)).toBe(62)
	end)
end)

--[[ ── AND THE PUBLIC HALF: `UI.Composition{ exclusions }` ────────────────────
	The rules above are the PURE decision, driven with a plain table. These two
	drive the same decision through the mounted path — a Readable of window-space
	rects on the declaration, which is where a consumer's own chrome row actually
	lives (it publishes the same rects into `appChromeRects` for the platform fact
	to merge). WINDOW space is the point: it is the space `platformChrome.rects` is
	stated in and the space the solver's own output rects are in, so a consumer
	never converts and never needs to know where its composition landed. ]]
describe("§8: `UI.Composition{ exclusions }` — the declaration, through the mounted path", function()
	local UI = require("../src/blueprint")
	local customFactory = require("../src/core/custom")
	local environment = require("../src/env/environment")
	local renderer = require("../src/render/renderer")
	local mountLib = require("../src/mount")
	local fake_target = require("./lib/fake_target")

	local function screen(exclusions: any): any
		local function zone(id: string, group: string, rank: number, w: number): any
			return UI.Region({
				id = id,
				group = group,
				rank = rank,
				children = {
					UI.Box({ id = id .. "Body", width = { type = "fixed", px = w }, height = { type = "fixed", px = 36 } }),
				},
			})
		end
		return UI.Screen({
			id = "S",
			children = {
				UI.Composition({
					id = "H",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					groups = composition.HUD_GROUPS,
					arrangements = { composition.HUD },
					exclusions = exclusions,
					children = { zone("Rounds", "topLeft", 1, 80), zone("Rail", "topRight", 2, 80) },
				}),
			},
		})
	end

	local function mount(exclusions: any): any
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 766, h = 400 })
		local root = mountLib.mount(core, screen(exclusions))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return { core = core, adapter = adapter, controller = controller }
	end

	it("a declared chrome row pushes only the lanes its own content reaches into", function()
		local w = mount({ { x = 0, y = 0, w = 259, h = 62 } })
		expect(w.adapter.node("/S/H/Rounds").rect.y).toBe(62)
		expect(w.adapter.node("/S/H/Rail").rect.y).toBe(0)
	end)

	it("it is REACTIVE: a chrome row that arrives after the first solve re-runs the pass", function()
		--[[ THE HALF THAT MADE THE CONSUMER BUILD A DEPENDENCY TOKEN BY HAND. A
			declared prop is a bound prop, so the framework's own observer invalidates
			the solve — there is no epoch to keep in sync and nothing to leave out of
			it. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 766, h = 400 })
		local rects = core:signal({})
		local root = mountLib.mount(core, screen(rects))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/H/Rounds").rect.y).toBe(0)
		rects:set({ { x = 0, y = 0, w = 259, h = 62 } })
		controller.refresh()
		expect(adapter.node("/S/H/Rounds").rect.y).toBe(62)
		-- ...and it settles where a FRESH mount of the same state lands, which is the
		-- property the consumer's monotone latch could not guarantee
		local fresh = mount({ { x = 0, y = 0, w = 259, h = 62 } })
		expect(adapter.node("/S/H/Rounds").rect.y).toBe(fresh.adapter.node("/S/H/Rounds").rect.y)
		expect(adapter.node("/S/H/Rail").rect.y).toBe(fresh.adapter.node("/S/H/Rail").rect.y)
	end)
end)
