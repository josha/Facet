--!strict
-- Facet.layout.transformFootprint (framework-gaps-phase2 gap 33, audit-marked
-- "teaches-wrong 12"): the reserved-box formula for a scaled/rotated node,
-- published so a consumer stops hand-transcribing the trigonometry
-- `examples/gallery/scenarios/nested_compositing.luau` used to carry under a
-- comment naming this exact function as the owed API.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local transform_footprint = require("../src/layout/transform_footprint")

describe("Facet.layout.transformFootprint (gap 33)", function()
	it("is reachable on the public Facet table", function()
		expect(type(Facet.layout)).toBe("table")
		expect(type(Facet.layout.transformFootprint)).toBe("function")
	end)

	it("reproduces the exact device defect measurement (api.md:325)", function()
		-- a 100x70 box at scale 1.5 / rotation 30 painted 182.40 x 165.93
		local w, h = transform_footprint.transformFootprint(100, 70, 1.5, 30)
		expect(w).toBe(183) -- ceil(182.40...)
		expect(h).toBe(166) -- ceil(165.93...)
	end)

	it("an unscaled, unrotated box reserves exactly its own size", function()
		local w, h = transform_footprint.transformFootprint(100, 70, 1, 0)
		expect(w).toBe(100)
		expect(h).toBe(70)
	end)

	it("a 90-degree rotation swaps width and height", function()
		local w, h = transform_footprint.transformFootprint(100, 70, 1, 90)
		expect(w).toBe(70)
		expect(h).toBe(100)
	end)

	it("scale alone (no rotation) scales both axes directly", function()
		local w, h = transform_footprint.transformFootprint(100, 70, 2, 0)
		expect(w).toBe(200)
		expect(h).toBe(140)
	end)

	it("always rounds UP, never clipping a fraction of a pixel off an edge", function()
		-- a scale chosen to NOT land on an integer: 100 * 1.001 = 100.1
		local w, h = transform_footprint.transformFootprint(100, 100, 1.001, 0)
		expect(w).toBe(101)
		expect(h).toBe(101)
	end)
end)
