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

local CTX = {
	measure = function(id: string, form: number, _w: number, _h: number): (number, number)
		local list = SIZES[id]
		local s = list[math.min(form, #list)]
		return s.w, s.h
	end,
}

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

--[[ ── AND THE OTHER END OF THE LANE THE EXCLUSION SHORTENED (ADR-0056) ───────
	THE BUG THESE PIN, in the director's words: *"screen-anchored HUD now overlaps
	at the bottom"* — reported twice, on a PS5 and on a phone
	(`artifacts/framework-gaps-phase2-fix4/item1-ps5-hud-overlap.png`, `overlap.png`),
	both with the showcase's chip row declared as `exclusions`.

	THE TERM. A lane that gives way starts at `laneBandY + inset` and its rect is
	`laneBudget - inset` tall — that half was right from the day §8 landed, and the
	case above ("shorter by exactly what it gave") pins it. What the PLACEMENT pass
	then shared out between the lane's groups was `laneBudget - laneNeed`: the
	slack of the lane the composition would have had if no chrome row existed. So
	every group in a shortened lane was pushed down by its share of one extra
	`inset`, and an `end`-placed group — `bottomLeft`/`bottom`/`bottomRight`, whose
	share is all of it — landed EXACTLY `inset` px past the bottom of its own lane.

	IT WAS SILENT, AND THAT IS THE SECOND HALF OF THE DEFECT. Rule 3's overflow
	arithmetic already subtracts the inset (`laneOver`), so a lane whose content
	does not FIT is caught; this content fitted and was merely put in the wrong
	place. The collision finding compares regions with each OTHER, never with their
	lane. So the composition returned `legal = true`, no rejection and no collision,
	while painting a region outside its box by the whole inset — measured LIVE at
	54px on the phone, 141px on the PS5, and 300px in the sweep case below — and
	`tests/lib/overflow_guard.luau`'s own header recorded the premise this
	falsifies: *"a LEGAL composition cannot produce one"*.

	The fix is one term: the slack a lane shares out is measured against the lane's
	OWN rect, which already carries the inset. `laneRect.h` is `laneBudget - inset`
	by construction, so the two halves cannot drift again. ]]
describe("§8: a lane that gave way is shorter at BOTH ends — the PS5/phone bottom overlap", function()
	local BOTTOM_SIZES: { [string]: { w: number, h: number } } = {
		Rounds = { w = 80, h = 36 },
		Health = { w = 120, h = 40 },
		Feed = { w = 200, h = 60 },
	}
	local BOTTOM_CTX = {
		measure = function(id: string, _f: number, _w: number, _h: number): (number, number)
			local s = BOTTOM_SIZES[id]
			return s.w, s.h
		end,
	}
	-- the shape of the reported screen: a top-anchored zone the chrome row pushes
	-- down, and the `bottomLeft` cluster (health, then the kill feed) under it
	local BOTTOM_REGIONS = {
		{ id = "Rounds", group = "topLeft", rank = 1, forms = 1 },
		{ id = "Health", group = "bottomLeft", rank = 2, forms = 1 },
		{ id = "Feed", group = "bottomLeft", rank = 3, forms = 1 },
	}

	local function bottomResolve(offer: any, exclusions: { any }?): any
		local ctx = table.clone(BOTTOM_CTX) :: any
		ctx.exclusions = exclusions
		return composition.resolve(
			{ groups = composition.HUD_GROUPS, arrangements = { composition.HUD }, regions = BOTTOM_REGIONS },
			offer,
			ctx
		)
	end

	local function laneBottom(r: any, i: number): number
		return r.lanes[i].rect.y + r.lanes[i].rect.h
	end

	it("the PS5 shape: the kill feed ends AT the lane's bottom edge, not past it", function()
		--[[ THE REPRODUCED REPORT. 1716x871 is the showcase HUD's own box on the PS5
			preset and 54 is the chip row's reach below what the HUD had already spent
			(`hud.luau`'s own `urlBarPx` computes the same 54 as `reserved`). Before the
			fix `Feed` ended at 925 — 54 past a lane that ends at 871. ]]
		local r = bottomResolve({ w = 1716, h = 871 }, { { x = 0, y = 0, w = 1716, h = 54 } })
		expect(r.lanes[1].exclusion).toBe(54)
		expect(laneBottom(r, 1)).toBe(871)
		local feed = r.regionById.Feed
		expect(feed.rect.y + feed.rect.h).toBe(871)
		-- ...and the cluster above it is inside the lane too
		local health = r.regionById.Health
		expect(health.rect.y >= r.lanes[1].rect.y).toBe(true)
		expect(health.rect.y + health.rect.h <= laneBottom(r, 1)).toBe(true)
	end)

	it("...and the PHONE shape is the same term, not a second bug", function()
		--[[ THE DIRECTOR'S `overlap.png`: a phone, the showcase's "Topbar strip"
			toggle on, the feed line over the caption. Same declaration, one third the
			box, and the overshoot tracks the chip row rather than the viewport —
			which is what makes it the same mechanism and not a coincidence. ]]
		local r = bottomResolve({ w = 320, h = 512 }, { { x = 0, y = 0, w = 320, h = 44 } })
		expect(r.lanes[1].exclusion).toBe(44)
		expect(laneBottom(r, 1)).toBe(512)
		local feed = r.regionById.Feed
		expect(feed.rect.y + feed.rect.h).toBe(512)
	end)

	it("the displacement was EXACTLY the inset, so it is gone at EVERY inset", function()
		--[[ THE TERM IDENTIFIED BY MEASUREMENT, not by reading. Before the fix the
			overshoot was 1:1 with the exclusion's reach — 1px of chrome moved the feed
			1px out, 300px moved it 300 — which is what named `laneBudget` (the lane
			before it gave way) as the wrong operand rather than a rounding step or a
			gap. Sweeping the term is what stops a fix that happens to be right at 54. ]]
		for _, h in { 1, 20, 54, 69, 141, 300 } do
			local r = bottomResolve({ w = 1716, h = 871 }, { { x = 0, y = 0, w = 1716, h = h } })
			expect(r.lanes[1].exclusion).toBe(h)
			local feed = r.regionById.Feed
			expect(feed.rect.y + feed.rect.h - laneBottom(r, 1)).toBe(0)
		end
	end)

	it("a `fill` group in a shortened lane is shortened, not merely moved", function()
		--[[ THE SECOND READER OF THE SAME SLACK. `place` shares it out between hug
			groups; `sizing = "fill"` hands it to the group as HEIGHT. Both were reading
			the pre-exclusion budget, so a fill group's rect ran `inset` px past its
			lane too — a different symptom of one term, and a case the HUD preset cannot
			reach (its own `fill` column group holds no regions). ]]
		local decl = {
			groups = {
				{ id = "top", lane = "main", place = "start" },
				{ id = "body", lane = "main", sizing = "fill", holdsLane = true },
			},
			arrangements = { { name = "one", lanes = { { "main" } } } },
			regions = {
				{ id = "Rounds", group = "top", rank = 1, forms = 1 },
				{ id = "Feed", group = "body", rank = 2, forms = 1 },
			},
		}
		local ctx = table.clone(BOTTOM_CTX) :: any
		ctx.exclusions = { { x = 0, y = 0, w = 1716, h = 141 } }
		local r = composition.resolve(decl :: any, { w = 1716, h = 871 }, ctx)
		local body
		for _, g in r.groups do
			if g.id == "body" then
				body = g
			end
		end
		expect(r.lanes[1].exclusion).toBe(141)
		expect(body.rect.y + body.rect.h).toBe(laneBottom(r, 1))
	end)

	it("A SHORTENED LANE PLACES LIKE A SHORT LANE — the invariant, for every `place`", function()
		--[[ THE GENERAL STATEMENT OF THE FIX, and the strongest one available: after
			giving way, a lane is a rect like any other, so it must place its groups
			exactly as an unshortened lane of the SAME HEIGHT does — offset by where it
			starts and by nothing else. `end` is the reported bug; `center` is the same
			term at half strength (a centred group used to sit half an inset low); the
			trio together is what makes this a rule rather than three patches. ]]
		local function decl(place: string): any
			return {
				groups = {
					{ id = "top", lane = "main", place = "start" },
					{ id = "mid", lane = "main", place = place },
				},
				arrangements = { { name = "one", lanes = { { "main" } } } },
				regions = {
					{ id = "Rounds", group = "top", rank = 1, forms = 1 },
					{ id = "Feed", group = "mid", rank = 2, forms = 1 },
				},
			}
		end
		for _, place in { "start", "center", "end" } do
			for _, inset in { 54, 141 } do
				local pushed = table.clone(BOTTOM_CTX) :: any
				pushed.exclusions = { { x = 0, y = 0, w = 1716, h = inset } }
				local a = composition.resolve(decl(place), { w = 1716, h = 871 }, pushed)
				-- the same lane HEIGHT, reached without an exclusion at all
				local b =
					composition.resolve(decl(place), { w = 1716, h = 871 - inset }, table.clone(BOTTOM_CTX) :: any)
				expect(a.lanes[1].rect.h).toBe(b.lanes[1].rect.h)
				expect(a.lanes[1].rect.y - b.lanes[1].rect.y).toBe(inset)
				expect(a.regionById.Feed.rect.y - b.regionById.Feed.rect.y).toBe(inset)
				expect(a.regionById.Feed.rect.h).toBe(b.regionById.Feed.rect.h)
			end
		end
	end)

	it("the solver was SILENT while it happened — and now has nothing to say", function()
		--[[ WHY THE FRAMEWORK'S OWN OVERFLOW MACHINERY MISSED A 300px ESCAPE, pinned
			so the answer cannot rot into a guess: the content FIT. `laneOver` compares
			need against `laneBudget - laneInset` and this need is far under it, so no
			arrangement is rejected and no form steps down; the collision finding needs
			a region measuring bigger than its allotment and every one of these measured
			exactly its own. Nothing in the resolution compared a placed rect against
			the LANE rect it was placed into. The assertions below are the two halves
			together: legal, AND contained. ]]
		local r = bottomResolve({ w = 1716, h = 871 }, { { x = 0, y = 0, w = 1716, h = 300 } })
		expect(r.legal).toBe(true)
		expect(r.fallback).toBe(false)
		expect(#r.collisions).toBe(0)
		expect(#r.rejected).toBe(0)
		for _, g in r.groups do
			if g.lane ~= nil then
				local lane = r.lanes[g.lane]
				expect(g.rect.y >= lane.rect.y - 0.5).toBe(true)
				expect(g.rect.y + g.rect.h <= lane.rect.y + lane.rect.h + 0.5).toBe(true)
			end
		end
	end)

	it("INVARIANCE, over a MATRIX: a declaration that reaches no exclusion dumps byte for byte", function()
		--[[ THE HONEST MECHANICAL GUARD for "nothing without a chrome row moved"
			(review finding I-5). The first version of this round cited
			`check_flat_baseline` for that claim; that gate renders eight fixtures and
			not one of them contains a `UI.Composition`, so its PASS is structurally
			incapable of observing this change in either direction — the exact
			"pin that cannot reach the mechanism" failure this round exists to condemn,
			committed by the round itself.

			This is the guard that can reach it: every combination of lane count,
			`place` and `sizing` this ADR moves, each resolved three ways — with no
			`exclusions` key at all, with a far-away 1x1 rect, and with a rect that
			shares no x range with any content — and the three dumps compared BY VALUE.
			Deterministic enumeration rather than a fuzzer: no seed, no clock, and the
			failure names the exact cell.

			WHY THE THREE ARMS ARE DIFFERENT QUESTIONS. "No key" is the pre-feature
			path. "A far-away rect" is the arm FIX-4 used as its discriminator (the
			overflow scaled with the rect's reach, not its presence). "A
			non-intersecting rect" is the one that exercises §8's own decision — the
			rule runs, measures every region's x range, and decides NOT to give way —
			so a fix that accidentally made every declared rect an inset would be
			caught here and nowhere else. ]]
		local PLACES = { "start", "center", "end", 0.25, 0.66 }
		local SIZINGS = { "hug", "fill" }
		-- a stable serialization, keys sorted, so "byte for byte" is a string compare
		-- a failure can PRINT rather than a structural walk that only says "differs"
		local function ser(v: any): string
			if type(v) ~= "table" then
				return tostring(v)
			end
			local keys: { string } = {}
			for k in v do
				table.insert(keys, tostring(k))
			end
			table.sort(keys)
			local parts: { string } = {}
			for _, k in keys do
				local raw = (v :: any)[k]
				if raw == nil then
					raw = (v :: any)[tonumber(k) :: any]
				end
				table.insert(parts, `{k}={ser(raw)}`)
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		local mismatches: { string } = {}
		for _, lanes in { 1, 2, 3 } do
			for _, place in PLACES do
				for _, sizing in SIZINGS do
					local groups: { any } = {}
					local regions: { any } = {}
					local laneNames = { "lead", "main", "trail" }
					for i = 1, lanes do
						table.insert(groups, { id = `top{i}`, lane = laneNames[i], place = "start" })
						table.insert(groups, { id = `body{i}`, lane = laneNames[i], place = place, sizing = sizing })
						table.insert(regions, { id = `Rounds{i}`, group = `top{i}`, rank = i * 2 - 1, forms = 1 })
						table.insert(regions, { id = `Feed{i}`, group = `body{i}`, rank = i * 2, forms = 1 })
					end
					local names: { string } = {}
					for i = 1, lanes do
						table.insert(names, laneNames[i])
					end
					local decl: any = {
						groups = groups,
						arrangements = { { name = "m", lanes = { names } } },
						regions = regions,
					}
					local sizes: { [string]: { w: number, h: number } } = {}
					for i = 1, lanes do
						sizes[`Rounds{i}`] = { w = 80, h = 36 }
						sizes[`Feed{i}`] = { w = 120, h = 60 }
					end
					local function resolve(exclusions: { any }?): any
						local ctx: any = {
							measure = function(id: string): (number, number)
								local sz = sizes[id]
								return sz.w, sz.h
							end,
						}
						ctx.exclusions = exclusions
						return composition.dump(composition.resolve(decl, { w = 900, h = 500 }, ctx))
					end
					local base = resolve(nil)
					local cell = `lanes={lanes} place={tostring(place)} sizing={sizing}`
					-- a 1x1 rect far past the composition's own box
					if ser(base) ~= ser(resolve({ { x = 5000, y = 5000, w = 1, h = 1 } })) then
						table.insert(mismatches, `{cell}: far-away 1x1 rect moved the solve`)
					end
					-- a real rect that shares no x range with any lane's content
					if ser(base) ~= ser(resolve({ { x = 1200, y = 0, w = 300, h = 80 } })) then
						table.insert(mismatches, `{cell}: a non-intersecting chrome row moved the solve`)
					end
				end
			end
		end
		expect(`invariance mismatches: [{table.concat(mismatches, "; ")}]`).toBe("invariance mismatches: []")
		-- ...AND THE MATRIX IS NOT EMPTY, which is the failure mode this whole round
		-- is about: 3 lane counts x 5 places x 2 sizings
		expect(`cells swept: {3 * #PLACES * #SIZINGS}`).toBe("cells swept: 30")
	end)

	it("ADDITIVITY: a lane that gave way NOTHING places exactly as it always did", function()
		--[[ THE CONTROL FOR THE FIX ITSELF. With no exclusion the inset is 0, so the
			new operand IS the old one and every composition in the library places byte
			for byte where it did. The trivial-rect arm is the one FIX-4 measured as the
			discriminator (a far-away 1x1 rect excludes nothing and produced no
			overflow), kept as a case so the fix cannot be confused with "exclusions are
			ignored now". ]]
		local none = bottomResolve({ w = 1716, h = 871 })
		local trivial = bottomResolve({ w = 1716, h = 871 }, { { x = 1700, y = 800, w = 1, h = 1 } })
		expect(composition.dump(trivial)).toEqual(composition.dump(none))
		expect(none.regionById.Feed.rect.y + none.regionById.Feed.rect.h).toBe(871)
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
					UI.Box({
						id = id .. "Body",
						width = { type = "fixed", px = w },
						height = { type = "fixed", px = 36 },
					}),
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

	it("...and the bottom-anchored zone lands INSIDE the composition, on a phone (ADR-0056)", function()
		--[[ THE DIRECTOR'S `overlap.png`, end to end. The two cases above drive the
			pure decision and the top of the lane; this one drives the whole mounted
			path at a phone viewport with a bottom-anchored zone, which is the shape
			that was painting off the bottom of the screen. The Composition fills the
			Screen, so the assertion is the one a player can check: the feed's bottom
			edge is inside the surface that is supposed to contain it. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 512 })
		local function zone(id: string, group: string, rank: number, h: number): any
			return UI.Region({
				id = id,
				group = group,
				rank = rank,
				children = {
					UI.Box({
						id = id .. "Body",
						width = { type = "fixed", px = 120 },
						height = { type = "fixed", px = h },
					}),
				},
			})
		end
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.Composition({
						id = "H",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						groups = composition.HUD_GROUPS,
						arrangements = { composition.HUD },
						exclusions = { { x = 0, y = 0, w = 320, h = 44 } },
						children = { zone("Rounds", "topLeft", 1, 36), zone("Feed", "bottomLeft", 2, 60) },
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local hud = adapter.node("/S/H").rect
		local feed = adapter.node("/S/H/Feed").rect
		expect(adapter.node("/S/H/Rounds").rect.y).toBe(44)
		expect(feed.y + feed.h).toBe(hud.y + hud.h)
	end)
end)
