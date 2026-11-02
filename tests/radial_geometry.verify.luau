--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	local g = require("../src/ui/nav_radial_geometry")
	local Radial = require("../src/ui/radial_types")
	local function sectors(
		items: { Radial.RadialItem<string> },
		start: number,
		sweep: number,
		distribution: Radial.Distribution,
		inner: number,
		outer: number
	): { Radial.Sector<string> }
		return g.sectors<<string>>(items, start, sweep, distribution, inner, outer)
	end
	local function hit(
		list: { Radial.Sector<string> },
		x: number,
		y: number,
		appearance: string,
		overshoot: number?,
		previous: Radial.Sector<string>?
	): Radial.Sector<string>?
		return g.hit<<string>>(list, x, y, appearance, overshoot, previous)
	end
	local function item(value: Radial.RadialAction<string>): Radial.RadialItem<string>
		return value
	end
	local function change(shape: Radial.SectorShape, field: string, delta: number)
		if field == "x" then
			shape.x += delta
		elseif field == "y" then
			shape.y += delta
		elseif field == "inner" then
			shape.inner += delta
		elseif field == "outer" then
			shape.outer += delta
		elseif field == "angle" then
			shape.angle += delta
		else
			shape.span += delta
		end
	end
	local expect = Verify.expect
	describe("radial geometry", function()
		it("label fits follow changed shapes and requested heights", {
			id = "radial_geometry::radial geometry::label fits follow changed shapes and requested heights",
			run = function()
				local shape: Radial.SectorShape =
					{ x = 0, y = -100, inner = 60, outer = 150, angle = 0, span = 90, size = 40 }
				local fieldNames: { "x" | "y" | "inner" | "outer" | "angle" | "span" } =
					{ "x", "y", "inner", "outer", "angle", "span" }
				local initial = g.labelBounds(shape, 40)
				expect(g.labelBounds(shape, 40)):toEqual(initial)
				for _, field in fieldNames do
					change(shape, field, 7)
					expect(g.labelBounds(shape, 40)):toEqual(g.labelBounds(table.clone(shape), 40))
					change(shape, field, -7)
				end
				expect(g.labelBounds(shape, 20)):toEqual(g.labelBounds(table.clone(shape), 20))
				expect(g.labelBounds(shape, 40)):toEqual(initial)
			end,
		})
		it("label bounds stay inside rotated narrow and wide sectors", {
			id = "radial_geometry::radial geometry::label bounds stay inside rotated narrow and wide sectors",
			run = function()
				for _, span in { 15, 45, 90, 180, 270, 360 } do
					for angle = -180, 540, 17 do
						for _, inner in { 0, 60, 110 } do
							local shape: Radial.SectorShape = {
								x = math.sin(math.rad(angle)) * (inner + 150) / 2,
								y = -math.cos(math.rad(angle)) * (inner + 150) / 2,
								inner = inner,
								outer = 150,
								angle = angle,
								span = span,
								size = 150 - inner,
							}
							local box = g.labelBounds(shape, 40)
							expect(box.w >= 0 and box.w <= 160 and box.h >= 0 and box.h <= 40):toBe(true)
							if box.w > 0 and box.h > 0 then
								local nearX = math.max(0, math.abs(shape.x) - box.w / 2 - 3)
								local nearY = math.max(0, math.abs(shape.y) - box.h / 2 - 3)
								expect(nearX * nearX + nearY * nearY >= inner * inner - 1e-8):toBe(true)
								for _, dx in { -box.w / 2 - 3, box.w / 2 + 3 } do
									for _, dy in { -box.h / 2 - 3, box.h / 2 + 3 } do
										local x, y = shape.x + dx, shape.y + dy
										expect(x * x + y * y <= 150 * 150 + 1e-8):toBe(true)
										expect(
											math.abs(g.delta(math.deg(math.atan2(x, -y)), angle)) <= span / 2 - 2 + 1e-8
										):toBe(true)
									end
								end
							end
						end
					end
				end
			end,
		})
		it("radial sectors exclude the hole, preserve compass gaps, and bound overshoot", {
			id = "radial_geometry::radial geometry::radial sectors exclude the hole, preserve compass gaps, and bound overshoot",
			run = function()
				local items: { Radial.RadialItem<string> } = {
					{ id = "up", label = "up", slot = "N" },
					{ id = "right", label = "right", slot = "E" },
					{ id = "left", label = "left", slot = "W" },
				}
				local sectors = sectors(items, 0, 360, "compass", 60, 120)
				expect((hit(sectors, 0, 0, "wedges"))):toBe(nil)
				expect(assert(hit(sectors, 0, -90, "wedges")).id):toBe("up")
				expect((hit(sectors, 64, -64, "wedges"))):toBe(nil)
				expect((hit(sectors, 0, -140, "wedges"))):toBe(nil)
				expect(assert(hit(sectors, 0, -140, "wedges", 32)).id):toBe("up")
				expect((hit(sectors, 0, -180, "wedges", 32))):toBe(nil)
			end,
		})
		it("all corner arcs face inward without rotating authored compass directions", {
			id = "radial_geometry::radial geometry::all corner arcs face inward without rotating authored compass directions",
			run = function()
				local expected: { [string]: number } =
					{ ["top-left"] = 90, ["top-right"] = 180, ["bottom-right"] = 270, ["bottom-left"] = 0 }
				for corner, angle in expected do
					local start, sweep = g.arc(corner)
					expect(start):toBe(angle)
					expect(sweep):toBe(90)
				end
			end,
		})
		it("direct circular buttons reject rectangular corners", {
			id = "radial_geometry::radial geometry::direct circular buttons reject rectangular corners",
			run = function()
				local sectors = sectors({ item({ id = "a", label = "a" }) }, 0, 360, "even", 60, 120)
				expect((hit(sectors, 29, -61, "buttons"))):toBe(nil)
				expect(assert(hit(sectors, 0, -90, "buttons")).id):toBe("a")
			end,
		})
		it("paint seams have the same pixel width at both edges of thick and slim rings", {
			id = "radial_geometry::radial geometry::paint seams have the same pixel width at both edges of thick and slim rings",
			run = function()
				for _, band in { 44, 62, 96 } do
					local sectors = sectors({
						item({ id = "a", label = "a" }),
						item({ id = "b", label = "b" }),
						item({ id = "c", label = "c" }),
					}, 0, 360, "even", 82, 82 + band)
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
						expect(math.abs(math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) - 2) < 0.001):toBe(true)
					end
				end
			end,
		})
		it("short arc stroke ends preserve the radial gap and tangent", {
			id = "radial_geometry::radial geometry::short arc stroke ends preserve the radial gap and tangent",
			run = function()
				local s = sectors({ item({ id = "a", label = "a" }) }, 0, 90, "even", 82, 144)[1]
				local fitted = g.fitContent(s, 20, 22, 4, "both")
				local p = g.paint(fitted)
				local radius = (fitted.inner + fitted.outer) / 2
				for _, endpoint in { { 1, -1 }, { #p.points, 1 } } do
					local point, edge = p.points[endpoint[1]], endpoint[2]
					local angle = math.rad(fitted.angle + edge * fitted.span / 2)
					local x, y = point.x * p.w + p.x, point.y * p.h + p.y
					local radial = x * math.sin(angle) - y * math.cos(angle)
					local gap = x * math.cos(angle) + y * math.sin(angle)
					expect(math.abs(radial - radius) < 1e-6):toBe(true)
					expect(math.abs(gap + edge * (fitted.gap or 2) / 2) < 1e-6):toBe(true)
					local tangentX, tangentY = point.outX * p.w, point.outY * p.h
					expect(math.abs(tangentX * math.sin(angle) - tangentY * math.cos(angle)) < 1e-6):toBe(true)
					expect(tangentX * math.cos(angle) + tangentY * math.sin(angle) > 0):toBe(true)
				end
			end,
		})
		it("content-fitted paint encloses upright icons at every compass direction", {
			id = "radial_geometry::radial geometry::content-fitted paint encloses upright icons at every compass direction",
			run = function()
				local items: { Radial.RadialItem<string> } = {}
				for i = 1, 8 do
					table.insert(items, item({ id = tostring(i), label = tostring(i) }))
				end
				for _, s in sectors(items, 0, 360, "even", 82, 143.6) do
					local p = g.fitContent(s, 20, 22, 4, "both")
					expect(p.span < s.span):toBe(true)
					expect(p.outer - p.inner < s.outer - s.inner):toBe(true)
					for _, dx in { -10, 10 } do
						for _, dy in { -11, 11 } do
							local x, y = s.x + dx, s.y + dy
							local radius = math.sqrt(x * x + y * y)
							expect(radius >= p.inner and radius <= p.outer):toBe(true)
							expect(math.abs(g.delta(math.deg(math.atan2(x, -y)), p.angle)) < p.span / 2):toBe(true)
						end
					end
				end
			end,
		})
		it("conflicting compass assignments are rejected", {
			id = "radial_geometry::radial geometry::conflicting compass assignments are rejected",
			run = function()
				local ok = pcall(function()
					sectors({
						{ id = "a", label = "a", slot = "N" },
						{ id = "b", label = "b", slot = "N" },
					}, 0, 360, "compass", 60, 120)
				end)
				expect(ok):toBe(false)
			end,
		})
	end)
end
