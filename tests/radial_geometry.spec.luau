--!strict
local t = require("./lib/testkit")
local g = require("../src/controls/radial_geometry")
local it, expect = t.it, t.expect
t.describe("radial geometry", function()
	it("radial sectors exclude the hole, preserve compass gaps, and bound overshoot", function()
		local items = { { id = "up", slot = "N" }, { id = "right", slot = "E" }, { id = "left", slot = "W" } }
		local sectors = g.sectors(items, 0, 360, "compass", 60, 120)
		expect(g.hit(sectors, 0, 0, "wedges")).toBe(nil)
		expect(g.hit(sectors, 0, -90, "wedges").id).toBe("up")
		expect(g.hit(sectors, 64, -64, "wedges")).toBe(nil)
		expect(g.hit(sectors, 0, -140, "wedges")).toBe(nil)
		expect(g.hit(sectors, 0, -140, "wedges", 32).id).toBe("up")
		expect(g.hit(sectors, 0, -180, "wedges", 32)).toBe(nil)
	end)
	it("all corner arcs face inward without rotating authored compass directions", function()
		local expected = { ["top-left"] = 90, ["top-right"] = 180, ["bottom-right"] = 270, ["bottom-left"] = 0 }
		for corner, angle in expected do
			local start, sweep = g.arc(corner)
			expect(start).toBe(angle)
			expect(sweep).toBe(90)
		end
	end)
	it("direct circular buttons reject rectangular corners", function()
		local sectors = g.sectors({ { id = "a" } }, 0, 360, "even", 60, 120)
		expect(g.hit(sectors, 29, -61, "buttons")).toBe(nil)
		expect(g.hit(sectors, 0, -90, "buttons").id).toBe("a")
	end)
	it("paint seams have the same pixel width at both edges of thick and slim rings", function()
		for _, band in { 44, 62, 96 } do
			local sectors = g.sectors({ { id = "a" }, { id = "b" }, { id = "c" } }, 0, 360, "even", 82, 82 + band)
			local pa, pb = g.paint(sectors[1]), g.paint(sectors[2])
			local a, b = pa.points[#pa.points], pb.points[1]
			local ax, ay, bx, by = a.x * pa.w + pa.x, a.y * pa.h + pa.y, b.x * pb.w + pb.x, b.y * pb.h + pb.y
			local tx, ty = a.outX * pa.w, a.outY * pa.h
			local length = math.sqrt(tx * tx + ty * ty)
			tx, ty = tx / length, ty / length
			local ux, uy = b.outX * pb.w, b.outY * pb.h
			local otherLength = math.sqrt(ux * ux + uy * uy)
			ux, uy = ux / otherLength, uy / otherLength
			for _, edge in { -1, 1 } do
				local x1, y1 = ax - ty * band / 2 * edge, ay + tx * band / 2 * edge
				local x2, y2 = bx - uy * band / 2 * edge, by + ux * band / 2 * edge
				expect(math.abs(math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) - 2) < 0.001).toBe(true)
			end
		end
	end)
	it("short arc outlines close both end caps with straight tangents", function()
		local s = g.sectors({ { id = "a" } }, 0, 90, "even", 82, 144)[1]
		local p = g.paint(g.fitContent(s, 20, 22, 4, "both"))
		local outline = p.outline
		expect(type(outline)).toBe("table")
		local n = #outline / 2
		expect(outline[n].outX).toBe(0)
		expect(outline[n].outY).toBe(0)
		expect(outline[n + 1].inX).toBe(0)
		expect(outline[1].inX).toBe(0)
		expect(outline[#outline].outX).toBe(0)
		local dx = (outline[n].x - outline[n + 1].x) * p.w
		local dy = (outline[n].y - outline[n + 1].y) * p.h
		expect(math.sqrt(dx * dx + dy * dy) > 20).toBe(true)
	end)
	it("content-fitted paint encloses upright icons at every compass direction", function()
		local items = {}
		for i = 1, 8 do
			table.insert(items, { id = tostring(i) })
		end
		for _, s in g.sectors(items, 0, 360, "even", 82, 143.6) do
			local p = g.fitContent(s, 20, 22, 4, "both")
			expect(p.span < s.span).toBe(true)
			expect(p.outer - p.inner < s.outer - s.inner).toBe(true)
			for _, dx in { -10, 10 } do
				for _, dy in { -11, 11 } do
					local x, y = s.x + dx, s.y + dy
					local radius = math.sqrt(x * x + y * y)
					expect(radius >= p.inner and radius <= p.outer).toBe(true)
					expect(math.abs(g.delta(math.deg(math.atan2(x, -y)), p.angle)) < p.span / 2).toBe(true)
				end
			end
		end
	end)
	it("conflicting compass assignments are rejected", function()
		local ok = pcall(function()
			g.sectors({ { id = "a", slot = "N" }, { id = "b", slot = "N" } }, 0, 360, "compass", 60, 120)
		end)
		expect(ok).toBe(false)
	end)
end)
