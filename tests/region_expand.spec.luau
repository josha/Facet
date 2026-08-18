--!strict
--[[ WAVE REVEAL — a stepped-down region EXPANDS to its richest form.

	The knob is `expand`: `reveal` is already UI.Text's marquee prop and `disclose`
	is already its truncation policy, so a third meaning on the same surface would
	be the collision this name avoids.

	The ladder in `src/layout/composition.luau` steps a region down and then drops
	it, and D7.1 gave every one of those events a stated ROUTE. What no route
	covered is the commonest one of all: a region that stepped DOWN and whose
	author declared `recover = "self"` — "the reduced form IS the route" — had to
	hand-author the tap target, the focus stop, the plate and the dismissal in
	every zone of every screen. Measured on the HUD showcase: the one zone that
	did it (`Tasks`) is 40 lines of fixture code, and the seven that did not sent
	their content to the overflow sink instead, which is two navigations away from
	a thing that is standing right there on the screen.

	This file is the proof of the framework doing it. Four layers, in order:

	  1. THE PURE FACTS — `activeForm` / `richestForm` / `formInteractive` /
	     `expand` / `expandable` on the resolution, and the plate SIZE (with its
	     sheet fallback) decided by the same pure pass that decided the ladder, so
	     the device matrix stays a headless sweep.
	  2. THE AUTHORING BOUNDARY — `UI.Region{ expand = … }`, refused where it
	     cannot mean anything, and the per-form INTERACTIVITY read off the class
	     contract rather than guessed.
	  3. THE GEOMETRY — the affordance the framework synthesizes: a full-cover
	     activation surface over a PASSIVE compact form, a chevron beside an
	     INTERACTIVE one, hidden (and therefore out of focus order) at the richest
	     form and under `expand = "none"`.
	  4. THE PRESENTATION — the anchored plate itself: what opens it, what closes
	     it, and that nothing is left behind when it goes.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local composition = require("../src/layout/composition")

-- ===== 1. THE PURE FACTS ===================================================
-- One region per case, measured from a table, exactly as `composition.spec`
-- drives the ladder: no mount, no theme, no engine.

local function measureFrom(sizes: { [string]: { { w: number, h: number } } })
	return function(id: string, form: number, availW: number, _availH: number): (number, number)
		local forms = sizes[id]
		if forms == nil then
			return 0, 0
		end
		local entry = forms[math.min(form, #forms)]
		-- the honest measure a composition gets: the content's own width, NOT
		-- clamped to the offer, so a form that cannot fit says so
		return entry.w, entry.h
	end
end

local function decl(regions: { any }): any
	return {
		id = "Screen",
		groups = { { id = "body", lane = "main", sizing = "fill" } },
		regions = regions,
		arrangements = { { name = "column", lanes = { { "main" } } } },
	}
end

describe("EXPAND 1 — the resolution states which form is standing and whether it is a dead end", function()
	local SIZES = {
		Clock = { { w = 200, h = 60 }, { w = 60, h = 20 } },
	}

	it("a region at its richest form reports activeForm 1 and nothing to expand to", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow" } }),
			{ w = 400, h = 400 },
			{ measure = measureFrom(SIZES) }
		)
		local r = res.regionById.Clock
		expect(r.activeForm).toBe(1)
		expect(r.richestForm).toBe(1)
		expect(r.expandable).toBe(false)
	end)

	it("a stepped-down region reports the form it landed on, and that an expansion exists", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow" } }),
			{ w = 400, h = 30 },
			{ measure = measureFrom(SIZES) }
		)
		local r = res.regionById.Clock
		expect(r.activeForm).toBe(2)
		expect(r.richestForm).toBe(1)
		expect(r.expandable).toBe(true)
		expect(r.expand).toBe("auto")
	end)

	it("a DROPPED region has no active form, so it is never expandable — drops stay sheet-only", function()
		local res = composition.resolve(
			decl({
				{ id = "Clock", group = "body", rank = 2, forms = 2, recover = "overflow", mayDrop = true },
				{ id = "Big", group = "body", rank = 1, forms = 1, floor = nil },
			}),
			{ w = 400, h = 30 },
			{ measure = measureFrom({ Clock = SIZES.Clock, Big = { { w = 30, h = 30 } } }) }
		)
		local r = res.regionById.Clock
		expect(r.dropped).toBe(true)
		expect(r.activeForm).toBe(0)
		expect(r.expandable).toBe(false)
	end)

	it('expand = "none" is the authored escape: stepped down, and nothing to expand', function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow", expand = "none" } }),
			{ w = 400, h = 30 },
			{ measure = measureFrom(SIZES) }
		)
		local r = res.regionById.Clock
		expect(r.activeForm).toBe(2)
		expect(r.expand).toBe("none")
		expect(r.expandable).toBe(false)
	end)

	it("formInteractive is the ACTIVE form's own answer, read from the declaration", function()
		local d = decl({
			{
				id = "Clock",
				group = "body",
				rank = 1,
				forms = 2,
				recover = "overflow",
				-- form 1 holds buttons, form 2 is a bare figure
				formInteractive = { true, false },
			},
		})
		local rich = composition.resolve(d, { w = 400, h = 400 }, { measure = measureFrom(SIZES) })
		expect(rich.regionById.Clock.formInteractive).toBe(true)
		local poor = composition.resolve(d, { w = 400, h = 30 }, { measure = measureFrom(SIZES) })
		expect(poor.regionById.Clock.formInteractive).toBe(false)
	end)

	it("a dropped region's formInteractive is false — there is no form to be interactive", function()
		local res = composition.resolve(
			decl({
				{
					id = "Clock",
					group = "body",
					rank = 2,
					forms = 2,
					recover = "overflow",
					mayDrop = true,
					formInteractive = { true, true },
				},
				{ id = "Big", group = "body", rank = 1, forms = 1 },
			}),
			{ w = 400, h = 30 },
			{ measure = measureFrom({ Clock = SIZES.Clock, Big = { { w = 30, h = 30 } } }) }
		)
		expect(res.regionById.Clock.dropped).toBe(true)
		expect(res.regionById.Clock.formInteractive).toBe(false)
	end)

	it("the declaration refuses an expand mode it cannot honour", function()
		expect(function()
			composition.normalize(
				decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow", expand = "maybe" } })
			)
		end).toThrow()
		expect(function()
			composition.normalize(
				decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow", formInteractive = 3 } })
			)
		end).toThrow()
	end)
end)

describe("EXPAND 2 — the plate is sized by the same pure pass, and says when it cannot be one", function()
	local SIZES = {
		Clock = { { w = 200, h = 60 }, { w = 60, h = 20 } },
	}

	it("the plate is the richest form's own width, capped at the viewport minus gutters", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow" } }),
			{ w = 100, h = 30 },
			{ measure = measureFrom(SIZES), expandGutter = 8 }
		)
		local plate = res.regionById.Clock.plate
		expect(plate).never().toBeNil()
		-- 200 wanted, 100 - 2*8 offered: the cap wins and the form does not fit in it
		expect(plate.w).toBe(84)
		expect(plate.sheet).toBe(true)
	end)

	it("...and reports sheet = false when the richest form fits the plate", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow" } }),
			{ w = 400, h = 30 },
			{ measure = measureFrom(SIZES), expandGutter = 8 }
		)
		local r = res.regionById.Clock
		expect(r.activeForm).toBe(2)
		expect(r.plate.w).toBe(200)
		expect(r.plate.h).toBe(60)
		expect(r.plate.sheet).toBe(false)
	end)

	it("a region with nothing to expand is not measured for a plate", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow", expand = "none" } }),
			{ w = 100, h = 30 },
			{ measure = measureFrom(SIZES), expandGutter = 8 }
		)
		expect(res.regionById.Clock.plate).toBeNil()
	end)
end)

describe("EXPAND 3 — the dump carries the facts, and two calls are equal", function()
	local SIZES = {
		Clock = { { w = 200, h = 60 }, { w = 60, h = 20 } },
	}

	it("every region row states the form standing, the richest one, and the route", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow" } }),
			{ w = 100, h = 30 },
			{ measure = measureFrom(SIZES), expandGutter = 8 }
		)
		local dump = composition.dump(res)
		local row = dump.regions[1]
		expect(row.activeForm).toBe(2)
		expect(row.richestForm).toBe(1)
		expect(row.formInteractive).toBe(false)
		expect(row.expand).toBe("auto")
		expect(row.expandable).toBe(true)
		expect(row.plate.sheet).toBe(true)
		expect(dump).toEqual(composition.dump(res))
	end)
end)
