--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")
local Vector2 = require("@lune/roblox").Vector2

local FRAME = 1 / 60

local function sheet(extra: { [string]: any }?, options: any?): any
	local detent = Compose.cell("medium")
	local w = overlay.new(function(UI, Host)
		local spec: any = {
			isPresented = Compose.cell(true),
			detent = detent,
			title = "Race details",
			content = function()
				return Host.TextLabel "Copy" { Text = "Body" }
			end,
		}
		for key, value in extra or {} do
			spec[key] = value
		end
		return UI.Sheet "Sheet"(spec)
	end, options)
	w.detent = detent
	local modal = w.find("Modal")
	modal.AbsoluteSize = (options and options.room) or Vector2.new(800, 600)
	w.advance(1 / 300, 2)
	w.advance(0.5, 10)
	return w
end

t.describe("settle: the sheet", function()
	t.it("a programmatic detent change eases in and out instead of moving at constant speed", function()
		local w = sheet()
		local panel = w.find("SheetPanel")
		local start = panel.Size.Y.Offset
		w.detent:set("large")
		local heights = { start }
		for _ = 1, 30 do
			w.advance(FRAME)
			table.insert(heights, panel.Size.Y.Offset)
		end
		local first, middle = heights[2] - heights[1], heights[8] - heights[7]
		t.expect(first < middle).toBe(true)
		t.expect(heights[#heights]).toBe(heights[#heights - 1])
		w.stop()
	end)

	t.it("a side pull released short springs back carrying the release velocity", function()
		local w = sheet({ placement = "side" }, { room = Vector2.new(1200, 800) })
		local panel = w.find("SheetPanel")
		local drag = w.find("UIDragDetector")
		drag.DragStart.fire(w.Vector2.new(100, 300))
		w.tick(0.05)
		drag.DragContinue.fire(w.Vector2.new(110, 300))
		w.tick(0.05)
		drag.DragContinue.fire(w.Vector2.new(140, 300))
		t.expect(panel.Position.X.Offset).toBe(40)
		drag.DragEnd.fire()
		w.advance(FRAME)
		t.expect(panel.Position.X.Offset > 40).toBe(true)
		w.advance(1, 60)
		t.expect(panel.Position.X.Offset).toBe(0)
		w.stop()
	end)

	t.it("reduced motion lands a detent change at once", function()
		local w = sheet(nil, { reducedMotion = true })
		local panel = w.find("SheetPanel")
		w.detent:set("large")
		local goal = panel.Size.Y.Offset
		w.advance(FRAME)
		t.expect(panel.Size.Y.Offset).toBe(goal)
		w.stop()
	end)
end)
