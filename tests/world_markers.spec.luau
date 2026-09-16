--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local rect = require("../src/rect")

t.describe("world marker layout", function()
	t.it("clamps offscreen targets to an edge and reports their direction", function()
		local bounds = { x = 10, y = 20, w = 300, h = 200 }
		local rows = Facet.layout.worldMarkers({
			bounds = bounds,
			markers = {
				{ id = "Goal", x = 1000, y = 120, width = 80, height = 30 },
			},
		})
		t.expect(rows[1].edge).toBe(true)
		t.expect(rows[1].visible).toBe(true)
		t.expect(rect.contains(bounds, rows[1].rect)).toBe(true)
		t.expect(math.abs(rows[1].angle - 90) < 0.001).toBe(true)
	end)
	t.it("gives priority to important markers and keeps labels out of reserved HUD space", function()
		local block = { x = 0, y = 0, w = 300, h = 70 }
		local rows = Facet.layout.worldMarkers({
			bounds = { x = 0, y = 0, w = 300, h = 200 },
			exclusions = { block },
			markers = {
				{ id = "Low", x = 150, y = 80, width = 100, height = 30, priority = 0 },
				{ id = "High", x = 150, y = 80, width = 100, height = 30, priority = 10 },
			},
		})
		t.expect(rows[1].id).toBe("High")
		t.expect(rows[1].visible).toBe(true)
		local occupied = { block }
		for _, row in rows do
			if row.visible then
				for _, other in occupied do
					t.expect(rect.overlaps(row.rect, other)).toBe(false)
				end
				table.insert(occupied, row.rect)
			end
		end
	end)
	t.it("reports occluded, crowded, and oversized markers without losing identity", function()
		local rows = Facet.layout.worldMarkers({
			bounds = { x = 0, y = 0, w = 100, h = 40 },
			gap = 0,
			markers = {
				{ id = "A", x = 50, y = 20, width = 100, height = 40 },
				{ id = "B", x = 50, y = 20, width = 100, height = 40 },
				{ id = "C", x = 50, y = 20, width = 101, height = 40 },
				{ id = "D", x = 50, y = 20, width = 10, height = 10, visible = false },
			},
		})
		t.expect(rows[1].visible).toBe(true)
		t.expect(rows[2].reason).toBe("crowded")
		t.expect(rows[3].reason).toBe("tooLarge")
		t.expect(rows[4].reason).toBe("unavailable")
	end)
	t.it("reserves the full gap around HUD exclusions", function()
		local rows = Facet.layout.worldMarkers({
			bounds = { x = 0, y = 0, w = 100, h = 160 },
			gap = 20,
			exclusions = { { x = 0, y = 0, w = 100, h = 60 } },
			markers = { { id = "A", x = 50, y = 75, width = 20, height = 10 } },
		})
		t.expect(rows[1].visible).toBe(true)
		t.expect(rows[1].rect.y - 60 >= 20).toBe(true)
	end)

	for _, input in { "Gamepad", "Keyboard", "Touch", "MouseKeyboard" } do
		t.it(input .. " can move markers without marker focus, including after resize", function()
			local w = require("./lib/world").new({
				preferredInput = input,
				reducedMotion = true,
				env = { preferredTextOffset = 14 },
			})
			local built = require("../examples/gallery/scenarios/world_markers").build({
				Facet = Facet,
				core = w.core,
				env = w.env,
				presenter = w.pres,
			})
			w.present(built.screen, built.present)
			w.settle(4)
			local path = "/WorldMarkers/Controls/Move"
			local function activate()
				if input == "Gamepad" or input == "Keyboard" then
					t.expect(w.pres.focus.focused:get()).toBe(path)
					w.press(if input == "Gamepad" then "ButtonA" else "Return")
				else
					local r = w.adapter.node(path).rect
					w.adapter.tap(path, {
						source = "pointer",
						pointer = if input == "Touch" then "touch" else "mouse",
						x = r.x + r.w / 2,
						y = r.y + r.h / 2,
					})
				end
				w.settle(4)
			end
			activate()
			t.expect(built.report().markers[1].edge).toBe(true)
			w.env:set("viewportRect", { x = 0, y = 0, w = 844, h = 390 })
			w.settle(4)
			activate()
			t.expect(built.report().markers[1].edge).toBe(false)
			w.pres.dismiss(w.handle)
			built.dispose()
		end)
	end
end)
