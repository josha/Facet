--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	local placement = require("../src/ui/overlay_placement")

	local SAFE = { x = 0, y = 0, w = 800, h = 600 }

	verifyHarness:suite("anchored placement", function()
		verifyHarness:case("keeps a touch label outside the finger and prefers a side at the top edge", {
			id = "overlay_placement::anchored placement::keeps a touch label outside the finger and prefers a side at the top edge",
			run = function()
				for _, point in { { x = 200, y = 300 }, { x = 20, y = 20 }, { x = 370, y = 20 } } do
					local box = placement.touch(point, { w = 120, h = 48 }, { x = 8, y = 8, w = 374, h = 744 }, 52)
					Verify.expect(box.fits):toBe(true)
					Verify.expect(
						box.y + box.h <= point.y - 52 or box.x >= point.x + 52 or box.x + box.w <= point.x - 52
					)
						:toBe(true)
				end
			end,
		})

		verifyHarness:case("every edge and align pair moves by exactly the signed offset, and absent equals 0", {
			id = "overlay_placement::anchored placement::every edge and align pair moves by exactly the signed offset, and absent equals 0",
			run = function()
				local source = { x = 300, y = 250, w = 60, h = 40 }
				for _, edge in
					{ "top", "bottom", "leading", "trailing" } :: { "bottom" | "leading" | "top" | "trailing" }
				do
					for _, align in { "start", "center", "end" } do
						local base = placement.solve({
							source = source,
							size = { w = 100, h = 60 },
							safe = SAFE,
							edge = edge :: "bottom" | "leading" | "top" | "trailing",
							align = align,
						})
						local zero = placement.solve({
							source = source,
							size = { w = 100, h = 60 },
							safe = SAFE,
							edge = edge :: "bottom" | "leading" | "top" | "trailing",
							align = align,
							crossOffset = 0,
						})
						Verify.expect(zero.x):toBe(base.x)
						Verify.expect(zero.y):toBe(base.y)
						for _, offset in { 12, -12 } do
							local moved = placement.solve({
								source = source,
								size = { w = 100, h = 60 },
								safe = SAFE,
								edge = edge :: "bottom" | "leading" | "top" | "trailing",
								align = align,
								crossOffset = offset,
							})
							local vertical = edge == "top" or edge == "bottom"
							Verify.expect(
								`{edge}/{align}/{offset}: {if vertical then moved.x - base.x else moved.y - base.y}`
							)
								:toBe(`{edge}/{align}/{offset}: {offset}`)
							Verify.expect(if vertical then moved.y else moved.x)
								:toBe(if vertical then base.y else base.x)
						end
					end
				end
			end,
		})

		verifyHarness:case("a flip changes the edge only: the alignment and the offset do not flip", {
			id = "overlay_placement::anchored placement::a flip changes the edge only: the alignment and the offset do not flip",
			run = function()
				local source = { x = 300, y = 560, w = 60, h = 30 }
				local result = placement.solve({
					source = source,
					size = { w = 100, h = 80 },
					safe = SAFE,
					edge = "bottom" :: "bottom",
					align = "start" :: "start",
					crossOffset = 10,
				})
				Verify.expect(result.edge):toBe("top")
				Verify.expect(result.flipped):toBe(true)
				Verify.expect(result.x):toBe(310)
				Verify.expect(result.y):toBe(560 - 80)
			end,
		})

		verifyHarness:case("a surface that fits neither above nor below hangs beside its source, never over it", {
			id = "overlay_placement::anchored placement::a surface that fits neither above nor below hangs beside its source, never over it",
			run = function()
				local source = { x = 200, y = 250, w = 60, h = 100 }
				local result = placement.solve({
					source = source,
					size = { w = 180, h = 300 },
					safe = SAFE,
					edge = "bottom" :: "bottom",
					gap = 8,
				})
				Verify.expect(result.edge):toBe("right")
				Verify.expect(result.x):toBe(268)
				Verify.expect(result.x >= source.x + source.w):toBe(true)
				Verify.expect(result.fits):toBe(true)
				local left = placement.solve({
					source = { x = 600, y = 250, w = 60, h = 100 },
					size = { w = 180, h = 300 },
					safe = SAFE,
					edge = "bottom" :: "bottom",
					gap = 8,
				})
				Verify.expect(left.edge):toBe("left")
				Verify.expect(left.x + left.w <= 600):toBe(true)
				local nowhere = placement.solve({
					source = { x = 300, y = 250, w = 200, h = 100 },
					size = { w = 400, h = 300 },
					safe = SAFE,
					edge = "bottom" :: "bottom",
					gap = 8,
				})
				Verify.expect(nowhere.edge):toBe("bottom")
				Verify.expect(nowhere.fits):toBe(true)
				Verify.expect(nowhere.y):toBe(300)
			end,
		})

		verifyHarness:case("the safe clamp still wins over the offset, and reports the shift it took", {
			id = "overlay_placement::anchored placement::the safe clamp still wins over the offset, and reports the shift it took",
			run = function()
				local result = placement.solve({
					source = { x = 740, y = 100, w = 40, h = 40 },
					size = { w = 100, h = 60 },
					safe = SAFE,
					edge = "bottom" :: "bottom",
					align = "start" :: "start",
					crossOffset = 30,
				})
				Verify.expect(result.x):toBe(700)
				Verify.expect(result.shift):toBe(700 - 770)
			end,
		})

		verifyHarness:case("a non-finite or non-number offset is refused by name", {
			id = "overlay_placement::anchored placement::a non-finite or non-number offset is refused by name",
			run = function()
				for _, bad in { 0 / 0, math.huge, -math.huge, "12" :: any } do
					local ok, failure = pcall(placement.solve, {
						source = { x = 0, y = 0, w = 10, h = 10 },
						size = { w = 10, h = 10 },
						safe = SAFE,
						crossOffset = bad,
					})
					Verify.expect(ok):toBe(false)
					Verify.expect(string.find(tostring(failure), "crossOffset", 1, true) ~= nil):toBe(true)
				end
			end,
		})

		verifyHarness:case("growing safe insets pull a surface inside the new box", {
			id = "overlay_placement::anchored placement::growing safe insets pull a surface inside the new box",
			run = function()
				local request = {
					source = { x = 700, y = 100, w = 40, h = 40 },
					size = { w = 200, h = 60 },
					safe = SAFE,
					edge = "bottom" :: "bottom",
				}
				Verify.expect(placement.solve(request).x + 200 <= 800):toBe(true)
				request.safe = { x = 0, y = 0, w = 500, h = 600 }
				local narrowed = placement.solve(request)
				Verify.expect(narrowed.x + narrowed.w <= 500):toBe(true)
			end,
		})

		verifyHarness:case(
			"the tail sits on the source centre and is suppressed when the shift carries it off the source",
			{
				id = "overlay_placement::anchored placement::the tail sits on the source centre and is suppressed when the shift carries it off the source",
				run = function()
					local centred = placement.solve({
						source = { x = 300, y = 100, w = 100, h = 40 },
						size = { w = 160, h = 80 },
						safe = SAFE,
						edge = "bottom" :: "bottom",
						tail = 10,
						tailInset = 8,
					})
					Verify.expect(centred.tailX):toBe(350)
					Verify.expect(centred.tailY):toBe(140)
					Verify.expect(centred.tailSuppressed):toBe(false)
					local carried = placement.solve({
						source = { x = 790, y = 100, w = 10, h = 40 },
						size = { w = 160, h = 80 },
						safe = { x = 0, y = 0, w = 760, h = 600 },
						edge = "bottom" :: "bottom",
						tail = 10,
						tailInset = 8,
					})
					Verify.expect(carried.tailSuppressed):toBe(true)
				end,
			}
		)

		verifyHarness:case("a side panel too short for the tail's corner insets keeps its tail at its middle", {
			id = "overlay_placement::anchored placement::a side panel too short for the tail's corner insets keeps its tail at its middle",
			run = function()
				local short = placement.solve({
					source = { x = 300, y = 300, w = 44, h = 44 },
					size = { w = 200, h = 30 },
					safe = SAFE,
					edge = "trailing" :: "trailing",
					tail = 16 * math.sqrt(2),
					tailInset = 8,
				})
				Verify.expect(short.tailSuppressed):toBe(false)
				Verify.expect(short.tailX):toBe(short.x)
				Verify.expect(short.tailY):toBe(short.y + 15)
			end,
		})
	end)
end
