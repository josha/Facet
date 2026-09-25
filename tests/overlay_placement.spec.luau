--!strict
local t = require("./lib/testkit")
local placement = require("../src/ui/overlay_placement")

local SAFE = { x = 0, y = 0, w = 800, h = 600 }

t.describe("anchored placement", function()
	t.it("every edge and align pair moves by exactly the signed offset, and absent equals 0", function()
		local source = { x = 300, y = 250, w = 60, h = 40 }
		for _, edge in { "top", "bottom", "leading", "trailing" } do
			for _, align in { "start", "center", "end" } do
				local base = placement.solve({
					source = source,
					size = { w = 100, h = 60 },
					safe = SAFE,
					edge = edge,
					align = align,
				})
				local zero = placement.solve({
					source = source,
					size = { w = 100, h = 60 },
					safe = SAFE,
					edge = edge,
					align = align,
					crossOffset = 0,
				})
				t.expect(zero.x).toBe(base.x)
				t.expect(zero.y).toBe(base.y)
				for _, offset in { 12, -12 } do
					local moved = placement.solve({
						source = source,
						size = { w = 100, h = 60 },
						safe = SAFE,
						edge = edge,
						align = align,
						crossOffset = offset,
					})
					local vertical = edge == "top" or edge == "bottom"
					t.expect(`{edge}/{align}/{offset}: {if vertical then moved.x - base.x else moved.y - base.y}`)
						.toBe(`{edge}/{align}/{offset}: {offset}`)
					t.expect(if vertical then moved.y else moved.x).toBe(if vertical then base.y else base.x)
				end
			end
		end
	end)

	t.it("a flip changes the edge only: the alignment and the offset do not flip", function()
		local source = { x = 300, y = 560, w = 60, h = 30 }
		local result = placement.solve({
			source = source,
			size = { w = 100, h = 80 },
			safe = SAFE,
			edge = "bottom",
			align = "start",
			crossOffset = 10,
		})
		t.expect(result.edge).toBe("top")
		t.expect(result.flipped).toBe(true)
		t.expect(result.x).toBe(310)
		t.expect(result.y).toBe(560 - 80)
	end)

	t.it("a surface that fits neither above nor below hangs beside its source, never over it", function()
		local source = { x = 200, y = 250, w = 60, h = 100 }
		local result = placement.solve({
			source = source,
			size = { w = 180, h = 300 },
			safe = SAFE,
			edge = "bottom",
			gap = 8,
		})
		t.expect(result.edge).toBe("right")
		t.expect(result.x).toBe(268)
		t.expect(result.x >= source.x + source.w).toBe(true)
		t.expect(result.fits).toBe(true)
		local left = placement.solve({
			source = { x = 600, y = 250, w = 60, h = 100 },
			size = { w = 180, h = 300 },
			safe = SAFE,
			edge = "bottom",
			gap = 8,
		})
		t.expect(left.edge).toBe("left")
		t.expect(left.x + left.w <= 600).toBe(true)
		local nowhere = placement.solve({
			source = { x = 300, y = 250, w = 200, h = 100 },
			size = { w = 400, h = 300 },
			safe = SAFE,
			edge = "bottom",
			gap = 8,
		})
		t.expect(nowhere.edge).toBe("bottom")
		t.expect(nowhere.fits).toBe(true)
		t.expect(nowhere.y).toBe(300)
	end)

	t.it("the safe clamp still wins over the offset, and reports the shift it took", function()
		local result = placement.solve({
			source = { x = 740, y = 100, w = 40, h = 40 },
			size = { w = 100, h = 60 },
			safe = SAFE,
			edge = "bottom",
			align = "start",
			crossOffset = 30,
		})
		t.expect(result.x).toBe(700)
		t.expect(result.shift).toBe(700 - 770)
	end)

	t.it("a non-finite or non-number offset is refused by name", function()
		for _, bad in { 0 / 0, math.huge, -math.huge, "12" :: any } do
			local ok, failure = pcall(placement.solve, {
				source = { x = 0, y = 0, w = 10, h = 10 },
				size = { w = 10, h = 10 },
				safe = SAFE,
				crossOffset = bad,
			})
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(failure), "crossOffset", 1, true) ~= nil).toBe(true)
		end
	end)

	t.it("growing safe insets pull a surface inside the new box", function()
		local request = {
			source = { x = 700, y = 100, w = 40, h = 40 },
			size = { w = 200, h = 60 },
			safe = SAFE,
			edge = "bottom",
		}
		t.expect(placement.solve(request).x + 200 <= 800).toBe(true)
		request.safe = { x = 0, y = 0, w = 500, h = 600 }
		local narrowed = placement.solve(request)
		t.expect(narrowed.x + narrowed.w <= 500).toBe(true)
	end)

	t.it("the tail sits on the source centre and is suppressed when the shift carries it off the source", function()
		local centred = placement.solve({
			source = { x = 300, y = 100, w = 100, h = 40 },
			size = { w = 160, h = 80 },
			safe = SAFE,
			edge = "bottom",
			tail = 10,
			tailInset = 8,
		})
		t.expect(centred.tailX).toBe(350)
		t.expect(centred.tailY).toBe(140)
		t.expect(centred.tailSuppressed).toBe(false)
		local carried = placement.solve({
			source = { x = 790, y = 100, w = 10, h = 40 },
			size = { w = 160, h = 80 },
			safe = { x = 0, y = 0, w = 760, h = 600 },
			edge = "bottom",
			tail = 10,
			tailInset = 8,
		})
		t.expect(carried.tailSuppressed).toBe(true)
	end)
end)
