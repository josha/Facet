--!strict
local t = require("./lib/testkit")
local FocusBeam = require("../src/ui/focus_beam")

local function r(x: number, y: number, w: number, h: number)
	return { x = x, y = y, width = w, height = h }
end

t.describe("the beam neighbour", function()
	t.it("prefers an in-beam candidate by gap, even when an out-of-beam one is nearer", function()
		local from = r(300, 600, 600, 44)
		local candidates = { r(100, 520, 44, 44), r(500, 200, 300, 44) }
		t.expect(FocusBeam.neighbor(from, candidates, "up")).toBe(2)
	end)
	t.it("ranks in-beam candidates by leading-edge gap before centre offset (M2 with control frames)", function()
		local boost = r(17, 700, 687, 44)
		local candidates = { r(71, 272, 633, 44), r(164, 402, 392, 44), r(17, 480, 44, 190) }
		t.expect(FocusBeam.neighbor(boost, candidates, "up")).toBe(3)
	end)
	t.it("falls back to the half-plane and ignores candidates behind or overlapping", function()
		local from = r(100, 100, 100, 44)
		t.expect(FocusBeam.neighbor(from, { r(400, 400, 50, 50) }, "down")).toBe(1)
		t.expect(FocusBeam.neighbor(from, { r(100, 0, 100, 44) }, "down")).toBe(nil)
		t.expect(FocusBeam.neighbor(from, { r(120, 110, 20, 20) }, "down")).toBe(nil)
	end)
	t.it("works on every axis", function()
		local from = r(100, 100, 100, 100)
		local candidates = { r(300, 120, 50, 50), r(-100, 120, 50, 50), r(120, 300, 50, 50), r(120, -100, 50, 50) }
		t.expect(FocusBeam.neighbor(from, candidates, "right")).toBe(1)
		t.expect(FocusBeam.neighbor(from, candidates, "left")).toBe(2)
		t.expect(FocusBeam.neighbor(from, candidates, "down")).toBe(3)
		t.expect(FocusBeam.neighbor(from, candidates, "up")).toBe(4)
	end)
end)

return nil
